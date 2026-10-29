import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';

import '../core/services/document_service.dart';
import '../domain/models/doc_model.dart';
import '../domain/models/ingest_progress.dart';
import 'ai/engines.dart';
import 'entities/entities.dart';
import 'repositories.dart';

class FileDocumentPicker implements DocumentPicker {
  @override
  Future<List<Doc>> pick() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'txt', 'docx', 'md'],
      allowMultiple: true,
      withData: false,
    );
    if (result == null) return const [];
    final docs = <Doc>[];
    for (final file in result.files) {
      final sourcePath = file.path;
      if (sourcePath == null) continue;
      final ext = p.extension(file.name).toLowerCase();
      final type = switch (ext) {
        '.pdf' => DocType.pdf,
        '.docx' => DocType.docx,
        '.md' => DocType.md,
        '.txt' => DocType.txt,
        _ => null,
      };
      if (type == null) continue;
      final bytes = await File(sourcePath).length();
      docs.add(
        Doc(
          const Uuid().v4(),
          file.name,
          type,
          0,
          bytes / (1024 * 1024),
          path: sourcePath,
        ),
      );
    }
    return docs;
  }
}

class PageText {
  const PageText(this.page, this.text);
  final int page;
  final String text;
}

/// PDF parsing and DOCX/XML extraction run away from the UI isolate.
Future<List<PageText>> extractPages(String path, DocType type) =>
    Isolate.run(() {
      final bytes = File(path).readAsBytesSync();
      if (type == DocType.pdf) {
        final document = PdfDocument(inputBytes: bytes);
        try {
          final extractor = PdfTextExtractor(document);
          return [
            for (var i = 0; i < document.pages.count; i++)
              PageText(
                i + 1,
                extractor.extractText(startPageIndex: i, endPageIndex: i),
              ),
          ];
        } finally {
          document.dispose();
        }
      }
      if (type == DocType.docx) {
        final docx = ZipDecoder().decodeBytes(bytes);
        final xmlFile = docx.findFile('word/document.xml');
        if (xmlFile == null) {
          throw const FormatException(
            'This Word file is missing its document content.',
          );
        }
        final xmlDoc = XmlDocument.parse(
          utf8.decode(xmlFile.content as List<int>),
        );
        final text = xmlDoc
            .findAllElements('w:p')
            .map(
              (paragraph) => paragraph
                  .findAllElements('w:t')
                  .map((node) => node.innerText)
                  .join(),
            )
            .join('\n');
        if (text.trim().isEmpty) {
          throw const FormatException(
            'This Word file contains no extractable text.',
          );
        }
        return [PageText(1, text)];
      }
      String text;
      try {
        text = utf8.decode(bytes);
      } on FormatException {
        text = latin1.decode(bytes);
      }
      if (text.trim().isEmpty) {
        throw const FormatException('This document contains no readable text.');
      }
      return [PageText(1, text)];
    });

class TextChunk {
  const TextChunk(this.text, this.page);
  final String text;
  final int page;
}

class RecursiveChunker {
  // The splitter counts whitespace-delimited words; these defaults approximate
  // a 400–500-token BGE input while leaving room for the query prefix.
  const RecursiveChunker({this.targetTokens = 320, this.overlapTokens = 40})
    : assert(targetTokens > overlapTokens),
      assert(overlapTokens >= 0);
  final int targetTokens;
  final int overlapTokens;

  List<TextChunk> split(List<PageText> pages) {
    final output = <TextChunk>[];
    for (final page in pages) {
      final normalized = page.text.replaceAll('\r\n', '\n').trim();
      if (normalized.isEmpty) continue;
      final paragraphs = normalized.split(RegExp(r'\n\s*\n+'));
      var current = <String>[];
      var count = 0;
      var hasNewText = false;
      void flush() {
        final text = current.join('\n\n').trim();
        if (hasNewText && text.isNotEmpty) {
          output.add(TextChunk(text, page.page));
        }
        final words = text.split(RegExp(r'\s+'));
        final carry = overlapTokens == 0
            ? <String>[]
            : words
                  .skip((words.length - overlapTokens).clamp(0, words.length))
                  .toList();
        current = carry.isEmpty ? [] : [carry.join(' ')];
        count = carry.length;
        hasNewText = false;
      }

      for (final paragraph in paragraphs) {
        final sentences = paragraph.split(RegExp(r'(?<=[.!?])\s+'));
        for (final sentence in sentences) {
          final trimmed = sentence.trim();
          if (trimmed.isEmpty) continue;
          final words = trimmed.split(RegExp(r'\s+'));
          if (hasNewText &&
              words.length <= targetTokens &&
              count + words.length > targetTokens) {
            flush();
          }
          for (var start = 0; start < words.length;) {
            if (count == targetTokens) flush();
            final end = (start + targetTokens - count).clamp(0, words.length);
            current.add(words.sublist(start, end).join(' '));
            count += end - start;
            hasNewText = true;
            start = end;
            if (start < words.length) flush();
          }
        }
      }
      if (hasNewText) {
        output.add(TextChunk(current.join('\n\n').trim(), page.page));
      }
    }
    return output;
  }
}

Future<List<TextChunk>> splitPagesInBackground(
  RecursiveChunker chunker,
  List<PageText> pages,
) => Isolate.run(() => chunker.split(pages));

/// A complete ingestion transaction boundary. Canceling the subscription
/// propagates to the active operation and removes all partial database state.
class IngestDocumentUseCase {
  IngestDocumentUseCase(
    this.repositories,
    this.embedding, {
    this._chunker = const RecursiveChunker(),
    Future<Directory> Function()? documentDirectory,
  }) : _documentDirectory = documentDirectory ?? LocalFiles.documentsDirectory;
  final Repositories repositories;
  final EmbeddingEngine embedding;
  final RecursiveChunker _chunker;
  final Future<Directory> Function() _documentDirectory;

  Stream<IngestProgress> call(TopicEntity topic, List<Doc> picked) async* {
    for (final doc in picked) {
      final source = File(doc.path);
      final bytes = await source.readAsBytes();
      final sha = sha256.convert(bytes).toString();
      final docs = repositories.documents.forTopic(topic.id);
      if (docs.any((d) => d.contentSha256 == sha)) continue;
      final folder = await _documentDirectory();
      final localPath = p.join(folder.path, '${const Uuid().v4()}${p.extension(doc.name)}');
      final localFile = await source.copy(localPath);
      final entity = DocumentEntity()
        ..uuid = doc.id
        ..name = doc.name
        ..type = doc.type.name
        ..sizeBytes = bytes.length
        ..path = localFile.path
        ..status = 'saved'
        ..createdAt = DateTime.now()
        ..contentSha256 = sha;
      entity.topic.target = topic;
      var committed = false;
      try {
        if (repositories.topics.byUuid(topic.uuid) == null) throw StateError('This knowledge base no longer exists.');
        repositories.documents.put(entity);
        await for (final progress in indexSaved(entity.uuid)) {
          if (progress.stage >= 3) committed = true;
          if (progress.stage != 4) yield progress;
        }
      } finally {
        if (!committed) {
          repositories.documents.delete(entity.uuid, repositories.chunks);
          if (await localFile.exists()) await localFile.delete();
        }
      }
    }
    yield const IngestProgress(4, 1, 'Completed');
  }

  Stream<IngestProgress> indexSaved(String documentId) async* {
    final entity = repositories.documents.byUuid(documentId);
    if (entity == null) throw StateError('This document no longer exists.');
    final topic = entity.topic.target;
    if (topic == null) throw StateError('This knowledge base no longer exists.');
    final sourcePath = entity.path;
    final sourceSha = entity.contentSha256;
    final topicId = topic.id;
    final previousStatus = entity.status == 'processing' ? 'saved' : entity.status;
    final type = DocType.values.where((value) => value.name == entity.type).firstOrNull;
    if (type == null) throw StateError('This document format is not supported.');
    var committed = false;
    DocumentEntity? currentVersion() {
      final current = repositories.documents.byUuid(documentId);
      return current != null && current.id == entity.id && current.path == sourcePath &&
          current.contentSha256 == sourceSha && current.topic.targetId == topicId ? current : null;
    }
    try {
      entity.status = 'processing';
      repositories.documents.put(entity);
      yield const IngestProgress(0, .05, 'Reading document');
      final bytes = await File(sourcePath).readAsBytes();
      final actualSha = sha256.convert(bytes).toString();
      if (sourceSha.isNotEmpty && actualSha != sourceSha) throw StateError('The saved file changed. Save it again before indexing.');
      final pages = await extractPages(sourcePath, type);
      if (type == DocType.pdf && pages.every((page) => page.text.trim().isEmpty)) {
        throw const FormatException('This PDF appears to be scanned or image-only. OCR is not available yet.');
      }
      yield const IngestProgress(1, .18, 'Splitting text by page');
      final chunks = await splitPagesInBackground(_chunker, pages);
      if (chunks.isEmpty) throw const FormatException('No readable text was found in this document.');
      yield IngestProgress(1, .20, 'Created ${chunks.length} chunks');
      if (embedding.dimensions != 384) {
        throw StateError('This embedding model has ${embedding.dimensions} dimensions; this index requires 384. Load a supported embedding model before indexing.');
      }
      final embeddingId = embedding.modelId;
      if (embeddingId == null || embeddingId.isEmpty) throw StateError('Load an active embedding model first.');
      final records = <ChunkEntity>[];
      const batchSize = 8;
      yield IngestProgress(2, .20, '0 / ${chunks.length} chunks');
      for (var i = 0; i < chunks.length; i += batchSize) {
        final end = (i + batchSize).clamp(0, chunks.length);
        final vectors = await embedding.embedBatch(chunks.sublist(i, end).map((chunk) => chunk.text).toList());
        if (embedding.modelId != embeddingId) throw StateError('The embedding model changed during indexing. Try again.');
        if (currentVersion() == null) throw StateError('The document changed, moved or was deleted during indexing. Try again.');
        if (vectors.length != end - i || vectors.any((v) => v.length != 384 || v.any((value) => !value.isFinite))) {
          throw StateError('Embedding model returned an invalid vector.');
        }
        for (var j = i; j < end; j++) {
          final chunk = chunks[j];
          final row = ChunkEntity()
            ..text = chunk.text
            ..pageNumber = chunk.page
            ..chunkIndex = j
            ..embeddingModelId = embeddingId
            ..vector = vectors[j - i];
          row.document.target = entity;
          row.topic.target = topic;
          records.add(row);
        }
        yield IngestProgress(2, .2 + .62 * end / chunks.length, '$end / ${chunks.length} chunks');
      }
      if (embedding.modelId != embeddingId) throw StateError('The embedding model changed during indexing. Try again.');
      repositories.write(() {
        final current = currentVersion();
        if (current == null || repositories.topics.byUuid(topic.uuid) == null) {
          throw StateError('The document changed, moved or was deleted during indexing. Try again.');
        }
        repositories.chunks.deleteForDocument(current.id);
        repositories.chunks.putMany(records);
        current.chunkCount = records.length;
        current.pageCount = pages.length;
        current.contentSha256 = actualSha;
        current.status = 'ready';
        repositories.documents.put(current);
      });
      committed = true;
      yield const IngestProgress(3, .94, 'Indexed on this device');
      yield const IngestProgress(4, 1, 'Completed');
    } finally {
      if (!committed) {
        final current = repositories.documents.byUuid(documentId);
        if (current != null && current.path == sourcePath && current.contentSha256 == sourceSha && current.status == 'processing') {
          current.status = previousStatus;
          repositories.documents.put(current);
        }
      }
    }
  }
}

class ReindexEmbeddingsUseCase {
  ReindexEmbeddingsUseCase(this.repositories, this.embedding);
  final Repositories repositories;
  final EmbeddingEngine embedding;

  Stream<IngestProgress> call() async* {
    final topics = repositories.topics.getAll();
    final rows = [
      for (final topic in topics) ...repositories.chunks.forTopic(topic.id),
    ];
    if (rows.isEmpty) {
      yield const IngestProgress(4, 1, 'There are no chunks to re-index');
      return;
    }
    if (embedding.dimensions != 384) {
      throw StateError(
        'The current database index requires 384-dimensional embeddings.',
      );
    }
    final embeddingId = embedding.modelId;
    if (embeddingId == null || embeddingId.isEmpty) {
      throw StateError('Load an active embedding model first.');
    }
    final originals = {for (final row in rows) row.id: (row.text, row.document.targetId, row.topic.targetId)};
    final pending = <ChunkEntity>[];
    const batchSize = 8;
    for (var i = 0; i < rows.length; i += batchSize) {
      final end = (i + batchSize).clamp(0, rows.length);
      final batch = rows.sublist(i, end);
      final vectors = await embedding.embedBatch(
        batch.map((row) => row.text).toList(),
      );
      if (embedding.modelId != embeddingId) {
        throw StateError(
          'The embedding model changed during re-indexing. Try again.',
        );
      }
      if (vectors.length != batch.length ||
          vectors.any(
            (vector) =>
                vector.length != 384 || vector.any((value) => !value.isFinite),
          )) {
        throw StateError('The active model returned an incompatible vector.');
      }
      for (var j = 0; j < batch.length; j++) {
        batch[j].vector = vectors[j];
        batch[j].embeddingModelId = embeddingId;
        pending.add(batch[j]);
      }
      yield IngestProgress(
        2,
        end / rows.length,
        '$end / ${rows.length} chunks',
      );
    }
    if (embedding.modelId != embeddingId) {
      throw StateError(
        'The embedding model changed during re-indexing. Try again.',
      );
    }
    repositories.write(() {
      final current = {for (final topic in repositories.topics.getAll())
        for (final chunk in repositories.chunks.forTopic(topic.id)) chunk.id: chunk};
      for (final row in pending) {
        final chunk = current[row.id];
        if (chunk == null || (chunk.text, chunk.document.targetId, chunk.topic.targetId) != originals[row.id]) {
          throw StateError('Documents changed during re-indexing. Try again.');
        }
      }
      repositories.chunks.putMany(pending);
    });
    yield const IngestProgress(4, 1, 'Re-indexing completed');
  }
}

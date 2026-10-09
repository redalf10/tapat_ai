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
      docs.add(Doc(const Uuid().v4(), file.name, type, 0, bytes / (1024 * 1024), path: sourcePath));
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
Future<List<PageText>> extractPages(String path, DocType type) => Isolate.run(() {
  final bytes = File(path).readAsBytesSync();
  if (type == DocType.pdf) {
    final document = PdfDocument(inputBytes: bytes);
    try {
      final extractor = PdfTextExtractor(document);
      return [for (var i = 0; i < document.pages.count; i++)
        PageText(i + 1, extractor.extractText(startPageIndex: i, endPageIndex: i))];
    } finally { document.dispose(); }
  }
  if (type == DocType.docx) {
    final docx = ZipDecoder().decodeBytes(bytes);
    final xmlFile = docx.findFile('word/document.xml');
    if (xmlFile == null) throw const FormatException('This Word file is missing its document content.');
    final xmlDoc = XmlDocument.parse(utf8.decode(xmlFile.content as List<int>));
    final text = xmlDoc.findAllElements('w:p').map((paragraph) =>
      paragraph.findAllElements('w:t').map((node) => node.innerText).join()).join('\n');
    if (text.trim().isEmpty) throw const FormatException('This Word file contains no extractable text.');
    return [PageText(1, text)];
  }
  String text;
  try { text = utf8.decode(bytes); }
  on FormatException { text = latin1.decode(bytes); }
  if (text.trim().isEmpty) throw const FormatException('This document contains no readable text.');
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
      void flush() {
        final text = current.join('\n\n').trim();
        if (text.isNotEmpty) output.add(TextChunk(text, page.page));
        final carry = current.join(' ').split(RegExp(r'\s+'));
        current = carry.length > overlapTokens ? [carry.sublist(carry.length - overlapTokens).join(' ')] : [];
        count = current.isEmpty ? 0 : overlapTokens;
      }
      for (final paragraph in paragraphs) {
        final sentences = paragraph.split(RegExp(r'(?<=[.!?])\s+'));
        for (final sentence in sentences) {
          final trimmed = sentence.trim();
          if (trimmed.isEmpty) continue;
          final words = trimmed.split(RegExp(r'\s+'));
          if (words.length > targetTokens) {
            for (var start = 0; start < words.length; start += targetTokens - overlapTokens) {
              final end = (start + targetTokens).clamp(0, words.length);
              output.add(TextChunk(words.sublist(start, end).join(' '), page.page));
              if (end == words.length) break;
            }
            continue;
          }
          if (count + words.length > targetTokens && current.isNotEmpty) flush();
          current.add(sentence.trim());
          count += words.length;
        }
      }
      if (current.isNotEmpty) output.add(TextChunk(current.join('\n\n').trim(), page.page));
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
  IngestDocumentUseCase(this.repositories, this.embedding, {
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
        ..status = 'processing'
        ..createdAt = DateTime.now()
        ..contentSha256 = sha;
      entity.topic.target = topic;
      repositories.documents.put(entity);
      var committed = false;
      try {
        yield const IngestProgress(0, .05, 'Reading document');
        final pages = await extractPages(localFile.path, doc.type);
        if (doc.type == DocType.pdf && pages.every((page) => page.text.trim().isEmpty)) {
          throw const FormatException('This PDF appears to be scanned or image-only. OCR is not available yet.');
        }
        entity.pageCount = pages.length;
        yield const IngestProgress(1, .18, 'Splitting text by page');
        final chunks = await splitPagesInBackground(_chunker, pages);
        if (chunks.isEmpty) throw const FormatException('No readable text was found in this document.');
        yield IngestProgress(1, .20, 'Created ${chunks.length} chunks');
        if (embedding.dimensions != 384) {
          throw StateError('This embedding model has ${embedding.dimensions} dimensions; this index requires 384. Re-index this knowledge base after selecting a supported model.');
        }
        final records = <ChunkEntity>[];
        const batchSize = 8;
        yield IngestProgress(2, .20, '0 / ${chunks.length} chunks');
        for (var i = 0; i < chunks.length; i += batchSize) {
          final end = (i + batchSize).clamp(0, chunks.length);
          final vectors = await embedding.embedBatch(chunks.sublist(i, end).map((e) => e.text).toList());
          if (vectors.length != end - i || vectors.any((v) => v.length != 384)) {
            throw StateError('Embedding model returned an invalid vector.');
          }
          for (var j = i; j < end; j++) {
            final chunk = chunks[j];
            final row = ChunkEntity()
              ..text = chunk.text
              ..pageNumber = chunk.page
              ..chunkIndex = j
              ..embeddingModelId = embedding.modelId ?? '';
            row.document.target = entity;
            row.topic.target = topic;
            row.vector = vectors[j - i];
            records.add(row);
          }
          yield IngestProgress(2, .2 + .62 * end / chunks.length, '$end / ${chunks.length} chunks');
        }
        repositories.chunks.putMany(records);
        entity.chunkCount = records.length;
        entity.status = 'ready';
        repositories.documents.put(entity);
        committed = true;
        yield const IngestProgress(3, .94, 'Saved on this device');
      } finally {
        if (!committed) {
          repositories.chunks.deleteForDocument(entity.id);
          repositories.documents.delete(entity.uuid, repositories.chunks);
        }
      }
    }
    yield const IngestProgress(4, 1, 'Completed');
  }
}

class ReindexEmbeddingsUseCase {
  ReindexEmbeddingsUseCase(this.repositories, this.embedding);
  final Repositories repositories;
  final EmbeddingEngine embedding;

  Stream<IngestProgress> call() async* {
    final topics = repositories.topics.getAll();
    final rows = [for (final topic in topics) ...repositories.chunks.forTopic(topic.id)];
    if (rows.isEmpty) {
      yield const IngestProgress(4, 1, 'There are no chunks to re-index');
      return;
    }
    if (embedding.dimensions != 384) throw StateError('The current database index requires 384-dimensional embeddings.');
    final pending = <ChunkEntity>[];
    const batchSize = 8;
    for (var i = 0; i < rows.length; i += batchSize) {
      final end = (i + batchSize).clamp(0, rows.length);
      final batch = rows.sublist(i, end);
      final vectors = await embedding.embedBatch(batch.map((row) => row.text).toList());
      if (vectors.any((vector) => vector.length != 384)) throw StateError('The active model returned an incompatible vector.');
      for (var j = 0; j < batch.length; j++) {
        batch[j].vector = vectors[j];
        batch[j].embeddingModelId = embedding.modelId ?? '';
        pending.add(batch[j]);
      }
      yield IngestProgress(2, end / rows.length, '$end / ${rows.length} chunks');
    }
    repositories.chunks.putMany(pending);
    yield const IngestProgress(4, 1, 'Re-indexing completed');
  }
}


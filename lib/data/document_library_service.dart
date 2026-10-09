import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'entities/entities.dart';
import 'repositories.dart';

class DocumentLibraryService {
  DocumentLibraryService(this.repositories, {Future<Directory> Function()? documentDirectory})
    : _documentDirectory = documentDirectory ?? LocalFiles.documentsDirectory;
  final Repositories repositories;
  final Future<Directory> Function() _documentDirectory;

  Future<String> readText(String documentId) async {
    final document = repositories.documents.byUuid(documentId);
    if (document == null) throw StateError('This document no longer exists.');
    _requireEditable(document);
    return File(document.path).readAsString(encoding: utf8);
  }

  Future<DocumentEntity> saveText({
    required String topicId,
    required String title,
    required String content,
    String? documentId,
    String? expectedSha256,
    bool aiAssisted = false,
  }) async {
    title = title.trim().replaceFirst(RegExp(r'\.txt$', caseSensitive: false), '').trim();
    if (title.isEmpty || title.length > 200 || RegExp(r'[\x00-\x1f]').hasMatch(title)) {
      throw const FormatException('Enter a document title of 1–200 characters without line breaks.');
    }
    if (content.trim().isEmpty) throw const FormatException('Enter some document content before saving.');
    final bytes = utf8.encode(content);
    if (bytes.length > 4 * 1024 * 1024) throw const FormatException('Text documents must be smaller than 4 MB.');
    final topic = repositories.topics.byUuid(topicId);
    if (topic == null) throw StateError('This knowledge base no longer exists.');
    final existing = documentId == null ? null : repositories.documents.byUuid(documentId);
    if (documentId != null && existing == null) throw StateError('This document no longer exists.');
    if (existing != null) {
      _requireEditable(existing);
      _requireVersion(existing, topic.id, expectedSha256);
    }
    final previousSha = existing?.contentSha256;
    final previousPath = existing?.path;
    final directory = await _documentDirectory();
    final file = File(p.join(directory.path, '${LocalFiles.newId()}.txt'));
    var committed = false;
    try {
      await file.writeAsBytes(bytes, flush: true);
      final now = DateTime.now();
      final document = DocumentEntity()
        ..id = existing?.id ?? 0
        ..uuid = existing?.uuid ?? LocalFiles.newId()
        ..name = '$title.txt'
        ..type = 'txt'
        ..origin = 'created'
        ..aiAssisted = aiAssisted || (existing?.aiAssisted ?? false)
        ..path = file.path
        ..sizeBytes = bytes.length
        ..pageCount = 1
        ..status = 'saved'
        ..createdAt = existing?.createdAt ?? now
        ..updatedAt = now
        ..contentSha256 = sha256.convert(bytes).toString();
      document.topic.target = topic;
      repositories.write(() {
        if (repositories.topics.byUuid(topicId) == null) throw StateError('This knowledge base no longer exists.');
        if (existing != null) {
          final current = repositories.documents.byUuid(existing.uuid);
          if (current == null) throw StateError('This document was deleted while saving.');
          _requireVersion(current, topic.id, expectedSha256 ?? previousSha);
          repositories.chunks.deleteForDocument(current.id);
        }
        repositories.documents.put(document);
      });
      committed = true;
      if (existing != null) {
        try {
          final previous = File(previousPath!);
          if (await previous.exists()) await previous.delete();
        } on FileSystemException {
          return document;
        }
      }
      return document;
    } finally {
      if (!committed && await file.exists()) await file.delete();
    }
  }

  void _requireEditable(DocumentEntity document) {
    if (document.origin != 'created' || document.type != 'txt') {
      throw StateError('Only text documents created in Tapat AI can be edited here.');
    }
  }

  void _requireVersion(DocumentEntity document, int topicId, String? sha) {
    if (document.topic.targetId != topicId || (sha != null && document.contentSha256 != sha)) {
      throw StateError('This document changed or moved. Reopen it before saving your changes.');
    }
  }
}

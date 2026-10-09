import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:tapat_ai/data/ai/engines.dart';
import 'package:tapat_ai/data/file_ingestion.dart';
import 'package:tapat_ai/data/native_nfc_service.dart';
import 'package:tapat_ai/data/entities/entities.dart';
import 'package:tapat_ai/data/objectbox_store.dart';
import 'package:tapat_ai/data/repositories.dart';
import 'package:tapat_ai/domain/models/doc_model.dart';

void main() {
  test('repositories persist topic relations, vector search results and cascades', () {
    final objectBox = ObjectBoxStore.inMemory('repository-test');
    final repos = Repositories(objectBox);
    try {
      final topic = TopicEntity()
        ..uuid = 'topic-1' ..name = 'Study' ..createdAt = DateTime.now() ..nfcId = 'topic-1';
      repos.topics.put(topic);
      final document = DocumentEntity()
        ..uuid = 'doc-1' ..name = 'notes.txt' ..type = 'txt' ..path = 'unused'
        ..sizeBytes = 10 ..createdAt = DateTime.now() ..status = 'ready';
      document.topic.target = topic;
      repos.documents.put(document);
      final vector = List<double>.generate(384, (i) => i == 0 ? 1 : 0);
      final chunk = ChunkEntity()
        ..text = 'A grounded note.' ..pageNumber = 2 ..chunkIndex = 0 ..embeddingModelId = 'embed-1' ..vector = vector;
      chunk.topic.target = topic;
      chunk.document.target = document;
      repos.chunks.putMany([chunk]);
      expect(repos.chunks.search(topic.id, vector, 1).single.chunk.text, 'A grounded note.');
      repos.topics.deleteCascade(topic.uuid, repos);
      expect(repos.topics.getAll(), isEmpty);
      expect(repos.chunks.forTopic(topic.id), isEmpty);
      expect(repos.documents.forTopic(topic.id), isEmpty);
    } finally { objectBox.store.close(); }
  }, skip: Platform.isWindows
      ? 'ObjectBox desktop native library is not shipped for Windows unit tests; run on Android/iOS/Linux with the ObjectBox native runtime.'
      : false);

  test('ingest extracts text, chunks it, embeds it, and persists source pages', () async {
    final objectBox = ObjectBoxStore.inMemory('ingest-test');
    final repos = Repositories(objectBox);
    final temp = await Directory.systemTemp.createTemp('tapat-ingest-test');
    try {
      final topic = TopicEntity()
        ..uuid = 'topic-2' ..name = 'Notes' ..createdAt = DateTime.now() ..nfcId = 'topic-2';
      repos.topics.put(topic);
      final source = File('${temp.path}/input.txt');
      await source.writeAsString('The local model answers from indexed text.');
      final useCase = IngestDocumentUseCase(repos, _FakeEmbedding(), documentDirectory: () async => temp);
      final progress = await useCase(topic, [Doc('doc-2', 'input.txt', DocType.txt, 0, 0.1, path: source.path)]).toList();
      expect(progress.last.stage, 4);
      final doc = repos.documents.byUuid('doc-2')!;
      expect(doc.status, 'ready');
      expect(doc.chunkCount, 1);
      expect(repos.chunks.forTopic(topic.id).single.pageNumber, 1);
    } finally {
      objectBox.store.close();
      await temp.delete(recursive: true);
    }
  }, skip: Platform.isWindows
      ? 'ObjectBox desktop native library is not shipped for Windows unit tests; run on Android/iOS/Linux with the ObjectBox native runtime.'
      : false);

  group('RecursiveChunker', () {
    test('keeps each chunk on its source page and splits long content', () {
      const chunker = RecursiveChunker(targetTokens: 10, overlapTokens: 2);
      final chunks = chunker.split([
        PageText(1, 'One two three four five six seven eight nine ten. Eleven twelve thirteen fourteen fifteen sixteen.'),
        PageText(2, 'Second page has a different paragraph.'),
      ]);
      expect(chunks.length, greaterThan(2));
      expect(chunks.where((chunk) => chunk.page == 2), isNotEmpty);
      expect(chunks.where((chunk) => chunk.page == 1).every((chunk) => !chunk.text.contains('Second page')), isTrue);
    });
  });

  group('PromptBuilder', () {
    test('uses the Gemma template and includes bounded context with citations', () {
      final prompt = PromptBuilder.build(modelName: 'Gemma 2 2B', question: 'What happened?',
        context: ['Manual, page 2: A clear event.'], history: ['user: hi']);
      expect(prompt, contains('<start_of_turn>system'));
      expect(prompt, contains('[1] Manual, page 2: A clear event.'));
      expect(prompt, contains("I couldn't find that in your documents."));
    });
  });

  group('NFC topic payload', () {
    test('reads the external type UUID before falling back to the URI record', () {
      const id = 'topic-uuid-123';
      final message = NdefMessage(records: [
        NdefRecord(typeNameFormat: TypeNameFormat.external, type: Uint8List.fromList('tapat.ai:topic'.codeUnits),
          identifier: Uint8List(0), payload: Uint8List.fromList(id.codeUnits)),
        NdefRecord(typeNameFormat: TypeNameFormat.wellKnown, type: Uint8List.fromList([0x55]),
          identifier: Uint8List(0), payload: Uint8List.fromList([0, ...'tapat://kb/$id'.codeUnits])),
      ]);
      expect(NativeNfcService.parseTopicId(message), id);
      expect(NativeNfcService.parseTopicId(null), isNull);
    });
  });
}

class _FakeEmbedding implements EmbeddingEngine {
  @override
  int get dimensions => 384;
  @override
  String? get modelId => 'fake-embedding';
  @override
  Future<void> load(ModelEntity model) async {}
  @override
  Future<void> unload() async {}
  @override
  Future<List<double>> embed(String text) async => List<double>.filled(384, 0.01);
  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async =>
      List.generate(texts.length, (_) => List<double>.filled(384, 0.01));
}

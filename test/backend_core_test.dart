import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:tapat_ai/data/ai/engines.dart';
import 'package:tapat_ai/data/ai/local_rag_service.dart';
import 'package:tapat_ai/data/file_ingestion.dart';
import 'package:tapat_ai/data/native_nfc_service.dart';
import 'package:tapat_ai/data/entities/entities.dart';
import 'package:tapat_ai/data/objectbox_store.dart';
import 'package:tapat_ai/data/repositories.dart';
import 'package:tapat_ai/domain/models/doc_model.dart';
import 'package:tapat_ai/domain/models/topic_model.dart';

void main() {
  test(
    'repositories persist topic relations, vector search results and cascades',
    () {
      final objectBox = ObjectBoxStore.inMemory('repository-test');
      final repos = Repositories(objectBox);
      try {
        final topic = TopicEntity()
          ..uuid = 'topic-1'
          ..name = 'Study'
          ..createdAt = DateTime.now()
          ..nfcId = 'topic-1';
        repos.topics.put(topic);
        final document = DocumentEntity()
          ..uuid = 'doc-1'
          ..name = 'notes.txt'
          ..type = 'txt'
          ..path = 'unused'
          ..sizeBytes = 10
          ..createdAt = DateTime.now()
          ..status = 'ready';
        document.topic.target = topic;
        repos.documents.put(document);
        final vector = List<double>.generate(384, (i) => i == 0 ? 1 : 0);
        final chunk = ChunkEntity()
          ..text = 'A grounded note.'
          ..pageNumber = 2
          ..chunkIndex = 0
          ..embeddingModelId = 'embed-1'
          ..vector = vector;
        chunk.topic.target = topic;
        chunk.document.target = document;
        repos.chunks.putMany([chunk]);
        expect(
          repos.chunks.search(topic.id, vector, 1).single.chunk.text,
          'A grounded note.',
        );
        repos.topics.deleteCascade(topic.uuid, repos);
        expect(repos.topics.getAll(), isEmpty);
        expect(repos.chunks.forTopic(topic.id), isEmpty);
        expect(repos.documents.forTopic(topic.id), isEmpty);
      } finally {
        objectBox.store.close();
      }
    },
    skip: Platform.isWindows && !const bool.fromEnvironment('NATIVE_OBJECTBOX_TESTS')
        ? 'ObjectBox desktop native library is not shipped for Windows unit tests; run on Android/iOS/Linux with the ObjectBox native runtime.'
        : false,
  );

  test(
    'ingest extracts text, chunks it, embeds it, and persists source pages',
    () async {
      final objectBox = ObjectBoxStore.inMemory('ingest-test');
      final repos = Repositories(objectBox);
      final temp = await Directory.systemTemp.createTemp('tapat-ingest-test');
      try {
        final topic = TopicEntity()
          ..uuid = 'topic-2'
          ..name = 'Notes'
          ..createdAt = DateTime.now()
          ..nfcId = 'topic-2';
        repos.topics.put(topic);
        final source = File('${temp.path}/input.txt');
        await source.writeAsString(
          'The local model answers from indexed text.',
        );
        final useCase = IngestDocumentUseCase(
          repos,
          _FakeEmbedding(),
          documentDirectory: () async => temp,
        );
        final progress = await useCase(topic, [
          Doc('doc-2', 'input.txt', DocType.txt, 0, 0.1, path: source.path),
        ]).toList();
        expect(progress.last.stage, 4);
        final doc = repos.documents.byUuid('doc-2')!;
        expect(doc.status, 'ready');
        expect(doc.chunkCount, 1);
        expect(repos.chunks.forTopic(topic.id).single.pageNumber, 1);
      } finally {
        objectBox.store.close();
        await temp.delete(recursive: true);
      }
    },
    skip: Platform.isWindows && !const bool.fromEnvironment('NATIVE_OBJECTBOX_TESTS')
        ? 'ObjectBox desktop native library is not shipped for Windows unit tests; run on Android/iOS/Linux with the ObjectBox native runtime.'
        : false,
  );

  group('RecursiveChunker', () {
    test('keeps each chunk on its source page and splits long content', () {
      const chunker = RecursiveChunker(targetTokens: 10, overlapTokens: 2);
      final chunks = chunker.split([
        PageText(
          1,
          'One two three four five six seven eight nine ten. Eleven twelve thirteen fourteen fifteen sixteen.',
        ),
        PageText(2, 'Second page has a different paragraph.'),
      ]);
      expect(chunks.length, greaterThan(2));
      expect(chunks.where((chunk) => chunk.page == 2), isNotEmpty);
      expect(
        chunks
            .where((chunk) => chunk.page == 1)
            .every((chunk) => !chunk.text.contains('Second page')),
        isTrue,
      );
    });

    test('preserves source order around an oversized sentence', () {
      const chunker = RecursiveChunker(targetTokens: 10, overlapTokens: 2);
      final longSentence = List.generate(25, (i) => 'word$i').join(' ');
      final chunks = chunker.split([
        PageText(1, 'Before the details. $longSentence. After the details.'),
      ]);
      expect(chunks.first.text, startsWith('Before the details.'));
      expect(chunks.last.text, contains('After the details.'));
      expect(
        chunks.every((chunk) => chunk.text.split(RegExp(r'\s+')).length <= 10),
        isTrue,
      );
    });

    test(
      'bounds chunks even when overlap and a sentence exceed the target',
      () {
        const chunker = RecursiveChunker(targetTokens: 10, overlapTokens: 4);
        final chunks = chunker.split([
          const PageText(
            1,
            'One two three four five six seven eight. Nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen.',
          ),
        ]);
        expect(
          chunks.every(
            (chunk) => chunk.text.split(RegExp(r'\s+')).length <= 10,
          ),
          isTrue,
        );
      },
    );

    test('keeps every word without overlap-only trailing chunks', () {
      const chunker = RecursiveChunker(targetTokens: 10, overlapTokens: 2);
      final words = List.generate(26, (i) => 'word$i');
      final chunks = chunker.split([PageText(1, words.join(' '))]);
      final reconstructed = [
        ...chunks.first.text.split(RegExp(r'\s+')),
        for (final chunk in chunks.skip(1))
          ...chunk.text.split(RegExp(r'\s+')).skip(2),
      ];
      expect(reconstructed, words);
      expect(chunks.length, 3);
    });

    test('supports zero overlap and ignores empty pages', () {
      const chunker = RecursiveChunker(targetTokens: 3, overlapTokens: 0);
      final chunks = chunker.split([
        const PageText(1, '  '),
        const PageText(2, 'one two three four five six'),
      ]);
      expect(chunks.map((chunk) => chunk.text), [
        'one two three',
        'four five six',
      ]);
      expect(chunks.every((chunk) => chunk.page == 2), isTrue);
    });
  });

  group('EmbeddingTextSplitter', () {
    test('keeps a long passage whole when it fits the actual token budget', () {
      final text = List.generate(320, (i) => 'word$i').join(' ');
      final splitter = EmbeddingTextSplitter(
        (value) => value.split(RegExp(r'\s+')).length + 2,
      );
      expect(utf8.encode(text).length, greaterThan(480));
      expect(splitter.split(text), [text]);
    });

    test(
      'reserves prefix and special tokens without losing Unicode content',
      () {
        const prefix = 'query: ';
        const text = 'alpha beta café gamma 漢字 delta epsilon zeta eta theta';
        final splitter = EmbeddingTextSplitter(
          (value) => value.runes.length + 2,
          maxTokens: 24,
        );
        final passages = splitter.split(text, prefix: prefix);
        expect(passages.length, greaterThan(1));
        expect(passages.join(), text);
        expect(
          passages.every((passage) => '$prefix$passage'.runes.length + 2 <= 24),
          isTrue,
        );
        expect(passages.any((passage) => passage.contains('\uFFFD')), isFalse);
      },
    );

    test(
      'bounds unbroken text and rejects empty input or an oversized prefix',
      () {
        final splitter = EmbeddingTextSplitter(
          (value) => value.runes.length,
          maxTokens: 8,
        );
        expect(
          splitter.split('abcdefghijklmnopqrst').join(),
          'abcdefghijklmnopqrst',
        );
        expect(
          splitter
              .split('abcdefghijklmnopqrst')
              .every((part) => part.length <= 8),
          isTrue,
        );
        expect(() => splitter.split('   '), throwsStateError);
        expect(
          () => splitter.split('text', prefix: 'too long a prefix: '),
          throwsStateError,
        );
      },
    );
  });

  group('OnDeviceEmbeddingEngine', () {
    test(
      'batches unique normalized documents and caches queries separately',
      () async {
        final backend = _FakeEmbeddingBackend();
        final engine = OnDeviceEmbeddingEngine(
          createBackend: (_) async => backend,
        );
        addTearDown(engine.unload);
        await engine.load(_embeddingModel());
        final vectors = await engine.embedBatch([
          ' same\n text ',
          'same text',
          'different text',
        ]);
        expect(backend.calls.single.$1, ['same text', 'different text']);
        expect(backend.calls.single.$2, '');
        expect(vectors.length, 3);
        vectors.first[0] = 0;
        expect((await engine.embed('same text')).first, 1);
        await engine.embedQuery('same text');
        await engine.embedQuery(' same  text ');
        expect(backend.calls.length, 2);
        expect(backend.calls.last.$2, EmbeddingPrompts.queryPrefix('bge'));
        expect(engine.modelId, endsWith('auto-token512-bge-v2'));
      },
    );

    test(
      'uses E5 role prefixes and leaves unknown models unprefixed',
      () async {
        final backend = _FakeEmbeddingBackend();
        final engine = OnDeviceEmbeddingEngine(
          createBackend: (_) async => backend,
        );
        addTearDown(engine.unload);
        await engine.load(_embeddingModel(name: 'multilingual-e5-small'));
        await engine.embed('a passage');
        await engine.embedQuery('a question');
        expect(backend.calls.map((call) => call.$2), ['passage: ', 'query: ']);
        expect(
          EmbeddingPrompts.family(_embeddingModel(name: 'MiniLM')),
          'plain',
        );
        expect(EmbeddingPrompts.queryPrefix('plain'), '');
        expect(
          EmbeddingPrompts.queryPrefix(
            EmbeddingPrompts.family(_embeddingModel(name: 'BGE-M3')),
          ),
          '',
        );
      },
    );

    test(
      'evicts the least recently used vector rather than the oldest insertion',
      () async {
        final backend = _FakeEmbeddingBackend();
        final engine = OnDeviceEmbeddingEngine(
          createBackend: (_) async => backend,
          cacheCapacity: 2,
        );
        addTearDown(engine.unload);
        await engine.load(_embeddingModel());
        for (final text in ['one', 'two', 'one', 'three', 'one', 'two']) {
          await engine.embed(text);
        }
        expect(backend.calls.map((call) => call.$1.single), [
          'one',
          'two',
          'three',
          'two',
        ]);
      },
    );

    test(
      'returns an entire batch even when it exceeds cache capacity',
      () async {
        final backend = _FakeEmbeddingBackend();
        final engine = OnDeviceEmbeddingEngine(
          createBackend: (_) async => backend,
          cacheCapacity: 2,
        );
        addTearDown(engine.unload);
        await engine.load(_embeddingModel());
        final vectors = await engine.embedBatch(['one', 'two', 'three', 'one']);
        expect(vectors.length, 4);
        expect(backend.calls.single.$1, ['one', 'two', 'three']);
      },
    );

    test('clears cached vectors when the embedding model changes', () async {
      final first = _FakeEmbeddingBackend();
      final second = _FakeEmbeddingBackend();
      final backends = [first, second];
      final engine = OnDeviceEmbeddingEngine(
        createBackend: (_) async => backends.removeAt(0),
      );
      addTearDown(engine.unload);
      await engine.load(_embeddingModel());
      await engine.embed('cached passage');
      await engine.load(_embeddingModel(uuid: 'another-model'));
      await engine.embed('cached passage');
      expect(first.disposed, isTrue);
      expect(second.calls.length, 1);
      expect(engine.modelId, startsWith('another-model:'));
    });

    test('rejects invalid vectors without poisoning the cache', () async {
      final backend = _FakeEmbeddingBackend()
        ..vectorOverride = List.filled(384, double.nan);
      final engine = OnDeviceEmbeddingEngine(
        createBackend: (_) async => backend,
      );
      addTearDown(engine.unload);
      await engine.load(_embeddingModel());
      await expectLater(engine.embed('retry this'), throwsStateError);
      backend.vectorOverride = null;
      expect((await engine.embed('retry this')).first, 1);
      expect(backend.calls.length, 2);
      backend.omitLast = true;
      await expectLater(
        engine.embedBatch(['missing vector']),
        throwsStateError,
      );
    });

    test(
      'preserves the dimension mismatch and disposes the rejected backend',
      () async {
        final backend = _FakeEmbeddingBackend(dimensions: 3);
        final engine = OnDeviceEmbeddingEngine(
          createBackend: (_) async => backend,
        );
        await expectLater(
          engine.load(_embeddingModel()),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('returned 3 dimensions'),
            ),
          ),
        );
        expect(backend.disposed, isTrue);
        expect(engine.isLoaded, isFalse);
      },
    );

    test(
      'does not retain results from a model unloaded during inference',
      () async {
        final gate = Completer<void>();
        final backend = _FakeEmbeddingBackend()..gate = gate;
        final engine = OnDeviceEmbeddingEngine(
          createBackend: (_) async => backend,
        );
        await engine.load(_embeddingModel());
        final check = expectLater(engine.embed('in flight'), throwsStateError);
        await engine.unload();
        gate.complete();
        await check;
        expect(engine.modelId, isNull);
        expect(engine.dimensions, 0);
      },
    );

    test(
      'cancels a model load when the app unloads before it is ready',
      () async {
        final ready = Completer<EmbeddingBackend>();
        final started = Completer<void>();
        final backend = _FakeEmbeddingBackend();
        final engine = OnDeviceEmbeddingEngine(
          createBackend: (_) {
            started.complete();
            return ready.future;
          },
        );
        addTearDown(engine.unload);
        final check = expectLater(
          engine.load(_embeddingModel()),
          throwsStateError,
        );
        await started.future;
        await engine.unload();
        ready.complete(backend);
        await check;
        expect(engine.isLoaded, isFalse);
        expect(backend.disposed, isTrue);
      },
    );

    test('a slow model load cannot overwrite a newer active model', () async {
      final ready = Completer<EmbeddingBackend>();
      final started = Completer<void>();
      final oldBackend = _FakeEmbeddingBackend();
      final newBackend = _FakeEmbeddingBackend();
      final engine = OnDeviceEmbeddingEngine(
        createBackend: (model) {
          if (model.uuid == 'embedding-model') {
            started.complete();
            return ready.future;
          }
          return Future.value(newBackend);
        },
      );
      addTearDown(engine.unload);
      final check = expectLater(
        engine.load(_embeddingModel()),
        throwsStateError,
      );
      await started.future;
      await engine.load(_embeddingModel(uuid: 'new-model'));
      ready.complete(oldBackend);
      await check;
      expect(engine.modelId, startsWith('new-model:'));
      expect(oldBackend.disposed, isTrue);
      expect(newBackend.disposed, isFalse);
    });

    test(
      'rejects blank chunks before native work and accepts an empty batch',
      () async {
        final backend = _FakeEmbeddingBackend();
        final engine = OnDeviceEmbeddingEngine(
          createBackend: (_) async => backend,
        );
        addTearDown(engine.unload);
        expect(await engine.embedBatch([]), isEmpty);
        await engine.load(_embeddingModel());
        await expectLater(engine.embed('  \n '), throwsStateError);
        expect(backend.calls, isEmpty);
      },
    );
  });

  group('HybridChunkIndex', () {
    test('rescues an exact identifier missed by vector candidates', () {
      final semantic = _chunk(
        1,
        'General guidance for a local assistant.',
        _vector(0),
      );
      final exact = _chunk(
        2,
        'ABC-123 requires a supervisor approval.',
        _vector(1),
      );
      final index = HybridChunkIndex([semantic, exact]);
      final found = index.rank('What does ABC-123 require?', _vector(0), [
        ScoredChunk(semantic, 0),
      ]);
      expect(found.first.chunk.id, exact.id);
    });

    test(
      'combines lexical and semantic agreement while retaining paraphrases',
      () {
        final generic = _chunk(
          1,
          'General application information.',
          _vector(0),
        );
        final supported = _chunk(
          2,
          'Membership renewal costs 25 dollars.',
          _vector(0),
        );
        final index = HybridChunkIndex([generic, supported]);
        final found = index.rank('Membership renewal?', _vector(0), [
          ScoredChunk(generic, 0),
          ScoredChunk(supported, 0),
        ]);
        expect(found.first.chunk.id, supported.id);
        final paraphrase = HybridChunkIndex([supported]).rank(
          'How expensive is joining?',
          _vector(0),
          [ScoredChunk(supported, 0)],
        );
        expect(paraphrase.single.chunk.id, supported.id);
      },
    );

    test(
      'filters weak unrelated hits and never includes foreign-topic candidates',
      () {
        final local = _chunk(1, 'Local handbook instructions.', _vector(1));
        final foreign = _chunk(
          2,
          'Quantum physics has the answer.',
          _vector(0),
        );
        final index = HybridChunkIndex([local]);
        expect(
          index.rank('quantum physics', _vector(0), [
            ScoredChunk(local, 1),
            ScoredChunk(foreign, 0),
          ]),
          isEmpty,
        );
      },
    );

    test('deduplicates normalized text and returns distinct evidence', () {
      final first = _chunk(1, 'Activation code is ABC-123.', _vector(0));
      final duplicate = _chunk(
        2,
        '  Activation  code is ABC-123. ',
        _vector(0),
      );
      final other = _chunk(
        3,
        'Activation expires after thirty days.',
        _vector(0),
      );
      final index = HybridChunkIndex([first, duplicate, other]);
      final found = index.rank('Activation?', _vector(0), [
        ScoredChunk(first, 0),
        ScoredChunk(duplicate, 0),
        ScoredChunk(other, 0),
      ]);
      expect(found.length, 2);
      expect(
        found
            .map((hit) => RetrievalText.normalize(hit.chunk.text))
            .toSet()
            .length,
        2,
      );
    });

    test(
      'lexical matching preserves accented text, numbers and identifiers',
      () {
        expect(RetrievalText.terms('HOW café ABC-123 in 2026?'), [
          'café',
          'abc-123',
          '2026',
        ]);
        final chunk = _chunk(1, 'The café opens in 2026.', _vector(1));
        final found = HybridChunkIndex([chunk])
            .rank('When does the café open?', _vector(0), []);
        expect(found.single.chunk.id, chunk.id);
      },
    );

    test('topic-scoped exact fallback ranks cosine distances correctly', () {
      final opposite = _chunk(1, 'Opposite.', _vector(0, value: -1));
      final orthogonal = _chunk(2, 'Orthogonal.', _vector(1));
      final nearest = _chunk(3, 'Nearest.', _vector(0));
      final found = HybridChunkIndex([opposite, orthogonal, nearest])
          .semanticSearch(_vector(0), 2);
      expect(found.map((hit) => hit.chunk.id), [3, 2]);
      expect(found.map((hit) => hit.score), [0, 1]);
    });

    test('handles empty questions, empty indexes and zero result limits', () {
      final chunk = _chunk(1, 'Some text.', _vector(0));
      expect(HybridChunkIndex([]).rank('text', _vector(0), []), isEmpty);
      expect(
        HybridChunkIndex([chunk])
            .rank(' ', _vector(0), [ScoredChunk(chunk, 0)]),
        isEmpty,
      );
      expect(
        HybridChunkIndex([chunk])
            .rank('text', _vector(0), [ScoredChunk(chunk, 0)], limit: 0),
        isEmpty,
      );
    });
  });

  group('RagContext', () {
    test('finds relevant evidence late in a chunk instead of cutting its beginning', () {
      final filler = List.filled(
        80,
        'Unrelated background material.',
      ).join(' ');
      final text =
          '$filler The activation code is ABC-123 and it expires in thirty days.';
      final excerpt = selectContextExcerpt(
        text,
        'What is the activation code?',
        150,
      );
      expect(excerpt, contains('activation code is ABC-123'));
      expect(utf8.encode(excerpt).length, lessThanOrEqualTo(150));
    });

    test(
      'shares the budget across pages and aligns source numbers after grouping',
      () {
        final first = _chunk(
          1,
          List.filled(60, 'Activation information.').join(' '),
          _vector(0),
        );
        final samePage = _chunk(2, 'Activation code is ABC-123.', _vector(0))
          ..chunkIndex = 1;
        final otherPage = _chunk(
          3,
          'Activation expires in thirty days.',
          _vector(0),
        )..pageNumber = 2;
        final selected = RagContext.build('Activation code and expiry?', [
          ScoredChunk(first, 0),
          ScoredChunk(samePage, 0),
          ScoredChunk(otherPage, 0),
        ], maxBytes: 500);
        expect(selected.context.length, 2);
        expect(selected.sources.map((source) => source.page), [1, 2]);
        expect(selected.context.first, contains('ABC-123'));
        expect(selected.context.last, contains('thirty days'));
        final prompt = PromptBuilder.buildUserMessage(
          question: 'Activation?',
          context: selected.context,
        );
        expect(prompt, contains('[1] Document, page 1:'));
        expect(prompt, contains('[2] Document, page 2:'));
        expect(prompt, isNot(contains('[3]')));
        expect(
          selected.context.fold<int>(
            0,
            (bytes, text) => bytes + utf8.encode(text).length,
          ),
          lessThanOrEqualTo(500),
        );
      },
    );

    test('retains three sources even when the first chunk is much larger', () {
      final hits = [
        for (var page = 1; page <= 3; page++)
          ScoredChunk(
            _chunk(
              page,
              '${List.filled(80, 'Background.').join(' ')} Policy for section $page is available.',
              _vector(0),
            )..pageNumber = page,
            0,
          ),
      ];
      final selected = RagContext.build(
        'Policy sections?',
        hits,
        maxBytes: 600,
      );
      expect(selected.sources.length, 3);
      expect(selected.context.every((text) => text.contains('Policy')), isTrue);
    });

    test(
      'keeps Unicode byte limits and gracefully handles oversized words',
      () {
        final value = List.filled(80, '漢字 café ').join();
        final excerpt = selectContextExcerpt(value, 'café', 75);
        expect(utf8.encode(excerpt).length, lessThanOrEqualTo(75));
        expect(excerpt, isNot(contains('\uFFFD')));
        expect(
          selectContextExcerpt(
            'abcdefghijklmnopqrst',
            'abcdefghijklmnopqrst',
            5,
          ),
          'abcde',
        );
        expect(selectContextExcerpt(value, 'café', 0), '');
        expect(RagContext.build('question', [], maxBytes: 0).context, isEmpty);
      },
    );
  });

  group('RAG native integration', () {
    test(
      'invalidates cached indexes after writes, re-indexing and deletion',
      () {
        final objectBox = ObjectBoxStore.inMemory('hybrid-cache-test');
        final repos = Repositories(objectBox);
        try {
          final topic = createTopicEntity(
            uuid: 'hybrid-topic',
            name: 'Hybrid',
            description: '',
            category: 'Work',
            iconIndex: 0,
          );
          final otherTopic = createTopicEntity(
            uuid: 'other-topic',
            name: 'Other',
            description: '',
            category: 'Work',
            iconIndex: 0,
          );
          repos.topics.put(topic);
          repos.topics.put(otherTopic);
          final first = _chunk(0, 'ABC-123 is the local code.', _vector(1))
            ..topic.target = topic;
          final foreign = _chunk(0, 'ABC-123 is the foreign code.', _vector(0))
            ..topic.target = otherTopic;
          repos.chunks.putMany([first, foreign]);
          final initial = repos.chunks.indexForTopic(topic.id);
          expect(
            identical(initial, repos.chunks.indexForTopic(topic.id)),
            isTrue,
          );
          expect(
            repos.chunks
                .searchHybrid(topic.id, 'ABC-123', _vector(0), 5)
                .single
                .chunk
                .id,
            first.id,
          );
          first.embeddingModelId = 'updated-model';
          repos.chunks.putMany([first]);
          final updated = repos.chunks.indexForTopic(topic.id);
          expect(identical(initial, updated), isFalse);
          expect(updated.modelIds, {'updated-model'});
          repos.chunks.deleteForTopic(topic.id);
          expect(repos.chunks.indexForTopic(topic.id).chunks, isEmpty);
          expect(repos.chunks.forTopic(otherTopic.id).single.id, foreign.id);
        } finally {
          objectBox.store.close();
        }
      },
    );

    test('streams a grounded answer, uses query embeddings and bounds the question', () async {
      final objectBox = ObjectBoxStore.inMemory('rag-stream-test');
      final repos = Repositories(objectBox);
      try {
        final topic = createTopicEntity(
          uuid: 'rag-topic',
          name: 'RAG',
          description: '',
          category: 'Work',
          iconIndex: 0,
        );
        repos.topics.put(topic);
        final document = DocumentEntity()
          ..uuid = 'rag-doc'
          ..name = 'manual.txt'
          ..type = 'txt'
          ..path = 'unused'
          ..createdAt = DateTime.now();
        document.topic.target = topic;
        repos.documents.put(document);
        final chunk = _chunk(0, 'The activation code is ABC-123.', _vector(0))
          ..embeddingModelId = 'fake-embedding'
          ..topic.target = topic
          ..document.target = document;
        repos.chunks.putMany([chunk]);
        final embedding = _FakeEmbedding();
        final llm = _FakeLlm();
        final rag = LocalRagService(repos, embedding, llm);
        final model = Topic(
          id: topic.uuid,
          name: topic.name,
          description: '',
          category: 'Work',
          iconIndex: 0,
          created: topic.createdAt,
        );
        final events = await rag
            .askStream(
              model,
              'Activation code? ${List.filled(200, 'details').join(' ')}',
            )
            .toList();
        expect(
          events
              .where((event) => event.message == null)
              .map((event) => event.text)
              .join(),
          llm.answer,
        );
        expect(events.last.message!.text, llm.answer);
        expect(events.last.message!.sources.single.docName, document.name);
        expect(embedding.queries.length, 1);
        expect(
          utf8.encode(embedding.queries.single).length,
          lessThanOrEqualTo(700),
        );
        expect(llm.prompts.single, contains(embedding.queries.single));
        llm.answer = PromptBuilder.noAnswer;
        expect((await rag.ask(model, 'Activation code?')).sources, isEmpty);
        await expectLater(rag.ask(model, '  '), throwsStateError);
        chunk.embeddingModelId = 'outdated-model';
        repos.chunks.putMany([chunk]);
        await expectLater(rag.ask(model, 'Activation code?'), throwsStateError);
      } finally {
        objectBox.store.close();
      }
    });
  }, skip: Platform.isWindows && !const bool.fromEnvironment('NATIVE_OBJECTBOX_TESTS'));

  group('PromptBuilder', () {
    test(
      'uses the Gemma template and includes bounded context with citations',
      () {
        final prompt = PromptBuilder.build(
          modelName: 'Gemma 2 2B',
          question: 'What happened?',
          context: ['Manual, page 2: A clear event.'],
          history: ['user: hi'],
        );
        expect(prompt, contains('<start_of_turn>system'));
        expect(prompt, contains('[1] Manual, page 2: A clear event.'));
        expect(prompt, contains("I couldn't find that in your documents."));
      },
    );
  });

  group('NFC topic payload', () {
    test(
      'reads the external type UUID before falling back to the URI record',
      () {
        const id = 'topic-uuid-123';
        final message = NdefMessage(
          records: [
            NdefRecord(
              typeNameFormat: TypeNameFormat.external,
              type: Uint8List.fromList('tapat.ai:topic'.codeUnits),
              identifier: Uint8List(0),
              payload: Uint8List.fromList(id.codeUnits),
            ),
            NdefRecord(
              typeNameFormat: TypeNameFormat.wellKnown,
              type: Uint8List.fromList([0x55]),
              identifier: Uint8List(0),
              payload: Uint8List.fromList([0, ...'tapat://kb/$id'.codeUnits]),
            ),
          ],
        );
        expect(NativeNfcService.parseTopicId(message), id);
        expect(NativeNfcService.parseTopicId(null), isNull);
      },
    );
  });
}

List<double> _vector(int axis, {double value = 1}) =>
    List.generate(384, (i) => i == axis ? value : 0);

ChunkEntity _chunk(int id, String text, List<double> vector) => ChunkEntity()
  ..id = id
  ..text = text
  ..vector = vector
  ..pageNumber = 1
  ..embeddingModelId = 'test-model';

ModelEntity _embeddingModel({
  String uuid = 'embedding-model',
  String name = 'BGE Small English v1.5',
}) => ModelEntity()
  ..uuid = uuid
  ..name = name
  ..kind = 'embedding'
  ..dimensions = 384;

class _FakeEmbeddingBackend implements EmbeddingBackend {
  _FakeEmbeddingBackend({this.dimensions = 384});
  @override
  final int dimensions;
  final calls = <(List<String>, String)>[];
  bool disposed = false;
  bool omitLast = false;
  List<double>? vectorOverride;
  Completer<void>? gate;
  @override
  Future<List<List<double>>> embedBatch(
    List<String> texts, {
    String prefix = '',
  }) async {
    calls.add((List.of(texts), prefix));
    if (gate != null) await gate!.future;
    return List.generate(
      texts.length - (omitLast ? 1 : 0),
      (_) => List.of(vectorOverride ?? _vector(0)),
    );
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _FakeEmbedding implements EmbeddingEngine {
  final queries = <String>[];
  @override
  int get dimensions => 384;
  @override
  String? get modelId => 'fake-embedding';
  @override
  Future<void> load(ModelEntity model) async {}
  @override
  Future<void> unload() async {}
  @override
  Future<List<double>> embed(String text) async => _vector(0);
  @override
  Future<List<double>> embedQuery(String text) {
    queries.add(text);
    return embed(text);
  }

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async =>
      List.generate(texts.length, (_) => _vector(0));
}

class _FakeLlm implements LlmEngine {
  String answer = 'The activation code is ABC-123 [1].';
  final prompts = <String>[];
  @override
  Future<void> load(ModelEntity model) async {}
  @override
  Future<void> unload() async {}
  @override
  Future<void> stop() async {}
  @override
  Stream<String> generate(
    String prompt, {
    String? systemPrompt,
    GenParams params = const GenParams(),
  }) async* {
    prompts.add(prompt);
    yield answer.substring(0, 5);
    yield answer.substring(5);
  }
}

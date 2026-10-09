import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapat_ai/app.dart';
import 'package:tapat_ai/const/app_route.dart';
import 'package:tapat_ai/core/services/mock_service.dart';
import 'package:tapat_ai/core/services/rag_service.dart';
import 'package:tapat_ai/data/ai/engines.dart';
import 'package:tapat_ai/data/entities/entities.dart';
import 'package:tapat_ai/data/objectbox_store.dart';
import 'package:tapat_ai/data/repositories.dart';
import 'package:tapat_ai/domain/models/doc_model.dart';
import 'package:tapat_ai/domain/models/ingest_progress.dart';
import 'package:tapat_ai/domain/models/message_model.dart';
import 'package:tapat_ai/domain/models/rag_stream_event.dart';
import 'package:tapat_ai/domain/models/source_ref_model.dart';
import 'package:tapat_ai/domain/models/topic_model.dart';
import 'package:tapat_ai/presentation/chat/chat_screen.dart';
import 'package:tapat_ai/presentation/topic/topic_screen.dart';
import 'package:tapat_ai/provider/app_provider.dart';

void main() {
  testWidgets('chat screen displays the selected topic and input', (tester) async {
    final fixture = await _createFixture();
    addTearDown(() async {
      fixture.state.dispose();
      fixture.store.store.close();
    });
    final topic = fixture.state.createTopic('Study Notes', '', 0);
    await tester.pumpWidget(AppScope(
      notifier: fixture.state,
      child: MaterialApp(home: ChatScreen(topicId: topic.id)),
    ));
    expect(find.text('Study Notes'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  }, skip: Platform.isWindows);

  testWidgets('processing screen shows the five ingestion stages and progress', (tester) async {
    final fixture = await _createFixture();
    addTearDown(() async {
      fixture.state.dispose();
      fixture.store.store.close();
    });
    final topic = fixture.state.createTopic('Study Notes', '', 0);
    final doc = Doc('doc-1', 'notes.txt', DocType.txt, 3, .1);
    await tester.pumpWidget(AppScope(
      notifier: fixture.state,
      child: MaterialApp(home: UploadProcessingScreen(
        args: ProcessingArgs(topic.id, [doc]),
      )),
    ));
    await tester.pump();
    expect(find.text('Extracting text...'), findsOneWidget);
    expect(find.text('Creating text chunks...'), findsOneWidget);
    expect(find.text('Generating embeddings...'), findsOneWidget);
    expect(find.text('Saving to local database...'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
  }, skip: Platform.isWindows);

  testWidgets('a background answer is saved and its notification opens the chat', (tester) async {
    final rag = _ControlledRag();
    final state = await _createMemoryState(rag);
    final topic = state.createTopic('Study Notes', '', 0);
    final navigator = await _openChat(tester, state, topic.id);
    await _sendQuestion(tester, 'What do my notes say?');
    rag.streams.single.add(const RagStreamEvent.token('Working'));
    await tester.pump();
    navigator.popUntil((route) => route.settings.name == Routes.shell);
    await _pumpNavigation(tester);
    expect(find.byType(ChatScreen), findsNothing);
    final sentAt = DateTime(2026, 9, 1, 12);
    rag.streams.single.add(RagStreamEvent.complete(Message(
      'A ready answer.', false, [SourceRef('notes.txt', 2)], sentAt,
    )));
    unawaited(rag.streams.single.close());
    await _pumpNavigation(tester);
    state.chats.remove(topic.id);
    final messages = state.chatOf(topic.id);
    expect(messages.map((message) => message.text), ['What do my notes say?', 'A ready answer.']);
    expect(messages.last.sentAt, sentAt);
    expect(messages.last.sources.single.docName, 'notes.txt');
    expect(find.text('Your answer for Study Notes is ready.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('View answer'), findsOneWidget);
    await tester.tap(find.text('View answer'));
    await _pumpNavigation(tester);
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.text('A ready answer.'), findsOneWidget);
    expect(find.text('Your answer for Study Notes is ready.'), findsNothing);
  });

  testWidgets('reopening a running chat restores progress and other chats cannot interrupt it', (tester) async {
    final rag = _ControlledRag();
    final state = await _createMemoryState(rag);
    final topic = state.createTopic('Study Notes', '', 0);
    final other = state.createTopic('Other Notes', '', 1);
    final navigator = await _openChat(tester, state, topic.id);
    await _sendQuestion(tester, 'Explain my notes.');
    rag.streams.single.add(const RagStreamEvent.token('The first'));
    await tester.pump();
    await tester.tap(find.text('Explore app'));
    await _pumpNavigation(tester);
    expect(find.byType(ChatScreen), findsNothing);
    rag.streams.single.add(const RagStreamEvent.token(' part.'));
    await tester.pump();
    expect(state.answerProgress.value, 'The first part.');
    unawaited(navigator.pushNamed(Routes.chat, arguments: other.id));
    await _pumpNavigation(tester);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(state.askQuestion(other.id, 'Another question?'), isFalse);
    expect(state.chatOf(other.id), isEmpty);
    expect(rag.questions, ['Explain my notes.']);
    await tester.tap(find.text('View progress'));
    await _pumpNavigation(tester);
    expect(find.text('The first part.'), findsOneWidget);
    expect(find.byTooltip('Stop answer'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Stop answer'));
      await state.stopAnswer(topic.id);
    });
    await tester.pump();
    expect(state.isGenerating, isFalse);
  });

  testWidgets('a saved question can be regenerated in the background after reopening', (tester) async {
    final rag = _ControlledRag();
    final state = await _createMemoryState(rag);
    final topic = state.createTopic('Study Notes', '', 0);
    state.addMessage(topic.id, Message('Saved question?', true));
    state.addMessage(topic.id, Message('Old answer.', false));
    state.chats.clear();
    await _openChat(tester, state, topic.id);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await _pumpNavigation(tester);
    await tester.tap(find.text('Regenerate answer'));
    await _pumpNavigation(tester);
    expect(rag.questions, ['Saved question?']);
    expect(state.chatOf(topic.id).length, 1);
    await tester.tap(find.text('Explore app'));
    await _pumpNavigation(tester);
    rag.streams.single.add(RagStreamEvent.complete(Message('New answer.', false)));
    unawaited(rag.streams.single.close());
    await _pumpNavigation(tester);
    expect(state.chatOf(topic.id).map((message) => message.text), ['Saved question?', 'New answer.']);
    expect(find.text('Your answer for Study Notes is ready.'), findsOneWidget);
  });

  test('stopping keeps the engine locked until cancellation and never announces a late answer', () async {
    final rag = _ControlledRag();
    final stopGate = Completer<void>();
    final llm = _TestLlamaEngine()..stopGate = stopGate;
    final state = await _createMemoryState(rag, llm: llm);
    final notices = <ChatNotice>[];
    final subscription = state.chatNotices.listen(notices.add);
    addTearDown(subscription.cancel);
    final topic = state.createTopic('Study Notes', '', 0);
    state.askQuestion(topic.id, 'Stop this question.');
    rag.streams.single.add(const RagStreamEvent.token('Partial answer'));
    await Future<void>.delayed(Duration.zero);
    final stopping = state.stopAnswer(topic.id);
    expect(state.isStopping, isTrue);
    expect(state.askQuestion(topic.id, 'Too early?'), isFalse);
    rag.streams.single.add(RagStreamEvent.complete(Message('Late answer.', false)));
    await rag.streams.single.close();
    expect(notices, isEmpty);
    stopGate.complete();
    await stopping;
    expect(llm.stopCount, 1);
    expect(state.isGenerating, isFalse);
    expect(state.answerProgress.value, isEmpty);
    expect(state.chatOf(topic.id).map((message) => message.text), ['Stop this question.']);
    expect(state.askQuestion(topic.id, 'New question?'), isTrue);
    rag.streams.last.add(RagStreamEvent.complete(Message('New answer.', false)));
    await rag.streams.last.close();
    await Future<void>.delayed(Duration.zero);
    expect(notices.single.error, isNull);
    expect(state.chatOf(topic.id).last.text, 'New answer.');
  });

  testWidgets('background failures notify the user without reporting success', (tester) async {
    final rag = _ControlledRag();
    final state = await _createMemoryState(rag);
    final topic = state.createTopic('Study Notes', '', 0);
    await _openChat(tester, state, topic.id);
    await _sendQuestion(tester, 'A failing question.');
    await tester.tap(find.text('Explore app'));
    await _pumpNavigation(tester);
    rag.streams.single.addError(StateError('Model failed.'));
    await _pumpNavigation(tester);
    expect(state.isGenerating, isFalse);
    expect(state.chatOf(topic.id).length, 1);
    expect(find.textContaining('Model failed.'), findsOneWidget);
    expect(find.text('View answer'), findsNothing);
    await tester.tap(find.text('Open chat'));
    await _pumpNavigation(tester);
    expect(find.byType(ChatScreen), findsOneWidget);
  });

  test('a stream without a final answer reports failure and releases the engine', () async {
    final rag = _ControlledRag();
    final state = await _createMemoryState(rag);
    final notices = <ChatNotice>[];
    final subscription = state.chatNotices.listen(notices.add);
    addTearDown(subscription.cancel);
    final topic = state.createTopic('Study Notes', '', 0);
    expect(state.askQuestion(topic.id, 'No final answer?'), isTrue);
    rag.streams.single.add(const RagStreamEvent.token('Incomplete'));
    await rag.streams.single.close();
    await Future<void>.delayed(Duration.zero);
    expect(state.isGenerating, isFalse);
    expect(state.answerProgress.value, isEmpty);
    expect(state.chatOf(topic.id).length, 1);
    expect(notices.single.error, contains('did not return an answer'));
  });

  for (final action in ['clear chat', 'clear all chats', 'delete topic']) {
    test('$action cancels the answer without recreating deleted history', () async {
      final rag = _ControlledRag();
      final state = await _createMemoryState(rag);
      final topic = state.createTopic('Study Notes', '', 0);
      final notices = <ChatNotice>[];
      final subscription = state.chatNotices.listen(notices.add);
      addTearDown(subscription.cancel);
      state.askQuestion(topic.id, 'Do not save a late answer.');
      switch (action) {
        case 'clear chat': state.clearChat(topic.id);
        case 'clear all chats': state.clearChats();
        case 'delete topic': state.deleteTopic(topic.id);
      }
      rag.streams.single.add(RagStreamEvent.complete(Message('Late answer.', false)));
      await rag.streams.single.close();
      await Future<void>.delayed(Duration.zero);
      expect(state.isGenerating, isFalse);
      expect(state.chatOf(topic.id), isEmpty);
      expect(notices, isEmpty);
    });
  }

  test('pausing and resuming preserve inference and idle background models are released', () async {
    final rag = _ControlledRag();
    final llm = _TestLlamaEngine();
    final state = await _createMemoryState(rag, llm: llm);
    final embedding = state.embeddingEngine as _TestEmbeddingEngine;
    final topic = state.createTopic('Study Notes', '', 0);
    state.askQuestion(topic.id, 'Keep working.');
    state.didChangeAppLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);
    state.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(state.isGenerating, isTrue);
    expect(llm.unloadCount, 0);
    expect(embedding.unloadCount, 0);
    expect(llm.stopCount, 0);
    state.didChangeAppLifecycleState(AppLifecycleState.paused);
    rag.streams.single.add(RagStreamEvent.complete(Message('Finished in the background.', false)));
    await rag.streams.single.close();
    await Future<void>.delayed(Duration.zero);
    expect(state.chatOf(topic.id).last.text, 'Finished in the background.');
    expect(llm.unloadCount, 1);
    expect(embedding.unloadCount, 1);
  });

  test('memory pressure cancels safely and reports why the answer stopped', () async {
    final rag = _ControlledRag();
    final llm = _TestLlamaEngine();
    final state = await _createMemoryState(rag, llm: llm);
    final notices = <ChatNotice>[];
    final subscription = state.chatNotices.listen(notices.add);
    addTearDown(subscription.cancel);
    final topic = state.createTopic('Study Notes', '', 0);
    state.askQuestion(topic.id, 'An interrupted question.');
    state.didHaveMemoryPressure();
    await Future<void>.delayed(Duration.zero);
    expect(state.isGenerating, isFalse);
    expect(llm.stopCount, 1);
    expect(llm.unloadCount, 1);
    expect(notices.single.error, contains('low on memory'));
    expect(state.chatOf(topic.id).length, 1);
  });

  testWidgets('model changes are disabled during an answer but browsing and imports remain available', (tester) async {
    final rag = _ControlledRag();
    final repositories = _MemoryRepositories();
    final state = await _createMemoryState(rag, repositories: repositories);
    final topic = state.createTopic('Study Notes', '', 0);
    final navigator = await _openChat(tester, state, topic.id);
    repositories.models.rows.addAll([
      ModelEntity()..id = 1..uuid = 'llm'..name = 'Installed language model'..kind = 'llm',
      ModelEntity()..id = 2..uuid = 'embedding'..name = 'Installed embedding model'..kind = 'embedding'..isActive = true,
    ]);
    repositories.chunks.rows.add(ChunkEntity()
      ..text = 'A document chunk.'
      ..embeddingModelId = 'outdated-model'
      ..topic.target = repositories.topics.byUuid(topic.id));
    await _sendQuestion(tester, 'Continue while browsing models.');
    unawaited(navigator.pushNamed(Routes.models));
    await _pumpNavigation(tester);
    await tester.scrollUntilVisible(find.text('Re-index'), 150, scrollable: find.byType(Scrollable).first);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Use')).onPressed, isNull);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Re-index')).onPressed, isNull);
    for (final menu in tester.widgetList<PopupMenuButton<String>>(find.byType(PopupMenuButton<String>))) {
      expect(menu.enabled, isFalse);
    }
    await tester.scrollUntilVisible(find.text('Import'), -150, scrollable: find.byType(Scrollable).first);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Import')).onPressed, isNotNull);
    await tester.runAsync(() => state.stopAnswer(topic.id));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Use'), 150, scrollable: find.byType(Scrollable).first);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Use')).onPressed, isNotNull);
  });

  testWidgets('viewing a ready answer in its current chat does not duplicate the route', (tester) async {
    final rag = _ControlledRag();
    final state = await _createMemoryState(rag);
    final topic = state.createTopic('Study Notes', '', 0);
    await _openChat(tester, state, topic.id);
    final route = ModalRoute.of(tester.element(find.byType(ChatScreen)));
    await _sendQuestion(tester, 'Finish here.');
    rag.streams.single.add(RagStreamEvent.complete(Message('Ready here.', false)));
    unawaited(rag.streams.single.close());
    await _pumpNavigation(tester);
    await tester.tap(find.text('View answer'));
    await _pumpNavigation(tester);
    expect(ModalRoute.of(tester.element(find.byType(ChatScreen))), same(route));
  });

  test('disposing app state cancels outstanding work without saving or notifying', () async {
    final rag = _ControlledRag();
    final state = await _createMemoryState(rag, disposeAtTearDown: false);
    addTearDown(rag.dispose);
    final topic = state.createTopic('Study Notes', '', 0);
    state.askQuestion(topic.id, 'Do not finish after disposal.');
    state.dispose();
    rag.streams.single.add(RagStreamEvent.complete(Message('Late answer.', false)));
    await rag.streams.single.close();
    await Future<void>.delayed(Duration.zero);
    expect(state.chatOf(topic.id).length, 1);
  });
}

Future<NavigatorState> _openChat(WidgetTester tester, AppState state, String topicId) async {
  await tester.pumpWidget(TapatApp(state: state));
  await tester.pump(const Duration(milliseconds: 2300));
  await _pumpNavigation(tester);
  final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
  unawaited(navigator.pushNamed(Routes.chat, arguments: topicId));
  await _pumpNavigation(tester);
  return navigator;
}

Future<void> _pumpNavigation(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _sendQuestion(WidgetTester tester, String question) async {
  await tester.enterText(find.byType(TextField), question);
  await tester.testTextInput.receiveAction(TextInputAction.send);
  await tester.pump();
}

Future<AppState> _createMemoryState(_ControlledRag rag, {
  _TestLlamaEngine? llm,
  _MemoryRepositories? repositories,
  bool disposeAtTearDown = true,
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({'onboarded': true});
  FlutterSecureStorage.setMockInitialValues({});
  final state = AppState(
    rag: rag,
    nfc: MockNfcService(),
    picker: MockDocumentPicker(),
    prefs: await SharedPreferences.getInstance(),
    repositories: repositories ?? _MemoryRepositories(),
    embeddingEngine: _TestEmbeddingEngine(),
    llmEngine: llm ?? _TestLlamaEngine(),
    useMocks: false,
  );
  if (disposeAtTearDown) {
    addTearDown(() {
      state.dispose();
      rag.dispose();
    });
  }
  return state;
}

class _TestLlamaEngine extends OnDeviceLlamaEngine {
  bool loaded = true;
  int stopCount = 0;
  int unloadCount = 0;
  Completer<void>? stopGate;
  @override
  bool get isLoaded => loaded;
  @override
  Future<void> stop() async {
    stopCount++;
    await stopGate?.future;
  }

  @override
  Future<void> unload() async {
    unloadCount++;
    loaded = false;
  }
}

class _TestEmbeddingEngine extends OnDeviceEmbeddingEngine {
  bool loaded = true;
  int unloadCount = 0;
  @override
  bool get isLoaded => loaded;
  @override
  int get dimensions => loaded ? 384 : 0;
  @override
  Future<void> unload() async {
    unloadCount++;
    loaded = false;
  }
}

class _ControlledRag extends RagService {
  final streams = <StreamController<RagStreamEvent>>[];
  final questions = <String>[];
  @override
  Stream<RagStreamEvent> askStream(Topic topic, String question) {
    questions.add(question);
    final controller = StreamController<RagStreamEvent>();
    streams.add(controller);
    return controller.stream;
  }

  @override
  Future<Message> ask(Topic topic, String question) => throw UnsupportedError('Use askStream.');
  @override
  Stream<IngestProgress> ingest(Topic topic, List<Doc> docs) => const Stream.empty();

  void dispose() {
    for (final stream in streams) {
      if (!stream.isClosed) unawaited(stream.close());
    }
  }
}

class _RepositoryStub {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryRepositories extends _RepositoryStub implements Repositories {
  @override
  final _MemoryTopics topics = _MemoryTopics();
  @override
  final _MemoryDocuments documents = _MemoryDocuments();
  @override
  final _MemoryChunks chunks = _MemoryChunks();
  @override
  final _MemoryChats chats = _MemoryChats();
  @override
  final _MemoryModels models = _MemoryModels();
  @override
  final _MemorySettings settings = _MemorySettings();
}

class _MemoryTopics extends _RepositoryStub implements TopicRepository {
  final rows = <TopicEntity>[];
  @override
  List<TopicEntity> getAll() => List.of(rows);
  @override
  TopicEntity? byUuid(String uuid) => rows.where((row) => row.uuid == uuid).firstOrNull;
  @override
  TopicEntity put(TopicEntity topic) {
    if (topic.id == 0) {
      topic.id = rows.length + 1;
      rows.add(topic);
    }
    return topic;
  }

  @override
  Stream<List<TopicEntity>> watch() => const Stream.empty();
  @override
  void deleteCascade(String uuid, Repositories repos) {
    final topic = byUuid(uuid);
    if (topic != null) repos.chats.clear(topic.id);
    rows.removeWhere((row) => row.uuid == uuid);
  }
}

class _MemoryDocuments extends _RepositoryStub implements DocumentRepository {
  @override
  List<DocumentEntity> forTopic(int topicId) => [];
  @override
  List<DocumentEntity> getAll() => [];
}

class _MemoryChunks extends _RepositoryStub implements ChunkRepository {
  final rows = <ChunkEntity>[];
  @override
  void clearCache() {}
  @override
  List<ChunkEntity> forTopic(int topicId) => rows.where((row) => row.topic.target?.id == topicId).toList();
}

class _MemoryChats extends _RepositoryStub implements ChatRepository {
  final rows = <ChatMessageEntity>[];
  int _nextId = 1;
  @override
  List<ChatMessageEntity> forTopic(int topicId) => rows.where((row) => row.topic.target?.id == topicId).toList();
  @override
  void add(ChatMessageEntity message) {
    message.id = _nextId++;
    rows.add(message);
  }

  @override
  void remove(int id) => rows.removeWhere((row) => row.id == id);
  @override
  void clear(int topicId) => rows.removeWhere((row) => row.topic.target?.id == topicId);
}

class _MemoryModels extends _RepositoryStub implements ModelRepository {
  final rows = <ModelEntity>[];
  @override
  List<ModelEntity> getAll() => List.of(rows);
  @override
  ModelEntity? active(String kind) => rows.where((row) => row.kind == kind && row.isActive).firstOrNull;
}

class _MemorySettings extends _RepositoryStub implements SettingsRepository {
  final values = <String, String>{};
  @override
  String? get(String key) => values[key];
  @override
  void set(String key, String value) => values[key] = value;
}

Future<_Fixture> _createFixture() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final store = ObjectBoxStore.inMemory('widget-${DateTime.now().microsecondsSinceEpoch}');
  final repositories = Repositories(store);
  final state = AppState(
    rag: MockRagService(),
    nfc: MockNfcService(),
    picker: MockDocumentPicker(),
    prefs: await SharedPreferences.getInstance(),
    repositories: repositories,
    embeddingEngine: OnDeviceEmbeddingEngine(),
    llmEngine: OnDeviceLlamaEngine(),
    useMocks: true,
  );
  return _Fixture(store, state);
}

class _Fixture {
  const _Fixture(this.store, this.state);
  final ObjectBoxStore store;
  final AppState state;
}

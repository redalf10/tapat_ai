import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:objectbox/objectbox.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapat_ai/app.dart';
import 'package:tapat_ai/const/app_route.dart';
import 'package:tapat_ai/core/services/mock_service.dart';
import 'package:tapat_ai/core/services/rag_service.dart';
import 'package:tapat_ai/data/ai/engines.dart';
import 'package:tapat_ai/data/ai/local_rag_service.dart';
import 'package:tapat_ai/data/document_library_service.dart';
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
import 'package:tapat_ai/presentation/topic/document_editor_screen.dart';
import 'package:tapat_ai/provider/app_provider.dart';

void main() {
  testWidgets('Add Document offers upload and creation without loaded models', (tester) async {
    final state = await _createMemoryState(_ControlledRag(), llm: _TestLlamaEngine()..loaded = false);
    (state.embeddingEngine as _TestEmbeddingEngine).loaded = false;
    final topic = state.createTopic('Writing', '', 0);
    await tester.pumpWidget(AppScope(
      notifier: state,
      child: MaterialApp(onGenerateRoute: AppRouter.generate, home: KnowledgeDetailScreen(topicId: topic.id)),
    ));
    await tester.tap(find.text('Add Document'));
    await _pumpNavigation(tester);
    expect(find.text('Upload existing documents'), findsOneWidget);
    expect(find.text('Create from Scratch'), findsOneWidget);
  });

  test('document creation saves UTF-8 text without models and updates RAG on edit and delete', () async {
    final temp = await Directory.systemTemp.createTemp('tapat-created-document');
    addTearDown(() => temp.delete(recursive: true));
    final repositories = _MemoryRepositories();
    final state = await _createMemoryState(_ControlledRag(), repositories: repositories,
      documentLibrary: DocumentLibraryService(repositories, documentDirectory: () async => temp));
    final embedding = state.embeddingEngine as _TestEmbeddingEngine;
    embedding.loaded = false;
    final topic = state.createTopic('Notes', '', 0);
    final saved = await state.saveTextDocument(topic.id, title: 'Water cycle', content: 'Evaporation turns café water into vapour.', aiAssisted: true);
    expect(saved.name, 'Water cycle.txt');
    expect(saved.origin, 'created');
    expect(saved.aiAssisted, isTrue);
    expect(saved.isIndexed, isFalse);
    expect(await state.documentLibrary.readText(saved.id), 'Evaporation turns café water into vapour.');
    expect(state.byId(topic.id).docs.single.id, saved.id);
    embedding.loaded = true;
    await state.indexDocument(saved.id).toList();
    expect(state.byId(topic.id).docs.single.isIndexed, isTrue);
    final topicRow = repositories.topics.byUuid(topic.id)!;
    final previousIndex = repositories.chunks.indexForTopic(topicRow.id);
    final rag = LocalRagService(repositories, embedding, state.llmEngine);
    final answer = await rag.ask(state.byId(topic.id), 'What is evaporation?');
    expect(answer.sources.single.docName, saved.name);
    expect((state.llmEngine as _TestLlamaEngine).prompts.last, contains('Evaporation turns'));
    final updated = await state.saveTextDocument(topic.id, title: 'Updated notes', content: 'Condensation forms clouds from water vapour.',
      documentId: saved.id, expectedSha256: saved.contentSha256);
    expect(updated.id, saved.id);
    expect(updated.isIndexed, isFalse);
    expect(await File(saved.path).exists(), isFalse);
    expect(repositories.chunks.indexForTopic(topicRow.id).chunks, isEmpty);
    expect(identical(previousIndex, repositories.chunks.indexForTopic(topicRow.id)), isFalse);
    await state.indexDocument(saved.id).toList();
    await rag.ask(state.byId(topic.id), 'What forms clouds?');
    final prompt = (state.llmEngine as _TestLlamaEngine).prompts.last;
    expect(prompt, contains('Condensation forms clouds'));
    expect(prompt, isNot(contains('Evaporation turns')));
    await expectLater(state.saveTextDocument(topic.id, title: 'Stale', content: 'Do not overwrite.',
      documentId: saved.id, expectedSha256: saved.contentSha256), throwsStateError);
    expect(await state.documentLibrary.readText(saved.id), 'Condensation forms clouds from water vapour.');
    state.removeDoc(topic.id, saved.id);
    expect(state.byId(topic.id).docs, isEmpty);
    expect(repositories.chunks.indexForTopic(topicRow.id).chunks, isEmpty);
    expect(await File(updated.path).exists(), isFalse);
  });

  test('document indexing failure preserves saved content and can be retried offline', () async {
    final temp = await Directory.systemTemp.createTemp('tapat-index-failure');
    addTearDown(() => temp.delete(recursive: true));
    final repositories = _MemoryRepositories();
    final state = await _createMemoryState(_ControlledRag(), repositories: repositories,
      documentLibrary: DocumentLibraryService(repositories, documentDirectory: () async => temp));
    final topic = state.createTopic('Notes', '', 0);
    final saved = await state.saveTextDocument(topic.id, title: 'Notes', content: 'Content must survive an unavailable embedding model.');
    final embedding = state.embeddingEngine as _TestEmbeddingEngine;
    embedding.failEmbedding = true;
    await expectLater(state.indexDocument(saved.id).toList(), throwsStateError);
    expect(state.byId(topic.id).docs.single.status, 'saved');
    expect(await state.documentLibrary.readText(saved.id), contains('Content must survive'));
    expect(repositories.chunks.rows, isEmpty);
    expect(state.isIndexing, isFalse);
    embedding.failEmbedding = false;
    await state.indexDocument(saved.id).toList();
    expect(state.byId(topic.id).docs.single.isIndexed, isTrue);
  });

  for (final action in ['edit', 'delete', 'move']) {
    test('document $action during indexing cannot commit stale chunks', () async {
      final temp = await Directory.systemTemp.createTemp('tapat-index-race');
      addTearDown(() => temp.delete(recursive: true));
      final repositories = _MemoryRepositories();
      final library = DocumentLibraryService(repositories, documentDirectory: () async => temp);
      final state = await _createMemoryState(_ControlledRag(), repositories: repositories, documentLibrary: library);
      final topic = state.createTopic('Notes', '', 0);
      final saved = await state.saveTextDocument(topic.id, title: 'Notes', content: 'Original content.');
      final embedding = state.embeddingEngine as _TestEmbeddingEngine
        ..embeddingGate = Completer<void>()
        ..embeddingStarted = Completer<void>();
      final check = expectLater(state.indexDocument(saved.id).toList(), throwsStateError);
      await embedding.embeddingStarted!.future;
      if (action == 'edit') {
        await library.saveText(topicId: topic.id, title: 'Notes', content: 'Replacement content.',
          documentId: saved.id, expectedSha256: saved.contentSha256);
      }
      if (action == 'delete') state.removeDoc(topic.id, saved.id);
      if (action == 'move') state.moveDocument(saved.id, state.createTopic('Other', '', 1).id);
      embedding.embeddingGate!.complete();
      await check;
      expect(repositories.chunks.rows, isEmpty);
      if (action == 'edit') {
        expect(await library.readText(saved.id), 'Replacement content.');
        expect(repositories.documents.byUuid(saved.id)!.status, 'saved');
      }
    });
  }

  test('document indexing cancellation leaves the saved file unindexed', () async {
    final temp = await Directory.systemTemp.createTemp('tapat-index-cancel');
    addTearDown(() => temp.delete(recursive: true));
    final repositories = _MemoryRepositories();
    final state = await _createMemoryState(_ControlledRag(), repositories: repositories,
      documentLibrary: DocumentLibraryService(repositories, documentDirectory: () async => temp));
    final topic = state.createTopic('Notes', '', 0);
    final saved = await state.saveTextDocument(topic.id, title: 'Notes', content: 'Keep this saved text.');
    final cancelled = Completer<void>();
    late StreamSubscription<IngestProgress> subscription;
    subscription = state.indexDocument(saved.id).listen((progress) {
      if (progress.stage == 0) unawaited(subscription.cancel().then((_) => cancelled.complete()));
    });
    await cancelled.future;
    expect(await state.documentLibrary.readText(saved.id), 'Keep this saved text.');
    expect(state.byId(topic.id).docs.single.status, 'saved');
    expect(repositories.chunks.rows, isEmpty);
    expect(state.isIndexing, isFalse);
  });

  test('document text generation only needs the language model and cancels without changing stored text', () async {
    final llm = _TestLlamaEngine();
    final state = await _createMemoryState(_ControlledRag(), llm: llm);
    (state.embeddingEngine as _TestEmbeddingEngine).loaded = false;
    expect(await state.generateDocumentText('Create study notes.'), llm.generatedText);
    llm.generationGate = Completer<void>();
    final pending = state.generateDocumentText('Write a tutorial.');
    final check = expectLater(pending, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    expect(state.isGenerating, isTrue);
    expect(state.askQuestion(state.createTopic('Notes', '', 0).id, 'Cannot interrupt.'), isFalse);
    await state.stopLocalGeneration();
    await check;
    expect(state.isGenerating, isFalse);
    expect(state.repositories.documents.getAll(), isEmpty);
  });

  testWidgets('document generated drafts are editable and replacement requires confirmation', (tester) async {
    final llm = _TestLlamaEngine();
    final state = await _createMemoryState(_ControlledRag(), llm: llm);
    final topic = state.createTopic('Writing', '', 0);
    await tester.pumpWidget(AppScope(notifier: state,
      child: MaterialApp(home: DocumentEditorScreen(args: DocumentEditorArgs(topic.id)))));
    final content = find.byKey(const ValueKey('document-content'));
    await tester.enterText(content, 'My original content.');
    final contentController = tester.widget<TextField>(content).controller!;
    await tester.tap(find.text('Generate Text'));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('document-prompt')));
    await tester.enterText(find.byKey(const ValueKey('document-prompt')), 'Write study notes.');
    await tester.ensureVisible(find.text('Generate draft'));
    await tester.tap(find.text('Generate draft'));
    await tester.pump();
    await tester.pump();
    expect(contentController.text, 'My original content.');
    final draft = find.byKey(const ValueKey('generated-draft'));
    expect(tester.widget<TextField>(draft).controller!.text, llm.generatedText);
    await tester.enterText(draft, 'Reviewed draft.');
    await tester.ensureVisible(find.text('Replace content'));
    await tester.tap(find.text('Replace content'));
    await _pumpNavigation(tester);
    expect(find.text('Replace document content?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
    await _pumpNavigation(tester);
    expect(contentController.text, 'My original content.');
    await tester.tap(find.text('Replace content'));
    await _pumpNavigation(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Replace'));
    await _pumpNavigation(tester);
    expect(contentController.text, 'Reviewed draft.');
    expect(find.byKey(const ValueKey('generated-draft')), findsNothing);
    expect(state.byId(topic.id).docs, isEmpty);
  });

  testWidgets('document generation displays loading and appends without overwriting user text', (tester) async {
    final llm = _TestLlamaEngine()..generationGate = Completer<void>();
    final state = await _createMemoryState(_ControlledRag(), llm: llm);
    final topic = state.createTopic('Writing', '', 0);
    await tester.pumpWidget(AppScope(notifier: state,
      child: MaterialApp(home: DocumentEditorScreen(args: DocumentEditorArgs(topic.id)))));
    final content = find.byKey(const ValueKey('document-content'));
    await tester.enterText(content, 'Keep my writing.');
    final contentController = tester.widget<TextField>(content).controller!;
    await tester.tap(find.text('Generate Text'));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('document-prompt')));
    await tester.enterText(find.byKey(const ValueKey('document-prompt')), 'Explain a process.');
    await tester.ensureVisible(find.text('Generate draft'));
    await tester.tap(find.text('Generate draft'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Stop generation'), findsOneWidget);
    expect(contentController.text, 'Keep my writing.');
    llm.generationGate!.complete();
    await tester.pump();
    await tester.pump();
    await tester.ensureVisible(find.text('Append'));
    await tester.tap(find.text('Append'));
    await tester.pump();
    expect(contentController.text, 'Keep my writing.\n\n${llm.generatedText}');
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('diagram requests keep the explanation visible while generating a visual', (tester) async {
    final rag = _ControlledRag();
    final llm = _TestLlamaEngine()..generationGate = Completer<void>();
    final state = await _createMemoryState(rag, llm: llm);
    final topic = state.createTopic('Authentication', '', 0);
    await _openChat(tester, state, topic.id);
    await _sendQuestion(tester, 'Create a flowchart showing how login authentication works.');
    rag.streams.single.add(RagStreamEvent.complete(Message('Check the credentials, then allow or deny access.', false)));
    unawaited(rag.streams.single.close());
    await _pumpNavigation(tester);
    expect(find.text('Check the credentials, then allow or deny access.'), findsOneWidget);
    expect(find.text('Generating diagram...'), findsOneWidget);
  });

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
  }, skip: Platform.isWindows && !const bool.fromEnvironment('NATIVE_OBJECTBOX_TESTS'));

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
  }, skip: Platform.isWindows && !const bool.fromEnvironment('NATIVE_OBJECTBOX_TESTS'));

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
  DocumentLibraryService? documentLibrary,
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
    documentLibrary: documentLibrary,
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
  Completer<void>? generationGate;
  String generatedText = 'Locally generated study notes.';
  final prompts = <String>[];
  @override
  bool get isLoaded => loaded;
  @override
  Stream<String> generate(String prompt, {String? systemPrompt, GenParams params = const GenParams()}) async* {
    prompts.add(prompt);
    await generationGate?.future;
    yield generatedText;
  }
  @override
  Future<void> stop() async {
    stopCount++;
    await stopGate?.future;
    final gate = generationGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<void> unload() async {
    unloadCount++;
    loaded = false;
  }
}

class _TestEmbeddingEngine extends OnDeviceEmbeddingEngine {
  bool loaded = true;
  bool failEmbedding = false;
  int unloadCount = 0;
  Completer<void>? embeddingGate;
  Completer<void>? embeddingStarted;
  @override
  bool get isLoaded => loaded;
  @override
  int get dimensions => loaded ? 384 : 0;
  @override
  String? get modelId => loaded ? 'test-embedding' : null;
  @override
  Future<List<double>> embed(String text) async => (await embedBatch([text])).single;
  @override
  Future<List<double>> embedQuery(String text) => embed(text);
  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    if (!(embeddingStarted?.isCompleted ?? true)) embeddingStarted!.complete();
    await embeddingGate?.future;
    if (!loaded || failEmbedding) throw StateError('Embedding unavailable offline.');
    return [for (final _ in texts) List.generate(384, (i) => i == 0 ? 1.0 : 0.0)];
  }
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
  @override
  T write<T>(T Function() action) => action();
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
    if (topic != null) {
      repos.documents.deleteForTopic(topic.id);
      repos.chunks.deleteForTopic(topic.id);
      repos.chats.clear(topic.id);
    }
    rows.removeWhere((row) => row.uuid == uuid);
  }
}

class _MemoryRelation<T> extends ToOne<T> {
  _MemoryRelation(this.idOf);
  final int Function(T) idOf;
  T? _target;
  int _targetId = 0;
  @override
  T? get target => _target;
  @override
  set target(T? value) { _target = value; _targetId = value == null ? 0 : idOf(value); }
  @override
  int get targetId => _target == null ? _targetId : idOf(_target as T);
  @override
  set targetId(int? value) { _targetId = value ?? 0; _target = null; }
}

class _StoredDocument extends DocumentEntity {
  final _topic = _MemoryRelation<TopicEntity>((topic) => topic.id);
  @override
  ToOne<TopicEntity> get topic => _topic;
}

class _StoredChunk extends ChunkEntity {
  final _topic = _MemoryRelation<TopicEntity>((topic) => topic.id);
  final _document = _MemoryRelation<DocumentEntity>((document) => document.id);
  @override
  ToOne<TopicEntity> get topic => _topic;
  @override
  ToOne<DocumentEntity> get document => _document;
}

class _MemoryDocuments extends _RepositoryStub implements DocumentRepository {
  final rows = <DocumentEntity>[];
  int _nextId = 1;
  @override
  List<DocumentEntity> forTopic(int topicId) => rows.where((row) => (row.topic.target?.id ?? row.topic.targetId) == topicId).toList();
  @override
  List<DocumentEntity> getAll() => List.of(rows);
  @override
  DocumentEntity? byUuid(String uuid) => rows.where((row) => row.uuid == uuid).firstOrNull;
  @override
  DocumentEntity put(DocumentEntity document) {
    if (document.id == 0) document.id = _nextId++;
    final stored = document is _StoredDocument ? document : (_StoredDocument()
      ..id = document.id..uuid = document.uuid..name = document.name..type = document.type
      ..path = document.path..sizeBytes = document.sizeBytes..pageCount = document.pageCount
      ..chunkCount = document.chunkCount..status = document.status..createdAt = document.createdAt
      ..contentSha256 = document.contentSha256..origin = document.origin
      ..aiAssisted = document.aiAssisted..updatedAt = document.updatedAt
      ..topic.target = document.topic.target);
    rows.removeWhere((row) => row.id == document.id);
    rows.add(stored);
    return stored;
  }
  @override
  void delete(String uuid, ChunkRepository chunks) {
    final document = byUuid(uuid);
    if (document == null) return;
    chunks.deleteForDocument(document.id);
    final file = File(document.path);
    if (file.existsSync()) file.deleteSync();
    rows.remove(document);
  }
  @override
  void deleteForTopic(int topicId) {
    for (final document in forTopic(topicId)) {
      final file = File(document.path);
      if (file.existsSync()) file.deleteSync();
      rows.remove(document);
    }
  }
}

class _MemoryChunks extends _RepositoryStub implements ChunkRepository {
  final rows = <ChunkEntity>[];
  int _nextId = 1;
  HybridChunkIndex? _index;
  int? _topicId;
  @override
  void clearCache() { _index = null; _topicId = null; }
  @override
  List<ChunkEntity> forTopic(int topicId) => rows.where((row) => (row.topic.target?.id ?? row.topic.targetId) == topicId).toList();
  @override
  List<ChunkEntity> forDocument(int documentId) => rows.where((row) => row.document.targetId == documentId).toList();
  @override
  void putMany(List<ChunkEntity> chunks) {
    for (final chunk in chunks) {
      if (chunk.id == 0) chunk.id = _nextId++;
      final stored = chunk is _StoredChunk ? chunk : (_StoredChunk()
        ..id = chunk.id..text = chunk.text..pageNumber = chunk.pageNumber..chunkIndex = chunk.chunkIndex
        ..embeddingModelId = chunk.embeddingModelId..vector = chunk.vector
        ..topic.target = chunk.topic.target..document.target = chunk.document.target);
      rows.removeWhere((row) => row.id == chunk.id);
      rows.add(stored);
    }
    clearCache();
  }
  @override
  void deleteForDocument(int documentId) {
    rows.removeWhere((row) => row.document.targetId == documentId);
    clearCache();
  }
  @override
  void deleteForTopic(int topicId) {
    rows.removeWhere((row) => (row.topic.target?.id ?? row.topic.targetId) == topicId);
    clearCache();
  }
  @override
  HybridChunkIndex indexForTopic(int topicId) {
    if (_index == null || _topicId != topicId) { _index = HybridChunkIndex(forTopic(topicId)); _topicId = topicId; }
    return _index!;
  }
  @override
  List<ScoredChunk> searchHybrid(int topicId, String question, List<double> vector, int k) {
    final index = indexForTopic(topicId);
    return index.rank(question, vector, index.semanticSearch(vector, k), limit: k);
  }
}

class _MemoryChats extends _RepositoryStub implements ChatRepository {
  final rows = <ChatMessageEntity>[];
  int _nextId = 1;
  @override
  List<ChatMessageEntity> forTopic(int topicId) => rows.where((row) => row.topic.target?.id == topicId).toList()
    ..sort((a, b) => a.id.compareTo(b.id));
  @override
  ChatMessageEntity? byId(int id) => rows.where((row) => row.id == id).firstOrNull;
  @override
  void add(ChatMessageEntity message) {
    if (message.id == 0) message.id = _nextId++;
    rows.removeWhere((row) => row.id == message.id);
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

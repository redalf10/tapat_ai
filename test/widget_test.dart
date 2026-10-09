import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapat_ai/const/app_route.dart';
import 'package:tapat_ai/core/services/mock_service.dart';
import 'package:tapat_ai/data/ai/engines.dart';
import 'package:tapat_ai/data/objectbox_store.dart';
import 'package:tapat_ai/data/repositories.dart';
import 'package:tapat_ai/domain/models/doc_model.dart';
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

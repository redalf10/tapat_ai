import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapat_ai/app.dart';
import 'package:tapat_ai/core/services/mock_service.dart';
import 'package:tapat_ai/provider/app_provider.dart';
import 'package:tapat_ai/data/ai/engines.dart';
import 'package:tapat_ai/data/ai/local_rag_service.dart';
import 'package:tapat_ai/data/file_ingestion.dart';
import 'package:tapat_ai/data/native_nfc_service.dart';
import 'package:tapat_ai/data/objectbox_store.dart';
import 'package:tapat_ai/data/repositories.dart';

const bool useMocks = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final logger = Logger();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    logger.e('Flutter framework error', error: details.exception, stackTrace: details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    logger.e('Uncaught platform error', error: error, stackTrace: stack);
    return true;
  };
  ErrorWidget.builder = (_) => const Material(
    child: Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Tapat AI hit a problem. Restart the app and try again.'))),
  );
  final prefs = await SharedPreferences.getInstance();
  late final ObjectBoxStore store;
  try {
    store = await ObjectBoxStore.open();
  } catch (error, stack) {
    logger.e('Local database could not be opened', error: error, stackTrace: stack);
    runApp(const MaterialApp(home: Scaffold(
      body: Center(child: Padding(padding: EdgeInsets.all(24), child: Text(
        'Tapat AI could not open its local database. Restart the app or reinstall it if the problem continues.',
        textAlign: TextAlign.center,
      ))),
    )));
    return;
  }
  final repositories = Repositories(store);
  final embedding = OnDeviceEmbeddingEngine();
  final llm = OnDeviceLlamaEngine();
  final state = AppState(
    rag: useMocks ? MockRagService() : LocalRagService(repositories, embedding, llm),
    nfc: useMocks ? MockNfcService() : NativeNfcService(),
    picker: useMocks ? MockDocumentPicker() : FileDocumentPicker(),
    prefs: prefs,
    repositories: repositories,
    embeddingEngine: embedding,
    llmEngine: llm,
    useMocks: useMocks,
  );
  runApp(TapatApp(state: state));
}



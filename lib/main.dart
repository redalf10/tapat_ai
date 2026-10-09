import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapat_ai/app.dart';
import 'package:tapat_ai/core/services/mock_service.dart';
import 'package:tapat_ai/provider/app_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final state = AppState(
    rag: MockRagService(),
    nfc: MockNfcService(),
    picker: MockDocumentPicker(),
    prefs: prefs,
  );
  runApp(TapatApp(state: state));
}



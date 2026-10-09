import 'package:flutter/material.dart';
import 'package:tapat_ai/domain/models/doc_model.dart';
import 'package:tapat_ai/presentation/chat/chat_screen.dart';
import 'package:tapat_ai/presentation/nfc/nfc_screen.dart';
import 'package:tapat_ai/presentation/settings/settings_screen.dart';
import 'package:tapat_ai/presentation/settings/model_manager_screen.dart';
import 'package:tapat_ai/presentation/settings/image_generation_settings_screen.dart';
import 'package:tapat_ai/presentation/shell/shell_screen.dart';
import 'package:tapat_ai/presentation/splashscreen/splash_screen.dart';
import 'package:tapat_ai/presentation/topic/topic_screen.dart';
import 'package:tapat_ai/presentation/topic/document_editor_screen.dart';

class Routes {
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const shell = '/home';
  static const create = '/create';
  static const processing = '/processing';
  static const documentEditor = '/documents/editor';
  static const detail = '/detail'; // arg: topicId
  static const chat = '/chat'; // arg: topicId
  static const nfcScan = '/nfc/scan';
  static const nfcDetected = '/nfc/detected'; // arg: topicId
  static const nfcWrite = '/nfc/write'; // arg: topicId
  static const knowledge = '/knowledge';
  static const settings = '/settings';
  static const models = '/settings/models';
  static const images = '/settings/images';
}

class ProcessingArgs {
  const ProcessingArgs(this.topicId, this.docs, {this.existingDocumentId});
  final String topicId;
  final List<Doc> docs;
  final String? existingDocumentId;
}

class DocumentEditorArgs {
  const DocumentEditorArgs(this.topicId, {this.documentId});
  final String topicId;
  final String? documentId;
}

class AppRouter {
  static Route<dynamic> generate(RouteSettings s) {
    final uri = Uri.tryParse(s.name ?? '');
    if (uri?.scheme == 'tapat' && uri?.host == 'kb' && uri!.pathSegments.isNotEmpty) {
      return generate(RouteSettings(name: Routes.nfcDetected, arguments: uri.pathSegments.first));
    }
    final a = s.arguments;
    final Widget w = switch (s.name) {
      Routes.onboarding => const OnboardingScreen(),
      Routes.shell => const ShellScreen(),
      Routes.create => const CreateTopicScreen(),
      Routes.processing => UploadProcessingScreen(args: a as ProcessingArgs),
      Routes.documentEditor => DocumentEditorScreen(args: a as DocumentEditorArgs),
      Routes.detail => KnowledgeDetailScreen(topicId: a as String),
      Routes.chat => ChatScreen(topicId: a as String),
      Routes.nfcScan => const NfcScanScreen(),
      Routes.nfcDetected => NfcDetectedScreen(topicId: a as String),
      Routes.nfcWrite => NfcWriteScreen(topicId: a as String),
      Routes.knowledge => const KnowledgeBasesScreen(),
      Routes.settings => const SettingsScreen(),
      Routes.models => const ModelManagerScreen(),
      Routes.images => const ImageGenerationSettingsScreen(),
      _ => const SplashScreen(),
    };
    return PageRouteBuilder(
      settings: s,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (_, _, _) => w,
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    );
  }
}

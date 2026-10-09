import 'package:flutter/material.dart';
import 'package:tapat_ai/domain/models/doc_model.dart';
import 'package:tapat_ai/presentation/chat/chat_screen.dart';
import 'package:tapat_ai/presentation/nfc/nfc_screen.dart';
import 'package:tapat_ai/presentation/settings/settings_screen.dart';
import 'package:tapat_ai/presentation/shell/shell_screen.dart';
import 'package:tapat_ai/presentation/splashscreen/splash_screen.dart';
import 'package:tapat_ai/presentation/topic/topic_screen.dart';

class Routes {
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const shell = '/home';
  static const create = '/create';
  static const processing = '/processing';
  static const detail = '/detail'; // arg: topicId
  static const chat = '/chat'; // arg: topicId
  static const nfcScan = '/nfc/scan';
  static const nfcDetected = '/nfc/detected'; // arg: topicId
  static const nfcWrite = '/nfc/write'; // arg: topicId
  static const knowledge = '/knowledge';
  static const settings = '/settings';
}

class ProcessingArgs {
  const ProcessingArgs(this.topicId, this.docs);
  final String topicId;
  final List<Doc> docs;
}

class AppRouter {
  static Route<dynamic> generate(RouteSettings s) {
    final a = s.arguments;
    final Widget w = switch (s.name) {
      Routes.onboarding => const OnboardingScreen(),
      Routes.shell => const ShellScreen(),
      Routes.create => const CreateTopicScreen(),
      Routes.processing => UploadProcessingScreen(args: a as ProcessingArgs),
      Routes.detail => KnowledgeDetailScreen(topicId: a as String),
      Routes.chat => ChatScreen(topicId: a as String),
      Routes.nfcScan => const NfcScanScreen(),
      Routes.nfcDetected => NfcDetectedScreen(topicId: a as String),
      Routes.nfcWrite => NfcWriteScreen(topicId: a as String),
      Routes.knowledge => const KnowledgeBasesScreen(),
      Routes.settings => const SettingsScreen(),
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
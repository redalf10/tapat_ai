import 'package:flutter/material.dart';
import 'package:tapat_ai/const/app_route.dart';
import 'package:tapat_ai/provider/app_provider.dart';

Future<void> uploadToTopic(BuildContext context, String topicId) async {
  final s = AppState.read(context);
  if (!s.useMocks && !s.embeddingEngine.isLoaded) {
    await Navigator.pushNamed(context, Routes.models);
    if (!context.mounted || !s.embeddingEngine.isLoaded) return;
  }
  final nav = Navigator.of(context);
  final docs = await s.picker.pick();
  if (docs.isEmpty) return;
  nav.pushNamed(Routes.processing, arguments: ProcessingArgs(topicId, docs));
}

/// Bottom sheet to choose a topic (or create one) before uploading.
Future<void> pickTopicAndUpload(BuildContext context) async {
  final s = AppState.read(context);
  if (!s.useMocks && !s.embeddingEngine.isLoaded) {
    await Navigator.pushNamed(context, Routes.models);
    if (!context.mounted || !s.embeddingEngine.isLoaded) return;
  }
  if (s.topics.isEmpty) {
    Navigator.pushNamed(context, Routes.create);
    return;
  }
  final id = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Upload to which knowledge base?',
                style: TextStyle(fontWeight: FontWeight.w600))),
        for (final t in s.topics)
          ListTile(title: Text(t.name), subtitle: Text(t.stats),
              onTap: () => Navigator.pop(context, t.id)),
      ]),
    ),
  );
  if (id != null && context.mounted) uploadToTopic(context, id);
}

void snack(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));

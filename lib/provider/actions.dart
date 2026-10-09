import 'package:flutter/material.dart';
import 'package:tapat_ai/const/app_route.dart';
import 'package:tapat_ai/provider/app_provider.dart';

Future<void> addDocumentToTopic(BuildContext context, String topicId) async {
  final action = await showModalBottomSheet<String>(context: context, showDragHandle: true,
    builder: (sheetContext) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const ListTile(title: Text('Add Document')),
      ListTile(leading: const Icon(Icons.upload_file), title: const Text('Upload existing documents'),
        subtitle: const Text('PDF, TXT, Markdown or DOCX'), onTap: () => Navigator.pop(sheetContext, 'upload')),
      ListTile(leading: const Icon(Icons.edit_note), title: const Text('Create from Scratch'),
        subtitle: const Text('Write, generate and save a text document'), onTap: () => Navigator.pop(sheetContext, 'create')),
    ])));
  if (!context.mounted) return;
  if (action == 'upload') {
    await uploadToTopic(context, topicId);
  } else if (action == 'create') {
    await Navigator.pushNamed(context, Routes.documentEditor, arguments: DocumentEditorArgs(topicId));
  }
}

Future<bool> deleteDocumentFromTopic(BuildContext context, String topicId, String documentId) async {
  final state = AppState.read(context);
  final document = state.repositories.documents.byUuid(documentId);
  if (document == null) return false;
  final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
    title: const Text('Delete document?'),
    content: Text('Delete ${document.name} and its indexed content from this device? This cannot be undone.'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
    ],
  ));
  if (confirmed != true || !context.mounted) return false;
  try {
    state.removeDoc(topicId, documentId);
    snack(context, 'Document deleted.');
    return true;
  } catch (error) {
    snack(context, 'Could not delete this document: $error');
    return false;
  }
}

Future<void> indexSavedDocument(BuildContext context, String topicId, String documentId) async {
  final state = AppState.read(context);
  if (!state.embeddingEngine.isLoaded) {
    await Navigator.pushNamed(context, Routes.models);
    if (!context.mounted || !state.embeddingEngine.isLoaded) return;
  }
  final document = state.byId(topicId).docs.where((doc) => doc.id == documentId).firstOrNull;
  if (document != null && context.mounted) {
    await Navigator.pushNamed(context, Routes.processing, arguments: ProcessingArgs(topicId, [document], existingDocumentId: documentId));
  }
}

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
            child: Text('Add a document to which knowledge base?',
                style: TextStyle(fontWeight: FontWeight.w600))),
        for (final t in s.topics)
          ListTile(title: Text(t.name), subtitle: Text(t.stats),
              onTap: () => Navigator.pop(context, t.id)),
      ]),
    ),
  );
  if (id != null && context.mounted) await addDocumentToTopic(context, id);
}

void snack(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating));

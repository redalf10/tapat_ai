import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tapat_ai/const/app_color.dart';
import 'package:tapat_ai/const/app_common.dart';
import 'package:tapat_ai/const/app_route.dart';
import 'package:tapat_ai/domain/models/doc_model.dart';
import 'package:tapat_ai/domain/models/ingest_progress.dart';
import 'package:tapat_ai/domain/models/topic_model.dart';
import 'package:tapat_ai/provider/actions.dart';
import 'package:tapat_ai/provider/app_provider.dart';

class CreateTopicScreen extends StatefulWidget {
  const CreateTopicScreen({super.key});
  @override
  State<CreateTopicScreen> createState() => _CreateTopicState();
}

class _CreateTopicState extends State<CreateTopicScreen> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  int _icon = 0;
  String _category = 'Personal';

  @override
  void dispose() { _name.dispose(); _desc.dispose(); super.dispose(); }

  void _create() {
    final s = AppState.read(context);
    final t = s.createTopic(_name.text.trim(), _desc.text.trim(), _icon, category: _category);
    Navigator.pushReplacementNamed(context, Routes.detail, arguments: t.id);
  }

  @override
  Widget build(BuildContext context) {
    final label = const TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
    return Scaffold(
      appBar: AppBar(title: const Text('Create New Topic')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Center(child: TopicIcon(_icon, size: 80)),
        const SizedBox(height: 24),
        Text('Topic Name', style: label),
        const SizedBox(height: 6),
        TextField(controller: _name, onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(hintText: 'e.g. Computer Networking')),
        const SizedBox(height: 16),
        Text('Description (Optional)', style: label),
        const SizedBox(height: 6),
        TextField(controller: _desc, maxLines: 3,
            decoration: const InputDecoration(hintText: 'What is this knowledge base about?')),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _category,
          decoration: const InputDecoration(labelText: 'Category'),
          items: [for (final category in ['Education', 'Work', 'Personal']) DropdownMenuItem(value: category, child: Text(category))],
          onChanged: (value) { if (value != null) setState(() => _category = value); },
        ),
        const SizedBox(height: 16),
        Text('Icon', style: label),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (var i = 0; i < topicIcons.length; i++)
            GestureDetector(
              onTap: () => setState(() => _icon = i),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _icon == i ? AppColors.blue : Colors.transparent, width: 2)),
                child: TopicIcon(i, size: 44),
              ),
            ),
        ]),
        const SizedBox(height: 28),
        GradientButton(label: 'Create Topic', onPressed: _name.text.trim().isEmpty ? null : _create),
      ]),
    );
  }
}

class UploadProcessingScreen extends StatefulWidget {
  const UploadProcessingScreen({super.key, required this.args});
  final ProcessingArgs args;
  @override
  State<UploadProcessingScreen> createState() => _UploadProcessingState();
}

class _UploadProcessingState extends State<UploadProcessingScreen> {
  static const _stages = ['Extracting text...', 'Creating text chunks...', 'Generating embeddings...', 'Saving to local database...', 'Completed'];
  StreamSubscription<IngestProgress>? _sub;
  IngestProgress _p = const IngestProgress(0, 0);
  bool _done = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = AppState.read(context);
    final topic = s.byId(widget.args.topicId);
    final progress = widget.args.existingDocumentId == null
        ? s.ingestDocuments(topic, widget.args.docs)
        : s.indexDocument(widget.args.existingDocumentId!);
    _sub = progress.listen((p) {
      setState(() => _p = p);
      if (p.stage == 4) {
        s.addDocs(widget.args.topicId, widget.args.docs);
        setState(() => _done = true);
      }
    }, onError: (Object error) {
      if (mounted) setState(() => _error = error.toString());
    });
  }

  @override
  void dispose() { _sub?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    final doc = widget.args.docs.first;
    return Scaffold(
      appBar: AppBar(title: Text(widget.args.existingDocumentId == null ? 'Upload Document' : 'Index Document')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        AppCard(
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.picture_as_pdf, color: Colors.red),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(doc.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('${doc.sizeMb} MB', style: TextStyle(fontSize: 12, color: hint)),
            ])),
          ]),
        ),
        const SizedBox(height: 20),
        for (var i = 0; i < _stages.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(children: [
              i < _p.stage || _done
                  ? const Icon(Icons.check_circle, color: AppColors.blue, size: 22)
                  : i == _p.stage
                      ? const Icon(Icons.radio_button_unchecked, color: AppColors.blue, size: 22)
                      : Icon(Icons.check_circle_outline, color: hint, size: 22),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_stages[i], style: TextStyle(color: i <= _p.stage ? null : hint)),
                if (i == 2 && _p.stage == 2) Text(_p.detail, style: TextStyle(fontSize: 11, color: hint)),
              ])),
            ]),
          ),
        const SizedBox(height: 28),
        Center(
          child: SizedBox(
            width: 120, height: 120,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                    value: _p.fraction, strokeWidth: 6, backgroundColor: hint.withValues(alpha: .2), color: AppColors.blue),
              ),
              Text('${(_p.fraction * 100).round()}%', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Text(_error ?? (_done ? 'All done!' : 'Please wait...\nThis may take a few minutes.'),
            textAlign: TextAlign.center, style: TextStyle(color: hint, fontSize: 12)),
        const SizedBox(height: 24),
        _done || _error != null
            ? GradientButton(label: 'Done', onPressed: () => Navigator.pop(context))
            : SoftButton(label: 'Cancel', onPressed: () => Navigator.pop(context)),
      ]),
    );
  }
}

class KnowledgeDetailScreen extends StatelessWidget {
  const KnowledgeDetailScreen({super.key, required this.topicId});
  final String topicId;

  @override
  Widget build(BuildContext context) {
    final s = AppState.of(context);
    final matches = s.topics.where((t) => t.id == topicId);
    if (matches.isEmpty) return const Scaffold();
    final t = matches.first;
    final hint = Theme.of(context).hintColor;
    return Scaffold(
      appBar: AppBar(
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'edit') _editTopic(context, t, s);
              if (v == 'delete') {
                Navigator.pop(context);
                s.deleteTopic(topicId);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit knowledge base')),
              PopupMenuItem(value: 'delete', child: Text('Delete knowledge base')),
            ],
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Center(child: TopicIcon(t.iconIndex, size: 72)),
        const SizedBox(height: 12),
        Text(t.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('${t.stats}\nCreated ${fmtDate(t.created)}', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: hint)),
        const SizedBox(height: 20),
        GradientButton(label: 'Chat with AI', icon: Icons.auto_awesome, onPressed: () => Navigator.pushNamed(context, Routes.chat, arguments: t.id)),
        const SizedBox(height: 10),
        SoftButton(label: 'Add Document', icon: Icons.note_add_outlined, onPressed: () => addDocumentToTopic(context, t.id)),
        const SizedBox(height: 10),
        SoftButton(label: 'Link NFC Tag', icon: Icons.nfc, onPressed: () => Navigator.pushNamed(context, Routes.nfcWrite, arguments: t.id)),
        const SizedBox(height: 24),
        const Text('Documents', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (t.docs.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Center(child: Text('No documents yet', style: TextStyle(color: hint)))),
        for (final d in t.docs)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: (d.type == DocType.pdf ? Colors.red : d.type == DocType.txt ? Colors.blue : Colors.indigo).withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(d.type == DocType.pdf ? Icons.picture_as_pdf : Icons.description,
                  color: d.type == DocType.pdf ? Colors.red : Colors.blue, size: 20),
            ),
            title: Text(d.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            subtitle: Text('${d.originLabel}\n${d.statusLabel}', style: const TextStyle(fontSize: 12)),
            isThreeLine: true,
            onTap: d.isEditable && !s.isIndexing ? () => Navigator.pushNamed(context, Routes.documentEditor,
              arguments: DocumentEditorArgs(t.id, documentId: d.id)) : null,
            trailing: PopupMenuButton<String>(
              enabled: !s.isIndexing,
              onSelected: (value) {
                if (value == 'edit') Navigator.pushNamed(context, Routes.documentEditor, arguments: DocumentEditorArgs(t.id, documentId: d.id));
                if (value == 'index') indexSavedDocument(context, t.id, d.id);
                if (value == 'remove') deleteDocumentFromTopic(context, t.id, d.id);
                if (value == 'move') _moveDocument(context, t.id, d.id, s);
              },
              itemBuilder: (_) => [
                if (d.isEditable) const PopupMenuItem(value: 'edit', child: Text('Open / Edit')),
                PopupMenuItem(value: 'index', child: Text(d.isIndexed ? 'Re-index document' : 'Index document')),
                const PopupMenuItem(value: 'move', child: Text('Move to another topic')),
                const PopupMenuItem(value: 'remove', child: Text('Delete')),
              ],
            ),
          ),
      ]),
    );
  }

  Future<void> _editTopic(BuildContext context, Topic topic, AppState state) async {
    final name = TextEditingController(text: topic.name);
    final description = TextEditingController(text: topic.description);
    var category = topic.category;
    await showDialog<void>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: const Text('Edit knowledge base'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
        TextField(controller: description, decoration: const InputDecoration(labelText: 'Description')),
        DropdownButtonFormField<String>(initialValue: category, decoration: const InputDecoration(labelText: 'Category'),
          items: [for (final c in ['Education', 'Work', 'Personal']) DropdownMenuItem(value: c, child: Text(c))],
          onChanged: (value) { if (value != null) setDialogState(() => category = value); }),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
        FilledButton(onPressed: () {
          if (name.text.trim().isEmpty) return;
          state.updateTopic(topic.id, name: name.text.trim(), description: description.text.trim(), category: category, iconIndex: topic.iconIndex);
          Navigator.pop(dialogContext);
        }, child: const Text('Save')),
      ],
    )));
    name.dispose();
    description.dispose();
  }

  Future<void> _moveDocument(BuildContext context, String currentTopicId, String documentId, AppState state) async {
    final targetId = await showModalBottomSheet<String>(context: context, showDragHandle: true,
      builder: (_) => SafeArea(child: ListView(shrinkWrap: true, children: [
        const ListTile(title: Text('Move document to')),
        for (final topic in state.topics.where((t) => t.id != currentTopicId))
          ListTile(title: Text(topic.name), subtitle: Text(topic.category), onTap: () => Navigator.pop(context, topic.id)),
      ])));
    if (targetId != null) state.moveDocument(documentId, targetId);
  }
}

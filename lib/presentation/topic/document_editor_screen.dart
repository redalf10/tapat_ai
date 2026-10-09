import 'package:flutter/material.dart';

import '../../const/app_common.dart';
import '../../const/app_route.dart';
import '../../domain/models/doc_model.dart';
import '../../provider/actions.dart';
import '../../provider/app_provider.dart';

class DocumentEditorScreen extends StatefulWidget {
  const DocumentEditorScreen({super.key, required this.args});
  final DocumentEditorArgs args;
  @override
  State<DocumentEditorScreen> createState() => _DocumentEditorState();
}

class _DocumentEditorState extends State<DocumentEditorScreen> {
  final _title = TextEditingController();
  final _content = TextEditingController();
  final _prompt = TextEditingController();
  final _draft = TextEditingController();
  late final AppState _state;
  String? _documentId, _sha, _error, _indexError;
  String _savedTitle = '', _savedContent = '', _progress = '';
  bool _loading = false, _editing = true, _saving = false, _generating = false;
  bool _showGenerator = false, _generatedOnce = false, _aiAssisted = false;
  bool _indexOnSave = false, _allowPop = false, _leaving = false;

  bool get _dirty => _title.text != _savedTitle || _content.text != _savedContent || _draft.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _state = AppState.read(context);
    _documentId = widget.args.documentId;
    _indexOnSave = _state.embeddingEngine.isLoaded;
    if (_documentId != null) {
      _loading = true;
      _editing = false;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final document = _state.byId(widget.args.topicId).docs.firstWhere((doc) => doc.id == _documentId);
      final text = await _state.documentLibrary.readText(document.id);
      if (!mounted) return;
      _title.text = document.name.replaceFirst(RegExp(r'\.txt$', caseSensitive: false), '');
      _content.text = text;
      _savedTitle = _title.text;
      _savedContent = text;
      _sha = document.contentSha256;
      _aiAssisted = document.aiAssisted;
      _indexOnSave = document.isIndexed && _state.embeddingEngine.isLoaded;
    } catch (error) {
      if (mounted) _error = 'Could not open this document: $error';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _prompt.dispose();
    _draft.dispose();
    super.dispose();
  }

  Future<bool> _confirm(String title, String body, String action) async => await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(title: Text(title), content: Text(body), actions: [
      TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(action)),
    ]),
  ) ?? false;

  Future<void> _generate() async {
    if (_generating || _saving) return;
    if (_prompt.text.trim().isEmpty) {
      setState(() => _error = 'Describe the content you want to generate.');
      return;
    }
    if (_draft.text.isNotEmpty && !await _confirm('Regenerate this draft?',
        'This replaces the generated draft, including your edits to it. Your document content will not change.', 'Regenerate')) {
      return;
    }
    if (!mounted) return;
    if (!_state.llmEngine.isLoaded) {
      await Navigator.pushNamed(context, Routes.models);
      if (!mounted || !_state.llmEngine.isLoaded) return;
    }
    setState(() { _generating = true; _error = null; });
    try {
      final text = await _state.generateDocumentText(_prompt.text);
      if (mounted) setState(() { _draft.text = text; _generatedOnce = true; });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _append() {
    if (_draft.text.trim().isEmpty) return;
    setState(() {
      _content.text = _content.text.isEmpty ? _draft.text : '${_content.text}\n\n${_draft.text}';
      _content.selection = TextSelection.collapsed(offset: _content.text.length);
      _aiAssisted = true;
      _draft.clear();
    });
  }

  Future<void> _replace() async {
    if (_draft.text.trim().isEmpty) return;
    if (_content.text.isNotEmpty && !await _confirm('Replace document content?',
        'Your current content will be replaced by the generated draft. The saved document is unchanged until you press Save.', 'Replace')) {
      return;
    }
    if (!mounted) return;
    setState(() { _content.text = _draft.text; _aiAssisted = true; _draft.clear(); });
  }

  Future<void> _index() async {
    await for (final progress in _state.indexDocument(_documentId!)) {
      if (mounted) setState(() => _progress = progress.detail);
    }
  }

  Future<void> _save() async {
    if (_saving || _generating) return;
    if (_draft.text.isNotEmpty) {
      setState(() => _error = 'Append, replace or discard the generated draft before saving.');
      return;
    }
    setState(() { _saving = true; _error = null; _indexError = null; _progress = 'Saving text document'; });
    try {
      final document = await _state.saveTextDocument(widget.args.topicId, title: _title.text,
        content: _content.text, documentId: _documentId, expectedSha256: _sha, aiAssisted: _aiAssisted);
      if (!mounted) return;
      setState(() {
        _documentId = document.id;
        _sha = document.contentSha256;
        _title.text = document.name.replaceFirst(RegExp(r'\.txt$', caseSensitive: false), '');
        _savedTitle = _title.text;
        _savedContent = _content.text;
        _editing = false;
      });
      if (_indexOnSave) {
        try {
          await _index();
        } catch (error) {
          if (mounted) setState(() => _indexError = 'Document saved, but indexing failed: $error');
        }
      }
      if (mounted) snack(context, _indexOnSave && _indexError == null ? 'Document saved and indexed.' : 'Document saved on this device.');
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not save this document: $error');
    } finally {
      if (mounted) setState(() { _saving = false; _progress = ''; });
    }
  }

  Future<void> _retryIndex() async {
    if (!_state.embeddingEngine.isLoaded) {
      await Navigator.pushNamed(context, Routes.models);
      if (!mounted || !_state.embeddingEngine.isLoaded) return;
    }
    setState(() { _saving = true; _indexError = null; });
    try {
      await _index();
      if (mounted) snack(context, 'Document indexed for future answers.');
    } catch (error) {
      if (mounted) setState(() => _indexError = 'Document saved, but indexing failed: $error');
    } finally {
      if (mounted) setState(() { _saving = false; _progress = ''; });
    }
  }

  void _pop() {
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) Navigator.pop(context); });
  }

  Future<void> _leave() async {
    if (_saving || _leaving) return;
    _leaving = true;
    try {
      if (_dirty && !await _confirm('Discard unsaved changes?', 'Unsaved text and generated drafts will be discarded.', 'Discard')) return;
      if (_generating) await _state.stopLocalGeneration();
      if (mounted) _pop();
    } finally {
      _leaving = false;
    }
  }

  Future<void> _delete() async {
    if (_documentId == null || _saving || _generating) return;
    if (await deleteDocumentFromTopic(context, widget.args.topicId, _documentId!) && mounted) _pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppState.of(context);
    final documents = state.topics.where((topic) => topic.id == widget.args.topicId).firstOrNull?.docs ?? <Doc>[];
    final saved = documents.where((doc) => doc.id == _documentId).firstOrNull;
    final busy = _saving || _generating;
    final hint = Theme.of(context).colorScheme.onSurfaceVariant;
    return PopScope(
      canPop: _allowPop || (!_dirty && !busy),
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _leave(); },
      child: Scaffold(
        appBar: AppBar(title: Text(_documentId == null ? 'Create Document' : 'Document'), actions: [
          if (_documentId != null && !_loading && !_editing)
            TextButton.icon(onPressed: busy ? null : () => setState(() => _editing = true), icon: const Icon(Icons.edit_outlined), label: const Text('Edit')),
          if (_documentId != null)
            IconButton(tooltip: 'Delete document', onPressed: busy ? null : _delete, icon: const Icon(Icons.delete_outline)),
        ]),
        body: _loading ? const Center(child: CircularProgressIndicator()) : Center(
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 840), child: ListView(
            padding: const EdgeInsets.all(20), children: [
              Text(saved == null ? 'Unsaved draft · Not indexed' : '${saved.originLabel} · ${saved.statusLabel}', style: TextStyle(color: hint)),
              const SizedBox(height: 12),
              TextField(key: const ValueKey('document-title'), controller: _title, readOnly: !_editing || _saving,
                maxLength: 200, decoration: const InputDecoration(labelText: 'Document title', suffixText: '.txt'),
                onChanged: (_) => setState(() {})),
              const SizedBox(height: 12),
              if (_editing) Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(
                onPressed: _saving ? null : () => setState(() => _showGenerator = true),
                icon: const Icon(Icons.auto_awesome_outlined), label: const Text('Generate Text'))),
              const SizedBox(height: 8),
              TextField(key: const ValueKey('document-content'), controller: _content, readOnly: !_editing || _saving,
                minLines: 12, maxLines: null, keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(labelText: 'Content', alignLabelWithHint: true, hintText: 'Write or paste your document here...'),
                onChanged: (_) => setState(() {})),
              if (_editing && _showGenerator) ...[
                const SizedBox(height: 16),
                AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Generate with local AI', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text('Runs on this device using your language model. Drafts are not saved or indexed until you apply and save them.', style: TextStyle(color: hint, fontSize: 12)),
                  const SizedBox(height: 12),
                  TextField(key: const ValueKey('document-prompt'), controller: _prompt, enabled: !busy,
                    minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'What should the AI write?', hintText: 'e.g. Study notes explaining the water cycle')),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, children: [
                    FilledButton.icon(onPressed: busy || state.isGenerating ? null : _generate,
                      icon: const Icon(Icons.auto_awesome), label: Text(_generatedOnce ? 'Regenerate draft' : 'Generate draft')),
                    if (_generating) TextButton(onPressed: state.isStopping ? null : () async {
                      try { await state.stopLocalGeneration(); } catch (error) { if (mounted) setState(() => _error = '$error'); }
                    }, child: const Text('Stop generation')),
                    if (!state.llmEngine.isLoaded && !_generating)
                      TextButton(onPressed: () => Navigator.pushNamed(context, Routes.models), child: const Text('Choose language model')),
                  ]),
                  if (_generating) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
                  if (_draft.text.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    TextField(key: const ValueKey('generated-draft'), controller: _draft, enabled: !busy,
                      minLines: 4, maxLines: 12, decoration: const InputDecoration(labelText: 'Generated draft · Review and edit'),
                      onChanged: (_) => setState(() {})),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, children: [
                      TextButton.icon(onPressed: busy ? null : _append, icon: const Icon(Icons.add), label: const Text('Append')),
                      TextButton.icon(onPressed: busy ? null : _replace, icon: const Icon(Icons.find_replace), label: const Text('Replace content')),
                      TextButton(onPressed: busy ? null : () => setState(_draft.clear), child: const Text('Discard draft')),
                    ]),
                  ],
                ])),
              ],
              if (_editing) ...[
                const SizedBox(height: 12),
                CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('Index after saving'),
                  subtitle: Text(state.embeddingEngine.isLoaded ? 'Make this document searchable in future answers.' : 'Saving works offline without models. Activate an embedding model to index later.'),
                  value: _indexOnSave && state.embeddingEngine.isLoaded,
                  onChanged: busy || !state.embeddingEngine.isLoaded ? null : (value) => setState(() => _indexOnSave = value ?? false)),
              ],
              if (_error != null || _indexError != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12),
                child: Semantics(liveRegion: true, child: Text(_error ?? _indexError!, style: TextStyle(color: Theme.of(context).colorScheme.error)))),
              if (!_editing && saved != null && (!saved.isIndexed || _indexError != null))
                TextButton.icon(onPressed: busy || state.isIndexing ? null : _retryIndex, icon: const Icon(Icons.manage_search), label: const Text('Index saved document')),
              if (_saving) Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(_progress.isEmpty ? 'Indexing document...' : _progress)),
              const SizedBox(height: 12),
              if (_editing) GradientButton(label: _documentId == null ? 'Save' : 'Save changes', loading: _saving,
                icon: Icons.save_outlined, onPressed: busy || state.isIndexing ? null : _save),
              TextButton(onPressed: _saving ? null : _leave, child: Text(_editing ? 'Cancel' : 'Close')),
            ],
          )),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../const/app_common.dart';
import '../../data/entities/entities.dart';
import '../../data/ai/engines.dart';
import '../../data/model_downloader.dart';
import '../../data/repositories.dart';
import '../../data/file_ingestion.dart';
import '../../provider/app_provider.dart';

class ModelManagerScreen extends StatefulWidget {
  const ModelManagerScreen({super.key});
  @override
  State<ModelManagerScreen> createState() => _ModelManagerScreenState();
}

class _ModelManagerScreenState extends State<ModelManagerScreen> {
  final _downloader = ModelDownloader();
  final _token = TextEditingController();
  DownloadProgress? _progress;
  bool _busy = false;
  bool _paused = false;
  String? _working;
  String? _error;
  double? _reindexProgress;

  @override
  void initState() {
    super.initState();
    _downloader.getToken().then((value) { if (mounted) _token.text = value ?? ''; });
  }

  @override
  void dispose() { _downloader.cancel(); _token.dispose(); super.dispose(); }

  Future<void> _download(ModelCatalogItem item) async {
    final state = AppState.read(context);
    setState(() { _busy = true; _working = item.name; _error = null; _progress = null; });
    try {
      final file = await _downloader.download(item, onProgress: (p) { if (mounted) setState(() => _progress = p); });
      final model = ModelEntity()
        ..uuid = LocalFiles.newId()
        ..name = item.name
        ..kind = item.kind
        ..repoId = item.repo
        ..filename = item.file
        ..localPath = file.path
        ..sizeBytes = await file.length()
        ..status = 'available'
        ..sha256 = item.sha256
        ..dimensions = item.dimensions
        ..license = item.license;
      if (!mounted) return;
      state.repositories.models.put(model);
      if (mounted) _notice('${item.name} downloaded and verified.');
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally { if (mounted) setState(() { _busy = false; _working = null; _paused = false; }); }
  }

  Future<void> _import() async {
    final state = AppState.read(context);
    setState(() { _busy = true; _working = 'Importing model'; _error = null; _progress = null; });
    try {
      final row = await _downloader.importFromDevice(onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (!mounted) return;
      state.repositories.models.put(row);
      if (mounted) _notice('Model copied into Tapat AI storage.');
    } catch (e) { if (mounted && e is! FileSystemException) setState(() => _error = '$e'); }
    finally { if (mounted) setState(() { _busy = false; _working = null; _progress = null; }); }
  }

  Future<void> _activate(ModelEntity model) async {
    final state = AppState.read(context);
    setState(() { _busy = true; _working = 'Loading ${model.name}'; _error = null; });
    try {
      if (model.kind == 'llm') {
        await state.llmEngine.load(model);
      } else {
        await state.embeddingEngine.load(model);
        if (state.embeddingEngine.dimensions != 384) {
          final actualDimensions = state.embeddingEngine.dimensions;
          await state.embeddingEngine.unload();
          throw StateError('This vector database requires 384-dimensional embeddings. Re-index support is needed before activating a model with $actualDimensions dimensions.');
        }
      }
      state.repositories.models.setActive(model.id, model.kind);
      state.modelCatalogChanged();
      if (mounted) _notice('${model.name} is ready for offline use.');
    } catch (e) { if (mounted) setState(() => _error = '$e'); }
    finally { if (mounted) setState(() { _busy = false; _working = null; }); }
  }

  Future<void> _delete(ModelEntity model) async {
    final state = AppState.read(context);
    final file = File(model.localPath);
    if (file.existsSync()) await file.delete();
    if (!mounted) return;
    state.repositories.models.delete(model.id);
    if (model.isActive) {
      if (model.kind == 'llm') {
        await state.llmEngine.unload();
      } else {
        await state.embeddingEngine.unload();
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _reindex() async {
    final state = AppState.read(context);
    setState(() { _busy = true; _working = 'Re-indexing documents'; _reindexProgress = 0; _error = null; });
    try {
      await for (final progress in ReindexEmbeddingsUseCase(state.repositories, state.embeddingEngine).call()) {
        if (mounted) setState(() => _reindexProgress = progress.fraction);
      }
      if (mounted) _notice('All document embeddings have been updated.');
    } catch (e) { if (mounted) setState(() => _error = '$e'); }
    finally { if (mounted) setState(() { _busy = false; _working = null; _reindexProgress = null; }); }
  }

  bool _needsReindex(ModelEntity model) {
    if (model.kind != 'embedding' || !model.isActive) return false;
    final repo = AppState.read(context).repositories;
    for (final topic in repo.topics.getAll()) {
      if (repo.chunks.forTopic(topic.id).any((chunk) => chunk.embeddingModelId != embeddingModelIndexId(model))) return true;
    }
    return false;
  }

  void _notice(String text) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
  String _size(int bytes) => bytes >= 1073741824 ? '${(bytes / 1073741824).toStringAsFixed(2)} GB' : '${(bytes / 1048576).toStringAsFixed(0)} MB';
  String _duration(Duration? d) => d == null ? 'estimating…' : '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')} remaining';

  @override
  Widget build(BuildContext context) {
    final state = AppState.of(context);
    final models = state.repositories.models.getAll();
    final total = models.fold<int>(0, (sum, m) => sum + m.sizeBytes);
    return Scaffold(
      appBar: AppBar(title: const Text('Local AI Models')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Your models stay on this device', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Storage used by models: ${_size(total)}', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
          const SizedBox(height: 10),
          TextField(controller: _token, obscureText: true,
            decoration: InputDecoration(labelText: 'Optional Hugging Face access token',
              suffixIcon: IconButton(tooltip: 'Save token', icon: const Icon(Icons.save_outlined), onPressed: () async { await _downloader.saveToken(_token.text); if (mounted) _notice('Token saved securely on this device.'); }))),
        ])),
        const SizedBox(height: 16),
        Row(children: [const Expanded(child: Text('Recommended models', style: TextStyle(fontWeight: FontWeight.w700))), TextButton.icon(onPressed: _busy ? null : _import, icon: const Icon(Icons.file_open), label: const Text('Import'))]),
        for (final item in ModelCatalogItem.recommended) _catalogCard(item),
        const SizedBox(height: 16),
        const Text('Installed models', style: TextStyle(fontWeight: FontWeight.w700)),
        if (models.isEmpty) const AppCard(child: Text('No local models installed yet. Download or import one to get started.')),
        for (final model in models) _modelCard(model),
        if (_progress != null && _working != null) ...[
          const SizedBox(height: 12),
          AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_paused ? 'Paused: $_working' : 'Downloading: $_working'),
            const SizedBox(height: 10), LinearProgressIndicator(value: _progress!.fraction),
            const SizedBox(height: 6), Text('${_size(_progress!.received)} / ${_size(_progress!.total)} · ${_size(_progress!.bytesPerSecond.round())}/s · ${_duration(_progress!.eta)}'),
            Row(children: [TextButton(onPressed: () { if (_paused) { _downloader.resume(); setState(() => _paused = false); } else { _downloader.pause(); setState(() => _paused = true); } }, child: Text(_paused ? 'Resume' : 'Pause')),
              TextButton(onPressed: _downloader.cancel, child: const Text('Cancel'))]),
          ])),
        ],
        if (_working != null && _progress == null) Padding(padding: const EdgeInsets.all(12), child: Center(child: _reindexProgress == null
          ? const CircularProgressIndicator() : CircularProgressIndicator(value: _reindexProgress))),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        const SizedBox(height: 20),
        const Text('Qwen2.5 1.5B requires about 3 GB RAM while running. BGE Small produces 384-dimensional vectors. The first chat and document indexing require both models.', style: TextStyle(fontSize: 12)),
      ]),
    );
  }

  Widget _catalogCard(ModelCatalogItem item) => Padding(padding: const EdgeInsets.only(bottom: 8), child: AppCard(
    child: Row(children: [
      Icon(item.kind == 'llm' ? Icons.chat_bubble_outline : Icons.hub_outlined), const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text('${_size(item.sizeBytes)} · ${item.quantization} · ${item.ramGb} GB RAM · ${item.license}', style: const TextStyle(fontSize: 11)),
      ])),
      TextButton(onPressed: _busy ? null : () => _download(item), child: const Text('Download')),
    ])));

  Widget _modelCard(ModelEntity model) => Padding(padding: const EdgeInsets.only(top: 8), child: AppCard(
    child: Row(children: [Icon(model.kind == 'llm' ? Icons.chat_bubble_outline : Icons.hub_outlined), const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(model.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text('${model.kind} · ${_size(model.sizeBytes)}${model.isActive ? ' · Active' : ''}', style: const TextStyle(fontSize: 11)),
      ])),
      if (!model.isActive) TextButton(onPressed: _busy ? null : () => _activate(model), child: const Text('Use')),
      if (_needsReindex(model)) TextButton(onPressed: _busy ? null : _reindex, child: const Text('Re-index')),
      PopupMenuButton<String>(onSelected: (v) { if (v == 'delete') _delete(model); }, itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete'))]),
    ])));
}

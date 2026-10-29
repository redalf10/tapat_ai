import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:background_downloader/background_downloader.dart';
import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart' as convert;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'entities/entities.dart';
import 'repositories.dart';

class ModelCatalogItem {
  const ModelCatalogItem({
    required this.name,
    required this.kind,
    required this.repo,
    required this.file,
    required this.sizeBytes,
    required this.ramGb,
    required this.quantization,
    required this.license,
    this.dimensions = 0,
    this.sha256 = '',
  });
  final String name, kind, repo, file, quantization, license, sha256;
  final int sizeBytes, dimensions;
  final double ramGb;
  String get url => 'https://huggingface.co/$repo/resolve/main/$file';
  Map<String, Object> toJson() => {
    'name': name,
    'kind': kind,
    'repo': repo,
    'file': file,
    'sizeBytes': sizeBytes,
    'ramGb': ramGb,
    'quantization': quantization,
    'license': license,
    'dimensions': dimensions,
    'sha256': sha256,
  };
  factory ModelCatalogItem.fromJson(Map<String, dynamic> json) =>
      ModelCatalogItem(
        name: json['name'] as String,
        kind: json['kind'] as String,
        repo: json['repo'] as String,
        file: json['file'] as String,
        sizeBytes: (json['sizeBytes'] as num).toInt(),
        ramGb: (json['ramGb'] as num).toDouble(),
        quantization: json['quantization'] as String,
        license: json['license'] as String,
        dimensions: (json['dimensions'] as num?)?.toInt() ?? 0,
        sha256: json['sha256'] as String? ?? '',
      );
  static const recommended = <ModelCatalogItem>[
    ModelCatalogItem(
      name: 'Qwen2.5 1.5B Instruct',
      kind: 'llm',
      repo: 'bartowski/Qwen2.5-1.5B-Instruct-GGUF',
      file: 'Qwen2.5-1.5B-Instruct-Q4_K_M.gguf',
      sizeBytes: 986000000,
      ramGb: 3.0,
      quantization: 'Q4_K_M',
      license: 'Apache-2.0',
    ),
    ModelCatalogItem(
      name: 'BGE Small English v1.5 (llama.cpp)',
      kind: 'embedding',
      repo: 'CompendiumLabs/bge-small-en-v1.5-gguf',
      file: 'bge-small-en-v1.5-q4_k_m.gguf',
      sizeBytes: 24000000,
      ramGb: 1.0,
      quantization: 'Q4_K_M',
      license: 'MIT / BAAI license',
      dimensions: 384,
    ),
  ];
}

class DownloadProgress {
  const DownloadProgress(this.received, this.total, this.bytesPerSecond);
  final int received, total;
  final double bytesPerSecond;
  double get fraction => total <= 0 ? 0 : (received / total).clamp(0, 1);
  Duration? get eta => bytesPerSecond <= 0 || total <= 0
      ? null
      : Duration(seconds: ((total - received) / bytesPerSecond).round());
}

/// Owns model transfers independently of the model screen. Native URLSession /
/// WorkManager jobs can finish while the app process is suspended or stopped.
class ModelDownloader extends ChangeNotifier {
  ModelDownloader._();
  static final ModelDownloader instance = ModelDownloader._();
  static const _pendingKey = 'pending_model_download';
  static const _group = 'model-downloads';
  final _secure = const FlutterSecureStorage();
  Repositories? _repositories;
  Transfer? _transfer;
  ModelCatalogItem? _item;
  Future<void>? _initialization;
  bool _paused = false;
  String? _error;

  ModelCatalogItem? get item => _item;
  bool get isDownloading =>
      _transfer != null && !_transfer!.status.isFinalState;
  bool get isPaused => _paused || _transfer?.status == TaskStatus.paused;
  String? get error => _error;
  DownloadProgress? get progress {
    final transfer = _transfer;
    final item = _item;
    if (transfer == null || item == null) return null;
    final fraction = transfer.progress ?? 0;
    final total = transfer.task is DownloadTask ? item.sizeBytes : 0;
    final speed = transfer.networkSpeed > 0
        ? transfer.networkSpeed * 1024 * 1024
        : 0.0;
    return DownloadProgress((fraction * total).round(), total, speed);
  }

  Future<void> initialize(Repositories repositories) {
    _repositories = repositories;
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    final downloader = FileDownloader();
    await downloader.start(autoCleanDatabase: false);
    downloader.configureNotification(
      running: const TaskNotification('Downloading model', '{filename}'),
      complete: const TaskNotification('Model download complete', '{filename}'),
      error: const TaskNotification('Model download failed', '{filename}'),
      paused: const TaskNotification('Model download paused', '{filename}'),
      progressBar: true,
    );
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_pendingKey);
    if (saved == null) return;
    try {
      final data = jsonDecode(saved) as Map<String, dynamic>;
      final item = ModelCatalogItem.fromJson(
        data['item'] as Map<String, dynamic>,
      );
      final task = _task(
        item,
        data['taskId'] as String,
        null,
        userInitiated: data['userInitiated'] as bool? ?? true,
      );
      final transfer = await downloader.transfers.getOrStart(task);
      _bind(item, transfer);
      if (transfer.status == TaskStatus.complete) {
        await _complete(item, transfer);
      } else if (transfer.status.isFinalState) {
        _error =
            'The background download ${transfer.status.name}. Start it again to retry.';
        await prefs.remove(_pendingKey);
        notifyListeners();
      } else {
        unawaited(_watch(transfer, item));
      }
    } catch (error) {
      _error = 'Could not resume the model download: $error';
      notifyListeners();
    }
  }

  Future<String?> getToken() => _secure.read(key: 'huggingface_token');
  Future<void> saveToken(String token) => token.trim().isEmpty
      ? _secure.delete(key: 'huggingface_token')
      : _secure.write(key: 'huggingface_token', value: token.trim());

  Future<File> download(
    ModelCatalogItem item, {
    required void Function(DownloadProgress) onProgress,
  }) async {
    await _initialization;
    final prefs = await SharedPreferences.getInstance();
    final token = await getToken();
    final taskId = const Uuid().v4();
    _error = null;
    final downloader = FileDownloader();
    var notificationPermission = await downloader.permissions.status(
      PermissionType.notifications,
    );
    if (notificationPermission != PermissionStatus.granted) {
      notificationPermission = await downloader.permissions.request(
        PermissionType.notifications,
      );
    }
    final userInitiated = notificationPermission == PermissionStatus.granted;
    await prefs.setString(
      _pendingKey,
      jsonEncode({
        'taskId': taskId,
        'item': item.toJson(),
        'userInitiated': userInitiated,
      }),
    );
    final transfer = await downloader.transfers.start(
      _task(item, taskId, token, userInitiated: userInitiated),
    );
    _bind(item, transfer);
    notifyListeners();
    void update() {
      final value = progress;
      if (value != null) onProgress(value);
    }

    transfer.progressNotifier.addListener(update);
    try {
      final file = await transfer.file;
      return await _complete(item, transfer, downloadedFile: file);
    } catch (error) {
      _error = '$error';
      notifyListeners();
      rethrow;
    } finally {
      transfer.progressNotifier.removeListener(update);
    }
  }

  DownloadTask _task(
    ModelCatalogItem item,
    String taskId,
    String? token, {
    bool userInitiated = true,
  }) => DownloadTask(
    taskId: taskId,
    url: item.url,
    filename: '${item.file}.part',
    directory: 'models',
    baseDirectory: BaseDirectory.applicationDocuments,
    group: _group,
    headers: {
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    },
    retries: 3,
    transferHints: {
      TransferHint.largeFile,
      if (userInitiated) TransferHint.userInitiated,
    },
    notificationConfig: TaskNotificationConfig(
      running: TaskNotification('Downloading model', '{filename}'),
      complete: TaskNotification('Model download complete', '{filename}'),
      error: TaskNotification('Model download failed', '{filename}'),
      progressBar: true,
    ),
    metaData: jsonEncode(item.toJson()),
    displayName: item.name,
  );

  void _bind(ModelCatalogItem item, Transfer transfer) {
    _item = item;
    _transfer = transfer;
    _paused = transfer.status == TaskStatus.paused;
    transfer.statusNotifier.addListener(notifyListeners);
    transfer.progressNotifier.addListener(notifyListeners);
    notifyListeners();
  }

  Future<void> _watch(Transfer transfer, ModelCatalogItem item) async {
    try {
      await transfer.file;
      await _complete(item, transfer);
    } catch (error) {
      _error = '$error';
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingKey);
      notifyListeners();
    }
  }

  Future<File> _complete(
    ModelCatalogItem item,
    Transfer transfer, {
    File? downloadedFile,
  }) async {
    final partial = downloadedFile ?? await transfer.file;
    final bytes = await partial.openRead(0, 4).first;
    if (utf8.decode(bytes, allowMalformed: true) != 'GGUF') {
      await partial.delete();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingKey);
      throw const FormatException(
        'The downloaded file is not a valid GGUF model.',
      );
    }
    final actualHash = await _sha256File(partial);
    if (item.sha256.isNotEmpty &&
        actualHash.toLowerCase() != item.sha256.toLowerCase()) {
      await partial.delete();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pendingKey);
      throw const FormatException('Model SHA-256 verification failed.');
    }
    final destination = File(p.join(partial.parent.path, item.file));
    if (await destination.exists()) await destination.delete();
    final file = await partial.rename(destination.path);
    final repository = _repositories;
    if (repository != null &&
        !repository.models.getAll().any(
          (model) =>
              model.repoId == item.repo &&
              model.filename == item.file &&
              model.localPath == file.path,
        )) {
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
      repository.models.put(model);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingKey);
    _transfer = null;
    _paused = false;
    notifyListeners();
    return file;
  }

  Future<void> pause() async {
    _paused = true;
    await _transfer?.pause();
    notifyListeners();
  }

  Future<void> resume() async {
    _paused = false;
    await _transfer?.resume();
    notifyListeners();
  }

  Future<void> cancel() async {
    await _transfer?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingKey);
    final partial = _item == null
        ? null
        : File(
            p.join(
              (await LocalFiles.modelsDirectory()).path,
              '${_item!.file}.part',
            ),
          );
    if (partial != null && await partial.exists()) await partial.delete();
    _transfer = null;
    _paused = false;
    notifyListeners();
  }

  Future<ModelEntity> importFromDevice({
    void Function(DownloadProgress)? onProgress,
  }) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['gguf'],
      allowMultiple: false,
      withData: false,
    );
    if (result == null ||
        result.files.isEmpty ||
        result.files.first.path == null)
      throw const FileSystemException('No model file was selected.');
    final picked = result.files.first;
    final source = File(picked.path!);
    final bytes = await source.openRead(0, 4).first;
    if (utf8.decode(bytes, allowMalformed: true) != 'GGUF') {
      throw const FormatException(
        'This file is not a valid GGUF model. Choose a .gguf file beginning with the GGUF header.',
      );
    }
    final kind = _looksLikeEmbedding(picked.name) ? 'embedding' : 'llm';
    final dir = await LocalFiles.modelsDirectory();
    final target = File(
      p.join(dir.path, '${const Uuid().v4()}${p.extension(picked.name)}'),
    );
    final total = await source.length();
    final watch = Stopwatch()..start();
    var received = 0;
    final sink = target.openWrite();
    try {
      await for (final chunk in source.openRead()) {
        sink.add(chunk);
        received += chunk.length;
        final speed = received / max(1, watch.elapsedMilliseconds) * 1000;
        onProgress?.call(DownloadProgress(received, total, speed));
      }
    } finally {
      await sink.close();
    }
    return ModelEntity()
      ..uuid = const Uuid().v4()
      ..name = p.basenameWithoutExtension(picked.name)
      ..kind = kind
      ..filename = picked.name
      ..localPath = target.path
      ..sizeBytes = await target.length()
      ..status = 'available'
      ..dimensions = kind == 'embedding' ? 384 : 0;
  }

  static bool _looksLikeEmbedding(String name) =>
      RegExp(r'(bge|embed|minilm|e5)', caseSensitive: false).hasMatch(name);
  static Future<String> _sha256File(File file) async {
    final sink = convert.AccumulatorSink<Digest>();
    final converter = sha256.startChunkedConversion(sink);
    await for (final chunk in file.openRead()) {
      converter.add(chunk);
    }
    converter.close();
    return sink.events.single.toString();
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart' as convert;
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'entities/entities.dart';
import 'repositories.dart';

class ModelCatalogItem {
  const ModelCatalogItem({required this.name, required this.kind, required this.repo,
    required this.file, required this.sizeBytes, required this.ramGb, required this.quantization,
    required this.license, this.dimensions = 0, this.sha256 = ''});
  final String name, kind, repo, file, quantization, license, sha256;
  final int sizeBytes, dimensions;
  final double ramGb;
  String get url => 'https://huggingface.co/$repo/resolve/main/$file';
  static const recommended = <ModelCatalogItem>[
    ModelCatalogItem(name: 'Qwen2.5 1.5B Instruct', kind: 'llm',
      repo: 'bartowski/Qwen2.5-1.5B-Instruct-GGUF', file: 'Qwen2.5-1.5B-Instruct-Q4_K_M.gguf',
      sizeBytes: 986000000, ramGb: 3.0, quantization: 'Q4_K_M', license: 'Apache-2.0'),
    ModelCatalogItem(name: 'BGE Small English v1.5 (llama.cpp)', kind: 'embedding',
      repo: 'CompendiumLabs/bge-small-en-v1.5-gguf', file: 'bge-small-en-v1.5-q4_k_m.gguf',
      sizeBytes: 24000000, ramGb: 1.0, quantization: 'Q4_K_M', license: 'MIT / BAAI license', dimensions: 384),
  ];
}

class DownloadProgress {
  const DownloadProgress(this.received, this.total, this.bytesPerSecond);
  final int received, total;
  final double bytesPerSecond;
  double get fraction => total <= 0 ? 0 : (received / total).clamp(0, 1);
  Duration? get eta => bytesPerSecond <= 0 || total <= 0 ? null : Duration(seconds: ((total - received) / bytesPerSecond).round());
}

class ModelDownloader {
  ModelDownloader({Dio? dio, FlutterSecureStorage? secureStorage})
    : _dio = dio ?? Dio(), _secure = secureStorage ?? const FlutterSecureStorage();
  final Dio _dio;
  final FlutterSecureStorage _secure;
  CancelToken? _cancelToken;
  Completer<void>? _resumeGate;
  bool _paused = false;

  Future<String?> getToken() => _secure.read(key: 'huggingface_token');
  Future<void> saveToken(String token) => token.trim().isEmpty
      ? _secure.delete(key: 'huggingface_token')
      : _secure.write(key: 'huggingface_token', value: token.trim());

  void pause() { _paused = true; _resumeGate = Completer<void>(); }
  void resume() { _paused = false; if (!(_resumeGate?.isCompleted ?? true)) _resumeGate!.complete(); }
  void cancel() { _cancelToken?.cancel('Download cancelled'); resume(); }

  Future<File> download(ModelCatalogItem item, {required void Function(DownloadProgress) onProgress}) async {
    final dir = await LocalFiles.modelsDirectory();
    final destination = File(p.join(dir.path, item.file));
    final partial = File('${destination.path}.part');
    final cancelToken = _cancelToken = CancelToken();
    final token = await getToken();
    Object? lastError;
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        final offset = partial.existsSync() ? await partial.length() : 0;
        final response = await _dio.get<ResponseBody>(item.url,
          cancelToken: cancelToken,
          options: Options(responseType: ResponseType.stream,
            followRedirects: true, headers: {
              if (offset > 0) 'Range': 'bytes=$offset-',
              if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
            }));
        final isPartial = response.statusCode == HttpStatus.partialContent;
        final startAt = isPartial ? offset : 0;
        if (!isPartial && offset > 0) await partial.delete();
        final contentLength = int.tryParse(response.headers.value(Headers.contentLengthHeader) ?? '') ?? 0;
        final total = response.headers.value('content-range')?.split('/').lastOrNull
            .let(int.tryParse) ?? (contentLength + startAt);
        final file = await partial.open(mode: startAt > 0 ? FileMode.append : FileMode.write);
        final watch = Stopwatch()..start();
        var received = startAt;
        try {
          await for (final bytes in response.data!.stream) {
            while (_paused) { await _resumeGate!.future; }
            if (cancelToken.isCancelled) throw DioException(requestOptions: RequestOptions(path: item.url), type: DioExceptionType.cancel);
            await file.writeFrom(bytes);
            received += bytes.length;
            final speed = received / max(1, watch.elapsedMilliseconds) * 1000;
            onProgress(DownloadProgress(received, total, speed));
          }
        } finally { await file.close(); }
        if (total > 0 && received < total) throw const SocketException('Download ended before the expected length.');
        final header = await partial.openRead(0, 4).first;
        if (utf8.decode(header, allowMalformed: true) != 'GGUF') {
          throw const FormatException('The downloaded file is not a valid GGUF model.');
        }
        final actualHash = await _sha256File(partial);
        if (item.sha256.isNotEmpty && actualHash.toLowerCase() != item.sha256.toLowerCase()) {
          throw const FormatException('Model SHA-256 verification failed.');
        }
        await partial.rename(destination.path);
        return destination;
      } catch (error) {
        lastError = error;
        if (error is DioException && CancelToken.isCancel(error)) rethrow;
        if (attempt == 3) break;
        await Future<void>.delayed(Duration(milliseconds: 500 * (1 << attempt)));
      }
    }
    throw StateError('Model download failed: $lastError');
  }

  Future<ModelEntity> importFromDevice({void Function(DownloadProgress)? onProgress}) async {
    final result = await FilePicker.pickFiles(type: FileType.custom,
      allowedExtensions: const ['gguf'], allowMultiple: false, withData: false);
    if (result == null || result.files.isEmpty || result.files.first.path == null) throw const FileSystemException('No model file was selected.');
    final picked = result.files.first;
    final source = File(picked.path!);
    final bytes = await source.openRead(0, 4).first;
    if (utf8.decode(bytes, allowMalformed: true) != 'GGUF') {
      throw const FormatException('This file is not a valid GGUF model. Choose a .gguf file beginning with the GGUF header.');
    }
    final kind = _looksLikeEmbedding(picked.name) ? 'embedding' : 'llm';
    final dir = await LocalFiles.modelsDirectory();
    final target = File(p.join(dir.path, '${const Uuid().v4()}${p.extension(picked.name)}'));
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

  static bool _looksLikeEmbedding(String name) => RegExp(r'(bge|embed|minilm|e5)', caseSensitive: false).hasMatch(name);

  static Future<String> _sha256File(File file) async {
    final sink = convert.AccumulatorSink<Digest>();
    final converter = sha256.startChunkedConversion(sink);
    await for (final chunk in file.openRead()) { converter.add(chunk); }
    converter.close();
    return sink.events.single.toString();
  }
}

extension _NullableLet<T> on T? {
  R? let<R>(R? Function(T) fn) => this == null ? null : fn(this as T);
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/models/image_service_config.dart';

class StableDiffusionImageService {
  StableDiffusionImageService({Dio? dio, FlutterSecureStorage? secureStorage})
    : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 8))),
      _secure = secureStorage ?? const FlutterSecureStorage();
  final Dio _dio;
  final FlutterSecureStorage _secure;
  static const maxResponseBytes = 12 * 1024 * 1024;

  String _tokenKey(ImageServiceConfig config) => 'image_service_${sha256.convert(utf8.encode('${config.addressUri().origin}\u0000${config.username}'))}';
  Future<String?> getToken(ImageServiceConfig config) => _secure.read(key: _tokenKey(config));
  Future<void> saveToken(ImageServiceConfig config, String token) => token.trim().isEmpty
    ? _secure.delete(key: _tokenKey(config)) : _secure.write(key: _tokenKey(config), value: token.trim());

  Future<String> generate(String prompt, ImageServiceConfig config, {CancelToken? cancelToken}) async {
    if (!config.enabled) throw StateError('Image generation is disabled. Configure a Stable Diffusion image service in Settings → Image Generation. Local diagrams do not need this service.');
    final uri = config.checkedUri();
    if (prompt.trim().isEmpty || prompt.length > 1200) throw const FormatException('Use a shorter, non-empty image prompt.');
    final cancellation = cancelToken ?? CancelToken();
    try {
      return await _request(prompt, config, uri, cancellation).timeout(const Duration(minutes: 4), onTimeout: () {
        cancellation.cancel('Image generation timed out');
        throw StateError('The image server took too long. Your text answer is saved; try regenerating the image.');
      });
    } on DioException catch (error) {
      final message = switch (error.type) {
        DioExceptionType.cancel => 'Image generation was cancelled.',
        DioExceptionType.connectionTimeout || DioExceptionType.receiveTimeout || DioExceptionType.sendTimeout => 'The image server timed out. Check that it is running, then regenerate the image.',
        DioExceptionType.badResponse => 'The image server rejected the request (HTTP ${error.response?.statusCode ?? 'error'}). Check its model and API settings.',
        _ => 'The image server is unavailable. Start it with API access enabled and check your connection. Text and local diagrams still work offline.',
      };
      throw StateError(message);
    }
  }

  Future<String> _request(String prompt, ImageServiceConfig config, Uri base, CancelToken cancellation) async {
    final token = await getToken(config);
    final path = '${base.path.replaceFirst(RegExp(r'/+$'), '')}/sdapi/v1/txt2img';
    final response = await _dio.post<ResponseBody>(base.replace(path: path).toString(),
      cancelToken: cancellation,
      data: {'prompt': prompt, 'negative_prompt': 'watermark, blurry, illegible text',
        'steps': 20, 'width': 512, 'height': 512, 'batch_size': 1, 'n_iter': 1,
        'seed': -1, 'send_images': true, 'save_images': false},
      options: Options(responseType: ResponseType.stream, followRedirects: false,
        receiveTimeout: const Duration(minutes: 4), sendTimeout: const Duration(seconds: 20),
        headers: {if (token != null && token.isNotEmpty) 'Authorization': config.username.isEmpty
          ? 'Bearer $token' : 'Basic ${base64Encode(utf8.encode('${config.username}:$token'))}'}));
    final length = int.tryParse(response.headers.value(Headers.contentLengthHeader) ?? '') ?? 0;
    if (length > maxResponseBytes) {
      cancellation.cancel('Image response too large');
      throw const FormatException('The image server returned too much data. Request a smaller image.');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final part in response.data!.stream) {
      if (bytes.length + part.length > maxResponseBytes) {
        cancellation.cancel('Image response too large');
        throw const FormatException('The image server returned too much data. Request a smaller image.');
      }
      bytes.add(part);
    }
    Object? value;
    try {
      value = jsonDecode(utf8.decode(bytes.takeBytes()));
    } on FormatException {
      throw const FormatException('The image server returned invalid JSON. Check its API address and configuration.');
    }
    final images = value is Map<String, dynamic> ? value['images'] : null;
    if (images is! List || images.isEmpty || images.first is! String) {
      throw const FormatException('The image server returned no image. Check that an image model is loaded.');
    }
    return normalizeImage(images.first as String);
  }

  static Future<String> normalizeImage(String encoded) async {
    encoded = encoded.replaceFirst(RegExp(r'^data:image/(?:png|jpeg|webp);base64,'), '').trim();
    if (encoded.length > maxResponseBytes) throw const FormatException('The generated image is too large to save.');
    final bytes = base64Decode(encoded);
    if (bytes.length < 24 || bytes.length > 8 * 1024 * 1024) throw const FormatException('The image server returned invalid image data.');
    final png = bytes.take(8).toList().asMap().entries.every((entry) => entry.value == const [137, 80, 78, 71, 13, 10, 26, 10][entry.key]);
    final jpeg = bytes[0] == 255 && bytes[1] == 216 && bytes[2] == 255;
    final webp = ascii.decode(bytes.take(4).toList(), allowInvalid: true) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP';
    if (!png && !jpeg && !webp) throw const FormatException('The image server must return a PNG, JPEG or WebP image.');
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    try {
      try {
        descriptor = await ui.ImageDescriptor.encoded(buffer);
      } catch (_) {
        throw const FormatException('The image server returned a corrupt or unsupported image.');
      }
      final width = descriptor.width;
      final height = descriptor.height;
      if (width == 0 || height == 0 || width > 4096 || height > 4096 || width * height > 16777216) {
        throw const FormatException('The generated image dimensions are unsupported. Request a smaller image.');
      }
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }
    return base64Encode(bytes);
  }
}

import 'dart:convert';

class ImageServiceConfig {
  const ImageServiceConfig({this.enabled = false, this.endpoint = 'http://127.0.0.1:7860', this.allowRemote = false, this.username = ''});
  final bool enabled, allowRemote;
  final String endpoint, username;

  bool get isOnDevice => {'localhost', '127.0.0.1', '::1', '[::1]'}.contains(Uri.tryParse(endpoint.trim())?.host.toLowerCase());

  Uri addressUri() {
    final uri = Uri.tryParse(endpoint.trim());
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty || !{'http', 'https'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
      throw const FormatException('Enter an HTTP(S) server address without embedded credentials, query parameters or a fragment.');
    }
    if (username.length > 200 || username.contains(':') || RegExp(r'[\x00-\x1f]').hasMatch(username)) {
      throw const FormatException('Enter an API username without a colon or control characters.');
    }
    return uri;
  }

  Uri checkedUri() {
    final uri = addressUri();
    if (!isOnDevice && uri.scheme != 'https') throw const FormatException('Use HTTPS for image servers outside this device.');
    if (!isOnDevice && !allowRemote) throw const FormatException('Allow sending image prompts outside this device before enabling this server.');
    return uri;
  }

  String encode() => jsonEncode({'enabled': enabled, 'endpoint': endpoint, 'allowRemote': allowRemote, 'username': username});
  static ImageServiceConfig decode(String? encoded) {
    if (encoded == null) return const ImageServiceConfig();
    try {
      final value = jsonDecode(encoded) as Map<String, dynamic>;
      return ImageServiceConfig(enabled: value['enabled'] as bool? ?? false,
        endpoint: value['endpoint'] as String? ?? 'http://127.0.0.1:7860', allowRemote: value['allowRemote'] as bool? ?? false,
        username: value['username'] as String? ?? '');
    } catch (_) {
      return const ImageServiceConfig();
    }
  }
}

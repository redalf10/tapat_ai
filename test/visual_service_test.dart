import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapat_ai/data/ai/engines.dart';
import 'package:tapat_ai/data/ai/image_generation_service.dart';
import 'package:tapat_ai/data/ai/local_rag_service.dart';
import 'package:tapat_ai/data/ai/local_text_service.dart';
import 'package:tapat_ai/data/ai/local_visual_service.dart';
import 'package:tapat_ai/data/entities/entities.dart';
import 'package:tapat_ai/domain/models/image_service_config.dart';
import 'package:tapat_ai/domain/models/message_model.dart';
import 'package:tapat_ai/domain/models/source_ref_model.dart';
import 'package:tapat_ai/domain/models/visual_model.dart';
import 'package:tapat_ai/presentation/chat/visual_widget.dart';

const _png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+Xlo0AAAAASUVORK5CYII=';

void main() {
  _ServiceTestBinding();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('visual intent', () {
    for (final question in [
      'Create a flowchart showing how login authentication works.',
      'Visualize the RAG pipeline.',
      'Show me a diagram of how NFC communicates with a mobile application.',
      'Draw a system architecture diagram.',
      'Create a workflow for document indexing.',
    ]) {
      test('detects $question', () => expect(VisualIntent.detect(question)?.kind, VisualKind.diagram));
    }
    for (final question in ['Generate an image explaining the water cycle.', 'Create an illustration of a garden.', 'Draw a picture of a cat.']) {
      test('detects $question', () => expect(VisualIntent.detect(question)?.kind, VisualKind.image));
    }
    for (final question in [
      'What is 2 + 2?', 'What is a flowchart?', 'Summarize my notes.',
      'How do I generate images with Stable Diffusion?',
      'Explain the water cycle, text only.', 'Explain the RAG pipeline without a diagram.',
      'Please do not generate any images for this answer.', 'Generate a text summary of the flowchart.',
    ]) {
      test('keeps text-only: $question', () => expect(VisualIntent.detect(question), isNull));
    }
    test('suggests a local diagram only for an explanatory process question', () {
      final intent = VisualIntent.detect('Explain how the RAG pipeline works.');
      expect(intent?.kind, VisualKind.diagram);
      expect(intent?.explicit, isFalse);
      expect(VisualIntent.refersToDocuments('Generate an image from my uploaded documents.'), isTrue);
      expect(VisualIntent.refersToDocuments('Draw a cat in a garden.'), isFalse);
    });
  });

  group('local text and visual generation', () {
    test('uses the local engine without embeddings or network access', () async {
      final llm = _TextEngine()..answer = 'A locally generated tutorial.';
      final text = await LocalTextService(llm).generateDocument('Write a tutorial.');
      expect(text, llm.answer);
      expect(llm.prompts.single, 'Write a tutorial.');
      expect(llm.systems.single, contains('editable document'));
      expect(llm.parameters.single.maxTokens, 768);
    });
    test('rejects empty or oversized prompts and empty model output', () async {
      final llm = _TextEngine();
      final text = LocalTextService(llm);
      await expectLater(text.generateDocument('  '), throwsFormatException);
      await expectLater(text.generateDocument(List.filled(801, 'é').join()), throwsFormatException);
      expect(llm.prompts, isEmpty);
      llm.answer = '';
      await expectLater(text.generateDocument('Write notes.'), throwsStateError);
      expect(LocalTextService.truncateUtf8('café 漢字', 6), 'café ');
    });
    test('parses a genuine model-generated graph and derives its breakdown', () async {
      final llm = _TextEngine()..answer = '```json\n${jsonEncode(_graph())}\n```';
      final visual = await LocalVisualService(LocalTextService(llm)).describe(
        const VisualIntent(VisualKind.diagram), 'Draw authentication.', 'Validate credentials and allow or deny access.');
      expect(visual.status, VisualStatus.ready);
      expect(visual.request, 'Draw authentication.');
      expect(visual.diagram!.edges.where((edge) => edge.from == 'check').map((edge) => edge.label), ['Yes', 'No']);
      expect(visual.breakdown, hasLength(4));
      expect(visual.imageBase64, isEmpty);
      expect(llm.prompts.single, contains('Validate credentials'));
      expect(llm.systems.single, contains('Use only supported relationships'));
    });
    test('image specifications are not misrepresented as image pixels', () async {
      final llm = _TextEngine()..answer = jsonEncode({'title': 'Water cycle', 'caption': 'An educational illustration.',
        'prompt': 'Water evaporating, clouds condensing and rain falling.', 'breakdown': ['Evaporation rises from the lake.', 'Rain returns water.']});
      final visual = await LocalVisualService(LocalTextService(llm)).describe(
        const VisualIntent(VisualKind.image), 'Illustrate the water cycle.', 'Water evaporates, condenses and falls as rain.');
      expect(visual.status, VisualStatus.loading);
      expect(visual.hasContent, isFalse);
      expect(visual.generationPrompt, contains('clouds'));
    });
    test('invalid model output is an error, never a fabricated fallback diagram', () async {
      final llm = _TextEngine()..answer = 'I cannot supply JSON.';
      await expectLater(LocalVisualService(LocalTextService(llm)).describe(
        const VisualIntent(VisualKind.diagram), 'Draw a flowchart.', 'A clear explanation.'), throwsFormatException);
    });
  });

  group('diagram validation and layout', () {
    test('rejects unknown connections, duplicated IDs and unlabelled decisions', () {
      final unknown = _graph();
      (unknown['edges'] as List).first['to'] = 'missing';
      expect(() => DiagramData.fromJson(unknown), throwsFormatException);
      final duplicate = _graph();
      (duplicate['nodes'] as List).last['id'] = 'start';
      expect(() => DiagramData.fromJson(duplicate), throwsFormatException);
      final unlabelled = _graph();
      (unlabelled['edges'] as List)[1]['label'] = '';
      expect(() => DiagramData.fromJson(unlabelled), throwsFormatException);
    });
    test('keeps joins below all predecessor steps in a branched workflow', () {
      final value = _graph();
      value['nodes'] = [
        {'id': 'start', 'label': 'Start', 'description': 'Start the workflow.', 'kind': 'start'},
        {'id': 'check', 'label': 'Needs extra checks?', 'description': 'Choose a branch.', 'kind': 'decision'},
        {'id': 'extra', 'label': 'Extra check', 'description': 'Do additional work.', 'kind': 'process'},
        {'id': 'verify', 'label': 'Verify', 'description': 'Verify the extra work.', 'kind': 'process'},
        {'id': 'end', 'label': 'End', 'description': 'Finish both branches.', 'kind': 'end'},
      ];
      value['edges'] = [
        {'from': 'start', 'to': 'check'}, {'from': 'check', 'to': 'extra', 'label': 'Yes'},
        {'from': 'check', 'to': 'end', 'label': 'No'}, {'from': 'extra', 'to': 'verify'}, {'from': 'verify', 'to': 'end'},
      ];
      final graph = DiagramData.fromJson(value);
      final layout = DiagramLayout(graph, 700, ColorScheme.fromSeed(seedColor: Colors.blue), TextScaler.noScaling, TextDirection.ltr);
      for (final edge in graph.edges) {
        expect(layout.rects[edge.to]!.top, greaterThan(layout.rects[edge.from]!.bottom));
      }
    });
    test('supports cycles, small screens, dark themes and large accessible text', () {
      final graph = DiagramData.fromJson({'title': 'Cycle', 'nodes': [
        for (final id in ['a', 'b', 'c']) {'id': id, 'label': 'A clearly labelled stage $id', 'description': 'Stage $id in the cycle.', 'kind': 'process'},
      ], 'edges': [{'from': 'a', 'to': 'b'}, {'from': 'b', 'to': 'c'}, {'from': 'c', 'to': 'a'}]});
      final layout = DiagramLayout(graph, 320, ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
        const TextScaler.linear(2.5), TextDirection.ltr);
      expect(layout.height.isFinite, isTrue);
      for (final rect in layout.rects.values) {
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(320));
        expect(rect.height, greaterThan(0));
        expect(rect.bottom, lessThanOrEqualTo(layout.height));
        expect(layout.rects.values.where((other) => other != rect && other.overlaps(rect)), isEmpty);
      }
      expect(graph.accessibleDescription, contains('Stage a'));
    });
  });

  group('visual persistence', () {
    test('round-trips message ID, timestamps, sources and graph data', () {
      final topic = TopicEntity()..id = 1..uuid = 'topic'..name = 'Topic'..createdAt = DateTime(2026);
      final graph = DiagramData.fromJson(_graph());
      final visual = ChatVisual(kind: VisualKind.diagram, status: VisualStatus.ready, request: 'Draw authentication.',
        title: graph.title, diagram: graph, breakdown: const ['Validate credentials.']);
      final message = Message('An unchanged explanation.', false, [SourceRef('notes.txt', 1)], DateTime(2026, 10, 1), 17, visual);
      final restored = fromChatEntity(toChatEntity(topic, message));
      expect(restored.id, 17);
      expect(restored.sentAt, message.sentAt);
      expect(restored.sources.single.docName, 'notes.txt');
      expect(restored.text, message.text);
      expect(restored.visual!.diagram!.nodes.length, 4);
      expect(restored.visual!.request, visual.request);
    });
    test('restores interrupted and corrupt visuals without breaking the text message', () {
      final pending = const ChatVisual(kind: VisualKind.image, status: VisualStatus.loading, request: 'Draw a cat.');
      expect(ChatVisual.restore(pending.encode())!.status, VisualStatus.error);
      expect(ChatVisual.restore(pending.encode())!.error, contains('interrupted'));
      expect(ChatVisual.restore('not json')!.status, VisualStatus.error);
      expect(ChatVisual.restore(''), isNull);
    });
  });

  group('optional image service', () {
    test('requires opt-in, HTTPS for other devices, and credential-free URLs', () async {
      final service = StableDiffusionImageService();
      await expectLater(service.generate('A cat.', const ImageServiceConfig()), throwsStateError);
      expect(() => const ImageServiceConfig(enabled: true, endpoint: 'http://192.168.1.2:7860', allowRemote: true).checkedUri(), throwsFormatException);
      expect(() => const ImageServiceConfig(enabled: true, endpoint: 'https://example.com').checkedUri(), throwsFormatException);
      expect(() => const ImageServiceConfig(enabled: true, endpoint: 'https://user:password@example.com', allowRemote: true).checkedUri(), throwsFormatException);
      expect(() => const ImageServiceConfig(endpoint: 'http://127.0.0.1:7860/?token=secret').checkedUri(), throwsFormatException);
      expect(const ImageServiceConfig(enabled: true).checkedUri().host, '127.0.0.1');
    });
    test('calls the real WebUI-compatible HTTP API and securely scopes credentials', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final received = <(String, String?, Map<String, dynamic>)>[];
      final subscription = server.listen((request) async {
        final payload = jsonDecode(await utf8.decoder.bind(request).join()) as Map<String, dynamic>;
        received.add((request.uri.path, request.headers.value('authorization'), payload));
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'images': [_png]}));
        await request.response.close();
      });
      addTearDown(subscription.cancel);
      final config = ImageServiceConfig(enabled: true, endpoint: 'http://127.0.0.1:${server.port}/prefix');
      final service = StableDiffusionImageService();
      await service.saveToken(config, 'test-token');
      final encoded = await service.generate('An educational water cycle.', config);
      expect(base64Decode(encoded), base64Decode(_png));
      expect(received.single.$1, '/prefix/sdapi/v1/txt2img');
      expect(received.single.$2, 'Bearer test-token');
      expect(received.single.$3['prompt'], 'An educational water cycle.');
      expect(received.single.$3['width'], 512);
      expect(received.single.$3['batch_size'], 1);
      final basic = ImageServiceConfig(enabled: true, endpoint: config.endpoint, username: 'test-user');
      await service.saveToken(basic, 'test-password');
      await service.generate('A cat.', basic);
      expect(received.last.$2, 'Basic ${base64Encode(utf8.encode('test-user:test-password'))}');
      expect(await service.getToken(ImageServiceConfig(endpoint: 'http://localhost:${server.port}')), isNull);
      expect(config.encode(), isNot(contains('test-token')));
    });
    test('unavailable local servers report offline failure without leaking credentials', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final config = ImageServiceConfig(enabled: true, endpoint: 'http://127.0.0.1:${server.port}');
      await server.close(force: true);
      final service = StableDiffusionImageService();
      await service.saveToken(config, 'not-a-real-secret');
      await expectLater(service.generate('A cat.', config), throwsA(isA<StateError>()
        .having((error) => error.message, 'message', contains('unavailable'))
        .having((error) => error.message, 'message', isNot(contains('not-a-real-secret')))));
    });
    test('rejects malformed replies, oversized responses and corrupt image data', () async {
      final adapter = _ReplyAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final service = StableDiffusionImageService(dio: dio);
      const config = ImageServiceConfig(enabled: true);
      adapter.body = '{}';
      await expectLater(service.generate('A cat.', config), throwsFormatException);
      adapter.body = '<html>Not an API response</html>';
      await expectLater(service.generate('A cat.', config), throwsFormatException);
      adapter.body = jsonEncode({'images': ['not base64']});
      await expectLater(service.generate('A cat.', config), throwsFormatException);
      adapter.body = jsonEncode({'images': [_png]});
      adapter.length = StableDiffusionImageService.maxResponseBytes + 1;
      await expectLater(service.generate('A cat.', config), throwsFormatException);
      await expectLater(StableDiffusionImageService.normalizeImage(base64Encode(Uint8List(40))), throwsFormatException);
      expect(await StableDiffusionImageService.normalizeImage('data:image/png;base64,$_png'), _png);
    });
    test('does not follow redirects or forward tokens to another endpoint', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var count = 0;
      final subscription = server.listen((request) async {
        count++;
        request.response.statusCode = 307;
        request.response.headers.set(HttpHeaders.locationHeader, 'http://127.0.0.1:${server.port}/other');
        await request.response.close();
      });
      addTearDown(subscription.cancel);
      final config = ImageServiceConfig(enabled: true, endpoint: 'http://127.0.0.1:${server.port}');
      final service = StableDiffusionImageService();
      await service.saveToken(config, 'test-token');
      await expectLater(service.generate('A cat.', config), throwsA(isA<StateError>().having((error) => error.message, 'message', contains('307'))));
      expect(count, 1);
    });
  });
}

class _ServiceTestBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

class _TextEngine implements LlmEngine {
  String answer = '';
  final prompts = <String>[];
  final systems = <String>[];
  final parameters = <GenParams>[];
  @override
  Stream<String> generate(String prompt, {String? systemPrompt, GenParams params = const GenParams()}) async* {
    prompts.add(prompt);
    systems.add(systemPrompt ?? '');
    parameters.add(params);
    yield answer;
  }
  @override
  Future<void> load(ModelEntity model) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> unload() async {}
}

class _ReplyAdapter implements HttpClientAdapter {
  String body = '{}';
  int? length;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
    ResponseBody.fromString(body, 200, headers: {Headers.contentTypeHeader: [Headers.jsonContentType],
      if (length != null) Headers.contentLengthHeader: ['$length']});
  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _graph() => {'title': 'Authentication', 'nodes': [
  {'id': 'start', 'label': 'Login request', 'description': 'The user submits credentials.', 'kind': 'start'},
  {'id': 'check', 'label': 'Credentials valid?', 'description': 'Validate the supplied credentials.', 'kind': 'decision'},
  {'id': 'allow', 'label': 'Allow access', 'description': 'A valid user gets access.', 'kind': 'end'},
  {'id': 'deny', 'label': 'Deny access', 'description': 'Invalid credentials are rejected.', 'kind': 'end'},
], 'edges': [{'from': 'start', 'to': 'check'}, {'from': 'check', 'to': 'allow', 'label': 'Yes'}, {'from': 'check', 'to': 'deny', 'label': 'No'}]};

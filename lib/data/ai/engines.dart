import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import '../entities/entities.dart';

class GenParams {
  const GenParams({this.maxTokens = 512, this.temperature = .2, this.topP = .9});
  final int maxTokens;
  final double temperature;
  final double topP;
}

Future<LlamaEngine> _spawnEngine({required ModelParams modelParams, required ContextParams contextParams}) =>
    Platform.isIOS
        ? LlamaEngine.spawnFromProcess(modelParams: modelParams, contextParams: contextParams)
        : LlamaEngine.spawn(modelParams: modelParams, contextParams: contextParams);

String embeddingModelIndexId(ModelEntity model) {
  return '${model.uuid}:auto-byte480-v1';
}

abstract interface class LlmEngine {
  Future<void> load(ModelEntity model);
  Stream<String> generate(String prompt, {String? systemPrompt, GenParams params = const GenParams()});
  Future<void> stop();
  Future<void> unload();
}

abstract interface class EmbeddingEngine {
  int get dimensions;
  String? get modelId;
  Future<void> load(ModelEntity model);
  Future<List<double>> embed(String text);
  Future<List<List<double>>> embedBatch(List<String> texts);
  Future<void> unload();
}

class OnDeviceLlamaEngine implements LlmEngine {
  LlamaEngine? _engine;
  EngineChat? _chat;
  bool get isLoaded => _chat != null;

  @override
  Future<void> load(ModelEntity model) async {
    await unload();
    if (!File(model.localPath).existsSync()) throw StateError('The selected model file is missing.');
    final llm = await _spawnEngine(
      modelParams: ModelParams(path: model.localPath, gpuLayers: 0),
      contextParams: ContextParams.mobile(nCtx: 2048, nBatch: 128, nUbatch: 128),
    );
    _engine = llm;
    _chat = await llm.createChat();
  }

  @override
  Stream<String> generate(String prompt, {String? systemPrompt, GenParams params = const GenParams()}) async* {
    final chat = _chat;
    if (chat == null) throw StateError('Load an active local language model first.');
    chat.clearHistory();
    if (systemPrompt != null && systemPrompt.isNotEmpty) chat.addSystem(systemPrompt);
    chat.addUser(prompt);
    await for (final event in chat.generate(
      sampler: SamplerParams(temperature: params.temperature, topP: params.topP),
      maxTokens: params.maxTokens.clamp(1, 1024),
      shiftPolicy: _engine!.canShift ? ContextShiftPolicy.auto : ContextShiftPolicy.off,
    )) {
      if (event case TokenEvent(:final text)) yield text;
      if (event case DoneEvent(:final trailingText)) {
        if (trailingText.isNotEmpty) yield trailingText;
        break;
      }
    }
  }

  @override
  Future<void> stop() async {
    final engine = _engine;
    final chat = _chat;
    if (engine == null || chat == null) return;
    _chat = null;
    await chat.dispose();
    _chat = await engine.createChat();
  }

  @override
  Future<void> unload() async {
    await _chat?.dispose();
    _chat = null;
    await _engine?.dispose();
    _engine = null;
  }
}

class OnDeviceEmbeddingEngine implements EmbeddingEngine {
  LlamaEngine? _engine;
  int _dimensions = 0;
  final _cache = <String, List<double>>{};
  @override
  String? modelId;
  @override
  int get dimensions => _dimensions;
  bool get isLoaded => _engine != null;

  @override
  Future<void> load(ModelEntity model) async {
    await unload();
    if (!File(model.localPath).existsSync()) throw StateError('The selected embedding model file is missing.');
    final engine = await _spawnEngine(
      modelParams: ModelParams(path: model.localPath, gpuLayers: 0),
      contextParams: const ContextParams(
        nCtx: 512, nBatch: 512, nUbatch: 512, nSeqMax: 1, nThreads: 4,
        embeddings: true, poolingType: PoolingType.auto,
        attentionType: AttentionType.nonCausal,
      ),
    );
    _engine = engine;
    modelId = embeddingModelIndexId(model);
    final probe = await engine.embed('dimension probe');
    _dimensions = probe.nEmbd;
    if (!probe.pooled || _dimensions <= 0) {
      await unload();
      throw StateError('The selected model did not return pooled text embeddings. Check that it is a compatible GGUF embedding model.');
    }
    if (model.dimensions > 0 && _dimensions != model.dimensions) {
      await unload();
      throw StateError('The selected model returned $_dimensions dimensions, but its catalog entry expects ${model.dimensions}.');
    }
  }

  @override
  Future<List<double>> embed(String text) async => (await embedBatch([text])).single;

  @override
  Future<List<List<double>>> embedBatch(List<String> texts) async {
    if (texts.isEmpty) return const [];
    final engine = _engine;
    if (engine == null) throw StateError('Load an active embedding model first.');
    final vectors = <List<double>>[];
    for (var i = 0; i < texts.length; i++) {
      final text = texts[i];
      final cached = _cache[text];
      if (cached != null) {
        vectors.add(List<double>.of(cached));
        continue;
      }

      final passages = <String>[];
      var passage = StringBuffer();
      var bytes = 0;
      for (final rune in text.runes) {
        final character = String.fromCharCode(rune);
        final length = utf8.encode(character).length;
        if (bytes + length > 480) {
          passages.add(passage.toString());
          passage = StringBuffer();
          bytes = 0;
        }
        passage.write(character);
        bytes += length;
      }
      if (passage.isNotEmpty) passages.add(passage.toString());
      if (passages.isEmpty) {
        throw StateError('Cannot embed an empty text chunk.');
      }

      final sum = List<double>.filled(_dimensions, 0);
      for (var partIndex = 0; partIndex < passages.length; partIndex++) {
        try {
          final result = await engine.embed(passages[partIndex]);
          if (!result.pooled || result.nEmbd != _dimensions || result.vector.length != _dimensions) {
            throw StateError('Embedding output dimension changed.');
          }
          for (var j = 0; j < _dimensions; j++) {
            sum[j] += result.vector[j] * result.nTokens;
          }
        } catch (error) {
          throw StateError('Embedding failed on chunk ${i + 1} of ${texts.length}, passage ${partIndex + 1} of ${passages.length}: $error');
        }
      }
      final vector = normalizeVector(sum);
      if (_cache.length >= 64) _cache.remove(_cache.keys.first);
      _cache[text] = vector;
      vectors.add(List<double>.of(vector));
    }
    return vectors;
  }

  @override
  Future<void> unload() async {
    await _engine?.dispose();
    _engine = null;
    _dimensions = 0;
    modelId = null;
    _cache.clear();
  }
}

class PromptBuilder {
  static const systemPrompt = 'Answer from the supplied document context. If the context does not contain the answer, say: "I couldn\'t find that in your documents." Cite relevant sources using [1], [2], etc.';

  /// Builds plain user content; llama.cpp applies the template embedded in the
  /// selected GGUF through EngineChat.
  static String buildUserMessage({required String question, required List<String> context}) {
    final joinedContext = [for (var i = 0; i < context.length; i++) '[${i + 1}] ${context[i]}'].join('\n\n');
    return 'DOCUMENT CONTEXT:\n$joinedContext\n\nQUESTION:\n$question';
  }

  static String build({required String modelName, required String question,
    required List<String> context, required List<String> history}) {
    final family = modelName.toLowerCase();
    final system = 'Answer only from the numbered document context. If it does not contain the answer, say exactly: "I couldn\'t find that in your documents." Cite relevant context using [1], [2], etc.';
    final joinedContext = [for (var i = 0; i < context.length; i++) '[${i + 1}] ${context[i]}'].join('\n\n');
    final user = 'DOCUMENT CONTEXT:\n$joinedContext\n\nQUESTION:\n$question';
    final historyText = history.join('\n');
    if (family.contains('gemma')) {
      return '<start_of_turn>system\n$system<end_of_turn>\n$historyText\n<start_of_turn>user\n$user<end_of_turn>\n<start_of_turn>model\n';
    }
    if (family.contains('llama-3') || family.contains('llama 3')) {
      return '<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n$system<|eot_id|>\n$historyText\n<|start_header_id|>user<|end_header_id|>\n$user<|eot_id|>\n<|start_header_id|>assistant<|end_header_id|>\n';
    }
    // ChatML is the native template used by Qwen and many instruct GGUFs.
    return '<|im_start|>system\n$system<|im_end|>\n$historyText\n<|im_start|>user\n$user<|im_end|>\n<|im_start|>assistant\n';
  }
}

List<double> normalizeVector(List<double> values) {
  final norm = math.sqrt(values.fold<double>(0, (sum, value) => sum + value * value));
  if (norm == 0 || !norm.isFinite) throw StateError('Embedding model returned an empty vector.');
  return values.map((v) => v / norm).toList(growable: false);
}

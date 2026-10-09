import 'dart:async';
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
  final isBge = '${model.name} ${model.repoId}'.toLowerCase().contains('bge');
  return '${model.uuid}:${isBge ? 'bge-cls-v1' : 'mean-v1'}';
}

abstract interface class LlmEngine {
  Future<void> load(ModelEntity model);
  Stream<String> generate(String prompt, {GenParams params = const GenParams()});
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
  EngineSession? _session;
  bool get isLoaded => _session != null;

  @override
  Future<void> load(ModelEntity model) async {
    await unload();
    if (!File(model.localPath).existsSync()) throw StateError('The selected model file is missing.');
    final llm = await _spawnEngine(
      modelParams: ModelParams(path: model.localPath, gpuLayers: 0),
      contextParams: ContextParams.mobile(nCtx: 2048, nBatch: 128, nUbatch: 128),
    );
    _engine = llm;
    _session = await llm.createSession();
  }

  @override
  Stream<String> generate(String prompt, {GenParams params = const GenParams()}) async* {
    final session = _session;
    if (session == null) throw StateError('Load an active local language model first.');
    await for (final event in session.generate(
      prompt: prompt,
      sampler: SamplerParams(temperature: params.temperature, topP: params.topP),
      maxTokens: params.maxTokens.clamp(1, 1024),
      shiftPolicy: _engine!.canShift ? ContextShiftPolicy.auto : ContextShiftPolicy.off,
    )) {
      if (event case TokenEvent(:final text)) yield text;
      if (event is DoneEvent) break;
    }
  }

  @override
  Future<void> stop() async {
    final engine = _engine;
    final session = _session;
    if (engine == null || session == null) return;
    await session.dispose();
    _session = await engine.createSession();
  }

  @override
  Future<void> unload() async {
    await _session?.dispose();
    _session = null;
    await _engine?.dispose();
    _engine = null;
  }
}

class OnDeviceEmbeddingEngine implements EmbeddingEngine {
  LlamaEngine? _engine;
  int _dimensions = 0;
  bool _bgePrefix = false;
  @override
  String? modelId;
  @override
  int get dimensions => _dimensions;
  bool get isLoaded => _engine != null;

  @override
  Future<void> load(ModelEntity model) async {
    await unload();
    if (!File(model.localPath).existsSync()) throw StateError('The selected embedding model file is missing.');
    final isBge = '${model.name} ${model.repoId}'.toLowerCase().contains('bge');
    final engine = await _spawnEngine(
      modelParams: ModelParams(path: model.localPath, gpuLayers: 0),
      contextParams: ContextParams(
        nCtx: 512, nBatch: 128, nUbatch: 128, nSeqMax: 8,
        embeddings: true, poolingType: isBge ? PoolingType.cls : PoolingType.mean,
        attentionType: AttentionType.nonCausal,
      ),
    );
    _engine = engine;
    modelId = embeddingModelIndexId(model);
    _bgePrefix = isBge;
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
    for (var i = 0; i < texts.length; i += 8) {
      final end = (i + 8).clamp(0, texts.length);
      final batch = texts.sublist(i, end).map((text) =>
        _bgePrefix ? 'Represent this sentence for searching relevant passages: $text' : text).toList();
      late final List<EmbeddingResult> results;
      try {
        results = await engine.embedBatch(batch, normalize: true);
      } catch (error) {
        throw StateError('The embedding engine failed on chunk batch ${i + 1}–$end. The text may exceed the model context or the model may not support embedding: $error');
      }
      if (results.any((result) => !result.pooled || result.nEmbd != _dimensions)) {
        throw StateError('Embedding output dimension changed. Re-index documents before continuing.');
      }
      vectors.addAll(results.map((result) => result.vector.map((e) => e.toDouble()).toList(growable: false)));
    }
    return vectors;
  }

  @override
  Future<void> unload() async {
    await _engine?.dispose();
    _engine = null;
    _dimensions = 0;
    modelId = null;
  }
}

class PromptBuilder {
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

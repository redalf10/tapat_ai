import 'dart:convert';

import '../../domain/models/visual_model.dart';
import 'engines.dart';
import 'local_text_service.dart';

class LocalVisualService {
  const LocalVisualService(this.text);
  final LocalTextService text;

  Future<ChatVisual> describe(VisualIntent intent, String request, String explanation) async {
    final prompt = 'REQUEST: ${LocalTextService.truncateUtf8(request, 260)}\n'
        'EXPLANATION: ${LocalTextService.truncateUtf8(explanation, 640)}';
    final diagram = intent.kind == VisualKind.diagram;
    final output = await text.generate(prompt,
      systemPrompt: diagram
        ? 'Convert the explanation to a small directed diagram. Use only supported relationships. '
          'Return JSON only: {"title":"...","nodes":[{"id":"a","label":"...","description":"...","kind":"process"}],'
          '"edges":[{"from":"a","to":"b","label":""}]}. '
          'Use 2-6 nodes, at most 8 edges. Keep labels under 50 characters and descriptions under 120. '
          'Kinds: start, process, decision, end. Decisions need distinct labelled branches. IDs must be unique. No code or markdown.'
        : 'Describe an illustration matching the request and explanation. Return JSON only: '
          '{"title":"...","caption":"...","prompt":"...","breakdown":["..."]}. '
          'Use a descriptive Stable Diffusion prompt, at most 120 words, no instructions to tools. '
          'Give 2-4 short breakdown points describing the intended components, not claiming to inspect a generated image. '
          'Do not invent document facts. No markdown.',
      params: const GenParams(maxTokens: 768, temperature: .2));
    final start = output.indexOf('{');
    final end = output.lastIndexOf('}');
    if (start < 0 || end < start) throw const FormatException('The local AI did not return a valid visual description. Regenerate it or simplify the request.');
    final decoded = jsonDecode(output.substring(start, end + 1));
    if (decoded is! Map<String, dynamic>) throw const FormatException('Invalid visual description. Regenerate it.');
    if (diagram) {
      final graph = DiagramData.fromJson(decoded);
      return ChatVisual(kind: intent.kind, status: VisualStatus.ready, request: request, explicit: intent.explicit,
        title: graph.title, caption: 'AI-generated diagram based on the explanation.', diagram: graph,
        breakdown: graph.nodes.map((node) => '${node.label}: ${node.description}').toList(growable: false));
    }
    final breakdown = decoded['breakdown'];
    if (breakdown is! List || breakdown.isEmpty || breakdown.length > 6) throw const FormatException('The local AI omitted the illustration breakdown. Regenerate it.');
    return ChatVisual(kind: intent.kind, status: VisualStatus.loading, request: request, explicit: intent.explicit,
      title: visualString(decoded, 'title', 100), caption: visualString(decoded, 'caption', 400),
      generationPrompt: visualString(decoded, 'prompt', 1000),
      breakdown: breakdown.map((item) => visualString({'detail': item}, 'detail', 300)).toList(growable: false));
  }
}

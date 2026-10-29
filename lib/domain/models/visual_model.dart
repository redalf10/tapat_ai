import 'dart:convert';

enum VisualKind { diagram, image }
enum VisualStatus { loading, ready, error }

class VisualIntent {
  const VisualIntent(this.kind, {this.explicit = true});
  final VisualKind kind;
  final bool explicit;

  static VisualIntent? detect(String question) {
    final text = question.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (RegExp(r'\b(?:text[ -]only|only text)\b|\b(?:no|without|avoid|do not|don\x27t)\s+(?:(?:generate|generating|create|creating|draw|drawing|show|include|including|add|use)\s+)?(?:(?:a|an|any|the)\s+)?(?:images?|pictures?|diagrams?|flowcharts?|visuals?|illustrations?)\b').hasMatch(text)) return null;
    if (RegExp(r'\bhow (?:to|do i|can i|should i)\b.*\b(?:generate|create|draw|render)\b').hasMatch(text)) return null;
    if (RegExp(r'\b(?:generate|create|write|make|give)\s+(?:(?:me|a|an|some|the)\s+)*(?:text|summary|explanation|notes|tutorial)\b').hasMatch(text) &&
        !RegExp(r'\b(?:with|include|including|and|plus)\s+(?:an?\s+)?(?:image|picture|illustration|diagram|flowchart)\b').hasMatch(text)) {
      return null;
    }
    const request = r'(?:create|generate|draw|render|make|show|include|add|need|want|design|produce|sketch)';
    const diagram = r'(?:flow\s?charts?|diagrams?|workflows?|system architecture|process visuali[sz]ation|pipelines?)';
    const image = r'(?:images?|pictures?|illustrations?|photos?|artwork|drawings?)';
    if (RegExp('\\b$request\\b[^.!?]{0,100}\\b$diagram\\b').hasMatch(text) ||
        RegExp(r'^(?:please )?diagram\b').hasMatch(text)) {
      return const VisualIntent(VisualKind.diagram);
    }
    if (RegExp('\\b$request\\b[^.!?]{0,100}\\b$image\\b').hasMatch(text) ||
        RegExp('\\bwith (?:an? )?$image\\b').hasMatch(text)) {
      return const VisualIntent(VisualKind.image);
    }
    if (RegExp(r'\bvisuali[sz]e\b|\b(?:draw|show)\s+(?:me\s+)?how\b').hasMatch(text)) return const VisualIntent(VisualKind.diagram);
    if (RegExp(r'\billustrate\b|\bdepict\b').hasMatch(text)) return const VisualIntent(VisualKind.image);
    if (RegExp(r'\b(?:how|explain|walk me through)\b').hasMatch(text) &&
        RegExp(r'\b(?:rag pipeline|authentication (?:works?|flow|process)|water cycle|nfc (?:communication|communicates)|workflow|system architecture)\b').hasMatch(text)) {
      return const VisualIntent(VisualKind.diagram, explicit: false);
    }
    return null;
  }

  static bool refersToDocuments(String question) => RegExp(
    r'\b(?:(?:my|our|these|this|the|saved|uploaded|indexed)\s+(?:\w+\s+){0,2}(?:documents?|docs?|notes?|files?|manuals?|handbooks?)|(?:from|in|using)\s+(?:the\s+)?(?:documents?|docs?|notes?|files?|manuals?))\b|\.(?:pdf|docx|txt|md)\b',
    caseSensitive: false,
  ).hasMatch(question);
}

String visualString(Map<String, dynamic> value, String key, int maxLength, {bool optional = false}) {
  final raw = value[key];
  if (raw == null && optional) return '';
  if (raw is! String || raw.length > maxLength || RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]').hasMatch(raw)) {
    throw FormatException('The local AI returned an invalid visual $key. Regenerate the visual.');
  }
  final text = raw.trim();
  if (!optional && text.isEmpty) throw FormatException('The local AI omitted the visual $key. Regenerate the visual.');
  return text;
}

class DiagramNode {
  const DiagramNode(this.id, this.label, this.description, {this.kind = 'process'});
  final String id, label, description, kind;
  Map<String, Object?> toJson() => {'id': id, 'label': label, 'description': description, 'kind': kind};
}

class DiagramEdge {
  const DiagramEdge(this.from, this.to, {this.label = ''});
  final String from, to, label;
  Map<String, Object?> toJson() => {'from': from, 'to': to, 'label': label};
}

class DiagramData {
  const DiagramData(this.title, this.nodes, this.edges);
  final String title;
  final List<DiagramNode> nodes;
  final List<DiagramEdge> edges;

  factory DiagramData.fromJson(Map<String, dynamic> value) {
    final title = visualString(value, 'title', 100);
    final rawNodes = value['nodes'];
    final rawEdges = value['edges'];
    if (rawNodes is! List || rawNodes.length < 2 || rawNodes.length > 8 ||
        rawEdges is! List || rawEdges.isEmpty || rawEdges.length > 12) {
      throw const FormatException('A diagram needs 2–8 components and 1–12 connections. Regenerate it with fewer steps.');
    }
    final nodes = <DiagramNode>[];
    final ids = <String>{};
    for (final raw in rawNodes) {
      if (raw is! Map<String, dynamic>) throw const FormatException('Invalid diagram component.');
      final id = visualString(raw, 'id', 32);
      final kind = visualString(raw, 'kind', 16);
      if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_-]*$').hasMatch(id) || !ids.add(id) ||
          !{'process', 'decision', 'start', 'end'}.contains(kind)) {
        throw const FormatException('The diagram contains duplicate IDs or an unsupported component type. Regenerate it.');
      }
      nodes.add(DiagramNode(id, visualString(raw, 'label', 64), visualString(raw, 'description', 200), kind: kind));
    }
    final edges = <DiagramEdge>[];
    final seen = <(String, String, String)>{};
    for (final raw in rawEdges) {
      if (raw is! Map<String, dynamic>) throw const FormatException('Invalid diagram connection.');
      final from = visualString(raw, 'from', 32);
      final to = visualString(raw, 'to', 32);
      final label = visualString(raw, 'label', 24, optional: true);
      if (!ids.contains(from) || !ids.contains(to) || from == to || !seen.add((from, to, label))) {
        throw const FormatException('The diagram has an invalid connection. Regenerate it.');
      }
      edges.add(DiagramEdge(from, to, label: label));
    }
    for (final node in nodes) {
      if (!edges.any((edge) => edge.from == node.id || edge.to == node.id)) {
        throw const FormatException('The diagram contains an unconnected component. Regenerate it.');
      }
      if (node.kind == 'decision') {
        final branches = edges.where((edge) => edge.from == node.id).toList();
        if (branches.length < 2 || branches.any((edge) => edge.label.isEmpty) ||
            branches.map((edge) => edge.label.toLowerCase()).toSet().length != branches.length) {
          throw const FormatException('Each decision needs at least two distinct, labelled branches. Regenerate the flowchart.');
        }
      }
    }
    return DiagramData(title, List.unmodifiable(nodes), List.unmodifiable(edges));
  }

  Map<String, Object?> toJson() => {'title': title, 'nodes': nodes.map((node) => node.toJson()).toList(), 'edges': edges.map((edge) => edge.toJson()).toList()};
  String get accessibleDescription => '${nodes.map((node) => '${node.label}: ${node.description}').join('. ')}. Connections: ${edges.map((edge) {
    final from = nodes.firstWhere((node) => node.id == edge.from).label;
    final to = nodes.firstWhere((node) => node.id == edge.to).label;
    return '$from to $to${edge.label.isEmpty ? '' : ' (${edge.label})'}';
  }).join('; ')}.';
}

class ChatVisual {
  const ChatVisual({required this.kind, required this.status, required this.request,
    this.explicit = true, this.title = '', this.caption = '', this.breakdown = const [],
    this.diagram, this.imageBase64 = '', this.generationPrompt = '', this.error});
  final VisualKind kind;
  final VisualStatus status;
  final String request, title, caption, imageBase64, generationPrompt;
  final bool explicit;
  final List<String> breakdown;
  final DiagramData? diagram;
  final String? error;
  bool get hasContent => diagram != null || imageBase64.isNotEmpty;

  ChatVisual copyWith({VisualStatus? status, String? title, String? caption, List<String>? breakdown,
    DiagramData? diagram, String? imageBase64, String? generationPrompt, String? error}) => ChatVisual(
    kind: kind, status: status ?? this.status, request: request, explicit: explicit,
    title: title ?? this.title, caption: caption ?? this.caption, breakdown: breakdown ?? this.breakdown,
    diagram: diagram ?? this.diagram, imageBase64: imageBase64 ?? this.imageBase64,
    generationPrompt: generationPrompt ?? this.generationPrompt, error: error,
  );

  Map<String, Object?> toJson() => {'kind': kind.name, 'status': status.name, 'request': request,
    'explicit': explicit, 'title': title, 'caption': caption, 'breakdown': breakdown,
    'diagram': diagram?.toJson(), 'imageBase64': imageBase64, 'generationPrompt': generationPrompt, 'error': error};
  String encode() => jsonEncode(toJson());

  static ChatVisual? restore(String encoded) {
    if (encoded.isEmpty) return null;
    try {
      final value = jsonDecode(encoded) as Map<String, dynamic>;
      final kind = VisualKind.values.firstWhere((kind) => kind.name == value['kind']);
      final status = VisualStatus.values.firstWhere((status) => status.name == value['status']);
      final rawBreakdown = value['breakdown'] as List? ?? const [];
      if (rawBreakdown.length > 12) throw const FormatException('Too many visual details.');
      final diagram = value['diagram'];
      return ChatVisual(kind: kind,
        status: status == VisualStatus.loading ? VisualStatus.error : status,
        request: visualString(value, 'request', 16000, optional: true),
        explicit: value['explicit'] as bool? ?? true,
        title: visualString(value, 'title', 100, optional: true),
        caption: visualString(value, 'caption', 400, optional: true),
        breakdown: rawBreakdown.map((item) => visualString({'detail': item}, 'detail', 300)).toList(growable: false),
        diagram: diagram == null ? null : DiagramData.fromJson(diagram as Map<String, dynamic>),
        imageBase64: visualString(value, 'imageBase64', 12 * 1024 * 1024, optional: true),
        generationPrompt: visualString(value, 'generationPrompt', 1200, optional: true),
        error: status == VisualStatus.loading ? 'Visual generation was interrupted. Regenerate it to try again.' : value['error'] as String?,
      );
    } catch (_) {
      return const ChatVisual(kind: VisualKind.diagram, status: VisualStatus.error, request: '',
        error: 'This saved visual could not be read. Send a new visual request; your text answer is still available.');
    }
  }
}

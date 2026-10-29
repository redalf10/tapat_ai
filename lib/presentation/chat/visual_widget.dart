import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../domain/models/visual_model.dart';

class ChatVisualCard extends StatefulWidget {
  const ChatVisualCard({super.key, required this.visual, this.onRegenerate, this.onCancel, this.onConfigure});
  final ChatVisual visual;
  final VoidCallback? onRegenerate, onCancel, onConfigure;
  @override
  State<ChatVisualCard> createState() => _ChatVisualCardState();
}

class _ChatVisualCardState extends State<ChatVisualCard> {
  Uint8List? _image;
  @override
  void initState() { super.initState(); _decode(); }
  @override
  void didUpdateWidget(ChatVisualCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visual.imageBase64 != widget.visual.imageBase64) _decode();
  }
  void _decode() {
    try {
      _image = widget.visual.imageBase64.isEmpty ? null : base64Decode(widget.visual.imageBase64);
    } on FormatException {
      _image = null;
    }
  }

  Widget _content({bool preview = false}) {
    final visual = widget.visual;
    if (visual.diagram != null) return DiagramView(visual.diagram!, scrollable: !preview);
    if (_image == null) return const Text('This image could not be read. Regenerate it to try again.');
    return Image.memory(_image!, fit: BoxFit.contain, gaplessPlayback: true,
      semanticLabel: visual.caption.isEmpty ? visual.title : visual.caption,
      errorBuilder: (_, _, _) => const Padding(padding: EdgeInsets.all(16), child: Text('This image could not be displayed. Regenerate it to try again.')));
  }

  void _preview() {
    showDialog<void>(context: context, builder: (dialogContext) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(width: 900, height: MediaQuery.sizeOf(context).height * .85, child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 4, 8), child: Row(children: [
          Expanded(child: Text(widget.visual.title.isEmpty ? 'Visual preview' : widget.visual.title,
            style: Theme.of(context).textTheme.titleMedium)),
          IconButton(tooltip: 'Close preview', onPressed: () => Navigator.pop(dialogContext), icon: const Icon(Icons.close)),
        ])),
        Expanded(child: ClipRect(child: InteractiveViewer(constrained: widget.visual.diagram == null,
          minScale: .5, maxScale: 4, boundaryMargin: const EdgeInsets.all(40),
          child: widget.visual.diagram == null ? Center(child: _content(preview: true)) : SizedBox(width: 700, child: _content(preview: true))))),
        const Padding(padding: EdgeInsets.all(12), child: Text('Pinch or scroll to zoom; drag to explore.', style: TextStyle(fontSize: 12))),
      ])),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final visual = widget.visual;
    final theme = Theme.of(context);
    final loading = visual.status == VisualStatus.loading;
    return Container(
      width: double.infinity, margin: const EdgeInsets.only(top: 14), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .4), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Visual', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        if (visual.title.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(visual.title)),
        if (loading) Semantics(liveRegion: true, child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(visual.kind == VisualKind.diagram ? 'Generating diagram...' : 'Generating image...'),
            const SizedBox(height: 8), const LinearProgressIndicator(),
          ]))),
        if (visual.hasContent) ClipRRect(borderRadius: BorderRadius.circular(8), child: _content()),
        if (visual.error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Semantics(liveRegion: true,
          child: Text(visual.error!, style: TextStyle(color: theme.colorScheme.error)))),
        if (visual.caption.isNotEmpty && visual.hasContent) Padding(padding: const EdgeInsets.only(top: 8), child: Text(visual.caption,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
        if (visual.breakdown.isNotEmpty && visual.hasContent) ...[
          const SizedBox(height: 12),
          Text('Breakdown', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          for (final point in visual.breakdown) Padding(padding: const EdgeInsets.only(top: 6), child: Text('• $point')),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 4, children: [
          if (visual.hasContent) TextButton.icon(onPressed: _preview, icon: const Icon(Icons.open_in_full, size: 16), label: const Text('View larger')),
          if (!loading) TextButton.icon(onPressed: widget.onRegenerate, icon: const Icon(Icons.refresh, size: 16), label: const Text('Regenerate visual')),
          if (loading) TextButton(onPressed: widget.onCancel, child: const Text('Cancel visual')),
          if (visual.status == VisualStatus.error && widget.onConfigure != null)
            TextButton(onPressed: widget.onConfigure, child: Text(visual.kind == VisualKind.image ? 'Image settings' : 'Local AI Models')),
        ]),
      ]),
    );
  }
}

class DiagramView extends StatelessWidget {
  const DiagramView(this.diagram, {super.key, this.scrollable = true});
  final DiagramData diagram;
  final bool scrollable;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 600.0;
    final layout = DiagramLayout(diagram, width, Theme.of(context).colorScheme, MediaQuery.textScalerOf(context), Directionality.of(context));
    final canvas = Semantics(label: '${diagram.title}. ${diagram.accessibleDescription}', image: true,
      child: SizedBox(width: width, height: layout.height, child: CustomPaint(painter: _DiagramPainter(layout))));
    return ColoredBox(color: Theme.of(context).colorScheme.surface,
      child: scrollable ? SizedBox(height: math.min(layout.height, 420), child: SingleChildScrollView(child: canvas)) : canvas);
  });
}

class DiagramLayout {
  DiagramLayout(this.diagram, this.width, this.colors, this.scaler, this.direction) {
    final levels = {for (final node in diagram.nodes) node.id: 0};
    final incoming = {for (final node in diagram.nodes) node.id: diagram.edges.where((edge) => edge.to == node.id).length};
    final queue = diagram.nodes.where((node) => incoming[node.id] == 0).map((node) => node.id).toList();
    final visited = <String>{};
    for (var i = 0; i < queue.length; i++) {
      final id = queue[i];
      visited.add(id);
      for (final edge in diagram.edges.where((edge) => edge.from == id)) {
        levels[edge.to] = math.max(levels[edge.to]!, levels[id]! + 1);
        incoming[edge.to] = incoming[edge.to]! - 1;
        if (incoming[edge.to] == 0) queue.add(edge.to);
      }
    }
    for (final node in diagram.nodes.where((node) => !visited.contains(node.id))) {
      if (!visited.add(node.id)) continue;
      levels[node.id] = visited.length == 1 ? 0 : math.max(levels[node.id]!,
        visited.where((id) => id != node.id).map((id) => levels[id]!).reduce(math.max) + 1);
      final cycle = [node.id];
      for (var i = 0; i < cycle.length; i++) {
        for (final edge in diagram.edges.where((edge) => edge.from == cycle[i])) {
          if (visited.add(edge.to)) { levels[edge.to] = levels[cycle[i]]! + 1; cycle.add(edge.to); }
        }
      }
    }
    final columns = width >= 540 && scaler.scale(14) <= 21 ? 2 : 1;
    final spacing = math.max(64.0, scaler.scale(30) * 2);
    var y = 36.0;
    final orderedLevels = levels.values.toSet().toList()..sort();
    for (final level in orderedLevels) {
      final nodes = diagram.nodes.where((node) => levels[node.id] == level).toList();
      for (var start = 0; start < nodes.length; start += columns) {
        final row = nodes.sublist(start, math.min(start + columns, nodes.length));
        final nodeWidth = math.min(320.0, (width - 80 - 28 * (row.length - 1)) / row.length);
        final heights = <double>[];
        for (final node in row) {
          final color = node.kind == 'decision' ? colors.onSecondaryContainer :
            {'start', 'end'}.contains(node.kind) ? colors.onPrimaryContainer : colors.onSurface;
          final text = TextPainter(text: TextSpan(text: node.label, style: TextStyle(fontSize: 14, height: 1.25, color: color, fontWeight: FontWeight.w600)),
            textDirection: direction, textAlign: TextAlign.center, textScaler: scaler)..layout(maxWidth: math.max(32, nodeWidth * (node.kind == 'decision' ? .58 : 1) - 24));
          labels[node.id] = text;
          heights.add(node.kind == 'decision' ? text.height * 1.75 + 40 : math.max(60, text.height + 28));
        }
        final rowHeight = heights.reduce(math.max);
        final totalWidth = row.length * nodeWidth + (row.length - 1) * 28;
        for (var i = 0; i < row.length; i++) {
          rects[row[i].id] = Rect.fromLTWH((width - totalWidth) / 2 + i * (nodeWidth + 28), y + (rowHeight - heights[i]) / 2, nodeWidth, heights[i]);
        }
        y += rowHeight + spacing;
      }
    }
    height = y - spacing + 36;
  }
  final DiagramData diagram;
  final double width;
  final ColorScheme colors;
  final TextScaler scaler;
  final TextDirection direction;
  final rects = <String, Rect>{};
  final labels = <String, TextPainter>{};
  late final double height;
}

class _DiagramPainter extends CustomPainter {
  _DiagramPainter(this.layout);
  final DiagramLayout layout;
  @override
  void paint(Canvas canvas, Size size) {
    final colors = layout.colors;
    final line = Paint()..color = colors.primary..strokeWidth = 1.8..style = PaintingStyle.stroke;
    for (var i = 0; i < layout.diagram.edges.length; i++) {
      final edge = layout.diagram.edges[i];
      final from = layout.rects[edge.from]!;
      final to = layout.rects[edge.to]!;
      final points = <Offset>[];
      var labelWidth = 100.0;
      Offset labelPosition;
      if (to.top > from.bottom && to.top - from.bottom < 180) {
        final middle = (from.bottom + to.top) / 2;
        points.addAll([from.bottomCenter, Offset(from.center.dx, middle), Offset(to.center.dx, middle), to.topCenter]);
        labelPosition = Offset((from.center.dx + to.center.dx) / 2, middle);
        if ((from.center.dx - to.center.dx).abs() < 1) labelPosition += const Offset(28, 0);
      } else if ((from.center.dy - to.center.dy).abs() < 1) {
        final y = math.max(12.0, math.min(from.top, to.top) - 24);
        points.addAll([from.topCenter, Offset(from.center.dx, y), Offset(to.center.dx, y), to.topCenter]);
        labelPosition = Offset((from.center.dx + to.center.dx) / 2, y);
      } else {
        final backward = to.center.dy < from.center.dy;
        final x = backward ? 14.0 + i % 3 * 6 : size.width - 14.0 - i % 3 * 6;
        final start = backward ? from.centerLeft : from.centerRight;
        final end = backward ? to.centerLeft : to.centerRight;
        points.addAll([start, Offset(x, start.dy), Offset(x, end.dy), end]);
        labelPosition = Offset(backward ? 20 : size.width - 20, (start.dy + end.dy) / 2);
        labelWidth = 32;
      }
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) { path.lineTo(point.dx, point.dy); }
      canvas.drawPath(path, line);
      final end = points.last;
      final previous = points.reversed.skip(1).firstWhere((point) => point != end);
      final angle = math.atan2(end.dy - previous.dy, end.dx - previous.dx);
      final arrow = Path()..moveTo(end.dx, end.dy)
        ..lineTo(end.dx - 8 * math.cos(angle - .45), end.dy - 8 * math.sin(angle - .45))
        ..lineTo(end.dx - 8 * math.cos(angle + .45), end.dy - 8 * math.sin(angle + .45))..close();
      canvas.drawPath(arrow, Paint()..color = colors.primary);
      if (edge.label.isNotEmpty) _label(canvas, edge.label, labelPosition, labelWidth);
    }
    for (final node in layout.diagram.nodes) {
      final rect = layout.rects[node.id]!;
      final fill = Paint()..color = node.kind == 'decision' ? colors.secondaryContainer :
        {'start', 'end'}.contains(node.kind) ? colors.primaryContainer : colors.surfaceContainerHigh;
      final border = Paint()..color = node.kind == 'decision' ? colors.secondary : colors.primary..style = PaintingStyle.stroke..strokeWidth = 1.5;
      if (node.kind == 'decision') {
        final diamond = Path()..moveTo(rect.center.dx, rect.top)..lineTo(rect.right, rect.center.dy)
          ..lineTo(rect.center.dx, rect.bottom)..lineTo(rect.left, rect.center.dy)..close();
        canvas.drawPath(diamond, fill);
        canvas.drawPath(diamond, border);
      } else {
        final shape = RRect.fromRectAndRadius(rect, Radius.circular({'start', 'end'}.contains(node.kind) ? rect.height / 2 : 12));
        canvas.drawRRect(shape, fill);
        canvas.drawRRect(shape, border);
      }
      final text = layout.labels[node.id]!;
      text.paint(canvas, rect.center - Offset(text.width / 2, text.height / 2));
    }
  }

  void _label(Canvas canvas, String label, Offset center, double width) {
    final text = TextPainter(text: TextSpan(text: label, style: TextStyle(fontSize: 11, color: layout.colors.onSurface)),
      textDirection: layout.direction, textAlign: TextAlign.center, textScaler: layout.scaler)..layout(maxWidth: width);
    final origin = center - Offset(text.width / 2, text.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(origin.dx - 3, origin.dy - 2, text.width + 6, text.height + 4), const Radius.circular(4)), Paint()..color = layout.colors.surface);
    text.paint(canvas, origin);
  }

  @override
  bool shouldRepaint(_DiagramPainter oldDelegate) => oldDelegate.layout != layout;
}

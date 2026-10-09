import 'package:tapat_ai/domain/models/source_ref_model.dart';
import 'visual_model.dart';

class Message {
  Message(this.text, this.isUser, [this.sources = const [], DateTime? sentAt, this.id = 0, this.visual])
    : sentAt = sentAt ?? DateTime.now();
  final String text;
  final bool isUser;
  final List<SourceRef> sources;
  final DateTime sentAt;
  final int id;
  final ChatVisual? visual;

  Message copyWith({int? id, ChatVisual? visual}) => Message(text, isUser, sources, sentAt, id ?? this.id, visual ?? this.visual);
}

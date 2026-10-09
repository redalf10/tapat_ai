import 'package:tapat_ai/domain/models/source_ref_model.dart';

class Message {
  Message(this.text, this.isUser, [this.sources = const [], DateTime? sentAt])
      : sentAt = sentAt ?? DateTime.now();
  final String text;
  final bool isUser;
  final List<SourceRef> sources;
  final DateTime sentAt;
}

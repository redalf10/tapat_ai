import 'package:tapat_ai/domain/models/source_ref_model.dart';

class Message {
  const Message(this.text, this.isUser, [this.sources = const []]);
  final String text;
  final bool isUser;
  final List<SourceRef> sources;
}
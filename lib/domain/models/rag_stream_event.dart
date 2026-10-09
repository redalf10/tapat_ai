import 'message_model.dart';

class RagStreamEvent {
  const RagStreamEvent.token(this.text) : message = null;
  const RagStreamEvent.complete(this.message) : text = '';
  final String text;
  final Message? message;
}

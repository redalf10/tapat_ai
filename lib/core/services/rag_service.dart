import 'package:tapat_ai/domain/models/doc_model.dart';
import 'package:tapat_ai/domain/models/ingest_progress.dart';
import 'package:tapat_ai/domain/models/message_model.dart';
import 'package:tapat_ai/domain/models/topic_model.dart';

/// Swap these implementations for llama.cpp / ONNX embeddings / ObjectBox etc.
abstract class RagService {
  Stream<IngestProgress> ingest(Topic topic, List<Doc> docs);
  Future<Message> ask(Topic topic, String question);
}
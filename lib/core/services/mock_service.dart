import 'dart:async';

import 'package:tapat_ai/core/services/document_service.dart';
import 'package:tapat_ai/core/services/nfc_servide.dart';
import 'package:tapat_ai/core/services/rag_service.dart';
import 'package:tapat_ai/domain/models/doc_model.dart';
import 'package:tapat_ai/domain/models/ingest_progress.dart';
import 'package:tapat_ai/domain/models/message_model.dart';
import 'package:tapat_ai/domain/models/rag_stream_event.dart';
import 'package:tapat_ai/domain/models/source_ref_model.dart';
import 'package:tapat_ai/domain/models/topic_model.dart';

class MockRagService implements RagService {
  @override
  Stream<RagStreamEvent> askStream(Topic topic, String question) async* {
    yield RagStreamEvent.complete(await ask(topic, question));
  }

  @override
  Stream<IngestProgress> ingest(Topic topic, List<Doc> docs) async* {
    final total = docs.fold<int>(0, (a, d) => a + d.chunks);
    yield const IngestProgress(0, 0.05);
    await Future.delayed(const Duration(milliseconds: 700));
    yield const IngestProgress(1, 0.2);
    await Future.delayed(const Duration(milliseconds: 700));
    for (var i = 1; i <= 10; i++) {
      yield IngestProgress(
          2, 0.2 + 0.6 * i / 10, '${(total * i / 10).round()} / $total chunks');
      await Future.delayed(const Duration(milliseconds: 250));
    }
    yield const IngestProgress(3, 0.9);
    await Future.delayed(const Duration(milliseconds: 600));
    yield const IngestProgress(4, 1);
  }
 
  @override
  Future<Message> ask(Topic topic, String q) async {
    await Future.delayed(const Duration(milliseconds: 1200));
    if (topic.docs.isEmpty) {
      return Message(
          'This knowledge base has no documents yet. Add one to get answers.',
          false);
    }
    final refs = [
      for (var i = 0; i < topic.docs.length && i < 3; i++)
        SourceRef(topic.docs[i].name, 5 + i * 7),
    ];
    return Message(
        'Based on your "${topic.name}" documents, here is a mock answer to "$q". '
        'Connect a local LLM and vector store in MockRagService to generate real, grounded responses.',
        false,
        refs);
  }
}
 
class MockNfcService implements NfcService {
  Completer<String?>? _c;
 
  @override
  Future<bool> isAvailable() async => true;
 
  @override
  Future<String?> scan() {
    final c = _c = Completer<String?>();
    Future.delayed(const Duration(seconds: 3), () {
      if (!c.isCompleted) c.complete('computer-001');
    });
    return c.future;
  }
 
  @override
  Future<bool> write(String payload) async {
    await Future.delayed(const Duration(seconds: 3));
    return true;
  }

  @override
  Future<bool> erase() async => true;
 
  @override
  void cancel() {
    final c = _c;
    if (c != null && !c.isCompleted) c.complete(null);
  }
}
 
class MockDocumentPicker implements DocumentPicker {
  int _n = 0;
  @override
  Future<List<Doc>> pick() async {
    _n++;
    await Future.delayed(const Duration(milliseconds: 300));
    return [Doc('new$_n', 'Document_$_n.pdf', DocType.pdf, 40 + _n * 9, 2.4)];
  }
}

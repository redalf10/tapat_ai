import 'dart:convert';
import '../../core/services/rag_service.dart';
import '../../domain/models/doc_model.dart';
import '../../domain/models/ingest_progress.dart';
import '../../domain/models/message_model.dart';
import '../../domain/models/rag_stream_event.dart';
import '../../domain/models/source_ref_model.dart';
import '../../domain/models/topic_model.dart';
import '../entities/entities.dart';
import '../file_ingestion.dart';
import '../repositories.dart';
import 'engines.dart';

class LocalRagService implements RagService {
  LocalRagService(this.repositories, this.embedding, this.llm)
      : _ingest = IngestDocumentUseCase(repositories, embedding);
  final Repositories repositories;
  final OnDeviceEmbeddingEngine embedding;
  final OnDeviceLlamaEngine llm;
  final IngestDocumentUseCase _ingest;

  @override
  Stream<IngestProgress> ingest(Topic topic, List<Doc> docs) async* {
    final entity = repositories.topics.byUuid(topic.id);
    if (entity == null) throw StateError('This knowledge base no longer exists.');
    yield* _ingest(entity, docs);
  }

  @override
  Future<Message> ask(Topic topic, String question) async {
    Message? finalMessage;
    await for (final event in askStream(topic, question)) {
      if (event.message != null) finalMessage = event.message;
    }
    return finalMessage ?? const Message("I couldn't find that in your documents.", false);
  }

  @override
  Stream<RagStreamEvent> askStream(Topic topic, String question) async* {
    final entity = repositories.topics.byUuid(topic.id);
    if (entity == null) throw StateError('This knowledge base no longer exists.');
    final indexedChunks = repositories.chunks.forTopic(entity.id);
    if (repositories.documents.forTopic(entity.id).isEmpty || indexedChunks.isEmpty) {
      yield const RagStreamEvent.complete(Message('This knowledge base has no documents yet. Add one to get answers.', false));
      return;
    }
    if (embedding.dimensions != 384) {
      throw StateError('Your active embedding model is incompatible with this vector index. Re-index the knowledge base from Local AI Models.');
    }
    if (indexedChunks.any((chunk) => chunk.embeddingModelId != embedding.modelId)) {
      throw StateError('The active embedding model changed. Re-index this knowledge base in Local AI Models before chatting.');
    }
    final queryVector = await embedding.embed(question);
    final found = repositories.chunks.search(entity.id, queryVector, 5);
    if (found.isEmpty) {
      yield const RagStreamEvent.complete(Message("I couldn't find that in your documents.", false));
      return;
    }
    final context = <String>[];
    final sources = <SourceRef>[];
    final boundedQuestion = _truncateUtf8(question.trim(), 700);
    // Reserve space for the chat template, system instruction, and answer in
    // the model's 2,048-token context. UTF-8 bytes are a conservative estimate
    // for prompt length and prevent five full chunks from overflowing it.
    var contextBudget = 1200 - utf8.encode(boundedQuestion).length - 100;
    for (final hit in found) {
      final docName = hit.chunk.document.target?.name ?? 'Document';
      final header = '$docName, page ${hit.chunk.pageNumber}: ';
      final headerBytes = utf8.encode(header).length;
      if (contextBudget <= headerBytes + 20) break;
      final excerpt = _truncateUtf8(hit.chunk.text, contextBudget - headerBytes).trim();
      if (excerpt.isEmpty) continue;
      context.add('$header$excerpt');
      contextBudget -= headerBytes + utf8.encode(excerpt).length;
      sources.add(SourceRef(docName, hit.chunk.pageNumber));
    }
    if (context.isEmpty) {
      yield const RagStreamEvent.complete(Message("I couldn't find that in your documents.", false));
      return;
    }
    final prompt = PromptBuilder.buildUserMessage(question: boundedQuestion, context: context);
    final output = StringBuffer();
    await for (final token in llm.generate(
      prompt,
      systemPrompt: PromptBuilder.systemPrompt,
      params: const GenParams(maxTokens: 384),
    )) {
      output.write(token);
      yield RagStreamEvent.token(token);
    }
    final answer = output.toString().trim();
    if (answer.isEmpty) throw StateError('The local model returned an empty answer. Try again.');
    // Deduplicate citations when multiple retrieved chunks come from the same page.
    final unique = <String, SourceRef>{for (final ref in sources) '${ref.docName}:${ref.page}': ref};
    yield RagStreamEvent.complete(Message(answer, false, unique.values.toList(growable: false)));
  }
}

String _truncateUtf8(String value, int maxBytes) {
  if (maxBytes <= 0) return '';
  final output = StringBuffer();
  var bytes = 0;
  for (final rune in value.runes) {
    final character = String.fromCharCode(rune);
    final length = utf8.encode(character).length;
    if (bytes + length > maxBytes) break;
    output.write(character);
    bytes += length;
  }
  return output.toString();
}

TopicEntity createTopicEntity({required String uuid, required String name, required String description,
  required String category, required int iconIndex}) => TopicEntity()
  ..uuid = uuid
  ..name = name
  ..description = description
  ..category = category
  ..iconIndex = iconIndex
  ..createdAt = DateTime.now()
  ..nfcId = uuid;

ChatMessageEntity toChatEntity(TopicEntity topic, Message message) => ChatMessageEntity()
  ..topic.target = topic
  ..text = message.text
  ..isUser = message.isUser
  ..sourcesJson = jsonEncode(message.sources.map((s) => {'docName': s.docName, 'page': s.page}).toList())
  ..createdAt = DateTime.now();

Message fromChatEntity(ChatMessageEntity entity) {
  final raw = jsonDecode(entity.sourcesJson) as List<dynamic>;
  return Message(entity.text, entity.isUser, raw.map((v) => SourceRef(
    v['docName'] as String, v['page'] as int)).toList(growable: false));
}

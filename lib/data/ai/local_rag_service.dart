import 'dart:convert';
import 'dart:math' as math;

import '../../core/services/rag_service.dart';
import '../../domain/models/doc_model.dart';
import '../../domain/models/ingest_progress.dart';
import '../../domain/models/message_model.dart';
import '../../domain/models/rag_stream_event.dart';
import '../../domain/models/source_ref_model.dart';
import '../../domain/models/topic_model.dart';
import '../../domain/models/visual_model.dart';
import 'local_text_service.dart';
import '../entities/entities.dart';
import '../file_ingestion.dart';
import '../repositories.dart';
import 'engines.dart';

class LocalRagService implements RagService {
  LocalRagService(this.repositories, this.embedding, this.llm)
    : _ingest = IngestDocumentUseCase(repositories, embedding);
  final Repositories repositories;
  final EmbeddingEngine embedding;
  final LlmEngine llm;
  final IngestDocumentUseCase _ingest;

  @override
  Stream<IngestProgress> ingest(Topic topic, List<Doc> docs) async* {
    final entity = repositories.topics.byUuid(topic.id);
    if (entity == null) {
      throw StateError('This knowledge base no longer exists.');
    }
    yield* _ingest(entity, docs);
  }

  @override
  Future<Message> ask(Topic topic, String question) async {
    Message? finalMessage;
    await for (final event in askStream(topic, question)) {
      if (event.message != null) finalMessage = event.message;
    }
    return finalMessage ??
        Message("I couldn't find that in your documents.", false);
  }

  @override
  Stream<RagStreamEvent> askStream(Topic topic, String question) async* {
    final boundedQuestion = LocalTextService.truncateUtf8(
      question.replaceAll(RegExp(r'\s+'), ' ').trim(),
      700,
    );
    if (boundedQuestion.isEmpty) {
      throw StateError('Enter a question before asking.');
    }
    final entity = repositories.topics.byUuid(topic.id);
    if (entity == null) {
      throw StateError('This knowledge base no longer exists.');
    }
    final documents = repositories.documents.forTopic(entity.id);
    final index = repositories.chunks.indexForTopic(entity.id);
    if (documents.isEmpty || index.chunks.isEmpty) {
      yield* _withoutContext(boundedQuestion, documents.isEmpty
          ? 'This knowledge base has no documents yet. Add one to get answers.'
          : 'Your documents are saved but not indexed yet. Index a document to answer from it.', originalQuestion: question);
      return;
    }
    if (embedding.dimensions != 384) {
      throw StateError(
        'Your active embedding model is incompatible with this vector index. Re-index the knowledge base from Local AI Models.',
      );
    }
    final embeddingId = embedding.modelId;
    if (embeddingId == null ||
        index.modelIds.any((modelId) => modelId != embeddingId)) {
      throw StateError(
        'The embedding model or indexing format changed. Re-index this knowledge base in Local AI Models before chatting.',
      );
    }
    final queryVector = await embedding.embedQuery(boundedQuestion);
    if (embedding.modelId != embeddingId) {
      throw StateError(
        'The embedding model changed during retrieval. Try again.',
      );
    }
    final found = repositories.chunks.searchHybrid(
      entity.id,
      boundedQuestion,
      queryVector,
      8,
    );
    if (found.isEmpty) {
      yield* _withoutContext(boundedQuestion, PromptBuilder.noAnswer, originalQuestion: question);
      return;
    }
    // Reserve space for the chat template, system instruction, and answer in
    // the model's 2,048-token context. UTF-8 bytes are a conservative estimate
    // for prompt length and prevent five full chunks from overflowing it.
    final contextBudget = 1200 - utf8.encode(boundedQuestion).length - 100;
    final selected = RagContext.build(
      boundedQuestion,
      found,
      maxBytes: contextBudget,
      documentNames: {for (final doc in documents) doc.id: doc.name},
    );
    final context = selected.context;
    final sources = selected.sources;
    if (context.isEmpty) {
      yield* _withoutContext(boundedQuestion, PromptBuilder.noAnswer, originalQuestion: question);
      return;
    }
    final prompt = PromptBuilder.buildUserMessage(
      question: boundedQuestion,
      context: context,
    );
    final output = StringBuffer();
    await for (final token in llm.generate(
      prompt,
      systemPrompt: PromptBuilder.systemPrompt,
      params: const GenParams(maxTokens: 384, temperature: .1),
    )) {
      output.write(token);
      yield RagStreamEvent.token(token);
    }
    final answer = output.toString().trim();
    if (answer.isEmpty) {
      throw StateError('The local model returned an empty answer. Try again.');
    }
    // Deduplicate citations when multiple retrieved chunks come from the same page.
    final unique = <(String, int), SourceRef>{
      for (final ref in sources) (ref.docName, ref.page): ref,
    };
    yield RagStreamEvent.complete(
      Message(
        answer,
        false,
        answer == PromptBuilder.noAnswer
            ? const []
            : unique.values.toList(growable: false),
      ),
    );
  }

  Stream<RagStreamEvent> _withoutContext(String question, String noContextMessage, {String? originalQuestion}) async* {
    final request = originalQuestion ?? question;
    final intent = VisualIntent.detect(request);
    if (intent == null || !intent.explicit || VisualIntent.refersToDocuments(request)) {
      yield RagStreamEvent.complete(Message(noContextMessage, false));
      return;
    }
    final explanation = await LocalTextService(llm).generate(question,
      systemPrompt: 'Explain the visual requested by the user using general knowledge. '
          'Give a concise, useful textual explanation. Do not claim that an image has already been generated. '
          'Do not cite or claim to use saved documents. State uncertainty instead of guessing unknown facts.',
      params: const GenParams(maxTokens: 384, temperature: .3));
    yield RagStreamEvent.complete(Message('General local-AI explanation (not based on indexed documents).\n\n$explanation', false));
  }
}

class RagContext {
  const RagContext(this.context, this.sources);
  final List<String> context;
  final List<SourceRef> sources;

  static RagContext build(
    String question,
    List<ScoredChunk> hits, {
    int maxBytes = 1100,
    int maxSources = 3,
    Map<int, String> documentNames = const {},
  }) {
    final groups = <(String, int), List<ChunkEntity>>{};
    final seen = <String>{};
    for (final hit in hits) {
      final chunk = hit.chunk;
      if (!seen.add(RetrievalText.normalize(chunk.text))) continue;
      final name =
          documentNames[chunk.document.targetId] ??
          chunk.document.target?.name ??
          'Document';
      final key = (name, chunk.pageNumber);
      if (!groups.containsKey(key) && groups.length >= maxSources) continue;
      (groups[key] ??= []).add(chunk);
    }
    final context = <String>[];
    final sources = <SourceRef>[];
    var remaining = maxBytes;
    var slots = groups.length;
    for (final group in groups.entries) {
      final allocation = remaining ~/ slots--;
      final name = LocalTextService.truncateUtf8(group.key.$1, 100);
      final header = '$name, page ${group.key.$2}: ';
      final overhead = utf8.encode(header).length + 6;
      if (allocation <= overhead) continue;
      group.value.sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));
      final text = group.value.map((chunk) => chunk.text).join('\n');
      final excerpt = selectContextExcerpt(
        text,
        question,
        allocation - overhead,
      );
      if (excerpt.isEmpty) continue;
      context.add('$header$excerpt');
      sources.add(SourceRef(group.key.$1, group.key.$2));
      remaining -= overhead + utf8.encode(excerpt).length;
    }
    return RagContext(context, sources);
  }
}

String selectContextExcerpt(String value, String question, int maxBytes) {
  if (maxBytes <= 0) return '';
  final text = value.trim();
  if (utf8.encode(text).length <= maxBytes) return text;
  final queryTerms = RetrievalText.terms(question).toSet();
  if (queryTerms.isEmpty) return LocalTextService.truncateUtf8(text, maxBytes).trim();
  final words = RegExp(r'\S+\s*').allMatches(text).toList(growable: false);
  final lengths = [
    for (final word in words) utf8.encode(word.group(0)!).length,
  ];
  final matches = [
    for (final word in words)
      RetrievalText.terms(word.group(0)!).toSet().intersection(queryTerms),
  ];
  final frequencies = <String, int>{};
  var end = 0;
  var bytes = 0;
  var matchedPositions = 0;
  var matchedCount = 0;
  var bestStart = 0;
  var bestEnd = 0;
  var bestScore = 0.0;
  for (var start = 0; start < words.length; start++) {
    if (end < start) end = start;
    while (end < words.length && bytes + lengths[end] <= maxBytes) {
      bytes += lengths[end];
      for (final term in matches[end]) {
        frequencies[term] = (frequencies[term] ?? 0) + 1;
      }
      matchedPositions += end * matches[end].length;
      matchedCount += matches[end].length;
      end++;
    }
    if (matchedCount > 0) {
      final center = matchedPositions / matchedCount;
      final repeated = frequencies.values.fold<int>(
        0,
        (sum, count) => sum + math.min(3, count),
      );
      final score =
          frequencies.length * 100 +
          repeated -
          (center - (start + end - 1) / 2).abs() * .001;
      if (score > bestScore) {
        bestScore = score;
        bestStart = start;
        bestEnd = end;
      }
    }
    if (end > start) {
      bytes -= lengths[start];
      for (final term in matches[start]) {
        final count = frequencies[term]! - 1;
        if (count == 0) {
          frequencies.remove(term);
        } else {
          frequencies[term] = count;
        }
      }
      matchedPositions -= start * matches[start].length;
      matchedCount -= matches[start].length;
    } else {
      end = start + 1;
    }
  }
  return bestEnd > bestStart
      ? text.substring(words[bestStart].start, words[bestEnd - 1].end).trim()
      : LocalTextService.truncateUtf8(text, maxBytes).trim();
}

TopicEntity createTopicEntity({
  required String uuid,
  required String name,
  required String description,
  required String category,
  required int iconIndex,
}) => TopicEntity()
  ..uuid = uuid
  ..name = name
  ..description = description
  ..category = category
  ..iconIndex = iconIndex
  ..createdAt = DateTime.now()
  ..nfcId = uuid;

ChatMessageEntity toChatEntity(TopicEntity topic, Message message) =>
    ChatMessageEntity()
      ..id = message.id
      ..topic.target = topic
      ..text = message.text
      ..isUser = message.isUser
      ..sourcesJson = jsonEncode(
        message.sources
            .map((s) => {'docName': s.docName, 'page': s.page})
            .toList(),
      )
      ..createdAt = message.sentAt
      ..visualJson = message.visual?.encode() ?? '';

Message fromChatEntity(ChatMessageEntity entity) {
  final raw = jsonDecode(entity.sourcesJson) as List<dynamic>;
  return Message(
    entity.text,
    entity.isUser,
    raw
        .map((v) => SourceRef(v['docName'] as String, v['page'] as int))
        .toList(growable: false),
    entity.createdAt,
    entity.id,
    ChatVisual.restore(entity.visualJson),
  );
}

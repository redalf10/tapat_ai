import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'entities/entities.dart';
import 'objectbox_store.dart';
import '../objectbox.g.dart';

class Repositories {
  Repositories(this.store)
    : topics = TopicRepository(store),
      documents = DocumentRepository(store),
      chunks = ChunkRepository(store),
      chats = ChatRepository(store),
      models = ModelRepository(store),
      settings = SettingsRepository(store);
  final ObjectBoxStore store;
  final TopicRepository topics;
  final DocumentRepository documents;
  final ChunkRepository chunks;
  final ChatRepository chats;
  final ModelRepository models;
  final SettingsRepository settings;

  T write<T>(T Function() action) => store.store.runInTransaction(TxMode.write, action);
}

class TopicRepository {
  TopicRepository(ObjectBoxStore store) : _box = store.store.box<TopicEntity>();
  final Box<TopicEntity> _box;
  List<TopicEntity> getAll() =>
      _box.getAll()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  TopicEntity? byUuid(String uuid) =>
      _first(_box.query(TopicEntity_.uuid.equals(uuid)).build());
  TopicEntity? byNfcId(String id) =>
      _first(_box.query(TopicEntity_.nfcId.equals(id)).build());
  TopicEntity put(TopicEntity topic) {
    _box.put(topic);
    return topic;
  }

  Stream<List<TopicEntity>> watch() =>
      _box.query().watch(triggerImmediately: true).map((_) => getAll());
  void deleteCascade(String uuid, Repositories repos) {
    final topic = byUuid(uuid);
    if (topic == null) return;
    repos.documents.deleteForTopic(topic.id);
    repos.chunks.deleteForTopic(topic.id);
    repos.chats.deleteForTopic(topic.id);
    _box.remove(topic.id);
  }

  TopicEntity? _first(Query<TopicEntity> query) {
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }
}

class DocumentRepository {
  DocumentRepository(ObjectBoxStore store)
    : _box = store.store.box<DocumentEntity>();
  final Box<DocumentEntity> _box;
  List<DocumentEntity> getAll() => _box.getAll();
  List<DocumentEntity> forTopic(int topicId) =>
      _find(_box.query(DocumentEntity_.topic.equals(topicId)).build());
  DocumentEntity? byUuid(String uuid) =>
      _first(_box.query(DocumentEntity_.uuid.equals(uuid)).build());
  DocumentEntity put(DocumentEntity doc) {
    _box.put(doc);
    return doc;
  }

  void deleteForTopic(int topicId) {
    for (final d in forTopic(topicId)) {
      final file = File(d.path);
      if (file.existsSync()) file.deleteSync();
      _box.remove(d.id);
    }
  }

  void delete(String uuid, ChunkRepository chunks) {
    final d = byUuid(uuid);
    if (d == null) return;
    chunks.deleteForDocument(d.id);
    final file = File(d.path);
    if (file.existsSync()) file.deleteSync();
    _box.remove(d.id);
  }

  List<DocumentEntity> _find(Query<DocumentEntity> query) {
    try {
      return query.find();
    } finally {
      query.close();
    }
  }

  DocumentEntity? _first(Query<DocumentEntity> query) {
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }
}

class ScoredChunk {
  const ScoredChunk(this.chunk, this.score);
  final ChunkEntity chunk;
  final double score;
}

class RetrievalText {
  static final _words = RegExp(
    r'[\p{L}\p{N}]+(?:[-_./][\p{L}\p{N}]+)*',
    unicode: true,
  );
  static const _stopWords = {
    'a',
    'an',
    'and',
    'are',
    'as',
    'at',
    'be',
    'been',
    'but',
    'by',
    'can',
    'could',
    'do',
    'does',
    'for',
    'from',
    'had',
    'has',
    'have',
    'how',
    'i',
    'if',
    'in',
    'is',
    'it',
    'its',
    'me',
    'my',
    'of',
    'on',
    'or',
    'our',
    'should',
    'that',
    'the',
    'their',
    'these',
    'this',
    'to',
    'was',
    'we',
    'were',
    'what',
    'when',
    'where',
    'which',
    'who',
    'why',
    'will',
    'with',
    'would',
    'you',
    'your',
  };

  static List<String> terms(String text) => [
    for (final match in _words.allMatches(text.toLowerCase()))
      if (!_stopWords.contains(match.group(0))) match.group(0)!,
  ];

  static String normalize(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
}

class HybridChunkIndex {
  HybridChunkIndex(List<ChunkEntity> rows) : chunks = List.unmodifiable(rows) {
    var totalLength = 0;
    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      _byId[chunk.id] = i;
      modelIds.add(chunk.embeddingModelId);
      final terms = RetrievalText.terms(chunk.text);
      _lengths.add(terms.length);
      totalLength += terms.length;
      final frequencies = <String, int>{};
      for (final term in terms) {
        frequencies[term] = (frequencies[term] ?? 0) + 1;
      }
      _terms.add(frequencies.keys.toSet());
      for (final entry in frequencies.entries) {
        (_postings[entry.key] ??= {})[i] = entry.value;
      }
    }
    _averageLength = chunks.isEmpty
        ? 1
        : math.max(1, totalLength / chunks.length);
  }

  final List<ChunkEntity> chunks;
  final modelIds = <String>{};
  final _byId = <int, int>{};
  final _postings = <String, Map<int, int>>{};
  final _lengths = <int>[];
  final _terms = <Set<String>>[];
  late final double _averageLength;

  Map<int, double> _lexicalScores(Set<String> queryTerms) {
    final scores = <int, double>{};
    for (final term in queryTerms) {
      final postings = _postings[term];
      if (postings == null) continue;
      final idf = math.log(
        1 + (chunks.length - postings.length + .5) / (postings.length + .5),
      );
      for (final entry in postings.entries) {
        final frequency = entry.value;
        final denominator =
            frequency +
            1.2 * (.25 + .75 * _lengths[entry.key] / _averageLength);
        scores[entry.key] =
            (scores[entry.key] ?? 0) + idf * frequency * 2.2 / denominator;
      }
    }
    return scores;
  }

  List<ScoredChunk> semanticSearch(List<double> queryVector, int limit) {
    final ranked = [
      for (final chunk in chunks)
        ScoredChunk(chunk, 1 - _cosineSimilarity(queryVector, chunk.vector)),
    ];
    ranked.sort((a, b) => a.score.compareTo(b.score));
    return ranked.take(limit).toList(growable: false);
  }

  List<ScoredChunk> rank(
    String question,
    List<double> queryVector,
    List<ScoredChunk> semantic, {
    int limit = 5,
    double minimumSimilarity = .25,
  }) {
    if (limit <= 0 || question.trim().isEmpty || chunks.isEmpty) {
      return const [];
    }
    final queryTerms = RetrievalText.terms(question).toSet();
    final lexical = _lexicalScores(queryTerms);
    final lexicalRank = lexical.keys.toList()
      ..sort((a, b) => lexical[b]!.compareTo(lexical[a]!));
    final fused = <int, double>{};
    for (var i = 0; i < semantic.length; i++) {
      final index = _byId[semantic[i].chunk.id];
      if (index != null) fused[index] = (fused[index] ?? 0) + 1 / (60 + i + 1);
    }
    for (
      var i = 0;
      i < math.min(lexicalRank.length, math.max(24, limit * 4));
      i++
    ) {
      final index = lexicalRank[i];
      fused[index] = (fused[index] ?? 0) + 1 / (60 + i + 1);
    }
    final similarities = <int, double>{};
    for (final index in fused.keys.toList()) {
      final similarity = _cosineSimilarity(queryVector, chunks[index].vector);
      if (similarity < minimumSimilarity && !lexical.containsKey(index)) {
        fused.remove(index);
        continue;
      }
      similarities[index] = similarity;
      final coverage = queryTerms.isEmpty
          ? 0
          : _terms[index].intersection(queryTerms).length / queryTerms.length;
      fused[index] = fused[index]! + .005 * coverage;
    }
    if (fused.isEmpty) return const [];
    final maximum = fused.values.reduce(math.max);
    final selected = <int>[];
    final seen = <String>{};
    while (selected.length < limit && fused.isNotEmpty) {
      int? best;
      var bestScore = double.negativeInfinity;
      for (final entry in fused.entries) {
        if (seen.contains(RetrievalText.normalize(chunks[entry.key].text))) {
          continue;
        }
        var overlap = 0.0;
        for (final previous in selected) {
          final union = _terms[entry.key].union(_terms[previous]).length;
          if (union > 0) {
            overlap = math.max(
              overlap,
              _terms[entry.key].intersection(_terms[previous]).length / union,
            );
          }
        }
        final score = .85 * entry.value / maximum - .15 * overlap;
        if (score > bestScore) {
          best = entry.key;
          bestScore = score;
        }
      }
      if (best == null) break;
      selected.add(best);
      seen.add(RetrievalText.normalize(chunks[best].text));
      fused.remove(best);
    }
    return [
      for (final index in selected)
        ScoredChunk(chunks[index], 1 - similarities[index]!),
    ];
  }
}

double _cosineSimilarity(List<double> query, List<double>? vector) {
  if (vector == null || vector.length != query.length) return 0;
  var dot = 0.0;
  var queryNorm = 0.0;
  var vectorNorm = 0.0;
  for (var i = 0; i < query.length; i++) {
    dot += query[i] * vector[i];
    queryNorm += query[i] * query[i];
    vectorNorm += vector[i] * vector[i];
  }
  final norm = math.sqrt(queryNorm * vectorNorm);
  return norm > 0 && norm.isFinite ? (dot / norm).clamp(-1, 1) : 0;
}

class ChunkRepository {
  ChunkRepository(ObjectBoxStore store) : _box = store.store.box<ChunkEntity>();
  final Box<ChunkEntity> _box;
  int? _indexedTopic;
  HybridChunkIndex? _index;
  List<ChunkEntity> forTopic(int topicId) =>
      _find(_box.query(ChunkEntity_.topic.equals(topicId)).build());
  List<ChunkEntity> forDocument(int documentId) =>
      _find(_box.query(ChunkEntity_.document.equals(documentId)).build());
  HybridChunkIndex indexForTopic(int topicId) {
    if (_index == null || _indexedTopic != topicId) {
      _index = HybridChunkIndex(forTopic(topicId));
      _indexedTopic = topicId;
    }
    return _index!;
  }

  void clearCache() {
    _index = null;
    _indexedTopic = null;
  }

  void putMany(List<ChunkEntity> chunks) {
    _box.putMany(chunks);
    clearCache();
  }

  void deleteForTopic(int topicId) {
    _box.removeMany(forTopic(topicId).map((e) => e.id).toList());
    clearCache();
  }

  void deleteForDocument(int documentId) {
    final q = _box.query(ChunkEntity_.document.equals(documentId)).build();
    try {
      _box.removeMany(q.find().map((e) => e.id).toList());
      clearCache();
    } finally {
      q.close();
    }
  }

  List<ScoredChunk> search(int topicId, List<double> queryVector, int k) {
    if (queryVector.length != 384 ||
        queryVector.any((value) => !value.isFinite)) {
      throw StateError(
        'Embedding dimensions changed. Re-index this knowledge base before searching.',
      );
    }
    if (k <= 0) return const [];
    final query =
        _box
            .query(
              ChunkEntity_.vector.nearestNeighborsF32(
                    queryVector,
                    math.max(32, k * 4),
                  ) &
                  ChunkEntity_.topic.equals(topicId),
            )
            .build()
          ..limit = k;
    try {
      return query
          .findWithScores()
          .map((result) => ScoredChunk(result.object, result.score))
          .toList(growable: false);
    } finally {
      query.close();
    }
  }

  List<ScoredChunk> searchHybrid(
    int topicId,
    String question,
    List<double> queryVector,
    int k,
  ) {
    if (k <= 0 || question.trim().isEmpty) return const [];
    final index = indexForTopic(topicId);
    final candidates = math.max(24, k * 4);
    var semantic = search(topicId, queryVector, candidates);
    if (semantic.length < math.min(candidates, index.chunks.length)) {
      semantic = index.semanticSearch(queryVector, candidates);
    }
    return index.rank(question, queryVector, semantic, limit: k);
  }

  List<ChunkEntity> _find(Query<ChunkEntity> query) {
    try {
      return query.find();
    } finally {
      query.close();
    }
  }
}

class ChatRepository {
  ChatRepository(ObjectBoxStore store)
    : _box = store.store.box<ChatMessageEntity>();
  final Box<ChatMessageEntity> _box;
  List<ChatMessageEntity> forTopic(int topicId) =>
      _find(_box.query(ChatMessageEntity_.topic.equals(topicId)).build())
        ..sort((a, b) => a.id.compareTo(b.id));
  ChatMessageEntity? byId(int id) => _box.get(id);
  void add(ChatMessageEntity message) => _box.put(message);
  void remove(int id) => _box.remove(id);
  Stream<List<ChatMessageEntity>> watch(int topicId) => _box
      .query(ChatMessageEntity_.topic.equals(topicId))
      .watch(triggerImmediately: true)
      .map((_) => forTopic(topicId));
  void clear(int topicId) =>
      _box.removeMany(forTopic(topicId).map((m) => m.id).toList());
  void deleteForTopic(int topicId) => clear(topicId);
  List<ChatMessageEntity> _find(Query<ChatMessageEntity> query) {
    try {
      return query.find();
    } finally {
      query.close();
    }
  }
}

class ModelRepository {
  ModelRepository(ObjectBoxStore store)
    : _box = store.store.box<ModelEntity>(),
      _store = store.store;
  final Box<ModelEntity> _box;
  final Store _store;
  List<ModelEntity> getAll() => _box.getAll();
  ModelEntity? active(String kind) {
    final query = _box
        .query(
          ModelEntity_.kind.equals(kind) & ModelEntity_.isActive.equals(true),
        )
        .build();
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  ModelEntity put(ModelEntity model) {
    _box.put(model);
    return model;
  }

  void setActive(int id, String kind) {
    _store.runInTransaction(TxMode.write, () {
      final query = _box.query(ModelEntity_.kind.equals(kind)).build();
      try {
        for (final model in query.find()) {
          model.isActive = model.id == id;
          _box.put(model);
        }
      } finally {
        query.close();
      }
    });
  }

  void delete(int id) => _box.remove(id);
}

class SettingsRepository {
  SettingsRepository(ObjectBoxStore store)
    : _box = store.store.box<SettingEntity>();
  final Box<SettingEntity> _box;
  String? get(String key) {
    final query = _box.query(SettingEntity_.key.equals(key)).build();
    try {
      return query.findFirst()?.value;
    } finally {
      query.close();
    }
  }

  void set(String key, String value) {
    final query = _box.query(SettingEntity_.key.equals(key)).build();
    final existing = _first(query);
    final row = existing ?? (SettingEntity()..key = key);
    row.value = value;
    _box.put(row);
  }

  SettingEntity? _first(Query<SettingEntity> query) {
    try {
      return query.findFirst();
    } finally {
      query.close();
    }
  }

  void clear() => _box.removeAll();
}

class LocalFiles {
  static const _uuid = Uuid();
  static Future<Directory> documentsDirectory() async => Directory(
    p.join((await getApplicationDocumentsDirectory()).path, 'documents'),
  )..createSync(recursive: true);
  static Future<Directory> modelsDirectory() async => Directory(
    p.join((await getApplicationDocumentsDirectory()).path, 'models'),
  )..createSync(recursive: true);
  static String newId() => _uuid.v4();
  static String encodeSources(List<Map<String, Object?>> sources) =>
      jsonEncode(sources);
}

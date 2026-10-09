import 'dart:convert';
import 'dart:io';

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
}

class TopicRepository {
  TopicRepository(ObjectBoxStore store) : _box = store.store.box<TopicEntity>();
  final Box<TopicEntity> _box;
  List<TopicEntity> getAll() => _box.getAll()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  TopicEntity? byUuid(String uuid) => _first(_box.query(TopicEntity_.uuid.equals(uuid)).build());
  TopicEntity? byNfcId(String id) => _first(_box.query(TopicEntity_.nfcId.equals(id)).build());
  TopicEntity put(TopicEntity topic) { _box.put(topic); return topic; }
  Stream<List<TopicEntity>> watch() => _box.query().watch(triggerImmediately: true).map((_) => getAll());
  void deleteCascade(String uuid, Repositories repos) {
    final topic = byUuid(uuid);
    if (topic == null) return;
    repos.documents.deleteForTopic(topic.id);
    repos.chunks.deleteForTopic(topic.id);
    repos.chats.deleteForTopic(topic.id);
    _box.remove(topic.id);
  }

  TopicEntity? _first(Query<TopicEntity> query) { try { return query.findFirst(); } finally { query.close(); } }
}

class DocumentRepository {
  DocumentRepository(ObjectBoxStore store) : _box = store.store.box<DocumentEntity>();
  final Box<DocumentEntity> _box;
  List<DocumentEntity> getAll() => _box.getAll();
  List<DocumentEntity> forTopic(int topicId) => _find(_box.query(DocumentEntity_.topic.equals(topicId)).build());
  DocumentEntity? byUuid(String uuid) => _first(_box.query(DocumentEntity_.uuid.equals(uuid)).build());
  DocumentEntity put(DocumentEntity doc) { _box.put(doc); return doc; }
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
  List<DocumentEntity> _find(Query<DocumentEntity> query) { try { return query.find(); } finally { query.close(); } }
  DocumentEntity? _first(Query<DocumentEntity> query) { try { return query.findFirst(); } finally { query.close(); } }
}

class ScoredChunk {
  const ScoredChunk(this.chunk, this.score);
  final ChunkEntity chunk;
  final double score;
}

class ChunkRepository {
  ChunkRepository(ObjectBoxStore store) : _box = store.store.box<ChunkEntity>();
  final Box<ChunkEntity> _box;
  List<ChunkEntity> forTopic(int topicId) => _find(_box.query(ChunkEntity_.topic.equals(topicId)).build());
  List<ChunkEntity> forDocument(int documentId) => _find(_box.query(ChunkEntity_.document.equals(documentId)).build());
  void putMany(List<ChunkEntity> chunks) { _box.putMany(chunks); }
  void deleteForTopic(int topicId) => _box.removeMany(forTopic(topicId).map((e) => e.id).toList());
  void deleteForDocument(int documentId) {
    final q = _box.query(ChunkEntity_.document.equals(documentId)).build();
    try { _box.removeMany(q.find().map((e) => e.id).toList()); } finally { q.close(); }
  }

  List<ScoredChunk> search(int topicId, List<double> queryVector, int k) {
    if (queryVector.length != 384) {
      throw StateError('Embedding dimensions changed. Re-index this knowledge base before searching.');
    }
    final query = _box.query(ChunkEntity_.vector.nearestNeighborsF32(queryVector, k) &
        ChunkEntity_.topic.equals(topicId)).build();
    try {
      return query.findWithScores()
          .map((result) => ScoredChunk(result.object, result.score))
          .toList(growable: false);
    } finally { query.close(); }
  }
  List<ChunkEntity> _find(Query<ChunkEntity> query) { try { return query.find(); } finally { query.close(); } }
}

class ChatRepository {
  ChatRepository(ObjectBoxStore store) : _box = store.store.box<ChatMessageEntity>();
  final Box<ChatMessageEntity> _box;
  List<ChatMessageEntity> forTopic(int topicId) => _find(_box.query(ChatMessageEntity_.topic.equals(topicId)).build())
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  void add(ChatMessageEntity message) => _box.put(message);
  void remove(int id) => _box.remove(id);
  Stream<List<ChatMessageEntity>> watch(int topicId) => _box.query(ChatMessageEntity_.topic.equals(topicId))
      .watch(triggerImmediately: true).map((_) => forTopic(topicId));
  void clear(int topicId) => _box.removeMany(forTopic(topicId).map((m) => m.id).toList());
  void deleteForTopic(int topicId) => clear(topicId);
  List<ChatMessageEntity> _find(Query<ChatMessageEntity> query) { try { return query.find(); } finally { query.close(); } }
}

class ModelRepository {
  ModelRepository(ObjectBoxStore store) : _box = store.store.box<ModelEntity>(), _store = store.store;
  final Box<ModelEntity> _box;
  final Store _store;
  List<ModelEntity> getAll() => _box.getAll();
  ModelEntity? active(String kind) {
    final query = _box.query(ModelEntity_.kind.equals(kind) & ModelEntity_.isActive.equals(true)).build();
    try { return query.findFirst(); } finally { query.close(); }
  }
  ModelEntity put(ModelEntity model) { _box.put(model); return model; }
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
  SettingsRepository(ObjectBoxStore store) : _box = store.store.box<SettingEntity>();
  final Box<SettingEntity> _box;
  String? get(String key) {
    final query = _box.query(SettingEntity_.key.equals(key)).build();
    try { return query.findFirst()?.value; } finally { query.close(); }
  }
  void set(String key, String value) {
    final query = _box.query(SettingEntity_.key.equals(key)).build();
    final existing = _first(query);
    final row = existing ?? (SettingEntity()..key = key);
    row.value = value;
    _box.put(row);
  }
  SettingEntity? _first(Query<SettingEntity> query) { try { return query.findFirst(); } finally { query.close(); } }
  void clear() => _box.removeAll();
}

class LocalFiles {
  static const _uuid = Uuid();
  static Future<Directory> documentsDirectory() async =>
      Directory(p.join((await getApplicationDocumentsDirectory()).path, 'documents'))..createSync(recursive: true);
  static Future<Directory> modelsDirectory() async =>
      Directory(p.join((await getApplicationDocumentsDirectory()).path, 'models'))..createSync(recursive: true);
  static String newId() => _uuid.v4();
  static String encodeSources(List<Map<String, Object?>> sources) => jsonEncode(sources);
}

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/services/document_service.dart';
import '../core/services/nfc_servide.dart';
import '../core/services/rag_service.dart';
import '../data/ai/local_rag_service.dart';
import '../data/ai/engines.dart';
import '../data/entities/entities.dart';
import '../data/repositories.dart';
import '../domain/models/doc_model.dart';
import '../domain/models/message_model.dart';
import '../domain/models/topic_model.dart';

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState notifier, required super.child}) : super(notifier: notifier);
}

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  AppState({required this.rag, required this.nfc, required this.picker, required this.prefs,
    required this.repositories, required this.embeddingEngine, required this.llmEngine, required this.useMocks}) {
    onboarded = prefs.getBool('onboarded') ?? false;
    final savedTheme = int.tryParse(repositories.settings.get('theme') ?? '') ?? ThemeMode.system.index;
    themeMode = ThemeMode.values[savedTheme.clamp(0, ThemeMode.values.length - 1)];
    _refreshTopics();
    WidgetsBinding.instance.addObserver(this);
    _topicWatch = repositories.topics.watch().listen((_) { _refreshTopics(); notifyListeners(); });
    unawaited(loadActiveModels());
  }

  static AppState of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState read(BuildContext c) => c.getInheritedWidgetOfExactType<AppScope>()!.notifier!;

  final RagService rag;
  final NfcService nfc;
  final DocumentPicker picker;
  final SharedPreferences prefs;
  final Repositories repositories;
  final bool useMocks;
  final OnDeviceEmbeddingEngine embeddingEngine;
  final OnDeviceLlamaEngine llmEngine;
  String? engineError;
  StreamSubscription<List<TopicEntity>>? _topicWatch;
  late bool onboarded;
  late ThemeMode themeMode;
  List<Topic> topics = [];
  final Map<String, List<Message>> chats = {};
  String query = '';
  String filter = 'All';
  static const categories = ['All', 'Education', 'Work', 'Personal'];

  void _refreshTopics() {
    topics = repositories.topics.getAll().map(_domainTopic).toList(growable: true);
  }

  Topic _domainTopic(TopicEntity row) => Topic(
    id: row.uuid, name: row.name, description: row.description, category: row.category,
    iconIndex: row.iconIndex, created: row.createdAt,
    docs: repositories.documents.forTopic(row.id).map((d) => Doc(
      d.uuid, d.name, _docType(d.type), d.chunkCount, d.sizeBytes / (1024 * 1024), path: d.path)).toList(),
  );

  DocType _docType(String value) => DocType.values.where((t) => t.name == value).firstOrNull ?? DocType.txt;

  List<Topic> get filtered => topics.where((t) =>
    (filter == 'All' || t.category == filter) &&
    (t.name.toLowerCase().contains(query.toLowerCase()) || t.docs.any((d) => d.name.toLowerCase().contains(query.toLowerCase())))).toList();

  Topic byId(String id) => topics.firstWhere((t) => t.id == id, orElse: () => throw StateError('Knowledge base not found.'));
  Topic? byNfcId(String id) {
    final row = repositories.topics.byNfcId(id);
    return row == null ? null : _domainTopic(row);
  }
  int get totalDocs => topics.fold(0, (n, t) => n + t.docs.length);
  double get storageGb => (repositories.documents.getAll().fold<int>(0, (sum, d) => sum + d.sizeBytes) +
      repositories.models.getAll().fold<int>(0, (sum, m) => sum + m.sizeBytes)) / 1073741824;

  void setQuery(String q) { query = q; notifyListeners(); }
  void setFilter(String f) { filter = f; notifyListeners(); }
  void setTheme(ThemeMode m) { themeMode = m; repositories.settings.set('theme', '${m.index}'); notifyListeners(); }
  void completeOnboarding() { onboarded = true; prefs.setBool('onboarded', true); notifyListeners(); }

  Topic createTopic(String name, String desc, int icon, {String category = 'Personal'}) {
    final uuid = LocalFiles.newId();
    final entity = createTopicEntity(uuid: uuid, name: name, description: desc,
      category: category, iconIndex: icon);
    repositories.topics.put(entity);
    final topic = _domainTopic(entity);
    topics.insert(0, topic);
    notifyListeners();
    return topic;
  }

  void updateTopic(String id, {required String name, required String description,
    required String category, required int iconIndex}) {
    final topic = repositories.topics.byUuid(id);
    if (topic == null) return;
    topic.name = name;
    topic.description = description;
    topic.category = category;
    topic.iconIndex = iconIndex;
    repositories.topics.put(topic);
    _refreshTopics();
    notifyListeners();
  }

  void moveDocument(String docUuid, String targetTopicUuid) {
    final document = repositories.documents.byUuid(docUuid);
    final target = repositories.topics.byUuid(targetTopicUuid);
    if (document == null || target == null) return;
    document.topic.target = target;
    repositories.documents.put(document);
    for (final chunk in repositories.chunks.forDocument(document.id)) {
      chunk.topic.target = target;
      repositories.chunks.putMany([chunk]);
    }
    _refreshTopics();
    notifyListeners();
  }

  void deleteTopic(String id) {
    repositories.topics.deleteCascade(id, repositories);
    chats.remove(id);
    _refreshTopics();
    notifyListeners();
  }

  void addDocs(String topicId, List<Doc> docs) {
    // The ingestion use case commits the complete document and chunk records.
    _refreshTopics();
    notifyListeners();
  }

  void removeDoc(String topicId, String docId) {
    repositories.documents.delete(docId, repositories.chunks);
    _refreshTopics();
    notifyListeners();
  }

  List<Message> chatOf(String id) => chats.putIfAbsent(id, () {
    final topic = repositories.topics.byUuid(id);
    if (topic == null) return <Message>[];
    return repositories.chats.forTopic(topic.id).map(fromChatEntity).toList(growable: true);
  });
  void addMessage(String id, Message message) {
    chatOf(id).add(message);
    final topic = repositories.topics.byUuid(id);
    if (topic != null) repositories.chats.add(toChatEntity(topic, message));
    notifyListeners();
  }
  void clearChat(String id) {
    final topic = repositories.topics.byUuid(id);
    if (topic != null) repositories.chats.clear(topic.id);
    chats.remove(id);
    notifyListeners();
  }
  void removeLastAssistant(String id) {
    final messages = chatOf(id);
    if (messages.isNotEmpty && !messages.last.isUser) messages.removeLast();
    final topic = repositories.topics.byUuid(id);
    if (topic != null) {
      final rows = repositories.chats.forTopic(topic.id);
      final row = rows.reversed.where((m) => !m.isUser).firstOrNull;
      if (row != null) repositories.chats.remove(row.id);
    }
    notifyListeners();
  }
  void clearChats() {
    for (final topic in repositories.topics.getAll()) {
      repositories.chats.clear(topic.id);
    }
    chats.clear();
    notifyListeners();
  }
  void refreshFromStorage() {
    chats.clear();
    _refreshTopics();
    notifyListeners();
  }

  void modelCatalogChanged() => notifyListeners();

  Future<void> loadActiveModels() async {
    try {
      final embedding = repositories.models.active('embedding');
      final llm = repositories.models.active('llm');
      if (embedding != null && !File(embedding.localPath).existsSync()) {
        throw StateError('The active embedding model file is missing. Choose or import it again in Local AI Models.');
      }
      if (llm != null && !File(llm.localPath).existsSync()) {
        throw StateError('The active language model file is missing. Choose or import it again in Local AI Models.');
      }
      if (embedding != null && embeddingEngine.dimensions == 0) await embeddingEngine.load(embedding);
      if (llm != null) await llmEngine.load(llm);
      engineError = null;
    } catch (e) { engineError = e.toString(); }
    notifyListeners();
  }

  Future<void> unloadModels() async {
    repositories.chunks.clearCache();
    await embeddingEngine.unload();
    await llmEngine.unload();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      unawaited(unloadModels());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(loadActiveModels());
    }
  }

  @override
  void didHaveMemoryPressure() {
    unawaited(unloadModels());
  }

  Future<void> resetApp() async {
    await embeddingEngine.unload();
    await llmEngine.unload();
    for (final topic in repositories.topics.getAll()) {
      repositories.topics.deleteCascade(topic.uuid, repositories);
    }
    for (final model in repositories.models.getAll()) {
      final file = File(model.localPath);
      if (file.existsSync()) await file.delete();
      repositories.models.delete(model.id);
    }
    repositories.settings.clear();
    for (final directory in [await LocalFiles.documentsDirectory(), await LocalFiles.modelsDirectory()]) {
      if (directory.existsSync()) {
        for (final entity in directory.listSync()) { await entity.delete(recursive: true); }
      }
    }
    await prefs.clear();
    topics.clear();
    chats.clear();
    onboarded = false;
    themeMode = ThemeMode.system;
    notifyListeners();
  }

  @override
  void dispose() {
    _topicWatch?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    repositories.chunks.clearCache();
    embeddingEngine.unload();
    llmEngine.unload();
    super.dispose();
  }
}

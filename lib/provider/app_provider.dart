import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
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
import '../domain/models/rag_stream_event.dart';
import '../domain/models/topic_model.dart';

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState notifier, required super.child}) : super(notifier: notifier);
}

class ChatNotice {
  const ChatNotice(this.topicId, this.topicName, {this.error});
  final String topicId;
  final String topicName;
  final String? error;
}

class _ChatRequest {
  _ChatRequest(this.topic);
  final Topic topic;
  StreamSubscription<RagStreamEvent>? subscription;
  Message? answer;
  bool cancelled = false;
  Future<void>? cancellation;
}

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  AppState({required this.rag, required this.nfc, required this.picker, required this.prefs,
    required this.repositories, required this.embeddingEngine, required this.llmEngine, required this.useMocks}) {
    onboarded = prefs.getBool('onboarded') ?? false;
    final savedTheme = int.tryParse(repositories.settings.get('theme') ?? '') ?? ThemeMode.system.index;
    themeMode = ThemeMode.values[savedTheme.clamp(0, ThemeMode.values.length - 1)];
    _refreshTopics();
    WidgetsBinding.instance.addObserver(this);
    _topicWatch = repositories.topics.watch().listen((_) {
      if (_disposed) return;
      _refreshTopics();
      notifyListeners();
    });
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
  final _chatNotices = StreamController<ChatNotice>.broadcast();
  final _answerProgress = ValueNotifier<String>('');
  _ChatRequest? _request;
  bool _disposed = false;
  AppLifecycleState _lifecycleState = WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
  Future<void> _modelWork = Future.value();
  late bool onboarded;
  late ThemeMode themeMode;
  List<Topic> topics = [];
  final Map<String, List<Message>> chats = {};
  String query = '';
  String filter = 'All';
  static const categories = ['All', 'Education', 'Work', 'Personal'];

  bool get isGenerating => _request != null;
  bool get isStopping => _request?.cancelled ?? false;
  Topic? get answeringTopic => _request?.topic;
  bool isAnswering(String topicId) => _request?.topic.id == topicId;
  ValueListenable<String> get answerProgress => _answerProgress;
  Stream<ChatNotice> get chatNotices => _chatNotices.stream;
  String? lastQuestion(String topicId) => chatOf(topicId).reversed.where((message) => message.isUser).firstOrNull?.text;

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
    unawaited(stopAnswer(id));
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
    final messages = chatOf(id);
    final topic = repositories.topics.byUuid(id);
    if (topic != null) repositories.chats.add(toChatEntity(topic, message));
    messages.add(message);
    notifyListeners();
  }
  void clearChat(String id) {
    unawaited(stopAnswer(id));
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
    unawaited(stopAnswer());
    for (final topic in repositories.topics.getAll()) {
      repositories.chats.clear(topic.id);
    }
    chats.clear();
    notifyListeners();
  }
  void refreshFromStorage() {
    unawaited(stopAnswer());
    chats.clear();
    _refreshTopics();
    notifyListeners();
  }

  bool askQuestion(String topicId, String question, {bool regenerate = false}) {
    question = question.trim();
    if (_disposed || isGenerating || question.isEmpty) return false;
    if (!useMocks && (!embeddingEngine.isLoaded || !llmEngine.isLoaded)) return false;
    final request = _ChatRequest(byId(topicId));
    _request = request;
    _answerProgress.value = '';
    try {
      if (regenerate) {
        removeLastAssistant(topicId);
      } else {
        addMessage(topicId, Message(question, true));
      }
      request.subscription = rag.askStream(request.topic, question).listen(
        (event) {
          if (_disposed || _request != request || request.cancelled) return;
          if (event.text.isNotEmpty) _answerProgress.value += event.text;
          if (event.message != null) request.answer = event.message;
        },
        onError: (Object error, StackTrace _) => _finishRequest(request, error: error),
        onDone: () => _finishRequest(request),
        cancelOnError: true,
      );
    } catch (error) {
      _finishRequest(request, error: error);
    }
    return true;
  }

  void _finishRequest(_ChatRequest request, {Object? error}) {
    if (_disposed || _request != request || request.cancelled) return;
    _request = null;
    _answerProgress.value = '';
    final topic = repositories.topics.byUuid(request.topic.id);
    if (topic != null) {
      try {
        if (error == null) {
          final answer = request.answer;
          if (answer == null) throw StateError('The local AI did not return an answer. Try again.');
          addMessage(topic.uuid, answer);
        }
      } catch (failure) {
        error = failure;
      }
      _chatNotices.add(ChatNotice(topic.uuid, topic.name, error: error?.toString()));
    }
    notifyListeners();
    if (_isBackgrounded) unawaited(_unloadIdleModels());
  }

  Future<void> stopAnswer([String? topicId]) async {
    final request = _request;
    if (request == null || (topicId != null && request.topic.id != topicId)) return;
    final pending = request.cancellation;
    if (pending != null) return pending;
    request.cancelled = true;
    if (!_disposed) notifyListeners();
    request.cancellation = _cancelRequest(request);
    await request.cancellation;
  }

  Future<void> _cancelRequest(_ChatRequest request) async {
    try {
      await Future.wait<void>([
        llmEngine.stop(),
        if (request.subscription != null) request.subscription!.cancel(),
      ]);
    } catch (error) {
      if (!_disposed) {
        _chatNotices.add(ChatNotice(request.topic.id, request.topic.name,
          error: 'Could not stop the local AI: $error'));
      }
    } finally {
      if (_request == request) _request = null;
      if (!_disposed) {
        _answerProgress.value = '';
        notifyListeners();
      }
    }
  }

  void modelCatalogChanged() => notifyListeners();

  Future<void> _runModelOperation(Future<void> Function() operation) {
    final result = _modelWork.then((_) => operation());
    _modelWork = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> loadActiveModels() async {
    try {
      await _runModelOperation(() async {
        if (_disposed || isGenerating || _isBackgrounded) return;
        final embedding = repositories.models.active('embedding');
        final llm = repositories.models.active('llm');
        if (embedding != null && !File(embedding.localPath).existsSync()) {
          throw StateError('The active embedding model file is missing. Choose or import it again in Local AI Models.');
        }
        if (llm != null && !File(llm.localPath).existsSync()) {
          throw StateError('The active language model file is missing. Choose or import it again in Local AI Models.');
        }
        if (embedding != null && !embeddingEngine.isLoaded) await embeddingEngine.load(embedding);
        if (llm != null && !llmEngine.isLoaded) await llmEngine.load(llm);
        engineError = null;
      });
    } catch (e) { engineError = e.toString(); }
    if (!_disposed) notifyListeners();
  }

  Future<void> _unloadIdleModels() => _runModelOperation(() async {
    if (isGenerating) return;
    repositories.chunks.clearCache();
    await embeddingEngine.unload();
    await llmEngine.unload();
  });

  Future<void> unloadModels() async {
    await stopAnswer();
    await _unloadIdleModels();
  }

  bool get _isBackgrounded => _lifecycleState == AppLifecycleState.paused || _lifecycleState == AppLifecycleState.detached;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (isGenerating) return;
    if (_isBackgrounded) {
      unawaited(_unloadIdleModels());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(loadActiveModels());
    }
  }

  @override
  void didHaveMemoryPressure() {
    final request = _request;
    if (request != null && !request.cancelled) {
      _chatNotices.add(ChatNotice(request.topic.id, request.topic.name,
        error: 'The answer was stopped because the device is low on memory. Try again.'));
    }
    unawaited(unloadModels());
  }

  Future<void> resetApp() async {
    await unloadModels();
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
    _disposed = true;
    _topicWatch?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(unloadModels());
    _answerProgress.dispose();
    _chatNotices.close();
    super.dispose();
  }
}

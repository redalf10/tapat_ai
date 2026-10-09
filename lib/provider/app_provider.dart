import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import '../core/services/document_service.dart';
import '../core/services/nfc_servide.dart';
import '../core/services/rag_service.dart';
import '../data/ai/local_rag_service.dart';
import '../data/ai/local_text_service.dart';
import '../data/ai/local_visual_service.dart';
import '../data/ai/image_generation_service.dart';
import '../data/ai/engines.dart';
import '../data/document_library_service.dart';
import '../data/entities/entities.dart';
import '../data/file_ingestion.dart';
import '../data/repositories.dart';
import '../domain/models/doc_model.dart';
import '../domain/models/ingest_progress.dart';
import '../domain/models/message_model.dart';
import '../domain/models/rag_stream_event.dart';
import '../domain/models/topic_model.dart';
import '../domain/models/visual_model.dart';
import '../domain/models/image_service_config.dart';

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
  _ChatRequest(this.topic, this.question);
  final Topic topic;
  final String question;
  StreamSubscription<RagStreamEvent>? subscription;
  Message? answer;
  bool cancelled = false;
  Future<void>? cancellation;
}

class _VisualJob {
  _VisualJob(this.topicId, this.kind);
  final String topicId;
  final VisualKind kind;
  final cancellation = CancelToken();
  bool cancelled = false;
}

class _LocalAiTask {
  _LocalAiTask(this.label, this.topicId, this.messageId);
  final String label;
  final String? topicId;
  final int? messageId;
  final finished = Completer<void>();
  bool cancelled = false;
  Future<void>? cancellation;
}

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  AppState({required this.rag, required this.nfc, required this.picker, required this.prefs,
    required this.repositories, required this.embeddingEngine, required this.llmEngine, required this.useMocks,
    DocumentLibraryService? documentLibrary, StableDiffusionImageService? imageService}) {
    this.documentLibrary = documentLibrary ?? DocumentLibraryService(repositories);
    this.imageService = imageService ?? StableDiffusionImageService();
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
  late final DocumentLibraryService documentLibrary;
  late final LocalTextService localText = LocalTextService(llmEngine);
  late final LocalVisualService localVisuals = LocalVisualService(localText);
  late final StableDiffusionImageService imageService;
  final _visualJobs = <int, _VisualJob>{};
  late final IngestDocumentUseCase _documentIngest = IngestDocumentUseCase(repositories, embeddingEngine);
  _LocalAiTask? _localTask;
  bool _indexing = false;
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

  bool get isGenerating => _request != null || _localTask != null;
  bool get isModelBusy => isGenerating || _indexing;
  bool get isIndexing => _indexing;
  String? get localTaskLabel => _localTask?.label;
  bool get isStopping => (_request?.cancelled ?? false) || (_localTask?.cancelled ?? false);
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
    docs: repositories.documents.forTopic(row.id).map(_domainDocument).toList(),
  );

  Doc _domainDocument(DocumentEntity d) => Doc(
    d.uuid, d.name, _docType(d.type), d.chunkCount, d.sizeBytes / (1024 * 1024),
    path: d.path, origin: d.origin, status: d.status, aiAssisted: d.aiAssisted,
    contentSha256: d.contentSha256, updatedAt: d.updatedAt,
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
    _cancelVisuals(id);
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

  Future<Doc> saveTextDocument(String topicId, {required String title, required String content,
    String? documentId, String? expectedSha256, bool aiAssisted = false}) async {
    if (isIndexing) throw StateError('Wait for document indexing to finish before saving changes.');
    final document = await documentLibrary.saveText(topicId: topicId, title: title, content: content,
      documentId: documentId, expectedSha256: expectedSha256, aiAssisted: aiAssisted);
    if (!_disposed) {
      _refreshTopics();
      notifyListeners();
    }
    return _domainDocument(document);
  }

  Future<String> generateDocumentText(String prompt) => _withLocalAi(
    'Generating document text', () => localText.generateDocument(prompt));

  Future<T> _withLocalAi<T>(String label, Future<T> Function() work, {String? topicId, int? messageId}) async {
    if (_disposed || isGenerating) throw StateError('The local AI is busy. Wait for it to finish first.');
    if (!llmEngine.isLoaded) throw StateError('Load a local language model in Local AI Models first.');
    final task = _LocalAiTask(label, topicId, messageId);
    _localTask = task;
    notifyListeners();
    try {
      final result = await work();
      if (_disposed || task.cancelled) throw StateError('Local text generation was cancelled. Your existing content was not changed.');
      return result;
    } finally {
      if (_localTask == task && !task.cancelled) _localTask = null;
      task.finished.complete();
      if (!_disposed) {
        notifyListeners();
        if (_isBackgrounded) unawaited(_unloadIdleModels());
      }
    }
  }

  Future<void> stopLocalGeneration() async {
    final task = _localTask;
    if (task == null) return;
    task.cancelled = true;
    if (!_disposed) notifyListeners();
    await (task.cancellation ??= _cancelLocalTask(task));
  }

  Future<void> _cancelLocalTask(_LocalAiTask task) async {
    try {
      await llmEngine.stop();
    } finally {
      await task.finished.future;
      if (_localTask == task) _localTask = null;
      if (!_disposed) {
        notifyListeners();
        if (_isBackgrounded) unawaited(_unloadIdleModels());
      }
    }
  }

  Stream<IngestProgress> ingestDocuments(Topic topic, List<Doc> docs) => _trackIndexing(rag.ingest(topic, docs));
  Stream<IngestProgress> indexDocument(String documentId) => _trackIndexing(_documentIngest.indexSaved(documentId));
  Stream<IngestProgress> reindexDocuments() => _trackIndexing(ReindexEmbeddingsUseCase(repositories, embeddingEngine).call());

  Stream<IngestProgress> _trackIndexing(Stream<IngestProgress> work) async* {
    if (_disposed || _indexing) throw StateError('Another document is being indexed. Wait for it to finish.');
    _indexing = true;
    notifyListeners();
    try {
      await for (final progress in work) {
        if (!_disposed) {
          _refreshTopics();
          notifyListeners();
        }
        yield progress;
      }
    } finally {
      _indexing = false;
      if (!_disposed) {
        _refreshTopics();
        notifyListeners();
        if (_isBackgrounded) unawaited(_unloadIdleModels());
      }
    }
  }

  List<Message> chatOf(String id) => chats.putIfAbsent(id, () {
    final topic = repositories.topics.byUuid(id);
    if (topic == null) return <Message>[];
    return repositories.chats.forTopic(topic.id).map(fromChatEntity).toList(growable: true);
  });
  Message addMessage(String id, Message message) {
    final messages = chatOf(id);
    final topic = repositories.topics.byUuid(id);
    if (topic != null) {
      final row = toChatEntity(topic, message);
      repositories.chats.add(row);
      message = message.copyWith(id: row.id);
    }
    messages.add(message);
    notifyListeners();
    return message;
  }
  void clearChat(String id) {
    _cancelVisuals(id);
    unawaited(stopAnswer(id));
    final topic = repositories.topics.byUuid(id);
    if (topic != null) repositories.chats.clear(topic.id);
    chats.remove(id);
    notifyListeners();
  }
  void removeLastAssistant(String id) {
    _cancelVisuals(id);
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
    _cancelVisuals();
    unawaited(stopAnswer());
    for (final topic in repositories.topics.getAll()) {
      repositories.chats.clear(topic.id);
    }
    chats.clear();
    notifyListeners();
  }
  void refreshFromStorage() {
    _cancelVisuals();
    unawaited(stopAnswer());
    chats.clear();
    _refreshTopics();
    notifyListeners();
  }

  ImageServiceConfig get imageConfig => ImageServiceConfig.decode(repositories.settings.get('image_service'));
  bool isGeneratingVisual(int messageId) => _visualJobs.containsKey(messageId);

  Future<void> setImageConfig(ImageServiceConfig config) async {
    if (config.endpoint.trim().isNotEmpty) config.addressUri();
    if (config.enabled) config.checkedUri();
    for (final entry in _visualJobs.entries.toList()) {
      if (entry.value.kind == VisualKind.image) await stopVisual(entry.value.topicId, entry.key);
    }
    repositories.settings.set('image_service', config.encode());
    if (!_disposed) notifyListeners();
  }

  bool _noVisualContext(String text) => text == PromptBuilder.noAnswer ||
      text.startsWith('This knowledge base has no documents') || text.startsWith('Your documents are saved but not indexed');

  Future<void> generateVisual(String topicId, int messageId) async {
    final message = chatOf(topicId).where((message) => message.id == messageId).firstOrNull;
    final original = message?.visual;
    if (_disposed || message == null || message.isUser || original == null || original.request.isEmpty || _visualJobs.containsKey(messageId)) return;
    final job = _VisualJob(topicId, original.kind);
    _visualJobs[messageId] = job;
    if (!_updateVisual(topicId, messageId, original.copyWith(status: VisualStatus.loading))) {
      _visualJobs.remove(messageId);
      return;
    }
    try {
      if (_noVisualContext(message.text)) throw StateError('Index relevant documents first; there is no supporting explanation for this visual.');
      final config = imageConfig;
      if (original.kind == VisualKind.image) {
        if (!config.enabled) throw StateError('Illustration generation needs an image model, not the text-only GGUF model. Enable a Stable Diffusion service in Settings → Image Generation. Local diagrams work without it.');
        config.checkedUri();
      }
      final described = await _withLocalAi(original.kind == VisualKind.diagram ? 'Generating a diagram' : 'Preparing an illustration',
        () => localVisuals.describe(VisualIntent(original.kind, explicit: original.explicit), original.request, message.text),
        topicId: topicId, messageId: messageId);
      if (job.cancelled || _visualJobs[messageId] != job) return;
      final completed = original.kind == VisualKind.diagram ? described : described.copyWith(
        status: VisualStatus.ready,
        imageBase64: await imageService.generate(described.generationPrompt, config, cancelToken: job.cancellation));
      if (!job.cancelled && _visualJobs[messageId] == job) _updateVisual(topicId, messageId, completed);
    } catch (error) {
      if (!job.cancelled && _visualJobs[messageId] == job) {
        _updateVisual(topicId, messageId, original.copyWith(status: VisualStatus.error, error: '$error'));
      }
    } finally {
      if (_visualJobs[messageId] == job) _visualJobs.remove(messageId);
      if (!_disposed) notifyListeners();
    }
  }

  bool _updateVisual(String topicId, int messageId, ChatVisual visual) {
    if (_disposed) return false;
    final topic = repositories.topics.byUuid(topicId);
    final messages = chats[topicId];
    if (topic == null || messages == null) return false;
    final index = messages.indexWhere((message) => message.id == messageId);
    final row = repositories.chats.byId(messageId);
    if (index < 0 || row == null || row.text != messages[index].text || row.isUser ||
        row.createdAt.millisecondsSinceEpoch != messages[index].sentAt.millisecondsSinceEpoch || row.topic.target?.uuid != topicId) {
      return false;
    }
    final updated = messages[index].copyWith(visual: visual);
    try {
      repositories.chats.add(toChatEntity(topic, updated));
      messages[index] = updated;
    } catch (_) {
      messages[index] = messages[index].copyWith(visual: visual.copyWith(status: VisualStatus.error,
        error: 'Could not save this visual on the device. Free some storage and regenerate it. Your text answer is unchanged.'));
      notifyListeners();
      return false;
    }
    notifyListeners();
    return true;
  }

  Future<void> stopVisual(String topicId, int messageId) async {
    final job = _visualJobs[messageId];
    if (job == null || job.topicId != topicId) return;
    _visualJobs.remove(messageId);
    job.cancelled = true;
    job.cancellation.cancel('Visual generation cancelled');
    final message = chats[topicId]?.where((message) => message.id == messageId).firstOrNull;
    if (message?.visual != null) {
      _updateVisual(topicId, messageId, message!.visual!.copyWith(
        status: VisualStatus.error, error: 'Visual generation was cancelled. Your text answer is unchanged.'));
    }
    if (_localTask?.messageId == messageId) await stopLocalGeneration();
    if (!_disposed) notifyListeners();
  }

  void _cancelVisuals([String? topicId]) {
    final cancelled = <int>{};
    for (final entry in _visualJobs.entries.toList()) {
      if (topicId != null && entry.value.topicId != topicId) continue;
      entry.value.cancelled = true;
      entry.value.cancellation.cancel('Chat was cleared or closed');
      cancelled.add(entry.key);
      _visualJobs.remove(entry.key);
    }
    if (cancelled.contains(_localTask?.messageId)) {
      unawaited(stopLocalGeneration().catchError((Object _) {
        if (!_disposed) {
          engineError = 'Could not stop visual generation. Wait for the local AI to finish.';
          notifyListeners();
        }
      }));
    }
  }

  bool chatModelsReady(String topicId, String question) {
    if (useMocks) return true;
    if (!llmEngine.isLoaded) return false;
    if (embeddingEngine.isLoaded) return true;
    final intent = VisualIntent.detect(question);
    return intent != null && intent.explicit && !byId(topicId).docs.any((doc) => doc.isIndexed);
  }

  bool askQuestion(String topicId, String question, {bool regenerate = false}) {
    question = question.trim();
    if (_disposed || isGenerating || question.isEmpty || !chatModelsReady(topicId, question)) return false;
    final request = _ChatRequest(byId(topicId), question);
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
          final intent = VisualIntent.detect(request.question);
          final noContext = _noVisualContext(answer.text);
          final visual = intent == null || (noContext && !intent.explicit) ? null : ChatVisual(
            kind: intent.kind, status: noContext ? VisualStatus.error : VisualStatus.loading,
            request: request.question, explicit: intent.explicit,
            error: noContext ? 'No supporting explanation was found in your indexed documents. Add or index relevant content before generating this visual.' : null);
          final saved = addMessage(topic.uuid, visual == null ? answer : answer.copyWith(visual: visual));
          if (visual != null && !noContext) unawaited(generateVisual(topic.uuid, saved.id));
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
        if (_disposed || isModelBusy || _isBackgrounded) return;
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
    if (isModelBusy) return;
    repositories.chunks.clearCache();
    await embeddingEngine.unload();
    await llmEngine.unload();
  });

  Future<void> unloadModels() async {
    await stopAnswer();
    await stopLocalGeneration();
    await _unloadIdleModels();
  }

  bool get _isBackgrounded => _lifecycleState == AppLifecycleState.paused || _lifecycleState == AppLifecycleState.detached;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (isModelBusy) return;
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
    _cancelVisuals();
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
    _cancelVisuals();
    _topicWatch?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(unloadModels());
    _answerProgress.dispose();
    _chatNotices.close();
    super.dispose();
  }
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tapat_ai/core/services/document_service.dart';
import 'package:tapat_ai/core/services/nfc_servide.dart';
import 'package:tapat_ai/core/services/rag_service.dart';
import 'package:tapat_ai/data/entities/mock_data.dart';
import 'package:tapat_ai/domain/models/doc_model.dart';
import 'package:tapat_ai/domain/models/message_model.dart';
import 'package:tapat_ai/domain/models/topic_model.dart';

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState notifier, required super.child})
      : super(notifier: notifier);
}

class AppState extends ChangeNotifier {
  AppState({required this.rag, required this.nfc, required this.picker, required this.prefs}) {
    onboarded = prefs.getBool('onboarded') ?? false;
    themeMode = ThemeMode.values[prefs.getInt('theme') ?? 0];
  }

  static AppState of(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState read(BuildContext c) =>
      c.getInheritedWidgetOfExactType<AppScope>()!.notifier!;

  final RagService rag;
  final NfcService nfc;
  final DocumentPicker picker;
  final SharedPreferences prefs;

  late bool onboarded;
  late ThemeMode themeMode;
  List<Topic> topics = MockData.topics();
  final Map<String, List<Message>> chats = {};
  String query = '';
  String filter = 'All';
  int _seq = 100;

  static const categories = ['All', 'Education', 'Work', 'Personal'];

  List<Topic> get filtered => topics
      .where((t) =>
          (filter == 'All' || t.category == filter) &&
          t.name.toLowerCase().contains(query.toLowerCase()))
      .toList();

  Topic byId(String id) => topics.firstWhere((t) => t.id == id);
  Topic? byNfcId(String nfcId) {
    for (final t in topics) {
      if (t.nfcId == nfcId) return t;
    }
    return topics.isEmpty ? null : topics.first;
  }

  int get totalDocs => topics.fold(0, (a, t) => a + t.docs.length);
  double get storageGb =>
      topics.fold(0.0, (a, t) => a + t.docs.fold(0.0, (b, d) => b + d.sizeMb)) / 1024 + 1.2;

  void setQuery(String q) { query = q; notifyListeners(); }
  void setFilter(String f) { filter = f; notifyListeners(); }

  void setTheme(ThemeMode m) {
    themeMode = m;
    prefs.setInt('theme', m.index);
    notifyListeners();
  }

  void completeOnboarding() {
    onboarded = true;
    prefs.setBool('onboarded', true);
    notifyListeners();
  }

  Topic createTopic(String name, String desc, int icon) {
    final t = Topic(id: '${++_seq}', name: name, description: desc, iconIndex: icon);
    topics.insert(0, t);
    notifyListeners();
    return t;
  }

  void deleteTopic(String id) {
    topics.removeWhere((t) => t.id == id);
    chats.remove(id);
    notifyListeners();
  }

  void addDocs(String topicId, List<Doc> docs) {
    byId(topicId).docs.addAll(docs);
    notifyListeners();
  }

  void removeDoc(String topicId, String docId) {
    byId(topicId).docs.removeWhere((d) => d.id == docId);
    notifyListeners();
  }

  List<Message> chatOf(String id) => chats.putIfAbsent(id, () => []);
  void addMessage(String id, Message m) {
    chatOf(id).add(m);
    notifyListeners();
  }

  void clearChats() { chats.clear(); notifyListeners(); }

  Future<void> resetApp() async {
    await prefs.clear();
    topics = MockData.topics();
    chats.clear();
    onboarded = false;
    themeMode = ThemeMode.system;
    notifyListeners();
  }
}
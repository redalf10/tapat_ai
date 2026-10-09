import 'package:objectbox_flutter_libs/objectbox_flutter_libs.dart';
import '../objectbox.g.dart';

/// The only owner of the native ObjectBox Store. Open this once before runApp.
class ObjectBoxStore {
  ObjectBoxStore._(this.store);
  static ObjectBoxStore? _instance;
  final Store store;

  static ObjectBoxStore get instance =>
      _instance ?? (throw StateError('ObjectBoxStore.open() must run before use'));

  static ObjectBoxStore inMemory(String name) =>
      ObjectBoxStore._(Store(getObjectBoxModel(), directory: '${Store.inMemoryPrefix}$name'));

  static Future<ObjectBoxStore> open() async {
    if (_instance != null) return _instance!;
    final directory = await defaultStoreDirectory();
    final store = await openStore(directory: directory.path);
    return _instance = ObjectBoxStore._(store);
  }
}

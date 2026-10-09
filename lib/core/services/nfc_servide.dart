abstract class NfcService {
  Future<bool> isAvailable();
 
  /// Returns the id stored on the tag, or null if cancelled.
  Future<String?> scan();
  Future<bool> write(String payload);
  Future<bool> erase();
  void cancel();
}

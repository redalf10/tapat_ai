import 'package:tapat_ai/domain/models/doc_model.dart';

abstract class DocumentPicker {
  Future<List<Doc>> pick();
}
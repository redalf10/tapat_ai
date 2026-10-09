import 'package:tapat_ai/domain/models/doc_model.dart';

class Topic {
  Topic({
    required this.id,
    required this.name,
    this.description = '',
    this.category = 'Personal',
    this.iconIndex = 0,
    DateTime? created,
    List<Doc>? docs,
  })  : created = created ?? DateTime.now(),
        docs = docs ?? [];
 
  final String id;
  String name, description, category;
  int iconIndex;
  final DateTime created;
  final List<Doc> docs;
 
  /// Payload written to NFC tags, e.g. "computer-001".
  String get nfcId =>
      '${name.toLowerCase().split(' ').first.replaceAll(RegExp(r'[^a-z0-9]'), '')}-${id.padLeft(3, '0')}';
  int get chunks => docs.fold(0, (a, d) => a + d.chunks);
  String get stats =>
      '${docs.length} document${docs.length == 1 ? '' : 's'} · $chunks chunks';
}
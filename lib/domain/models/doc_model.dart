enum DocType { pdf, txt, docx, md }

class Doc {
  const Doc(this.id, this.name, this.type, this.chunks, this.sizeMb, {
    this.path = '', this.origin = 'uploaded', this.status = 'ready',
    this.aiAssisted = false, this.contentSha256 = '', this.updatedAt,
  });
  final String id, name;
  final DocType type;
  final int chunks;
  final double sizeMb;
  final String path, origin, status, contentSha256;
  final bool aiAssisted;
  final DateTime? updatedAt;

  bool get isEditable => origin == 'created' && type == DocType.txt;
  bool get isIndexed => status == 'ready' && chunks > 0;
  String get statusLabel => status == 'processing' ? 'Indexing' : isIndexed ? 'Indexed · $chunks chunks' : 'Saved · Not indexed';
  String get originLabel => origin == 'created' ? (aiAssisted ? 'Created · AI-assisted' : 'Created') : 'Uploaded';
}

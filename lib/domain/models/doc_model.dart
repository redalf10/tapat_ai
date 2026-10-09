enum DocType { pdf, txt, docx, md }
 
class Doc {
  const Doc(this.id, this.name, this.type, this.chunks, this.sizeMb, {this.path = ''});
  final String id, name;
  final DocType type;
  final int chunks;
  final double sizeMb;
  final String path;
}

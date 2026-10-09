enum DocType { pdf, txt, docx }
 
class Doc {
  const Doc(this.id, this.name, this.type, this.chunks, this.sizeMb);
  final String id, name;
  final DocType type;
  final int chunks;
  final double sizeMb;
}
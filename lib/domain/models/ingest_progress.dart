class IngestProgress {
  const IngestProgress(this.stage, this.fraction, [this.detail = '']);
  final int stage; // 0..4
  final double fraction; // overall 0..1
  final String detail;
}
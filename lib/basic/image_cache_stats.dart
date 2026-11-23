class ImageCacheDay {
  final String date;
  final int fileCount;
  final int bytes;

  const ImageCacheDay({
    required this.date,
    required this.fileCount,
    required this.bytes,
  });

  factory ImageCacheDay.fromJson(Map<String, dynamic> json) {
    final date = json['date'];
    final count = json['file_count'];
    final bytes = json['bytes'];
    if (date is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        count is! int ||
        count < 0 ||
        bytes is! int ||
        bytes < 0) {
      throw const FormatException('Invalid image cache statistics');
    }
    return ImageCacheDay(date: date, fileCount: count, bytes: bytes);
  }
}

String formatCacheBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GiB';
}

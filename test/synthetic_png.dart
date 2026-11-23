import 'dart:io';
import 'dart:ui' as ui;

/// Writes an image without depending on repository or user-provided assets.
/// The caller owns the destination file and its temporary directory.
Future<void> writeSyntheticPng(
  File file, {
  required int width,
  required int height,
}) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xFF4285F4), ui.BlendMode.src);
  final picture = recorder.endRecording();
  try {
    final image = await picture.toImage(width, height);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('Could not encode synthetic PNG');
      await file.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    } finally {
      image.dispose();
    }
  } finally {
    picture.dispose();
  }
}

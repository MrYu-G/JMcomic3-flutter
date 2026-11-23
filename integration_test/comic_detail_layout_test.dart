import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:jmcomic3/configs/theme.dart' as app_theme;

import '../test/comic_detail_layout_test.dart' as detail_regressions;

// Reuse the asserted detail/navigation states on a native Flutter engine.
// Every backend request uses synthetic fixtures rather than personal data.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final density = app_theme.lightTheme.visualDensity;
  debugPrint(
    'Detail native platform=${defaultTargetPlatform.name}; '
    'visualDensity=(${density.horizontal}, ${density.vertical}); '
    'minimum chapter height=${48 + density.baseSizeAdjustment.dy}',
  );
  const output = String.fromEnvironment('DETAIL_CAPTURE_DIR');
  if (output.isNotEmpty) {
    detail_regressions.detailCheckpoint = (name, tester) async {
      await tester.pump(const Duration(milliseconds: 250));
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('comic-detail-preview')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          if (png == null) throw StateError('Empty detail capture');
          final file = File('$output/$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(
            png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
          );
        } finally {
          image.dispose();
        }
      });
    };
  }
  detail_regressions.main();
}

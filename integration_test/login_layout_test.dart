import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/login_layout_test.dart' as login_regressions;

// Exercise the same input/navigation/layout contracts on the native engine.
// The shared suite intercepts every backend call with synthetic fixtures.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const output = String.fromEnvironment('LOGIN_CAPTURE_DIR');
  if (output.isNotEmpty) {
    login_regressions.loginCheckpoint = (name, tester) async {
      // Settle finite field-label and button-state transitions while keeping
      // pending-request spinners active for their capture.
      await tester.pump(const Duration(milliseconds: 250));
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('login-layout-preview')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          if (png == null) throw StateError('Empty login capture');
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
  login_regressions.main();
}

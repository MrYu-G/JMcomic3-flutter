import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/page_image_provider.dart';
import 'package:jmcomic3/screens/components/images.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');
  const pageKey = ValueKey('pending-reader-page');
  final unavailable = jsonEncode({
    'error_message': 'Synthetic image unavailable',
    'response_data': '',
  });

  for (final layout in [
    (name: 'portrait', viewport: const Size(393, 852), explicitHeight: true),
    (name: 'landscape', viewport: const Size(852, 393), explicitHeight: true),
    (name: 'width only', viewport: const Size(393, 852), explicitHeight: false),
  ]) {
    testWidgets('${layout.name} page keeps loading and retry icons bounded', (
      tester,
    ) async {
      clearAllImageMemoryCaches();
      final requests = <Completer<String>>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'invoke');
        final request = jsonDecode(call.arguments as String) as Map;
        expect(request['method'], 'jm_page_image');
        final pending = Completer<String>();
        requests.add(pending);
        return pending.future;
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = layout.viewport;
      addTearDown(() async {
        for (final request in requests) {
          if (!request.isCompleted) request.complete(unavailable);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        clearAllImageMemoryCaches();
        messenger.setMockMethodCallHandler(channel, null);
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            // A placeholder without both dimensions must use its own fallback
            // instead of inheriting a reader-scale icon theme.
            body: IconTheme(
              data: const IconThemeData(size: 300),
              child: SizedBox.expand(
                child: JMPageImage(
                  9001,
                  'synthetic-page.png',
                  key: pageKey,
                  width: layout.viewport.width,
                  height: layout.explicitHeight ? layout.viewport.height : null,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(requests, hasLength(1));

      void expectPlaceholder(IconData icon, double size) {
        final finder = find.byIcon(icon);
        expect(finder, findsOneWidget);
        expect(tester.getSize(find.byKey(pageKey)), layout.viewport);
        expect(tester.getSize(finder), Size.square(size));
        expect(tester.getCenter(finder), tester.getCenter(find.byKey(pageKey)));
        expect(tester.takeException(), isNull);
      }

      expectPlaceholder(Icons.downloading, layout.explicitHeight ? 72 : 32);
      requests.single.complete(unavailable);
      await tester.pumpAndSettle();
      expectPlaceholder(Icons.error_outline, layout.explicitHeight ? 48 : 32);

      await tester.tap(find.byIcon(Icons.error_outline));
      await tester.pump();
      expect(requests, hasLength(2));
      expectPlaceholder(Icons.downloading, layout.explicitHeight ? 72 : 32);
      requests.last.complete(unavailable);
      await tester.pumpAndSettle();
      expectPlaceholder(Icons.error_outline, layout.explicitHeight ? 48 : 32);
    });
  }
}

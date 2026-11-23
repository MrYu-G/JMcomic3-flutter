import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/reader/reader_info_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  testWidgets(
    'chapter replacement ignores old status and refreshes on resume',
    (tester) async {
      final oldStatus = Completer<Map<String, dynamic>>();
      var requests = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'device_status');
            requests++;
            if (requests == 1) return oldStatus.future;
            return {
              'battery_level': requests == 2 ? 85 : 14,
              'charging': false,
              'network': requests == 2 ? 'wifi' : 'none',
            };
          });
      Widget bar(
        String chapter, {
        double scale = 1,
        int page = 8,
        int total = 30,
      }) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: ReaderInfoBar(
                key: ValueKey(chapter),
                page: page,
                total: total,
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(bar('old'));
      await tester.pumpWidget(bar('new'));
      await tester.pump();
      expect(find.text('85%'), findsOneWidget);
      expect(find.byIcon(Icons.wifi), findsOneWidget);
      expect(find.byIcon(Icons.battery_5_bar), findsOneWidget);
      expect(
        tester.getCenter(find.text('8/30')).dx,
        closeTo(tester.getCenter(find.byType(ReaderInfoBar)).dx, .5),
      );
      oldStatus.complete({
        'battery_level': 10,
        'charging': true,
        'network': 'mobile',
      });
      await tester.pump();
      expect(find.text('85%'), findsOneWidget);
      expect(find.text('10%'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('14%'), findsOneWidget);
      expect(find.byIcon(Icons.battery_alert), findsOneWidget);
      expect(find.byIcon(Icons.signal_wifi_off), findsOneWidget);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(bar('new', scale: 2.5, page: 999, total: 1000));
      await tester.pump();
      expect(
        tester.getTopLeft(find.text('999/1000')).dy,
        greaterThan(tester.getBottomLeft(find.text('14%')).dy),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

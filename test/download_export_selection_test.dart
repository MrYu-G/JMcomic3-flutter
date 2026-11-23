import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/configs/export_path.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/components/content_error.dart';
import 'package:jmcomic3/screens/download_export_selection_screen.dart';
import 'package:jmcomic3/screens/downloads_exporting_screen.dart';
import 'package:jmcomic3/screens/incomplete_download_export_screen.dart';

const _channel = MethodChannel('methods');

Map<String, dynamic> _album(int id, int status) => {
  'id': id,
  'name': 'Synthetic download $id',
  'author': '[]',
  'tags': '[]',
  'works': '[]',
  'dl_status': status,
  'image_count': 10,
  'dled_image_count': status == 1 ? 10 : 3,
};

class _Fixture {
  var rows = [_album(42, 1), _album(43, 1), _album(44, 4), _album(45, 3)];
  bool failLoads = false;
  int loads = 0;
  Completer<void>? loadGate;

  Future<String> handle(MethodCall call) async {
    final request = jsonDecode(call.arguments as String) as Map;
    Object response;
    switch (request['method']) {
      case 'all_downloads':
        loads++;
        await loadGate?.future;
        if (failLoads) return _envelope('', error: 'Synthetic load failure');
        response = rows;
        break;
      case 'load_property':
        response = 'D:/synthetic-exports';
        break;
      case 'jm_3x4_cover':
        return _envelope('', error: 'Synthetic cover unavailable');
      default:
        throw StateError('Unexpected backend operation ${request['method']}');
    }
    return _envelope(response);
  }
}

String _envelope(Object response, {String error = ''}) => jsonEncode({
  'error_message': error,
  'response_data': response is String ? response : jsonEncode(response),
});

Future<_Fixture> _prepare(WidgetTester tester) async {
  final fixture = _Fixture();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_channel, fixture.handle);
  tester.view.physicalSize = const Size(800, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    messenger.setMockMethodCallHandler(_channel, null);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await initExportPath();
  return fixture;
}

Widget _app({bool incomplete = false}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [AppLocalizations.delegate],
  supportedLocales: AppLocalizations.supportedLocales,
  home: incomplete
      ? const DownloadExportSelectionScreen.includingIncomplete()
      : const DownloadExportSelectionScreen.completed(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('failed export list can retry and show the refreshed downloads', (
    tester,
  ) async {
    final fixture = await _prepare(tester);
    fixture.failLoads = true;
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.byType(ContentError), findsOneWidget);
    fixture.failLoads = false;
    fixture.loadGate = Completer<void>();
    await tester.tap(find.text('(Tap to refresh)'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<IconButton>(
            // byTooltip matches the tooltip inside the button, not the button.
            find.ancestor(
              of: find.byTooltip('Export selected'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    fixture.loadGate!.complete();
    await tester.pumpAndSettle();
    expect(fixture.loads, 2);
    expect(find.text('Synthetic download 42'), findsOneWidget);
    expect(find.text('Synthetic download 44'), findsNothing);
    expect(find.byType(ContentError), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final incomplete in [false, true]) {
    testWidgets(
      'returning from ${incomplete ? 'unfinished' : 'completed'} export refreshes and retains only eligible selections',
      (tester) async {
        final fixture = await _prepare(tester);
        await tester.pumpWidget(_app(incomplete: incomplete));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Select all'));
        await tester.pump();
        await tester.tap(find.byTooltip('Export selected'));
        await tester.pumpAndSettle();
        List<int> exportedIds() => incomplete
            ? tester
                  .widget<IncompleteDownloadExportScreen>(
                    find.byType(IncompleteDownloadExportScreen),
                  )
                  .idList
            : tester
                  .widget<DownloadsExportingScreen>(
                    find.byType(DownloadsExportingScreen),
                  )
                  .idList;
        expect(exportedIds(), incomplete ? [42, 43, 44] : [42, 43]);
        fixture.rows = [
          _album(42, 1),
          _album(43, 3),
          _album(44, 4),
          _album(46, 1),
        ];
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(fixture.loads, 2);
        expect(find.text('Synthetic download 43'), findsNothing);
        expect(find.text('Synthetic download 46'), findsOneWidget);
        expect(
          find.byIcon(Icons.check_circle),
          findsNWidgets(incomplete ? 2 : 1),
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Export selected'));
        await tester.pumpAndSettle();
        expect(exportedIds(), incomplete ? [42, 44] : [42]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('disposing during export list retry ignores late completion', (
    tester,
  ) async {
    final fixture = await _prepare(tester);
    fixture.failLoads = true;
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    fixture.failLoads = false;
    fixture.loadGate = Completer<void>();
    await tester.tap(find.text('(Tap to refresh)'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    fixture.loadGate!.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

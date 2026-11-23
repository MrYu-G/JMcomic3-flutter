import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/trusted_updates.dart';
import 'package:jmcomic3/configs/theme.dart';
import 'package:jmcomic3/configs/versions.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/about_screen.dart';
import 'package:jmcomic3/screens/components/update_dialog.dart';

import 'trusted_updates_test.dart' show releaseFixture;

class _ControlledDownload extends UpdateDownloader {
  final completion = Completer<File>();
  void Function(UpdateDownloadProgress)? progress;
  bool cancelled = false;
  @override
  Future<File> download(
    UpdateAsset asset,
    void Function(UpdateDownloadProgress) onProgress,
  ) {
    progress = onProgress;
    return completion.future;
  }

  @override
  void cancel() {
    cancelled = true;
    if (!completion.isCompleted)
      completion.completeError(UpdateDownloadCancelled());
    super.cancel();
  }
}

const _preview = ValueKey('update-preview');
final _screenshots = Platform.environment['LAYOUT_SCREENSHOTS'] == '1';

Future<void> _capture(WidgetTester tester, String name) async {
  if (!_screenshots) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_preview),
  );
  await tester.runAsync(() async {
    final bitmap = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await bitmap.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/checks/hijacked-updates/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      bitmap.dispose();
    }
  });
}

Widget _host(
  Widget child, {
  bool dark = false,
  double scale = 1,
  String locale = 'en',
}) => MaterialApp(
  theme: (_screenshots
      ? (dark ? darkTheme : lightTheme).copyWith(
          textTheme: (dark ? darkTheme : lightTheme).textTheme.apply(
            fontFamily: 'Arial',
          ),
          primaryTextTheme: (dark ? darkTheme : lightTheme).primaryTextTheme
              .apply(fontFamily: 'Arial'),
        )
      : (dark ? darkTheme : lightTheme)),
  locale: Locale(locale),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: RepaintBoundary(key: _preview, child: child!),
  ),
  home: child,
);

void main() {
  setUpAll(() async {
    if (_screenshots) {
      for (final font in {
        'Arial': 'C:/Windows/Fonts/arial.ttf',
        'Roboto': 'C:/Windows/Fonts/segoeui.ttf',
        'Microsoft YaHei': 'C:/Windows/Fonts/msyh.ttc',
      }.entries) {
        if (await File(font.value).exists()) {
          final bytes = ByteData.sublistView(
            await File(font.value).readAsBytes(),
          );
          await (FontLoader(font.key)..addFont(Future.value(bytes))).load();
        }
      }
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    }
  });

  for (final width in [320.0, 1200.0]) {
    testWidgets('full release notes and update actions remain usable at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final body = List.generate(
        12,
        (i) =>
            '## Change ${i + 1}\n\nThis paragraph explains the complete change without clipping.',
      ).join('\n\n');
      final json = releaseFixture(tag: 'v99.1.0+990')..['body'] = body;
      final release = TrustedRelease.parse(json);
      final properties = {
        'verifiedGithubReleaseCacheV1': jsonEncode({
          'repository': updateRepository,
          'release': json,
        }),
      };
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('methods'), (
            call,
          ) async {
            final request = jsonDecode(call.arguments as String) as Map;
            return jsonEncode({
              'error_message': '',
              'response_data': request['method'] == 'load_property'
                  ? properties[request['params']] ?? ''
                  : '',
            });
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel('methods'), null),
      );
      await tester.runAsync(initVersion);
      await tester.pumpWidget(
        _host(
          const AboutScreen(),
          dark: width > 1000,
          scale: width == 320 ? 1.5 : 1,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<ReleaseNotes>(find.byType(ReleaseNotes)).body,
        contains(body),
      );
      expect(find.text('Download update'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'about-${width.toInt()}');
      await tester.pumpWidget(
        _host(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => UpdateReleaseDialog(release: release),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
          dark: width > 1000,
          scale: width == 320 ? 1.5 : 1,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.widget<ReleaseNotes>(find.byType(ReleaseNotes)).body, body);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'release-dialog-${width.toInt()}');
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.byType(UpdateReleaseDialog), findsNothing);
    });
  }

  testWidgets(
    'download reports target, percent, bytes, route and verification before export',
    (tester) async {
      tester.view.physicalSize = const Size(390, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final release = TrustedRelease.parse(releaseFixture());
      final downloader = _ControlledDownload();
      await tester.pumpWidget(
        _host(
          Scaffold(
            body: UpdateDownloadDialog(
              version: release.tag,
              asset: release.assets.single,
              downloader: downloader,
            ),
          ),
        ),
      );
      await tester.pump();
      downloader.progress!(
        const UpdateDownloadProgress(UpdateDownloadPhase.downloading, 50, 100),
      );
      await tester.pump();
      expect(find.textContaining('v1.7.27+56'), findsWidgets);
      expect(find.textContaining('50%'), findsOneWidget);
      expect(find.text('Download route: Official GitHub'), findsOneWidget);
      expect(find.text('Save package'), findsNothing);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'download-progress');
      downloader.progress!(
        const UpdateDownloadProgress(UpdateDownloadPhase.verifying, 100, 100),
      );
      await tester.pump();
      expect(find.text('Verifying SHA-256…'), findsOneWidget);
      expect(find.text('Save package'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(downloader.cancelled, isTrue);
    },
  );
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/runtime_log.dart';
import 'package:jmcomic3/configs/theme.dart' as app_theme;
import 'package:jmcomic3/configs/download_thread_count.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/download_import_screen.dart';
import 'package:jmcomic3/screens/image_cache_screen.dart';
import 'package:jmcomic3/screens/runtime_log_screen.dart';
import 'package:jmcomic3/screens/downloads_screen.dart';

const _channel = MethodChannel('methods');
const _preview = ValueKey('library-management-preview');
final _screenshots = Platform.environment['LAYOUT_SCREENSHOTS'] == '1';

Widget _app(Widget screen, {bool dark = false, double scale = 1}) =>
    MaterialApp(
      theme: app_theme.lightTheme,
      darkTheme: app_theme.darkTheme,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      locale: const Locale('en'),
      localizationsDelegates: const [AppLocalizations.delegate],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: RepaintBoundary(key: _preview, child: child!),
      ),
      home: screen,
    );

Future<void> _capture(WidgetTester tester, String name) async {
  if (!_screenshots) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_preview),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/checks/library-management/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _fonts(WidgetTester tester) async {
  if (!_screenshots) return;
  await tester.runAsync(() async {
    final font = File('C:/Windows/Fonts/segoeui.ttf');
    if (await font.exists()) {
      final bytes = ByteData.sublistView(await font.readAsBytes());
      for (final family in ['Roboto', 'LayoutPreview']) {
        await (FontLoader(family)..addFont(Future.value(bytes))).load();
      }
    }
    final config = jsonDecode(
      await File('.dart_tool/package_config.json').readAsString(),
    ) as Map;
    final sdk = Uri.parse(config['flutterRoot'] as String).toFilePath();
    final icons = File(
      '$sdk/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    );
    if (await icons.exists()) {
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(ByteData.sublistView(await icons.readAsBytes())),
          ))
          .load();
    }
  });
}

class _Picker extends FilePickerPlatform {
  PlatformFile? result;
  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => result;
}

final class _PickedBackup extends PlatformFile {
  @override
  String get name => 'backup.jmi';
  @override
  String get path => 'C:/test-fixtures/backup.jmi';
  @override
  Uri get uri => Uri.file(path, windows: true);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(_channel, null);
    clearRuntimeLog();
  });

  test(
    'runtime diagnostics are bounded and do not accept data as operation names',
    () {
      clearRuntimeLog();
      for (var i = 0; i < runtimeLogCapacity + 2; i++) {
        recordRuntimeOperation(
          'operation_$i',
          failed: i.isEven,
          duration: Duration(milliseconds: i),
        );
      }
      expect(runtimeLogEntries, hasLength(runtimeLogCapacity));
      expect(runtimeLogEntries.last.operation, 'operation_2');
      recordRuntimeOperation(
        'https://example.invalid/?token=private',
        failed: true,
        duration: Duration.zero,
      );
      expect(runtimeLogEntries.first.operation, 'operation');
    },
  );

  testWidgets('cache cleanup sends selected dates and refreshes statistics', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var rows = <Map<String, dynamic>>[
      {'date': '2026-11-23', 'file_count': 3, 'bytes': 4096},
      {'date': '2026-11-22', 'file_count': 2, 'bytes': 2048},
    ];
    final deleted = <List<String>>[];
    messenger.setMockMethodCallHandler(_channel, (call) async {
      final request = jsonDecode(call.arguments as String) as Map;
      Object response;
      if (request['method'] == 'image_cache_stats') {
        response = rows;
      } else if (request['method'] == 'clean_image_cache_dates') {
        final params = jsonDecode(request['params'] as String) as Map;
        final dates = (params['dates'] as List).cast<String>();
        deleted.add(dates);
        rows = rows.where((row) => !dates.contains(row['date'])).toList();
        response = '';
      } else {
        throw StateError('Unexpected method ${request['method']}');
      }
      return jsonEncode({
        'error_message': '',
        'response_data': response is String ? response : jsonEncode(response),
      });
    });
    await _fonts(tester);
    await tester.pumpWidget(_app(const ImageCacheScreen()));
    await tester.pumpAndSettle();
    expect(find.text('6.0 KiB · 5 files'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cache-date-2026-11-22')));
    await tester.pumpAndSettle();
    await _capture(tester, 'cache-selected-mobile');
    await tester.tap(
      find.widgetWithText(FilledButton, 'Clear 1 selected days · 2.0 KiB'),
    );
    await tester.pumpAndSettle();
    expect(deleted, [
      ['2026-11-22'],
    ]);
    expect(find.byKey(const ValueKey('cache-date-2026-11-22')), findsNothing);
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Clear 1 selected days · 4.0 KiB'),
    );
    await tester.pumpAndSettle();
    expect(deleted.last, ['2026-11-23']);
    expect(find.text('No image cache'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('error filter preserves icon and removes successful operations', (
    tester,
  ) async {
    recordRuntimeOperation(
      'successful_request',
      failed: false,
      duration: Duration.zero,
    );
    recordRuntimeOperation(
      'failed_request',
      failed: true,
      duration: const Duration(milliseconds: 12),
    );
    await _fonts(tester);
    await tester.pumpWidget(_app(const RuntimeLogScreen(), dark: true));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Errors Only'));
    await tester.pumpAndSettle();
    final chip = tester.widget<FilterChip>(find.byType(FilterChip));
    expect(chip.showCheckmark, isFalse);
    expect((chip.avatar! as Icon).icon, Icons.error_outline);
    expect(
      chip.selectedColor,
      Theme.of(tester.element(find.byType(FilterChip)))
          .colorScheme
          .errorContainer,
    );
    expect(find.text('successful_request'), findsNothing);
    expect(find.text('failed_request'), findsOneWidget);
    await _capture(tester, 'runtime-log-selected-dark');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'downloads display the backend-resolved full directory after retry',
    (tester) async {
      var directoryRequests = 0;
      const directory = 'D:/Test downloads/Shared library/nested directory';
      messenger.setMockMethodCallHandler(_channel, (call) async {
        final request = jsonDecode(call.arguments as String) as Map;
        Object response;
        switch (request['method']) {
          case 'load_download_thread':
            response = '2';
            break;
          case 'all_downloads':
            response = <Object>[];
            break;
          case 'get_effective_download_dir':
            directoryRequests++;
            if (directoryRequests == 1) {
              return jsonEncode({
                'error_message': 'Directory unavailable',
                'response_data': '',
              });
            }
            response = directory;
            break;
          default:
            throw StateError('Unexpected method ${request['method']}');
        }
        return jsonEncode({
          'error_message': '',
          'response_data': response is String ? response : jsonEncode(response),
        });
      });
      await initDownloadThreadCount();
      await _fonts(tester);
      await tester.pumpWidget(_app(const DownloadsScreen()));
      await tester.pumpAndSettle();
      expect(find.textContaining('Directory unavailable'), findsOneWidget);
      await tester.tap(find.byTooltip('Retry'));
      await tester.pumpAndSettle();
      expect(find.text(directory), findsOneWidget);
      expect(directoryRequests, 2);
      await _capture(tester, 'downloads-directory-wide');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'import cancellation, failure and retry keep controls available',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final picker = _Picker();
      final previousPicker = FilePickerPlatform.instance;
      FilePickerPlatform.instance = picker;
      addTearDown(() => FilePickerPlatform.instance = previousPicker);
      var imports = 0;
      final pending = Completer<String>();
      messenger.setMockMethodCallHandler(_channel, (call) async {
        final request = jsonDecode(call.arguments as String) as Map;
        expect(request['method'], 'import_jm_jmi');
        expect(request['params'], 'C:/test-fixtures/backup.jmi');
        imports++;
        if (imports == 1) {
          return jsonEncode({
            'error_message': 'Invalid backup',
            'response_data': '',
          });
        }
        return pending.future;
      });
      await _fonts(tester);
      await tester.pumpWidget(_app(const DownloadImportScreen()));
      await tester.pumpAndSettle();
      await _capture(tester, 'import-mobile');
      await tester.tap(find.text('Import a file'));
      await tester.pumpAndSettle();
      expect(
        find.text('Selection cancelled. You can choose another backup.'),
        findsOneWidget,
      );
      expect(imports, 0);
      picker.result = _PickedBackup();
      await tester.tap(find.text('Import a file'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Invalid backup'), findsOneWidget);
      await _capture(tester, 'import-error-mobile');
      await tester.tap(find.text('Import a file'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.tap(find.text('Import a file'));
      expect(imports, 2);
      pending.complete(jsonEncode({'error_message': '', 'response_data': ''}));
      await tester.pumpAndSettle();
      expect(
        find.text('Import complete. Open Downloads to view your comics.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/entities.dart';
import 'package:jmcomic3/configs/download_thread_count.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';
import 'package:jmcomic3/screens/downloads_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'paused download retains progress without claiming deletion or polling',
    () {
      final album = DownloadAlbum.fromJson({
        'id': 42,
        'name': 'Paused',
        'dl_status': 4,
        'image_count': 10,
        'dled_image_count': 3,
      });
      expect(album.isPaused, isTrue);
      expect(album.isDeleting, isFalse);
      expect(album.shouldAutoRefreshStatus, isFalse);
      expect(album.downloadProgress, .3);
    },
  );

  testWidgets(
    'download actions pause, persist visible status and resume same task',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var status = 0;
      final actions = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(const MethodChannel('methods'), (
        call,
      ) async {
        final request = jsonDecode(call.arguments as String) as Map;
        final method = request['method'];
        Object response = '';
        switch (method) {
          case 'load_download_thread':
            response = '2';
            break;
          case 'get_effective_download_dir':
            response = 'D:/fixture/downloads';
            break;
          case 'all_downloads':
            response = [
              {
                'id': 42,
                'name': 'Synthetic download',
                'author': '[]',
                'tags': '[]',
                'works': '[]',
                'dl_status': status,
                'image_count': 10,
                'dled_image_count': 3,
              },
            ];
            break;
          case 'pause_download':
          case 'resume_download':
            expect(request['params'], '42');
            actions.add(method as String);
            status = method == 'pause_download' ? 4 : 0;
            break;
          case 'jm_3x4_cover':
            return jsonEncode({
              'error_message': 'Fixture has no cover',
              'response_data': '',
            });
          default:
            throw StateError('Unexpected $method');
        }
        return jsonEncode({
          'error_message': '',
          'response_data': response is String ? response : jsonEncode(response),
        });
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('methods'),
          null,
        ),
      );
      await initDownloadThreadCount();
      await tester.pumpWidget(
        const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: DownloadsScreen(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Import downloads'), findsOneWidget);
      await tester.tap(find.byTooltip('More download options'));
      await tester.pumpAndSettle();
      expect(find.text('Export downloads'), findsOneWidget);
      expect(find.text('Concurrent downloads: 2'), findsOneWidget);
      expect(find.text('Refresh download status'), findsOneWidget);
      // Dismiss without mutating tasks; then use the visible task menu.
      await tester.tapAt(const Offset(4, 700));
      await tester.pumpAndSettle();
      final actionsButton = find.byTooltip('Download actions');
      expect(tester.getSize(actionsButton).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(actionsButton).height, greaterThanOrEqualTo(48));
      await tester.tap(actionsButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pause download'));
      await tester.pumpAndSettle();
      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('Deleting'), findsNothing);
      await tester.longPress(find.byKey(const Key('DOWNLOAD:42')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resume download'));
      await tester.pumpAndSettle();
      expect(find.text('Downloading'), findsOneWidget);
      expect(actions, ['pause_download', 'resume_download']);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}

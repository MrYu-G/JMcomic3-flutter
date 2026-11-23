import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/configs/login.dart';
import 'package:jmcomic3/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  testWidgets(
    'folder create failure stays visible and retry refreshes the folder menu',
    (tester) async {
      var creates = 0;
      var folders = <Map<String, dynamic>>[];
      final requests = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        final request = jsonDecode(call.arguments as String) as Map;
        final method = request['method'] as String;
        requests.add(method);
        Object response = '';
        switch (method) {
          case 'pre_login':
            response = {
              'pre_set': true,
              'pre_login': true,
              'message': '',
              'self_info': {
                'uid': 42,
                'username': 'Fixture',
                'email': '',
                'emailverified': '',
                'photo': '?v=0?v=',
                'fname': '',
                'gender': '',
                'message': '',
                'coin': 0,
                'album_favorites': 0,
                's': '',
                'level_name': '',
                'level': 1,
                'nextLevelExp': 100,
                'exp': '0',
                'expPercent': 0.0,
                'badges': [],
                'album_favorites_max': 100,
              },
            };
            break;
          case 'favorite':
            response = {
              'total': 0,
              'count': 0,
              'list': [],
              'folder_list': folders,
            };
            break;
          case 'create_favorite_folder':
            creates++;
            expect(request['params'], 'New folder');
            if (creates == 1)
              return jsonEncode({
                'error_message': 'Folder request rejected',
                'response_data': '',
              });
            folders = [
              {'FID': 7, 'UID': 42, 'name': 'New folder'},
            ];
            response = {'status': 'ok', 'msg': ''};
            break;
          case 'pro_info_all':
            response = {
              'pro_info_af': {'is_pro': true, 'expire': 4102444800},
              'pro_info_pat': {'is_pro': true},
            };
            break;
        }
        return jsonEncode({
          'error_message': '',
          'response_data': response is String ? response : jsonEncode(response),
        });
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  createFavoriteFolderItemTile(context),
                  deleteFavoriteFolderItemTile(context),
                  renameFavoriteFolderItemTile(context),
                ],
              ),
            ),
          ),
        ),
      );
      await initLogin(tester.element(find.byType(Scaffold)));
      await tester.pumpAndSettle();
      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.tap(find.text('Create favorites folder'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '  New folder  ');
        await tester.tap(find.text('Confirm'));
        await tester.pumpAndSettle();
        if (attempt == 0) {
          expect(favData, isEmpty);
          expect(
            find.textContaining('Folder request rejected'),
            findsOneWidget,
          );
        } else {
          expect(favData.single.fid, 7);
          expect(favData.single.name, 'New folder');
        }
        await tester.pump(const Duration(seconds: 5));
      }
      expect(creates, 2);
      expect(requests.where((request) => request == 'favorite'), hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );
}

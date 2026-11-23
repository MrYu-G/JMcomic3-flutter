import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/reader_image_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('methods');
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  test(
    'session cleanup waits for reads and never ends a newer reader',
    () async {
      final ended = <String>[];
      var created = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final request = jsonDecode(call.arguments as String) as Map;
            var response = '';
            if (request['method'] == 'begin_reader_session') {
              response = 'session-${++created}';
            } else if (request['method'] == 'end_reader_session') {
              ended.add(request['params'] as String);
            }
            return jsonEncode({'error_message': '', 'response_data': response});
          });
      final old = ReaderImageSession();
      final newer = ReaderImageSession();
      final gate = Completer<void>();
      final read = old.run(() async {
        await old.token;
        await gate.future;
      });
      final closing = old.close();
      await newer.token;
      expect(ended, isEmpty);
      await expectLater(old.run(() async {}), throwsStateError);
      gate.complete();
      await read;
      await closing;
      await old.close();
      expect(ended, ['session-1']);
      expect(newer.closed, isFalse);
      await newer.close();
      expect(ended, ['session-1', 'session-2']);
    },
  );
}

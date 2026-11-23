import 'dart:convert';

import 'package:flutter/services.dart';

import '../method_response_decoder.dart';
import '../runtime_log.dart';

/// The single native transport used by the app. Method-specific payloads and
/// entities stay in Methods; this boundary owns the string envelope and timing.
class MethodChannelTransport {
  const MethodChannelTransport();
  static const _channel = MethodChannel('methods');

  Future<String> invoke(String method, dynamic params) async {
    final elapsed = Stopwatch()..start();
    var failed = false;
    try {
      final response = await _channel.invokeMethod<String>(
        'invoke',
        jsonEncode({
          'method': method,
          'params': params is String ? params : jsonEncode(params),
        }),
      );
      if (response == null) {
        throw const FormatException('Missing invoke response');
      }
      return decodeInvokeResponse(response);
    } catch (_) {
      failed = true;
      rethrow;
    } finally {
      // Never send request data, credentials, paths or backend error text to
      // runtime diagnostics. The operation identifier is sanitized by the log.
      recordRuntimeOperation(method, failed: failed, duration: elapsed.elapsed);
    }
  }

  Future<dynamic> invokePlatform(String method, [dynamic arguments]) =>
      _channel.invokeMethod<dynamic>(method, arguments);
}

// Run with the pinned Dart executable, without `dart run` or Flutter/native
// build hooks: dart --packages=.dart_tool/package_config.json test/bridge_core_check.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:jmcomic3/basic/bridge/response_cache.dart';
import 'package:jmcomic3/basic/method_response_decoder.dart';

int _assertions = 0;

void check(bool condition, String message) {
  _assertions++;
  if (!condition) throw StateError(message);
}

void equal(Object? actual, Object? expected, String message) =>
    check(actual == expected, '$message: expected <$expected>, got <$actual>');

Future<void> rejects<T extends Object>(
  FutureOr<Object?> Function() action,
  String message, {
  Object? identicalError,
}) async {
  try {
    await action();
  } catch (error) {
    check(error is T, '$message: expected $T, got ${error.runtimeType}');
    if (identicalError != null) {
      check(identical(error, identicalError), '$message: error was replaced');
    }
    return;
  }
  throw StateError('$message: expected $T, but operation succeeded');
}

class _Clock {
  DateTime value = DateTime.utc(2026, 1, 1);
  DateTime now() => value;
  void advance(Duration duration) => value = value.add(duration);
}

Future<String> _unexpectedLoad() => throw StateError(
  'A valid cached/coalesced request must not run its loader',
);

Future<void> _ttl() async {
  final clock = _Clock();
  final cache = ResponseCache(ttl: const Duration(seconds: 10), now: clock.now);
  equal(
    await cache.load('album', () async => 'first'),
    'first',
    'Initial load',
  );
  clock.advance(const Duration(seconds: 10));
  equal(await cache.load('album', _unexpectedLoad), 'first', 'Inclusive TTL');
  clock.advance(const Duration(microseconds: 1));
  equal(
    await cache.load('album', () async => 'second'),
    'second',
    'Expired TTL',
  );
  equal(
    await cache.load('album', _unexpectedLoad),
    'second',
    'Refreshed value',
  );
}

Future<void> _deduplication() async {
  final cache = ResponseCache(ttl: const Duration(minutes: 1));
  final loading = Completer<String>();
  var calls = 0;
  final first = cache.load('same', () {
    calls++;
    return loading.future;
  });
  final second = cache.load('same', _unexpectedLoad);
  check(
    identical(first, second),
    'Concurrent readers share one pending future',
  );
  equal(calls, 1, 'One loader runs');
  equal(
    await cache.load('other', () async => 'independent'),
    'independent',
    'Keys load independently',
  );
  loading.complete('coalesced');
  equal(await first, 'coalesced', 'First reader completes');
  equal(await second, 'coalesced', 'Second reader completes');

  Future<String>? reentrant;
  final outer = cache.load('reentrant', () {
    reentrant = cache.load('reentrant', _unexpectedLoad);
    return Future.value('registered-before-loader');
  });
  check(identical(outer, reentrant), 'Synchronous reentrant access coalesces');
  equal(await outer, 'registered-before-loader', 'Reentrant load completes');
}

Future<void> _retryFailures() async {
  final cache = ResponseCache(ttl: const Duration(minutes: 1));
  final failure = StateError('synthetic network failure');
  await rejects<StateError>(
    () => cache.load('sync', () => throw failure),
    'Synchronous failure',
    identicalError: failure,
  );
  equal(
    await cache.load('sync', () async => 'retry'),
    'retry',
    'Synchronous failure is not cached',
  );
  final pending = Completer<String>();
  final first = cache.load('async', () => pending.future);
  final second = cache.load('async', _unexpectedLoad);
  final checks = [
    rejects<StateError>(
      () => first,
      'First failure propagates',
      identicalError: failure,
    ),
    rejects<StateError>(
      () => second,
      'Joined failure propagates',
      identicalError: failure,
    ),
  ];
  pending.completeError(failure);
  await Future.wait(checks);
  equal(
    await cache.load('async', () async => 'recovered'),
    'recovered',
    'Failed flight can retry',
  );
}

Future<void> _boundedEviction() async {
  final cache = ResponseCache(ttl: const Duration(minutes: 1), capacity: 2);
  await cache.load('a', () async => 'A');
  await cache.load('b', () async => 'B');
  equal(
    await cache.load('a', _unexpectedLoad),
    'A',
    'Cache hit refreshes recency',
  );
  await cache.load('c', () async => 'C');
  equal(await cache.load('a', _unexpectedLoad), 'A', 'Recent entry survives');
  equal(await cache.load('c', _unexpectedLoad), 'C', 'New entry survives');
  equal(
    await cache.load('b', () async => 'B-reloaded'),
    'B-reloaded',
    'Least recent entry is evicted',
  );
  final one = ResponseCache(ttl: const Duration(minutes: 1), capacity: 1);
  await one.load('old', () async => 'old');
  await one.load('new', () async => 'new');
  equal(
    await one.load('old', () async => 'reload'),
    'reload',
    'Capacity one is enforced',
  );
}

Future<void> _clearRaces() async {
  for (final oldFinishesFirst in [true, false]) {
    final cache = ResponseCache(ttl: const Duration(minutes: 1));
    final old = Completer<String>();
    final current = Completer<String>();
    final oldRead = cache.load('account-comics', () => old.future);
    cache.clear(); // The account/route mutation invalidates earlier ownership.
    final newRead = cache.load('account-comics', () => current.future);
    if (oldFinishesFirst) {
      old.complete('previous-account');
      equal(
        await oldRead,
        'previous-account',
        'Existing caller retains its result',
      );
      check(
        identical(cache.load('account-comics', _unexpectedLoad), newRead),
        'Old completion cannot erase newer flight',
      );
      current.complete('current-account');
      await newRead;
    } else {
      current.complete('current-account');
      await newRead;
      old.complete('previous-account');
      await oldRead;
    }
    equal(
      await cache.load('account-comics', _unexpectedLoad),
      'current-account',
      'Old account completion cannot overwrite current cache',
    );
  }
  final cache = ResponseCache(ttl: const Duration(minutes: 1));
  final old = Completer<String>();
  final oldRead = cache.load('route', () => old.future);
  cache.clear();
  old.complete('old-route');
  await oldRead;
  equal(
    await cache.load('route', () async => 'new-route'),
    'new-route',
    'Invalidated result cannot repopulate an empty cache',
  );

  final failed = Completer<String>();
  final failedRead = cache.load('failing-route', () => failed.future);
  final checked = rejects<StateError>(
    () => failedRead,
    'Old route failure propagates',
  );
  cache.clear();
  final fresh = Completer<String>();
  final freshRead = cache.load('failing-route', () => fresh.future);
  failed.completeError(StateError('old route failed'));
  await checked;
  check(
    identical(cache.load('failing-route', _unexpectedLoad), freshRead),
    'Old failure does not remove new pending request',
  );
  fresh.complete('fresh-route');
  await freshRead;
}

Future<void> _partialRemoval() async {
  final cache = ResponseCache(ttl: const Duration(minutes: 1));
  await cache.load('7|cached', () async => 'changed-album');
  await cache.load('8|cached', () async => 'unrelated-album');
  final old = Completer<String>();
  final other = Completer<String>();
  final oldRead = cache.load('7|pending', () => old.future);
  final otherRead = cache.load('8|pending', () => other.future);
  cache.removeWhere((key) => key.startsWith('7|'));
  equal(
    await cache.load('7|cached', () async => 'refetched'),
    'refetched',
    'Selected completed entry removed',
  );
  equal(
    await cache.load('8|cached', _unexpectedLoad),
    'unrelated-album',
    'Unselected completed entry remains',
  );
  check(
    identical(cache.load('8|pending', _unexpectedLoad), otherRead),
    'Unselected flight remains coalesced',
  );
  final replacement = Completer<String>();
  final replacementRead = cache.load('7|pending', () => replacement.future);
  old.complete('obsolete');
  await oldRead;
  check(
    identical(cache.load('7|pending', _unexpectedLoad), replacementRead),
    'Removed old flight cannot erase replacement',
  );
  other.complete('unrelated-result');
  replacement.complete('updated-result');
  await Future.wait([otherRead, replacementRead]);
  equal(
    await cache.load('7|pending', _unexpectedLoad),
    'updated-result',
    'Selected replacement persists',
  );
  equal(
    await cache.load('8|pending', _unexpectedLoad),
    'unrelated-result',
    'Unrelated flight publishes normally',
  );
}

Future<void> _stalePolicy() async {
  final clock = _Clock();
  final cache = ResponseCache(ttl: const Duration(seconds: 5), now: clock.now);
  await cache.load('display', () async => 'cached-display');
  clock.advance(const Duration(seconds: 6));
  equal(
    await cache.load(
      'display',
      () => throw StateError('offline'),
      allowStaleOnError: true,
    ),
    'cached-display',
    'Explicit stale fallback',
  );
  clock.advance(const Duration(seconds: 4));
  equal(
    await cache.load('display', _unexpectedLoad),
    'cached-display',
    'Fallback renews TTL to avoid retry storms',
  );
  clock.advance(const Duration(seconds: 2));
  await rejects<StateError>(
    () => cache.load('display', () => throw StateError('strict')),
    'Strict request does not return stale',
  );
  equal(
    await cache.load('display', () async => 'online'),
    'online',
    'Strict failure leaves request retryable',
  );
  await rejects<StateError>(
    () => cache.load(
      'empty',
      () => throw StateError('offline'),
      allowStaleOnError: true,
    ),
    'Missing cache cannot fall back',
  );
}

Future<void> _invalidatedStalePolicy() async {
  for (final partial in [false, true]) {
    final clock = _Clock();
    final cache = ResponseCache(
      ttl: const Duration(seconds: 1),
      now: clock.now,
    );
    await cache.load('account|album', () async => 'old-account-cache');
    clock.advance(const Duration(seconds: 2));
    final old = Completer<String>();
    final oldRead = cache.load(
      'account|album',
      () => old.future,
      allowStaleOnError: true,
    );
    final checked = rejects<StateError>(
      () => oldRead,
      'Invalidated flight cannot return stale account data',
    );
    if (partial) {
      cache.removeWhere((key) => key.startsWith('account|'));
    } else {
      cache.clear();
    }
    final current = Completer<String>();
    final currentRead = cache.load('account|album', () => current.future);
    old.completeError(StateError('old request failed'));
    await checked;
    check(
      identical(cache.load('account|album', _unexpectedLoad), currentRead),
      'Stale old error does not erase new flight',
    );
    current.complete('current-account');
    await currentRead;
    equal(
      await cache.load('account|album', _unexpectedLoad),
      'current-account',
      'Stale old error cannot publish over new value',
    );
  }
}

String _envelope(String data, {String error = ''}) =>
    jsonEncode({'error_message': error, 'response_data': data});

Future<void> _responseEnvelope() async {
  equal(decodeInvokeResponse(_envelope('')), '', 'Empty success payload');
  equal(
    decodeInvokeResponse(_envelope('  plain text  ')),
    '  plain text  ',
    'Payload whitespace preserved',
  );
  equal(
    decodeInvokeResponse('\uFEFF${_envelope('\uFEFF3')}'),
    '3',
    'Outer and payload BOM boundaries',
  );
  equal(
    decodeInvokeResponse(_envelope('x\uFEFFy')),
    'x\uFEFFy',
    'Interior BOM is data',
  );
  final nested = jsonEncode({'value': '\uFEFFtext'});
  equal(
    decodeInvokeResponse(_envelope(nested)),
    nested,
    'Envelope does not decode nested payload',
  );
  equal(
    decodeMapResponse(
      decodeInvokeResponse(_envelope(nested)),
      'nested',
    )['value'],
    '\uFEFFtext',
    'Object decoder preserves value BOM',
  );
  for (final invalid in [
    'null',
    '[]',
    '7',
    'true',
    '"text"',
    '{',
    '{}',
    '{"error_message":""}',
    '{"response_data":""}',
    '{"error_message":null,"response_data":""}',
    '{"error_message":"","response_data":3}',
  ]) {
    await rejects<FormatException>(
      () => decodeInvokeResponse(invalid),
      'Reject malformed/non-string envelope $invalid',
    );
  }
  try {
    decodeInvokeResponse(
      _envelope('ignored', error: 'synthetic backend error'),
    );
    throw StateError('Backend error was swallowed');
  } on StateError catch (error) {
    equal(
      error.message,
      'synthetic backend error',
      'Backend error is propagated exactly',
    );
  }
  equal(
    decodeBackendInt(
      decodeInvokeResponse(_envelope('\uFEFF"3"')),
      fallback: -1,
    ),
    3,
    'Scalar parser consumes stripped boundary BOM',
  );
}

Future<void> _scalarCompatibility() async {
  const valid = <String, int>{
    '0': 0,
    '-9': -9,
    ' 42 ': 42,
    '+12': 12,
    '0x2a': 42,
    '"42"': 42,
    '" -9 "': -9,
    '"0x2a"': 42,
    '3.0': 3,
    '"3.0"': 3,
    '3e2': 300,
    '"3e2"': 300,
    '-0.0': 0,
    '9007199254740993': 9007199254740993,
    '"9007199254740993"': 9007199254740993,
    '"9223372036854775807"': 9223372036854775807,
    '"-9223372036854775808"': -9223372036854775808,
  };
  for (final entry in valid.entries) {
    equal(
      decodeBackendInt(entry.key, fallback: -999),
      entry.value,
      'Legacy scalar ${entry.key}',
    );
  }
  for (final invalid in [
    '',
    '  ',
    'garbage',
    'null',
    'true',
    'false',
    '{}',
    '[]',
    '""',
    '3.25',
    '"3.25"',
    '"NaN"',
    '"Infinity"',
    '1e999',
    '"\\"3\\""',
  ]) {
    equal(
      decodeBackendInt(invalid, fallback: -999),
      -999,
      'Explicit fallback for $invalid',
    );
  }
}

Future<void> main() async {
  final cases = <String, Future<void> Function()>{
    'TTL boundaries': _ttl,
    'Request deduplication and reentrancy': _deduplication,
    'Failure retry': _retryFailures,
    'Bounded least-recent eviction': _boundedEviction,
    'Clear and account/route completion races': _clearRaces,
    'Partial invalidation': _partialRemoval,
    'Stale fallback policy': _stalePolicy,
    'Invalidated stale account data': _invalidatedStalePolicy,
    'Envelope and BOM contract': _responseEnvelope,
    'Legacy integer scalar compatibility': _scalarCompatibility,
  };
  var failed = 0;
  for (final entry in cases.entries) {
    try {
      await entry.value().timeout(const Duration(seconds: 5));
      stdout.writeln('PASS ${entry.key}');
    } catch (error, stack) {
      failed++;
      stderr.writeln('FAIL ${entry.key}: $error\n$stack');
    }
  }
  stdout.writeln(
    '${cases.length - failed}/${cases.length} groups passed; $_assertions assertions.',
  );
  stdout.writeln(
    'Pure Dart contracts only; MethodChannel/native/UI integration is not exercised.',
  );
  if (failed > 0) exitCode = 1;
}

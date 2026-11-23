import 'dart:async';

import 'package:jmcomic3/basic/methods.dart';

/// Owns only temporary reader files. A new chapter/reader receives a distinct
/// token, so cleanup of a replaced route cannot delete the new reader's files.
class ReaderImageSession {
  ReaderImageSession() : cacheIdentity = _nextIdentity++;

  static int _nextIdentity = 0;
  final int cacheIdentity;
  Future<String>? _token;
  final Set<Future<void>> _pending = {};
  bool _closed = false;
  Future<void>? _closing;

  bool get closed => _closed;

  Future<String> get token => _token ??= _begin();

  Future<String> _begin() async {
    final result = await methods.beginReaderSession();
    if (result.trim().isEmpty) throw StateError('reader session unavailable');
    return result;
  }

  Future<T> run<T>(Future<T> Function() operation) {
    if (_closed) return Future.error(StateError('reader session closed'));
    final result = Future<T>.sync(operation);
    late final Future<void> settled;
    settled = result
        .then<void>((_) {}, onError: (Object _, StackTrace __) {})
        .whenComplete(() => _pending.remove(settled));
    _pending.add(settled);
    return result;
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    // Includes native requests and file reads/decoding, not just path lookup.
    await Future.wait(_pending.toList());
    final created = _token;
    if (created != null) await methods.endReaderSession(await created);
  }
}

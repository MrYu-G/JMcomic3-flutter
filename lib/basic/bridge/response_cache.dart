import 'dart:async';
import 'dart:collection';

/// Bounded, coalescing cache for serialized backend responses. Cached strings
/// are decoded for each caller so mutable entities are never shared across UI.
class ResponseCache {
  ResponseCache({
    required this.ttl,
    this.capacity = 500,
    DateTime Function()? now,
  }) : assert(capacity > 0),
       _now = now ?? DateTime.now;

  final Duration ttl;
  final int capacity;
  final DateTime Function() _now;
  final _entries = LinkedHashMap<String, _ResponseEntry>();
  final _pending = <String, Future<String>>{};

  Future<String> load(
    String key,
    Future<String> Function() loader, {
    bool allowStaleOnError = false,
  }) {
    final current = _entries[key];
    if (current != null && _now().difference(current.createdAt) <= ttl) {
      _entries.remove(key);
      _entries[key] = current;
      return Future.value(current.value);
    }
    final pending = _pending[key];
    if (pending != null) return pending;

    // Register before the loader runs, including synchronous/reentrant loaders.
    final result = Completer<String>();
    final future = result.future;
    _pending[key] = future;
    Future<String>.sync(loader).then(
      (value) {
        if (identical(_pending[key], future)) {
          _store(key, value);
          _pending.remove(key);
        }
        result.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        // Invalidation removes ownership. An old account/route request must not
        // republish stale data or clear a newer in-flight request after it settles.
        if (allowStaleOnError &&
            current != null &&
            identical(_pending[key], future)) {
          _store(key, current.value);
          _pending.remove(key);
          result.complete(current.value);
        } else {
          if (identical(_pending[key], future)) _pending.remove(key);
          result.completeError(error, stack);
        }
      },
    );
    return future;
  }

  void _store(String key, String value) {
    _entries.remove(key);
    _entries[key] = _ResponseEntry(value, _now());
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
  }

  void clear() {
    _entries.clear();
    _pending.clear();
  }

  void removeWhere(bool Function(String key) matches) {
    _entries.removeWhere((key, _) => matches(key));
    _pending.removeWhere((key, _) => matches(key));
  }
}

class _ResponseEntry {
  const _ResponseEntry(this.value, this.createdAt);
  final String value;
  final DateTime createdAt;
}

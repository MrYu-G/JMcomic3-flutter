import 'dart:async';
import 'dart:collection';

/// Bounds native image work even when several visible pages and preloads start
/// in one frame. Each operation retains its normal transport retry behavior.
class ReaderImageQueue {
  ReaderImageQueue({this.concurrency = 4}) : assert(concurrency > 0);

  final int concurrency;
  final Queue<void Function()> _waiting = Queue();
  int _active = 0;

  Future<T> run<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _waiting.add(() {
      _active++;
      Future<T>.sync(operation)
          .then(result.complete, onError: result.completeError)
          .whenComplete(() {
            _active--;
            _startWaiting();
          });
    });
    _startWaiting();
    return result.future;
  }

  void _startWaiting() {
    while (_active < concurrency && _waiting.isNotEmpty) {
      _waiting.removeFirst()();
    }
  }
}

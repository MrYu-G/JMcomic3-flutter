import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jmcomic3/basic/reader_image_queue.dart';
import 'package:jmcomic3/configs/reader_preload.dart';

void main() {
  test('preloads nearest pages in each selected direction and clips edges', () {
    List<int> pages(
      int page,
      int count,
      ReaderPreloadDirection direction, {
      bool paired = false,
    }) => readerPreloadPages(
      page: page,
      pageCount: 10,
      count: count,
      direction: direction,
      paired: paired,
    );
    expect(pages(4, 2, ReaderPreloadDirection.both), [5, 3, 6, 2]);
    expect(pages(4, 2, ReaderPreloadDirection.forward), [5, 6]);
    expect(pages(4, 2, ReaderPreloadDirection.backward), [3, 2]);
    expect(pages(0, 2, ReaderPreloadDirection.both), [1, 2]);
    expect(pages(9, 2, ReaderPreloadDirection.both), [8, 7]);
    expect(pages(4, 0, ReaderPreloadDirection.both), isEmpty);
    expect(pages(4, 2, ReaderPreloadDirection.both, paired: true), [
      6,
      3,
      7,
      2,
    ]);
    expect(pages(8, 6, ReaderPreloadDirection.forward, paired: true), isEmpty);
  });

  test(
    'reader image work stays at four and failure releases a waiting slot',
    () async {
      final queue = ReaderImageQueue();
      final gates = List.generate(9, (_) => Completer<int>());
      var running = 0;
      var peak = 0;
      final started = <int>[];
      final results = [
        for (var index = 0; index < gates.length; index++)
          queue
              .run(() async {
                started.add(index);
                running++;
                if (running > peak) peak = running;
                try {
                  return await gates[index].future;
                } finally {
                  running--;
                }
              })
              .then<Object>((value) => value, onError: (Object error) => error),
      ];
      expect(started, [0, 1, 2, 3]);
      gates[1].completeError(StateError('fixture'));
      await Future<void>.delayed(Duration.zero);
      expect(started, [0, 1, 2, 3, 4]);
      for (var index = 0; index < gates.length; index++) {
        if (index != 1) gates[index].complete(index);
      }
      final completed = await Future.wait(results);
      expect(peak, 4);
      expect(running, 0);
      expect(completed[1], isA<StateError>());
      expect(completed.last, 8);
    },
  );
}

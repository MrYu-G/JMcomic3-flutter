import 'dart:collection';

import 'package:flutter/foundation.dart';

class RuntimeLogEntry {
  final DateTime time;
  final String operation;
  final bool failed;
  final Duration duration;

  const RuntimeLogEntry({
    required this.time,
    required this.operation,
    required this.failed,
    required this.duration,
  });
}

final runtimeLogRevision = ValueNotifier<int>(0);
final ListQueue<RuntimeLogEntry> _runtimeLog = ListQueue();
const runtimeLogCapacity = 300;

List<RuntimeLogEntry> get runtimeLogEntries => List.unmodifiable(_runtimeLog);

/// Only operation identifiers and timing enter this log. Request/response data,
/// error text, paths, and account details deliberately never enter the buffer.
void recordRuntimeOperation(
  String operation, {
  required bool failed,
  required Duration duration,
}) {
  _runtimeLog.addFirst(
    RuntimeLogEntry(
      time: DateTime.now(),
      operation: RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,79}$').hasMatch(operation)
          ? operation
          : 'operation',
      failed: failed,
      duration: duration,
    ),
  );
  while (_runtimeLog.length > runtimeLogCapacity) {
    _runtimeLog.removeLast();
  }
  runtimeLogRevision.value++;
}

void clearRuntimeLog() {
  _runtimeLog.clear();
  runtimeLogRevision.value++;
}

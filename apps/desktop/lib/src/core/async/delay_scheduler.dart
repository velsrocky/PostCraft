import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A cancelable "run this after a delay" primitive.
///
/// Injected so autosave debouncing can be unit-tested deterministically
/// without `FakeAsync` interacting badly with real file I/O.
abstract interface class DelayScheduler {
  /// Cancels any pending callback, then schedules [callback] after [delay].
  void schedule(Duration delay, void Function() callback);

  void cancel();
}

class TimerScheduler implements DelayScheduler {
  Timer? _timer;

  @override
  void schedule(Duration delay, void Function() callback) {
    _timer?.cancel();
    _timer = Timer(delay, callback);
  }

  @override
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}

final delaySchedulerProvider = Provider<DelayScheduler>((ref) {
  final scheduler = TimerScheduler();
  ref.onDispose(scheduler.cancel);
  return scheduler;
});

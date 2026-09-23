import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postcraft/src/rust/api.dart' as native_api;
import 'package:postcraft/src/rust/lib.dart';

import '../../../core/feedback.dart';
import '../../capture/domain/capture_result.dart';
import '../application/capture_coordinator.dart';
import '../domain/global_shortcut.dart';

/// Thin wrapper over the generated FRB global-shortcut surface.
class GlobalShortcutService {
  const GlobalShortcutService();

  Future<bool> supported() => native_api.globalShortcutsSupported();

  Future<GlobalShortcutStatus> register() =>
      native_api.startGlobalShortcuts(bindings: defaultShortcutBindings());

  Future<String?> poll() => native_api.pollGlobalShortcut();

  Future<void> unregister() => native_api.stopGlobalShortcuts();
}

final globalShortcutServiceProvider = Provider<GlobalShortcutService>(
  (ref) => const GlobalShortcutService(),
);

final globalShortcutsSupportedProvider = FutureProvider<bool>(
  (ref) => ref.watch(globalShortcutServiceProvider).supported(),
);

enum ShortcutRegistration { idle, active, failed }

class GlobalShortcutsState {
  const GlobalShortcutsState({
    this.enabled = false,
    this.registration = ShortcutRegistration.idle,
    this.message,
  });

  final bool enabled;
  final ShortcutRegistration registration;
  final String? message;

  GlobalShortcutsState copyWith({
    bool? enabled,
    ShortcutRegistration? registration,
    String? message,
  }) => GlobalShortcutsState(
    enabled: enabled ?? this.enabled,
    registration: registration ?? this.registration,
    message: message ?? this.message,
  );
}

/// Registers portal global shortcuts and drains activation events.
///
/// Disabled by default so enabling never triggers an unexpected desktop
/// consent prompt. When enabled, a lightweight poll drains activations that
/// happened while the window was unfocused and routes them through the same
/// [CaptureCoordinator] as the in-app buttons.
class GlobalShortcutsController extends Notifier<GlobalShortcutsState> {
  static const pollInterval = Duration(milliseconds: 150);

  Timer? _timer;
  bool _busy = false;

  @override
  GlobalShortcutsState build() {
    ref.onDispose(_stopPolling);
    return const GlobalShortcutsState();
  }

  Future<void> setEnabled(bool enabled) async {
    if (!enabled) {
      _stopPolling();
      await ref.read(globalShortcutServiceProvider).unregister();
      state = state.copyWith(
        enabled: false,
        registration: ShortcutRegistration.idle,
      );
      return;
    }

    state = state.copyWith(enabled: true);
    try {
      final status = await ref.read(globalShortcutServiceProvider).register();
      if (status.supported) {
        state = state.copyWith(
          registration: ShortcutRegistration.active,
          message: status.message,
        );
        _startPolling();
      } else {
        state = state.copyWith(
          enabled: false,
          registration: ShortcutRegistration.failed,
          message: status.message,
        );
      }
    } on Object catch (error) {
      state = state.copyWith(
        enabled: false,
        registration: ShortcutRegistration.failed,
        message: '$error',
      );
    }
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(pollInterval, (_) => drainOnce());
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  /// Drains every queued activation exactly once. Also used by the poll timer
  /// and by tests to drive dispatch deterministically.
  Future<void> drainOnce() async {
    if (_busy) return;
    _busy = true;
    try {
      while (true) {
        final id = await ref.read(globalShortcutServiceProvider).poll();
        if (id == null) return;
        await _dispatch(id);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _dispatch(String id) async {
    switch (id) {
      case ShortcutIds.region:
        await ref.read(captureCoordinatorProvider).run(CaptureMode.region);
      case ShortcutIds.screen:
        await ref.read(captureCoordinatorProvider).run(CaptureMode.screen);
      default:
        ref.read(feedbackProvider.notifier).notify('Unknown shortcut: $id');
    }
  }
}

final globalShortcutsControllerProvider =
    NotifierProvider<GlobalShortcutsController, GlobalShortcutsState>(
      GlobalShortcutsController.new,
    );

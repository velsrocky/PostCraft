import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postcraft/src/features/capture/application/capture_coordinator.dart';
import 'package:postcraft/src/features/capture/application/global_shortcuts_controller.dart';
import 'package:postcraft/src/features/capture/domain/capture_result.dart';
import 'package:postcraft/src/features/capture/domain/global_shortcut.dart';
import 'package:postcraft/src/rust/lib.dart';

void main() {
  test(
    'enable registers, drains activations, and disable unregisters',
    () async {
      final service = _FakeShortcutService(supportedValue: true)
        ..queue = [ShortcutIds.region];
      final runner = _FakeRunner();
      final container = ProviderContainer(
        overrides: [
          globalShortcutServiceProvider.overrideWithValue(service),
          captureCoordinatorProvider.overrideWithValue(runner),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(
        globalShortcutsControllerProvider.notifier,
      );
      await controller.setEnabled(true);

      expect(service.registerCalls, 1);
      expect(container.read(globalShortcutsControllerProvider).enabled, isTrue);
      expect(
        container.read(globalShortcutsControllerProvider).registration,
        ShortcutRegistration.active,
      );

      await controller.drainOnce();
      expect(runner.modes, [CaptureMode.region]);

      await controller.setEnabled(false);
      expect(service.unregisterCalls, 1);
      expect(
        container.read(globalShortcutsControllerProvider).enabled,
        isFalse,
      );
    },
  );

  test('enable is refused when the portal is unsupported', () async {
    final service = _FakeShortcutService(supportedValue: false);
    final container = ProviderContainer(
      overrides: [globalShortcutServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    await container
        .read(globalShortcutsControllerProvider.notifier)
        .setEnabled(true);

    expect(container.read(globalShortcutsControllerProvider).enabled, isFalse);
    expect(
      container.read(globalShortcutsControllerProvider).registration,
      ShortcutRegistration.failed,
    );
  });

  test('activation ids map to the correct capture modes', () async {
    final service = _FakeShortcutService(supportedValue: true)
      ..queue = [ShortcutIds.screen];
    final runner = _FakeRunner();
    final container = ProviderContainer(
      overrides: [
        globalShortcutServiceProvider.overrideWithValue(service),
        captureCoordinatorProvider.overrideWithValue(runner),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(
      globalShortcutsControllerProvider.notifier,
    );
    await controller.setEnabled(true);
    await controller.drainOnce();

    expect(runner.modes, [CaptureMode.screen]);
  });
}

class _FakeShortcutService extends GlobalShortcutService {
  _FakeShortcutService({required this.supportedValue});
  final bool supportedValue;
  List<String> queue = [];
  int registerCalls = 0;
  int unregisterCalls = 0;

  @override
  Future<GlobalShortcutStatus> register() async {
    registerCalls++;
    return GlobalShortcutStatus(
      supported: supportedValue,
      requestedIds: const [],
      message: supportedValue ? 'registered' : 'unsupported',
    );
  }

  @override
  Future<String?> poll() async => queue.isEmpty ? null : queue.removeAt(0);

  @override
  Future<void> unregister() async => unregisterCalls++;
}

class _FakeRunner implements CaptureRunner {
  final List<CaptureMode> modes = [];
  @override
  Future<void> run(CaptureMode mode) async => modes.add(mode);
}

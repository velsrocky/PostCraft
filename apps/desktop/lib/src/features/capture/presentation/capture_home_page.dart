import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_selector/file_selector.dart';

import '../../../app/theme.dart';
import '../../editor/application/editor_controller.dart';
import '../../projects/application/projects_providers.dart';
import '../application/capture_providers.dart';
import '../domain/capture_result.dart';

class CaptureHomePage extends ConsumerWidget {
  const CaptureHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final capabilities = ref.watch(captureCapabilitiesProvider);
    final enabled =
        capabilities.hasValue && capabilities.requireValue.desktopCapture;
    return CallbackShortcuts(
      bindings: {
        SingleActivator(LogicalKeyboardKey.keyA, control: true, shift: true):
            enabled ? () => _capture(context, ref, CaptureMode.region) : () {},
        SingleActivator(LogicalKeyboardKey.keyF, control: true, shift: true):
            enabled ? () => _capture(context, ref, CaptureMode.screen) : () {},
      },
      child: Focus(
        autofocus: true,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Capture something great',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Take a screenshot, mark it up, and share a polished result.',
                    style: TextStyle(color: PostCraftTheme.muted, fontSize: 14),
                  ),
                  const SizedBox(height: 28),
                  Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      _CaptureAction(
                        icon: Icons.crop_free_rounded,
                        title: 'Select region',
                        subtitle: 'Choose any area of your screen',
                        shortcut: 'Ctrl + Shift + A',
                        enabled: enabled,
                        onPressed: () =>
                            _capture(context, ref, CaptureMode.region),
                      ),
                      _CaptureAction(
                        icon: Icons.screenshot_monitor_outlined,
                        title: 'Capture screen',
                        subtitle: 'Take a screenshot of the display',
                        shortcut: 'Ctrl + Shift + F',
                        enabled: enabled,
                        onPressed: () =>
                            _capture(context, ref, CaptureMode.screen),
                      ),
                      if (_hasDisplayTargets(ref))
                        _CaptureAction(
                          icon: Icons.desktop_windows_outlined,
                          title: 'Capture display',
                          subtitle: 'Pick a connected monitor',
                          enabled: enabled,
                          onPressed: () =>
                              _captureDisplay(context, ref),
                        ),
                      _CaptureAction(
                        icon: Icons.image_outlined,
                        title: 'Open an image',
                        subtitle: 'Import a PNG, JPEG, or WebP',
                        onPressed: () => _importImage(context, ref),
                      ),
                    ],
                  ),
                  if (_hasDisplayTargets(ref)) ...[
                    const SizedBox(height: 14),
                    _CapabilityNote(
                      icon: Icons.info_outline_rounded,
                      message: _displaySummary(ref),
                    ),
                  ],
                  const SizedBox(height: 20),
                  capabilities.when(
                    data: (value) => value.desktopCapture
                        ? const _CapabilityNote(
                            icon: Icons.verified_user_outlined,
                            message:
                                'Capture opens the desktop’s secure screenshot chooser.',
                          )
                        : const _CapabilityNote(
                            icon: Icons.info_outline_rounded,
                            message:
                                'The XDG Screenshot portal is unavailable in this session. Image import and editing are still available.',
                          ),
                    error: (_, _) => const _CapabilityNote(
                      icon: Icons.warning_amber_rounded,
                      message:
                          'Could not check screenshot support. Retry from the editor toolbar.',
                    ),
                    loading: () => const _CapabilityNote(
                      icon: Icons.hourglass_empty_rounded,
                      message: 'Checking desktop screenshot support…',
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextButton.icon(
                    onPressed: () => context.go('/editor'),
                    icon: const Icon(Icons.edit_outlined, size: 17),
                    label: const Text('Open editor'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Map<String, Object?>> _displayTargets(WidgetRef ref) {
    final report = ref.watch(captureTargetReportProvider);
    return report.when(
      data: (value) => value.targets
          .where((target) => target['kind'] == 'display')
          .toList(),
      error: (_, _) => const [],
      loading: () => const [],
    );
  }

  bool _hasDisplayTargets(WidgetRef ref) => _displayTargets(ref).isNotEmpty;

  String _displaySummary(WidgetRef ref) {
    final targets = _displayTargets(ref);
    if (targets.length <= 1) return 'Connected display ready for targeted capture.';
    final names = targets
        .map((target) => '${target['name'] ?? target['id'] ?? 'Display'}')
        .join(', ');
    return 'Displays: $names';
  }

  Future<void> _captureDisplay(BuildContext context, WidgetRef ref) async {
    final targets = _displayTargets(ref);
    if (targets.isEmpty) return;
    if (targets.length == 1) {
      final targetId = targets.first['id']?.toString();
      await _capture(context, ref, CaptureMode.display, targetId: targetId);
      return;
    }
    final selected = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Capture display'),
        children: [
          for (final target in targets)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(target),
              child: Text(
                '${target['name'] ?? target['id'] ?? 'Display'}'
                '${target['width'] != null && target['height'] != null ? ' · ${target['width']}×${target['height']}' : ''}',
              ),
            ),
        ],
      ),
    );
    if (selected == null || !context.mounted) return;
    await _capture(
      context,
      ref,
      CaptureMode.display,
      targetId: selected['id']?.toString(),
    );
  }

  Future<void> _capture(
    BuildContext context,
    WidgetRef ref,
    CaptureMode mode, {
    String? targetId,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref
          .read(linuxCaptureServiceProvider)
          .capture(mode, targetId: targetId);
      final image = await _decodeImage(result.bytes);
      ref
          .read(editorControllerProvider.notifier)
          .openImage(result.bytes, image.width, image.height);
      image.dispose();
      final document = ref.read(editorControllerProvider).document;
      await ref
          .read(workspaceControllerProvider.notifier)
          .startProject(document, name: _captureLabel(mode, targetId));
      if (context.mounted) {
        context.go('/editor');
        messenger.showSnackBar(
          SnackBar(content: Text('${_captureLabel(mode, targetId)} captured')),
        );
      }
    } on Object catch (error) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Capture failed: $error')),
        );
      }
    }
  }

  String _captureLabel(CaptureMode mode, String? targetId) => switch (mode) {
    CaptureMode.region => 'Region capture',
    CaptureMode.screen => 'Screen capture',
    CaptureMode.display =>
      targetId == null ? 'Display capture' : 'Display $targetId capture',
  };

  Future<void> _importImage(BuildContext context, WidgetRef ref) async {
    final result = await openImageFile();
    if (result == null) return;
    final image = await _decodeImage(result);
    ref
        .read(editorControllerProvider.notifier)
        .openImage(result, image.width, image.height);
    image.dispose();
    final document = ref.read(editorControllerProvider).document;
    await ref
        .read(workspaceControllerProvider.notifier)
        .startProject(document, name: 'Imported image');
    if (context.mounted) context.go('/editor');
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(Uint8List.fromList(bytes), completer.complete);
    return completer.future;
  }
}

class _CaptureAction extends StatelessWidget {
  const _CaptureAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
    this.shortcut,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? shortcut;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 232,
    child: Opacity(
      opacity: enabled ? 1 : .48,
      child: Material(
        color: PostCraftTheme.panel,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 164,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: .07)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: 21,
                  color: enabled ? PostCraftTheme.accent : PostCraftTheme.muted,
                ),
                const Spacer(),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: PostCraftTheme.muted,
                    fontSize: 11,
                  ),
                ),
                if (shortcut != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    shortcut!,
                    style: const TextStyle(
                      color: PostCraftTheme.muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _CapabilityNote extends StatelessWidget {
  const _CapabilityNote({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: PostCraftTheme.muted),
      const SizedBox(width: 9),
      Expanded(
        child: Text(
          message,
          style: const TextStyle(color: PostCraftTheme.muted, fontSize: 11),
        ),
      ),
    ],
  );
}

Future<Uint8List?> openImageFile() async {
  final file = await openFile(
    acceptedTypeGroups: [
      const XTypeGroup(
        label: 'Images',
        extensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp'],
      ),
    ],
  );
  if (file == null) return null;
  return Uint8List.fromList(await file.readAsBytes());
}

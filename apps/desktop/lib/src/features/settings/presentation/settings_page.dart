import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../capture/application/capture_providers.dart';
import '../../capture/application/global_shortcuts_controller.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shortcuts = ref.watch(globalShortcutsControllerProvider);
    final supported = ref.watch(globalShortcutsSupportedProvider);
    final capture = ref.watch(captureCapabilitiesProvider);
    final desktopCapture =
        capture.hasValue && capture.requireValue.desktopCapture;
    final recording = ref.watch(recordingCapabilitiesProvider);
    final screencast = ref.watch(waylandScreencastPreparationProvider);
    final pipewire = ref.watch(pipewireTransportProvider);

    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const Text(
          'Preferences',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 22),
        ),
        const SizedBox(height: 24),
        const _Section('Capture'),
        _SettingTile(
          title: 'Region capture',
          subtitle: desktopCapture
              ? 'Available in this desktop session'
              : 'Requires the XDG Screenshot portal',
          trailing: _CapabilityChip(available: desktopCapture),
        ),
        _SettingTile(
          title: 'Wayland ScreenCast portal',
          subtitle: screencast.when(
            loading: () => 'Checking portal session support…',
            error: (error, _) => 'Could not query ScreenCast support.',
            data: (state) => state['reason'] as String? ?? 'No status available.',
          ),
          trailing: screencast.when(
            loading: () => const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            error: (_, _) => const _CapabilityChip(available: false),
            data: (state) => _CapabilityChip(available: state['supported'] == true),
          ),
        ),
        _SettingTile(
          title: 'PipeWire transport',
          subtitle: pipewire.when(
            loading: () => 'Checking PipeWire…',
            error: (error, _) => 'Could not inspect PipeWire.',
            data: (state) => state['reason'] as String? ?? 'No status available.',
          ),
          trailing: pipewire.when(
            loading: () => const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            error: (_, _) => const _CapabilityChip(available: false),
            data: (state) => _CapabilityChip(available: state['connected'] == true),
          ),
        ),
        _SettingTile(
          title: 'Global shortcuts',
          subtitle:
              'Capture with Ctrl+Shift+A / F while PostCraft is unfocused',
          trailing: supported.when(
            loading: () => const Text(
              'Checking…',
              style: TextStyle(color: PostCraftTheme.muted, fontSize: 12),
            ),
            error: (error, _) => const _CapabilityChip(available: false),
            data: (ok) => Switch(
              value: shortcuts.enabled,
              onChanged: ok
                  ? (value) => ref
                        .read(globalShortcutsControllerProvider.notifier)
                        .setEnabled(value)
                  : null,
            ),
          ),
        ),
        if (supported.value == false)
          const _Hint(
            'The desktop did not advertise global-shortcut support, so they '
            'cannot be enabled in this session.',
          ),
        if (shortcuts.enabled && shortcuts.message != null)
          _Hint(
            shortcuts.registration == ShortcutRegistration.active
                ? 'Active · ${shortcuts.message}'
                : 'Could not register · ${shortcuts.message}',
          ),
        if (shortcuts.enabled)
          const _Hint(
            'If the desktop shows an approval prompt, confirm it to allow the '
            'shortcuts.',
          ),
        const SizedBox(height: 16),
        const _Section('Editor'),
        const _SettingTile(
          title: 'Autosave',
          subtitle: 'Recoverable drafts are saved automatically while editing',
          trailing: Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF63D6A2),
            size: 18,
          ),
        ),
        _SettingTile(
          title: 'Screen recording',
          subtitle: recording.when(
            loading: () => 'Checking recording backend…',
            error: (error, _) => 'Could not inspect recording backend.',
            data: (capabilities) => capabilities.reason,
          ),
          trailing: recording.when(
            loading: () => const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            error: (_, _) => const _CapabilityChip(available: false),
            data: (capabilities) => _CapabilityChip(available: capabilities.supported),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: PostCraftTheme.muted,
        fontSize: 11,
        letterSpacing: 1.1,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _CapabilityChip extends StatelessWidget {
  const _CapabilityChip({required this.available});
  final bool available;
  @override
  Widget build(BuildContext context) => Text(
    available ? 'Ready' : 'Unavailable',
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: available ? const Color(0xFF63D6A2) : PostCraftTheme.muted,
    ),
  );
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
    child: Text(
      text,
      style: const TextStyle(
        color: PostCraftTheme.muted,
        fontSize: 11,
        height: 1.4,
      ),
    ),
  );
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });
  final String title;
  final String subtitle;
  final Widget trailing;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 1),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    decoration: BoxDecoration(
      color: PostCraftTheme.panel,
      border: Border(
        bottom: BorderSide(color: Colors.white.withValues(alpha: .05)),
      ),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: PostCraftTheme.muted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        trailing,
      ],
    ),
  );
}

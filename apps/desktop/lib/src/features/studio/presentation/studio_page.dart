import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../library/application/library_providers.dart';
import '../../library/domain/asset.dart';
import '../application/studio_controller.dart';
import '../domain/timeline.dart';

class StudioPage extends ConsumerWidget {
  const StudioPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assets = ref.watch(assetsProvider);
    final timeline = ref.watch(studioControllerProvider);
    final controller = ref.read(studioControllerProvider.notifier);
    final rendering = ref.watch(studioRenderingProvider);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Media studio', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('Build a local timeline from imported media, then render it with FFmpeg.', style: TextStyle(color: PostCraftTheme.muted)),
          const SizedBox(height: 20),
          Row(
            children: [
              FilledButton.icon(
                onPressed: rendering || timeline.isEmpty
                    ? null
                    : () async {
                        try {
                          await controller.render();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Timeline rendered and added to the library.')),
                            );
                          }
                        } on Object catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Render failed: $error')));
                          }
                        }
                      },
                icon: rendering
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.movie_creation_outlined),
                label: Text(rendering ? 'Rendering…' : 'Render MP4'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 280, child: _AssetPicker(assets: assets, onAdd: controller.addClip)),
                const SizedBox(width: 16),
                Expanded(
                  child: _TimelinePanel(
                    timeline: timeline,
                    onRemove: controller.removeClip,
                    onTrim: controller.trimClip,
                    onSplit: controller.splitClip,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AssetPicker extends StatelessWidget {
  const _AssetPicker({required this.assets, required this.onAdd});
  final AsyncValue<List<Asset>> assets;
  final Future<void> Function({required String assetId, TimelineClipKind kind}) onAdd;

  @override
  Widget build(BuildContext context) => Card(
    child: assets.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Padding(padding: const EdgeInsets.all(16), child: Text('Library unavailable: $error')),
      data: (items) => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Text('Assets', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final asset in items)
            ListTile(
              dense: true,
              title: Text(asset.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(asset.kind.name),
              trailing: IconButton(
                tooltip: 'Add to timeline',
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () async {
                  await onAdd(assetId: asset.id, kind: switch (asset.kind) {
                    AssetKind.video => TimelineClipKind.video,
                    AssetKind.audio => TimelineClipKind.audio,
                    _ => TimelineClipKind.image,
                  });
                },
              ),
            ),
        ],
      ),
    ),
  );
}

class _TimelinePanel extends StatelessWidget {
  const _TimelinePanel({
    required this.timeline,
    required this.onRemove,
    required this.onTrim,
    required this.onSplit,
  });
  final Timeline timeline;
  final void Function(String id) onRemove;
  final void Function(String id, {required int sourceInUs, required int sourceOutUs})
      onTrim;
  final void Function(String id, int atUs) onSplit;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: timeline.isEmpty
          ? const Center(child: Text('Add an asset to start a timeline.', style: TextStyle(color: PostCraftTheme.muted)))
          : ListView(
              children: [
                Text('Timeline · ${_seconds(timeline.durationUs)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 14),
                for (final track in timeline.tracks)
                  for (final clip in track.clips)
                    ListTile(
                      tileColor: PostCraftTheme.panel,
                      title: Text('${clip.kind.name} · ${clip.assetId}'),
                      subtitle: Text(
                        '${_seconds(clip.startUs)} → ${_seconds(clip.endUs)} · source ${_seconds(clip.sourceInUs)}–${_seconds(clip.sourceOutUs)}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Trim clip',
                            icon: const Icon(Icons.content_cut_rounded, size: 18),
                            onPressed: () => _showTrimDialog(context, clip),
                          ),
                          IconButton(
                            tooltip: 'Split at position',
                            icon: const Icon(Icons.call_split_rounded, size: 18),
                            onPressed: () => _showSplitDialog(context, clip),
                          ),
                          IconButton(
                            tooltip: 'Delete clip',
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => onRemove(clip.id),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
    ),
  );

  Future<void> _showTrimDialog(BuildContext context, TimelineClip clip) async {
    final inController = TextEditingController(
      text: (clip.sourceInUs / 1000000).toStringAsFixed(3),
    );
    final outController = TextEditingController(
      text: (clip.sourceOutUs / 1000000).toStringAsFixed(3),
    );
    final formKey = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Trim clip'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: inController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Source in (seconds)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  final parsed = double.tryParse(value ?? '');
                  if (parsed == null || parsed < 0) return 'Enter a number ≥ 0';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: outController,
                decoration: const InputDecoration(labelText: 'Source out (seconds)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  final parsed = double.tryParse(value ?? '');
                  final inValue = double.tryParse(inController.text) ?? 0;
                  if (parsed == null || parsed <= inValue) {
                    return 'Must be greater than source in';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(dialogContext).pop(true);
              }
            },
            child: const Text('Trim'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final sourceInUs = ((double.parse(inController.text)) * 1000000).round();
      final sourceOutUs = ((double.parse(outController.text)) * 1000000).round();
      try {
        onTrim(clip.id, sourceInUs: sourceInUs, sourceOutUs: sourceOutUs);
      } on Object catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Trim failed: $error')),
          );
        }
      }
    }
    inController.dispose();
    outController.dispose();
  }

  Future<void> _showSplitDialog(BuildContext context, TimelineClip clip) async {
    final midpoint = (clip.sourceInUs + clip.sourceOutUs) / 2000000;
    final controller = TextEditingController(text: midpoint.toStringAsFixed(3));
    final formKey = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Split clip'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Split at (seconds, source-relative)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (value) {
              final parsed = double.tryParse(value ?? '');
              if (parsed == null) return 'Enter a number';
              final atUs = (parsed * 1000000).round();
              if (atUs <= clip.sourceInUs || atUs >= clip.sourceOutUs) {
                return 'Must be between ${_seconds(clip.sourceInUs)} and ${_seconds(clip.sourceOutUs)}';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(dialogContext).pop(true);
              }
            },
            child: const Text('Split'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final atUs = ((double.parse(controller.text)) * 1000000).round();
      try {
        onSplit(clip.id, atUs);
      } on Object catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Split failed: $error')),
          );
        }
      }
    }
    controller.dispose();
  }
}

String _seconds(int micros) => '${(micros / 1000000).toStringAsFixed(1)}s';

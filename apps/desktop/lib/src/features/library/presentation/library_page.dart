import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_selector/file_selector.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../editor/application/editor_controller.dart';
import '../../projects/application/projects_providers.dart';
import '../application/library_providers.dart';
import '../data/media_preview_service.dart';
import '../domain/asset.dart';

class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(libraryQueryProvider);
    final assets = ref.watch(assetsProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Media library',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
              ),
              FilledButton.icon(
                onPressed: () => _import(context, ref),
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: const Text('Import'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _FilterBar(initial: query),
          const SizedBox(height: 16),
          Expanded(
            child: assets.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('$error')),
              data: (items) {
                if (items.isEmpty) {
                  return Center(
                    child: Text(
                      query.isFiltered
                          ? 'No media matches your filters.'
                          : 'No media yet. Capture a screenshot or import a file.',
                      style: const TextStyle(color: PostCraftTheme.muted),
                    ),
                  );
                }
                return GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 240,
                    childAspectRatio: 0.8,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) =>
                      _AssetCard(asset: items[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Media',
          extensions: [
            'png',
            'jpg',
            'jpeg',
            'webp',
            'gif',
            'bmp',
            'mp4',
            'mov',
            'webm',
            'mp3',
            'wav',
            'm4a',
          ],
        ),
      ],
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    await ref
        .read(assetIngestorProvider)
        .add(bytes: bytes, fileName: file.name, name: file.name);
    messenger.showSnackBar(const SnackBar(content: Text('Added to library')));
  }
}

class _FilterBar extends ConsumerStatefulWidget {
  const _FilterBar({required this.initial});
  final LibraryQuery initial;

  @override
  ConsumerState<_FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends ConsumerState<_FilterBar> {
  late final TextEditingController _search = TextEditingController(
    text: widget.initial.search,
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(libraryQueryProvider);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 260,
          child: TextField(
            controller: _search,
            onChanged: (value) =>
                ref.read(libraryQueryProvider.notifier).setSearch(value),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search name or tag…',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              suffixIcon: query.search.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 16),
                      onPressed: () {
                        _search.clear();
                        ref.read(libraryQueryProvider.notifier).setSearch('');
                      },
                    ),
              filled: true,
              fillColor: PostCraftTheme.panel,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        for (final kind in AssetKind.values)
          ChoiceChip(
            label: Text(_kindLabel(kind)),
            selected: query.kind == kind,
            onSelected: (selected) => ref
                .read(libraryQueryProvider.notifier)
                .setKind(selected ? kind : null),
          ),
      ],
    );
  }
}

class _AssetCard extends ConsumerWidget {
  const _AssetCard({required this.asset});
  final Asset asset;

  static const _previewService = MediaPreviewService();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: PostCraftTheme.panel,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: asset.kind == AssetKind.image ? () => _open(context, ref) : null,
        onLongPress: () => _showActions(context, ref),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: FutureBuilder<String?>(
                future: ref
                    .read(assetRepositoryProvider.future)
                    .then((repo) => repo.filePath(asset.id)),
                builder: (context, snapshot) {
                  final path = snapshot.data;
                  if (path == null) {
                    return const _KindPlaceholder();
                  }
                  if (asset.kind == AssetKind.image) {
                    return Image.file(
                      File(path),
                      fit: BoxFit.cover,
                      cacheWidth: 480,
                      gaplessPlayback: true,
                      errorBuilder: (context, error, stackTrace) =>
                          const _KindPlaceholder(),
                    );
                  }
                  return FutureBuilder<MediaPreview?>(
                    future: _previewService.preview(asset, path),
                    builder: (context, snapshot) {
                      final preview = snapshot.data;
                      if (preview == null ||
                          snapshot.connectionState != ConnectionState.done) {
                        return _KindIcon(asset: asset);
                      }
                      return Image.memory(
                        preview.bytes,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      );
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      asset.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _showActions(context, ref),
                    icon: const Icon(Icons.more_horiz_rounded, size: 18),
                  ),
                ],
              ),
            ),
            if (asset.tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final tag in asset.tags)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: PostCraftTheme.accent.withValues(alpha: .16),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(tag, style: const TextStyle(fontSize: 9)),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final repo = await ref.read(assetRepositoryProvider.future);
    final path = await repo.filePath(asset.id);
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    final image = await _decode(bytes);
    ref
        .read(editorControllerProvider.notifier)
        .openImage(bytes, image.width, image.height);
    image.dispose();
    final document = ref.read(editorControllerProvider).document;
    await ref
        .read(workspaceControllerProvider.notifier)
        .startProject(document, name: asset.name);
    if (context.mounted) context.go('/editor');
  }

  void _showActions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.sell_outlined),
              title: const Text('Edit tags'),
              onTap: () {
                Navigator.pop(sheetContext);
                _editTags(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Remove from library'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final repo = await ref.read(assetRepositoryProvider.future);
                await repo.remove(asset.id);
                ref.invalidate(assetsProvider);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editTags(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: asset.tags.join(', '));
    final result = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tags'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'comma, separated, tags'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              controller.text
                  .split(',')
                  .map((t) => t.trim())
                  .where((t) => t.isNotEmpty)
                  .toList(),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result != null) {
      final repo = await ref.read(assetRepositoryProvider.future);
      await repo.setTags(asset.id, result);
      ref.invalidate(assetsProvider);
    }
  }
}

class _KindPlaceholder extends StatelessWidget {
  const _KindPlaceholder();
  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: PostCraftTheme.elevated,
    child: Center(
      child: Icon(Icons.broken_image_outlined, color: PostCraftTheme.muted),
    ),
  );
}

class _KindIcon extends StatelessWidget {
  const _KindIcon({required this.asset});
  final Asset asset;

  @override
  Widget build(BuildContext context) {
    final icon = switch (asset.kind) {
      AssetKind.video => Icons.videocam_outlined,
      AssetKind.audio => Icons.audio_file_outlined,
      AssetKind.other => Icons.insert_drive_file_outlined,
      AssetKind.image => Icons.image_outlined,
    };
    return ColoredBox(
      color: PostCraftTheme.elevated,
      child: Center(
        child: Icon(icon, color: PostCraftTheme.muted, size: 32),
      ),
    );
  }
}

String _kindLabel(AssetKind kind) => switch (kind) {
  AssetKind.image => 'Images',
  AssetKind.video => 'Video',
  AssetKind.audio => 'Audio',
  AssetKind.other => 'Other',
};

Future<ui.Image> _decode(List<int> bytes) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromList(Uint8List.fromList(bytes), completer.complete);
  return completer.future;
}

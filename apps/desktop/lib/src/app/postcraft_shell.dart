import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/feedback.dart';
import '../features/editor/application/editor_controller.dart';
import '../features/export/document_renderer.dart';
import '../features/projects/application/projects_providers.dart';
import '../features/share/application/share_providers.dart';
import '../features/share/domain/share_provider.dart';
import 'theme.dart';

class PostCraftShell extends ConsumerWidget {
  const PostCraftShell({
    required this.location,
    required this.child,
    super.key,
  });

  final String location;
  final Widget child;

  static const _items = [
    _NavigationItem('Capture', Icons.add_a_photo_outlined, '/workspace'),
    _NavigationItem('Projects', Icons.grid_view_rounded, '/projects'),
    _NavigationItem('Library', Icons.photo_library_outlined, '/library'),
    _NavigationItem('Studio', Icons.movie_creation_outlined, '/studio'),
    _NavigationItem(
      'Templates',
      Icons.dashboard_customize_outlined,
      '/templates',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Surface transient messages (e.g. from a background global capture).
    ref.listen(feedbackProvider, (_, next) {
      if (next == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(next.$1)));
    });

    final workspace = ref.watch(workspaceControllerProvider);
    final canExport =
        (location == '/workspace' || location == '/editor') &&
        workspace.hasProject;

    return Scaffold(
      body: Row(
        children: [
          _Sidebar(location: location),
          Expanded(
            child: Column(
              children: [
                _TitleBar(
                  location: location,
                  canExport: canExport,
                  onExport: canExport
                      ? () => _openShareSheet(context, ref)
                      : null,
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openShareSheet(BuildContext context, WidgetRef ref) async {
    final document = ref.read(editorControllerProvider).document;
    final workspace = ref.read(workspaceControllerProvider);
    final messenger = ScaffoldMessenger.of(context);
    Uint8List? png;
    try {
      png = await const DocumentRenderer().renderPng(document);
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $error')));
      return;
    }
    if (!context.mounted) return;
    final payload = SharePayload(
      pngBytes: png,
      filePath: workspace.current?.bundlePath,
      title: workspace.current?.name ?? 'PostCraft',
    );
    final destinations = ref.read(shareDestinationsProvider);
    final selected = await showModalBottomSheet<ShareDestination>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text(
                'Share & export',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
            for (final destination in destinations)
              ListTile(
                leading: Icon(destination.icon, size: 20),
                title: Text(destination.label),
                onTap: () => Navigator.of(sheetContext).pop(destination),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected == null || !context.mounted) return;
    await runShare(context, selected, payload);
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.location});
  final String location;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 218,
      decoration: BoxDecoration(
        color: PostCraftTheme.panel,
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: .06)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 21, 16, 24),
            child: Row(
              children: [
                _BrandMark(),
                SizedBox(width: 11),
                Flexible(
                  child: Text(
                    'PostCraft',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          for (final item in PostCraftShell._items)
            _NavButton(item: item, selected: location == item.route),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
            child: _NavButton(
              item: const _NavigationItem(
                'Settings',
                Icons.settings_outlined,
                '/settings',
              ),
              selected: location == '/settings',
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 0, 18, 18),
            child: Text(
              'LOCAL WORKSPACE',
              style: TextStyle(
                color: PostCraftTheme.muted,
                fontSize: 10,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) => Container(
    width: 30,
    height: 30,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(9),
      gradient: const LinearGradient(
        colors: [Color(0xFFB7A9FF), Color(0xFF6D5CE7)],
      ),
      boxShadow: [
        BoxShadow(
          color: PostCraftTheme.accent.withValues(alpha: .28),
          blurRadius: 14,
        ),
      ],
    ),
    child: const Icon(
      Icons.auto_awesome_rounded,
      color: Colors.white,
      size: 17,
    ),
  );
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.selected});
  final _NavigationItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFFE4DEFF) : PostCraftTheme.muted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: selected
            ? PostCraftTheme.accent.withValues(alpha: .14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: () => context.go(item.route),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(item.icon, size: 18, color: color),
                const SizedBox(width: 12),
                Text(
                  item.label,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({
    required this.location,
    required this.canExport,
    required this.onExport,
  });
  final String location;
  final bool canExport;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final titles = {
      '/workspace': 'Capture & edit',
      '/editor': 'Untitled project',
      '/projects': 'Projects',
      '/library': 'Asset library',
      '/studio': 'Media studio',
      '/templates': 'Templates',
      '/settings': 'Settings',
    };
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: .06)),
        ),
      ),
      child: Row(
        children: [
          Text(
            titles[location] ?? 'PostCraft',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Search',
            onPressed: () {},
            icon: const Icon(Icons.search_rounded, size: 19),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onExport,
            icon: const Icon(Icons.ios_share_rounded, size: 16),
            label: const Text('Export'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavigationItem {
  const _NavigationItem(this.label, this.icon, this.route);
  final String label;
  final IconData icon;
  final String route;
}

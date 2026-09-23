import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme.dart';
import '../../editor/application/editor_controller.dart';
import '../application/projects_providers.dart';
import '../domain/project.dart';

class ProjectsPage extends ConsumerWidget {
  const ProjectsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projects = ref.watch(projectsProvider);
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Projects',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: projects.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _EmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Could not load projects',
                subtitle: '$error',
                actionLabel: 'Retry',
                onAction: () => ref.invalidate(projectsProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return _EmptyState(
                    icon: Icons.folder_open_rounded,
                    title: 'Your projects will appear here',
                    subtitle:
                        'Capture a screenshot or import an image to start a project. '
                        'Everything stays on this device.',
                    actionLabel: 'New capture',
                    onAction: () => context.go('/workspace'),
                  );
                }
                final recoverable = items
                    .where((p) => p.hasUnsavedDraft)
                    .length;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (recoverable > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _RecoveryBanner(count: recoverable),
                      ),
                    Expanded(
                      child: GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 260,
                              childAspectRatio: 0.82,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                            ),
                        itemCount: items.length,
                        itemBuilder: (context, index) => _ProjectCard(
                          project: items[index],
                          onOpen: () => _open(ref, items[index], draft: false),
                          onResumeDraft: items[index].hasUnsavedDraft
                              ? () => _open(ref, items[index], draft: true)
                              : null,
                          onDelete: () =>
                              _confirmDelete(context, ref, items[index]),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _open(
    WidgetRef ref,
    Project project, {
    required bool draft,
  }) async {
    final repository = await ref.read(projectRepositoryProvider.future);
    final document = await repository.load(project.id, draft: draft);
    ref.read(editorControllerProvider.notifier).replaceDocument(document);
    ref.read(workspaceControllerProvider.notifier).bindExisting(project);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Project project,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete project?'),
        content: Text(
          '“${project.name}” will be permanently removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(projectsProvider.notifier).delete(project.id);
    }
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.onOpen,
    required this.onDelete,
    this.onResumeDraft,
  });
  final Project project;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final VoidCallback? onResumeDraft;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PostCraftTheme.panel,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onOpen,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: .06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(13),
                  ),
                  child: project.thumbnailPath != null
                      ? Image.file(
                          File(project.thumbnailPath!),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, _, _) => const _ThumbnailFallback(),
                        )
                      : const _ThumbnailFallback(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            project.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _subtitle(project),
                            style: const TextStyle(
                              color: PostCraftTheme.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline_rounded, size: 17),
                      color: PostCraftTheme.muted,
                    ),
                  ],
                ),
              ),
              if (onResumeDraft != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed: onResumeDraft,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(32),
                      ),
                      icon: const Icon(Icons.restore_rounded, size: 15),
                      label: const Text('Resume unsaved changes'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle(Project project) {
    final draft = project.hasUnsavedDraft ? ' · unsaved edits' : '';
    return '${_relativeTime(project.updatedAt)} · '
        '${project.width}×${project.height}$draft';
  }
}

class _RecoveryBanner extends StatelessWidget {
  const _RecoveryBanner({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFBE62).withValues(alpha: .12),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFFFBE62).withValues(alpha: .4)),
    ),
    child: Row(
      children: [
        const Icon(Icons.history_rounded, size: 18, color: Color(0xFFFFBE62)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            count == 1
                ? 'One project has unsaved changes from a previous session. '
                      'Use “Resume” to recover them.'
                : '$count projects have unsaved changes from a previous '
                      'session. Use “Resume” to recover them.',
            style: const TextStyle(fontSize: 12, height: 1.4),
          ),
        ),
      ],
    ),
  );
}

class _ThumbnailFallback extends StatelessWidget {
  const _ThumbnailFallback();

  @override
  Widget build(BuildContext context) => Container(
    color: PostCraftTheme.elevated,
    alignment: Alignment.center,
    child: const Icon(
      Icons.image_outlined,
      size: 30,
      color: PostCraftTheme.muted,
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: PostCraftTheme.accent.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, color: PostCraftTheme.accent, size: 28),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
          const SizedBox(height: 9),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: PostCraftTheme.muted,
              height: 1.5,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.add_rounded),
            label: Text(actionLabel),
          ),
        ],
      ),
    ),
  );
}

String _relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return '${time.year}-${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')}';
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_paths.dart';
import '../../../core/async/delay_scheduler.dart';
import '../../editor/application/editor_controller.dart';
import '../../editor/domain/editor_document.dart';
import '../../export/document_renderer.dart';
import '../../library/application/library_providers.dart';
import '../data/directory_project_repository.dart';
import '../domain/project.dart';
import '../domain/project_repository.dart';

final projectRepositoryProvider = FutureProvider<ProjectRepository>((
  ref,
) async {
  final paths = await ref.watch(appPathsProvider.future);
  return DirectoryProjectRepository(paths.projects);
});

/// Renders a small thumbnail for a project card. Best-effort: a null result is
/// stored as "no thumbnail" rather than failing the save.
final projectThumbnailerProvider =
    Provider<Future<List<int>?> Function(EditorDocument)>((ref) {
      const renderer = DocumentRenderer();
      return (document) async {
        try {
          return await renderer.renderPng(document);
        } on Object {
          return null;
        }
      };
    });

enum SaveStatus { none, saving, saved }

class WorkspaceState {
  const WorkspaceState({
    this.current,
    this.dirty = false,
    this.status = SaveStatus.none,
  });

  final Project? current;
  final bool dirty;
  final SaveStatus status;

  bool get hasProject => current != null;

  WorkspaceState copyWith({
    Project? current,
    bool? dirty,
    SaveStatus? status,
    bool clearProject = false,
  }) => WorkspaceState(
    current: clearProject ? null : (current ?? this.current),
    dirty: dirty ?? this.dirty,
    status: status ?? this.status,
  );
}

/// Owns the currently open project and drives debounced autosave.
///
/// A new capture/import turns into a durable project immediately so nothing is
/// ever only-in-memory; subsequent edits are written to a recoverable draft
/// after [autosaveDelay] of idle time, and promoted to a saved revision on an
/// explicit [saveNow].
class WorkspaceController extends Notifier<WorkspaceState> {
  static const autosaveDelay = Duration(milliseconds: 1200);

  late DelayScheduler _scheduler;

  @override
  WorkspaceState build() {
    _scheduler = ref.watch(delaySchedulerProvider);
    ref.onDispose(_scheduler.cancel);
    return const WorkspaceState();
  }

  /// Persists [document] as a new project and makes it current.
  Future<Project> startProject(EditorDocument document, {String? name}) async {
    _scheduler.cancel();
    final repository = await ref.read(projectRepositoryProvider.future);
    final title = name ?? 'Untitled capture';
    final thumbnail = await ref.read(projectThumbnailerProvider)(document);
    final project = await repository.save(
      name: title,
      document: document,
      thumbnail: thumbnail,
    );
    state = state.copyWith(
      current: project,
      dirty: false,
      status: SaveStatus.saved,
    );
    await ref.read(projectsProvider.notifier).reload();
    final sourceImage = document.sourceImage;
    if (sourceImage != null) {
      try {
        await ref
            .read(assetIngestorProvider)
            .add(bytes: sourceImage, fileName: '$title.png', name: title);
      } on Object {
        // The media library is best-effort; a failure here must not lose the
        // durable project or block editing.
      }
    }
    return project;
  }

  /// Attaches an already-open project (e.g. loaded from the recents list).
  void bindExisting(Project project) {
    _scheduler.cancel();
    state = state.copyWith(
      current: project,
      dirty: false,
      status: SaveStatus.none,
    );
  }

  /// Called whenever the editor document changes; schedules an autosave.
  void markChanged() {
    if (state.current == null) return;
    state = state.copyWith(dirty: true, status: SaveStatus.saving);
    _scheduler.cancel();
    _scheduler.schedule(autosaveDelay, _flushDraft);
  }

  Future<void> _flushDraft() async {
    final project = state.current;
    if (project == null) return;
    final document = ref.read(editorControllerProvider).document;
    final repository = await ref.read(projectRepositoryProvider.future);
    try {
      final updated = await repository.autosave(project.id, document);
      state = state.copyWith(
        current: updated,
        dirty: false,
        status: SaveStatus.saved,
      );
    } on Object {
      // A failed autosave leaves the in-memory document intact; the user can
      // still save explicitly. Reflect that instead of silently swallowing.
      state = state.copyWith(dirty: true, status: SaveStatus.none);
    }
    await ref.read(projectsProvider.notifier).reload();
  }

  /// Promotes the current document to a saved revision and clears the draft.
  Future<void> saveNow() async {
    _scheduler.cancel();
    final project = state.current;
    if (project == null) return;
    final document = ref.read(editorControllerProvider).document;
    final repository = await ref.read(projectRepositoryProvider.future);
    final thumbnail = await ref.read(projectThumbnailerProvider)(document);
    final updated = await repository.save(
      existing: project,
      name: project.name,
      document: document,
      thumbnail: thumbnail,
    );
    state = state.copyWith(
      current: updated,
      dirty: false,
      status: SaveStatus.saved,
    );
    await ref.read(projectsProvider.notifier).reload();
  }

  void clear() {
    _scheduler.cancel();
    state = const WorkspaceState();
  }
}

final workspaceControllerProvider =
    NotifierProvider<WorkspaceController, WorkspaceState>(
      WorkspaceController.new,
    );

class ProjectsController extends AsyncNotifier<List<Project>> {
  @override
  Future<List<Project>> build() => _load();

  Future<List<Project>> _load() async {
    final repository = await ref.watch(projectRepositoryProvider.future);
    return repository.list();
  }

  Future<void> reload() async {
    state = await AsyncValue.guard(() async {
      final repository = await ref.read(projectRepositoryProvider.future);
      return repository.list();
    });
  }

  Future<void> delete(String id) async {
    final repository = await ref.read(projectRepositoryProvider.future);
    await repository.delete(id);
    await reload();
  }
}

final projectsProvider =
    AsyncNotifierProvider<ProjectsController, List<Project>>(
      ProjectsController.new,
    );

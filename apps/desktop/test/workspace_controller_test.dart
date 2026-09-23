import 'dart:io';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postcraft/src/core/async/delay_scheduler.dart';
import 'package:postcraft/src/features/editor/application/editor_controller.dart';
import 'package:postcraft/src/features/editor/domain/editor_document.dart';
import 'package:postcraft/src/features/projects/application/projects_providers.dart';
import 'package:postcraft/src/features/projects/domain/project.dart';
import 'package:postcraft/src/features/projects/domain/project_repository.dart';

void main() {
  const base = EditorDocument(width: 100, height: 80);

  ProviderContainer makeContainer(
    _FakeRepository repo,
    _FakeScheduler scheduler,
  ) {
    final container = ProviderContainer(
      overrides: [
        projectRepositoryProvider.overrideWith((ref) async => repo),
        projectThumbnailerProvider.overrideWithValue((doc) async => null),
        delaySchedulerProvider.overrideWithValue(scheduler),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test(
    'startProject persists a durable project and binds it as current',
    () async {
      final repo = _FakeRepository();
      final container = makeContainer(repo, _FakeScheduler());

      final project = await container
          .read(workspaceControllerProvider.notifier)
          .startProject(base, name: 'First');

      expect(container.read(workspaceControllerProvider).current, isNotNull);
      expect(container.read(workspaceControllerProvider).dirty, isFalse);
      expect(repo.projects, hasLength(1));
      expect(project.name, 'First');
    },
  );

  test('editing schedules a debounced autosave written to a draft', () async {
    final repo = _FakeRepository();
    final scheduler = _FakeScheduler();
    final container = makeContainer(repo, scheduler);

    await container
        .read(workspaceControllerProvider.notifier)
        .startProject(base, name: 'First');

    container
        .read(editorControllerProvider.notifier)
        .commit(
          const ShapeObject(
            id: 1,
            color: Color(0xFFFF0000),
            rect: Rect.fromLTWH(0, 0, 5, 5),
            kind: EditorTool.rectangle,
          ),
        );
    container.read(workspaceControllerProvider.notifier).markChanged();

    expect(
      container.read(workspaceControllerProvider).status,
      SaveStatus.saving,
    );
    expect(scheduler.pending, isNotNull);

    scheduler.fire();
    await pumpEventQueue();

    expect(repo.draftWrittenFor, isNotNull);
    expect(
      container.read(workspaceControllerProvider).current!.hasUnsavedDraft,
      isTrue,
    );
    expect(container.read(workspaceControllerProvider).dirty, isFalse);
  });

  test(
    'a rapid burst of edits coalesces into a single scheduled autosave',
    () async {
      final repo = _FakeRepository();
      final scheduler = _FakeScheduler();
      final container = makeContainer(repo, scheduler);
      await container
          .read(workspaceControllerProvider.notifier)
          .startProject(base, name: 'First');

      for (var i = 0; i < 5; i++) {
        container.read(workspaceControllerProvider.notifier).markChanged();
      }
      expect(scheduler.scheduleCount, 5);
      expect(scheduler.pending, isNotNull); // only one pending at a time
    },
  );

  test(
    'saveNow cancels pending autosave and writes a saved revision',
    () async {
      final repo = _FakeRepository();
      final scheduler = _FakeScheduler();
      final container = makeContainer(repo, scheduler);
      await container
          .read(workspaceControllerProvider.notifier)
          .startProject(base, name: 'First');
      container.read(workspaceControllerProvider.notifier).markChanged();
      scheduler.fire();
      await pumpEventQueue();

      await container.read(workspaceControllerProvider.notifier).saveNow();
      await pumpEventQueue();

      expect(scheduler.cancelled, isTrue);
      expect(
        container.read(workspaceControllerProvider).current!.hasUnsavedDraft,
        isFalse,
      );
      expect(repo.draftWrittenFor, isNull); // save clears the draft
    },
  );

  test(
    'autosave of a document with an invalid revision is reflected as dirty',
    () async {
      final repo = _FakeRepository()..throwOnAutosave = true;
      final scheduler = _FakeScheduler();
      final container = makeContainer(repo, scheduler);
      await container
          .read(workspaceControllerProvider.notifier)
          .startProject(base, name: 'First');
      container.read(workspaceControllerProvider.notifier).markChanged();
      scheduler.fire();
      await pumpEventQueue();

      final state = container.read(workspaceControllerProvider);
      expect(state.dirty, isTrue);
      expect(state.status, SaveStatus.none);
    },
  );
}

class _FakeScheduler implements DelayScheduler {
  void Function()? pending;
  int scheduleCount = 0;
  bool cancelled = false;

  @override
  void schedule(Duration delay, void Function() callback) {
    scheduleCount++;
    cancelled = false;
    pending = callback;
  }

  @override
  void cancel() {
    cancelled = true;
    pending = null;
  }

  void fire() {
    final cb = pending;
    pending = null;
    cb?.call();
  }
}

class _FakeRepository implements ProjectRepository {
  final List<Project> projects = [];
  String? draftWrittenFor;
  bool throwOnAutosave = false;
  int _counter = 0;

  Project _projectFor(
    String id,
    EditorDocument document,
    String name, {
    bool draft = false,
  }) {
    return Project(
      id: id,
      name: name,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026).add(Duration(minutes: _counter++)),
      width: document.width,
      height: document.height,
      layerCount: document.objects.length,
      directoryPath: '/fake/$id',
      hasUnsavedDraft: draft,
    );
  }

  @override
  Future<List<Project>> list() async => List.unmodifiable(projects);

  @override
  Future<Project?> get(String id) async =>
      projects.where((p) => p.id == id).firstOrNull;

  @override
  Future<Project> save({
    Project? existing,
    required String name,
    required EditorDocument document,
    List<int>? thumbnail,
  }) async {
    final id = existing?.id ?? 'id-${projects.length + 1}';
    draftWrittenFor = null; // a full save clears the draft marker
    final project = _projectFor(id, document, name);
    projects
      ..removeWhere((p) => p.id == id)
      ..add(project);
    return project;
  }

  @override
  Future<Project> autosave(String id, EditorDocument document) async {
    if (throwOnAutosave) {
      throw const FileSystemException('simulated autosave failure');
    }
    final existing = projects.firstWhere((p) => p.id == id);
    draftWrittenFor = id;
    final updated = _projectFor(id, document, existing.name, draft: true);
    projects
      ..removeWhere((p) => p.id == id)
      ..add(updated);
    return updated;
  }

  @override
  Future<EditorDocument> load(String id, {bool draft = false}) async =>
      throw UnimplementedError();

  @override
  Future<void> delete(String id) async =>
      projects.removeWhere((p) => p.id == id);
}

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:postcraft/src/features/editor/domain/editor_document.dart';
import 'package:postcraft/src/features/projects/data/directory_project_repository.dart';
import 'package:postcraft/src/features/projects/domain/project.dart';

void main() {
  late Directory root;
  late DirectoryProjectRepository repository;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('postcraft-repo-');
    repository = DirectoryProjectRepository(root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  const base = EditorDocument(width: 100, height: 80);
  final withLayer = base.add(
    const ShapeObject(
      id: 1,
      color: Color(0xFFFF0000),
      rect: Rect.fromLTWH(1, 1, 5, 5),
      kind: EditorTool.rectangle,
    ),
  );

  test('saves, lists, and reloads a project', () async {
    final saved = await repository.save(name: 'One', document: base);
    expect(saved.id, isNotEmpty);

    final list = await repository.list();
    expect(list, hasLength(1));
    expect(list.first.name, 'One');
    expect(list.first.hasUnsavedDraft, isFalse);

    final loaded = await repository.load(saved.id);
    expect(loaded.width, 100);
    expect(loaded.height, 80);

    final fetched = await repository.get(saved.id);
    expect(fetched, isA<Project>());
    expect(fetched!.id, saved.id);
  });

  test(
    'autosave creates a recoverable draft without touching the saved revision',
    () async {
      final saved = await repository.save(name: 'One', document: base);

      final updated = await repository.autosave(saved.id, withLayer);
      expect(updated.hasUnsavedDraft, isTrue);

      final reloaded = await repository.get(saved.id);
      expect(reloaded!.hasUnsavedDraft, isTrue);

      // The draft reflects the newer edit; the saved revision is untouched.
      final draft = await repository.load(saved.id, draft: true);
      final durable = await repository.load(saved.id);
      expect(draft.objects, hasLength(1));
      expect(durable.objects, isEmpty);

      // An explicit save clears the draft and promotes the edit.
      await repository.save(
        existing: updated,
        name: 'One',
        document: withLayer,
      );
      final afterSave = await repository.get(saved.id);
      expect(afterSave!.hasUnsavedDraft, isFalse);
      expect(afterSave.layerCount, 1);
    },
  );

  test('delete removes the project from disk and the list', () async {
    final saved = await repository.save(name: 'Gone', document: base);
    await repository.delete(saved.id);

    expect(await repository.list(), isEmpty);
    expect(await repository.get(saved.id), isNull);
    expect(Directory(saved.directoryPath).existsSync(), isFalse);
  });

  test('save rejects structurally invalid documents', () async {
    await expectLater(
      repository.save(
        name: 'Bad',
        document: const EditorDocument(width: 0, height: 0),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(await repository.list(), isEmpty);
  });

  test('persists source image bytes through a full save cycle', () async {
    final withImage = base.withSourceImage(
      Uint8List.fromList([1, 2, 3, 4, 5]),
      100,
      80,
    );
    final saved = await repository.save(name: 'Img', document: withImage);
    final loaded = await repository.load(saved.id);
    expect(loaded.sourceImage, [1, 2, 3, 4, 5]);
  });
}

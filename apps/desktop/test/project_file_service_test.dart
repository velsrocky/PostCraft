import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postcraft/src/features/editor/domain/editor_document.dart';
import 'package:postcraft/src/features/projects/data/project_file_service.dart';

void main() {
  test(
    'project bundle round-trip preserves source media and editable layers',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'postcraft-test-',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final projectPath = '${tempDirectory.path}/round-trip.postcraft';
      final expected = EditorDocument(
        width: 320,
        height: 180,
        sourceImage: Uint8List.fromList([11, 22, 33, 44]),
        objects: const [
          ShapeObject(
            id: 1,
            color: Color(0xFF9988FF),
            rect: Rect.fromLTWH(10, 12, 30, 20),
            kind: EditorTool.blur,
          ),
        ],
      );
      final service = ProjectFileService(
        pickSaveLocation: () async => projectPath,
        pickOpenFile: () async => XFile(projectPath),
      );

      expect(await service.save(expected), isTrue);
      final restored = await service.open();

      expect(restored, isNotNull);
      expect(restored!.width, 320);
      expect(restored.height, 180);
      expect(restored.sourceImage, expected.sourceImage);
      expect(restored.objects, hasLength(1));
      expect(restored.objects.single, isA<ShapeObject>());
    },
  );

  test('rejects a non-project archive', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'postcraft-test-',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final badProject = File('${tempDirectory.path}/bad.postcraft');
    final archive = Archive()
      ..add(ArchiveFile.string('wrong.txt', 'not a manifest'));
    await badProject.writeAsBytes(ZipEncoder().encode(archive));
    final service = ProjectFileService(
      pickOpenFile: () async => XFile(badProject.path),
    );

    expect(service.open, throwsA(isA<FormatException>()));
  });

  test(
    'failed save validation leaves the existing project untouched',
    () async {
      final tempDirectory = await Directory.systemTemp.createTemp(
        'postcraft-test-',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final projectPath = '${tempDirectory.path}/safe.postcraft';
      final service = ProjectFileService(
        pickSaveLocation: () async => projectPath,
      );
      final valid = const EditorDocument(width: 320, height: 180);
      await service.save(valid);
      final originalBytes = await File(projectPath).readAsBytes();

      final invalid = EditorDocument(width: 0, height: 180);
      await expectLater(service.save(invalid), throwsA(isA<FormatException>()));

      expect(await File(projectPath).readAsBytes(), originalBytes);
      expect(
        tempDirectory.listSync().where(
          (entity) =>
              entity.path.contains('.tmp-') || entity.path.contains('.bak-'),
        ),
        isEmpty,
      );
    },
  );

  test('rejects unknown archive entries and duplicate IDs', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'postcraft-test-',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final projectPath = '${tempDirectory.path}/invalid.postcraft';
    final manifest = ArchiveFile.string(
      'manifest.json',
      '{"formatVersion":1,"document":{"width":320,"height":180,"objects":[]}}',
    );
    final archive = Archive()
      ..add(manifest)
      ..add(ArchiveFile.string('unexpected.txt', 'payload'));
    await File(projectPath).writeAsBytes(ZipEncoder().encode(archive));
    final service = ProjectFileService(
      pickOpenFile: () async => XFile(projectPath),
    );

    await expectLater(service.open(), throwsA(isA<FormatException>()));
  });

  test('rejects duplicate annotation object IDs', () async {
    final tempDirectory = await Directory.systemTemp.createTemp(
      'postcraft-test-',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));
    final projectPath = '${tempDirectory.path}/duplicate-ids.postcraft';
    const object = {
      'type': 'shape',
      'id': 1,
      'color': 4278190335,
      'left': 1,
      'top': 1,
      'width': 10,
      'height': 10,
      'kind': 'rectangle',
    };
    final archive = Archive()
      ..add(
        ArchiveFile.string(
          'manifest.json',
          '{"formatVersion":1,"document":{"width":320,"height":180,"objects":[${jsonEncode(object)},${jsonEncode(object)}]}}',
        ),
      );
    await File(projectPath).writeAsBytes(ZipEncoder().encode(archive));
    final service = ProjectFileService(
      pickOpenFile: () async => XFile(projectPath),
    );

    await expectLater(service.open(), throwsA(isA<FormatException>()));
  });
}

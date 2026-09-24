import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postcraft/src/features/editor/domain/editor_document.dart';
import 'package:postcraft/src/features/projects/data/directory_project_repository.dart';
import 'package:postcraft/src/features/projects/data/project_bundle_codec.dart';
import 'package:postcraft/src/features/projects/domain/project.dart';

void main() {
  group('bundle formatVersion', () {
    for (final version in <Object?>[0, 2, null]) {
      test('rejects a manifest with formatVersion $version', () {
        expect(
          () => ProjectBundleCodec.decode(_archiveWithVersion(version)),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('format'),
            ),
          ),
        );
      });
    }

    test('writes the current formatVersion of 1', () {
      expect(ProjectBundleCodec.formatVersion, 1);
      final decoded = jsonDecode(
        utf8.decode(
          ZipDecoder()
                  .decodeBytes(
                    ProjectBundleCodec.encode(
                      const EditorDocument(width: 10, height: 10),
                    ),
                  )
                  .findFile(ProjectBundleCodec.manifestPath)!
                  .content
              as List<int>,
        ),
      );
      expect(decoded, isA<Map<String, dynamic>>());
      expect((decoded as Map<String, dynamic>)['formatVersion'], 1);
    });
  });

  group('migrateManifest', () {
    test('returns a version 1 manifest as-is', () {
      final manifest = <String, Object?>{
        'formatVersion': 1,
        'document': <String, Object?>{},
      };
      final migrated = ProjectBundleCodec.migrateManifest(manifest);
      expect(identical(migrated, manifest), isTrue);
    });

    test('rejects a missing or non-integer formatVersion', () {
      expect(
        () => ProjectBundleCodec.migrateManifest(<String, Object?>{}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => ProjectBundleCodec.migrateManifest(<String, Object?>{
          'formatVersion': '1',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects versions outside the supported range', () {
      expect(
        () => ProjectBundleCodec.migrateManifest(<String, Object?>{
          'formatVersion': 0,
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('format'),
          ),
        ),
      );
      expect(
        () => ProjectBundleCodec.migrateManifest(<String, Object?>{
          'formatVersion': 2,
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('format'),
          ),
        ),
      );
    });
  });

  group('meta.json schemaVersion', () {
    late Directory root;
    late DirectoryProjectRepository repository;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('postcraft-schema-');
      repository = DirectoryProjectRepository(root);
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('meta.json without schemaVersion still loads as version 1', () async {
      final directory = Directory(
        '${root.path}${Platform.pathSeparator}legacy-project',
      )..createSync(recursive: true);
      File(
        '${directory.path}${Platform.pathSeparator}meta.json',
      ).writeAsStringSync(
        jsonEncode({
          'id': 'legacy-project',
          'name': 'Legacy',
          'createdAt': '2026-01-01T00:00:00.000Z',
          'updatedAt': '2026-01-02T00:00:00.000Z',
          'width': 100,
          'height': 80,
          'layerCount': 0,
        }),
      );

      final project = await repository.get('legacy-project');
      expect(project, isNotNull);
      expect(project!.schemaVersion, 1);
      expect(project.name, 'Legacy');
    });

    test('meta.json with schemaVersion 1 round-trips through save', () async {
      final saved = await repository.save(
        name: 'Current',
        document: const EditorDocument(width: 64, height: 48),
      );
      expect(saved.schemaVersion, 1);

      final meta =
          jsonDecode(
                File(
                  '${saved.directoryPath}${Platform.pathSeparator}meta.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      expect(meta['schemaVersion'], 1);

      final reloaded = Project.fromJson(
        meta,
        directoryPath: saved.directoryPath,
      );
      expect(reloaded, isNotNull);
      expect(reloaded!.schemaVersion, 1);
      expect(reloaded.toJson()['schemaVersion'], 1);
      expect(reloaded.id, saved.id);
      expect(reloaded.name, saved.name);
    });
  });
}

Uint8List _archiveWithVersion(Object? formatVersion) {
  final archive = Archive();
  archive.add(
    ArchiveFile.string(
      ProjectBundleCodec.manifestPath,
      jsonEncode({
        'formatVersion': ?formatVersion,
        'document': {'width': 100, 'height': 100, 'objects': <Object?>[]},
      }),
    ),
  );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

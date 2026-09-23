import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:postcraft/src/features/library/data/file_asset_repository.dart';
import 'package:postcraft/src/features/library/domain/asset.dart';

void main() {
  late Directory root;
  late FileAssetRepository repo;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('postcraft-assets-');
    repo = FileAssetRepository(root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  final pngBytes = Uint8List.fromList([
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    1,
    2,
    3,
    4,
  ]);

  test('adds an image asset and classifies its kind', () async {
    final asset = await repo.add(
      bytes: pngBytes,
      fileName: 'shot.png',
      name: 'Screenshot one',
    );

    expect(asset.kind, AssetKind.image);
    expect(asset.name, 'Screenshot one');
    expect(asset.byteSize, pngBytes.length);
    expect(asset.contentHash, hasLength(64)); // sha256 hex
    expect(await repo.list(), hasLength(1));

    final path = await repo.filePath(asset.id);
    expect(path, isNotNull);
    expect(await File(path!).readAsBytes(), pngBytes);
  });

  test('re-adding identical bytes de-duplicates and merges tags', () async {
    final first = await repo.add(
      bytes: pngBytes,
      fileName: 'a.png',
      name: 'A',
      tags: ['work'],
    );
    final second = await repo.add(
      bytes: pngBytes,
      fileName: 'b.png',
      name: 'A',
      tags: ['urgent'],
    );

    expect(second.id, first.id);
    expect(await repo.list(), hasLength(1));
    expect((await repo.get(first.id))!.tags, containsAll(['work', 'urgent']));
  });

  test('search filters by name and by tag', () async {
    await repo.add(
      bytes: pngBytes,
      fileName: 'logo.png',
      name: 'Brand logo',
      tags: ['marketing'],
    );
    await repo.add(
      bytes: Uint8List.fromList([0, 1, 2, 3]),
      fileName: 'clip.mp4',
      name: 'Demo reel',
    );

    expect(await repo.list(query: 'logo'), hasLength(1));
    expect(await repo.list(query: 'marketing'), hasLength(1));
    expect(await repo.list(kind: AssetKind.video), hasLength(1));
    expect(await repo.list(query: 'nomatch'), isEmpty);
  });

  test('setTags updates an asset', () async {
    final asset = await repo.add(bytes: pngBytes, fileName: 'x.png', name: 'X');
    final updated = await repo.setTags(asset.id, [' one ', '', 'two']);
    expect(updated.tags, ['one', 'two']);
  });

  test('remove deletes the folder and drops it from the list', () async {
    final asset = await repo.add(bytes: pngBytes, fileName: 'gone.png');
    await repo.remove(asset.id);
    expect(await repo.list(), isEmpty);
    expect(await repo.filePath(asset.id), isNull);
    expect(
      Directory(
        '${root.path}${Platform.pathSeparator}${asset.id}',
      ).existsSync(),
      isFalse,
    );
  });

  test('a fresh repository instance reads the persisted index', () async {
    final asset = await repo.add(
      bytes: pngBytes,
      fileName: 'persist.png',
      name: 'Persisted',
      tags: ['keep'],
    );

    final reopened = FileAssetRepository(root);
    final listed = await reopened.list();
    expect(listed, hasLength(1));
    expect(listed.single.id, asset.id);
    expect(listed.single.tags, ['keep']);
    // The bytes are still retrievable through the new instance.
    final path = await reopened.filePath(asset.id);
    expect(path, isNotNull);
    expect(await File(path!).exists(), isTrue);
  });
}

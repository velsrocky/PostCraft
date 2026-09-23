import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postcraft/src/features/editor/domain/editor_document.dart';
import 'package:postcraft/src/features/projects/data/project_bundle_codec.dart';

void main() {
  const object = ShapeObject(
    id: 1,
    color: Color(0xFFFF0000),
    rect: Rect.fromLTWH(2, 3, 40, 50),
    kind: EditorTool.rectangle,
  );

  test('round-trips a document with its source image', () {
    final document = const EditorDocument(
      width: 800,
      height: 600,
      objects: [object],
    ).withSourceImage(Uint8List.fromList([9, 8, 7]), 800, 600);

    final restored = ProjectBundleCodec.decode(
      ProjectBundleCodec.encode(document),
    );

    expect(restored.width, 800);
    expect(restored.height, 600);
    expect(restored.sourceImage, [9, 8, 7]);
    expect(restored.objects.single, isA<ShapeObject>());
  });

  test('rejects archives with an unknown entry', () {
    expect(
      () => ProjectBundleCodec.decode(
        _archive({'manifest.json': _manifest([]), 'evil.txt': 'x'}),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects documents with invalid dimensions', () {
    expect(
      () =>
          ProjectBundleCodec.encode(const EditorDocument(width: 0, height: 0)),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects duplicate object IDs on decode', () {
    expect(
      () => ProjectBundleCodec.decode(
        _archive({
          'manifest.json': _manifest([object.toJson(), object.toJson()]),
        }),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}

String _manifest(List<Object?> objects) => jsonEncode({
  'formatVersion': 1,
  'document': {'width': 100, 'height': 100, 'objects': objects},
});

Uint8List _archive(Map<String, String> entries) {
  final archive = Archive();
  entries.forEach((name, content) {
    archive.add(ArchiveFile.string(name, content));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

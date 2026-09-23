import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:postcraft/src/features/editor/domain/editor_document.dart';

void main() {
  test(
    'document JSON round-trip preserves drawable objects and source pixels',
    () {
      const document = EditorDocument(
        width: 320,
        height: 180,
        sourceImage: null,
        objects: [
          ShapeObject(
            id: 1,
            color: Color(0xFFFF0000),
            rect: Rect.fromLTWH(12, 20, 30, 40),
            kind: EditorTool.rectangle,
          ),
          TextObject(
            id: 2,
            color: Color(0xFFFFFFFF),
            position: Offset(50, 60),
            text: 'Hello',
          ),
          StrokeObject(
            id: 3,
            color: Color(0xFF00FF00),
            points: [Offset(1, 2), Offset(3, 4)],
          ),
        ],
      );
      final json = document.toJson()
        ..['sourceImageBase64'] = base64Encode([1, 2, 3]);

      final restored = EditorDocument.fromJson(json);

      expect(restored.width, 320);
      expect(restored.height, 180);
      expect(restored.nextId, 4);
      expect(restored.objects, hasLength(3));
      expect(restored.objects[0], isA<ShapeObject>());
      expect(restored.objects[1], isA<TextObject>());
      expect(restored.objects[2], isA<StrokeObject>());
      expect(restored.sourceImage, Uint8List.fromList([1, 2, 3]));
    },
  );

  test('adding annotations preserves original source and document size', () {
    final source = Uint8List.fromList([1, 2, 3, 4]);
    final document = const EditorDocument(width: 800, height: 600)
        .withSourceImage(source, 800, 600)
        .add(
          const ShapeObject(
            id: 1,
            color: Color(0xFFFFFFFF),
            rect: Rect.fromLTWH(20, 30, 40, 50),
            kind: EditorTool.rectangle,
          ),
        );

    expect(document.sourceImage, same(source));
    expect(document.width, 800);
    expect(document.height, 600);
    expect(document.objects, hasLength(1));
  });
}

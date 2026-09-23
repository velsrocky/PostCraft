import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postcraft/src/features/editor/application/editor_controller.dart';
import 'package:postcraft/src/features/editor/domain/editor_document.dart';

void main() {
  test('commits an object and undo/redo restores document revisions', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(editorControllerProvider.notifier);

    controller.commit(
      const ShapeObject(
        id: 1,
        color: Color(0xFFFF0000),
        rect: Rect.fromLTWH(10, 20, 30, 40),
        kind: EditorTool.rectangle,
      ),
    );
    expect(controller.state.document.objects, hasLength(1));

    controller.undo();
    expect(controller.state.document.objects, isEmpty);

    controller.redo();
    expect(controller.state.document.objects, hasLength(1));
  });

  test('object mutations preserve the source image and canvas dimensions', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(editorControllerProvider.notifier);
    final source = Uint8List.fromList([1, 2, 3, 4]);
    controller.importSourceImage(source, 10, 8);
    controller.commit(
      const ShapeObject(
        id: 1,
        color: Color(0xFFFF0000),
        rect: Rect.fromLTWH(1, 1, 4, 4),
        kind: EditorTool.rectangle,
      ),
    );

    expect(controller.state.document.sourceImage, same(source));
    expect(controller.state.document.width, 10);
    expect(controller.state.document.height, 8);
    controller.undo();
    expect(controller.state.document.sourceImage, same(source));
    expect(controller.state.document.objects, isEmpty);
  });

  test('undo history is bounded and new edits clear redo history', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(editorControllerProvider.notifier);
    for (var id = 1; id <= editorHistoryLimit + 5; id++) {
      controller.commit(
        ShapeObject(
          id: id,
          color: const Color(0xFF00FF00),
          rect: Rect.fromLTWH(id.toDouble(), 0, 1, 1),
          kind: EditorTool.rectangle,
        ),
      );
    }
    expect(controller.state.undoStack, hasLength(editorHistoryLimit));
    controller.undo();
    expect(controller.state.redoStack, hasLength(1));
    controller.commit(
      const ShapeObject(
        id: 1000,
        color: Color(0xFF00FF00),
        rect: Rect.fromLTWH(0, 0, 1, 1),
        kind: EditorTool.rectangle,
      ),
    );
    expect(controller.state.redoStack, isEmpty);
  });
}

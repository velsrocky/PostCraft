import 'dart:ui';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/editor_document.dart';
import '../../studio/domain/timeline.dart';

const editorHistoryLimit = 100;

final editorControllerProvider =
    NotifierProvider<EditorController, EditorState>(EditorController.new);

class EditorState {
  const EditorState({
    this.document = const EditorDocument(),
    this.tool = EditorTool.select,
    this.color = const Color(0xFF8D7CFF),
    this.undoStack = const [],
    this.redoStack = const [],
  });

  final EditorDocument document;
  final EditorTool tool;
  final Color color;
  final List<EditorDocument> undoStack;
  final List<EditorDocument> redoStack;

  EditorState copyWith({
    EditorDocument? document,
    EditorTool? tool,
    Color? color,
    List<EditorDocument>? undoStack,
    List<EditorDocument>? redoStack,
  }) => EditorState(
    document: document ?? this.document,
    tool: tool ?? this.tool,
    color: color ?? this.color,
    undoStack: undoStack ?? this.undoStack,
    redoStack: redoStack ?? this.redoStack,
  );
}

class EditorController extends Notifier<EditorState> {
  @override
  EditorState build() => const EditorState();

  void selectTool(EditorTool tool) => state = state.copyWith(tool: tool);
  void selectColor(Color color) => state = state.copyWith(color: color);

  void commit(EditorObject object) {
    final current = state.document;
    final next = current.add(object);
    state = state.copyWith(
      document: next,
      undoStack: _boundedHistory(state.undoStack, current),
      redoStack: const [],
    );
  }

  bool removeObject(int id) {
    final current = state.document;
    final nextObjects = current.objects
        .where((object) => object.id != id)
        .toList();
    if (nextObjects.length == current.objects.length) return false;
    state = state.copyWith(
      document: current.withObjects(nextObjects),
      undoStack: _boundedHistory(state.undoStack, current),
      redoStack: const [],
    );
    return true;
  }

  void undo() {
    if (state.undoStack.isEmpty) return;
    final previous = state.undoStack.last;
    state = state.copyWith(
      document: previous,
      undoStack: state.undoStack.sublist(0, state.undoStack.length - 1),
      redoStack: [...state.redoStack, state.document],
    );
  }

  void redo() {
    if (state.redoStack.isEmpty) return;
    final next = state.redoStack.last;
    state = state.copyWith(
      document: next,
      undoStack: [...state.undoStack, state.document],
      redoStack: state.redoStack.sublist(0, state.redoStack.length - 1),
    );
  }

  void replaceDocument(EditorDocument document) {
    state = state.copyWith(
      document: document,
      undoStack: const [],
      redoStack: const [],
    );
  }

  void replaceTimeline(Timeline timeline) {
    final current = state.document;
    state = state.copyWith(
      document: current.withTimeline(timeline),
      undoStack: _boundedHistory(state.undoStack, current),
      redoStack: const [],
    );
  }

  void clearDocument() => replaceDocument(const EditorDocument());

  void importSourceImage(Uint8List bytes, int width, int height) {
    final current = state.document;
    final next = current.withSourceImage(bytes, width, height);
    state = state.copyWith(
      document: next,
      undoStack: _boundedHistory(state.undoStack, current),
      redoStack: const [],
    );
  }

  void openImage(Uint8List bytes, int width, int height) {
    state = state.copyWith(
      document: const EditorDocument().withSourceImage(bytes, width, height),
      undoStack: const [],
      redoStack: const [],
    );
  }

  List<EditorDocument> _boundedHistory(
    List<EditorDocument> history,
    EditorDocument document,
  ) {
    final updated = [...history, document];
    if (updated.length <= editorHistoryLimit) return updated;
    return updated.sublist(updated.length - editorHistoryLimit);
  }
}

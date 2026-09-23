import 'dart:ui';
import 'dart:convert';
import 'dart:typed_data';

import '../../studio/domain/timeline.dart';

enum EditorTool { select, arrow, rectangle, ellipse, text, pencil, blur }

EditorTool editorToolFromName(String name) => EditorTool.values.firstWhere(
  (tool) => tool.name == name,
  orElse: () => EditorTool.select,
);

sealed class EditorObject {
  const EditorObject({required this.id, required this.color});
  final int id;
  final Color color;
  Map<String, Object?> toJson();
}

class ShapeObject extends EditorObject {
  const ShapeObject({
    required super.id,
    required super.color,
    required this.rect,
    required this.kind,
  });
  final Rect rect;
  final EditorTool kind;

  @override
  Map<String, Object?> toJson() => {
    'type': 'shape',
    'id': id,
    'color': color.toARGB32(),
    'left': rect.left,
    'top': rect.top,
    'width': rect.width,
    'height': rect.height,
    'kind': kind.name,
  };
}

class TextObject extends EditorObject {
  const TextObject({
    required super.id,
    required super.color,
    required this.position,
    required this.text,
  });
  final Offset position;
  final String text;

  @override
  Map<String, Object?> toJson() => {
    'type': 'text',
    'id': id,
    'color': color.toARGB32(),
    'x': position.dx,
    'y': position.dy,
    'text': text,
  };
}

class StrokeObject extends EditorObject {
  const StrokeObject({
    required super.id,
    required super.color,
    required this.points,
  });
  final List<Offset> points;

  @override
  Map<String, Object?> toJson() => {
    'type': 'stroke',
    'id': id,
    'color': color.toARGB32(),
    'points': points.map((point) => [point.dx, point.dy]).toList(),
  };
}

class EditorDocument {
  const EditorDocument({
    this.objects = const [],
    this.nextId = 1,
    this.sourceImage,
    this.width = 1920,
    this.height = 1080,
    this.timeline = const Timeline(),
  });
  final List<EditorObject> objects;
  final int nextId;
  final Uint8List? sourceImage;
  final int width;
  final int height;
  final Timeline timeline;

  Map<String, Object?> toJson() => {
    'width': width,
    'height': height,
    if (sourceImage != null) 'sourceImageBase64': base64Encode(sourceImage!),
    'objects': objects.map((object) => object.toJson()).toList(),
    'timeline': timeline.toJson(),
  };

  factory EditorDocument.fromJson(Map<String, Object?> json) {
    final rawObjects = json['objects'];
    if (rawObjects is! List) return const EditorDocument();
    final encodedImage = json['sourceImageBase64'];
    final sourceImage = encodedImage is String
        ? base64Decode(encodedImage)
        : null;
    final width = json['width'] is int ? json['width']! as int : 1920;
    final height = json['height'] is int ? json['height']! as int : 1080;
    final objects = <EditorObject>[];
    for (final raw in rawObjects) {
      if (raw is! Map) continue;
      final map = Map<String, Object?>.from(raw);
      final id = map['id'];
      final color = map['color'];
      if (id is! int || color is! int) continue;
      final type = map['type'];
      if (type == 'shape') {
        final left = _number(map['left']);
        final top = _number(map['top']);
        final width = _number(map['width']);
        final height = _number(map['height']);
        objects.add(
          ShapeObject(
            id: id,
            color: Color(color),
            rect: Rect.fromLTWH(left, top, width, height),
            kind: editorToolFromName(map['kind'] as String? ?? 'rectangle'),
          ),
        );
      } else if (type == 'text' && map['text'] is String) {
        objects.add(
          TextObject(
            id: id,
            color: Color(color),
            position: Offset(_number(map['x']), _number(map['y'])),
            text: map['text']! as String,
          ),
        );
      } else if (type == 'stroke' && map['points'] is List) {
        final points = (map['points']! as List)
            .whereType<List>()
            .where((point) => point.length == 2)
            .map((point) => Offset(_number(point[0]), _number(point[1])))
            .toList();
        if (points.isNotEmpty) {
          objects.add(
            StrokeObject(id: id, color: Color(color), points: points),
          );
        }
      }
    }
    return EditorDocument(
      objects: objects,
      nextId: objects.fold(
        1,
        (next, object) => object.id >= next ? object.id + 1 : next,
      ),
      sourceImage: sourceImage,
      width: width,
      height: height,
      timeline: Timeline.fromJson(json['timeline']),
    );
  }

  EditorDocument withSourceImage(Uint8List bytes, int width, int height) =>
      EditorDocument(
        objects: objects,
        nextId: nextId,
        sourceImage: bytes,
        width: width,
        height: height,
        timeline: timeline,
      );

  EditorDocument add(EditorObject object) => EditorDocument(
    objects: [...objects, object],
    nextId: object.id >= nextId ? object.id + 1 : nextId,
    sourceImage: sourceImage,
    width: width,
    height: height,
    timeline: timeline,
  );

  EditorDocument withObjects(List<EditorObject> nextObjects) => EditorDocument(
    objects: nextObjects,
    nextId: nextObjects.fold(
      1,
      (next, object) => object.id >= next ? object.id + 1 : next,
    ),
    sourceImage: sourceImage,
    width: width,
    height: height,
    timeline: timeline,
  );

  EditorDocument withTimeline(Timeline nextTimeline) => EditorDocument(
    objects: objects,
    nextId: nextId,
    sourceImage: sourceImage,
    width: width,
    height: height,
    timeline: nextTimeline,
  );
}

double _number(Object? value) => value is num ? value.toDouble() : 0;

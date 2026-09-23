import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../application/editor_controller.dart';
import '../domain/editor_document.dart';

class EditorSurface extends StatefulWidget {
  const EditorSurface({required this.state, required this.onCommit, super.key});
  final EditorState state;
  final ValueChanged<EditorObject> onCommit;

  @override
  State<EditorSurface> createState() => _EditorSurfaceState();
}

class _EditorSurfaceState extends State<EditorSurface> {
  Offset? _start;
  Offset? _current;
  final List<Offset> _strokePoints = [];
  ui.Image? _sourceImage;
  Uint8List? _decodedBytes;

  @override
  void initState() {
    super.initState();
    _decodeSourceImage();
  }

  @override
  void didUpdateWidget(covariant EditorSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
      oldWidget.state.document.sourceImage,
      widget.state.document.sourceImage,
    )) {
      _decodeSourceImage();
    }
  }

  @override
  void dispose() {
    _sourceImage?.dispose();
    super.dispose();
  }

  void _decodeSourceImage() {
    final bytes = widget.state.document.sourceImage;
    if (bytes == null) {
      _sourceImage?.dispose();
      _sourceImage = null;
      _decodedBytes = null;
      return;
    }
    if (identical(bytes, _decodedBytes)) return;
    _decodedBytes = bytes;
    ui.decodeImageFromList(bytes, (image) {
      if (!mounted || !identical(bytes, widget.state.document.sourceImage)) {
        image.dispose();
        return;
      }
      setState(() {
        _sourceImage?.dispose();
        _sourceImage = image;
      });
    });
  }

  Offset _toDocument(Offset point, Size size) => Offset(
    point.dx * widget.state.document.width / size.width,
    point.dy * widget.state.document.height / size.height,
  );

  Size get _canvasSize => Size(
    context.size?.width ?? widget.state.document.width.toDouble(),
    context.size?.height ?? widget.state.document.height.toDouble(),
  );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (details) {
        if (widget.state.tool == EditorTool.select ||
            widget.state.tool == EditorTool.text) {
          return;
        }
        setState(() {
          _start = _toDocument(details.localPosition, _canvasSize);
          _current = _start;
          _strokePoints
            ..clear()
            ..add(_start!);
        });
      },
      onPanUpdate: (details) {
        if (_start == null) return;
        setState(() {
          _current = _toDocument(details.localPosition, _canvasSize);
          if (widget.state.tool == EditorTool.pencil) {
            _strokePoints.add(_current!);
          }
        });
      },
      onPanEnd: (_) => _finishGesture(),
      onTapUp: (details) {
        if (widget.state.tool == EditorTool.text) {
          final id = widget.state.document.nextId;
          widget.onCommit(
            TextObject(
              id: id,
              color: widget.state.color,
              position: _toDocument(details.localPosition, _canvasSize),
              text: 'Double-click to edit',
            ),
          );
        }
      },
      child: CustomPaint(
        painter: DocumentPainter(
          objects: widget.state.document.objects,
          tool: widget.state.tool,
          color: widget.state.color,
          start: _start,
          current: _current,
          strokePoints: _strokePoints,
          sourceImage: _sourceImage,
          documentWidth: widget.state.document.width,
          documentHeight: widget.state.document.height,
        ),
        size: Size.infinite,
      ),
    );
  }

  void _finishGesture() {
    if (_start == null || _current == null) return;
    final id = widget.state.document.nextId;
    final color = widget.state.color;
    final start = _start!;
    final current = _current!;
    switch (widget.state.tool) {
      case EditorTool.rectangle:
      case EditorTool.ellipse:
      case EditorTool.blur:
        widget.onCommit(
          ShapeObject(
            id: id,
            color: color,
            rect: Rect.fromPoints(start, current),
            kind: widget.state.tool,
          ),
        );
      case EditorTool.arrow:
        widget.onCommit(
          StrokeObject(id: id, color: color, points: [start, current]),
        );
      case EditorTool.pencil:
        if (_strokePoints.length > 1) {
          widget.onCommit(
            StrokeObject(id: id, color: color, points: List.of(_strokePoints)),
          );
        }
      case EditorTool.select:
      case EditorTool.text:
        break;
    }
    setState(() {
      _start = null;
      _current = null;
      _strokePoints.clear();
    });
  }
}

class DocumentPainter extends CustomPainter {
  DocumentPainter({
    required this.objects,
    required this.tool,
    required this.color,
    required this.start,
    required this.current,
    required this.strokePoints,
    required this.sourceImage,
    required this.documentWidth,
    required this.documentHeight,
    this.showGrid = true,
  });

  final List<EditorObject> objects;
  final EditorTool tool;
  final Color color;
  final Offset? start;
  final Offset? current;
  final List<Offset> strokePoints;
  final ui.Image? sourceImage;
  final int documentWidth;
  final int documentHeight;
  final bool showGrid;

  @override
  void paint(Canvas canvas, Size size) {
    if (sourceImage case final image?) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(
          0,
          0,
          documentWidth.toDouble(),
          documentHeight.toDouble(),
        ),
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
    canvas.save();
    canvas.scale(size.width / documentWidth, size.height / documentHeight);
    if (showGrid && sourceImage == null) {
      final gridPaint = Paint()..color = Colors.white.withValues(alpha: .025);
      for (var x = 0.0; x < documentWidth; x += 24) {
        for (var y = 0.0; y < documentHeight; y += 24) {
          if ((x ~/ 24 + y ~/ 24).isEven) {
            canvas.drawRect(Rect.fromLTWH(x, y, 24, 24), gridPaint);
          }
        }
      }
    }
    for (final object in objects) {
      _paintObject(canvas, object);
    }
    if (start != null && current != null) _paintPreview(canvas);
    canvas.restore();
  }

  void _paintObject(Canvas canvas, EditorObject object) {
    if (object is ShapeObject) {
      final paint = Paint()
        ..color = object.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      if (object.kind == EditorTool.ellipse) {
        canvas.drawOval(object.rect, paint);
      } else if (object.kind == EditorTool.blur) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(object.rect, const Radius.circular(4)),
          Paint()..color = Colors.white.withValues(alpha: .16),
        );
        canvas.drawRect(object.rect, paint..color = Colors.white54);
      } else {
        canvas.drawRect(object.rect, paint);
      }
    } else if (object is TextObject) {
      final painter = TextPainter(
        text: TextSpan(
          text: object.text,
          style: TextStyle(
            color: object.color,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, object.position);
    } else if (object is StrokeObject) {
      final paint = Paint()
        ..color = object.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      final path = Path()
        ..moveTo(object.points.first.dx, object.points.first.dy);
      for (final point in object.points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
      if (object.points.length == 2) {
        _paintArrowHead(canvas, object.points[0], object.points[1], paint);
      }
    }
  }

  void _paintPreview(Canvas canvas) {
    final a = start!;
    final b = current!;
    final paint = Paint()
      ..color = color.withValues(alpha: .9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    switch (tool) {
      case EditorTool.rectangle:
        canvas.drawRect(Rect.fromPoints(a, b), paint);
      case EditorTool.ellipse:
        canvas.drawOval(Rect.fromPoints(a, b), paint);
      case EditorTool.blur:
        canvas.drawRect(Rect.fromPoints(a, b), paint..color = Colors.white54);
      case EditorTool.arrow:
        canvas.drawLine(a, b, paint);
        _paintArrowHead(canvas, a, b, paint);
      case EditorTool.pencil:
        if (strokePoints.length > 1) {
          final path = Path()
            ..moveTo(strokePoints.first.dx, strokePoints.first.dy);
          for (final point in strokePoints.skip(1)) {
            path.lineTo(point.dx, point.dy);
          }
          canvas.drawPath(path, paint);
        }
      case EditorTool.select:
      case EditorTool.text:
        break;
    }
  }

  void _paintArrowHead(Canvas canvas, Offset from, Offset to, Paint paint) {
    final direction = to - from;
    if (direction.distance == 0) return;
    final angle = direction.direction;
    const length = 12.0;
    final path = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(
        to.dx - length * math.cos(angle - .5),
        to.dy - length * math.sin(angle - .5),
      )
      ..moveTo(to.dx, to.dy)
      ..lineTo(
        to.dx - length * math.cos(angle + .5),
        to.dy - length * math.sin(angle + .5),
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant DocumentPainter oldDelegate) =>
      oldDelegate.objects != objects ||
      oldDelegate.tool != tool ||
      oldDelegate.color != color ||
      oldDelegate.start != start ||
      oldDelegate.current != current ||
      oldDelegate.strokePoints != strokePoints ||
      oldDelegate.sourceImage != sourceImage ||
      oldDelegate.showGrid != showGrid;
}

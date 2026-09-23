import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:postcraft/src/rust/api.dart' as native_api;

import '../editor/domain/editor_document.dart';
import '../editor/presentation/editor_surface.dart';

/// Renders an [EditorDocument] to PNG bytes offscreen.
///
/// Shared by the editor's export/clipboard actions and by project autosave so
/// that thumbnails match the exported result. Blur and pixelate redaction is
/// recomputed from the source pixels through the native layer rather than
/// reused from the interactive preview.
class DocumentRenderer {
  const DocumentRenderer({
    this.redactionBlockSize = 12,
    this.blurRadius = 12,
  });

  final int redactionBlockSize;
  final int blurRadius;

  Future<Uint8List> renderPng(EditorDocument document) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(const Color(0xFF242833), BlendMode.src);
    ui.Image? redactedImage = document.sourceImage == null
        ? null
        : await _decodeImage(document.sourceImage!);
    final originalImage = redactedImage;
    try {
      for (final object in document.objects.whereType<ShapeObject>()) {
        if (redactedImage == null) continue;
        if (object.kind == EditorTool.blur) {
          redactedImage = await _applyBlur(
            document,
            object,
            redactedImage,
          );
        }
      }
      DocumentPainter(
        objects: document.objects
            .where(
              (object) =>
                  object is! ShapeObject || object.kind != EditorTool.blur,
            )
            .toList(),
        tool: EditorTool.select,
        color: const Color(0xFF8D7CFF),
        start: null,
        current: null,
        strokePoints: const [],
        sourceImage: redactedImage,
        documentWidth: document.width,
        documentHeight: document.height,
        showGrid: false,
      ).paint(
        canvas,
        Size(document.width.toDouble(), document.height.toDouble()),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(document.width, document.height);
      picture.dispose();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) {
        throw const FormatException('PNG rendering failed');
      }
      return data.buffer.asUint8List();
    } finally {
      if (redactedImage != null && !identical(redactedImage, originalImage)) {
        redactedImage.dispose();
      }
      originalImage?.dispose();
    }
  }

  Future<ui.Image> _applyBlur(
    EditorDocument document,
    ShapeObject object,
    ui.Image image,
  ) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) {
      throw const FormatException('Unable to read source pixels for blur');
    }
    final scale = image.width / document.width;
    final scaleY = image.height / document.height;
    final left = (object.rect.left * scale).floor().clamp(0, image.width - 1);
    final top = (object.rect.top * scaleY).floor().clamp(0, image.height - 1);
    final right = (object.rect.right * scale).ceil().clamp(
      left + 1,
      image.width,
    );
    final bottom = (object.rect.bottom * scaleY).ceil().clamp(
      top + 1,
      image.height,
    );
    final blurred = await native_api.blurRegionRgba(
      width: image.width,
      height: image.height,
      rgba: data.buffer.asUint8List(),
      left: left,
      top: top,
      regionWidth: right - left,
      regionHeight: bottom - top,
      radius: blurRadius,
    );
    final decoded = await _decodeRgba(
      blurred.rgba,
      blurred.width,
      blurred.height,
    );
    image.dispose();
    return decoded;
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, completer.complete);
    return completer.future;
  }

  Future<ui.Image> _decodeRgba(Uint8List rgba, int width, int height) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }
}

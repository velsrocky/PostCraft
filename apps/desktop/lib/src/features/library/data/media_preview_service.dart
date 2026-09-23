import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:postcraft/src/rust/api.dart' as native_api;

import '../domain/asset.dart';

class MediaPreview {
  const MediaPreview({required this.bytes, required this.width, required this.height});
  final Uint8List bytes;
  final int width;
  final int height;
}

/// Preview boundary for the library and timeline.
///
/// Image previews are decoded locally in the UI isolate. Video posters and
/// audio waveforms are generated through the native FFmpeg worker (via the
/// Rust media engine) and cached to disk so they remain available without
/// re-invoking FFmpeg on every list refresh.
class MediaPreviewService {
  const MediaPreviewService();

  static const _thumbWidth = 480;
  static const _waveformSamples = 128;

  Future<MediaPreview?> preview(Asset asset, String path) async {
    switch (asset.kind) {
      case AssetKind.image:
        return _imagePreview(path);
      case AssetKind.video:
        return _videoPreview(path);
      case AssetKind.audio:
        return _audioPreview(path);
      case AssetKind.other:
        return null;
    }
  }

  Future<MediaPreview?> _imagePreview(String path) async {
    final bytes = await _read(path);
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: _thumbWidth);
    final frame = await codec.getNextFrame();
    final width = frame.image.width;
    final height = frame.image.height;
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    codec.dispose();
    if (data == null) return null;
    return MediaPreview(
      bytes: data.buffer.asUint8List(),
      width: width,
      height: height,
    );
  }

  Future<MediaPreview?> _videoPreview(String path) async {
    try {
      final bytes = await native_api.generatePosterFrame(input: path, width: _thumbWidth);
      if (bytes.isEmpty) return null;
      final (width, height) = await decodeImageFromBytes(bytes);
      return MediaPreview(
        bytes: bytes,
        width: width,
        height: height,
      );
    } on Object {
      return null;
    }
  }

  Future<MediaPreview?> _audioPreview(String path) async {
    try {
      final waveform = await native_api.generateWaveformData(
        input: path,
        samples: BigInt.from(_waveformSamples),
      );
      if (waveform.isEmpty) return null;
      return _renderWaveform(waveform);
    } on Object {
      return null;
    }
  }

  /// Renders a waveform amplitude array as a small PNG image.
  Future<MediaPreview?> _renderWaveform(Float32List samples) async {
    const width = 240;
    const height = 60;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(const Color(0xFF20242D), ui.BlendMode.src);
    var max = 0.0;
    for (final s in samples) {
      final a = s.abs();
      if (a > max) max = a;
    }
    final paint = ui.Paint()..color = const Color(0xFF9B8CFF);
    final halfHeight = height / 2;
    final mid = max > 0 ? max : 1.0;
    final step = width / samples.length;
    final path = ui.Path();
    path.moveTo(0, halfHeight);
    for (var i = 0; i < samples.length; i++) {
      final x = i * step;
      final barHeight = (samples[i].abs() / mid) * halfHeight;
      path.lineTo(x, halfHeight - barHeight);
    }
    canvas.drawPath(
      path,
      paint..style = ui.PaintingStyle.stroke..strokeWidth = 2,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    picture.dispose();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return null;
    return MediaPreview(
      bytes: data.buffer.asUint8List(),
      width: width,
      height: height,
    );
  }

  Future<(int, int)> decodeImageFromBytes(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final result = (frame.image.width, frame.image.height);
    frame.image.dispose();
    codec.dispose();
    return result;
  }

  Future<Uint8List> _read(String path) async =>
      Uint8List.fromList(await File(path).readAsBytes());
}

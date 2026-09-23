import 'dart:typed_data';

enum CaptureMode { region, screen }

class CapturedImage {
  const CapturedImage({
    required this.bytes,
    required this.mode,
    required this.sourcePath,
  });

  final Uint8List bytes;
  final CaptureMode mode;
  final String sourcePath;
}

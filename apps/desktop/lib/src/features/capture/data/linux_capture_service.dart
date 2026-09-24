import 'dart:io';

import 'package:postcraft/src/rust/api.dart' as native_api;
import 'package:postcraft/src/rust/lib.dart';

import '../domain/capture_result.dart';

class LinuxCaptureService {
  const LinuxCaptureService();

  Future<PlatformCapabilities> capabilities() =>
      native_api.platformCapabilities();

  Future<CapturedImage> capture(CaptureMode mode, {String? targetId}) async {
    final result = await native_api.captureDesktop(
      mode: mode.name,
      targetId: targetId,
    );
    final file = File(result.path);
    if (!await file.exists()) {
      throw const FileSystemException('Capture returned a missing image file.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || !_hasPngSignature(bytes)) {
      throw const FileSystemException(
        'Capture backend returned an invalid PNG file.',
      );
    }
    return CapturedImage(bytes: bytes, mode: mode, sourcePath: result.path);
  }

  bool _hasPngSignature(List<int> bytes) =>
      bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A;
}

import 'dart:io';

import 'package:postcraft/src/rust/api.dart' as native_api;

import '../domain/capture_service.dart';

class PlatformRecordingService implements RecordingService {
  const PlatformRecordingService();

  @override
  Future<RecordingCapabilities> capabilities() async {
    try {
      final raw = await native_api.recordingCapabilities();
      final parts = raw.split('|');
      if (parts.length < 4) {
        return RecordingCapabilities(
          supported: false,
          microphone: false,
          systemAudio: false,
          reason: Platform.isLinux
              ? 'Linux recording requires an active X11 session and FFmpeg.'
              : 'Recording capability query returned an unexpected response.',
        );
      }
      return RecordingCapabilities(
        supported: parts[0] == 'true',
        microphone: parts[1] == 'true',
        systemAudio: parts[2] == 'true',
        reason: parts.sublist(3).join('|'),
      );
    } on Object catch (error) {
      return RecordingCapabilities(
        supported: false,
        microphone: false,
        systemAudio: false,
        reason: 'Recording backend unavailable: $error',
      );
    }
  }

  @override
  Future<RecordingSession> start(RecordingRequest request) async {
    final output = await _defaultOutputPath();
    final raw = await native_api.startRecordingSession(
      output: output,
      width: 1920,
      height: 1080,
      fps: 30,
      includeMicrophone: request.includeMicrophone,
      includeSystemAudio: request.includeSystemAudio,
    );
    final parts = raw.split('|');
    if (parts.length < 2) {
      throw StateError('Recording backend returned an unexpected session.');
    }
    return RecordingSession(id: parts[0], outputPath: parts.sublist(1).join('|'));
  }

  @override
  Future<void> stop(String sessionId) async {
    final id = int.tryParse(sessionId);
    if (id == null) {
      throw StateError('Invalid recording session id.');
    }
    await native_api.stopRecording(id: id);
  }

  @override
  Future<void> cancel(String sessionId) async {
    final id = int.tryParse(sessionId);
    if (id == null) {
      throw StateError('Invalid recording session id.');
    }
    await native_api.cancelRecording(id: id);
  }

  Future<String> _defaultOutputPath() async {
    final dir = Directory.systemTemp.createTempSync('postcraft-recording-');
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return '${dir.path}${Platform.pathSeparator}recording-$stamp.mp4';
  }
}

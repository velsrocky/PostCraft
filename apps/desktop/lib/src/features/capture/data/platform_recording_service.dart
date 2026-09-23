import 'dart:io';

import '../domain/capture_service.dart';

class PlatformRecordingService implements RecordingService {
  const PlatformRecordingService();

  @override
  Future<RecordingCapabilities> capabilities() async {
    if (Platform.isLinux) {
      return const RecordingCapabilities(
        supported: false,
        microphone: false,
        systemAudio: false,
        reason: 'Linux recording requires an active X11 or ScreenCast portal session.',
      );
    }
    if (Platform.isWindows) {
      return const RecordingCapabilities(
        supported: false,
        microphone: false,
        systemAudio: false,
        reason: 'Windows Graphics Capture backend is not linked in this build.',
      );
    }
    if (Platform.isMacOS) {
      return const RecordingCapabilities(
        supported: false,
        microphone: false,
        systemAudio: false,
        reason: 'macOS ScreenCaptureKit backend is not linked in this build.',
      );
    }
    return const RecordingCapabilities(
      supported: false,
      microphone: false,
      systemAudio: false,
      reason: 'No recording backend exists for this platform.',
    );
  }

  @override
  Future<RecordingSession> start(RecordingRequest request) => Future.error(
    StateError('Recording backend is unavailable on this platform.'),
  );

  @override
  Future<void> stop(String sessionId) => Future.error(
    StateError('No recording session is active.'),
  );

  @override
  Future<void> cancel(String sessionId) => Future.error(
    StateError('No recording session is active.'),
  );
}

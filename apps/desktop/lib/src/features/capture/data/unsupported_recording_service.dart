import '../domain/capture_service.dart';

class UnsupportedRecordingService implements RecordingService {
  const UnsupportedRecordingService();

  @override
  Future<RecordingCapabilities> capabilities() async => const RecordingCapabilities(
    supported: false,
    microphone: false,
    systemAudio: false,
    reason: 'Screen recording is not implemented for this platform yet.',
  );

  @override
  Future<RecordingSession> start(RecordingRequest request) => Future.error(
    StateError('Screen recording is unavailable on this platform.'),
  );

  @override
  Future<void> stop(String sessionId) => Future.error(StateError('No recording session is active.'));

  @override
  Future<void> cancel(String sessionId) => Future.error(StateError('No recording session is active.'));
}

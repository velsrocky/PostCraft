import 'capture_result.dart';
import '../../../rust/lib.dart';

enum CaptureTargetKind { region, display, allDisplays, window }

class CaptureCapability {
  const CaptureCapability({required this.supported, required this.reason});
  final bool supported;
  final String reason;
}

abstract interface class CaptureService {
  Future<PlatformCapabilities> capabilities();
  Future<CapturedImage> capture(CaptureMode mode, {String? targetId});
}

abstract interface class RecordingService {
  Future<RecordingCapabilities> capabilities();
  Future<RecordingSession> start(RecordingRequest request);
  Future<void> stop(String sessionId);
  Future<void> cancel(String sessionId);
}

class RecordingCapabilities {
  const RecordingCapabilities({
    required this.supported,
    required this.microphone,
    required this.systemAudio,
    required this.reason,
  });

  final bool supported;
  final bool microphone;
  final bool systemAudio;
  final String reason;
}

class RecordingRequest {
  const RecordingRequest({required this.target, this.includeMicrophone = false, this.includeSystemAudio = false});
  final CaptureTargetKind target;
  final bool includeMicrophone;
  final bool includeSystemAudio;
}

class RecordingSession {
  const RecordingSession({required this.id, required this.outputPath});
  final String id;
  final String outputPath;
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postcraft/src/rust/lib.dart';

import '../data/linux_capture_service.dart';
import '../data/platform_recording_service.dart';
import '../data/linux_window_handle_service.dart';
import '../domain/capture_service.dart';
import 'dart:convert';
import '../../../rust/api.dart' as native_api;

class CaptureTargetReport {
  const CaptureTargetReport({required this.reason, required this.targets, required this.windowCapture, required this.multiDisplay, required this.microphone, required this.systemAudio});
  final String reason;
  final List<Map<String, Object?>> targets;
  final bool windowCapture;
  final bool multiDisplay;
  final bool microphone;
  final bool systemAudio;

  factory CaptureTargetReport.fromJson(String raw) {
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return CaptureTargetReport(
      reason: json['reason'] as String? ?? 'Unknown capture target state.',
      targets: (json['targets'] as List?)?.whereType<Map<String, Object?>>().toList() ?? const [],
      windowCapture: json['window_capture'] as bool? ?? false,
      multiDisplay: json['multi_display'] as bool? ?? false,
      microphone: json['microphone'] as bool? ?? false,
      systemAudio: json['system_audio'] as bool? ?? false,
    );
  }
}

final linuxCaptureServiceProvider = Provider<LinuxCaptureService>(
  (ref) => const LinuxCaptureService(),
);

final recordingServiceProvider = Provider<RecordingService>(
  (ref) => const PlatformRecordingService(),
);

final recordingCapabilitiesProvider = FutureProvider<RecordingCapabilities>(
  (ref) => ref.watch(recordingServiceProvider).capabilities(),
);

final linuxWindowHandleServiceProvider = Provider<LinuxWindowHandleService>(
  (ref) => const LinuxWindowHandleService(),
);

final waylandScreenCastStarterProvider = Provider<Future<Map<String, dynamic>> Function(String)>(
  (ref) => (sessionHandle) => ref
      .read(linuxWindowHandleServiceProvider)
      .startWaylandSession(sessionHandle: sessionHandle),
);

final captureCapabilitiesProvider = FutureProvider<PlatformCapabilities>((
  ref,
) async {
  try {
    return await ref.watch(linuxCaptureServiceProvider).capabilities();
  } on Object {
    return const PlatformCapabilities(
      desktopCapture: false,
      windowCapture: false,
      systemAudioCapture: false,
      globalShortcuts: false,
      clipboardImageWrite: false,
      waylandScreencast: false,
      microphoneCapture: false,
      captureReason: 'Could not query native capture capabilities.',
    );
  }
});

final captureTargetReportProvider = FutureProvider<CaptureTargetReport>((ref) async {
  return CaptureTargetReport.fromJson(await native_api.captureTargetReport());
});

final waylandScreencastPreparationProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final raw = await native_api.prepareWaylandScreencast(
    includeMicrophone: false,
    includeSystemAudio: false,
  );
  return jsonDecode(raw) as Map<String, dynamic>;
});

final pipewireTransportProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return jsonDecode(await native_api.inspectPipewireTransport()) as Map<String, dynamic>;
});

final authorizedPipewireStreamProbeProvider = Provider<Future<Map<String, dynamic>> Function(int)>(
  (ref) => (nodeId) async => jsonDecode(
    await native_api.probeAuthorizedPipewireStream(nodeId: nodeId),
  ) as Map<String, dynamic>,
);

final authorizedPipewireRecorderProvider = Provider<Future<BigInt> Function({
  required int nodeId,
  required int width,
  required int height,
  required int fps,
  required String pixelFormat,
  required String output,
  required int durationMs,
})>((ref) => ({
  required int nodeId,
  required int width,
  required int height,
  required int fps,
  required String pixelFormat,
  required String output,
  required int durationMs,
}) => native_api.recordAuthorizedPipewireStream(
  nodeId: nodeId,
  width: width,
  height: height,
  fps: fps,
  pixelFormat: pixelFormat,
  output: output,
  durationMs: BigInt.from(durationMs),
));

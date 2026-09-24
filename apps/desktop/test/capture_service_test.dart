import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:postcraft/src/features/capture/data/linux_capture_service.dart';
import 'package:postcraft/src/features/capture/domain/capture_result.dart';
import 'package:postcraft/src/rust/frb_generated.dart';
import 'package:postcraft/src/rust/lib.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'capture service verifies PNG data and retains the portal-owned file',
    () async {
      final file = File(
        '${Directory.systemTemp.path}/postcraft-capture-test.png',
      );
      await file.writeAsBytes([137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3]);
      PostCraftRust.initMock(api: _FakeCaptureApi(file.path));
      addTearDown(() async {
        PostCraftRust.dispose();
        if (await file.exists()) await file.delete();
      });

      final captured = await const LinuxCaptureService().capture(
        CaptureMode.screen,
      );

      expect(captured.mode, CaptureMode.screen);
      expect(captured.bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect(await file.exists(), isTrue);
    },
  );

  test(
    'capture service rejects non-PNG without deleting portal-owned files',
    () async {
      final file = File(
        '${Directory.systemTemp.path}/postcraft-capture-invalid.png',
      );
      await file.writeAsBytes([1, 2, 3, 4]);
      PostCraftRust.initMock(api: _FakeCaptureApi(file.path));
      addTearDown(() async {
        PostCraftRust.dispose();
        if (await file.exists()) await file.delete();
      });

      await expectLater(
        const LinuxCaptureService().capture(CaptureMode.region),
        throwsA(isA<FileSystemException>()),
      );
      expect(await file.exists(), isTrue);
    },
  );
}

class _FakeCaptureApi extends PostCraftRustApi {
  _FakeCaptureApi(this.path);
  final String path;

  @override
  Future<String> crateApiCaptureTargetReport() async =>
      '{"targets":[],"window_capture":false,"multi_display":false,"microphone":false,"system_audio":false,"reason":"test"}';

  @override
  Future<String> crateApiPrepareWaylandScreencast({
    required bool includeMicrophone,
    required bool includeSystemAudio,
  }) async => '{"supported":false,"started":false,"reason":"test"}';

  @override
  Future<String> crateApiStartWaylandScreencast({
    required String sessionHandle,
    required String parentWindow,
  }) async => '{"started":false,"reason":"test"}';

  @override
  Future<String> crateApiInspectPipewireTransport() async =>
      '{"connected":false,"reason":"test","node_ids":[]}';

  @override
  Future<String> crateApiProbeAuthorizedPipewireStream({required int nodeId}) async =>
      '{"node_id":$nodeId,"connected":false,"streaming":false,"frames_received":0,"last_buffer_bytes":0,"reason":"test"}';

  @override
  Future<BigInt> crateApiRecordAuthorizedPipewireStream({
    required int nodeId,
    required int width,
    required int height,
    required int fps,
    required String pixelFormat,
    required String output,
    required BigInt durationMs,
  }) async => BigInt.zero;

  @override
  Future<String> crateApiRecordingCapabilities() async => 'false|false|false|test';

  @override
  Future<int> crateApiStartTimelineRenderSession({
    required List<String> inputs,
    required List<String> kinds,
    required List<String> sourceInUs,
    required List<String> sourceOutUs,
    required List<String> volumes,
    required String output,
    required String container,
    int? crf,
  }) async => throw UnimplementedError();

  @override
  Future<String?> crateApiPollRenderSession({required int id}) async => null;

  @override
  Future<bool> crateApiCancelRecording({required int id}) async => false;

  @override
  Future<String> crateApiStartRecordingSession({
    required String output,
    required int width,
    required int height,
    required int fps,
    required bool includeMicrophone,
    required bool includeSystemAudio,
  }) async => throw UnimplementedError();

  @override
  Future<String> crateApiStopRecording({required int id}) async => throw UnimplementedError();

  @override
  Future<CaptureResult> crateApiCaptureDesktop({
    required String mode,
    String? targetId,
  }) async =>
      CaptureResult(path: path, mode: mode);

  @override
  Future<String> crateApiMediaStatus() async =>
      '{"available":false,"message":"test"}';

  @override
  Future<void> crateApiInstallPanicHook({required String logPath}) async {}

  @override
  Future<bool> crateApiGlobalShortcutsSupported() async => false;

  @override
  Future<GlobalShortcutStatus> crateApiStartGlobalShortcuts({
    required List<ShortcutBinding> bindings,
  }) async => throw UnimplementedError();

  @override
  Future<String?> crateApiPollGlobalShortcut() async => null;

  @override
  Future<void> crateApiStopGlobalShortcuts() async {}

  @override
  Future<RuntimeInfo> crateApiRuntimeInfo() async =>
      const RuntimeInfo(version: 'test', platform: 'linux');

  @override
  Future<PlatformCapabilities> crateApiPlatformCapabilities() async =>
      const PlatformCapabilities(
        desktopCapture: true,
        windowCapture: false,
        systemAudioCapture: false,
        globalShortcuts: false,
        clipboardImageWrite: false,
        waylandScreencast: false,
        microphoneCapture: false,
        captureReason: 'test',
      );

  @override
  Future<ImageOperationResult> crateApiPixelateRgba({
    required int width,
    required int height,
    required List<int> rgba,
    required int blockSize,
  }) => throw UnimplementedError();

  @override
  Future<ImageOperationResult> crateApiPixelateRegionRgba({
    required int width,
    required int height,
    required List<int> rgba,
    required int left,
    required int top,
    required int regionWidth,
    required int regionHeight,
    required int blockSize,
  }) => throw UnimplementedError();

  @override
  Future<ImageOperationResult> crateApiBlurRegionRgba({
    required int width,
    required int height,
    required List<int> rgba,
    required int left,
    required int top,
    required int regionWidth,
    required int regionHeight,
    required int radius,
  }) => throw UnimplementedError();

  @override
  Future<Uint8List> crateApiGeneratePosterFrame({
    required String input,
    required int width,
  }) => throw UnimplementedError();

  @override
  Future<Float32List> crateApiGenerateWaveformData({
    required String input,
    required BigInt samples,
  }) => throw UnimplementedError();

  @override
  Future<String> crateApiProbeMediaFile({required String input}) =>
      throw UnimplementedError();
}

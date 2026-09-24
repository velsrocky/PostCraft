import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../rust/api.dart' as native_api;
import '../../../rust/lib.dart';
import '../../capture/domain/capture_service.dart';

final runtimeInfoProvider = FutureProvider<RuntimeInfo>(
  (ref) => native_api.runtimeInfo(),
);

final nativeRecordingCapabilitiesProvider =
    FutureProvider<RecordingCapabilities>((ref) async {
      final raw = await native_api.recordingCapabilities();
      final parts = raw.split('|');
      if (parts.length < 4) {
        return const RecordingCapabilities(
          supported: false,
          microphone: false,
          systemAudio: false,
          reason: 'Recording capability query returned an unexpected response.',
        );
      }
      return RecordingCapabilities(
        supported: parts[0] == 'true',
        microphone: parts[1] == 'true',
        systemAudio: parts[2] == 'true',
        reason: parts.sublist(3).join('|'),
      );
    });

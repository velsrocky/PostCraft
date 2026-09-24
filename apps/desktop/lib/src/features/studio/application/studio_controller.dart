import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_paths.dart';
import '../../editor/application/editor_controller.dart';
import '../../library/application/library_providers.dart';
import '../../../rust/api.dart' as native_api;
import '../domain/timeline.dart';

final studioRenderingProvider = NotifierProvider<StudioRenderingController, bool>(
  StudioRenderingController.new,
);

class StudioRenderingController extends Notifier<bool> {
  @override
  bool build() => false;
}

final studioControllerProvider = NotifierProvider<StudioController, Timeline>(
  StudioController.new,
);

class StudioController extends Notifier<Timeline> {
  @override
  Timeline build() => ref.watch(editorControllerProvider).document.timeline;

  Future<void> addClip({
    required String assetId,
    TimelineClipKind kind = TimelineClipKind.video,
  }) async {
    final track = state.tracks.isEmpty
        ? const TimelineTrack(id: 'track-1')
        : state.tracks.first;
    final startUs = track.durationUs;
    final durationUs = await _probeDuration(assetId, kind);
    final clip = TimelineClip(
      id: 'clip-${DateTime.now().microsecondsSinceEpoch}',
      assetId: assetId,
      kind: kind,
      startUs: startUs,
      sourceInUs: 0,
      sourceOutUs: durationUs,
    );
    _commit(Timeline(tracks: [
      TimelineTrack(id: track.id, name: track.name, clips: [...track.clips, clip]),
    ]));
  }

  Future<int> _probeDuration(String assetId, TimelineClipKind kind) async {
    if (kind == TimelineClipKind.image) {
      // Images loop in FFmpeg timelines; use a sensible default duration.
      return 5 * 1000000;
    }
    try {
      final repository = await ref.read(assetRepositoryProvider.future);
      final path = await repository.filePath(assetId);
      if (path == null) return 10 * 1000000;
      final raw = await native_api.probeMediaFile(input: path);
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final durationUs = (decoded['duration_us'] as num?)?.toInt() ?? 0;
      return durationUs > 0 ? durationUs : 10 * 1000000;
    } on Object {
      return 10 * 1000000;
    }
  }

  void removeClip(String clipId) {
    final tracks = state.tracks
        .map((track) => TimelineTrack(
              id: track.id,
              name: track.name,
              clips: track.clips.where((clip) => clip.id != clipId).toList(),
            ))
        .where((track) => track.clips.isNotEmpty)
        .toList();
    _commit(Timeline(tracks: tracks));
  }

  void trimClip(String clipId, {required int sourceInUs, required int sourceOutUs}) {
    if (sourceInUs < 0 || sourceOutUs <= sourceInUs) {
      throw ArgumentError('Trim range must satisfy 0 <= sourceInUs < sourceOutUs.');
    }
    var found = false;
    final tracks = state.tracks.map((track) {
      final clips = track.clips.map((clip) {
        if (clip.id != clipId) return clip;
        found = true;
        return clip.copyWith(sourceInUs: sourceInUs, sourceOutUs: sourceOutUs);
      }).toList();
      return TimelineTrack(id: track.id, name: track.name, clips: clips);
    }).toList();
    if (!found) return;
    _commit(Timeline(tracks: tracks));
  }

  void splitClip(String clipId, int atUs) {
    var found = false;
    final tracks = <TimelineTrack>[];
    for (final track in state.tracks) {
      final clips = <TimelineClip>[];
      for (final clip in track.clips) {
        if (clip.id != clipId) {
          clips.add(clip);
          continue;
        }
        if (atUs <= clip.sourceInUs || atUs >= clip.sourceOutUs) {
          throw ArgumentError('Split point must be strictly inside the clip source range.');
        }
        found = true;
        final first = clip.copyWith(sourceOutUs: atUs);
        final second = TimelineClip(
          id: 'clip-${DateTime.now().microsecondsSinceEpoch}-${clip.id}',
          assetId: clip.assetId,
          kind: clip.kind,
          startUs: clip.startUs + (atUs - clip.sourceInUs),
          sourceInUs: atUs,
          sourceOutUs: clip.sourceOutUs,
          volume: clip.volume,
        );
        clips.add(first);
        clips.add(second);
      }
      tracks.add(TimelineTrack(id: track.id, name: track.name, clips: clips));
    }
    if (!found) return;
    _commit(Timeline(tracks: tracks));
  }

  Future<String> render() async {
    if (state.isEmpty) throw StateError('Add a video clip before rendering.');
    final repository = await ref.read(assetRepositoryProvider.future);
    final inputs = <String>[];
    final starts = <int>[];
    final ends = <int>[];
    final kinds = <String>[];
    final volumes = <String>[];
    for (final track in state.tracks) {
      for (final clip in track.clips) {
        final path = await repository.filePath(clip.assetId);
        if (path == null) throw StateError('Timeline asset ${clip.assetId} is unavailable.');
        inputs.add(path);
        starts.add(clip.sourceInUs);
        ends.add(clip.sourceOutUs);
        kinds.add(clip.kind.name);
        volumes.add((clip.volume * 1000).round().toString());
      }
    }
    final paths = await ref.read(appPathsProvider.future);
    final output = '${paths.cache.path}/studio-${DateTime.now().microsecondsSinceEpoch}.mp4';
    ref.read(studioRenderingProvider.notifier).state = true;
    try {
      final jobId = await native_api.startTimelineRenderSession(
        inputs: inputs,
        kinds: kinds,
        sourceInUs: starts.map((value) => value.toString()).toList(),
        sourceOutUs: ends.map((value) => value.toString()).toList(),
        volumes: volumes,
        output: output,
        container: 'mp4',
        crf: null,
      );
      while (true) {
        final status = await native_api.pollRenderSession(id: jobId);
        if (status == null) throw StateError('Render job disappeared.');
        final parts = status.split('|');
        final stateName = parts.first.toLowerCase();
        if (stateName == 'succeeded') break;
        if (stateName == 'failed') throw StateError(parts.length > 1 ? parts[1] : 'FFmpeg render failed.');
        if (stateName == 'cancelled') throw StateError('Render cancelled.');
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final bytes = await File(output).readAsBytes();
      final asset = await ref.read(assetIngestorProvider).add(
        bytes: bytes,
        fileName: 'PostCraft render.mp4',
        name: 'Rendered timeline',
      );
      return asset.id;
    } finally {
      ref.read(studioRenderingProvider.notifier).state = false;
    }
  }

  void _commit(Timeline timeline) {
    state = timeline;
    ref.read(editorControllerProvider.notifier).replaceTimeline(timeline);
  }
}

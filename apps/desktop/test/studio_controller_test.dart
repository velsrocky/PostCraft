import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postcraft/src/features/editor/application/editor_controller.dart';
import 'package:postcraft/src/features/editor/domain/editor_document.dart';
import 'package:postcraft/src/features/studio/application/studio_controller.dart';
import 'package:postcraft/src/features/studio/domain/timeline.dart';

void main() {
  ProviderContainer makeContainerWithClip({int startUs = 0, int sourceInUs = 0, int sourceOutUs = 4000000}) {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(editorControllerProvider.notifier).replaceDocument(
      const EditorDocument(
        timeline: Timeline(
          tracks: [
            TimelineTrack(
              id: 'track-1',
              clips: [
                TimelineClip(
                  id: 'clip-1',
                  assetId: 'asset-1',
                  kind: TimelineClipKind.video,
                  startUs: 0,
                  sourceInUs: 0,
                  sourceOutUs: 4000000,
                  fadeInUs: 250000,
                  fadeOutUs: 250000,
                ),
              ],
            ),
          ],
        ),
      ).copyWithTrack(startUs: startUs, sourceInUs: sourceInUs, sourceOutUs: sourceOutUs),
    );
    return container;
  }

  test('splitClip divides a clip into two adjacent halves', () {
    final container = makeContainerWithClip();
    final controller = container.read(studioControllerProvider.notifier);

    controller.splitClip('clip-1', 2000000);

    final clips = container.read(studioControllerProvider).tracks.single.clips;
    expect(clips, hasLength(2));
    final first = clips[0];
    final second = clips[1];
    expect(first.sourceInUs, 0);
    expect(first.sourceOutUs, 2000000);
    expect(first.startUs, 0);
    expect(first.fadeInUs, 250000);
    expect(first.fadeOutUs, 250000);
    expect(second.sourceInUs, 2000000);
    expect(second.sourceOutUs, 4000000);
    expect(second.startUs, 2000000);
    expect(second.assetId, 'asset-1');
    expect(second.kind, TimelineClipKind.video);
    expect(second.fadeInUs, 0);
    expect(second.fadeOutUs, 0);
    expect(second.id, isNot(first.id));
  });

  test('splitClip preserves layout when the source is already trimmed', () {
    final container = makeContainerWithClip(startUs: 500000, sourceInUs: 1000000, sourceOutUs: 3000000);
    final controller = container.read(studioControllerProvider.notifier);

    controller.splitClip('clip-1', 2000000);

    final clips = container.read(studioControllerProvider).tracks.single.clips;
    expect(clips, hasLength(2));
    expect(clips[0].startUs, 500000);
    expect(clips[0].sourceInUs, 1000000);
    expect(clips[0].sourceOutUs, 2000000);
    expect(clips[1].startUs, 1500000);
    expect(clips[1].sourceInUs, 2000000);
    expect(clips[1].sourceOutUs, 3000000);
  });

  test('splitClip rejects points outside the source range', () {
    final container = makeContainerWithClip();
    final controller = container.read(studioControllerProvider.notifier);

    expect(() => controller.splitClip('clip-1', 0), throwsArgumentError);
    expect(() => controller.splitClip('clip-1', 4000000), throwsArgumentError);
    expect(() => controller.splitClip('missing', 2000000), returnsNormally);
    expect(container.read(studioControllerProvider).tracks.single.clips, hasLength(1));
  });

  test('trimClip updates the source range in place', () {
    final container = makeContainerWithClip();
    final controller = container.read(studioControllerProvider.notifier);

    controller.trimClip('clip-1', sourceInUs: 500000, sourceOutUs: 3500000);

    final clip = container.read(studioControllerProvider).tracks.single.clips.single;
    expect(clip.sourceInUs, 500000);
    expect(clip.sourceOutUs, 3500000);
    expect(clip.startUs, 0);
  });

  test('trimClip rejects an empty or inverted range', () {
    final container = makeContainerWithClip();
    final controller = container.read(studioControllerProvider.notifier);

    expect(
      () => controller.trimClip('clip-1', sourceInUs: 2000000, sourceOutUs: 1000000),
      throwsArgumentError,
    );
    expect(
      () => controller.trimClip('clip-1', sourceInUs: -1, sourceOutUs: 1000000),
      throwsArgumentError,
    );
  });
}

extension on EditorDocument {
  EditorDocument copyWithTrack({
    required int startUs,
    required int sourceInUs,
    required int sourceOutUs,
  }) {
    final clip = timeline.tracks.single.clips.single;
    return withTimeline(
      Timeline(
        tracks: [
          TimelineTrack(
            id: 'track-1',
            clips: [
              clip.copyWith(
                startUs: startUs,
                sourceInUs: sourceInUs,
                sourceOutUs: sourceOutUs,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

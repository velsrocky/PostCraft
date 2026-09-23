import 'package:flutter_test/flutter_test.dart';
import 'package:postcraft/src/features/editor/domain/editor_document.dart';
import 'package:postcraft/src/features/studio/domain/timeline.dart';
import 'package:postcraft/src/features/projects/data/project_bundle_codec.dart';

void main() {
  test('timeline survives document JSON and project bundle round trips', () {
    const timeline = Timeline(
      tracks: [
        TimelineTrack(
          id: 'track-1',
          clips: [
            TimelineClip(
              id: 'clip-1',
              assetId: 'asset-1',
              kind: TimelineClipKind.video,
              startUs: 0,
              sourceInUs: 500000,
              sourceOutUs: 2500000,
            ),
          ],
        ),
      ],
    );
    const document = EditorDocument(width: 320, height: 180, timeline: timeline);
    final restored = EditorDocument.fromJson(document.toJson());

    expect(restored.timeline.durationUs, 2000000);
    expect(restored.timeline.tracks.single.clips.single.assetId, 'asset-1');

    final bundle = ProjectBundleCodec.encode(document);
    final fromBundle = ProjectBundleCodec.decode(bundle);
    expect(fromBundle.timeline.tracks.single.clips.single.sourceInUs, 500000);
  });
}

enum TimelineClipKind { video, image, audio }

TimelineClipKind timelineClipKindFromName(String? value) =>
    TimelineClipKind.values.firstWhere(
      (kind) => kind.name == value,
      orElse: () => TimelineClipKind.video,
    );

class TimelineClip {
  const TimelineClip({
    required this.id,
    required this.assetId,
    required this.kind,
    required this.startUs,
    required this.sourceInUs,
    required this.sourceOutUs,
    this.volume = 1,
    this.fadeInUs = 0,
    this.fadeOutUs = 0,
  });

  final String id;
  final String assetId;
  final TimelineClipKind kind;
  final int startUs;
  final int sourceInUs;
  final int sourceOutUs;
  final double volume;
  final int fadeInUs;
  final int fadeOutUs;

  int get durationUs => sourceOutUs - sourceInUs;
  int get endUs => startUs + durationUs;

  TimelineClip copyWith({
    int? startUs,
    int? sourceInUs,
    int? sourceOutUs,
    double? volume,
    int? fadeInUs,
    int? fadeOutUs,
  }) => TimelineClip(
    id: id,
    assetId: assetId,
    kind: kind,
    startUs: startUs ?? this.startUs,
    sourceInUs: sourceInUs ?? this.sourceInUs,
    sourceOutUs: sourceOutUs ?? this.sourceOutUs,
    volume: volume ?? this.volume,
    fadeInUs: fadeInUs ?? this.fadeInUs,
    fadeOutUs: fadeOutUs ?? this.fadeOutUs,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'assetId': assetId,
    'kind': kind.name,
    'startUs': startUs,
    'sourceInUs': sourceInUs,
    'sourceOutUs': sourceOutUs,
    'volume': volume,
    'fadeInUs': fadeInUs,
    'fadeOutUs': fadeOutUs,
  };

  static TimelineClip? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, Object?>.from(raw);
    final id = map['id'];
    final assetId = map['assetId'];
    if (id is! String || assetId is! String) return null;
    final start = _int(map['startUs']);
    final sourceIn = _int(map['sourceInUs']);
    final sourceOut = _int(map['sourceOutUs']);
    if (start < 0 || sourceIn < 0 || sourceOut <= sourceIn) return null;
    return TimelineClip(
      id: id,
      assetId: assetId,
      kind: timelineClipKindFromName(map['kind'] as String?),
      startUs: start,
      sourceInUs: sourceIn,
      sourceOutUs: sourceOut,
      volume: _double(map['volume'], 1),
      fadeInUs: _int(map['fadeInUs']),
      fadeOutUs: _int(map['fadeOutUs']),
    );
  }
}

class TimelineTrack {
  const TimelineTrack({required this.id, this.name = 'Track 1', this.clips = const []});

  final String id;
  final String name;
  final List<TimelineClip> clips;

  int get durationUs => clips.fold(0, (max, clip) => clip.endUs > max ? clip.endUs : max);

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'clips': clips.map((clip) => clip.toJson()).toList(),
  };

  static TimelineTrack? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, Object?>.from(raw);
    final id = map['id'];
    if (id is! String) return null;
    final clips = (map['clips'] as List?)
        ?.map(TimelineClip.fromJson)
        .whereType<TimelineClip>()
        .toList(growable: false) ?? const <TimelineClip>[];
    return TimelineTrack(id: id, name: map['name'] as String? ?? 'Track 1', clips: clips);
  }
}

class Timeline {
  const Timeline({this.tracks = const []});
  final List<TimelineTrack> tracks;

  bool get isEmpty => tracks.every((track) => track.clips.isEmpty);
  int get durationUs => tracks.fold(0, (max, track) => track.durationUs > max ? track.durationUs : max);

  Map<String, Object?> toJson() => {'tracks': tracks.map((track) => track.toJson()).toList()};

  static Timeline fromJson(Object? raw) {
    if (raw is! Map) return const Timeline();
    final tracks = (raw['tracks'] as List?)
        ?.map(TimelineTrack.fromJson)
        .whereType<TimelineTrack>()
        .toList(growable: false) ?? const <TimelineTrack>[];
    return Timeline(tracks: tracks);
  }
}

int _int(Object? value) => value is int ? value : value is num ? value.toInt() : 0;
double _double(Object? value, double fallback) => value is num ? value.toDouble() : fallback;

import 'dart:convert';

enum AssetKind { image, video, audio, other }

AssetKind assetKindForExtension(String extension) {
  switch (extension.toLowerCase()) {
    case 'png':
    case 'jpg':
    case 'jpeg':
    case 'webp':
    case 'gif':
    case 'bmp':
    case 'tiff':
    case 'avif':
      return AssetKind.image;
    case 'mp4':
    case 'mov':
    case 'webm':
    case 'mkv':
    case 'avi':
      return AssetKind.video;
    case 'mp3':
    case 'wav':
    case 'm4a':
    case 'aac':
    case 'flac':
    case 'ogg':
      return AssetKind.audio;
    default:
      return AssetKind.other;
  }
}

/// A media file (capture, import, or generated) tracked by the library.
///
/// Bytes are stored content-addressed; the model holds only lightweight,
/// indexable metadata so the grid/search can be served without reading media.
class Asset {
  const Asset({
    required this.id,
    required this.name,
    required this.storedFileName,
    required this.kind,
    required this.contentHash,
    required this.byteSize,
    required this.createdAt,
    this.tags = const [],
  });

  final String id;
  final String name;
  final String storedFileName;
  final AssetKind kind;
  final String contentHash;
  final int byteSize;
  final DateTime createdAt;
  final List<String> tags;

  Asset copyWith({String? name, List<String>? tags}) => Asset(
    id: id,
    name: name ?? this.name,
    storedFileName: storedFileName,
    kind: kind,
    contentHash: contentHash,
    byteSize: byteSize,
    createdAt: createdAt,
    tags: tags ?? this.tags,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'storedFileName': storedFileName,
    'kind': kind.name,
    'contentHash': contentHash,
    'byteSize': byteSize,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'tags': tags,
  };

  static Asset? fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final name = json['name'];
    final stored = json['storedFileName'];
    final hash = json['contentHash'];
    final created = json['createdAt'];
    if (id is! String ||
        name is! String ||
        stored is! String ||
        hash is! String ||
        created is! String) {
      return null;
    }
    final createdAt = DateTime.tryParse(created);
    if (createdAt == null) return null;
    final kindName = json['kind'];
    return Asset(
      id: id,
      name: name,
      storedFileName: stored,
      kind: AssetKind.values.firstWhere(
        (k) => k.name == kindName,
        orElse: () => AssetKind.other,
      ),
      contentHash: hash,
      byteSize: json['byteSize'] is int ? json['byteSize']! as int : 0,
      createdAt: createdAt,
      tags: (json['tags'] as List?)?.whereType<String>().toList() ?? const [],
    );
  }

  static String encodeIndex(List<Asset> assets) =>
      jsonEncode(assets.map((a) => a.toJson()).toList());

  static List<Asset> decodeIndex(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((e) => Asset.fromJson(Map<String, Object?>.from(e)))
        .whereType<Asset>()
        .toList();
  }
}

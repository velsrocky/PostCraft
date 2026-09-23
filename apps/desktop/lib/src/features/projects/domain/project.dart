/// A locally stored PostCraft project.
///
/// Metadata lives in a small `meta.json` inside the project directory so the
/// recents list can be read without decoding every bundle. The editable
/// document is stored separately as a `.postcraft` bundle.
class Project {
  const Project({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.width,
    required this.height,
    required this.layerCount,
    required this.directoryPath,
    this.hasUnsavedDraft = false,
    this.thumbnailPath,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int width;
  final int height;
  final int layerCount;
  final String directoryPath;
  final bool hasUnsavedDraft;
  final String? thumbnailPath;

  String get bundlePath => '$directoryPath/project.postcraft';
  String get draftPath => '$directoryPath/project.postcraft.draft';

  Project copyWith({
    String? name,
    DateTime? updatedAt,
    int? width,
    int? height,
    int? layerCount,
    bool? hasUnsavedDraft,
    String? thumbnailPath,
  }) => Project(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    width: width ?? this.width,
    height: height ?? this.height,
    layerCount: layerCount ?? this.layerCount,
    directoryPath: directoryPath,
    hasUnsavedDraft: hasUnsavedDraft ?? this.hasUnsavedDraft,
    thumbnailPath: thumbnailPath ?? this.thumbnailPath,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'width': width,
    'height': height,
    'layerCount': layerCount,
    if (thumbnailPath != null) 'thumbnailPath': thumbnailPath,
  };

  static Project? fromJson(
    Map<String, Object?> json, {
    required String directoryPath,
  }) {
    final id = json['id'];
    final name = json['name'];
    final created = json['createdAt'];
    final updated = json['updatedAt'];
    if (id is! String ||
        name is! String ||
        created is! String ||
        updated is! String) {
      return null;
    }
    final createdTime = DateTime.tryParse(created);
    final updatedTime = DateTime.tryParse(updated);
    if (createdTime == null || updatedTime == null) return null;
    final thumbnail = json['thumbnailPath'];
    return Project(
      id: id,
      name: name,
      createdAt: createdTime,
      updatedAt: updatedTime,
      width: json['width'] is int ? json['width']! as int : 0,
      height: json['height'] is int ? json['height']! as int : 0,
      layerCount: json['layerCount'] is int ? json['layerCount']! as int : 0,
      directoryPath: directoryPath,
      thumbnailPath: thumbnail is String ? thumbnail : null,
    );
  }
}

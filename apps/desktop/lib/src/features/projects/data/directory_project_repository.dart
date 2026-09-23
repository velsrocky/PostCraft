import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../../editor/domain/editor_document.dart';
import '../domain/project.dart';
import '../domain/project_repository.dart';
import 'project_bundle_codec.dart';
import 'project_file_service.dart';

/// Filesystem-backed [ProjectRepository].
///
/// Each project is a directory under [projectsRoot] containing `meta.json`,
/// `project.postcraft` (last saved revision), an optional
/// `project.postcraft.draft` (recoverable autosave), and `thumbnail.png`.
/// Every write is atomic (temp file + rename) and bundles are validated before
/// they replace an existing revision.
class DirectoryProjectRepository implements ProjectRepository {
  DirectoryProjectRepository(this.projectsRoot, {Random? random})
    : _random = random ?? Random();

  final Directory projectsRoot;
  final Random _random;

  static const _metaFile = 'meta.json';
  static const _bundleFile = 'project.postcraft';
  static const _draftFile = 'project.postcraft.draft';
  static const _thumbnailFile = 'thumbnail.png';

  @override
  Future<List<Project>> list() async {
    if (!await projectsRoot.exists()) return const [];
    final projects = <Project>[];
    await for (final entity in projectsRoot.list()) {
      if (entity is! Directory) continue;
      final project = await _readProject(entity);
      if (project != null) projects.add(project);
    }
    projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return projects;
  }

  @override
  Future<Project?> get(String id) async {
    final directory = Directory(_projectPath(id));
    if (!await directory.exists()) return null;
    return _readProject(directory);
  }

  @override
  Future<Project> save({
    Project? existing,
    required String name,
    required EditorDocument document,
    List<int>? thumbnail,
  }) async {
    ProjectBundleCodec.validateDocument(document);
    final now = DateTime.now().toUtc();
    final id = existing?.id ?? _newId();
    final directoryPath = _projectPath(id);
    await Directory(directoryPath).create(recursive: true);

    final bundle = File(_join(directoryPath, _bundleFile));
    await ProjectFileService.writeBundle(bundle, document, name: name);
    final draft = File(_join(directoryPath, _draftFile));
    if (await draft.exists()) await draft.delete();

    if (thumbnail != null && thumbnail.isNotEmpty) {
      await _writeAtomic(
        File(_join(directoryPath, _thumbnailFile)),
        Uint8List.fromList(thumbnail),
      );
    }

    final project = Project(
      id: id,
      name: name,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      width: document.width,
      height: document.height,
      layerCount: document.objects.length,
      directoryPath: directoryPath,
      thumbnailPath: File(_join(directoryPath, _thumbnailFile)).existsSync()
          ? _join(directoryPath, _thumbnailFile)
          : null,
    );
    await _writeMeta(project);
    return project;
  }

  @override
  Future<Project> autosave(String id, EditorDocument document) async {
    ProjectBundleCodec.validateDocument(document);
    final directoryPath = _projectPath(id);
    final directory = Directory(directoryPath);
    if (!await directory.exists()) {
      throw const FileSystemException('Cannot autosave an unknown project.');
    }
    final project = await _readProject(directory);
    if (project == null) {
      throw const FileSystemException('Cannot autosave an unknown project.');
    }
    final bytes = ProjectBundleCodec.encode(document, name: project.name);
    await _writeAtomic(File(_join(directoryPath, _draftFile)), bytes);
    return project.copyWith(
      updatedAt: DateTime.now().toUtc(),
      width: document.width,
      height: document.height,
      layerCount: document.objects.length,
      hasUnsavedDraft: true,
    );
  }

  @override
  Future<EditorDocument> load(String id, {bool draft = false}) async {
    final path = _join(_projectPath(id), draft ? _draftFile : _bundleFile);
    return ProjectFileService.readBundle(File(path));
  }

  @override
  Future<void> delete(String id) async {
    final directory = Directory(_projectPath(id));
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<Project?> _readProject(Directory directory) async {
    final meta = File(_join(directory.path, _metaFile));
    if (!await meta.exists()) return null;
    try {
      final decoded = jsonDecode(await meta.readAsString());
      if (decoded is! Map) return null;
      final project = Project.fromJson(
        Map<String, Object?>.from(decoded),
        directoryPath: directory.path,
      );
      if (project == null) return null;
      final hasDraft = await File(_join(directory.path, _draftFile)).exists();
      return project.copyWith(hasUnsavedDraft: hasDraft);
    } on Object {
      return null;
    }
  }

  Future<void> _writeMeta(Project project) async {
    await _writeAtomic(
      File(_join(project.directoryPath, _metaFile)),
      utf8.encode(jsonEncode(project.toJson())),
    );
  }

  Future<void> _writeAtomic(File target, List<int> bytes) async {
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.tmp-${_random.nextInt(1 << 32)}');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  String _newId() {
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final suffix = _random.nextInt(1 << 32).toRadixString(36).padLeft(7, '0');
    return 'p_${stamp}_$suffix';
  }

  String _projectPath(String id) => _join(projectsRoot.path, id);

  String _join(String a, String b) => '$a${Platform.pathSeparator}$b';
}

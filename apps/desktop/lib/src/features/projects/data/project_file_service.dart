import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import '../../editor/domain/editor_document.dart';
import 'project_bundle_codec.dart';

/// Dialog-driven open/save for `.postcraft` bundles.
///
/// Encoding/validation lives in [ProjectBundleCodec]; this class only handles
/// user file selection and the atomic replace on save. The repository reuses
/// the codec directly for programmatic (autosave) writes.
class ProjectFileService {
  const ProjectFileService({this.pickSaveLocation, this.pickOpenFile});

  final Future<String?> Function()? pickSaveLocation;
  final Future<XFile?> Function()? pickOpenFile;

  static const _projectType = XTypeGroup(
    label: 'PostCraft project',
    extensions: ['postcraft'],
  );

  Future<bool> save(EditorDocument document, {String name = 'Untitled'}) async {
    final location = pickSaveLocation == null
        ? (await getSaveLocation(
            suggestedName: '$name.postcraft',
            acceptedTypeGroups: [_projectType],
          ))?.path
        : await pickSaveLocation!();
    if (location == null) return false;
    await writeBundle(File(location), document, name: name);
    return true;
  }

  /// Atomically writes a bundle to [target]: temp file → validate → replace,
  /// rolling back to the previous file if the swap fails partway.
  static Future<void> writeBundle(
    File target,
    EditorDocument document, {
    String name = 'Untitled',
  }) async {
    final bytes = ProjectBundleCodec.encode(document, name: name);
    final token = '${DateTime.now().microsecondsSinceEpoch}-$pid';
    final temporary = File('${target.path}.tmp-$token');
    final backup = File('${target.path}.bak-$token');
    var movedOriginal = false;
    try {
      await target.parent.create(recursive: true);
      await temporary.writeAsBytes(bytes, flush: true);
      ProjectBundleCodec.decode(await temporary.readAsBytes());
      if (await target.exists()) {
        await target.rename(backup.path);
        movedOriginal = true;
      }
      await temporary.rename(target.path);
      if (movedOriginal) await backup.delete();
    } on Object {
      if (movedOriginal && !await target.exists() && await backup.exists()) {
        await backup.rename(target.path);
      }
      rethrow;
    } finally {
      if (await temporary.exists()) await temporary.delete();
      if (await backup.exists() &&
          await target.exists() &&
          await backup.exists()) {
        await backup.delete();
      }
    }
  }

  Future<EditorDocument?> open() async {
    final file = pickOpenFile == null
        ? await openFile(acceptedTypeGroups: [_projectType])
        : await pickOpenFile!();
    if (file == null) return null;
    if (await file.length() > ProjectBundleCodec.maxArchiveBytes) {
      throw const FormatException('Project archive exceeds the 512 MiB limit.');
    }
    final bytes = await file.readAsBytes();
    return decode(bytes);
  }

  static Future<EditorDocument> readBundle(File file) async {
    if (!await file.exists()) {
      throw const FileSystemException('Project bundle is missing.');
    }
    final bytes = await file.readAsBytes();
    return decode(bytes);
  }

  static EditorDocument decode(Uint8List bytes) =>
      ProjectBundleCodec.decode(bytes);
}

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:archive/archive.dart';

import '../../editor/domain/editor_document.dart';

/// Pure, I/O-free encoder/decoder for the `.postcraft` bundle format.
///
/// A bundle is a ZIP archive containing a `manifest.json` and, when a source
/// image is present, a `media/source-image.bin`. Keeping this separate from the
/// file-picker service lets the repository write bundles to arbitrary paths
/// atomically without any dialog or native dependency.
class ProjectBundleCodec {
  const ProjectBundleCodec._();

  static const formatVersion = 1;
  static const manifestPath = 'manifest.json';
  static const sourceMediaPath = 'media/source-image.bin';
  static const maxArchiveBytes = 512 * 1024 * 1024;
  static const maxManifestBytes = 16 * 1024 * 1024;
  static const maxSourceBytes = 500 * 1024 * 1024;
  static const maxEntries = 16;

  static Uint8List encode(EditorDocument document, {String name = 'Untitled'}) {
    validateDocument(document);
    final json = document.toJson()..remove('sourceImageBase64');
    final archive = Archive();
    archive.add(
      ArchiveFile.string(
        manifestPath,
        jsonEncode({
          'formatVersion': formatVersion,
          'project': {
            'name': name,
            'savedAt': DateTime.now().toUtc().toIso8601String(),
          },
          'document': json,
        }),
      ),
    );
    final image = document.sourceImage;
    if (image != null) {
      archive.add(ArchiveFile(sourceMediaPath, image.length, image));
    }
    final encoded = Uint8List.fromList(ZipEncoder().encode(archive));
    if (encoded.length > maxArchiveBytes) {
      throw const FormatException('Project exceeds the 512 MiB bundle limit.');
    }
    return encoded;
  }

  static EditorDocument decode(List<int> bytes) {
    if (bytes.length > maxArchiveBytes) {
      throw const FormatException('Project archive exceeds the 512 MiB limit.');
    }
    late final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object {
      throw const FormatException('Project archive is malformed or corrupted.');
    }
    if (archive.files.length > maxEntries) {
      throw const FormatException('Project archive contains too many entries.');
    }
    final names = <String>{};
    for (final entry in archive.files) {
      final path = entry.name;
      if (path.startsWith('/') || path.contains('..') || path.contains(r'\')) {
        throw const FormatException('Project archive contains an unsafe path.');
      }
      if (!names.add(path)) {
        throw const FormatException(
          'Project archive contains duplicate entries.',
        );
      }
      if (entry.isSymbolicLink) {
        throw const FormatException(
          'Project archive may not contain symbolic links.',
        );
      }
      if (entry.size < 0 || entry.size > maxSourceBytes) {
        throw const FormatException(
          'Project archive entry exceeds the supported size.',
        );
      }
      if (path != manifestPath && path != sourceMediaPath) {
        throw const FormatException(
          'Project archive contains an unknown entry.',
        );
      }
    }
    final manifest = archive.findFile(manifestPath);
    if (manifest == null || !manifest.isFile) {
      throw const FormatException('Project archive has no manifest.');
    }
    if (manifest.size > maxManifestBytes) {
      throw const FormatException('Project manifest exceeds the 16 MiB limit.');
    }
    final decoded = jsonDecode(utf8.decode(manifest.content as List<int>));
    if (decoded is! Map<String, dynamic> ||
        decoded['formatVersion'] != formatVersion) {
      throw const FormatException('Unsupported PostCraft project format.');
    }
    final document = decoded['document'];
    if (document is! Map<String, dynamic>) {
      throw const FormatException(
        'The project does not contain an editable document.',
      );
    }
    if (document.containsKey('sourceImageBase64')) {
      throw const FormatException(
        'Project manifest contains an invalid inline media field.',
      );
    }
    var result = EditorDocument.fromJson(document);
    final source = archive.findFile(sourceMediaPath);
    if (source != null && source.isFile) {
      final image = source.content as List<int>;
      if (image.length > maxSourceBytes) {
        throw const FormatException('Source media exceeds the supported size.');
      }
      result = result.withSourceImage(
        Uint8List.fromList(image),
        result.width,
        result.height,
      );
    }
    validateDocument(result);
    return result;
  }

  /// Rejects structurally invalid documents before they reach disk or the UI.
  static void validateDocument(EditorDocument document) {
    if (document.width <= 0 ||
        document.height <= 0 ||
        document.width > 16384 ||
        document.height > 16384 ||
        document.width * document.height > 100000000) {
      throw const FormatException(
        'Document dimensions are invalid or too large.',
      );
    }
    if (document.objects.length > 10000) {
      throw const FormatException('Document contains too many objects.');
    }
    final image = document.sourceImage;
    if (image != null && image.length > maxSourceBytes) {
      throw const FormatException('Source media exceeds the supported size.');
    }
    final ids = <int>{};
    for (final object in document.objects) {
      if (object.id <= 0) {
        throw const FormatException('Document contains an invalid object ID.');
      }
      if (!ids.add(object.id)) {
        throw const FormatException('Document contains duplicate object IDs.');
      }
      if (object is ShapeObject && !_isFiniteRect(object.rect)) {
        throw const FormatException(
          'Document contains invalid shape geometry.',
        );
      }
      if (object is TextObject &&
          (!object.position.dx.isFinite ||
              !object.position.dy.isFinite ||
              object.text.length > 100000)) {
        throw const FormatException('Document contains invalid text data.');
      }
      if (object is StrokeObject &&
          (object.points.length > 1000000 ||
              object.points.any(
                (point) => !point.dx.isFinite || !point.dy.isFinite,
              ))) {
        throw const FormatException('Document contains invalid stroke data.');
      }
    }
  }

  static bool _isFiniteRect(Rect rect) =>
      rect.left.isFinite &&
      rect.top.isFinite &&
      rect.width.isFinite &&
      rect.height.isFinite;
}

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../domain/share_provider.dart';

class CopyImageDestination implements ShareDestination {
  const CopyImageDestination();

  @override
  String get id => 'copy-image';

  @override
  String get label => 'Copy image';

  @override
  IconData get icon => Icons.content_copy_rounded;

  @override
  Future<ShareResult> share(SharePayload payload) async {
    final bytes = payload.pngBytes;
    if (bytes == null) {
      return const ShareResult(
        kind: ShareResultKind.failed,
        message: 'No image available to copy.',
      );
    }
    try {
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) {
        return const ShareResult(
          kind: ShareResultKind.failed,
          message: 'Clipboard is unavailable on this platform.',
        );
      }
      final item = DataWriterItem();
      item.add(Formats.png(bytes));
      await clipboard.write([item]);
      return const ShareResult(
        kind: ShareResultKind.copied,
        message: 'Image copied to clipboard.',
      );
    } on Object catch (error) {
      return ShareResult(
        kind: ShareResultKind.failed,
        message: 'Clipboard copy failed: $error',
      );
    }
  }
}

class SaveImageDestination implements ShareDestination {
  const SaveImageDestination();

  @override
  String get id => 'save-image';

  @override
  String get label => 'Save image as…';

  @override
  IconData get icon => Icons.download_outlined;

  @override
  Future<ShareResult> share(SharePayload payload) async {
    final bytes = payload.pngBytes;
    if (bytes == null) {
      return const ShareResult(
        kind: ShareResultKind.failed,
        message: 'No image available to save.',
      );
    }
    try {
      final location = await getSaveLocation(
        suggestedName: '${payload.title.isEmpty ? 'PostCraft-export' : payload.title}.png',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'PNG image', extensions: ['png']),
        ],
      );
      if (location == null) {
        return const ShareResult(
          kind: ShareResultKind.cancelled,
          message: 'Save cancelled.',
        );
      }
      await XFile.fromData(
        bytes,
        mimeType: 'image/png',
        name: 'export.png',
      ).saveTo(location.path);
      return const ShareResult(
        kind: ShareResultKind.saved,
        message: 'PNG saved.',
      );
    } on Object catch (error) {
      return ShareResult(
        kind: ShareResultKind.failed,
        message: 'Save failed: $error',
      );
    }
  }
}

class CopyPathDestination implements ShareDestination {
  const CopyPathDestination();

  @override
  String get id => 'copy-path';

  @override
  String get label => 'Copy file path';

  @override
  IconData get icon => Icons.link_rounded;

  @override
  Future<ShareResult> share(SharePayload payload) async {
    final path = payload.filePath;
    if (path == null || path.isEmpty) {
      return const ShareResult(
        kind: ShareResultKind.failed,
        message: 'No file path available.',
      );
    }
    try {
      await Clipboard.setData(ClipboardData(text: path));
      return const ShareResult(
        kind: ShareResultKind.copiedPath,
        message: 'File path copied to clipboard.',
      );
    } on Object catch (error) {
      return ShareResult(
        kind: ShareResultKind.failed,
        message: 'Could not copy path: $error',
      );
    }
  }
}

class OpenContainingFolderDestination implements ShareDestination {
  const OpenContainingFolderDestination();

  @override
  String get id => 'open-folder';

  @override
  String get label => 'Open containing folder';

  @override
  IconData get icon => Icons.folder_open_outlined;

  @override
  Future<ShareResult> share(SharePayload payload) async {
    final path = payload.filePath;
    if (path == null || path.isEmpty) {
      return const ShareResult(
        kind: ShareResultKind.failed,
        message: 'No file path available.',
      );
    }
    try {
      final parent = File(path).parent.path;
      final result = await _reveal(parent);
      if (result != 0) {
        return ShareResult(
          kind: ShareResultKind.failed,
          message: 'Could not open folder (exit $result).',
        );
      }
      return const ShareResult(
        kind: ShareResultKind.opened,
        message: 'Opened containing folder.',
      );
    } on Object catch (error) {
      return ShareResult(
        kind: ShareResultKind.failed,
        message: 'Could not open folder: $error',
      );
    }
  }

  Future<int> _reveal(String directory) async {
    if (Platform.isLinux) {
      final result = await Process.run('xdg-open', [directory]);
      return result.exitCode;
    }
    if (Platform.isMacOS) {
      final result = await Process.run('open', [directory]);
      return result.exitCode;
    }
    if (Platform.isWindows) {
      await Process.run('explorer', [directory]);
      return 0;
    }
    return 1;
  }
}

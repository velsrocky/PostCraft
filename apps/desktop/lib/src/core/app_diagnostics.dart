import 'dart:io';

import 'app_paths.dart';

/// Crash and error sink for PostCraft.
///
/// Startup failures go to `startup-errors.log` (via [recordStartup]); errors
/// raised after the framework boots go to `errors.log` (via [record]). Both
/// logs rotate in place when they exceed [maxBytes]: the live file is renamed
/// to `<name>.1` and any previous `.1` copy is dropped, so at most one rotated
/// file is retained per log. Every operation swallows its own failures so
/// recording an error can never throw a second error at the caller.
class AppDiagnostics {
  const AppDiagnostics(this.paths, {this.maxBytes = defaultMaxBytes});

  static const defaultMaxBytes = 1024 * 1024;
  static const startupLogName = 'startup-errors.log';
  static const runtimeLogName = 'errors.log';

  final AppPaths paths;
  final int maxBytes;

  Future<void> record(Object error, StackTrace stackTrace) =>
      _append(runtimeLogName, error, stackTrace);

  Future<void> recordStartup(Object error, StackTrace stackTrace) =>
      _append(startupLogName, error, stackTrace);

  Future<void> _append(
    String fileName,
    Object error,
    StackTrace stackTrace,
  ) async {
    try {
      final file = File(_path(fileName));
      await _rotate(file);
      await file.writeAsString(
        '${DateTime.now().toUtc().toIso8601String()}\n$error\n$stackTrace\n\n',
        mode: FileMode.append,
        flush: true,
      );
    } on Object {
      // Diagnostics must never surface as a new failure for the app.
    }
  }

  Future<void> _rotate(File file) async {
    try {
      if (!await file.exists()) return;
      if (await file.length() <= maxBytes) return;
      final rotated = File('${file.path}.1');
      if (await rotated.exists()) await rotated.delete();
      await file.rename(rotated.path);
    } on Object {
      // Rotation is best effort; appending still proceeds.
    }
  }

  String _path(String fileName) {
    final separator = Platform.pathSeparator;
    final root = paths.root.path;
    return root.endsWith(separator)
        ? '$root$fileName'
        : '$root$separator$fileName';
  }
}

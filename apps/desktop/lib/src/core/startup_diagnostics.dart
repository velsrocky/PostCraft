import 'dart:io';

import 'app_paths.dart';

class StartupDiagnostics {
  const StartupDiagnostics(this.paths);
  final AppPaths paths;

  Future<void> record(Object error, StackTrace stackTrace) async {
    try {
      final file = File('${paths.root.path}${Platform.pathSeparator}startup-errors.log');
      await file.writeAsString(
        '${DateTime.now().toUtc().toIso8601String()}\n$error\n$stackTrace\n\n',
        mode: FileMode.append,
        flush: true,
      );
    } on Object {
      // Startup diagnostics must never hide the original initialization error.
    }
  }
}

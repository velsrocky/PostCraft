import 'app_diagnostics.dart';
import 'app_paths.dart';

class StartupDiagnostics {
  const StartupDiagnostics(this.paths);
  final AppPaths paths;

  Future<void> record(Object error, StackTrace stackTrace) =>
      AppDiagnostics(paths).recordStartup(error, stackTrace);
}

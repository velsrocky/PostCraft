/// The user-facing PostCraft version.
///
/// Mirrors `version:` in `pubspec.yaml` (minus the build number), which cannot
/// be read cheaply at runtime. Keep the two in sync when cutting a release.
abstract final class AppVersion {
  static const string = '1.0.0';
}

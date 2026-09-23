import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Resolved writable locations for PostCraft's local-first data.
///
/// Kept behind a small value object so the storage engine (file store today,
/// a maintained Isar drop-in later) never hard-codes platform paths.
class AppPaths {
  const AppPaths({
    required this.root,
    required this.projects,
    required this.assets,
    required this.cache,
  });

  final Directory root;
  final Directory projects;
  final Directory assets;
  final Directory cache;

  static Future<AppPaths> resolve({
    Future<Directory> Function()? supportDirectory,
    Future<Directory> Function()? cacheDirectory,
  }) async {
    final support =
        await (supportDirectory ?? getApplicationSupportDirectory)();
    final cacheDir = await (cacheDirectory ?? getTemporaryDirectory)();
    final root = Directory('${support.path}${Platform.pathSeparator}PostCraft');
    final projects = Directory('${root.path}${Platform.pathSeparator}projects');
    final assets = Directory('${root.path}${Platform.pathSeparator}assets');
    final cache = Directory(
      '${cacheDir.path}${Platform.pathSeparator}PostCraft',
    );
    await Future.wait([
      root.create(recursive: true),
      projects.create(recursive: true),
      assets.create(recursive: true),
      cache.create(recursive: true),
    ]);
    return AppPaths(
      root: root,
      projects: projects,
      assets: assets,
      cache: cache,
    );
  }
}

/// Overridden in tests and, optionally, in production bootstrap.
final appPathsProvider = FutureProvider<AppPaths>((ref) => AppPaths.resolve());

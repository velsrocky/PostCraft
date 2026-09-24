import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:postcraft/src/core/app_diagnostics.dart';
import 'package:postcraft/src/core/app_paths.dart';

void main() {
  late Directory root;
  late AppPaths paths;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('postcraft-diagnostics-');
    paths = AppPaths(
      root: root,
      projects: Directory('${root.path}${Platform.pathSeparator}projects'),
      assets: Directory('${root.path}${Platform.pathSeparator}assets'),
      cache: Directory('${root.path}${Platform.pathSeparator}cache'),
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  File log(String name) => File('${root.path}${Platform.pathSeparator}$name');

  test('record writes a timestamped entry to errors.log', () async {
    await AppDiagnostics(
      paths,
    ).record('boom after startup', StackTrace.fromString('frame zero'));

    final content = await log(AppDiagnostics.runtimeLogName).readAsString();
    expect(content, contains('boom after startup'));
    expect(content, contains('frame zero'));
    expect(content, matches(RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}')));
  });

  test('recordStartup writes to startup-errors.log', () async {
    await AppDiagnostics(
      paths,
    ).recordStartup('rust init failed', StackTrace.fromString('startup frame'));

    final content = await log(AppDiagnostics.startupLogName).readAsString();
    expect(content, contains('rust init failed'));
    expect(content, contains('startup frame'));
    expect(content, matches(RegExp(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}')));
  });

  test(
    'rotates errors.log over the cap and retains one rotated file',
    () async {
      final diagnostics = AppDiagnostics(paths, maxBytes: 64);

      await diagnostics.record('first-runtime-entry', StackTrace.current);
      expect(log('${AppDiagnostics.runtimeLogName}.1').existsSync(), isFalse);

      await diagnostics.record('second-runtime-entry', StackTrace.current);
      final rotated = log('${AppDiagnostics.runtimeLogName}.1');
      expect(rotated.existsSync(), isTrue);
      expect(await rotated.readAsString(), contains('first-runtime-entry'));
      final live = await log(AppDiagnostics.runtimeLogName).readAsString();
      expect(live, contains('second-runtime-entry'));
      expect(live, isNot(contains('first-runtime-entry')));

      await diagnostics.record('third-runtime-entry', StackTrace.current);
      expect(log('${AppDiagnostics.runtimeLogName}.2').existsSync(), isFalse);
      expect(rotated.existsSync(), isTrue);
    },
  );

  test('applies the same rotation to the startup log', () async {
    final diagnostics = AppDiagnostics(paths, maxBytes: 64);

    await diagnostics.recordStartup('startup-one', StackTrace.current);
    await diagnostics.recordStartup('startup-two', StackTrace.current);

    final rotated = log('${AppDiagnostics.startupLogName}.1');
    expect(rotated.existsSync(), isTrue);
    expect(await rotated.readAsString(), contains('startup-one'));
    expect(log('${AppDiagnostics.startupLogName}.2').existsSync(), isFalse);
  });

  test('record never throws when the log directory is unavailable', () async {
    final missing = AppPaths(
      root: Directory('${root.path}${Platform.pathSeparator}missing'),
      projects: Directory('${root.path}${Platform.pathSeparator}projects'),
      assets: Directory('${root.path}${Platform.pathSeparator}assets'),
      cache: Directory('${root.path}${Platform.pathSeparator}cache'),
    );
    final diagnostics = AppDiagnostics(missing);

    await expectLater(
      diagnostics.record('unwritable', StackTrace.current),
      completes,
    );
    await expectLater(
      diagnostics.recordStartup('unwritable', StackTrace.current),
      completes,
    );
  });
}

import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app/postcraft_app.dart';
import 'src/core/app_diagnostics.dart';
import 'src/core/app_paths.dart';
import 'src/core/startup_diagnostics.dart';
import 'src/rust/api.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppPaths? paths;
  try {
    paths = await AppPaths.resolve();
  } on Object {
    paths = null;
  }
  final diagnostics = paths == null ? null : AppDiagnostics(paths);
  FlutterError.onError = (details) {
    try {
      diagnostics?.record(details.exception, details.stack ?? StackTrace.empty);
    } on Object {
      // Recording must never escalate into a second failure.
    }
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    try {
      diagnostics?.record(error, stackTrace);
    } on Object {
      // The framework still reports the error after this returns true.
    }
    return true;
  };
  try {
    await PostCraftRust.init();
  } on Object catch (error, stackTrace) {
    if (paths != null) {
      await StartupDiagnostics(paths).record(error, stackTrace);
    }
    runApp(_StartupFailure(error: error));
    return;
  }
  try {
    await installPanicHook(
      logPath: paths == null
          ? ''
          : '${paths.root.path}${Platform.pathSeparator}panic.log',
    );
  } on Object {
    // Panic logging is best-effort; never block startup on it.
  }
  runApp(const ProviderScope(child: PostCraftApp()));
}

class _StartupFailure extends StatelessWidget {
  const _StartupFailure({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'PostCraft startup failure',
    theme: ThemeData.dark(),
    home: Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: SelectableText(
              'PostCraft could not start.\n\n$error\n\nCheck startup-errors.log in the PostCraft application-support directory.',
            ),
          ),
        ),
      ),
    ),
  );
}

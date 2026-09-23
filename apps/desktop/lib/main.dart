import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app/postcraft_app.dart';
import 'src/core/app_paths.dart';
import 'src/core/startup_diagnostics.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await PostCraftRust.init();
  } on Object catch (error, stackTrace) {
    final paths = await AppPaths.resolve();
    await StartupDiagnostics(paths).record(error, stackTrace);
    runApp(_StartupFailure(error: error));
    return;
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

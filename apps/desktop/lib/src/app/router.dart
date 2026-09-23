import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/capture/presentation/capture_home_page.dart';
import '../features/editor/presentation/editor_page.dart';
import '../features/library/presentation/library_page.dart';
import '../features/projects/presentation/projects_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/studio/presentation/studio_page.dart';
import '../features/templates/presentation/templates_page.dart';
import 'postcraft_shell.dart';

/// Root navigator so capture can be driven from a background handler.
final rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/workspace',
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            PostCraftShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/workspace',
            builder: (context, state) => const CaptureHomePage(),
          ),
          GoRoute(
            path: '/editor',
            builder: (context, state) => const EditorPage(),
          ),
          GoRoute(
            path: '/projects',
            builder: (context, state) => const ProjectsPage(),
          ),
          GoRoute(
            path: '/library',
            builder: (context, state) => const LibraryPage(),
          ),
          GoRoute(
            path: '/studio',
            builder: (context, state) => const StudioPage(),
          ),
          GoRoute(
            path: '/templates',
            builder: (context, state) => const TemplatesPage(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsPage(),
          ),
        ],
      ),
    ],
  );
});

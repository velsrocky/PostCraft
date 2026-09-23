import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme.dart';

class PostCraftApp extends ConsumerWidget {
  const PostCraftApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'PostCraft',
    debugShowCheckedModeBanner: false,
    theme: PostCraftTheme.dark,
    routerConfig: ref.watch(routerProvider),
  );
}

import 'package:flutter/material.dart';

abstract final class PostCraftTheme {
  static const canvas = Color(0xFF111318);
  static const panel = Color(0xFF181B22);
  static const elevated = Color(0xFF20242D);
  static const accent = Color(0xFF9B8CFF);
  static const muted = Color(0xFF9298A7);

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
      surface: panel,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: canvas,
      dividerColor: Colors.white.withValues(alpha: .07),
      textTheme: ThemeData.dark().textTheme.apply(
        bodyColor: const Color(0xFFE9EAF0),
        displayColor: const Color(0xFFE9EAF0),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: elevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
      ),
    );
  }
}

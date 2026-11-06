import 'package:flutter/material.dart';

class AppColors {
  static const ink = Color(0xFF14202B);
  static const primary = Color(0xFF1F5A7A);
  static const primaryDark = Color(0xFF8CC4E0);
  static const accent = Color(0xFFD9A441);
  static const paper = Color(0xFFF5F3EE);
  static const paperDark = Color(0xFF11171C);
  static const cardDark = Color(0xFF1A2229);

  static const high = Color(0xFFB03A2E);
  static const medium = Color(0xFFC98A1B);
  static const low = Color(0xFF2E7DAF);
}

/// One colour per step of the ACAPS probability scale (very low -> very high).
const scaleColors = [
  Color(0xFF4F8AA6),
  Color(0xFF6E9E72),
  Color(0xFFD1A03A),
  Color(0xFFD46F35),
  Color(0xFFB03A2E),
];

Color levelColor(String level) => switch (level) {
      'High' => AppColors.high,
      'Medium' => AppColors.medium,
      'Low' => AppColors.low,
      _ => const Color(0xFF8A8F94),
    };

/// Black background, white text, yellow accents, strong outlines.
ThemeData buildContrastTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: AppColors.primary, brightness: Brightness.dark).copyWith(
    primary: const Color(0xFFFFE14D),
    onPrimary: Colors.black,
    tertiary: const Color(0xFFFFE14D),
    surface: Colors.black,
    onSurface: Colors.white,
    onSurfaceVariant: Colors.white,
    surfaceContainerLowest: Colors.black,
    surfaceContainerHighest: const Color(0xFF2A2A2A),
    outline: Colors.white,
    outlineVariant: Colors.white,
    error: const Color(0xFFFF6B6B),
    errorContainer: const Color(0xFF5A0000),
    onErrorContainer: Colors.white,
  );
  return _themeFrom(scheme, borderWidth: 2);
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: brightness,
  ).copyWith(
    primary: dark ? AppColors.primaryDark : AppColors.primary,
    onPrimary: dark ? AppColors.ink : Colors.white,
    tertiary: AppColors.accent,
    surface: dark ? AppColors.paperDark : AppColors.paper,
    onSurface: dark ? const Color(0xFFE6E8EA) : AppColors.ink,
    surfaceContainerLowest: dark ? AppColors.cardDark : Colors.white,
    surfaceContainerHighest: dark ? const Color(0xFF26313A) : const Color(0xFFE9E5DC),
    outlineVariant: dark ? const Color(0xFF34404A) : const Color(0xFFDCD7CC),
  );
  return _themeFrom(scheme);
}

ThemeData _themeFrom(ColorScheme scheme, {double borderWidth = 1}) {

  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final text = base.textTheme;
  final radius12 = BorderRadius.circular(12);

  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.3),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, height: 1.25),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      bodyMedium: text.bodyMedium?.copyWith(height: 1.45),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant, width: borderWidth),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      border: OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide(color: scheme.outlineVariant)),
      enabledBorder: OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide(color: scheme.outlineVariant)),
      focusedBorder: OutlineInputBorder(borderRadius: radius12, borderSide: BorderSide(color: scheme.primary, width: 2)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLowest,
      indicatorColor: scheme.primary.withAlpha(40),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    expansionTileTheme: const ExpansionTileThemeData(
      shape: Border(),
      collapsedShape: Border(),
    ),
  );
}

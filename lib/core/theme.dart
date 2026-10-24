import 'package:flutter/material.dart';

class AppColors {
  static const blue = Color(0xFF2563EB);
  static const teal = Color(0xFF14B8A6);
  static const green = Color(0xFF16A34A);
  static const red = Color(0xFFDC2626);
  static const purple = Color(0xFF7C3AED);
  static const ink = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const canvas = Color(0xFFF8FAFC);
}

ThemeData makeTheme({required bool dark, required bool highContrast}) {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.blue,
        brightness: dark ? Brightness.dark : Brightness.light,
      ).copyWith(
        primary: highContrast
            ? (dark ? const Color(0xFF93C5FD) : const Color(0xFF1E40AF))
            : AppColors.blue,
        onPrimary: dark && highContrast ? AppColors.ink : Colors.white,
        surface: dark ? const Color(0xFF1E293B) : Colors.white,
        onSurface: dark ? const Color(0xFFF8FAFC) : AppColors.ink,
        onSurfaceVariant: highContrast
            ? (dark ? Colors.white : const Color(0xFF334155))
            : (dark ? const Color(0xFFCBD5E1) : AppColors.muted),
      );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark ? const Color(0xFF0F172A) : AppColors.canvas,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      height: 72,
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

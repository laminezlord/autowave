import 'package:flutter/material.dart';

/// AutoWave palette: asphalt ink, road-marking yellow, and green for anything
/// that is secured or sustainable (escrow, recycling, learning).
class AppColors {
  static const ink = Color(0xFF15202B); // asphalt
  static const body = Color(0xFF3A4552);
  static const muted = Color(0xFF6B7684);
  static const surface = Color(0xFFF3F4F1);
  static const card = Colors.white;
  static const line = Color(0xFFE2E5E0);
  static const signal = Color(0xFFF5B800); // road-marking yellow
  static const signalSoft = Color(0xFFFFF3CC);
  static const go = Color(0xFF12805C); // secured / eco
  static const goSoft = Color(0xFFE3F3EC);
  static const alert = Color(0xFFC8372D);
  static const alertSoft = Color(0xFFFBE9E7);
  static const info = Color(0xFF1F5FBF);
  static const infoSoft = Color(0xFFE6EEFA);
  static const star = Color(0xFFE59E00);

  // Names used by the phase-4 tracking code.
  static const buttonBlack = ink;
  static const textPrimary = ink;
  static const textSecondary = body;
  static const textMuted = muted;
  static const lightGrey = surface;
  static const accentBlue = info;
}

class AppText {
  static const family = 'Archivo';
  static const display = 'ArchivoExpanded';

  static const h1 = TextStyle(fontFamily: display, fontSize: 30, height: 1.1, fontWeight: FontWeight.w800, color: AppColors.ink, letterSpacing: -0.6);
  static const h2 = TextStyle(fontFamily: display, fontSize: 22, height: 1.15, fontWeight: FontWeight.w700, color: AppColors.ink, letterSpacing: -0.3);
  static const h3 = TextStyle(fontFamily: family, fontSize: 18, height: 1.25, fontWeight: FontWeight.w700, color: AppColors.ink);
  static const title = TextStyle(fontFamily: family, fontSize: 16, height: 1.3, fontWeight: FontWeight.w700, color: AppColors.ink);
  static const body = TextStyle(fontFamily: family, fontSize: 15, height: 1.45, fontWeight: FontWeight.w400, color: AppColors.body);
  static const small = TextStyle(fontFamily: family, fontSize: 13, height: 1.4, fontWeight: FontWeight.w500, color: AppColors.muted);
  static const money = TextStyle(fontFamily: display, fontSize: 34, height: 1.0, fontWeight: FontWeight.w800, color: AppColors.ink, letterSpacing: -0.8);
}

ThemeData buildTheme() {
  const radius = 14.0;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.ink,
    primary: AppColors.ink,
    onPrimary: Colors.white,
    secondary: AppColors.signal,
    onSecondary: AppColors.ink,
    surface: AppColors.surface,
    error: AppColors.alert,
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, fontFamily: AppText.family);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.surface,
    textTheme: base.textTheme.apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: AppText.family, fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        disabledBackgroundColor: const Color(0xFFC9CED3),
        disabledForegroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        textStyle: const TextStyle(fontFamily: AppText.family, fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size.fromHeight(50),
        side: const BorderSide(color: AppColors.line, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        textStyle: const TextStyle(fontFamily: AppText.family, fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.info,
        textStyle: const TextStyle(fontFamily: AppText.family, fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      hintStyle: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w400),
      labelStyle: const TextStyle(color: AppColors.muted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: const BorderSide(color: AppColors.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: const BorderSide(color: AppColors.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: const BorderSide(color: AppColors.ink, width: 1.6)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: const BorderSide(color: AppColors.alert)),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Colors.white,
      selectedColor: AppColors.ink,
      side: const BorderSide(color: AppColors.line),
      // Resolves per state so FilterChip and ChoiceChip both get white text when selected.
      labelStyle: TextStyle(
        fontFamily: AppText.family,
        fontWeight: FontWeight.w600,
        fontSize: 14,
        color: WidgetStateColor.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : AppColors.ink),
      ),
      secondaryLabelStyle: const TextStyle(fontFamily: AppText.family, fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: AppColors.signalSoft,
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontFamily: AppText.family,
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? AppColors.ink : AppColors.muted,
          )),
      iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? AppColors.ink : AppColors.muted)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.ink,
      contentTextStyle: const TextStyle(fontFamily: AppText.family, color: Colors.white, fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1, space: 1),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : AppColors.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.go : AppColors.line),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.ink),
  );
}

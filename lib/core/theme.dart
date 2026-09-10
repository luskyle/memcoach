import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 记忆教练主题：参考 Apple 人机界面指南（HIG）的 iOS 视觉语言。
///
/// - 清晰：系统字体层级、label/secondaryLabel 对比度、大圆角卡片
/// - 遵循惯例：系统蓝 #007AFF、层级灰/白背景、hairline 分隔、系统控件形态
/// - 深度：Grouped 背景 + 白色浮层卡片、半透明 Tab/侧栏
class AppTheme {
  static final Color systemBlue = CupertinoColors.systemBlue.color;

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: systemBlue,
      onPrimary: isDark ? const Color(0xFF00214F) : Colors.white,
      primaryContainer: systemBlue.withValues(alpha: isDark ? 0.3 : 0.2),
      onPrimaryContainer: systemBlue,
      secondary: isDark ? const Color(0xFFAEAEB2) : const Color(0xFF8E8E93),
      onSecondary: Colors.white,
      secondaryContainer: systemBlue.withValues(alpha: isDark ? 0.35 : 0.14),
      onSecondaryContainer: systemBlue,
      tertiary: isDark ? const Color(0xFF5AC8FA) : systemBlue,
      onTertiary: Colors.white,
      error: CupertinoColors.systemRed.color,
      onError: Colors.white,
      // iOS 层级背景：Grouped Background（页面）→ 白色浮层（卡片/列表）
      surface: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      onSurface: isDark ? const Color(0xFFFFFFFF) : const Color(0xE5000000),
      onSurfaceVariant:
          isDark ? const Color(0x99FFFFFF) : const Color(0x99000000),
      surfaceContainerLowest: isDark ? Colors.black : const Color(0xFFF2F2F7),
      surfaceContainerLow: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      surfaceContainer:
          isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
      surfaceContainerHigh:
          isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA),
      surfaceContainerHighest:
          isDark ? const Color(0xFF48484A) : const Color(0xFFE5E5EA),
      outline: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFD1D1D6),
      outlineVariant:
          isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
      shadow: Colors.black,
      scrim: Colors.black54,
      inverseSurface: isDark ? const Color(0xFFE5E5EA) : Colors.black,
      onInverseSurface: isDark ? Colors.black : Colors.white,
      inversePrimary:
          isDark ? const Color(0xFF0A84FF) : const Color(0xFF3285FF),
    );

    final labelColor =
        isDark ? const Color(0xFFFFFFFF) : const Color(0xE5000000);
    final secondaryLabel =
        isDark ? const Color(0x99FFFFFF) : const Color(0x99000000);
    final hairline = isDark ? const Color(0x33FFFFFF) : const Color(0x14000000);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
      textTheme: TextTheme(
        displayMedium: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            color: labelColor,
            letterSpacing: .4),
        headlineMedium: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: labelColor,
            letterSpacing: .35),
        titleLarge: TextStyle(
            fontSize: 22, fontWeight: FontWeight.w600, color: labelColor),
        titleMedium: TextStyle(
            fontSize: 17, fontWeight: FontWeight.w600, color: labelColor),
        titleSmall: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w600, color: labelColor),
        bodyLarge: TextStyle(fontSize: 17, color: labelColor),
        bodyMedium: TextStyle(fontSize: 15, color: labelColor),
        bodySmall: TextStyle(fontSize: 13, color: secondaryLabel),
        labelLarge: TextStyle(
            fontSize: 17, fontWeight: FontWeight.w600, color: labelColor),
        labelMedium: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w500, color: secondaryLabel),
        labelSmall: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w500, color: secondaryLabel),
      ),
      dividerColor: hairline,
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: labelColor,
        titleTextStyle: TextStyle(
            fontSize: 17, fontWeight: FontWeight.w600, color: labelColor),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 56,
        elevation: 0,
        backgroundColor: scheme.surface.withValues(alpha: 0.93),
        surfaceTintColor: Colors.transparent,
        indicatorColor: const Color(0xFFFFFFFF),
        indicatorShape: const RoundedRectangleBorder(),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
              fontSize: 11, fontWeight: FontWeight.w500, color: secondaryLabel),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? systemBlue
                : secondaryLabel,
            size: 24,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        selectedColor: systemBlue.withValues(alpha: 0.18),
        labelStyle: TextStyle(fontSize: 13, color: labelColor),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: systemBlue, width: 1.2),
        ),
        labelStyle: TextStyle(fontSize: 15, color: secondaryLabel),
        hintStyle: TextStyle(fontSize: 15, color: secondaryLabel),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: systemBlue,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(64, 44),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 44),
          side: BorderSide(color: hairline),
          foregroundColor: systemBlue,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: systemBlue,
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            isDark ? const Color(0xFF3A3A3C) : const Color(0xE6000000),
        contentTextStyle: const TextStyle(fontSize: 15, color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        // 桌面无 iOS 毛玻璃层：用不透明表面色，避免弹窗内容透明看不清
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: secondaryLabel,
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Color constants matching the demo_ui.html design.
class AppColors {
  // Dark theme
  static const darkBase = Color(0xFF101318);
  static const darkSurface = Color(0xFF15191f);
  static const darkSurfaceAlt = Color(0xFF1a1f27);
  static const darkSidebar = Color(0xFF13171d);
  static const darkRail = Color(0xFF0d1015);
  static const darkBorder = Color(0xFF232a35);
  static const darkText = Color(0xFFe0e3ea);
  static const darkTextMuted = Color(0xFF8b95a5);
  static const darkTextDim = Color(0xFF5c6573);

  // Light theme
  static const lightBase = Color(0xFFF5F5F5);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceAlt = Color(0xFFF0F0F0);
  static const lightSidebar = Color(0xFFF8F8FA);
  static const lightRail = Color(0xFFEBEBF0);
  static const lightBorder = Color(0xFFD8D8DD);
  static const lightText = Color(0xFF1A1A2E);
  static const lightTextMuted = Color(0xFF6B7280);
  static const lightTextDim = Color(0xFF9CA3AF);

  // Accent
  static const accent = Color(0xFF4F6EF7);
  static const accentDark = Color(0xFF3B5BDB);
  static const accentLight = Color(0xFF6B85FA);

  // Semantic
  static const online = Color(0xFF3BA55C);
  static const danger = Color(0xFFED4245);
  static const warning = Color(0xFFFAA61A);

  // Message bubbles — spec §5 exact tokens
  // msgOutBg night / day
  static const bubbleSent = Color(0xFF2b5278);
  static const bubbleSentLight = Color(0xFFeffdde);
  // msgInBg night / day
  static const bubbleReceived = Color(0xFF182533);
  static const bubbleReceivedLight = Color(0xFFffffff);
  // msgOutBgSelected night / day
  static const bubbleSentSelected = Color(0xFF2e70a5);
  static const bubbleSentSelectedLight = Color(0xFFb7dbdb);
  // msgInBgSelected night / day
  static const bubbleReceivedSelected = Color(0xFF2e70a5);
  static const bubbleReceivedSelectedLight = Color(0xFFc2dcf2);

  // Bubble shadows — spec §5: 2px bottom shadow strip
  // Format: #RRGGBBAA in spec → 0xAARRGGBB in Flutter
  // msgOutShadow day / night (night disabled: alpha 00)
  static const bubbleSentShadow = Color(0x1d3ac346);
  static const bubbleSentShadowNight = Color(0x00000000);
  // msgOutShadowSelected day / night
  static const bubbleSentShadowSelected = Color(0x2237a78d);
  static const bubbleSentShadowSelectedNight = Color(0x00366ea6);
  // msgInShadow day / night (night disabled: alpha 00)
  static const bubbleReceivedShadow = Color(0x29748ea2);
  static const bubbleReceivedShadowNight = Color(0x00748ea2);
  // msgInShadowSelected day / night
  static const bubbleReceivedShadowSelected = Color(0x29548dbb);
  static const bubbleReceivedShadowSelectedNight = Color(0x00538ebb);
}

/// Sizing constants.
class AppSizes {
  static const double railWidth = 68;
  static const double sidebarWidth = 272;
  static const double emojiPanelWidth = 320;
  static const double rightPanelWidth = 260;
  static const double bubbleRadius = 18;
  static const double bubbleTailRadius = 6;
  static const double avatarSize = 40;
  static const double avatarSizeSmall = 32;
  static const double railIconSize = 48;
}

class AppTheme {
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: 'Inter',
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkText,
      error: AppColors.danger,
    ),
    scaffoldBackgroundColor: AppColors.darkBase,
    dividerColor: AppColors.darkBorder,
    cardColor: AppColors.darkSurfaceAlt,
    textTheme: _textTheme(AppColors.darkText, AppColors.darkTextMuted),
    iconTheme: const IconThemeData(color: AppColors.darkTextMuted, size: 20),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.darkBase,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.darkBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.accent, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      hintStyle: const TextStyle(color: AppColors.darkTextDim),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(AppColors.darkBorder),
      radius: const Radius.circular(4),
      thickness: WidgetStateProperty.all(6),
    ),
  );

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: 'Inter',
    colorScheme: const ColorScheme.light(
      primary: AppColors.accent,
      surface: AppColors.lightSurface,
      onSurface: AppColors.lightText,
      error: AppColors.danger,
    ),
    scaffoldBackgroundColor: AppColors.lightBase,
    dividerColor: AppColors.lightBorder,
    cardColor: AppColors.lightSurfaceAlt,
    textTheme: _textTheme(AppColors.lightText, AppColors.lightTextMuted),
    iconTheme: const IconThemeData(color: AppColors.lightTextMuted, size: 20),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.lightBase,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.lightBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.accent, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      hintStyle: const TextStyle(color: AppColors.lightTextDim),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(AppColors.lightBorder),
      radius: const Radius.circular(4),
      thickness: WidgetStateProperty.all(6),
    ),
  );

  static TextTheme _textTheme(Color primary, Color secondary) => TextTheme(
    headlineLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: primary),
    headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: primary),
    titleLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: primary),
    titleMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primary),
    bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: primary),
    bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: primary),
    bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: secondary),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: primary),
    labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: secondary),
  );
}

import 'package:flutter/material.dart';
import 'telegram_palette.dart';

export 'telegram_palette.dart';
export 'theme_file.dart';
export 'theme_tokens.dart';
export 'wallpaper.dart';

class AppColors {
  static const darkBase = Color(0xFF17212B);
  static const darkSurface = Color(0xFF17212B);
  static const darkSurfaceAlt = Color(0xFF232E3C);
  static const darkSidebar = Color(0xFF0E1621);
  static const darkRail = Color(0xFF0E1621);
  static const darkBorder = Color(0xFF232A35);
  static const darkText = Color(0xFFF5F5F5);
  static const darkTextMuted = Color(0xFF708499);
  static const darkTextDim = Color(0xFF6C7883);

  static const lightBase = Color(0xFFFFFFFF);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceAlt = Color(0xFFF1F1F1);
  static const lightSidebar = Color(0xFFF1F1F1);
  static const lightRail = Color(0xFFF1F1F1);
  static const lightBorder = Color(0xFFE5E5E5);
  static const lightText = Color(0xFF000000);
  static const lightTextMuted = Color(0xFF999999);
  static const lightTextDim = Color(0xFF999999);

  static const accent = Color(0xFF40A7E3);
  static const accentDark = Color(0xFF5288C1);
  static const accentLight = Color(0xFF6AB3F3);

  static const online = Color(0xFF4DC920);
  static const danger = Color(0xFFD14E4E);
  static const warning = Color(0xFFFAAD38);

  static const bubbleSent = Color(0xFF2b5278);
  static const bubbleSentLight = Color(0xFFeffdde);
  static const bubbleReceived = Color(0xFF182533);
  static const bubbleReceivedLight = Color(0xFFffffff);
  static const bubbleSentSelected = Color(0xFF2e70a5);
  static const bubbleSentSelectedLight = Color(0xFFcbebb5);
  static const bubbleReceivedSelected = Color(0xFF2e70a5);
  static const bubbleReceivedSelectedLight = Color(0xFFc2dcf2);

  static const msgInDateFg = Color(0xFFa0acb6);
  static const msgInDateFgNight = Color(0xFF7a858f);
  static const msgOutDateFg = Color(0xFF6fab69);
  static const msgOutDateFgNight = Color(0xFF7da8d3);
  static const historyOutIconFg = Color(0xFF5dc452);
  static const historyOutIconFgNight = Color(0xFF62b2fd);
  static const historySendingOutIconFg = Color(0xFF98d292);
  static const historySendingOutIconFgNight = Color(0xFF70a4d2);
  static const historySendingInIconFg = Color(0xFFa0adb5);
  static const historySendingInIconFgNight = Color(0xFF76838b);
  static const msgDateImgBg = Color(0x54000000);
  static const historyIconFgInverted = Color(0xFFffffff);
  static const historySendingInvertedIconFg = Color(0xC8ffffff);

  static const selectionCheckBgInactive = Color(0x40000000);
  static const selectionCheckBgActiveDay = Color(0xFF4ab44a);
  static const selectionCheckBgActiveNight = Color(0xFF5598db);
  static const selectionCheckBorder = Color(0xFFffffff);

  static const msgStickerOverlay = Color(0x7F358CD4);
  static const msgStickerOverlayNight = Color(0x7F3585D4);

  static const historyComposeAreaBg = Color(0xFFFFFFFF);
  static const historyComposeAreaBgNight = Color(0xFF17212B);
  static const historyComposeIconFg = Color(0xFF999999);
  static const historyComposeIconFgOver = Color(0xFF8a8a8a);
  static const historyComposeIconFgNight = Color(0xFF6c7883);
  static const historyComposeIconFgOverNight = Color(0xFFdcdcdc);

  static const bubbleSentShadow = Color(0x1d3ac346);
  static const bubbleSentShadowNight = Color(0x00000000);
  static const bubbleSentShadowSelected = Color(0x2237a78d);
  static const bubbleSentShadowSelectedNight = Color(0x00366ea6);
  static const bubbleReceivedShadow = Color(0x29748ea2);
  static const bubbleReceivedShadowNight = Color(0x00748ea2);
  static const bubbleReceivedShadowSelected = Color(0x29548dbb);
  static const bubbleReceivedShadowSelectedNight = Color(0x00538ebb);
}

class AppSizes {
  static const double railWidth = 68;
  static const double sidebarWidth = 272;
  static const double emojiPanelWidth = 345;
  static const double rightPanelWidth = 260;
  static const double bubbleRadius = 18;
  static const double bubbleTailRadius = 6;
  static const double avatarSize = 40;
  static const double avatarSizeSmall = 32;
  static const double railIconSize = 48;
}

class AppTheme {
  static ThemeData fromPalette(TelegramPalette p) {
    final isDark = p.isDark;
    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      fontFamily: 'Inter',
      colorScheme: isDark
          ? ColorScheme.dark(
              primary: p.windowBgActive,
              surface: p.windowBg,
              onSurface: p.windowFg,
              error: p.attentionButtonFg,
            )
          : ColorScheme.light(
              primary: p.windowBgActive,
              surface: p.windowBg,
              onSurface: p.windowFg,
              error: p.attentionButtonFg,
            ),
      scaffoldBackgroundColor: p.windowBg,
      dividerColor: p.shadowFg,
      cardColor: p.windowBgOver,
      textTheme: _textTheme(p.windowFg, p.windowSubTextFg),
      iconTheme: IconThemeData(color: p.menuIconFg, size: 20),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.windowBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.windowBgRipple),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.windowBgActive, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        hintStyle: TextStyle(color: p.windowSubTextFg),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(p.scrollBarBg),
        radius: const Radius.circular(4),
        thickness: WidgetStateProperty.all(6),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.tooltipBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: p.tooltipBorderFg, width: 1),
        ),
        textStyle: TextStyle(fontSize: 12, color: p.tooltipFg, height: 1.3),
        padding: const EdgeInsets.fromLTRB(5, 2, 5, 2),
        waitDuration: const Duration(milliseconds: 1000),
        showDuration: Duration.zero,
        preferBelow: true,
      ),
    );
  }

  static ThemeData get dark => fromPalette(TelegramPalette.night);
  static ThemeData get light => fromPalette(TelegramPalette.dayBlue);

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

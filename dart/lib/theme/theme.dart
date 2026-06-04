import 'package:flutter/material.dart';
import 'telegram_palette.dart';

export 'telegram_palette.dart';
export 'theme_file.dart';
export 'theme_tokens.dart';
export 'wallpaper.dart';

// NOTE: The former `AppColors` and `AppSizes` constant classes were deleted as
// dead, theme-blind duplicates of the authoritative `TelegramPalette` (per-theme
// colors) and `TgTokens` (AyuGram `.style` dimensions). Every theme-sensitive
// color now lives in `TelegramPalette` as the single source of truth — e.g. the
// message-selection checkbox reads `palette.boxTextFgGood` (chat.style:1246), so
// it is correct for every built-in and imported theme, not just day/night.

class AppTheme {
  static ThemeData fromPalette(TelegramPalette p, {String fontFamily = 'Inter'}) {
    final isDark = p.isDark;
    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      fontFamily: fontFamily,
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
        // AyuGram defaultInputField has borderRadius 0px, which routes to
        // InputField::paintFlatSurrounding (input_field.cpp:2388-2398): it draws
        // ONLY a bottom underline — a 1px resting line in borderFg=inputBorderFg
        // plus an animated 2px active line in borderFgActive=activeLineFg — not a
        // full box (paintRoundSurrounding is used only when borderRadius > 0).
        // So both borders are flat UnderlineInputBorder, no top-corner rounding
        // (border 1px / borderActive 2px, widgets.style:1058-1064).
        border: UnderlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: p.inputBorderFg),
        ),
        focusedBorder: UnderlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: p.activeLineFg, width: 2),
        ),
        // textMargins: margins(0px, 28px, 0px, 4px) — zero horizontal inset (text
        // flush to the field's left/right edges), 28px top reserving room for the
        // floating placeholder, 4px bottom (widgets.style:1045).
        contentPadding: const EdgeInsets.fromLTRB(0, 28, 0, 4),
        hintStyle: TextStyle(color: p.windowSubTextFg),
      ),
      scrollbarTheme: ScrollbarThemeData(
        // AyuGram scrollbar thumb width = width − 2·deltax = 4px (defaultScrollArea
        // 10−2·3, defaultSolidScroll 14−2·5; scroll_area.cpp:166); round 2px
        // (defaultScrollArea.round, widgets.style:822).
        thumbColor: WidgetStateProperty.all(p.scrollBarBg),
        radius: const Radius.circular(2),
        thickness: WidgetStateProperty.all(4),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.tooltipBg,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: p.tooltipBorderFg, width: 1),
        ),
        textStyle: TextStyle(fontSize: 13, color: p.tooltipFg, height: 1.3),
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

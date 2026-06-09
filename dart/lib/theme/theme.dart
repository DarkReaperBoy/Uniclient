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
  static ThemeData fromPalette(TelegramPalette p,
      {String fontFamily = 'Inter', List<String>? emojiFontFallback}) {
    final isDark = p.isDark;
    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      fontFamily: fontFamily,
      // Emoji rendering set (AyuGram Ui::Emoji::ManageSetsBox). Inter has no
      // emoji glyphs, so unicode emoji fall through to this chain; when the
      // user picks a bundled set (e.g. Twemoji) every theme-derived Text widget
      // renders emoji from it instead of the platform default font.
      fontFamilyFallback: emojiFontFallback,
      colorScheme: isDark
          ? ColorScheme.dark(
              primary: p.windowBgActive,
              // Material-3 FilledButton/ElevatedButton use colorScheme.onPrimary for
              // their label + icon color. AyuGram's defaultActiveButton.textFg is
              // activeButtonFg (= windowFgActive), white in every built-in theme
              // (widgets.style:728, colors.palette:35). ColorScheme.dark() otherwise
              // defaults onPrimary to Colors.black, which rendered black labels on the
              // #5288C1 blue accent in the default night theme.
              onPrimary: p.activeButtonFg,
              surface: p.windowBg,
              onSurface: p.windowFg,
              error: p.attentionButtonFg,
            )
          : ColorScheme.light(
              primary: p.windowBgActive,
              // ColorScheme.light() happens to default onPrimary to white, but map it
              // to activeButtonFg explicitly so imported themes follow their own token.
              onPrimary: p.activeButtonFg,
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

  // AyuGram's TextStyle struct has no letterSpacing field (basic.style:39-45) → zero
  // tracking, and defaultTextStyle.lineHeight: 0px (basic.style:84) → natural font
  // metrics. ThemeData composes the text theme as defaultTextTheme.merge(textTheme),
  // and TextStyle.merge keeps the base's non-overridden fields — so unless we pin them
  // here, Material-3 englishLike2021 leaks its letterSpacing (bodyLarge 0.5 … labelSmall
  // 0.5), loose line-heights (1.25–1.50) and leadingDistribution.even into all 177
  // textTheme.* call-sites, rendering body/dialog/message text looser and wider-tracked
  // than Telegram. We override all three on every slot. height 1.2 ≈ the intrinsic
  // ascent+descent of the default Inter font (what lineHeight:0 resolves to);
  // leadingDistribution.proportional matches natural metrics, not Material's even split.
  static TextStyle _slot(double size, FontWeight weight, Color color) => TextStyle(
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: 0,
    height: 1.2,
    leadingDistribution: TextLeadingDistribution.proportional,
  );

  static TextTheme _textTheme(Color primary, Color secondary) => TextTheme(
    headlineLarge: _slot(24, FontWeight.w700, primary),
    headlineMedium: _slot(20, FontWeight.w600, primary),
    titleLarge: _slot(16, FontWeight.w600, primary),
    titleMedium: _slot(14, FontWeight.w600, primary),
    // titleSmall was previously undefined → it fell back to the full Material default
    // (14px/w500/0.1 spacing/1.43 height). Both consumers (hamburger_drawer.dart:2350,
    // info_panel.dart:8290) already override the weight to w600 over a 14px label, so
    // define it to match while stopping the Material letterSpacing/line-height leak.
    titleSmall: _slot(14, FontWeight.w600, primary),
    bodyLarge: _slot(15, FontWeight.w400, primary),
    bodyMedium: _slot(14, FontWeight.w400, primary),
    bodySmall: _slot(12, FontWeight.w400, secondary),
    labelLarge: _slot(14, FontWeight.w500, primary),
    labelSmall: _slot(11, FontWeight.w500, secondary),
  );
}

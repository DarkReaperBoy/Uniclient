import 'package:flutter/widgets.dart';

abstract final class SettingsStyle {
  // §14.9 settingsButton: standard row with icon
  // Text starts at 60px from left edge (iconLeft + iconSize + iconGap).
  // In Flutter Row layout, use iconRowPadding on the Padding widget,
  // then Row([icon, SizedBox(iconGap), text, SizedBox(rightPad)]).
  static const iconRowPadding = EdgeInsets.fromLTRB(20, 10, 22, 10);
  static const double iconLeft = 20;
  static const double iconSize = 28;
  static const double iconGap = 12; // 20 + 28 + 12 = 60
  static const double iconRadius = 6;
  static const double iconInner = 18;
  static const double rowHeight = 41;
  static const double rightPad = 22;

  // settingsButton text padding: 60px left aligns text with icon-row text column
  static const buttonPadding = EdgeInsets.fromLTRB(60, 10, 22, 10);

  // §14.9 settingsButtonNoIcon: row without icon
  static const noIconPadding = EdgeInsets.fromLTRB(22, 10, 22, 8);

  // §14.9 settingsCheckboxPadding
  static const checkboxPadding = EdgeInsets.fromLTRB(22, 10, 10, 10);

  // §14.9 settingsSendTypePadding (radio rows)
  static const sendTypePadding = EdgeInsets.fromLTRB(22, 5, 10, 5);

  // §14.9 settingsBioMargins
  static const bioMargins = EdgeInsets.fromLTRB(22, 6, 22, 4);

  // §14.9 settingsCoverName font
  static const double coverNameSize = 17;
  static const FontWeight coverNameWeight = FontWeight.w600;

  // §14.9 settingsInfoPhotoSize / Height (Edit Profile)
  static const double infoPhotoSize = 100;
  static const double infoPhotoHeight = 162;

  // §14.9 other size tokens
  static const double accentColorSize = 24;
  static const double backgroundThumb = 76;
  static const Size themePreviewSize = Size(80, 92);
  static const Size themeBubbleSize = Size(40, 14);

  // Standard row text size used across all settings buttons
  static const double buttonFontSize = 14;
}

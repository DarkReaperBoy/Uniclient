import 'package:flutter/widgets.dart';

abstract final class TgTokens {
  // §56.1 — ui/basic.style global primitives

  // Font sizes (100% DPI baseline)
  static const double fsize = 13;
  static const double boxFontSize = 14;

  // Font styles
  static const TextStyle normalFont = TextStyle(fontSize: fsize);
  static const TextStyle semiboldFont =
      TextStyle(fontSize: fsize, fontWeight: FontWeight.w600);
  static const TextStyle linkFont = TextStyle(fontSize: fsize);
  static const TextStyle boxTextFont = TextStyle(fontSize: boxFontSize);

  // Layout primitives
  static const double lineWidth = 1;
  static const double defaultVerticalListSkip = 6;

  // Animation durations
  static const Duration slideDuration = Duration(milliseconds: 240);
  static const Duration slideWrapDuration = Duration(milliseconds: 150);
  static const Duration fadeWrapDuration = Duration(milliseconds: 200);
  static const Duration universalDuration = Duration(milliseconds: 120);

  // §56.2 — ui/layers/layers.style — layer / box chrome

  static const double boxWidth = 320;
  static const double boxWideWidth = 364;
  static const EdgeInsets boxPadding =
      EdgeInsets.fromLTRB(24, 14, 24, 8);
  static const double boxOptionListSkip = 20;
  static const double boxRadius = 6;
  static const Duration boxDuration = Duration(milliseconds: 200);
  static const double boxButtonHeight = 34;
  static const EdgeInsets boxButtonPadding =
      EdgeInsets.fromLTRB(6, 10, 10, 10);
  static const EdgeInsets boxMargin =
      EdgeInsets.fromLTRB(0, 10, 0, 10);

  // §56.3 — window/window.style — main-window layout

  static const double windowMinWidth = 380;
  static const double windowMinHeight = 480;
  static const double columnMinimalWidthLeft = 260;
  static const double columnMaximalWidthLeft = 540;
  static const double columnMinimalWidthMain = 380;
  static const double adaptiveChatWideWidth = 880;
  static const double topBarHeight = 54;
  static const Offset topBarMenuPosition = Offset(-6, 45);
  static const double topBarNameRightPadding = 3;
  static const double topBarActionSkip = 10;
  static const Size topBarInfoButtonSize = Size(52, 54);
  static const double topBarInfoButtonInnerSize = 42;
  static const double topBarConnectingSkip = 6;
  static const double topBarSearchWidth = 40;
  static const double topBarCloseChooseWidth = 56;
  static const double topBarMenuToggleWidth = 44;
  static const double topBarCallWidth = 40;

  // theme editor box (window.style — same file as the layout above).
  // Resolved literals: these are defined in window/window.style, NOT in a
  // separate theme_editor.style, so they belong in the resolved table.
  static const Size themeEditorSampleSize = Size(90, 51); // window.style:167 themeEditorSampleSize size(90px,51px)
  static const EdgeInsets themeEditorMargin =
      EdgeInsets.fromLTRB(17, 10, 17, 10); // window.style:168 themeEditorMargin margins(17px,10px,17px,10px)
  static const double themeEditorDescriptionSkip = 10; // window.style:169 themeEditorDescriptionSkip 10px
  static const TextStyle themeEditorNameFont =
      TextStyle(fontSize: 15, fontWeight: FontWeight.w600); // window.style:170 themeEditorNameFont font(15px semibold)

  // §56.4 — dialogs/dialogs.style — chat list

  static const double dialogsRowHeight = 62;
  static const double dialogsUnreadHeight = 19;
  static const double dialogsUnreadPadding = 5;
  static const double dialogsDateSkip = 5;
  static const double dialogsEmptyHeight = 160;
  static const double forumDialogRowHeight = 80;
  static const double dialogsPhotoSize = 46;
  static const double dialogsNameLeft = 68;
  static const double dialogsNameTop = 10;
  static const double dialogsTextLeft = 68;
  static const double dialogsTextTop = 34;
  static const EdgeInsets dialogsRowPadding =
      EdgeInsets.fromLTRB(10, 8, 10, 8);
  static const double dialogsStoriesFullHeight = 77;
  static const double dialogsStoriesFullPhoto = 42;
  static const double dialogsStoriesFullPhotoLeft = 10;
  static const double dialogsStoriesFullPhotoTop = 9;
  static const EdgeInsets contactsPadding =
      EdgeInsets.fromLTRB(16, 7, 16, 7);

  // §56.5 — chat_helpers/chat_helpers.style — compose row

  static const double historyReplySkip = 53;
  static const double historyReplyHeight = 49;
  static const Size emojiSetSize = Size(42, 39);
  static const Size emojiPanArea = Size(34, 32);
  static const Size stickersSize = Size(64, 64);
  static const EdgeInsets historySlowmodeCounterMargins =
      EdgeInsets.fromLTRB(0, 0, 10, 0);

  // §56.6 — boxes/boxes.style — contact / peer list boxes

  static const Size normalBoxLottieSize = Size(120, 120);

  // local-storage (cache) box rows (boxes.style — same file as above).
  static const double localStorageRowHeight = 50; // boxes.style:202 localStorageRowHeight 50px
  static const EdgeInsets localStorageRowPadding =
      EdgeInsets.fromLTRB(22, 5, 20, 5); // boxes.style:203 localStorageRowPadding margins(22px,5px,20px,5px)

  // passcode-lock box (boxes.style — same file as above).
  static const TextStyle passcodeHeaderFont =
      TextStyle(fontSize: 19); // boxes.style:290 passcodeHeaderFont font(19px)
  static const double passcodeHeaderHeight = 80; // boxes.style:291 passcodeHeaderHeight 80px
  static const EdgeInsets passcodePadding =
      EdgeInsets.fromLTRB(0, 0, 0, 5); // boxes.style:299 passcodePadding margins(0px,0px,0px,5px)

  // §56.7 — settings/settings.style — settings panels

  static const double settingsCloudPasswordIconSize = 100;
  static const double settingsPhotoTop = 8;
  static const double settingsPhotoBottom = 16;
  static const double settingsAccentColorSize = 24;
  static const double settingsAccentColorLine = 3;
  static const double settingsAccentColorSkip = 4;
  static const double settingsBackgroundThumb = 76;
  static const Size settingsThemePreviewSize = Size(80, 92);

  // §56.8 — info/info.style — profile & shared-media panes

  static const double infoDesiredWidth = 392;
  static const double infoLayerTopMinimal = 20;
  static const double infoLayerTopMaximal = 40;
  static const double infoMinimalLayerMargin = 48;
  static const double infoProfileSkip = 7;
  static const double infoTopBarHeight = 54;
  static const double infoTopBarScale = 0.7;
  static const Duration infoTopBarDuration = Duration(milliseconds: 150);
  static const double infoTopBarBackWidth = 60;
  static const double infoTopBarCloseWidth = 48;
  static const double infoTopBarSearchWidth = 56;
  static const double infoTopBarMenuWidth = 48;
  static const double infoTopBarForwardWidth = 46;

  // §56.9 — miscellaneous tokens

  static const double defaultInputFieldHeight = 55; // widgets.style:1070 defaultInputField.heightMin
  static const double defaultInputFieldFontSize = 14;
  static const double defaultRadioSize = 22;
  static const double defaultRadioStroke = 2;
  static const double defaultMultiSelectHeight = 32; // widgets.style:1082 defaultMultiSelectItem.height 32px
  // multi_select.cpp:184-186 paints the selected-contact pill with
  //   radius = min(AyuUserpic::ComputeRadius(height), height/2)
  // ComputeRadius(32) returns height/2 = 16 at the default avatarCorners
  // (23 == kMaxAvatarCorners → ayu_userpic.cpp:35), so min(16, 16) = 16 — a
  // full pill, not a rounded-rect. (Was 8 — a 50% under-rounding.)
  static const double defaultMultiSelectRadius = 16;
  static const double defaultRoundShadowBlur = 8;
  static const Offset defaultRoundShadowOffset = Offset(0, 2);
  // menuIconSize removed: invented/unsourced — no such token exists anywhere in
  // AyuGram (menu item icons are sized by their icon assets, not a scalar token).
  static const double radialSize = 50; // basic.style:118 radialSize size(50px,50px)
  static const double radialLine = 3;

  // §56.10 — palette quick-reference (22 most-referenced tokens)
  // All 22 tokens are defined in TelegramPalette with light/dark values
  // across 4 themes (dayBlue, night, classicDay, nightGreen).
  // See TelegramPalette fields: windowBg, windowBgActive, windowFg,
  // windowSubTextFg, windowBgOver, windowBoldFg, windowActiveTextFg,
  // boxBg, boxTextFg, boxTextFgError, boxDividerBg, layerBg,
  // msgServiceBg, msgServiceFg, msgInBg, msgOutBg, activeButtonBg,
  // activeButtonFg, menuIconFg, lightButtonFg, lightButtonFgOver,
  // attentionButtonFg.

  // §56.11 — derived / compound values
  static const double infoProfilePhotoSize = 72; // info.style:527 infoProfilePhotoInnerSize
  static const double settingsProfileCoverHeight = 162; // settings.style:205 settingsInfoPhotoHeight (photo: settingsInfoPhotoSize 100px)
  static const double defaultVerticalListSkipDouble = 12; // defaultVerticalListSkip * 2
  static const Duration defaultRadioDuration = Duration(milliseconds: 120); // widgets.style:868 defaultRadio.duration = universalDuration
  static const Duration defaultRadioDurationDouble = Duration(milliseconds: 240); // defaultRadioDuration * 2

  // §56.12 — false-positive st:: identifiers (NOT style tokens)
  // These appear in spec pseudocode but are C++ types/flags, not style tokens:
  // st::All, st::One, st::Box, st::Error, st::Id, st::Widget,
  // st::check, st::canAddCaption, st::hasGroupOption

  // §56.13 — coverage notes
  // ~99 tokens resolved with literal values (§56.1–56.9 above + TelegramPalette).
  // The theme-editor scalar tokens (themeEditorSampleSize/Margin/DescriptionSkip/
  // NameFont) live in window/window.style — NOT a separate theme_editor.style —
  // and the passcode/local-storage box scalars (passcodeHeaderFont/HeaderHeight/
  // Padding, localStorageRowHeight/RowPadding) live in boxes/boxes.style; all are
  // resolved above (§56.3, §56.6) with line citations, so they are no longer
  // listed here.
  //
  // The 16 below remain unresolved for concrete reasons, NOT because they sit in
  // an unread file:
  //   • intro.style: introStepFont, introStepSize, introTitleFont
  //   • OS/native dialogs (no .style literal): biometricPromptTitle,
  //     biometricPromptDescription, platformTitleFont
  //   • non-scalar widget-style objects (not a single literal): localStorageLimitSlider
  //     (MediaSlider, boxes.style:223)
  //   • palette colors → live in TelegramPalette, not as scalar tokens here:
  //     themeEditorNameFg
  //   • no matching definition in any .style file (no such token name exists in
  //     the AyuGram source): passcodeSubmitFont, passcodeLetterFont,
  //     passcodeDigitFont, localStorageClearFont
  //   • compose-files preview, not yet cross-referenced: composeFilesPreviewHeight,
  //     composeFilesPreviewPadding, composeAutocompleteMaxHeight, composeSlowmodeLabel
  static const List<String> unresolvedTokens = [
    'themeEditorNameFg',
    'passcodeSubmitFont',
    'passcodeLetterFont', 'passcodeDigitFont',
    'biometricPromptTitle', 'biometricPromptDescription',
    'introStepFont', 'introStepSize', 'introTitleFont',
    'localStorageLimitSlider', 'localStorageClearFont',
    'composeFilesPreviewHeight', 'composeFilesPreviewPadding',
    'composeAutocompleteMaxHeight', 'composeSlowmodeLabel',
    'platformTitleFont',
  ];
}

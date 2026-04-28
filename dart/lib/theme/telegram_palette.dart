import 'package:flutter/material.dart';

class TelegramPalette {
  // ── §25.2.1 Window & Global ──
  final Color windowBg;
  final Color windowBgOver;
  final Color windowBgRipple;
  final Color windowBgActive;
  final Color windowFg;
  final Color windowFgOver;
  final Color windowFgActive;
  final Color windowSubTextFg;
  final Color windowSubTextFgOver;
  final Color windowBoldFg;
  final Color windowBoldFgOver;
  final Color windowActiveTextFg;
  final Color windowShadowFg;
  final Color windowShadowFgFallback;
  final Color shadowFg;
  final Color titleBg;
  final Color titleBgActive;
  final Color titleShadow;
  final Color titleFg;
  final Color titleFgActive;
  final Color layerBg;

  // ── §25.2.2 + §57.9 Buttons ──
  final Color activeButtonBg;
  final Color activeButtonBgOver;
  final Color activeButtonBgRipple;
  final Color activeButtonFg;
  final Color activeButtonSecondaryFg;
  final Color activeLineFg;
  final Color activeLineFgError;
  final Color lightButtonBg;
  final Color lightButtonBgOver;
  final Color lightButtonBgRipple;
  final Color lightButtonFg;
  final Color attentionButtonFg;
  final Color attentionButtonBgOver;
  final Color attentionButtonBgRipple;
  final Color outlineButtonOutlineFg;

  // ── §25.2.3 + §57.2 Dialog List ──
  final Color dialogsBg;
  final Color dialogsBgOver;
  final Color dialogsBgActive;
  final Color dialogsRippleBg;
  final Color dialogsRippleBgActive;
  final Color dialogsNameFg;
  final Color dialogsNameFgOver;
  final Color dialogsNameFgActive;
  final Color dialogsTextFg;
  final Color dialogsTextFgOver;
  final Color dialogsTextFgActive;
  final Color dialogsTextFgService;
  final Color dialogsDateFg;
  final Color dialogsDraftFg;
  final Color dialogsUnreadBg;
  final Color dialogsUnreadBgMuted;
  final Color dialogsUnreadBgActive;
  final Color dialogsUnreadBgMutedActive;
  final Color dialogsUnreadFg;
  final Color dialogsUnreadFgActive;
  final Color dialogsOnlineBadgeFg;
  final Color dialogsOnlineBadgeFgActive;
  final Color dialogsSentIconFg;
  final Color dialogsSendingIconFg;
  final Color dialogsVerifiedIconBg;
  final Color dialogsVerifiedIconFg;
  final Color dialogsArchiveFg;
  final Color dialogsForwardBg;
  final Color dialogsForwardFg;

  // ── §57.3 Top Bar ──
  final Color topBarBg;

  // ── §25.2.4 + §57.4 Message Bubbles ──
  final Color msgInBg;
  final Color msgInBgSelected;
  final Color msgOutBg;
  final Color msgOutBgSelected;
  final Color msgInShadow;
  final Color msgOutShadow;
  final Color msgInDateFg;
  final Color msgOutDateFg;
  final Color msgInServiceFg;
  final Color msgOutServiceFg;
  final Color msgInReplyBarColor;
  final Color msgOutReplyBarColor;
  final Color msgInMonoFg;
  final Color msgOutMonoFg;
  final Color msgFileInBg;
  final Color msgFileOutBg;
  final Color msgServiceBg;
  final Color msgServiceBgSelected;
  final Color msgServiceFg;
  final Color msgSelectOverlay;
  final Color msgStickerOverlay;
  final Color msgDateImgBg;
  final Color msgDateImgBgOver;
  final Color msgDateImgBgSelected;

  // ── §57.5 History / Chat Area ──
  final Color historyTextInFg;
  final Color historyTextOutFg;
  final Color historyComposeAreaBg;
  final Color historyComposeAreaFg;
  final Color historyComposeIconFg;
  final Color historyComposeIconFgOver;
  final Color historyComposeButtonBg;
  final Color historyComposeButtonBgOver;
  final Color historyComposeButtonBgRipple;
  final Color historySendIconFg;
  final Color historyReplyBg;
  final Color historyReplyIconFg;
  final Color historyPinnedBg;
  final Color historyUnreadBarBg;
  final Color historyUnreadBarFg;
  final Color historyScrollBg;
  final Color historyScrollBgOver;
  final Color historyScrollBarBg;
  final Color historyScrollBarBgOver;
  final Color historyToDownBg;
  final Color historyToDownBgOver;
  final Color historyToDownFg;
  final Color historyOutIconFg;
  final Color historySendingOutIconFg;
  final Color historySendingInIconFg;
  final Color historyIconFgInverted;
  final Color historySendingInvertedIconFg;

  // ── §25.2.5 + §57.6 Peer Name Colors (8 colors) ──
  final Color historyPeer1NameFg;
  final Color historyPeer2NameFg;
  final Color historyPeer3NameFg;
  final Color historyPeer4NameFg;
  final Color historyPeer5NameFg;
  final Color historyPeer6NameFg;
  final Color historyPeer7NameFg;
  final Color historyPeer8NameFg;
  final Color historyPeer1UserpicBg;
  final Color historyPeer2UserpicBg;
  final Color historyPeer3UserpicBg;
  final Color historyPeer4UserpicBg;
  final Color historyPeer5UserpicBg;
  final Color historyPeer6UserpicBg;
  final Color historyPeer7UserpicBg;
  final Color historyPeer8UserpicBg;
  final Color historyPeer1UserpicBg2;
  final Color historyPeer2UserpicBg2;
  final Color historyPeer3UserpicBg2;
  final Color historyPeer4UserpicBg2;
  final Color historyPeer5UserpicBg2;
  final Color historyPeer6UserpicBg2;
  final Color historyPeer7UserpicBg2;
  final Color historyPeer8UserpicBg2;

  // ── §25.2.6 File Type Colors (4 groups × 4 states) ──
  final Color msgFile1Bg;
  final Color msgFile1BgDark;
  final Color msgFile1BgOver;
  final Color msgFile1BgSelected;
  final Color msgFile2Bg;
  final Color msgFile2BgDark;
  final Color msgFile2BgOver;
  final Color msgFile2BgSelected;
  final Color msgFile3Bg;
  final Color msgFile3BgDark;
  final Color msgFile3BgOver;
  final Color msgFile3BgSelected;
  final Color msgFile4Bg;
  final Color msgFile4BgDark;
  final Color msgFile4BgOver;
  final Color msgFile4BgSelected;

  // ── §25.2.7 Voice Waveform ──
  final Color msgWaveformInActive;
  final Color msgWaveformInInactive;
  final Color msgWaveformOutActive;
  final Color msgWaveformOutInactive;

  // ── §25.2.8 Media Viewer ──
  final Color mediaviewBg;
  final Color mediaviewControlBg;
  final Color mediaviewControlFg;
  final Color mediaviewCaptionBg;
  final Color mediaviewPlaybackActive;
  final Color mediaviewPlaybackInactive;
  final Color mediaviewPlaybackActiveOver;

  // ── §25.2.9 Intro / Login ──
  final Color introCoverTopBg;
  final Color introCoverBottomBg;
  final Color introCoverIconsFg;
  final Color introCoverPlaneTrace;
  final Color introCoverPlaneTop;

  // ── §25.2.10 Scrollbar ──
  final Color scrollBarBg;
  final Color scrollBarBgOver;
  final Color scrollBg;
  final Color scrollBgOver;

  // ── §57.7 Boxes / Dialogs ──
  final Color boxBg;
  final Color boxTextFg;
  final Color boxTitleFg;
  final Color boxSearchBg;
  final Color boxTitleAdditionalFg;
  final Color boxTextFgGood;
  final Color boxTextFgError;

  // ── §57.8 Profile / Info ──
  final Color profileStatusFgOver;
  final Color profileVerifiedCheckBg;
  final Color profileVerifiedCheckFg;
  final Color profileAdminStartFg;

  // ── §57.10 Sidebar (Folders Rail) ──
  final Color sideBarBg;
  final Color sideBarBgActive;
  final Color sideBarBgRipple;
  final Color sideBarTextFg;
  final Color sideBarTextFgActive;
  final Color sideBarIconFg;
  final Color sideBarIconFgActive;
  final Color sideBarBadgeBg;
  final Color sideBarBadgeBgMuted;
  final Color sideBarBadgeFg;

  // ── Menu ──
  final Color menuBg;
  final Color menuBgOver;
  final Color menuBgRipple;
  final Color menuIconFg;
  final Color menuIconFgOver;
  final Color menuSeparatorFg;

  // ── Main Menu / Hamburger ──
  final Color mainMenuBg;
  final Color mainMenuCoverBg;
  final Color mainMenuCoverFg;

  // ── Settings Icon Backgrounds (colorize-excluded) ──
  final Color settingsIconBg1;
  final Color settingsIconBg2;
  final Color settingsIconBg3;
  final Color settingsIconBg4;
  final Color settingsIconBg5;
  final Color settingsIconBg6;

  // ── Selection Checkbox ──
  final Color overviewCheckBg;

  const TelegramPalette({
    required this.windowBg,
    required this.windowBgOver,
    required this.windowBgRipple,
    required this.windowBgActive,
    required this.windowFg,
    required this.windowFgOver,
    required this.windowFgActive,
    required this.windowSubTextFg,
    required this.windowSubTextFgOver,
    required this.windowBoldFg,
    required this.windowBoldFgOver,
    required this.windowActiveTextFg,
    required this.windowShadowFg,
    required this.windowShadowFgFallback,
    required this.shadowFg,
    required this.titleBg,
    required this.titleBgActive,
    required this.titleShadow,
    required this.titleFg,
    required this.titleFgActive,
    required this.layerBg,
    required this.activeButtonBg,
    required this.activeButtonBgOver,
    required this.activeButtonBgRipple,
    required this.activeButtonFg,
    required this.activeButtonSecondaryFg,
    required this.activeLineFg,
    required this.activeLineFgError,
    required this.lightButtonBg,
    required this.lightButtonBgOver,
    required this.lightButtonBgRipple,
    required this.lightButtonFg,
    required this.attentionButtonFg,
    required this.attentionButtonBgOver,
    required this.attentionButtonBgRipple,
    required this.outlineButtonOutlineFg,
    required this.dialogsBg,
    required this.dialogsBgOver,
    required this.dialogsBgActive,
    required this.dialogsRippleBg,
    required this.dialogsRippleBgActive,
    required this.dialogsNameFg,
    required this.dialogsNameFgOver,
    required this.dialogsNameFgActive,
    required this.dialogsTextFg,
    required this.dialogsTextFgOver,
    required this.dialogsTextFgActive,
    required this.dialogsTextFgService,
    required this.dialogsDateFg,
    required this.dialogsDraftFg,
    required this.dialogsUnreadBg,
    required this.dialogsUnreadBgMuted,
    required this.dialogsUnreadBgActive,
    required this.dialogsUnreadBgMutedActive,
    required this.dialogsUnreadFg,
    required this.dialogsUnreadFgActive,
    required this.dialogsOnlineBadgeFg,
    required this.dialogsOnlineBadgeFgActive,
    required this.dialogsSentIconFg,
    required this.dialogsSendingIconFg,
    required this.dialogsVerifiedIconBg,
    required this.dialogsVerifiedIconFg,
    required this.dialogsArchiveFg,
    required this.dialogsForwardBg,
    required this.dialogsForwardFg,
    required this.topBarBg,
    required this.msgInBg,
    required this.msgInBgSelected,
    required this.msgOutBg,
    required this.msgOutBgSelected,
    required this.msgInShadow,
    required this.msgOutShadow,
    required this.msgInDateFg,
    required this.msgOutDateFg,
    required this.msgInServiceFg,
    required this.msgOutServiceFg,
    required this.msgInReplyBarColor,
    required this.msgOutReplyBarColor,
    required this.msgInMonoFg,
    required this.msgOutMonoFg,
    required this.msgFileInBg,
    required this.msgFileOutBg,
    required this.msgServiceBg,
    required this.msgServiceBgSelected,
    required this.msgServiceFg,
    required this.msgSelectOverlay,
    required this.msgStickerOverlay,
    required this.msgDateImgBg,
    required this.msgDateImgBgOver,
    required this.msgDateImgBgSelected,
    required this.historyTextInFg,
    required this.historyTextOutFg,
    required this.historyComposeAreaBg,
    required this.historyComposeAreaFg,
    required this.historyComposeIconFg,
    required this.historyComposeIconFgOver,
    required this.historyComposeButtonBg,
    required this.historyComposeButtonBgOver,
    required this.historyComposeButtonBgRipple,
    required this.historySendIconFg,
    required this.historyReplyBg,
    required this.historyReplyIconFg,
    required this.historyPinnedBg,
    required this.historyUnreadBarBg,
    required this.historyUnreadBarFg,
    required this.historyScrollBg,
    required this.historyScrollBgOver,
    required this.historyScrollBarBg,
    required this.historyScrollBarBgOver,
    required this.historyToDownBg,
    required this.historyToDownBgOver,
    required this.historyToDownFg,
    required this.historyOutIconFg,
    required this.historySendingOutIconFg,
    required this.historySendingInIconFg,
    required this.historyIconFgInverted,
    required this.historySendingInvertedIconFg,
    required this.historyPeer1NameFg,
    required this.historyPeer2NameFg,
    required this.historyPeer3NameFg,
    required this.historyPeer4NameFg,
    required this.historyPeer5NameFg,
    required this.historyPeer6NameFg,
    required this.historyPeer7NameFg,
    required this.historyPeer8NameFg,
    required this.historyPeer1UserpicBg,
    required this.historyPeer2UserpicBg,
    required this.historyPeer3UserpicBg,
    required this.historyPeer4UserpicBg,
    required this.historyPeer5UserpicBg,
    required this.historyPeer6UserpicBg,
    required this.historyPeer7UserpicBg,
    required this.historyPeer8UserpicBg,
    required this.historyPeer1UserpicBg2,
    required this.historyPeer2UserpicBg2,
    required this.historyPeer3UserpicBg2,
    required this.historyPeer4UserpicBg2,
    required this.historyPeer5UserpicBg2,
    required this.historyPeer6UserpicBg2,
    required this.historyPeer7UserpicBg2,
    required this.historyPeer8UserpicBg2,
    required this.msgFile1Bg,
    required this.msgFile1BgDark,
    required this.msgFile1BgOver,
    required this.msgFile1BgSelected,
    required this.msgFile2Bg,
    required this.msgFile2BgDark,
    required this.msgFile2BgOver,
    required this.msgFile2BgSelected,
    required this.msgFile3Bg,
    required this.msgFile3BgDark,
    required this.msgFile3BgOver,
    required this.msgFile3BgSelected,
    required this.msgFile4Bg,
    required this.msgFile4BgDark,
    required this.msgFile4BgOver,
    required this.msgFile4BgSelected,
    required this.msgWaveformInActive,
    required this.msgWaveformInInactive,
    required this.msgWaveformOutActive,
    required this.msgWaveformOutInactive,
    required this.mediaviewBg,
    required this.mediaviewControlBg,
    required this.mediaviewControlFg,
    required this.mediaviewCaptionBg,
    required this.mediaviewPlaybackActive,
    required this.mediaviewPlaybackInactive,
    required this.mediaviewPlaybackActiveOver,
    required this.introCoverTopBg,
    required this.introCoverBottomBg,
    required this.introCoverIconsFg,
    required this.introCoverPlaneTrace,
    required this.introCoverPlaneTop,
    required this.scrollBarBg,
    required this.scrollBarBgOver,
    required this.scrollBg,
    required this.scrollBgOver,
    required this.boxBg,
    required this.boxTextFg,
    required this.boxTitleFg,
    required this.boxSearchBg,
    required this.boxTitleAdditionalFg,
    required this.boxTextFgGood,
    required this.boxTextFgError,
    required this.profileStatusFgOver,
    required this.profileVerifiedCheckBg,
    required this.profileVerifiedCheckFg,
    required this.profileAdminStartFg,
    required this.sideBarBg,
    required this.sideBarBgActive,
    required this.sideBarBgRipple,
    required this.sideBarTextFg,
    required this.sideBarTextFgActive,
    required this.sideBarIconFg,
    required this.sideBarIconFgActive,
    required this.sideBarBadgeBg,
    required this.sideBarBadgeBgMuted,
    required this.sideBarBadgeFg,
    required this.menuBg,
    required this.menuBgOver,
    required this.menuBgRipple,
    required this.menuIconFg,
    required this.menuIconFgOver,
    required this.menuSeparatorFg,
    required this.mainMenuBg,
    required this.mainMenuCoverBg,
    required this.mainMenuCoverFg,
    required this.settingsIconBg1,
    required this.settingsIconBg2,
    required this.settingsIconBg3,
    required this.settingsIconBg4,
    required this.settingsIconBg5,
    required this.settingsIconBg6,
    required this.overviewCheckBg,
  });

  bool get isDark {
    final hsv = HSVColor.fromColor(dialogsBg);
    return hsv.value < 0.5;
  }

  Color peerNameColor(int index) => switch (index % 8) {
    0 => historyPeer1NameFg,
    1 => historyPeer2NameFg,
    2 => historyPeer3NameFg,
    3 => historyPeer4NameFg,
    4 => historyPeer5NameFg,
    5 => historyPeer6NameFg,
    6 => historyPeer7NameFg,
    _ => historyPeer8NameFg,
  };

  Color peerUserpicBg(int index) => switch (index % 8) {
    0 => historyPeer1UserpicBg,
    1 => historyPeer2UserpicBg,
    2 => historyPeer3UserpicBg,
    3 => historyPeer4UserpicBg,
    4 => historyPeer5UserpicBg,
    5 => historyPeer6UserpicBg,
    6 => historyPeer7UserpicBg,
    _ => historyPeer8UserpicBg,
  };

  Color peerUserpicBg2(int index) => switch (index % 8) {
    0 => historyPeer1UserpicBg2,
    1 => historyPeer2UserpicBg2,
    2 => historyPeer3UserpicBg2,
    3 => historyPeer4UserpicBg2,
    4 => historyPeer5UserpicBg2,
    5 => historyPeer6UserpicBg2,
    6 => historyPeer7UserpicBg2,
    _ => historyPeer8UserpicBg2,
  };

  Color fileTypeBg(int type) => switch (type % 4) {
    0 => msgFile1Bg,
    1 => msgFile2Bg,
    2 => msgFile3Bg,
    _ => msgFile4Bg,
  };

  Color fileTypeBgDark(int type) => switch (type % 4) {
    0 => msgFile1BgDark,
    1 => msgFile2BgDark,
    2 => msgFile3BgDark,
    _ => msgFile4BgDark,
  };

  // ── Day Blue (§25.3.2) ──
  // Values from §25.2 tables + §57 appendix.
  // Hex conversion: Telegram #RRGGBBAA → Flutter Color(0xAARRGGBB).
  static const dayBlue = TelegramPalette(
    // Window & Global
    windowBg: Color(0xFFFFFFFF),
    windowBgOver: Color(0xFFF1F1F1),
    windowBgRipple: Color(0xFFE5E5E5),
    windowBgActive: Color(0xFF40A7E3),
    windowFg: Color(0xFF000000),
    windowFgOver: Color(0xFF000000),
    windowFgActive: Color(0xFFFFFFFF),
    windowSubTextFg: Color(0xFF999999),
    windowSubTextFgOver: Color(0xFF919191),
    windowBoldFg: Color(0xFF222222),
    windowBoldFgOver: Color(0xFF222222),
    windowActiveTextFg: Color(0xFF168ACD),
    windowShadowFg: Color(0xFF000000),
    windowShadowFgFallback: Color(0xFFF1F1F1),
    shadowFg: Color(0x18000000),
    titleBg: Color(0xFFF1F1F1),
    titleBgActive: Color(0xFFF1F1F1),
    titleShadow: Color(0x03000000),
    titleFg: Color(0xFFACACAC),
    titleFgActive: Color(0xFF3E3C3E),
    layerBg: Color(0x7F000000),

    // Buttons
    activeButtonBg: Color(0xFF40A7E3),
    activeButtonBgOver: Color(0xFF39A5DB),
    activeButtonBgRipple: Color(0xFF2095D0),
    activeButtonFg: Color(0xFFFFFFFF),
    activeButtonSecondaryFg: Color(0xFFCCEEFF),
    activeLineFg: Color(0xFF37A1DE),
    activeLineFgError: Color(0xFFE48383),
    lightButtonBg: Color(0xFFFFFFFF),
    lightButtonBgOver: Color(0xFFE3F1FA),
    lightButtonBgRipple: Color(0xFFC9E4F6),
    lightButtonFg: Color(0xFF168ACD),
    attentionButtonFg: Color(0xFFD14E4E),
    attentionButtonBgOver: Color(0xFFFCDFDE),
    attentionButtonBgRipple: Color(0xFFF4C3C2),
    outlineButtonOutlineFg: Color(0xFF40A7E3),

    // Dialogs
    dialogsBg: Color(0xFFFFFFFF),
    dialogsBgOver: Color(0xFFF1F1F1),
    dialogsBgActive: Color(0xFF419FD9),
    dialogsRippleBg: Color(0xFFE5E5E5),
    dialogsRippleBgActive: Color(0xFF2095D0),
    dialogsNameFg: Color(0xFF222222),
    dialogsNameFgOver: Color(0xFF222222),
    dialogsNameFgActive: Color(0xFFFFFFFF),
    dialogsTextFg: Color(0xFF999999),
    dialogsTextFgOver: Color(0xFF919191),
    dialogsTextFgActive: Color(0xFFFFFFFF),
    dialogsTextFgService: Color(0xFF168ACD),
    dialogsDateFg: Color(0xFF999999),
    dialogsDraftFg: Color(0xFFDD4B39),
    dialogsUnreadBg: Color(0xFF40A7E3),
    dialogsUnreadBgMuted: Color(0xFFBBBBBB),
    dialogsUnreadBgActive: Color(0xFFFFFFFF),
    dialogsUnreadBgMutedActive: Color(0xFFC6E1F7),
    dialogsUnreadFg: Color(0xFFFFFFFF),
    dialogsUnreadFgActive: Color(0xFF419FD9),
    dialogsOnlineBadgeFg: Color(0xFF4DC920),
    dialogsOnlineBadgeFgActive: Color(0xFFFFFFFF),
    dialogsSentIconFg: Color(0xFF5DC452),
    dialogsSendingIconFg: Color(0xFFC1C1C1),
    dialogsVerifiedIconBg: Color(0xFF40A7E3),
    dialogsVerifiedIconFg: Color(0xFFFFFFFF),
    dialogsArchiveFg: Color(0xFF525252),
    dialogsForwardBg: Color(0xFF419FD9),
    dialogsForwardFg: Color(0xFFFFFFFF),

    // Top Bar
    topBarBg: Color(0xFFFFFFFF),

    // Message Bubbles
    msgInBg: Color(0xFFFFFFFF),
    msgInBgSelected: Color(0xFFC2DCF2),
    msgOutBg: Color(0xFFEFFDDE),
    msgOutBgSelected: Color(0xFFCBEBB5),
    msgInShadow: Color(0x29748EA2),
    msgOutShadow: Color(0x1D3AC346),
    msgInDateFg: Color(0xFFA0ACB6),
    msgOutDateFg: Color(0xFF6FAB69),
    msgInServiceFg: Color(0xFF168ACD),
    msgOutServiceFg: Color(0xFF529E39),
    msgInReplyBarColor: Color(0xFF37A1DE),
    msgOutReplyBarColor: Color(0xFF64B05C),
    msgInMonoFg: Color(0xFF4E7391),
    msgOutMonoFg: Color(0xFF459866),
    msgFileInBg: Color(0xFF40A7E3),
    msgFileOutBg: Color(0xFF60B867),
    msgServiceBg: Color(0x90527C41),
    msgServiceBgSelected: Color(0x8396B38B),
    msgServiceFg: Color(0xFFFFFFFF),
    msgSelectOverlay: Color(0x4C358CD4),
    msgStickerOverlay: Color(0x7F358CD4),
    msgDateImgBg: Color(0x54000000),
    msgDateImgBgOver: Color(0x74000000),
    msgDateImgBgSelected: Color(0x871C4A71),

    // History / Chat Area
    historyTextInFg: Color(0xFF000000),
    historyTextOutFg: Color(0xFF000000),
    historyComposeAreaBg: Color(0xFFFFFFFF),
    historyComposeAreaFg: Color(0xFF000000),
    historyComposeIconFg: Color(0xFF999999),
    historyComposeIconFgOver: Color(0xFF8A8A8A),
    historyComposeButtonBg: Color(0xFFFFFFFF),
    historyComposeButtonBgOver: Color(0xFFF1F1F1),
    historyComposeButtonBgRipple: Color(0xFFE5E5E5),
    historySendIconFg: Color(0xFF40A7E3),
    historyReplyBg: Color(0xFFFFFFFF),
    historyReplyIconFg: Color(0xFF40A7E3),
    historyPinnedBg: Color(0xFFFFFFFF),
    historyUnreadBarBg: Color(0xFFFCFBFA),
    historyUnreadBarFg: Color(0xFF538BB4),
    historyScrollBg: Color(0x4C517C41),
    historyScrollBgOver: Color(0x6B517C41),
    historyScrollBarBg: Color(0x7A517C41),
    historyScrollBarBgOver: Color(0xBC517C41),
    historyToDownBg: Color(0xFFFFFFFF),
    historyToDownBgOver: Color(0xFFF1F1F1),
    historyToDownFg: Color(0xFF999999),
    historyOutIconFg: Color(0xFF5DC452),
    historySendingOutIconFg: Color(0xFF98D292),
    historySendingInIconFg: Color(0xFFA0ADB5),
    historyIconFgInverted: Color(0xFFFFFFFF),
    historySendingInvertedIconFg: Color(0xC8FFFFFF),

    // Peer Name Colors
    historyPeer1NameFg: Color(0xFFC03D33),
    historyPeer2NameFg: Color(0xFF4FAD2D),
    historyPeer3NameFg: Color(0xFFD09306),
    historyPeer4NameFg: Color(0xFF168ACD),
    historyPeer5NameFg: Color(0xFF8544D6),
    historyPeer6NameFg: Color(0xFFCD4073),
    historyPeer7NameFg: Color(0xFF2996AD),
    historyPeer8NameFg: Color(0xFFCE671B),
    historyPeer1UserpicBg: Color(0xFFFF845E),
    historyPeer2UserpicBg: Color(0xFF9AD164),
    historyPeer3UserpicBg: Color(0xFFE5CA77),
    historyPeer4UserpicBg: Color(0xFF5CAFFA),
    historyPeer5UserpicBg: Color(0xFFB694F9),
    historyPeer6UserpicBg: Color(0xFFFF8AAC),
    historyPeer7UserpicBg: Color(0xFF5BCBE3),
    historyPeer8UserpicBg: Color(0xFFFEBB5B),
    historyPeer1UserpicBg2: Color(0xFFD45246),
    historyPeer2UserpicBg2: Color(0xFF46BA43),
    historyPeer3UserpicBg2: Color(0xFFE5CA77),
    historyPeer4UserpicBg2: Color(0xFF408ACF),
    historyPeer5UserpicBg2: Color(0xFF6C61DF),
    historyPeer6UserpicBg2: Color(0xFFD95574),
    historyPeer7UserpicBg2: Color(0xFF359AD4),
    historyPeer8UserpicBg2: Color(0xFFF68136),

    // File Type Colors
    msgFile1Bg: Color(0xFF72B1DF),
    msgFile1BgDark: Color(0xFF5C9ECE),
    msgFile1BgOver: Color(0xFF5294C4),
    msgFile1BgSelected: Color(0xFF5099D0),
    msgFile2Bg: Color(0xFF61B96E),
    msgFile2BgDark: Color(0xFF4DA859),
    msgFile2BgOver: Color(0xFF44A050),
    msgFile2BgSelected: Color(0xFF46A07E),
    msgFile3Bg: Color(0xFFE47272),
    msgFile3BgDark: Color(0xFFCD5B5E),
    msgFile3BgOver: Color(0xFFC35154),
    msgFile3BgSelected: Color(0xFF9F6A82),
    msgFile4Bg: Color(0xFFEFC274),
    msgFile4BgDark: Color(0xFFE6A561),
    msgFile4BgOver: Color(0xFFDC9C5A),
    msgFile4BgSelected: Color(0xFFB19D84),

    // Voice Waveform
    msgWaveformInActive: Color(0xFF40A7E3),
    msgWaveformInInactive: Color(0xFFD4DEE6),
    msgWaveformOutActive: Color(0xFF40A7E3),
    msgWaveformOutInactive: Color(0xFFB3D4E7),

    // Media Viewer
    mediaviewBg: Color(0xEB222222),
    mediaviewControlBg: Color(0x3C000000),
    mediaviewControlFg: Color(0xFFFFFFFF),
    mediaviewCaptionBg: Color(0x80111111),
    mediaviewPlaybackActive: Color(0xFFC7C7C7),
    mediaviewPlaybackInactive: Color(0xFF252525),
    mediaviewPlaybackActiveOver: Color(0xFFFFFFFF),

    // Intro / Login
    introCoverTopBg: Color(0xFF0F89D0),
    introCoverBottomBg: Color(0xFF39B0F0),
    introCoverIconsFg: Color(0xFF5EC6FF),
    introCoverPlaneTrace: Color(0x695EC6FF),
    introCoverPlaneTop: Color(0xFFFFFFFF),

    // Scrollbar
    scrollBarBg: Color(0x53000000),
    scrollBarBgOver: Color(0x7A000000),
    scrollBg: Color(0x00000000),
    scrollBgOver: Color(0x1A000000),

    // Boxes
    boxBg: Color(0xFFFFFFFF),
    boxTextFg: Color(0xFF000000),
    boxTitleFg: Color(0xFF404040),
    boxSearchBg: Color(0xFFFFFFFF),
    boxTitleAdditionalFg: Color(0xFF808080),
    boxTextFgGood: Color(0xFF4AB44A),
    boxTextFgError: Color(0xFFD84D4D),

    // Profile
    profileStatusFgOver: Color(0xFF7C99B2),
    profileVerifiedCheckBg: Color(0xFF40A7E3),
    profileVerifiedCheckFg: Color(0xFFFFFFFF),
    profileAdminStartFg: Color(0xFF40A7E3),

    // Sidebar
    sideBarBg: Color(0xFF293A4C),
    sideBarBgActive: Color(0xFF17212B),
    sideBarBgRipple: Color(0xFF1E2B38),
    sideBarTextFg: Color(0xFF8897A6),
    sideBarTextFgActive: Color(0xFF64B9FA),
    sideBarIconFg: Color(0xFF8393A3),
    sideBarIconFgActive: Color(0xFF5EB5F7),
    sideBarBadgeBg: Color(0xFF5EB5F7),
    sideBarBadgeBgMuted: Color(0xFF8393A3),
    sideBarBadgeFg: Color(0xFFFFFFFF),

    // Menu
    menuBg: Color(0xFFFFFFFF),
    menuBgOver: Color(0xFFF1F1F1),
    menuBgRipple: Color(0xFFE5E5E5),
    menuIconFg: Color(0xFF999999),
    menuIconFgOver: Color(0xFF8A8A8A),
    menuSeparatorFg: Color(0xFFE5E5E5),

    // Main Menu
    mainMenuBg: Color(0xFFFFFFFF),
    mainMenuCoverBg: Color(0xFF40A7E3),
    mainMenuCoverFg: Color(0xFFFFFFFF),

    // Settings Icons
    settingsIconBg1: Color(0xFF5BBB6F),
    settingsIconBg2: Color(0xFFEC7577),
    settingsIconBg3: Color(0xFF43A4DF),
    settingsIconBg4: Color(0xFFFAAD38),
    settingsIconBg5: Color(0xFF9A7BDF),
    settingsIconBg6: Color(0xFF5ABDD6),

    // Selection
    overviewCheckBg: Color(0x40000000),
  );

  // ── Night / Tinted (§25.3.3) ──
  // Values from §25.2 tables + §57 appendix.
  static const night = TelegramPalette(
    // Window & Global
    windowBg: Color(0xFF17212B),
    windowBgOver: Color(0xFF232E3C),
    windowBgRipple: Color(0xFF24303D),
    windowBgActive: Color(0xFF5288C1),
    windowFg: Color(0xFFF5F5F5),
    windowFgOver: Color(0xFFE9ECF0),
    windowFgActive: Color(0xFFFFFFFF),
    windowSubTextFg: Color(0xFF708499),
    windowSubTextFgOver: Color(0xFF7C90A4),
    windowBoldFg: Color(0xFFE9E8E8),
    windowBoldFgOver: Color(0xFFE9E9E9),
    windowActiveTextFg: Color(0xFF6AB3F3),
    windowShadowFg: Color(0xFF000000),
    windowShadowFgFallback: Color(0xFF17212B),
    shadowFg: Color(0x5604080E),
    titleBg: Color(0xFF1F2936),
    titleBgActive: Color(0xFF242F3D),
    titleShadow: Color(0x00000000),
    titleFg: Color(0xFF6A7680),
    titleFgActive: Color(0xFF91A3B3),
    layerBg: Color(0x7F000000),

    // Buttons
    activeButtonBg: Color(0xFF2F6EA5),
    activeButtonBgOver: Color(0xFF3476AB),
    activeButtonBgRipple: Color(0xFF3B7CB1),
    activeButtonFg: Color(0xFFFFFFFF),
    activeButtonSecondaryFg: Color(0xFF9ABFE7),
    activeLineFg: Color(0xFF6396CB),
    activeLineFgError: Color(0xFFEF5959),
    lightButtonBg: Color(0xFF17212B),
    lightButtonBgOver: Color(0xFF1D2A39),
    lightButtonBgRipple: Color(0xFF223143),
    lightButtonFg: Color(0xFF6AB2F2),
    attentionButtonFg: Color(0xFFEC3942),
    attentionButtonBgOver: Color(0x64592A2A),
    attentionButtonBgRipple: Color(0x64683232),
    outlineButtonOutlineFg: Color(0xFF3983C3),

    // Dialogs
    dialogsBg: Color(0xFF17212B),
    dialogsBgOver: Color(0xFF202B36),
    dialogsBgActive: Color(0xFF2B5278),
    dialogsRippleBg: Color(0xFF25313D),
    dialogsRippleBgActive: Color(0xFF315A80),
    dialogsNameFg: Color(0xFFF5F5F5),
    dialogsNameFgOver: Color(0xFFE9E9E9),
    dialogsNameFgActive: Color(0xFFFFFFFF),
    dialogsTextFg: Color(0xFF7F91A4),
    dialogsTextFgOver: Color(0xFF91A3B5),
    dialogsTextFgActive: Color(0xFFFFFFFF),
    dialogsTextFgService: Color(0xFF73B9F5),
    dialogsDateFg: Color(0xFF8696A8),
    dialogsDraftFg: Color(0xFFFF525D),
    dialogsUnreadBg: Color(0xFF4082BC),
    dialogsUnreadBgMuted: Color(0xFF3E546A),
    dialogsUnreadBgActive: Color(0xFFFFFFFF),
    dialogsUnreadBgMutedActive: Color(0xFF7AA3CA),
    dialogsUnreadFg: Color(0xFFFFFFFF),
    dialogsUnreadFgActive: Color(0xFF2A5378),
    dialogsOnlineBadgeFg: Color(0xFF63B6FF),
    dialogsOnlineBadgeFgActive: Color(0xFFFFFFFF),
    dialogsSentIconFg: Color(0xFF72BCFD),
    dialogsSendingIconFg: Color(0xFF647D96),
    dialogsVerifiedIconBg: Color(0xFF6AB3F3),
    dialogsVerifiedIconFg: Color(0xFF17212B),
    dialogsArchiveFg: Color(0xFF708499),
    dialogsForwardBg: Color(0xFF2B5278),
    dialogsForwardFg: Color(0xFFFFFFFF),

    // Top Bar
    topBarBg: Color(0xFF17212B),

    // Message Bubbles
    msgInBg: Color(0xFF182533),
    msgInBgSelected: Color(0xFF2E70A5),
    msgOutBg: Color(0xFF2B5278),
    msgOutBgSelected: Color(0xFF2E70A5),
    msgInShadow: Color(0x00748EA2),
    msgOutShadow: Color(0x00000000),
    msgInDateFg: Color(0xFF7A858F),
    msgOutDateFg: Color(0xFF7DA8D3),
    msgInServiceFg: Color(0xFF71BAFA),
    msgOutServiceFg: Color(0xFFFFFFFF),
    msgInReplyBarColor: Color(0xFF429BDB),
    msgOutReplyBarColor: Color(0xFF65B9F4),
    msgInMonoFg: Color(0xFF5A8CB7),
    msgOutMonoFg: Color(0xFFBAD9F6),
    msgFileInBg: Color(0xFF3F96D0),
    msgFileOutBg: Color(0xFFFFFFFF),
    msgServiceBg: Color(0xD51E2429),
    msgServiceBgSelected: Color(0xFF2E7AB4),
    msgServiceFg: Color(0xFFFFFFFF),
    msgSelectOverlay: Color(0x4C3585D4),
    msgStickerOverlay: Color(0x7F3585D4),
    msgDateImgBg: Color(0x54000000),
    msgDateImgBgOver: Color(0x74000000),
    msgDateImgBgSelected: Color(0x87204F78),

    // History / Chat Area
    historyTextInFg: Color(0xFFF5F5F5),
    historyTextOutFg: Color(0xFFF5F5F5),
    historyComposeAreaBg: Color(0xFF17212B),
    historyComposeAreaFg: Color(0xFFF5F5F5),
    historyComposeIconFg: Color(0xFF6C7883),
    historyComposeIconFgOver: Color(0xFFDCDCDC),
    historyComposeButtonBg: Color(0xFF17212B),
    historyComposeButtonBgOver: Color(0xFF1C2835),
    historyComposeButtonBgRipple: Color(0xFF222F3E),
    historySendIconFg: Color(0xFF5288C1),
    historyReplyBg: Color(0xFF17212B),
    historyReplyIconFg: Color(0xFF5288C1),
    historyPinnedBg: Color(0xFF181E24),
    historyUnreadBarBg: Color(0xFF182433),
    historyUnreadBarFg: Color(0xFFFFFFFF),
    historyScrollBg: Color(0x4C565A5E),
    historyScrollBgOver: Color(0x6B5A5D61),
    historyScrollBarBg: Color(0x7A7F8489),
    historyScrollBarBgOver: Color(0xBC64686C),
    historyToDownBg: Color(0xFF1D2B3A),
    historyToDownBgOver: Color(0xFF243446),
    historyToDownFg: Color(0xFFADB4BA),
    historyOutIconFg: Color(0xFF62B2FD),
    historySendingOutIconFg: Color(0xFF70A4D2),
    historySendingInIconFg: Color(0xFF76838B),
    historyIconFgInverted: Color(0xFFFFFFFF),
    historySendingInvertedIconFg: Color(0xC8FFFFFF),

    // Peer Name Colors
    historyPeer1NameFg: Color(0xFFFB6169),
    historyPeer2NameFg: Color(0xFF85DE85),
    historyPeer3NameFg: Color(0xFFF3BC5C),
    historyPeer4NameFg: Color(0xFF65BDF3),
    historyPeer5NameFg: Color(0xFFB48BF2),
    historyPeer6NameFg: Color(0xFFFF5694),
    historyPeer7NameFg: Color(0xFF62D4E3),
    historyPeer8NameFg: Color(0xFFFAA357),
    historyPeer1UserpicBg: Color(0xFFFF845E),
    historyPeer2UserpicBg: Color(0xFF9AD164),
    historyPeer3UserpicBg: Color(0xFFE5CA77),
    historyPeer4UserpicBg: Color(0xFF5CAFFA),
    historyPeer5UserpicBg: Color(0xFFB694F9),
    historyPeer6UserpicBg: Color(0xFFFF8AAC),
    historyPeer7UserpicBg: Color(0xFF5BCBE3),
    historyPeer8UserpicBg: Color(0xFFFEBB5B),
    historyPeer1UserpicBg2: Color(0xFFD45246),
    historyPeer2UserpicBg2: Color(0xFF46BA43),
    historyPeer3UserpicBg2: Color(0xFFE5CA77),
    historyPeer4UserpicBg2: Color(0xFF408ACF),
    historyPeer5UserpicBg2: Color(0xFF6C61DF),
    historyPeer6UserpicBg2: Color(0xFFD95574),
    historyPeer7UserpicBg2: Color(0xFF359AD4),
    historyPeer8UserpicBg2: Color(0xFFF68136),

    // File Type Colors (same across all themes — colorize-excluded)
    msgFile1Bg: Color(0xFF72B1DF),
    msgFile1BgDark: Color(0xFF5C9ECE),
    msgFile1BgOver: Color(0xFF5294C4),
    msgFile1BgSelected: Color(0xFF5099D0),
    msgFile2Bg: Color(0xFF61B96E),
    msgFile2BgDark: Color(0xFF4DA859),
    msgFile2BgOver: Color(0xFF44A050),
    msgFile2BgSelected: Color(0xFF46A07E),
    msgFile3Bg: Color(0xFFE47272),
    msgFile3BgDark: Color(0xFFCD5B5E),
    msgFile3BgOver: Color(0xFFC35154),
    msgFile3BgSelected: Color(0xFF9F6A82),
    msgFile4Bg: Color(0xFFEFC274),
    msgFile4BgDark: Color(0xFFE6A561),
    msgFile4BgOver: Color(0xFFDC9C5A),
    msgFile4BgSelected: Color(0xFFB19D84),

    // Voice Waveform
    msgWaveformInActive: Color(0xFF549CD7),
    msgWaveformInInactive: Color(0xFF3A4D61),
    msgWaveformOutActive: Color(0xFF62B2FD),
    msgWaveformOutInactive: Color(0xFF4B7FB3),

    // Media Viewer
    mediaviewBg: Color(0xEB222222),
    mediaviewControlBg: Color(0x3C000000),
    mediaviewControlFg: Color(0xFFFFFFFF),
    mediaviewCaptionBg: Color(0x80111111),
    mediaviewPlaybackActive: Color(0xFFC7C7C7),
    mediaviewPlaybackInactive: Color(0xFF252525),
    mediaviewPlaybackActiveOver: Color(0xFFFFFFFF),

    // Intro / Login
    introCoverTopBg: Color(0xFF0F89D0),
    introCoverBottomBg: Color(0xFF39B0F0),
    introCoverIconsFg: Color(0xFF5EC6FF),
    introCoverPlaneTrace: Color(0x695EC6FF),
    introCoverPlaneTop: Color(0xFFFFFFFF),

    // Scrollbar
    scrollBarBg: Color(0x53FFFFFF),
    scrollBarBgOver: Color(0x7AFFFFFF),
    scrollBg: Color(0x1AFFFFFF),
    scrollBgOver: Color(0x2CFFFFFF),

    // Boxes
    boxBg: Color(0xFF17212B),
    boxTextFg: Color(0xFFF5F5F5),
    boxTitleFg: Color(0xFFEBEBEB),
    boxSearchBg: Color(0xFF17212B),
    boxTitleAdditionalFg: Color(0xFF6D7F8F),
    boxTextFgGood: Color(0xFF5598DB),
    boxTextFgError: Color(0xFFDC3D3D),

    // Profile
    profileStatusFgOver: Color(0xFF677A8B),
    profileVerifiedCheckBg: Color(0xFF5288C1),
    profileVerifiedCheckFg: Color(0xFFFFFFFF),
    profileAdminStartFg: Color(0xFF62A9E6),

    // Sidebar
    sideBarBg: Color(0xFF0E1621),
    sideBarBgActive: Color(0xFF25303E),
    sideBarBgRipple: Color(0xFF1E2733),
    sideBarTextFg: Color(0xFF768C9E),
    sideBarTextFgActive: Color(0xFF64B9FA),
    sideBarIconFg: Color(0xFF768C9E),
    sideBarIconFgActive: Color(0xFF5EB5F7),
    sideBarBadgeBg: Color(0xFF5EB5F7),
    sideBarBadgeBgMuted: Color(0xFF768C9E),
    sideBarBadgeFg: Color(0xFFFFFFFF),

    // Menu
    menuBg: Color(0xFF17212B),
    menuBgOver: Color(0xFF2B3744),
    menuBgRipple: Color(0xFF24303D),
    menuIconFg: Color(0xFF6C7883),
    menuIconFgOver: Color(0xFFDCDCDC),
    menuSeparatorFg: Color(0xFF24303D),

    // Main Menu
    mainMenuBg: Color(0xFF17212B),
    mainMenuCoverBg: Color(0xFF5288C1),
    mainMenuCoverFg: Color(0xFFFFFFFF),

    // Settings Icons (same across all themes — colorize-excluded)
    settingsIconBg1: Color(0xFF5BBB6F),
    settingsIconBg2: Color(0xFFEC7577),
    settingsIconBg3: Color(0xFF43A4DF),
    settingsIconBg4: Color(0xFFFAAD38),
    settingsIconBg5: Color(0xFF9A7BDF),
    settingsIconBg6: Color(0xFF5ABDD6),

    // Selection
    overviewCheckBg: Color(0x40000000),
  );

  // ── Classic Day (§25.3.1) ──
  // Same as Day Blue except outgoing bubble colors (green tint).
  static const classicDay = TelegramPalette(
    windowBg: Color(0xFFFFFFFF),
    windowBgOver: Color(0xFFF1F1F1),
    windowBgRipple: Color(0xFFE5E5E5),
    windowBgActive: Color(0xFF40A7E3),
    windowFg: Color(0xFF000000),
    windowFgOver: Color(0xFF000000),
    windowFgActive: Color(0xFFFFFFFF),
    windowSubTextFg: Color(0xFF999999),
    windowSubTextFgOver: Color(0xFF919191),
    windowBoldFg: Color(0xFF222222),
    windowBoldFgOver: Color(0xFF222222),
    windowActiveTextFg: Color(0xFF168ACD),
    windowShadowFg: Color(0xFF000000),
    windowShadowFgFallback: Color(0xFFF1F1F1),
    shadowFg: Color(0x18000000),
    titleBg: Color(0xFFF1F1F1),
    titleBgActive: Color(0xFFF1F1F1),
    titleShadow: Color(0x03000000),
    titleFg: Color(0xFFACACAC),
    titleFgActive: Color(0xFF3E3C3E),
    layerBg: Color(0x7F000000),
    activeButtonBg: Color(0xFF40A7E3),
    activeButtonBgOver: Color(0xFF39A5DB),
    activeButtonBgRipple: Color(0xFF2095D0),
    activeButtonFg: Color(0xFFFFFFFF),
    activeButtonSecondaryFg: Color(0xFFCCEEFF),
    activeLineFg: Color(0xFF37A1DE),
    activeLineFgError: Color(0xFFE48383),
    lightButtonBg: Color(0xFFFFFFFF),
    lightButtonBgOver: Color(0xFFE3F1FA),
    lightButtonBgRipple: Color(0xFFC9E4F6),
    lightButtonFg: Color(0xFF168ACD),
    attentionButtonFg: Color(0xFFD14E4E),
    attentionButtonBgOver: Color(0xFFFCDFDE),
    attentionButtonBgRipple: Color(0xFFF4C3C2),
    outlineButtonOutlineFg: Color(0xFF40A7E3),
    dialogsBg: Color(0xFFFFFFFF),
    dialogsBgOver: Color(0xFFF1F1F1),
    dialogsBgActive: Color(0xFF419FD9),
    dialogsRippleBg: Color(0xFFE5E5E5),
    dialogsRippleBgActive: Color(0xFF2095D0),
    dialogsNameFg: Color(0xFF222222),
    dialogsNameFgOver: Color(0xFF222222),
    dialogsNameFgActive: Color(0xFFFFFFFF),
    dialogsTextFg: Color(0xFF999999),
    dialogsTextFgOver: Color(0xFF919191),
    dialogsTextFgActive: Color(0xFFFFFFFF),
    dialogsTextFgService: Color(0xFF168ACD),
    dialogsDateFg: Color(0xFF999999),
    dialogsDraftFg: Color(0xFFDD4B39),
    dialogsUnreadBg: Color(0xFF40A7E3),
    dialogsUnreadBgMuted: Color(0xFFBBBBBB),
    dialogsUnreadBgActive: Color(0xFFFFFFFF),
    dialogsUnreadBgMutedActive: Color(0xFFC6E1F7),
    dialogsUnreadFg: Color(0xFFFFFFFF),
    dialogsUnreadFgActive: Color(0xFF419FD9),
    dialogsOnlineBadgeFg: Color(0xFF4DC920),
    dialogsOnlineBadgeFgActive: Color(0xFFFFFFFF),
    dialogsSentIconFg: Color(0xFF5DC452),
    dialogsSendingIconFg: Color(0xFFC1C1C1),
    dialogsVerifiedIconBg: Color(0xFF40A7E3),
    dialogsVerifiedIconFg: Color(0xFFFFFFFF),
    dialogsArchiveFg: Color(0xFF525252),
    dialogsForwardBg: Color(0xFF419FD9),
    dialogsForwardFg: Color(0xFFFFFFFF),
    topBarBg: Color(0xFFFFFFFF),
    // Classic Day: green-tinted outgoing bubbles
    msgInBg: Color(0xFFFFFFFF),
    msgInBgSelected: Color(0xFFBBE1FC),
    msgOutBg: Color(0xFFEAFFDC),
    msgOutBgSelected: Color(0xFFBBE1FC),
    msgInShadow: Color(0x29748EA2),
    msgOutShadow: Color(0x1A0D5A91),
    msgInDateFg: Color(0xFFA0ACB6),
    msgOutDateFg: Color(0xFF6DB566),
    msgInServiceFg: Color(0xFF168ACD),
    msgOutServiceFg: Color(0xFF529E39),
    msgInReplyBarColor: Color(0xFF37A1DE),
    msgOutReplyBarColor: Color(0xFF64B05C),
    msgInMonoFg: Color(0xFF4E7391),
    msgOutMonoFg: Color(0xFF459866),
    msgFileInBg: Color(0xFF40A7E3),
    msgFileOutBg: Color(0xFF60B867),
    msgServiceBg: Color(0x59005180),
    msgServiceBgSelected: Color(0x8396B38B),
    msgServiceFg: Color(0xFFFFFFFF),
    msgSelectOverlay: Color(0x4C358CD4),
    msgStickerOverlay: Color(0x7F358CD4),
    msgDateImgBg: Color(0x54000000),
    msgDateImgBgOver: Color(0x74000000),
    msgDateImgBgSelected: Color(0x871C4A71),
    historyTextInFg: Color(0xFF000000),
    historyTextOutFg: Color(0xFF000000),
    historyComposeAreaBg: Color(0xFFFFFFFF),
    historyComposeAreaFg: Color(0xFF000000),
    historyComposeIconFg: Color(0xFF999999),
    historyComposeIconFgOver: Color(0xFF8A8A8A),
    historyComposeButtonBg: Color(0xFFFFFFFF),
    historyComposeButtonBgOver: Color(0xFFF1F1F1),
    historyComposeButtonBgRipple: Color(0xFFE5E5E5),
    historySendIconFg: Color(0xFF40A7E3),
    historyReplyBg: Color(0xFFFFFFFF),
    historyReplyIconFg: Color(0xFF40A7E3),
    historyPinnedBg: Color(0xFFFFFFFF),
    historyUnreadBarBg: Color(0xFFFCFBFA),
    historyUnreadBarFg: Color(0xFF538BB4),
    historyScrollBg: Color(0x4C517C41),
    historyScrollBgOver: Color(0x6B517C41),
    historyScrollBarBg: Color(0x7A517C41),
    historyScrollBarBgOver: Color(0xBC517C41),
    historyToDownBg: Color(0xFFFFFFFF),
    historyToDownBgOver: Color(0xFFF1F1F1),
    historyToDownFg: Color(0xFF999999),
    historyOutIconFg: Color(0xFF57B84C),
    historySendingOutIconFg: Color(0xFF98D292),
    historySendingInIconFg: Color(0xFFA0ADB5),
    historyIconFgInverted: Color(0xFFFFFFFF),
    historySendingInvertedIconFg: Color(0xC8FFFFFF),
    historyPeer1NameFg: Color(0xFFC03D33),
    historyPeer2NameFg: Color(0xFF4FAD2D),
    historyPeer3NameFg: Color(0xFFD09306),
    historyPeer4NameFg: Color(0xFF168ACD),
    historyPeer5NameFg: Color(0xFF8544D6),
    historyPeer6NameFg: Color(0xFFCD4073),
    historyPeer7NameFg: Color(0xFF2996AD),
    historyPeer8NameFg: Color(0xFFCE671B),
    historyPeer1UserpicBg: Color(0xFFFF845E),
    historyPeer2UserpicBg: Color(0xFF9AD164),
    historyPeer3UserpicBg: Color(0xFFE5CA77),
    historyPeer4UserpicBg: Color(0xFF5CAFFA),
    historyPeer5UserpicBg: Color(0xFFB694F9),
    historyPeer6UserpicBg: Color(0xFFFF8AAC),
    historyPeer7UserpicBg: Color(0xFF5BCBE3),
    historyPeer8UserpicBg: Color(0xFFFEBB5B),
    historyPeer1UserpicBg2: Color(0xFFD45246),
    historyPeer2UserpicBg2: Color(0xFF46BA43),
    historyPeer3UserpicBg2: Color(0xFFE5CA77),
    historyPeer4UserpicBg2: Color(0xFF408ACF),
    historyPeer5UserpicBg2: Color(0xFF6C61DF),
    historyPeer6UserpicBg2: Color(0xFFD95574),
    historyPeer7UserpicBg2: Color(0xFF359AD4),
    historyPeer8UserpicBg2: Color(0xFFF68136),
    msgFile1Bg: Color(0xFF72B1DF),
    msgFile1BgDark: Color(0xFF5C9ECE),
    msgFile1BgOver: Color(0xFF5294C4),
    msgFile1BgSelected: Color(0xFF5099D0),
    msgFile2Bg: Color(0xFF61B96E),
    msgFile2BgDark: Color(0xFF4DA859),
    msgFile2BgOver: Color(0xFF44A050),
    msgFile2BgSelected: Color(0xFF46A07E),
    msgFile3Bg: Color(0xFFE47272),
    msgFile3BgDark: Color(0xFFCD5B5E),
    msgFile3BgOver: Color(0xFFC35154),
    msgFile3BgSelected: Color(0xFF9F6A82),
    msgFile4Bg: Color(0xFFEFC274),
    msgFile4BgDark: Color(0xFFE6A561),
    msgFile4BgOver: Color(0xFFDC9C5A),
    msgFile4BgSelected: Color(0xFFB19D84),
    msgWaveformInActive: Color(0xFF40A7E3),
    msgWaveformInInactive: Color(0xFFD4DEE6),
    msgWaveformOutActive: Color(0xFF40A7E3),
    msgWaveformOutInactive: Color(0xFFB3D4E7),
    mediaviewBg: Color(0xEB222222),
    mediaviewControlBg: Color(0x3C000000),
    mediaviewControlFg: Color(0xFFFFFFFF),
    mediaviewCaptionBg: Color(0x80111111),
    mediaviewPlaybackActive: Color(0xFFC7C7C7),
    mediaviewPlaybackInactive: Color(0xFF252525),
    mediaviewPlaybackActiveOver: Color(0xFFFFFFFF),
    introCoverTopBg: Color(0xFF0F89D0),
    introCoverBottomBg: Color(0xFF39B0F0),
    introCoverIconsFg: Color(0xFF5EC6FF),
    introCoverPlaneTrace: Color(0x695EC6FF),
    introCoverPlaneTop: Color(0xFFFFFFFF),
    scrollBarBg: Color(0x53000000),
    scrollBarBgOver: Color(0x7A000000),
    scrollBg: Color(0x00000000),
    scrollBgOver: Color(0x1A000000),
    boxBg: Color(0xFFFFFFFF),
    boxTextFg: Color(0xFF000000),
    boxTitleFg: Color(0xFF404040),
    boxSearchBg: Color(0xFFFFFFFF),
    boxTitleAdditionalFg: Color(0xFF808080),
    boxTextFgGood: Color(0xFF4AB44A),
    boxTextFgError: Color(0xFFD84D4D),
    profileStatusFgOver: Color(0xFF7C99B2),
    profileVerifiedCheckBg: Color(0xFF40A7E3),
    profileVerifiedCheckFg: Color(0xFFFFFFFF),
    profileAdminStartFg: Color(0xFF40A7E3),
    sideBarBg: Color(0xFF293A4C),
    sideBarBgActive: Color(0xFF17212B),
    sideBarBgRipple: Color(0xFF1E2B38),
    sideBarTextFg: Color(0xFF8897A6),
    sideBarTextFgActive: Color(0xFF64B9FA),
    sideBarIconFg: Color(0xFF8393A3),
    sideBarIconFgActive: Color(0xFF5EB5F7),
    sideBarBadgeBg: Color(0xFF5EB5F7),
    sideBarBadgeBgMuted: Color(0xFF8393A3),
    sideBarBadgeFg: Color(0xFFFFFFFF),
    menuBg: Color(0xFFFFFFFF),
    menuBgOver: Color(0xFFF1F1F1),
    menuBgRipple: Color(0xFFE5E5E5),
    menuIconFg: Color(0xFF999999),
    menuIconFgOver: Color(0xFF8A8A8A),
    menuSeparatorFg: Color(0xFFE5E5E5),
    mainMenuBg: Color(0xFFFFFFFF),
    mainMenuCoverBg: Color(0xFF40A7E3),
    mainMenuCoverFg: Color(0xFFFFFFFF),
    settingsIconBg1: Color(0xFF5BBB6F),
    settingsIconBg2: Color(0xFFEC7577),
    settingsIconBg3: Color(0xFF43A4DF),
    settingsIconBg4: Color(0xFFFAAD38),
    settingsIconBg5: Color(0xFF9A7BDF),
    settingsIconBg6: Color(0xFF5ABDD6),
    overviewCheckBg: Color(0x40000000),
  );

  // ── Night Green (§25.3.4) ──
  // Accent: #3FC1B0 (teal). Outgoing: #2A2F33. Incoming: #33393F.
  static const nightGreen = TelegramPalette(
    windowBg: Color(0xFF282E33),
    windowBgOver: Color(0xFF313B43),
    windowBgRipple: Color(0xFF3F4850),
    windowBgActive: Color(0xFF3FC1B0),
    windowFg: Color(0xFFF5F5F5),
    windowFgOver: Color(0xFFE9ECF0),
    windowFgActive: Color(0xFFFFFFFF),
    windowSubTextFg: Color(0xFF82868A),
    windowSubTextFgOver: Color(0xFF8E9296),
    windowBoldFg: Color(0xFFE9E8E8),
    windowBoldFgOver: Color(0xFFE9E9E9),
    windowActiveTextFg: Color(0xFF4BE1C3),
    windowShadowFg: Color(0xFF000000),
    windowShadowFgFallback: Color(0xFF282E33),
    shadowFg: Color(0x18000000),
    titleBg: Color(0xFF2D3338),
    titleBgActive: Color(0xFF32383D),
    titleShadow: Color(0x00000000),
    titleFg: Color(0xFF7B8086),
    titleFgActive: Color(0xFF9BA3AB),
    layerBg: Color(0x7F000000),
    activeButtonBg: Color(0xFF3FC1B0),
    activeButtonBgOver: Color(0xFF36B8A7),
    activeButtonBgRipple: Color(0xFF30AE9E),
    activeButtonFg: Color(0xFFFFFFFF),
    activeButtonSecondaryFg: Color(0xFFA0E3DA),
    activeLineFg: Color(0xFF3FC1B0),
    activeLineFgError: Color(0xFFEF5959),
    lightButtonBg: Color(0xFF282E33),
    lightButtonBgOver: Color(0xFF2E3439),
    lightButtonBgRipple: Color(0xFF353B40),
    lightButtonFg: Color(0xFF4BE1C3),
    attentionButtonFg: Color(0xFFEC3942),
    attentionButtonBgOver: Color(0x64592A2A),
    attentionButtonBgRipple: Color(0x64683232),
    outlineButtonOutlineFg: Color(0xFF3FC1B0),
    dialogsBg: Color(0xFF282E33),
    dialogsBgOver: Color(0xFF313B43),
    dialogsBgActive: Color(0xFF009687),
    dialogsRippleBg: Color(0xFF3F4850),
    dialogsRippleBgActive: Color(0xFF00857A),
    dialogsNameFg: Color(0xFFE9E8E8),
    dialogsNameFgOver: Color(0xFFE9E9E9),
    dialogsNameFgActive: Color(0xFFFFFFFF),
    dialogsTextFg: Color(0xFF82868A),
    dialogsTextFgOver: Color(0xFF8E9296),
    dialogsTextFgActive: Color(0xFFFFFFFF),
    dialogsTextFgService: Color(0xFF4BE1C3),
    dialogsDateFg: Color(0xFF82868A),
    dialogsDraftFg: Color(0xFFDD4B39),
    dialogsUnreadBg: Color(0xFF3FC1B0),
    dialogsUnreadBgMuted: Color(0xFF656B70),
    dialogsUnreadBgActive: Color(0xFFFFFFFF),
    dialogsUnreadBgMutedActive: Color(0xFF80C5BC),
    dialogsUnreadFg: Color(0xFFFFFFFF),
    dialogsUnreadFgActive: Color(0xFF009687),
    dialogsOnlineBadgeFg: Color(0xFF4DC920),
    dialogsOnlineBadgeFgActive: Color(0xFFFFFFFF),
    dialogsSentIconFg: Color(0xFF11BFAB),
    dialogsSendingIconFg: Color(0xFF656B70),
    dialogsVerifiedIconBg: Color(0xFF4BE1C3),
    dialogsVerifiedIconFg: Color(0xFF282E33),
    dialogsArchiveFg: Color(0xFF82868A),
    dialogsForwardBg: Color(0xFF009687),
    dialogsForwardFg: Color(0xFFFFFFFF),
    topBarBg: Color(0xFF282E33),
    msgInBg: Color(0xFF33393F),
    msgInBgSelected: Color(0xFF009687),
    msgOutBg: Color(0xFF2A2F33),
    msgOutBgSelected: Color(0xFF009687),
    msgInShadow: Color(0x00748EA2),
    msgOutShadow: Color(0x00000000),
    msgInDateFg: Color(0xFF828D94),
    msgOutDateFg: Color(0xFF737F87),
    msgInServiceFg: Color(0xFF4BE1C3),
    msgOutServiceFg: Color(0xFF4BE1C3),
    msgInReplyBarColor: Color(0xFF32CEB9),
    msgOutReplyBarColor: Color(0xFF32CEB9),
    msgInMonoFg: Color(0xFF5AABA0),
    msgOutMonoFg: Color(0xFFC2F2EC),
    msgFileInBg: Color(0xFF3FC1B0),
    msgFileOutBg: Color(0xFF3FC1B0),
    msgServiceBg: Color(0xC8363C43),
    msgServiceBgSelected: Color(0xFF009687),
    msgServiceFg: Color(0xFFFFFFFF),
    msgSelectOverlay: Color(0x4C35D4BF),
    msgStickerOverlay: Color(0x7F35D4BF),
    msgDateImgBg: Color(0x54000000),
    msgDateImgBgOver: Color(0x74000000),
    msgDateImgBgSelected: Color(0x87006B5F),
    historyTextInFg: Color(0xFFF5F5F5),
    historyTextOutFg: Color(0xFFF5F5F5),
    historyComposeAreaBg: Color(0xFF282E33),
    historyComposeAreaFg: Color(0xFFF5F5F5),
    historyComposeIconFg: Color(0xFF7B8086),
    historyComposeIconFgOver: Color(0xFFDCDCDC),
    historyComposeButtonBg: Color(0xFF282E33),
    historyComposeButtonBgOver: Color(0xFF313B43),
    historyComposeButtonBgRipple: Color(0xFF3F4850),
    historySendIconFg: Color(0xFF3FC1B0),
    historyReplyBg: Color(0xFF282E33),
    historyReplyIconFg: Color(0xFF3FC1B0),
    historyPinnedBg: Color(0xFF282E33),
    historyUnreadBarBg: Color(0xFF2E3338),
    historyUnreadBarFg: Color(0xFFFFFFFF),
    historyScrollBg: Color(0x4C565A5E),
    historyScrollBgOver: Color(0x6B5A5D61),
    historyScrollBarBg: Color(0x7A7F8489),
    historyScrollBarBgOver: Color(0xBC64686C),
    historyToDownBg: Color(0xFF33393F),
    historyToDownBgOver: Color(0xFF3D4449),
    historyToDownFg: Color(0xFFADB4BA),
    historyOutIconFg: Color(0xFF11BFAB),
    historySendingOutIconFg: Color(0xFF4DA89D),
    historySendingInIconFg: Color(0xFF76838B),
    historyIconFgInverted: Color(0xFFFFFFFF),
    historySendingInvertedIconFg: Color(0xC8FFFFFF),
    historyPeer1NameFg: Color(0xFFFB6169),
    historyPeer2NameFg: Color(0xFF85DE85),
    historyPeer3NameFg: Color(0xFFF3BC5C),
    historyPeer4NameFg: Color(0xFF65BDF3),
    historyPeer5NameFg: Color(0xFFB48BF2),
    historyPeer6NameFg: Color(0xFFFF5694),
    historyPeer7NameFg: Color(0xFF62D4E3),
    historyPeer8NameFg: Color(0xFFFAA357),
    historyPeer1UserpicBg: Color(0xFFFF845E),
    historyPeer2UserpicBg: Color(0xFF9AD164),
    historyPeer3UserpicBg: Color(0xFFE5CA77),
    historyPeer4UserpicBg: Color(0xFF5CAFFA),
    historyPeer5UserpicBg: Color(0xFFB694F9),
    historyPeer6UserpicBg: Color(0xFFFF8AAC),
    historyPeer7UserpicBg: Color(0xFF5BCBE3),
    historyPeer8UserpicBg: Color(0xFFFEBB5B),
    historyPeer1UserpicBg2: Color(0xFFD45246),
    historyPeer2UserpicBg2: Color(0xFF46BA43),
    historyPeer3UserpicBg2: Color(0xFFE5CA77),
    historyPeer4UserpicBg2: Color(0xFF408ACF),
    historyPeer5UserpicBg2: Color(0xFF6C61DF),
    historyPeer6UserpicBg2: Color(0xFFD95574),
    historyPeer7UserpicBg2: Color(0xFF359AD4),
    historyPeer8UserpicBg2: Color(0xFFF68136),
    msgFile1Bg: Color(0xFF72B1DF),
    msgFile1BgDark: Color(0xFF5C9ECE),
    msgFile1BgOver: Color(0xFF5294C4),
    msgFile1BgSelected: Color(0xFF5099D0),
    msgFile2Bg: Color(0xFF61B96E),
    msgFile2BgDark: Color(0xFF4DA859),
    msgFile2BgOver: Color(0xFF44A050),
    msgFile2BgSelected: Color(0xFF46A07E),
    msgFile3Bg: Color(0xFFE47272),
    msgFile3BgDark: Color(0xFFCD5B5E),
    msgFile3BgOver: Color(0xFFC35154),
    msgFile3BgSelected: Color(0xFF9F6A82),
    msgFile4Bg: Color(0xFFEFC274),
    msgFile4BgDark: Color(0xFFE6A561),
    msgFile4BgOver: Color(0xFFDC9C5A),
    msgFile4BgSelected: Color(0xFFB19D84),
    msgWaveformInActive: Color(0xFF3FC1B0),
    msgWaveformInInactive: Color(0xFF4A5159),
    msgWaveformOutActive: Color(0xFF3FC1B0),
    msgWaveformOutInactive: Color(0xFF4A5159),
    mediaviewBg: Color(0xEB222222),
    mediaviewControlBg: Color(0x3C000000),
    mediaviewControlFg: Color(0xFFFFFFFF),
    mediaviewCaptionBg: Color(0x80111111),
    mediaviewPlaybackActive: Color(0xFFC7C7C7),
    mediaviewPlaybackInactive: Color(0xFF252525),
    mediaviewPlaybackActiveOver: Color(0xFFFFFFFF),
    introCoverTopBg: Color(0xFF0F89D0),
    introCoverBottomBg: Color(0xFF39B0F0),
    introCoverIconsFg: Color(0xFF5EC6FF),
    introCoverPlaneTrace: Color(0x695EC6FF),
    introCoverPlaneTop: Color(0xFFFFFFFF),
    scrollBarBg: Color(0x53FFFFFF),
    scrollBarBgOver: Color(0x7AFFFFFF),
    scrollBg: Color(0x1AFFFFFF),
    scrollBgOver: Color(0x2CFFFFFF),
    boxBg: Color(0xFF282E33),
    boxTextFg: Color(0xFFF5F5F5),
    boxTitleFg: Color(0xFFEBEBEB),
    boxSearchBg: Color(0xFF282E33),
    boxTitleAdditionalFg: Color(0xFF7B8086),
    boxTextFgGood: Color(0xFF3FC1B0),
    boxTextFgError: Color(0xFFDC3D3D),
    profileStatusFgOver: Color(0xFF7B8086),
    profileVerifiedCheckBg: Color(0xFF3FC1B0),
    profileVerifiedCheckFg: Color(0xFFFFFFFF),
    profileAdminStartFg: Color(0xFF3FC1B0),
    sideBarBg: Color(0xFF1E2226),
    sideBarBgActive: Color(0xFF282E33),
    sideBarBgRipple: Color(0xFF252A2F),
    sideBarTextFg: Color(0xFF7B8086),
    sideBarTextFgActive: Color(0xFF4BE1C3),
    sideBarIconFg: Color(0xFF7B8086),
    sideBarIconFgActive: Color(0xFF3FC1B0),
    sideBarBadgeBg: Color(0xFF3FC1B0),
    sideBarBadgeBgMuted: Color(0xFF656B70),
    sideBarBadgeFg: Color(0xFFFFFFFF),
    menuBg: Color(0xFF282E33),
    menuBgOver: Color(0xFF353B40),
    menuBgRipple: Color(0xFF3F4850),
    menuIconFg: Color(0xFF7B8086),
    menuIconFgOver: Color(0xFFDCDCDC),
    menuSeparatorFg: Color(0xFF3F4850),
    mainMenuBg: Color(0xFF282E33),
    mainMenuCoverBg: Color(0xFF3FC1B0),
    mainMenuCoverFg: Color(0xFFFFFFFF),
    settingsIconBg1: Color(0xFF5BBB6F),
    settingsIconBg2: Color(0xFFEC7577),
    settingsIconBg3: Color(0xFF43A4DF),
    settingsIconBg4: Color(0xFFFAAD38),
    settingsIconBg5: Color(0xFF9A7BDF),
    settingsIconBg6: Color(0xFF5ABDD6),
    overviewCheckBg: Color(0x40000000),
  );
}

class PaletteProvider extends InheritedWidget {
  final TelegramPalette palette;

  const PaletteProvider({
    super.key,
    required this.palette,
    required super.child,
  });

  static TelegramPalette of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<PaletteProvider>();
    return provider?.palette ?? TelegramPalette.dayBlue;
  }

  static TelegramPalette? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<PaletteProvider>()?.palette;
  }

  @override
  bool updateShouldNotify(PaletteProvider oldWidget) =>
      !identical(palette, oldWidget.palette);
}

extension PaletteExtension on BuildContext {
  TelegramPalette get palette => PaletteProvider.of(this);
}

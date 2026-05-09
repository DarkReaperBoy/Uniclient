import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'telegram_palette.dart';

const _maxThemeFileSize = 5 * 1024 * 1024; // 5 MB
const _maxPaletteFileSize = 1 * 1024 * 1024; // 1 MB

class ThemeFileData {
  final TelegramPalette palette;
  final Uint8List? backgroundImage;
  final bool backgroundTiled;
  final CloudThemeMeta? cloudMeta;
  final Map<String, String> referenceChain;

  const ThemeFileData({
    required this.palette,
    this.backgroundImage,
    this.backgroundTiled = false,
    this.cloudMeta,
    this.referenceChain = const {},
  });
}

class CloudThemeMeta {
  final int id;
  final int accessHash;

  const CloudThemeMeta({required this.id, required this.accessHash});
}

ThemeFileData? parseThemeFile(
  Uint8List bytes, {
  TelegramPalette fallback = TelegramPalette.dayBlue,
}) {
  if (bytes.length > _maxThemeFileSize) return null;

  if (_looksLikeZip(bytes)) {
    return _parseZipTheme(bytes, fallback);
  }

  final text = String.fromCharCodes(bytes);
  if (text.length > _maxPaletteFileSize) return null;
  final result = parsePaletteText(text, fallback: fallback);
  if (result == null) return null;
  return ThemeFileData(palette: result.palette, cloudMeta: result.cloudMeta, referenceChain: result.referenceChain);
}

class PaletteParseResult {
  final TelegramPalette palette;
  final CloudThemeMeta? cloudMeta;
  final Map<String, String> referenceChain;
  const PaletteParseResult({
    required this.palette,
    this.cloudMeta,
    this.referenceChain = const {},
  });
}

PaletteParseResult? parsePaletteText(
  String text, {
  TelegramPalette fallback = TelegramPalette.dayBlue,
}) {
  final fallbackMap = paletteToMap(fallback);
  final parsed = <String, dynamic>{};
  CloudThemeMeta? cloudMeta;

  bool inServiceBlock = false;
  int? serviceId;
  int? serviceHash;

  for (final rawLine in text.split('\n')) {
    final line = rawLine.trim();

    if (line == '// THEME EDITOR SERVICE INFO START') {
      inServiceBlock = true;
      continue;
    }
    if (line == '// THEME EDITOR SERVICE INFO END') {
      inServiceBlock = false;
      if (serviceId != null && serviceHash != null) {
        cloudMeta = CloudThemeMeta(id: serviceId, accessHash: serviceHash);
      }
      continue;
    }
    if (inServiceBlock) {
      final stripped = line.startsWith('//') ? line.substring(2).trim() : line;
      final idMatch = RegExp(r'id:(\d+)').firstMatch(stripped);
      final hashMatch = RegExp(r'hash:(\d+)').firstMatch(stripped);
      if (idMatch != null) serviceId = int.tryParse(idMatch.group(1)!);
      if (hashMatch != null) serviceHash = int.tryParse(hashMatch.group(1)!);
      continue;
    }

    if (line.isEmpty || line.startsWith('//')) continue;

    final colonIdx = line.indexOf(':');
    if (colonIdx < 1) continue;

    final name = line.substring(0, colonIdx).trim();
    var value = line.substring(colonIdx + 1).trim();

    final commentIdx = value.indexOf('//');
    if (commentIdx >= 0) value = value.substring(0, commentIdx).trim();

    if (value.endsWith(';')) value = value.substring(0, value.length - 1).trim();
    if (value.isEmpty) continue;

    if (value.startsWith('#')) {
      final color = _parseHexColor(value);
      if (color != null) parsed[name] = color;
    } else {
      parsed[name] = value;
    }
  }

  final resolved = <String, Color>{};
  final references = <String, String>{};
  for (final entry in parsed.entries) {
    if (entry.value is Color) {
      resolved[entry.key] = entry.value;
    }
  }
  for (final entry in parsed.entries) {
    if (entry.value is String) {
      final ref = entry.value as String;
      references[entry.key] = ref;
      if (resolved.containsKey(ref)) {
        resolved[entry.key] = resolved[ref]!;
      } else if (fallbackMap.containsKey(ref)) {
        resolved[entry.key] = fallbackMap[ref]!;
      }
    }
  }

  final merged = Map<String, Color>.from(fallbackMap)..addAll(resolved);
  final palette = paletteFromMap(merged, fallback);

  return PaletteParseResult(
    palette: palette,
    cloudMeta: cloudMeta,
    referenceChain: references,
  );
}

Uint8List exportThemeFile(ThemeFileData data) {
  final archive = Archive();

  final paletteText = _generatePaletteText(data);
  final paletteBytes = Uint8List.fromList(paletteText.codeUnits);
  archive.addFile(ArchiveFile(
    'colors.tdesktop-theme',
    paletteBytes.length,
    paletteBytes,
  ));

  if (data.backgroundImage != null) {
    final bgName = data.backgroundTiled ? 'tiled.jpg' : 'background.jpg';
    archive.addFile(ArchiveFile(
      bgName,
      data.backgroundImage!.length,
      data.backgroundImage!,
    ));
  }

  final encoded = ZipEncoder().encode(archive);
  return Uint8List.fromList(encoded);
}

String writeCloudMeta(CloudThemeMeta meta) {
  return '// THEME EDITOR SERVICE INFO START\n'
      '// id:${meta.id} hash:${meta.accessHash}\n'
      '// THEME EDITOR SERVICE INFO END\n';
}

CloudThemeMeta? readCloudMeta(String text) {
  final startIdx = text.indexOf('// THEME EDITOR SERVICE INFO START');
  final endIdx = text.indexOf('// THEME EDITOR SERVICE INFO END');
  if (startIdx < 0 || endIdx < 0 || endIdx <= startIdx) return null;

  final block = text.substring(startIdx, endIdx);
  final idMatch = RegExp(r'id:(\d+)').firstMatch(block);
  final hashMatch = RegExp(r'hash:(\d+)').firstMatch(block);
  if (idMatch == null || hashMatch == null) return null;

  return CloudThemeMeta(
    id: int.parse(idMatch.group(1)!),
    accessHash: int.parse(hashMatch.group(1)!),
  );
}

// ── Private helpers ──

bool _looksLikeZip(Uint8List bytes) =>
    bytes.length >= 4 &&
    bytes[0] == 0x50 &&
    bytes[1] == 0x4B &&
    bytes[2] == 0x03 &&
    bytes[3] == 0x04;

ThemeFileData? _parseZipTheme(Uint8List bytes, TelegramPalette fallback) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    return null;
  }

  ArchiveFile? paletteFile;
  ArchiveFile? bgFile;
  bool tiled = false;

  for (final file in archive) {
    final name = file.name.toLowerCase();
    if (paletteFile == null &&
        (name == 'colors.tdesktop-theme' || name == 'colors.tdesktop-palette')) {
      paletteFile = file;
    } else if (bgFile == null) {
      if (name == 'background.jpg' || name == 'background.png') {
        bgFile = file;
        tiled = false;
      } else if (name == 'tiled.jpg' || name == 'tiled.png') {
        bgFile = file;
        tiled = true;
      }
    }
  }

  if (paletteFile == null) return null;
  final paletteBytes = paletteFile.content as List<int>;
  if (paletteBytes.length > _maxPaletteFileSize) return null;

  final text = String.fromCharCodes(paletteBytes);
  final result = parsePaletteText(text, fallback: fallback);
  if (result == null) return null;

  Uint8List? bgBytes;
  if (bgFile != null) {
    bgBytes = Uint8List.fromList(bgFile.content as List<int>);
  }

  return ThemeFileData(
    palette: result.palette,
    backgroundImage: bgBytes,
    backgroundTiled: tiled,
    cloudMeta: result.cloudMeta,
    referenceChain: result.referenceChain,
  );
}

Color? _parseHexColor(String hex) {
  if (!hex.startsWith('#')) return null;
  final digits = hex.substring(1);
  if (digits.length == 6) {
    final v = int.tryParse(digits, radix: 16);
    if (v == null) return null;
    return Color((0xFF << 24) | v);
  } else if (digits.length == 8) {
    final v = int.tryParse(digits, radix: 16);
    if (v == null) return null;
    final r = (v >> 24) & 0xFF;
    final g = (v >> 16) & 0xFF;
    final b = (v >> 8) & 0xFF;
    final a = v & 0xFF;
    return Color((a << 24) | (r << 16) | (g << 8) | b);
  }
  return null;
}

String _colorToHex(Color c) {
  final r = (c.r * 255).round();
  final g = (c.g * 255).round();
  final b = (c.b * 255).round();
  final a = (c.a * 255).round();
  if (a == 255) {
    return '#${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${b.toRadixString(16).padLeft(2, '0')}';
  }
  return '#${r.toRadixString(16).padLeft(2, '0')}'
      '${g.toRadixString(16).padLeft(2, '0')}'
      '${b.toRadixString(16).padLeft(2, '0')}'
      '${a.toRadixString(16).padLeft(2, '0')}';
}

String _generatePaletteText(ThemeFileData data) {
  final buf = StringBuffer();
  buf.writeln('// Generated by UniClient');
  buf.writeln();

  final map = paletteToMap(data.palette);
  for (final entry in map.entries) {
    buf.writeln('${entry.key}: ${_colorToHex(entry.value)};');
  }

  if (data.cloudMeta != null) {
    buf.writeln();
    buf.write(writeCloudMeta(data.cloudMeta!));
  }

  return buf.toString();
}

// ── Token name ↔ palette field mapping ──

Map<String, Color> paletteToMap(TelegramPalette p) => {
  'windowBg': p.windowBg,
  'windowBgOver': p.windowBgOver,
  'windowBgRipple': p.windowBgRipple,
  'windowBgActive': p.windowBgActive,
  'windowFg': p.windowFg,
  'windowFgOver': p.windowFgOver,
  'windowFgActive': p.windowFgActive,
  'windowSubTextFg': p.windowSubTextFg,
  'windowSubTextFgOver': p.windowSubTextFgOver,
  'windowBoldFg': p.windowBoldFg,
  'windowBoldFgOver': p.windowBoldFgOver,
  'windowActiveTextFg': p.windowActiveTextFg,
  'windowShadowFg': p.windowShadowFg,
  'windowShadowFgFallback': p.windowShadowFgFallback,
  'shadowFg': p.shadowFg,
  'titleBg': p.titleBg,
  'titleBgActive': p.titleBgActive,
  'titleShadow': p.titleShadow,
  'titleFg': p.titleFg,
  'titleFgActive': p.titleFgActive,
  'layerBg': p.layerBg,
  'activeButtonBg': p.activeButtonBg,
  'activeButtonBgOver': p.activeButtonBgOver,
  'activeButtonBgRipple': p.activeButtonBgRipple,
  'activeButtonFg': p.activeButtonFg,
  'activeButtonSecondaryFg': p.activeButtonSecondaryFg,
  'activeLineFg': p.activeLineFg,
  'activeLineFgError': p.activeLineFgError,
  'lightButtonBg': p.lightButtonBg,
  'lightButtonBgOver': p.lightButtonBgOver,
  'lightButtonBgRipple': p.lightButtonBgRipple,
  'lightButtonFg': p.lightButtonFg,
  'lightButtonFgOver': p.lightButtonFgOver,
  'attentionButtonFg': p.attentionButtonFg,
  'attentionButtonBgOver': p.attentionButtonBgOver,
  'attentionButtonBgRipple': p.attentionButtonBgRipple,
  'outlineButtonOutlineFg': p.outlineButtonOutlineFg,
  'dialogsBg': p.dialogsBg,
  'dialogsBgOver': p.dialogsBgOver,
  'dialogsBgActive': p.dialogsBgActive,
  'dialogsRippleBg': p.dialogsRippleBg,
  'dialogsRippleBgActive': p.dialogsRippleBgActive,
  'dialogsNameFg': p.dialogsNameFg,
  'dialogsNameFgOver': p.dialogsNameFgOver,
  'dialogsNameFgActive': p.dialogsNameFgActive,
  'dialogsTextFg': p.dialogsTextFg,
  'dialogsTextFgOver': p.dialogsTextFgOver,
  'dialogsTextFgActive': p.dialogsTextFgActive,
  'dialogsTextFgService': p.dialogsTextFgService,
  'dialogsDateFg': p.dialogsDateFg,
  'dialogsDraftFg': p.dialogsDraftFg,
  'dialogsUnreadBg': p.dialogsUnreadBg,
  'dialogsUnreadBgMuted': p.dialogsUnreadBgMuted,
  'dialogsUnreadBgActive': p.dialogsUnreadBgActive,
  'dialogsUnreadBgMutedActive': p.dialogsUnreadBgMutedActive,
  'dialogsUnreadFg': p.dialogsUnreadFg,
  'dialogsUnreadFgActive': p.dialogsUnreadFgActive,
  'dialogsOnlineBadgeFg': p.dialogsOnlineBadgeFg,
  'dialogsOnlineBadgeFgActive': p.dialogsOnlineBadgeFgActive,
  'dialogsSentIconFg': p.dialogsSentIconFg,
  'dialogsSendingIconFg': p.dialogsSendingIconFg,
  'dialogsVerifiedIconBg': p.dialogsVerifiedIconBg,
  'dialogsVerifiedIconFg': p.dialogsVerifiedIconFg,
  'dialogsArchiveFg': p.dialogsArchiveFg,
  'dialogsForwardBg': p.dialogsForwardBg,
  'dialogsForwardFg': p.dialogsForwardFg,
  'topBarBg': p.topBarBg,
  'msgInBg': p.msgInBg,
  'msgInBgSelected': p.msgInBgSelected,
  'msgOutBg': p.msgOutBg,
  'msgOutBgSelected': p.msgOutBgSelected,
  'msgInShadow': p.msgInShadow,
  'msgOutShadow': p.msgOutShadow,
  'msgInDateFg': p.msgInDateFg,
  'msgOutDateFg': p.msgOutDateFg,
  'msgInServiceFg': p.msgInServiceFg,
  'msgOutServiceFg': p.msgOutServiceFg,
  'msgInReplyBarColor': p.msgInReplyBarColor,
  'msgOutReplyBarColor': p.msgOutReplyBarColor,
  'msgInMonoFg': p.msgInMonoFg,
  'msgOutMonoFg': p.msgOutMonoFg,
  'msgFileInBg': p.msgFileInBg,
  'msgFileOutBg': p.msgFileOutBg,
  'msgServiceBg': p.msgServiceBg,
  'msgServiceBgSelected': p.msgServiceBgSelected,
  'msgServiceFg': p.msgServiceFg,
  'msgSelectOverlay': p.msgSelectOverlay,
  'msgStickerOverlay': p.msgStickerOverlay,
  'msgDateImgBg': p.msgDateImgBg,
  'msgDateImgBgOver': p.msgDateImgBgOver,
  'msgDateImgBgSelected': p.msgDateImgBgSelected,
  'historyTextInFg': p.historyTextInFg,
  'historyTextOutFg': p.historyTextOutFg,
  'historyComposeAreaBg': p.historyComposeAreaBg,
  'historyComposeAreaFg': p.historyComposeAreaFg,
  'historyComposeIconFg': p.historyComposeIconFg,
  'historyComposeIconFgOver': p.historyComposeIconFgOver,
  'historyComposeButtonBg': p.historyComposeButtonBg,
  'historyComposeButtonBgOver': p.historyComposeButtonBgOver,
  'historyComposeButtonBgRipple': p.historyComposeButtonBgRipple,
  'historySendIconFg': p.historySendIconFg,
  'historyReplyBg': p.historyReplyBg,
  'historyReplyIconFg': p.historyReplyIconFg,
  'historyPinnedBg': p.historyPinnedBg,
  'historyUnreadBarBg': p.historyUnreadBarBg,
  'historyUnreadBarFg': p.historyUnreadBarFg,
  'historyScrollBg': p.historyScrollBg,
  'historyScrollBgOver': p.historyScrollBgOver,
  'historyScrollBarBg': p.historyScrollBarBg,
  'historyScrollBarBgOver': p.historyScrollBarBgOver,
  'historyToDownBg': p.historyToDownBg,
  'historyToDownBgOver': p.historyToDownBgOver,
  'historyToDownFg': p.historyToDownFg,
  'historyOutIconFg': p.historyOutIconFg,
  'historySendingOutIconFg': p.historySendingOutIconFg,
  'historySendingInIconFg': p.historySendingInIconFg,
  'historyIconFgInverted': p.historyIconFgInverted,
  'historySendingInvertedIconFg': p.historySendingInvertedIconFg,
  'historyPeer1NameFg': p.historyPeer1NameFg,
  'historyPeer2NameFg': p.historyPeer2NameFg,
  'historyPeer3NameFg': p.historyPeer3NameFg,
  'historyPeer4NameFg': p.historyPeer4NameFg,
  'historyPeer5NameFg': p.historyPeer5NameFg,
  'historyPeer6NameFg': p.historyPeer6NameFg,
  'historyPeer7NameFg': p.historyPeer7NameFg,
  'historyPeer8NameFg': p.historyPeer8NameFg,
  'historyPeer1UserpicBg': p.historyPeer1UserpicBg,
  'historyPeer2UserpicBg': p.historyPeer2UserpicBg,
  'historyPeer3UserpicBg': p.historyPeer3UserpicBg,
  'historyPeer4UserpicBg': p.historyPeer4UserpicBg,
  'historyPeer5UserpicBg': p.historyPeer5UserpicBg,
  'historyPeer6UserpicBg': p.historyPeer6UserpicBg,
  'historyPeer7UserpicBg': p.historyPeer7UserpicBg,
  'historyPeer8UserpicBg': p.historyPeer8UserpicBg,
  'historyPeer1UserpicBg2': p.historyPeer1UserpicBg2,
  'historyPeer2UserpicBg2': p.historyPeer2UserpicBg2,
  'historyPeer3UserpicBg2': p.historyPeer3UserpicBg2,
  'historyPeer4UserpicBg2': p.historyPeer4UserpicBg2,
  'historyPeer5UserpicBg2': p.historyPeer5UserpicBg2,
  'historyPeer6UserpicBg2': p.historyPeer6UserpicBg2,
  'historyPeer7UserpicBg2': p.historyPeer7UserpicBg2,
  'historyPeer8UserpicBg2': p.historyPeer8UserpicBg2,
  'msgFile1Bg': p.msgFile1Bg,
  'msgFile1BgDark': p.msgFile1BgDark,
  'msgFile1BgOver': p.msgFile1BgOver,
  'msgFile1BgSelected': p.msgFile1BgSelected,
  'msgFile2Bg': p.msgFile2Bg,
  'msgFile2BgDark': p.msgFile2BgDark,
  'msgFile2BgOver': p.msgFile2BgOver,
  'msgFile2BgSelected': p.msgFile2BgSelected,
  'msgFile3Bg': p.msgFile3Bg,
  'msgFile3BgDark': p.msgFile3BgDark,
  'msgFile3BgOver': p.msgFile3BgOver,
  'msgFile3BgSelected': p.msgFile3BgSelected,
  'msgFile4Bg': p.msgFile4Bg,
  'msgFile4BgDark': p.msgFile4BgDark,
  'msgFile4BgOver': p.msgFile4BgOver,
  'msgFile4BgSelected': p.msgFile4BgSelected,
  'msgWaveformInActive': p.msgWaveformInActive,
  'msgWaveformInInactive': p.msgWaveformInInactive,
  'msgWaveformOutActive': p.msgWaveformOutActive,
  'msgWaveformOutInactive': p.msgWaveformOutInactive,
  'mediaviewBg': p.mediaviewBg,
  'mediaviewControlBg': p.mediaviewControlBg,
  'mediaviewControlFg': p.mediaviewControlFg,
  'mediaviewCaptionBg': p.mediaviewCaptionBg,
  'mediaviewPlaybackActive': p.mediaviewPlaybackActive,
  'mediaviewPlaybackInactive': p.mediaviewPlaybackInactive,
  'mediaviewPlaybackActiveOver': p.mediaviewPlaybackActiveOver,
  'introCoverTopBg': p.introCoverTopBg,
  'introCoverBottomBg': p.introCoverBottomBg,
  'introCoverIconsFg': p.introCoverIconsFg,
  'introCoverPlaneTrace': p.introCoverPlaneTrace,
  'introCoverPlaneTop': p.introCoverPlaneTop,
  'scrollBarBg': p.scrollBarBg,
  'scrollBarBgOver': p.scrollBarBgOver,
  'scrollBg': p.scrollBg,
  'scrollBgOver': p.scrollBgOver,
  'boxBg': p.boxBg,
  'boxTextFg': p.boxTextFg,
  'boxTitleFg': p.boxTitleFg,
  'boxSearchBg': p.boxSearchBg,
  'boxTitleAdditionalFg': p.boxTitleAdditionalFg,
  'boxTextFgGood': p.boxTextFgGood,
  'boxTextFgError': p.boxTextFgError,
  'boxDividerBg': p.boxDividerBg,
  'profileStatusFgOver': p.profileStatusFgOver,
  'profileVerifiedCheckBg': p.profileVerifiedCheckBg,
  'profileVerifiedCheckFg': p.profileVerifiedCheckFg,
  'profileAdminStartFg': p.profileAdminStartFg,
  'profileOtherAdminStarFg': p.profileOtherAdminStarFg,
  'sideBarBg': p.sideBarBg,
  'sideBarBgActive': p.sideBarBgActive,
  'sideBarBgRipple': p.sideBarBgRipple,
  'sideBarTextFg': p.sideBarTextFg,
  'sideBarTextFgActive': p.sideBarTextFgActive,
  'sideBarIconFg': p.sideBarIconFg,
  'sideBarIconFgActive': p.sideBarIconFgActive,
  'sideBarBadgeBg': p.sideBarBadgeBg,
  'sideBarBadgeBgMuted': p.sideBarBadgeBgMuted,
  'sideBarBadgeFg': p.sideBarBadgeFg,
  'menuBg': p.menuBg,
  'menuBgOver': p.menuBgOver,
  'menuBgRipple': p.menuBgRipple,
  'menuIconFg': p.menuIconFg,
  'menuIconFgOver': p.menuIconFgOver,
  'menuSeparatorFg': p.menuSeparatorFg,
  'mainMenuBg': p.mainMenuBg,
  'mainMenuCoverBg': p.mainMenuCoverBg,
  'mainMenuCoverFg': p.mainMenuCoverFg,
  'settingsIconBg1': p.settingsIconBg1,
  'settingsIconBg2': p.settingsIconBg2,
  'settingsIconBg3': p.settingsIconBg3,
  'settingsIconBg4': p.settingsIconBg4,
  'settingsIconBg5': p.settingsIconBg5,
  'settingsIconBg6': p.settingsIconBg6,
  'settingsIconBg8': p.settingsIconBg8,
  'settingsIconBgArchive': p.settingsIconBgArchive,
  'historyPeer1NameFgSelected': p.historyPeer1NameFgSelected,
  'historyPeer2NameFgSelected': p.historyPeer2NameFgSelected,
  'historyPeer3NameFgSelected': p.historyPeer3NameFgSelected,
  'historyPeer4NameFgSelected': p.historyPeer4NameFgSelected,
  'historyPeer5NameFgSelected': p.historyPeer5NameFgSelected,
  'historyPeer6NameFgSelected': p.historyPeer6NameFgSelected,
  'historyPeer7NameFgSelected': p.historyPeer7NameFgSelected,
  'historyPeer8NameFgSelected': p.historyPeer8NameFgSelected,
  'mediaviewFileRedCornerFg': p.mediaviewFileRedCornerFg,
  'mediaviewFileYellowCornerFg': p.mediaviewFileYellowCornerFg,
  'mediaviewFileGreenCornerFg': p.mediaviewFileGreenCornerFg,
  'mediaviewFileBlueCornerFg': p.mediaviewFileBlueCornerFg,
  'premiumButtonBg1': p.premiumButtonBg1,
  'premiumButtonBg2': p.premiumButtonBg2,
  'premiumButtonBg3': p.premiumButtonBg3,
  'premiumIconBg1': p.premiumIconBg1,
  'premiumIconBg2': p.premiumIconBg2,
  'callIconFg': p.callIconFg,
  'tooltipBg': p.tooltipBg,
  'tooltipFg': p.tooltipFg,
  'tooltipBorderFg': p.tooltipBorderFg,
  'importantTooltipBg': p.importantTooltipBg,
  'overviewCheckBg': p.overviewCheckBg,
  // §57.11 derived token synonyms
  'dialogsChatBgOver': p.dialogsChatBgOver,
  'topBarIconFg': p.topBarIconFg,
  'topBarMenuFg': p.topBarMenuFg,
  'topBarTextFg': p.topBarTextFg,
  'profileStatusFg': p.profileStatusFg,
  'slideFadeOutBg': p.slideFadeOutBg,
  'slideFadeOutShadowFg': p.slideFadeOutShadowFg,
  'imageBg': p.imageBg,
  'imageBgTransparent': p.imageBgTransparent,
  'activeButtonFgOver': p.activeButtonFgOver,
  'activeButtonSecondaryFgOver': p.activeButtonSecondaryFgOver,
  'attentionButtonFgOver': p.attentionButtonFgOver,
  'menuSubmenuArrowFg': p.menuSubmenuArrowFg,
  'menuFgDisabled': p.menuFgDisabled,
  'smallCloseIconFg': p.smallCloseIconFg,
  'smallCloseIconFgOver': p.smallCloseIconFgOver,
  'radialFg': p.radialFg,
  'radialBg': p.radialBg,
  'placeholderFg': p.placeholderFg,
  'placeholderFgActive': p.placeholderFgActive,
  'inputBorderFg': p.inputBorderFg,
  'filterInputBorderFg': p.filterInputBorderFg,
  'filterInputActiveBg': p.filterInputActiveBg,
  'filterInputInactiveBg': p.filterInputInactiveBg,
  'checkboxFg': p.checkboxFg,
  'botKbBg': p.botKbBg,
  'botKbDownBg': p.botKbDownBg,
  'botKbColor': p.botKbColor,
  'botKbPrimaryBg': p.botKbPrimaryBg,
  'botKbDangerBg': p.botKbDangerBg,
  'botKbSuccessBg': p.botKbSuccessBg,
  'botKbInlinePrimaryBg': p.botKbInlinePrimaryBg,
  'botKbInlineDangerBg': p.botKbInlineDangerBg,
  'botKbInlineSuccessBg': p.botKbInlineSuccessBg,
  'sliderBgInactive': p.sliderBgInactive,
  'sliderBgActive': p.sliderBgActive,
  'titleButtonBg': p.titleButtonBg,
  'titleButtonFg': p.titleButtonFg,
  'titleButtonBgOver': p.titleButtonBgOver,
  'titleButtonFgOver': p.titleButtonFgOver,
  'titleButtonBgActive': p.titleButtonBgActive,
  'titleButtonFgActive': p.titleButtonFgActive,
  'titleButtonBgActiveOver': p.titleButtonBgActiveOver,
  'titleButtonFgActiveOver': p.titleButtonFgActiveOver,
  'titleButtonCloseBg': p.titleButtonCloseBg,
  'titleButtonCloseFg': p.titleButtonCloseFg,
  'titleButtonCloseBgOver': p.titleButtonCloseBgOver,
  'titleButtonCloseFgOver': p.titleButtonCloseFgOver,
  'titleButtonCloseBgActive': p.titleButtonCloseBgActive,
  'titleButtonCloseFgActive': p.titleButtonCloseFgActive,
  'titleButtonCloseBgActiveOver': p.titleButtonCloseBgActiveOver,
  'titleButtonCloseFgActiveOver': p.titleButtonCloseFgActiveOver,
  'trayCounterBg': p.trayCounterBg,
  'trayCounterBgMute': p.trayCounterBgMute,
  'trayCounterFg': p.trayCounterFg,
  'trayCounterBgMacInvert': p.trayCounterBgMacInvert,
  'trayCounterFgMacInvert': p.trayCounterFgMacInvert,
  'cancelIconFg': p.cancelIconFg,
  'cancelIconFgOver': p.cancelIconFgOver,
  'boxTitleCloseFg': p.boxTitleCloseFg,
  'boxTitleCloseFgOver': p.boxTitleCloseFgOver,
  'boxDividerFg': p.boxDividerFg,
  'paymentsTipActive': p.paymentsTipActive,
  'membersAboutLimitFg': p.membersAboutLimitFg,
  'contactsBg': p.contactsBg,
  'contactsBgOver': p.contactsBgOver,
  'contactsNameFg': p.contactsNameFg,
  'contactsStatusFg': p.contactsStatusFg,
  'contactsStatusFgOver': p.contactsStatusFgOver,
  'contactsStatusFgOnline': p.contactsStatusFgOnline,
  'photoCropFadeBg': p.photoCropFadeBg,
  'photoCropPointFg': p.photoCropPointFg,
  'callArrowFg': p.callArrowFg,
  'callArrowMissedFg': p.callArrowMissedFg,
  'introBg': p.introBg,
  'introTitleFg': p.introTitleFg,
  'introDescriptionFg': p.introDescriptionFg,
  'introCoverPlaneInner': p.introCoverPlaneInner,
  'introCoverPlaneOuter': p.introCoverPlaneOuter,
  'dialogsMenuIconFg': p.dialogsMenuIconFg,
  'dialogsMenuIconFgOver': p.dialogsMenuIconFgOver,
  'dialogsChatIconFg': p.dialogsChatIconFg,
  'dialogsChatIconFgOver': p.dialogsChatIconFgOver,
  'dialogsDateFgOver': p.dialogsDateFgOver,
  'dialogsTextFgServiceOver': p.dialogsTextFgServiceOver,
  'dialogsDraftFgOver': p.dialogsDraftFgOver,
  'dialogsVerifiedIconBgOver': p.dialogsVerifiedIconBgOver,
  'dialogsVerifiedIconFgOver': p.dialogsVerifiedIconFgOver,
  'dialogsSendingIconFgOver': p.dialogsSendingIconFgOver,
  'dialogsSentIconFgOver': p.dialogsSentIconFgOver,
  'dialogsUnreadBgOver': p.dialogsUnreadBgOver,
  'dialogsUnreadBgMutedOver': p.dialogsUnreadBgMutedOver,
  'dialogsUnreadFgOver': p.dialogsUnreadFgOver,
  'dialogsArchiveFgOver': p.dialogsArchiveFgOver,
  'dialogsScamFg': p.dialogsScamFg,
  'dialogsScamFgOver': p.dialogsScamFgOver,
  'dialogsChatIconFgActive': p.dialogsChatIconFgActive,
  'dialogsDateFgActive': p.dialogsDateFgActive,
  'dialogsTextFgServiceActive': p.dialogsTextFgServiceActive,
  'dialogsDraftFgActive': p.dialogsDraftFgActive,
  'dialogsVerifiedIconBgActive': p.dialogsVerifiedIconBgActive,
  'dialogsVerifiedIconFgActive': p.dialogsVerifiedIconFgActive,
  'dialogsSendingIconFgActive': p.dialogsSendingIconFgActive,
  'dialogsSentIconFgActive': p.dialogsSentIconFgActive,
  'dialogsScamFgActive': p.dialogsScamFgActive,
  'dialogsMentionIconFg': p.dialogsMentionIconFg,
  'dialogsReactionIconFg': p.dialogsReactionIconFg,
  'dialogsPollIconFg': p.dialogsPollIconFg,
  'searchedBarBg': p.searchedBarBg,
  'searchedBarFg': p.searchedBarFg,
  'emojiPanBg': p.emojiPanBg,
  'emojiPanCategories': p.emojiPanCategories,
  'emojiPanHeaderFg': p.emojiPanHeaderFg,
  'emojiPanHeaderBg': p.emojiPanHeaderBg,
  'emojiIconFg': p.emojiIconFg,
  'emojiSubIconFgActive': p.emojiSubIconFgActive,
  'stickerPanDeleteBg': p.stickerPanDeleteBg,
  'stickerPanDeleteFg': p.stickerPanDeleteFg,
  'stickerPreviewBg': p.stickerPreviewBg,
  'stickerPanPremium1': p.stickerPanPremium1,
  'stickerPanPremium2': p.stickerPanPremium2,
  'historyTextInFgSelected': p.historyTextInFgSelected,
  'historyTextOutFgSelected': p.historyTextOutFgSelected,
  'historyLinkInFg': p.historyLinkInFg,
  'historyLinkInFgSelected': p.historyLinkInFgSelected,
  'historyLinkOutFg': p.historyLinkOutFg,
  'historyLinkOutFgSelected': p.historyLinkOutFgSelected,
  'historyFileNameInFg': p.historyFileNameInFg,
  'historyFileNameInFgSelected': p.historyFileNameInFgSelected,
  'historyFileNameOutFg': p.historyFileNameOutFg,
  'historyFileNameOutFgSelected': p.historyFileNameOutFgSelected,
  'historyOutIconFgSelected': p.historyOutIconFgSelected,
  'historyCallArrowInFg': p.historyCallArrowInFg,
  'historyCallArrowInFgSelected': p.historyCallArrowInFgSelected,
  'historyCallArrowMissedInFg': p.historyCallArrowMissedInFg,
  'historyCallArrowMissedInFgSelected': p.historyCallArrowMissedInFgSelected,
  'historyCallArrowOutFg': p.historyCallArrowOutFg,
  'historyCallArrowOutFgSelected': p.historyCallArrowOutFgSelected,
  'historyUnreadBarBorder': p.historyUnreadBarBorder,
  'historyForwardChooseBg': p.historyForwardChooseBg,
  'historyForwardChooseFg': p.historyForwardChooseFg,
  'historyPeerUserpicFg': p.historyPeerUserpicFg,
  'historyPeerSavedMessagesBg': p.historyPeerSavedMessagesBg,
  'historyPeerArchiveUserpicBg': p.historyPeerArchiveUserpicBg,
  'historyPeerSavedMessagesBg2': p.historyPeerSavedMessagesBg2,
  'settingsIconFg': p.settingsIconFg,
  'msgInServiceFgSelected': p.msgInServiceFgSelected,
  'msgOutServiceFgSelected': p.msgOutServiceFgSelected,
  'msgInShadowSelected': p.msgInShadowSelected,
  'msgOutShadowSelected': p.msgOutShadowSelected,
  'msgInDateFgSelected': p.msgInDateFgSelected,
  'msgOutDateFgSelected': p.msgOutDateFgSelected,
  'msgInReplyBarSelColor': p.msgInReplyBarSelColor,
  'msgOutReplyBarSelColor': p.msgOutReplyBarSelColor,
  'msgImgReplyBarColor': p.msgImgReplyBarColor,
  'msgInMonoFgSelected': p.msgInMonoFgSelected,
  'msgOutMonoFgSelected': p.msgOutMonoFgSelected,
  'msgDateImgFg': p.msgDateImgFg,
  'msgFileThumbLinkInFg': p.msgFileThumbLinkInFg,
  'msgFileThumbLinkInFgSelected': p.msgFileThumbLinkInFgSelected,
  'msgFileThumbLinkOutFg': p.msgFileThumbLinkOutFg,
  'msgFileThumbLinkOutFgSelected': p.msgFileThumbLinkOutFgSelected,
  'msgFileInBgOver': p.msgFileInBgOver,
  'msgFileInBgSelected': p.msgFileInBgSelected,
  'msgFileOutBgSelected': p.msgFileOutBgSelected,
  'historyFileInIconFg': p.historyFileInIconFg,
  'historyFileInIconFgSelected': p.historyFileInIconFgSelected,
  'historyFileInRadialFg': p.historyFileInRadialFg,
  'historyFileInRadialFgSelected': p.historyFileInRadialFgSelected,
  'historyFileOutIconFg': p.historyFileOutIconFg,
  'historyFileOutIconFgSelected': p.historyFileOutIconFgSelected,
  'historyFileOutRadialFg': p.historyFileOutRadialFg,
  'historyFileOutRadialFgSelected': p.historyFileOutRadialFgSelected,
  'historyFileThumbIconFg': p.historyFileThumbIconFg,
  'historyFileThumbIconFgSelected': p.historyFileThumbIconFgSelected,
  'historyFileThumbRadialFg': p.historyFileThumbRadialFg,
  'historyFileThumbRadialFgSelected': p.historyFileThumbRadialFgSelected,
  'historyVideoMessageProgressFg': p.historyVideoMessageProgressFg,
  'msgWaveformInActiveSelected': p.msgWaveformInActiveSelected,
  'msgWaveformInInactiveSelected': p.msgWaveformInInactiveSelected,
  'msgWaveformOutActiveSelected': p.msgWaveformOutActiveSelected,
  'msgWaveformOutInactiveSelected': p.msgWaveformOutInactiveSelected,
  'msgBotKbOverBgAdd': p.msgBotKbOverBgAdd,
  'msgBotKbIconFg': p.msgBotKbIconFg,
  'msgBotKbRippleBg': p.msgBotKbRippleBg,
  'mediaInFg': p.mediaInFg,
  'mediaInFgSelected': p.mediaInFgSelected,
  'mediaOutFg': p.mediaOutFg,
  'mediaOutFgSelected': p.mediaOutFgSelected,
  'youtubePlayIconBg': p.youtubePlayIconBg,
  'youtubePlayIconFg': p.youtubePlayIconFg,
  'videoPlayIconBg': p.videoPlayIconBg,
  'videoPlayIconFg': p.videoPlayIconFg,
  'toastBg': p.toastBg,
  'toastFg': p.toastFg,
  'historyToDownBgRipple': p.historyToDownBgRipple,
  'historyToDownFgOver': p.historyToDownFgOver,
  'historyToDownShadow': p.historyToDownShadow,
  'historyComposeAreaFgService': p.historyComposeAreaFgService,
  'historySendIconFgOver': p.historySendIconFgOver,
  'historyReplyCancelFg': p.historyReplyCancelFg,
  'historyReplyCancelFgOver': p.historyReplyCancelFgOver,
  'mapPointDrop': p.mapPointDrop,
  'mapPointDot': p.mapPointDot,
  'overviewCheckBgActive': p.overviewCheckBgActive,
  'overviewCheckBorder': p.overviewCheckBorder,
  'overviewCheckFgActive': p.overviewCheckFgActive,
  'overviewPhotoSelectOverlay': p.overviewPhotoSelectOverlay,
  'notificationsBoxMonitorFg': p.notificationsBoxMonitorFg,
  'notificationsBoxScreenBg': p.notificationsBoxScreenBg,
  'notificationSampleUserpicFg': p.notificationSampleUserpicFg,
  'notificationSampleCloseFg': p.notificationSampleCloseFg,
  'notificationSampleTextFg': p.notificationSampleTextFg,
  'notificationSampleNameFg': p.notificationSampleNameFg,
  'mainMenuCloudFg': p.mainMenuCloudFg,
  'mainMenuCloudBg': p.mainMenuCloudBg,
  'mediaPlayerBg': p.mediaPlayerBg,
  'mediaPlayerActiveFg': p.mediaPlayerActiveFg,
  'mediaPlayerInactiveFg': p.mediaPlayerInactiveFg,
  'mediaPlayerDisabledFg': p.mediaPlayerDisabledFg,
  'mediaviewFileBg': p.mediaviewFileBg,
  'mediaviewFileNameFg': p.mediaviewFileNameFg,
  'mediaviewFileSizeFg': p.mediaviewFileSizeFg,
  'mediaviewFileExtFg': p.mediaviewFileExtFg,
  'mediaviewMenuBg': p.mediaviewMenuBg,
  'mediaviewMenuBgOver': p.mediaviewMenuBgOver,
  'mediaviewMenuBgRipple': p.mediaviewMenuBgRipple,
  'mediaviewMenuFg': p.mediaviewMenuFg,
  'mediaviewVideoBg': p.mediaviewVideoBg,
  'mediaviewCaptionFg': p.mediaviewCaptionFg,
  'mediaviewTextLinkFg': p.mediaviewTextLinkFg,
  'mediaviewSaveMsgBg': p.mediaviewSaveMsgBg,
  'mediaviewSaveMsgFg': p.mediaviewSaveMsgFg,
  'mediaviewPlaybackInactiveOver': p.mediaviewPlaybackInactiveOver,
  'mediaviewPlaybackProgressFg': p.mediaviewPlaybackProgressFg,
  'mediaviewPlaybackIconFg': p.mediaviewPlaybackIconFg,
  'mediaviewPlaybackIconFgOver': p.mediaviewPlaybackIconFgOver,
  'mediaviewPlaybackIconRipple': p.mediaviewPlaybackIconRipple,
  'mediaviewPipControlsFg': p.mediaviewPipControlsFg,
  'mediaviewPipControlsFgOver': p.mediaviewPipControlsFgOver,
  'mediaviewPipPlaybackActive': p.mediaviewPipPlaybackActive,
  'mediaviewPipPlaybackInactive': p.mediaviewPipPlaybackInactive,
  'mediaviewTransparentBg': p.mediaviewTransparentBg,
  'mediaviewTransparentFg': p.mediaviewTransparentFg,
  'notificationBg': p.notificationBg,
  'callBg': p.callBg,
  'callBgOpaque': p.callBgOpaque,
  'callBgButton': p.callBgButton,
  'callNameFg': p.callNameFg,
  'callStatusFg': p.callStatusFg,
  'callIconBg': p.callIconBg,
  'callIconBgActive': p.callIconBgActive,
  'callIconFgActive': p.callIconFgActive,
  'callIconActiveRipple': p.callIconActiveRipple,
  'callAnswerBg': p.callAnswerBg,
  'callAnswerRipple': p.callAnswerRipple,
  'callAnswerBgOuter': p.callAnswerBgOuter,
  'callHangupBg': p.callHangupBg,
  'callHangupRipple': p.callHangupRipple,
  'callMuteRipple': p.callMuteRipple,
  'callBarBg': p.callBarBg,
  'callBarMuteRipple': p.callBarMuteRipple,
  'callBarBgMuted': p.callBarBgMuted,
  'callBarFg': p.callBarFg,
  'importantTooltipFg': p.importantTooltipFg,
  'importantTooltipFgLink': p.importantTooltipFgLink,
  'premiumButtonFg': p.premiumButtonFg,
  'premiumIconBg3': p.premiumIconBg3,
  'groupCallBg': p.groupCallBg,
  'groupCallActiveFg': p.groupCallActiveFg,
  'groupCallMembersBg': p.groupCallMembersBg,
  'groupCallMembersBgOver': p.groupCallMembersBgOver,
  'groupCallMembersBgRipple': p.groupCallMembersBgRipple,
  'groupCallMembersFg': p.groupCallMembersFg,
  'groupCallMemberActiveIcon': p.groupCallMemberActiveIcon,
  'groupCallMemberActiveStatus': p.groupCallMemberActiveStatus,
  'groupCallMemberInactiveIcon': p.groupCallMemberInactiveIcon,
  'groupCallMemberInactiveStatus': p.groupCallMemberInactiveStatus,
  'groupCallMemberMutedIcon': p.groupCallMemberMutedIcon,
  'groupCallMemberNotJoinedStatus': p.groupCallMemberNotJoinedStatus,
  'groupCallIconFg': p.groupCallIconFg,
  'groupCallLive1': p.groupCallLive1,
  'groupCallLive2': p.groupCallLive2,
  'groupCallMuted1': p.groupCallMuted1,
  'groupCallMuted2': p.groupCallMuted2,
  'groupCallForceMutedBar1': p.groupCallForceMutedBar1,
  'groupCallForceMutedBar2': p.groupCallForceMutedBar2,
  'groupCallForceMutedBar3': p.groupCallForceMutedBar3,
  'groupCallForceMuted1': p.groupCallForceMuted1,
  'groupCallForceMuted2': p.groupCallForceMuted2,
  'groupCallForceMuted3': p.groupCallForceMuted3,
  'groupCallMenuBg': p.groupCallMenuBg,
  'groupCallMenuBgOver': p.groupCallMenuBgOver,
  'groupCallMenuBgRipple': p.groupCallMenuBgRipple,
  'groupCallLeaveBg': p.groupCallLeaveBg,
  'groupCallLeaveBgRipple': p.groupCallLeaveBgRipple,
  'groupCallVideoTextFg': p.groupCallVideoTextFg,
  'groupCallVideoSubTextFg': p.groupCallVideoSubTextFg,
};

TelegramPalette paletteFromMap(Map<String, Color> m, TelegramPalette fb) =>
    TelegramPalette(
      windowBg: m['windowBg'] ?? fb.windowBg,
      windowBgOver: m['windowBgOver'] ?? fb.windowBgOver,
      windowBgRipple: m['windowBgRipple'] ?? fb.windowBgRipple,
      windowBgActive: m['windowBgActive'] ?? fb.windowBgActive,
      windowFg: m['windowFg'] ?? fb.windowFg,
      windowFgOver: m['windowFgOver'] ?? fb.windowFgOver,
      windowFgActive: m['windowFgActive'] ?? fb.windowFgActive,
      windowSubTextFg: m['windowSubTextFg'] ?? fb.windowSubTextFg,
      windowSubTextFgOver: m['windowSubTextFgOver'] ?? fb.windowSubTextFgOver,
      windowBoldFg: m['windowBoldFg'] ?? fb.windowBoldFg,
      windowBoldFgOver: m['windowBoldFgOver'] ?? fb.windowBoldFgOver,
      windowActiveTextFg: m['windowActiveTextFg'] ?? fb.windowActiveTextFg,
      windowShadowFg: m['windowShadowFg'] ?? fb.windowShadowFg,
      windowShadowFgFallback: m['windowShadowFgFallback'] ?? fb.windowShadowFgFallback,
      shadowFg: m['shadowFg'] ?? fb.shadowFg,
      titleBg: m['titleBg'] ?? fb.titleBg,
      titleBgActive: m['titleBgActive'] ?? fb.titleBgActive,
      titleShadow: m['titleShadow'] ?? fb.titleShadow,
      titleFg: m['titleFg'] ?? fb.titleFg,
      titleFgActive: m['titleFgActive'] ?? fb.titleFgActive,
      layerBg: m['layerBg'] ?? fb.layerBg,
      activeButtonBg: m['activeButtonBg'] ?? fb.activeButtonBg,
      activeButtonBgOver: m['activeButtonBgOver'] ?? fb.activeButtonBgOver,
      activeButtonBgRipple: m['activeButtonBgRipple'] ?? fb.activeButtonBgRipple,
      activeButtonFg: m['activeButtonFg'] ?? fb.activeButtonFg,
      activeButtonSecondaryFg: m['activeButtonSecondaryFg'] ?? fb.activeButtonSecondaryFg,
      activeLineFg: m['activeLineFg'] ?? fb.activeLineFg,
      activeLineFgError: m['activeLineFgError'] ?? fb.activeLineFgError,
      lightButtonBg: m['lightButtonBg'] ?? fb.lightButtonBg,
      lightButtonBgOver: m['lightButtonBgOver'] ?? fb.lightButtonBgOver,
      lightButtonBgRipple: m['lightButtonBgRipple'] ?? fb.lightButtonBgRipple,
      lightButtonFg: m['lightButtonFg'] ?? fb.lightButtonFg,
      lightButtonFgOver: m['lightButtonFgOver'] ?? fb.lightButtonFgOver,
      attentionButtonFg: m['attentionButtonFg'] ?? fb.attentionButtonFg,
      attentionButtonBgOver: m['attentionButtonBgOver'] ?? fb.attentionButtonBgOver,
      attentionButtonBgRipple: m['attentionButtonBgRipple'] ?? fb.attentionButtonBgRipple,
      outlineButtonOutlineFg: m['outlineButtonOutlineFg'] ?? fb.outlineButtonOutlineFg,
      dialogsBg: m['dialogsBg'] ?? fb.dialogsBg,
      dialogsBgOver: m['dialogsBgOver'] ?? m['dialogsChatBgOver'] ?? fb.dialogsBgOver,
      dialogsBgActive: m['dialogsBgActive'] ?? fb.dialogsBgActive,
      dialogsRippleBg: m['dialogsRippleBg'] ?? fb.dialogsRippleBg,
      dialogsRippleBgActive: m['dialogsRippleBgActive'] ?? fb.dialogsRippleBgActive,
      dialogsNameFg: m['dialogsNameFg'] ?? fb.dialogsNameFg,
      dialogsNameFgOver: m['dialogsNameFgOver'] ?? fb.dialogsNameFgOver,
      dialogsNameFgActive: m['dialogsNameFgActive'] ?? fb.dialogsNameFgActive,
      dialogsTextFg: m['dialogsTextFg'] ?? fb.dialogsTextFg,
      dialogsTextFgOver: m['dialogsTextFgOver'] ?? fb.dialogsTextFgOver,
      dialogsTextFgActive: m['dialogsTextFgActive'] ?? fb.dialogsTextFgActive,
      dialogsTextFgService: m['dialogsTextFgService'] ?? fb.dialogsTextFgService,
      dialogsDateFg: m['dialogsDateFg'] ?? fb.dialogsDateFg,
      dialogsDraftFg: m['dialogsDraftFg'] ?? fb.dialogsDraftFg,
      dialogsUnreadBg: m['dialogsUnreadBg'] ?? fb.dialogsUnreadBg,
      dialogsUnreadBgMuted: m['dialogsUnreadBgMuted'] ?? fb.dialogsUnreadBgMuted,
      dialogsUnreadBgActive: m['dialogsUnreadBgActive'] ?? fb.dialogsUnreadBgActive,
      dialogsUnreadBgMutedActive: m['dialogsUnreadBgMutedActive'] ?? fb.dialogsUnreadBgMutedActive,
      dialogsUnreadFg: m['dialogsUnreadFg'] ?? fb.dialogsUnreadFg,
      dialogsUnreadFgActive: m['dialogsUnreadFgActive'] ?? fb.dialogsUnreadFgActive,
      dialogsOnlineBadgeFg: m['dialogsOnlineBadgeFg'] ?? fb.dialogsOnlineBadgeFg,
      dialogsOnlineBadgeFgActive: m['dialogsOnlineBadgeFgActive'] ?? fb.dialogsOnlineBadgeFgActive,
      dialogsSentIconFg: m['dialogsSentIconFg'] ?? fb.dialogsSentIconFg,
      dialogsSendingIconFg: m['dialogsSendingIconFg'] ?? fb.dialogsSendingIconFg,
      dialogsVerifiedIconBg: m['dialogsVerifiedIconBg'] ?? fb.dialogsVerifiedIconBg,
      dialogsVerifiedIconFg: m['dialogsVerifiedIconFg'] ?? fb.dialogsVerifiedIconFg,
      dialogsArchiveFg: m['dialogsArchiveFg'] ?? fb.dialogsArchiveFg,
      dialogsForwardBg: m['dialogsForwardBg'] ?? fb.dialogsForwardBg,
      dialogsForwardFg: m['dialogsForwardFg'] ?? fb.dialogsForwardFg,
      topBarBg: m['topBarBg'] ?? fb.topBarBg,
      msgInBg: m['msgInBg'] ?? fb.msgInBg,
      msgInBgSelected: m['msgInBgSelected'] ?? fb.msgInBgSelected,
      msgOutBg: m['msgOutBg'] ?? fb.msgOutBg,
      msgOutBgSelected: m['msgOutBgSelected'] ?? fb.msgOutBgSelected,
      msgInShadow: m['msgInShadow'] ?? fb.msgInShadow,
      msgOutShadow: m['msgOutShadow'] ?? fb.msgOutShadow,
      msgInDateFg: m['msgInDateFg'] ?? fb.msgInDateFg,
      msgOutDateFg: m['msgOutDateFg'] ?? fb.msgOutDateFg,
      msgInServiceFg: m['msgInServiceFg'] ?? fb.msgInServiceFg,
      msgOutServiceFg: m['msgOutServiceFg'] ?? fb.msgOutServiceFg,
      msgInReplyBarColor: m['msgInReplyBarColor'] ?? fb.msgInReplyBarColor,
      msgOutReplyBarColor: m['msgOutReplyBarColor'] ?? fb.msgOutReplyBarColor,
      msgInMonoFg: m['msgInMonoFg'] ?? fb.msgInMonoFg,
      msgOutMonoFg: m['msgOutMonoFg'] ?? fb.msgOutMonoFg,
      msgFileInBg: m['msgFileInBg'] ?? fb.msgFileInBg,
      msgFileOutBg: m['msgFileOutBg'] ?? fb.msgFileOutBg,
      msgServiceBg: m['msgServiceBg'] ?? fb.msgServiceBg,
      msgServiceBgSelected: m['msgServiceBgSelected'] ?? fb.msgServiceBgSelected,
      msgServiceFg: m['msgServiceFg'] ?? fb.msgServiceFg,
      msgSelectOverlay: m['msgSelectOverlay'] ?? fb.msgSelectOverlay,
      msgStickerOverlay: m['msgStickerOverlay'] ?? fb.msgStickerOverlay,
      msgDateImgBg: m['msgDateImgBg'] ?? fb.msgDateImgBg,
      msgDateImgBgOver: m['msgDateImgBgOver'] ?? fb.msgDateImgBgOver,
      msgDateImgBgSelected: m['msgDateImgBgSelected'] ?? fb.msgDateImgBgSelected,
      historyTextInFg: m['historyTextInFg'] ?? fb.historyTextInFg,
      historyTextOutFg: m['historyTextOutFg'] ?? fb.historyTextOutFg,
      historyComposeAreaBg: m['historyComposeAreaBg'] ?? fb.historyComposeAreaBg,
      historyComposeAreaFg: m['historyComposeAreaFg'] ?? fb.historyComposeAreaFg,
      historyComposeIconFg: m['historyComposeIconFg'] ?? fb.historyComposeIconFg,
      historyComposeIconFgOver: m['historyComposeIconFgOver'] ?? fb.historyComposeIconFgOver,
      historyComposeButtonBg: m['historyComposeButtonBg'] ?? fb.historyComposeButtonBg,
      historyComposeButtonBgOver: m['historyComposeButtonBgOver'] ?? fb.historyComposeButtonBgOver,
      historyComposeButtonBgRipple: m['historyComposeButtonBgRipple'] ?? fb.historyComposeButtonBgRipple,
      historySendIconFg: m['historySendIconFg'] ?? fb.historySendIconFg,
      historyReplyBg: m['historyReplyBg'] ?? fb.historyReplyBg,
      historyReplyIconFg: m['historyReplyIconFg'] ?? fb.historyReplyIconFg,
      historyPinnedBg: m['historyPinnedBg'] ?? fb.historyPinnedBg,
      historyUnreadBarBg: m['historyUnreadBarBg'] ?? fb.historyUnreadBarBg,
      historyUnreadBarFg: m['historyUnreadBarFg'] ?? fb.historyUnreadBarFg,
      historyScrollBg: m['historyScrollBg'] ?? fb.historyScrollBg,
      historyScrollBgOver: m['historyScrollBgOver'] ?? fb.historyScrollBgOver,
      historyScrollBarBg: m['historyScrollBarBg'] ?? fb.historyScrollBarBg,
      historyScrollBarBgOver: m['historyScrollBarBgOver'] ?? fb.historyScrollBarBgOver,
      historyToDownBg: m['historyToDownBg'] ?? fb.historyToDownBg,
      historyToDownBgOver: m['historyToDownBgOver'] ?? fb.historyToDownBgOver,
      historyToDownFg: m['historyToDownFg'] ?? fb.historyToDownFg,
      historyOutIconFg: m['historyOutIconFg'] ?? fb.historyOutIconFg,
      historySendingOutIconFg: m['historySendingOutIconFg'] ?? fb.historySendingOutIconFg,
      historySendingInIconFg: m['historySendingInIconFg'] ?? fb.historySendingInIconFg,
      historyIconFgInverted: m['historyIconFgInverted'] ?? fb.historyIconFgInverted,
      historySendingInvertedIconFg: m['historySendingInvertedIconFg'] ?? fb.historySendingInvertedIconFg,
      historyPeer1NameFg: m['historyPeer1NameFg'] ?? fb.historyPeer1NameFg,
      historyPeer2NameFg: m['historyPeer2NameFg'] ?? fb.historyPeer2NameFg,
      historyPeer3NameFg: m['historyPeer3NameFg'] ?? fb.historyPeer3NameFg,
      historyPeer4NameFg: m['historyPeer4NameFg'] ?? fb.historyPeer4NameFg,
      historyPeer5NameFg: m['historyPeer5NameFg'] ?? fb.historyPeer5NameFg,
      historyPeer6NameFg: m['historyPeer6NameFg'] ?? fb.historyPeer6NameFg,
      historyPeer7NameFg: m['historyPeer7NameFg'] ?? fb.historyPeer7NameFg,
      historyPeer8NameFg: m['historyPeer8NameFg'] ?? fb.historyPeer8NameFg,
      historyPeer1UserpicBg: m['historyPeer1UserpicBg'] ?? fb.historyPeer1UserpicBg,
      historyPeer2UserpicBg: m['historyPeer2UserpicBg'] ?? fb.historyPeer2UserpicBg,
      historyPeer3UserpicBg: m['historyPeer3UserpicBg'] ?? fb.historyPeer3UserpicBg,
      historyPeer4UserpicBg: m['historyPeer4UserpicBg'] ?? fb.historyPeer4UserpicBg,
      historyPeer5UserpicBg: m['historyPeer5UserpicBg'] ?? fb.historyPeer5UserpicBg,
      historyPeer6UserpicBg: m['historyPeer6UserpicBg'] ?? fb.historyPeer6UserpicBg,
      historyPeer7UserpicBg: m['historyPeer7UserpicBg'] ?? fb.historyPeer7UserpicBg,
      historyPeer8UserpicBg: m['historyPeer8UserpicBg'] ?? fb.historyPeer8UserpicBg,
      historyPeer1UserpicBg2: m['historyPeer1UserpicBg2'] ?? fb.historyPeer1UserpicBg2,
      historyPeer2UserpicBg2: m['historyPeer2UserpicBg2'] ?? fb.historyPeer2UserpicBg2,
      historyPeer3UserpicBg2: m['historyPeer3UserpicBg2'] ?? fb.historyPeer3UserpicBg2,
      historyPeer4UserpicBg2: m['historyPeer4UserpicBg2'] ?? fb.historyPeer4UserpicBg2,
      historyPeer5UserpicBg2: m['historyPeer5UserpicBg2'] ?? fb.historyPeer5UserpicBg2,
      historyPeer6UserpicBg2: m['historyPeer6UserpicBg2'] ?? fb.historyPeer6UserpicBg2,
      historyPeer7UserpicBg2: m['historyPeer7UserpicBg2'] ?? fb.historyPeer7UserpicBg2,
      historyPeer8UserpicBg2: m['historyPeer8UserpicBg2'] ?? fb.historyPeer8UserpicBg2,
      msgFile1Bg: m['msgFile1Bg'] ?? fb.msgFile1Bg,
      msgFile1BgDark: m['msgFile1BgDark'] ?? fb.msgFile1BgDark,
      msgFile1BgOver: m['msgFile1BgOver'] ?? fb.msgFile1BgOver,
      msgFile1BgSelected: m['msgFile1BgSelected'] ?? fb.msgFile1BgSelected,
      msgFile2Bg: m['msgFile2Bg'] ?? fb.msgFile2Bg,
      msgFile2BgDark: m['msgFile2BgDark'] ?? fb.msgFile2BgDark,
      msgFile2BgOver: m['msgFile2BgOver'] ?? fb.msgFile2BgOver,
      msgFile2BgSelected: m['msgFile2BgSelected'] ?? fb.msgFile2BgSelected,
      msgFile3Bg: m['msgFile3Bg'] ?? fb.msgFile3Bg,
      msgFile3BgDark: m['msgFile3BgDark'] ?? fb.msgFile3BgDark,
      msgFile3BgOver: m['msgFile3BgOver'] ?? fb.msgFile3BgOver,
      msgFile3BgSelected: m['msgFile3BgSelected'] ?? fb.msgFile3BgSelected,
      msgFile4Bg: m['msgFile4Bg'] ?? fb.msgFile4Bg,
      msgFile4BgDark: m['msgFile4BgDark'] ?? fb.msgFile4BgDark,
      msgFile4BgOver: m['msgFile4BgOver'] ?? fb.msgFile4BgOver,
      msgFile4BgSelected: m['msgFile4BgSelected'] ?? fb.msgFile4BgSelected,
      msgWaveformInActive: m['msgWaveformInActive'] ?? fb.msgWaveformInActive,
      msgWaveformInInactive: m['msgWaveformInInactive'] ?? fb.msgWaveformInInactive,
      msgWaveformOutActive: m['msgWaveformOutActive'] ?? fb.msgWaveformOutActive,
      msgWaveformOutInactive: m['msgWaveformOutInactive'] ?? fb.msgWaveformOutInactive,
      mediaviewBg: m['mediaviewBg'] ?? fb.mediaviewBg,
      mediaviewControlBg: m['mediaviewControlBg'] ?? fb.mediaviewControlBg,
      mediaviewControlFg: m['mediaviewControlFg'] ?? fb.mediaviewControlFg,
      mediaviewCaptionBg: m['mediaviewCaptionBg'] ?? fb.mediaviewCaptionBg,
      mediaviewPlaybackActive: m['mediaviewPlaybackActive'] ?? fb.mediaviewPlaybackActive,
      mediaviewPlaybackInactive: m['mediaviewPlaybackInactive'] ?? fb.mediaviewPlaybackInactive,
      mediaviewPlaybackActiveOver: m['mediaviewPlaybackActiveOver'] ?? fb.mediaviewPlaybackActiveOver,
      introCoverTopBg: m['introCoverTopBg'] ?? fb.introCoverTopBg,
      introCoverBottomBg: m['introCoverBottomBg'] ?? fb.introCoverBottomBg,
      introCoverIconsFg: m['introCoverIconsFg'] ?? fb.introCoverIconsFg,
      introCoverPlaneTrace: m['introCoverPlaneTrace'] ?? fb.introCoverPlaneTrace,
      introCoverPlaneTop: m['introCoverPlaneTop'] ?? fb.introCoverPlaneTop,
      scrollBarBg: m['scrollBarBg'] ?? fb.scrollBarBg,
      scrollBarBgOver: m['scrollBarBgOver'] ?? fb.scrollBarBgOver,
      scrollBg: m['scrollBg'] ?? fb.scrollBg,
      scrollBgOver: m['scrollBgOver'] ?? fb.scrollBgOver,
      boxBg: m['boxBg'] ?? fb.boxBg,
      boxTextFg: m['boxTextFg'] ?? fb.boxTextFg,
      boxTitleFg: m['boxTitleFg'] ?? fb.boxTitleFg,
      boxSearchBg: m['boxSearchBg'] ?? fb.boxSearchBg,
      boxTitleAdditionalFg: m['boxTitleAdditionalFg'] ?? fb.boxTitleAdditionalFg,
      boxTextFgGood: m['boxTextFgGood'] ?? fb.boxTextFgGood,
      boxTextFgError: m['boxTextFgError'] ?? fb.boxTextFgError,
      boxDividerBg: m['boxDividerBg'] ?? fb.boxDividerBg,
      profileStatusFgOver: m['profileStatusFgOver'] ?? fb.profileStatusFgOver,
      profileVerifiedCheckBg: m['profileVerifiedCheckBg'] ?? fb.profileVerifiedCheckBg,
      profileVerifiedCheckFg: m['profileVerifiedCheckFg'] ?? fb.profileVerifiedCheckFg,
      profileAdminStartFg: m['profileAdminStartFg'] ?? fb.profileAdminStartFg,
      profileOtherAdminStarFg: m['profileOtherAdminStarFg'] ?? fb.profileOtherAdminStarFg,
      sideBarBg: m['sideBarBg'] ?? fb.sideBarBg,
      sideBarBgActive: m['sideBarBgActive'] ?? fb.sideBarBgActive,
      sideBarBgRipple: m['sideBarBgRipple'] ?? fb.sideBarBgRipple,
      sideBarTextFg: m['sideBarTextFg'] ?? fb.sideBarTextFg,
      sideBarTextFgActive: m['sideBarTextFgActive'] ?? fb.sideBarTextFgActive,
      sideBarIconFg: m['sideBarIconFg'] ?? fb.sideBarIconFg,
      sideBarIconFgActive: m['sideBarIconFgActive'] ?? fb.sideBarIconFgActive,
      sideBarBadgeBg: m['sideBarBadgeBg'] ?? fb.sideBarBadgeBg,
      sideBarBadgeBgMuted: m['sideBarBadgeBgMuted'] ?? fb.sideBarBadgeBgMuted,
      sideBarBadgeFg: m['sideBarBadgeFg'] ?? fb.sideBarBadgeFg,
      menuBg: m['menuBg'] ?? fb.menuBg,
      menuBgOver: m['menuBgOver'] ?? fb.menuBgOver,
      menuBgRipple: m['menuBgRipple'] ?? fb.menuBgRipple,
      menuIconFg: m['menuIconFg'] ?? m['topBarIconFg'] ?? fb.menuIconFg,
      menuIconFgOver: m['menuIconFgOver'] ?? fb.menuIconFgOver,
      menuSeparatorFg: m['menuSeparatorFg'] ?? fb.menuSeparatorFg,
      mainMenuBg: m['mainMenuBg'] ?? fb.mainMenuBg,
      mainMenuCoverBg: m['mainMenuCoverBg'] ?? fb.mainMenuCoverBg,
      mainMenuCoverFg: m['mainMenuCoverFg'] ?? fb.mainMenuCoverFg,
      settingsIconBg1: m['settingsIconBg1'] ?? fb.settingsIconBg1,
      settingsIconBg2: m['settingsIconBg2'] ?? fb.settingsIconBg2,
      settingsIconBg3: m['settingsIconBg3'] ?? fb.settingsIconBg3,
      settingsIconBg4: m['settingsIconBg4'] ?? fb.settingsIconBg4,
      settingsIconBg5: m['settingsIconBg5'] ?? fb.settingsIconBg5,
      settingsIconBg6: m['settingsIconBg6'] ?? fb.settingsIconBg6,
      settingsIconBg8: m['settingsIconBg8'] ?? fb.settingsIconBg8,
      settingsIconBgArchive: m['settingsIconBgArchive'] ?? fb.settingsIconBgArchive,
      historyPeer1NameFgSelected: m['historyPeer1NameFgSelected'] ?? fb.historyPeer1NameFgSelected,
      historyPeer2NameFgSelected: m['historyPeer2NameFgSelected'] ?? fb.historyPeer2NameFgSelected,
      historyPeer3NameFgSelected: m['historyPeer3NameFgSelected'] ?? fb.historyPeer3NameFgSelected,
      historyPeer4NameFgSelected: m['historyPeer4NameFgSelected'] ?? fb.historyPeer4NameFgSelected,
      historyPeer5NameFgSelected: m['historyPeer5NameFgSelected'] ?? fb.historyPeer5NameFgSelected,
      historyPeer6NameFgSelected: m['historyPeer6NameFgSelected'] ?? fb.historyPeer6NameFgSelected,
      historyPeer7NameFgSelected: m['historyPeer7NameFgSelected'] ?? fb.historyPeer7NameFgSelected,
      historyPeer8NameFgSelected: m['historyPeer8NameFgSelected'] ?? fb.historyPeer8NameFgSelected,
      mediaviewFileRedCornerFg: m['mediaviewFileRedCornerFg'] ?? fb.mediaviewFileRedCornerFg,
      mediaviewFileYellowCornerFg: m['mediaviewFileYellowCornerFg'] ?? fb.mediaviewFileYellowCornerFg,
      mediaviewFileGreenCornerFg: m['mediaviewFileGreenCornerFg'] ?? fb.mediaviewFileGreenCornerFg,
      mediaviewFileBlueCornerFg: m['mediaviewFileBlueCornerFg'] ?? fb.mediaviewFileBlueCornerFg,
      premiumButtonBg1: m['premiumButtonBg1'] ?? fb.premiumButtonBg1,
      premiumButtonBg2: m['premiumButtonBg2'] ?? fb.premiumButtonBg2,
      premiumButtonBg3: m['premiumButtonBg3'] ?? fb.premiumButtonBg3,
      premiumIconBg1: m['premiumIconBg1'] ?? fb.premiumIconBg1,
      premiumIconBg2: m['premiumIconBg2'] ?? fb.premiumIconBg2,
      callIconFg: m['callIconFg'] ?? fb.callIconFg,
      tooltipBg: m['tooltipBg'] ?? fb.tooltipBg,
      tooltipFg: m['tooltipFg'] ?? fb.tooltipFg,
      tooltipBorderFg: m['tooltipBorderFg'] ?? fb.tooltipBorderFg,
      importantTooltipBg: m['importantTooltipBg'] ?? fb.importantTooltipBg,
      overviewCheckBg: m['overviewCheckBg'] ?? fb.overviewCheckBg,
      slideFadeOutBg: m['slideFadeOutBg'] ?? fb.slideFadeOutBg,
      slideFadeOutShadowFg: m['slideFadeOutShadowFg'] ?? fb.slideFadeOutShadowFg,
      imageBg: m['imageBg'] ?? fb.imageBg,
      imageBgTransparent: m['imageBgTransparent'] ?? fb.imageBgTransparent,
      activeButtonFgOver: m['activeButtonFgOver'] ?? fb.activeButtonFgOver,
      activeButtonSecondaryFgOver: m['activeButtonSecondaryFgOver'] ?? fb.activeButtonSecondaryFgOver,
      attentionButtonFgOver: m['attentionButtonFgOver'] ?? fb.attentionButtonFgOver,
      menuSubmenuArrowFg: m['menuSubmenuArrowFg'] ?? fb.menuSubmenuArrowFg,
      menuFgDisabled: m['menuFgDisabled'] ?? fb.menuFgDisabled,
      smallCloseIconFg: m['smallCloseIconFg'] ?? fb.smallCloseIconFg,
      smallCloseIconFgOver: m['smallCloseIconFgOver'] ?? fb.smallCloseIconFgOver,
      radialFg: m['radialFg'] ?? fb.radialFg,
      radialBg: m['radialBg'] ?? fb.radialBg,
      placeholderFg: m['placeholderFg'] ?? fb.placeholderFg,
      placeholderFgActive: m['placeholderFgActive'] ?? fb.placeholderFgActive,
      inputBorderFg: m['inputBorderFg'] ?? fb.inputBorderFg,
      filterInputBorderFg: m['filterInputBorderFg'] ?? fb.filterInputBorderFg,
      filterInputActiveBg: m['filterInputActiveBg'] ?? fb.filterInputActiveBg,
      filterInputInactiveBg: m['filterInputInactiveBg'] ?? fb.filterInputInactiveBg,
      checkboxFg: m['checkboxFg'] ?? fb.checkboxFg,
      botKbBg: m['botKbBg'] ?? fb.botKbBg,
      botKbDownBg: m['botKbDownBg'] ?? fb.botKbDownBg,
      botKbColor: m['botKbColor'] ?? fb.botKbColor,
      botKbPrimaryBg: m['botKbPrimaryBg'] ?? fb.botKbPrimaryBg,
      botKbDangerBg: m['botKbDangerBg'] ?? fb.botKbDangerBg,
      botKbSuccessBg: m['botKbSuccessBg'] ?? fb.botKbSuccessBg,
      botKbInlinePrimaryBg: m['botKbInlinePrimaryBg'] ?? fb.botKbInlinePrimaryBg,
      botKbInlineDangerBg: m['botKbInlineDangerBg'] ?? fb.botKbInlineDangerBg,
      botKbInlineSuccessBg: m['botKbInlineSuccessBg'] ?? fb.botKbInlineSuccessBg,
      sliderBgInactive: m['sliderBgInactive'] ?? fb.sliderBgInactive,
      sliderBgActive: m['sliderBgActive'] ?? fb.sliderBgActive,
      titleButtonBg: m['titleButtonBg'] ?? fb.titleButtonBg,
      titleButtonFg: m['titleButtonFg'] ?? fb.titleButtonFg,
      titleButtonBgOver: m['titleButtonBgOver'] ?? fb.titleButtonBgOver,
      titleButtonFgOver: m['titleButtonFgOver'] ?? fb.titleButtonFgOver,
      titleButtonBgActive: m['titleButtonBgActive'] ?? fb.titleButtonBgActive,
      titleButtonFgActive: m['titleButtonFgActive'] ?? fb.titleButtonFgActive,
      titleButtonBgActiveOver: m['titleButtonBgActiveOver'] ?? fb.titleButtonBgActiveOver,
      titleButtonFgActiveOver: m['titleButtonFgActiveOver'] ?? fb.titleButtonFgActiveOver,
      titleButtonCloseBg: m['titleButtonCloseBg'] ?? fb.titleButtonCloseBg,
      titleButtonCloseFg: m['titleButtonCloseFg'] ?? fb.titleButtonCloseFg,
      titleButtonCloseBgOver: m['titleButtonCloseBgOver'] ?? fb.titleButtonCloseBgOver,
      titleButtonCloseFgOver: m['titleButtonCloseFgOver'] ?? fb.titleButtonCloseFgOver,
      titleButtonCloseBgActive: m['titleButtonCloseBgActive'] ?? fb.titleButtonCloseBgActive,
      titleButtonCloseFgActive: m['titleButtonCloseFgActive'] ?? fb.titleButtonCloseFgActive,
      titleButtonCloseBgActiveOver: m['titleButtonCloseBgActiveOver'] ?? fb.titleButtonCloseBgActiveOver,
      titleButtonCloseFgActiveOver: m['titleButtonCloseFgActiveOver'] ?? fb.titleButtonCloseFgActiveOver,
      trayCounterBg: m['trayCounterBg'] ?? fb.trayCounterBg,
      trayCounterBgMute: m['trayCounterBgMute'] ?? fb.trayCounterBgMute,
      trayCounterFg: m['trayCounterFg'] ?? fb.trayCounterFg,
      trayCounterBgMacInvert: m['trayCounterBgMacInvert'] ?? fb.trayCounterBgMacInvert,
      trayCounterFgMacInvert: m['trayCounterFgMacInvert'] ?? fb.trayCounterFgMacInvert,
      cancelIconFg: m['cancelIconFg'] ?? fb.cancelIconFg,
      cancelIconFgOver: m['cancelIconFgOver'] ?? fb.cancelIconFgOver,
      boxTitleCloseFg: m['boxTitleCloseFg'] ?? fb.boxTitleCloseFg,
      boxTitleCloseFgOver: m['boxTitleCloseFgOver'] ?? fb.boxTitleCloseFgOver,
      boxDividerFg: m['boxDividerFg'] ?? fb.boxDividerFg,
      paymentsTipActive: m['paymentsTipActive'] ?? fb.paymentsTipActive,
      membersAboutLimitFg: m['membersAboutLimitFg'] ?? fb.membersAboutLimitFg,
      contactsBg: m['contactsBg'] ?? fb.contactsBg,
      contactsBgOver: m['contactsBgOver'] ?? fb.contactsBgOver,
      contactsNameFg: m['contactsNameFg'] ?? fb.contactsNameFg,
      contactsStatusFg: m['contactsStatusFg'] ?? fb.contactsStatusFg,
      contactsStatusFgOver: m['contactsStatusFgOver'] ?? fb.contactsStatusFgOver,
      contactsStatusFgOnline: m['contactsStatusFgOnline'] ?? fb.contactsStatusFgOnline,
      photoCropFadeBg: m['photoCropFadeBg'] ?? fb.photoCropFadeBg,
      photoCropPointFg: m['photoCropPointFg'] ?? fb.photoCropPointFg,
      callArrowFg: m['callArrowFg'] ?? fb.callArrowFg,
      callArrowMissedFg: m['callArrowMissedFg'] ?? fb.callArrowMissedFg,
      introBg: m['introBg'] ?? fb.introBg,
      introTitleFg: m['introTitleFg'] ?? fb.introTitleFg,
      introDescriptionFg: m['introDescriptionFg'] ?? fb.introDescriptionFg,
      introCoverPlaneInner: m['introCoverPlaneInner'] ?? fb.introCoverPlaneInner,
      introCoverPlaneOuter: m['introCoverPlaneOuter'] ?? fb.introCoverPlaneOuter,
      dialogsMenuIconFg: m['dialogsMenuIconFg'] ?? fb.dialogsMenuIconFg,
      dialogsMenuIconFgOver: m['dialogsMenuIconFgOver'] ?? fb.dialogsMenuIconFgOver,
      dialogsChatIconFg: m['dialogsChatIconFg'] ?? fb.dialogsChatIconFg,
      dialogsChatIconFgOver: m['dialogsChatIconFgOver'] ?? fb.dialogsChatIconFgOver,
      dialogsDateFgOver: m['dialogsDateFgOver'] ?? fb.dialogsDateFgOver,
      dialogsTextFgServiceOver: m['dialogsTextFgServiceOver'] ?? fb.dialogsTextFgServiceOver,
      dialogsDraftFgOver: m['dialogsDraftFgOver'] ?? fb.dialogsDraftFgOver,
      dialogsVerifiedIconBgOver: m['dialogsVerifiedIconBgOver'] ?? fb.dialogsVerifiedIconBgOver,
      dialogsVerifiedIconFgOver: m['dialogsVerifiedIconFgOver'] ?? fb.dialogsVerifiedIconFgOver,
      dialogsSendingIconFgOver: m['dialogsSendingIconFgOver'] ?? fb.dialogsSendingIconFgOver,
      dialogsSentIconFgOver: m['dialogsSentIconFgOver'] ?? fb.dialogsSentIconFgOver,
      dialogsUnreadBgOver: m['dialogsUnreadBgOver'] ?? fb.dialogsUnreadBgOver,
      dialogsUnreadBgMutedOver: m['dialogsUnreadBgMutedOver'] ?? fb.dialogsUnreadBgMutedOver,
      dialogsUnreadFgOver: m['dialogsUnreadFgOver'] ?? fb.dialogsUnreadFgOver,
      dialogsArchiveFgOver: m['dialogsArchiveFgOver'] ?? fb.dialogsArchiveFgOver,
      dialogsScamFg: m['dialogsScamFg'] ?? fb.dialogsScamFg,
      dialogsScamFgOver: m['dialogsScamFgOver'] ?? fb.dialogsScamFgOver,
      dialogsChatIconFgActive: m['dialogsChatIconFgActive'] ?? fb.dialogsChatIconFgActive,
      dialogsDateFgActive: m['dialogsDateFgActive'] ?? fb.dialogsDateFgActive,
      dialogsTextFgServiceActive: m['dialogsTextFgServiceActive'] ?? fb.dialogsTextFgServiceActive,
      dialogsDraftFgActive: m['dialogsDraftFgActive'] ?? fb.dialogsDraftFgActive,
      dialogsVerifiedIconBgActive: m['dialogsVerifiedIconBgActive'] ?? fb.dialogsVerifiedIconBgActive,
      dialogsVerifiedIconFgActive: m['dialogsVerifiedIconFgActive'] ?? fb.dialogsVerifiedIconFgActive,
      dialogsSendingIconFgActive: m['dialogsSendingIconFgActive'] ?? fb.dialogsSendingIconFgActive,
      dialogsSentIconFgActive: m['dialogsSentIconFgActive'] ?? fb.dialogsSentIconFgActive,
      dialogsScamFgActive: m['dialogsScamFgActive'] ?? fb.dialogsScamFgActive,
      dialogsMentionIconFg: m['dialogsMentionIconFg'] ?? fb.dialogsMentionIconFg,
      dialogsReactionIconFg: m['dialogsReactionIconFg'] ?? fb.dialogsReactionIconFg,
      dialogsPollIconFg: m['dialogsPollIconFg'] ?? fb.dialogsPollIconFg,
      searchedBarBg: m['searchedBarBg'] ?? fb.searchedBarBg,
      searchedBarFg: m['searchedBarFg'] ?? fb.searchedBarFg,
      emojiPanBg: m['emojiPanBg'] ?? fb.emojiPanBg,
      emojiPanCategories: m['emojiPanCategories'] ?? fb.emojiPanCategories,
      emojiPanHeaderFg: m['emojiPanHeaderFg'] ?? fb.emojiPanHeaderFg,
      emojiPanHeaderBg: m['emojiPanHeaderBg'] ?? fb.emojiPanHeaderBg,
      emojiIconFg: m['emojiIconFg'] ?? fb.emojiIconFg,
      emojiSubIconFgActive: m['emojiSubIconFgActive'] ?? fb.emojiSubIconFgActive,
      stickerPanDeleteBg: m['stickerPanDeleteBg'] ?? fb.stickerPanDeleteBg,
      stickerPanDeleteFg: m['stickerPanDeleteFg'] ?? fb.stickerPanDeleteFg,
      stickerPreviewBg: m['stickerPreviewBg'] ?? fb.stickerPreviewBg,
      stickerPanPremium1: m['stickerPanPremium1'] ?? fb.stickerPanPremium1,
      stickerPanPremium2: m['stickerPanPremium2'] ?? fb.stickerPanPremium2,
      historyTextInFgSelected: m['historyTextInFgSelected'] ?? fb.historyTextInFgSelected,
      historyTextOutFgSelected: m['historyTextOutFgSelected'] ?? fb.historyTextOutFgSelected,
      historyLinkInFg: m['historyLinkInFg'] ?? fb.historyLinkInFg,
      historyLinkInFgSelected: m['historyLinkInFgSelected'] ?? fb.historyLinkInFgSelected,
      historyLinkOutFg: m['historyLinkOutFg'] ?? fb.historyLinkOutFg,
      historyLinkOutFgSelected: m['historyLinkOutFgSelected'] ?? fb.historyLinkOutFgSelected,
      historyFileNameInFg: m['historyFileNameInFg'] ?? fb.historyFileNameInFg,
      historyFileNameInFgSelected: m['historyFileNameInFgSelected'] ?? fb.historyFileNameInFgSelected,
      historyFileNameOutFg: m['historyFileNameOutFg'] ?? fb.historyFileNameOutFg,
      historyFileNameOutFgSelected: m['historyFileNameOutFgSelected'] ?? fb.historyFileNameOutFgSelected,
      historyOutIconFgSelected: m['historyOutIconFgSelected'] ?? fb.historyOutIconFgSelected,
      historyCallArrowInFg: m['historyCallArrowInFg'] ?? fb.historyCallArrowInFg,
      historyCallArrowInFgSelected: m['historyCallArrowInFgSelected'] ?? fb.historyCallArrowInFgSelected,
      historyCallArrowMissedInFg: m['historyCallArrowMissedInFg'] ?? fb.historyCallArrowMissedInFg,
      historyCallArrowMissedInFgSelected: m['historyCallArrowMissedInFgSelected'] ?? fb.historyCallArrowMissedInFgSelected,
      historyCallArrowOutFg: m['historyCallArrowOutFg'] ?? fb.historyCallArrowOutFg,
      historyCallArrowOutFgSelected: m['historyCallArrowOutFgSelected'] ?? fb.historyCallArrowOutFgSelected,
      historyUnreadBarBorder: m['historyUnreadBarBorder'] ?? fb.historyUnreadBarBorder,
      historyForwardChooseBg: m['historyForwardChooseBg'] ?? fb.historyForwardChooseBg,
      historyForwardChooseFg: m['historyForwardChooseFg'] ?? fb.historyForwardChooseFg,
      historyPeerUserpicFg: m['historyPeerUserpicFg'] ?? fb.historyPeerUserpicFg,
      historyPeerSavedMessagesBg: m['historyPeerSavedMessagesBg'] ?? fb.historyPeerSavedMessagesBg,
      historyPeerArchiveUserpicBg: m['historyPeerArchiveUserpicBg'] ?? fb.historyPeerArchiveUserpicBg,
      historyPeerSavedMessagesBg2: m['historyPeerSavedMessagesBg2'] ?? fb.historyPeerSavedMessagesBg2,
      settingsIconFg: m['settingsIconFg'] ?? fb.settingsIconFg,
      msgInServiceFgSelected: m['msgInServiceFgSelected'] ?? fb.msgInServiceFgSelected,
      msgOutServiceFgSelected: m['msgOutServiceFgSelected'] ?? fb.msgOutServiceFgSelected,
      msgInShadowSelected: m['msgInShadowSelected'] ?? fb.msgInShadowSelected,
      msgOutShadowSelected: m['msgOutShadowSelected'] ?? fb.msgOutShadowSelected,
      msgInDateFgSelected: m['msgInDateFgSelected'] ?? fb.msgInDateFgSelected,
      msgOutDateFgSelected: m['msgOutDateFgSelected'] ?? fb.msgOutDateFgSelected,
      msgInReplyBarSelColor: m['msgInReplyBarSelColor'] ?? fb.msgInReplyBarSelColor,
      msgOutReplyBarSelColor: m['msgOutReplyBarSelColor'] ?? fb.msgOutReplyBarSelColor,
      msgImgReplyBarColor: m['msgImgReplyBarColor'] ?? fb.msgImgReplyBarColor,
      msgInMonoFgSelected: m['msgInMonoFgSelected'] ?? fb.msgInMonoFgSelected,
      msgOutMonoFgSelected: m['msgOutMonoFgSelected'] ?? fb.msgOutMonoFgSelected,
      msgDateImgFg: m['msgDateImgFg'] ?? fb.msgDateImgFg,
      msgFileThumbLinkInFg: m['msgFileThumbLinkInFg'] ?? fb.msgFileThumbLinkInFg,
      msgFileThumbLinkInFgSelected: m['msgFileThumbLinkInFgSelected'] ?? fb.msgFileThumbLinkInFgSelected,
      msgFileThumbLinkOutFg: m['msgFileThumbLinkOutFg'] ?? fb.msgFileThumbLinkOutFg,
      msgFileThumbLinkOutFgSelected: m['msgFileThumbLinkOutFgSelected'] ?? fb.msgFileThumbLinkOutFgSelected,
      msgFileInBgOver: m['msgFileInBgOver'] ?? fb.msgFileInBgOver,
      msgFileInBgSelected: m['msgFileInBgSelected'] ?? fb.msgFileInBgSelected,
      msgFileOutBgSelected: m['msgFileOutBgSelected'] ?? fb.msgFileOutBgSelected,
      historyFileInIconFg: m['historyFileInIconFg'] ?? fb.historyFileInIconFg,
      historyFileInIconFgSelected: m['historyFileInIconFgSelected'] ?? fb.historyFileInIconFgSelected,
      historyFileInRadialFg: m['historyFileInRadialFg'] ?? fb.historyFileInRadialFg,
      historyFileInRadialFgSelected: m['historyFileInRadialFgSelected'] ?? fb.historyFileInRadialFgSelected,
      historyFileOutIconFg: m['historyFileOutIconFg'] ?? fb.historyFileOutIconFg,
      historyFileOutIconFgSelected: m['historyFileOutIconFgSelected'] ?? fb.historyFileOutIconFgSelected,
      historyFileOutRadialFg: m['historyFileOutRadialFg'] ?? fb.historyFileOutRadialFg,
      historyFileOutRadialFgSelected: m['historyFileOutRadialFgSelected'] ?? fb.historyFileOutRadialFgSelected,
      historyFileThumbIconFg: m['historyFileThumbIconFg'] ?? fb.historyFileThumbIconFg,
      historyFileThumbIconFgSelected: m['historyFileThumbIconFgSelected'] ?? fb.historyFileThumbIconFgSelected,
      historyFileThumbRadialFg: m['historyFileThumbRadialFg'] ?? fb.historyFileThumbRadialFg,
      historyFileThumbRadialFgSelected: m['historyFileThumbRadialFgSelected'] ?? fb.historyFileThumbRadialFgSelected,
      historyVideoMessageProgressFg: m['historyVideoMessageProgressFg'] ?? fb.historyVideoMessageProgressFg,
      msgWaveformInActiveSelected: m['msgWaveformInActiveSelected'] ?? fb.msgWaveformInActiveSelected,
      msgWaveformInInactiveSelected: m['msgWaveformInInactiveSelected'] ?? fb.msgWaveformInInactiveSelected,
      msgWaveformOutActiveSelected: m['msgWaveformOutActiveSelected'] ?? fb.msgWaveformOutActiveSelected,
      msgWaveformOutInactiveSelected: m['msgWaveformOutInactiveSelected'] ?? fb.msgWaveformOutInactiveSelected,
      msgBotKbOverBgAdd: m['msgBotKbOverBgAdd'] ?? fb.msgBotKbOverBgAdd,
      msgBotKbIconFg: m['msgBotKbIconFg'] ?? fb.msgBotKbIconFg,
      msgBotKbRippleBg: m['msgBotKbRippleBg'] ?? fb.msgBotKbRippleBg,
      mediaInFg: m['mediaInFg'] ?? fb.mediaInFg,
      mediaInFgSelected: m['mediaInFgSelected'] ?? fb.mediaInFgSelected,
      mediaOutFg: m['mediaOutFg'] ?? fb.mediaOutFg,
      mediaOutFgSelected: m['mediaOutFgSelected'] ?? fb.mediaOutFgSelected,
      youtubePlayIconBg: m['youtubePlayIconBg'] ?? fb.youtubePlayIconBg,
      youtubePlayIconFg: m['youtubePlayIconFg'] ?? fb.youtubePlayIconFg,
      videoPlayIconBg: m['videoPlayIconBg'] ?? fb.videoPlayIconBg,
      videoPlayIconFg: m['videoPlayIconFg'] ?? fb.videoPlayIconFg,
      toastBg: m['toastBg'] ?? fb.toastBg,
      toastFg: m['toastFg'] ?? fb.toastFg,
      historyToDownBgRipple: m['historyToDownBgRipple'] ?? fb.historyToDownBgRipple,
      historyToDownFgOver: m['historyToDownFgOver'] ?? fb.historyToDownFgOver,
      historyToDownShadow: m['historyToDownShadow'] ?? fb.historyToDownShadow,
      historyComposeAreaFgService: m['historyComposeAreaFgService'] ?? fb.historyComposeAreaFgService,
      historySendIconFgOver: m['historySendIconFgOver'] ?? fb.historySendIconFgOver,
      historyReplyCancelFg: m['historyReplyCancelFg'] ?? fb.historyReplyCancelFg,
      historyReplyCancelFgOver: m['historyReplyCancelFgOver'] ?? fb.historyReplyCancelFgOver,
      mapPointDrop: m['mapPointDrop'] ?? fb.mapPointDrop,
      mapPointDot: m['mapPointDot'] ?? fb.mapPointDot,
      overviewCheckBgActive: m['overviewCheckBgActive'] ?? fb.overviewCheckBgActive,
      overviewCheckBorder: m['overviewCheckBorder'] ?? fb.overviewCheckBorder,
      overviewCheckFgActive: m['overviewCheckFgActive'] ?? fb.overviewCheckFgActive,
      overviewPhotoSelectOverlay: m['overviewPhotoSelectOverlay'] ?? fb.overviewPhotoSelectOverlay,
      notificationsBoxMonitorFg: m['notificationsBoxMonitorFg'] ?? fb.notificationsBoxMonitorFg,
      notificationsBoxScreenBg: m['notificationsBoxScreenBg'] ?? fb.notificationsBoxScreenBg,
      notificationSampleUserpicFg: m['notificationSampleUserpicFg'] ?? fb.notificationSampleUserpicFg,
      notificationSampleCloseFg: m['notificationSampleCloseFg'] ?? fb.notificationSampleCloseFg,
      notificationSampleTextFg: m['notificationSampleTextFg'] ?? fb.notificationSampleTextFg,
      notificationSampleNameFg: m['notificationSampleNameFg'] ?? fb.notificationSampleNameFg,
      mainMenuCloudFg: m['mainMenuCloudFg'] ?? fb.mainMenuCloudFg,
      mainMenuCloudBg: m['mainMenuCloudBg'] ?? fb.mainMenuCloudBg,
      mediaPlayerBg: m['mediaPlayerBg'] ?? fb.mediaPlayerBg,
      mediaPlayerActiveFg: m['mediaPlayerActiveFg'] ?? fb.mediaPlayerActiveFg,
      mediaPlayerInactiveFg: m['mediaPlayerInactiveFg'] ?? fb.mediaPlayerInactiveFg,
      mediaPlayerDisabledFg: m['mediaPlayerDisabledFg'] ?? fb.mediaPlayerDisabledFg,
      mediaviewFileBg: m['mediaviewFileBg'] ?? fb.mediaviewFileBg,
      mediaviewFileNameFg: m['mediaviewFileNameFg'] ?? fb.mediaviewFileNameFg,
      mediaviewFileSizeFg: m['mediaviewFileSizeFg'] ?? fb.mediaviewFileSizeFg,
      mediaviewFileExtFg: m['mediaviewFileExtFg'] ?? fb.mediaviewFileExtFg,
      mediaviewMenuBg: m['mediaviewMenuBg'] ?? fb.mediaviewMenuBg,
      mediaviewMenuBgOver: m['mediaviewMenuBgOver'] ?? fb.mediaviewMenuBgOver,
      mediaviewMenuBgRipple: m['mediaviewMenuBgRipple'] ?? fb.mediaviewMenuBgRipple,
      mediaviewMenuFg: m['mediaviewMenuFg'] ?? fb.mediaviewMenuFg,
      mediaviewVideoBg: m['mediaviewVideoBg'] ?? fb.mediaviewVideoBg,
      mediaviewCaptionFg: m['mediaviewCaptionFg'] ?? fb.mediaviewCaptionFg,
      mediaviewTextLinkFg: m['mediaviewTextLinkFg'] ?? fb.mediaviewTextLinkFg,
      mediaviewSaveMsgBg: m['mediaviewSaveMsgBg'] ?? fb.mediaviewSaveMsgBg,
      mediaviewSaveMsgFg: m['mediaviewSaveMsgFg'] ?? fb.mediaviewSaveMsgFg,
      mediaviewPlaybackInactiveOver: m['mediaviewPlaybackInactiveOver'] ?? fb.mediaviewPlaybackInactiveOver,
      mediaviewPlaybackProgressFg: m['mediaviewPlaybackProgressFg'] ?? fb.mediaviewPlaybackProgressFg,
      mediaviewPlaybackIconFg: m['mediaviewPlaybackIconFg'] ?? fb.mediaviewPlaybackIconFg,
      mediaviewPlaybackIconFgOver: m['mediaviewPlaybackIconFgOver'] ?? fb.mediaviewPlaybackIconFgOver,
      mediaviewPlaybackIconRipple: m['mediaviewPlaybackIconRipple'] ?? fb.mediaviewPlaybackIconRipple,
      mediaviewPipControlsFg: m['mediaviewPipControlsFg'] ?? fb.mediaviewPipControlsFg,
      mediaviewPipControlsFgOver: m['mediaviewPipControlsFgOver'] ?? fb.mediaviewPipControlsFgOver,
      mediaviewPipPlaybackActive: m['mediaviewPipPlaybackActive'] ?? fb.mediaviewPipPlaybackActive,
      mediaviewPipPlaybackInactive: m['mediaviewPipPlaybackInactive'] ?? fb.mediaviewPipPlaybackInactive,
      mediaviewTransparentBg: m['mediaviewTransparentBg'] ?? fb.mediaviewTransparentBg,
      mediaviewTransparentFg: m['mediaviewTransparentFg'] ?? fb.mediaviewTransparentFg,
      notificationBg: m['notificationBg'] ?? fb.notificationBg,
      callBg: m['callBg'] ?? fb.callBg,
      callBgOpaque: m['callBgOpaque'] ?? fb.callBgOpaque,
      callBgButton: m['callBgButton'] ?? fb.callBgButton,
      callNameFg: m['callNameFg'] ?? fb.callNameFg,
      callStatusFg: m['callStatusFg'] ?? fb.callStatusFg,
      callIconBg: m['callIconBg'] ?? fb.callIconBg,
      callIconBgActive: m['callIconBgActive'] ?? fb.callIconBgActive,
      callIconFgActive: m['callIconFgActive'] ?? fb.callIconFgActive,
      callIconActiveRipple: m['callIconActiveRipple'] ?? fb.callIconActiveRipple,
      callAnswerBg: m['callAnswerBg'] ?? fb.callAnswerBg,
      callAnswerRipple: m['callAnswerRipple'] ?? fb.callAnswerRipple,
      callAnswerBgOuter: m['callAnswerBgOuter'] ?? fb.callAnswerBgOuter,
      callHangupBg: m['callHangupBg'] ?? fb.callHangupBg,
      callHangupRipple: m['callHangupRipple'] ?? fb.callHangupRipple,
      callMuteRipple: m['callMuteRipple'] ?? fb.callMuteRipple,
      callBarBg: m['callBarBg'] ?? fb.callBarBg,
      callBarMuteRipple: m['callBarMuteRipple'] ?? fb.callBarMuteRipple,
      callBarBgMuted: m['callBarBgMuted'] ?? fb.callBarBgMuted,
      callBarFg: m['callBarFg'] ?? fb.callBarFg,
      importantTooltipFg: m['importantTooltipFg'] ?? fb.importantTooltipFg,
      importantTooltipFgLink: m['importantTooltipFgLink'] ?? fb.importantTooltipFgLink,
      premiumButtonFg: m['premiumButtonFg'] ?? fb.premiumButtonFg,
      premiumIconBg3: m['premiumIconBg3'] ?? fb.premiumIconBg3,
      groupCallBg: m['groupCallBg'] ?? fb.groupCallBg,
      groupCallActiveFg: m['groupCallActiveFg'] ?? fb.groupCallActiveFg,
      groupCallMembersBg: m['groupCallMembersBg'] ?? fb.groupCallMembersBg,
      groupCallMembersBgOver: m['groupCallMembersBgOver'] ?? fb.groupCallMembersBgOver,
      groupCallMembersBgRipple: m['groupCallMembersBgRipple'] ?? fb.groupCallMembersBgRipple,
      groupCallMembersFg: m['groupCallMembersFg'] ?? fb.groupCallMembersFg,
      groupCallMemberActiveIcon: m['groupCallMemberActiveIcon'] ?? fb.groupCallMemberActiveIcon,
      groupCallMemberActiveStatus: m['groupCallMemberActiveStatus'] ?? fb.groupCallMemberActiveStatus,
      groupCallMemberInactiveIcon: m['groupCallMemberInactiveIcon'] ?? fb.groupCallMemberInactiveIcon,
      groupCallMemberInactiveStatus: m['groupCallMemberInactiveStatus'] ?? fb.groupCallMemberInactiveStatus,
      groupCallMemberMutedIcon: m['groupCallMemberMutedIcon'] ?? fb.groupCallMemberMutedIcon,
      groupCallMemberNotJoinedStatus: m['groupCallMemberNotJoinedStatus'] ?? fb.groupCallMemberNotJoinedStatus,
      groupCallIconFg: m['groupCallIconFg'] ?? fb.groupCallIconFg,
      groupCallLive1: m['groupCallLive1'] ?? fb.groupCallLive1,
      groupCallLive2: m['groupCallLive2'] ?? fb.groupCallLive2,
      groupCallMuted1: m['groupCallMuted1'] ?? fb.groupCallMuted1,
      groupCallMuted2: m['groupCallMuted2'] ?? fb.groupCallMuted2,
      groupCallForceMutedBar1: m['groupCallForceMutedBar1'] ?? fb.groupCallForceMutedBar1,
      groupCallForceMutedBar2: m['groupCallForceMutedBar2'] ?? fb.groupCallForceMutedBar2,
      groupCallForceMutedBar3: m['groupCallForceMutedBar3'] ?? fb.groupCallForceMutedBar3,
      groupCallForceMuted1: m['groupCallForceMuted1'] ?? fb.groupCallForceMuted1,
      groupCallForceMuted2: m['groupCallForceMuted2'] ?? fb.groupCallForceMuted2,
      groupCallForceMuted3: m['groupCallForceMuted3'] ?? fb.groupCallForceMuted3,
      groupCallMenuBg: m['groupCallMenuBg'] ?? fb.groupCallMenuBg,
      groupCallMenuBgOver: m['groupCallMenuBgOver'] ?? fb.groupCallMenuBgOver,
      groupCallMenuBgRipple: m['groupCallMenuBgRipple'] ?? fb.groupCallMenuBgRipple,
      groupCallLeaveBg: m['groupCallLeaveBg'] ?? fb.groupCallLeaveBg,
      groupCallLeaveBgRipple: m['groupCallLeaveBgRipple'] ?? fb.groupCallLeaveBgRipple,
      groupCallVideoTextFg: m['groupCallVideoTextFg'] ?? fb.groupCallVideoTextFg,
      groupCallVideoSubTextFg: m['groupCallVideoSubTextFg'] ?? fb.groupCallVideoSubTextFg,
    );

// ── §25.10 Theme Caching ──

class ThemeCacheData {
  final TelegramPalette palette;
  final Uint8List? backgroundImage;
  final bool tileBg;
  final int paletteChecksum;
  final int contentChecksum;
  final CloudThemeMeta? cloudMeta;

  const ThemeCacheData({
    required this.palette,
    this.backgroundImage,
    this.tileBg = false,
    required this.paletteChecksum,
    required this.contentChecksum,
    this.cloudMeta,
  });
}

ThemeCacheData buildThemeCache(Uint8List themeFileBytes, ThemeFileData parsed) {
  final contentChecksum = getCrc32(themeFileBytes);

  int paletteChecksum = 0;
  if (_looksLikeZip(themeFileBytes)) {
    try {
      final archive = ZipDecoder().decodeBytes(themeFileBytes);
      for (final file in archive) {
        final name = file.name.toLowerCase();
        if (name == 'colors.tdesktop-theme' || name == 'colors.tdesktop-palette') {
          paletteChecksum = getCrc32(file.content as List<int>);
          break;
        }
      }
    } catch (_) {
      paletteChecksum = contentChecksum;
    }
  } else {
    paletteChecksum = contentChecksum;
  }

  return ThemeCacheData(
    palette: parsed.palette,
    backgroundImage: parsed.backgroundImage,
    tileBg: parsed.backgroundTiled,
    paletteChecksum: paletteChecksum,
    contentChecksum: contentChecksum,
    cloudMeta: parsed.cloudMeta,
  );
}

bool validateThemeCache(ThemeCacheData cache, Uint8List themeFileBytes) {
  final contentChecksum = getCrc32(themeFileBytes);
  if (contentChecksum != cache.contentChecksum) return false;

  if (_looksLikeZip(themeFileBytes)) {
    try {
      final archive = ZipDecoder().decodeBytes(themeFileBytes);
      for (final file in archive) {
        final name = file.name.toLowerCase();
        if (name == 'colors.tdesktop-theme' || name == 'colors.tdesktop-palette') {
          return getCrc32(file.content as List<int>) == cache.paletteChecksum;
        }
      }
    } catch (_) {
      return false;
    }
  }
  return true;
}

void saveThemeCache(String configDir, ThemeCacheData cache) {
  final colorMap = paletteToMap(cache.palette);
  final hexColors = <String, String>{};
  for (final entry in colorMap.entries) {
    hexColors[entry.key] = _colorToHex(entry.value);
  }

  final json = <String, dynamic>{
    'paletteChecksum': cache.paletteChecksum,
    'contentChecksum': cache.contentChecksum,
    'tileBg': cache.tileBg,
    'colors': hexColors,
  };
  if (cache.cloudMeta != null) {
    json['cloudMetaId'] = cache.cloudMeta!.id;
    json['cloudMetaHash'] = cache.cloudMeta!.accessHash;
  }

  try {
    File('$configDir/theme_cache.json').writeAsStringSync(jsonEncode(json));
  } catch (_) {}

  if (cache.backgroundImage != null) {
    try {
      File('$configDir/theme_cache_bg.dat').writeAsBytesSync(cache.backgroundImage!);
    } catch (_) {}
  } else {
    try {
      final f = File('$configDir/theme_cache_bg.dat');
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }
}

ThemeCacheData? loadThemeCache(String configDir) {
  try {
    final cacheFile = File('$configDir/theme_cache.json');
    if (!cacheFile.existsSync()) return null;

    final data = jsonDecode(cacheFile.readAsStringSync()) as Map<String, dynamic>;
    final paletteChecksum = data['paletteChecksum'] as int? ?? 0;
    final contentChecksum = data['contentChecksum'] as int? ?? 0;
    final tileBg = data['tileBg'] as bool? ?? false;
    final colorsJson = data['colors'] as Map<String, dynamic>?;
    if (colorsJson == null) return null;

    final colorMap = <String, Color>{};
    for (final entry in colorsJson.entries) {
      final c = _parseHexColor(entry.value as String);
      if (c != null) colorMap[entry.key] = c;
    }

    final fallback = TelegramPalette.dayBlue;
    final merged = Map<String, Color>.from(paletteToMap(fallback))..addAll(colorMap);
    final palette = paletteFromMap(merged, fallback);

    Uint8List? bgBytes;
    final bgFile = File('$configDir/theme_cache_bg.dat');
    if (bgFile.existsSync()) bgBytes = bgFile.readAsBytesSync();

    CloudThemeMeta? cloudMeta;
    final cmId = data['cloudMetaId'] as int?;
    final cmHash = data['cloudMetaHash'] as int?;
    if (cmId != null && cmHash != null) {
      cloudMeta = CloudThemeMeta(id: cmId, accessHash: cmHash);
    }

    return ThemeCacheData(
      palette: palette,
      backgroundImage: bgBytes,
      tileBg: tileBg,
      paletteChecksum: paletteChecksum,
      contentChecksum: contentChecksum,
      cloudMeta: cloudMeta,
    );
  } catch (_) {
    return null;
  }
}

void clearThemeCache(String configDir) {
  try {
    final f = File('$configDir/theme_cache.json');
    if (f.existsSync()) f.deleteSync();
  } catch (_) {}
  try {
    final f = File('$configDir/theme_cache_bg.dat');
    if (f.existsSync()) f.deleteSync();
  } catch (_) {}
}

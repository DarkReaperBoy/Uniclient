import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../theme/telegram_palette.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../l10n/strings.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';

enum _DeviceType {
  windows,
  mac,
  ubuntu,
  linux,
  iphone,
  ipad,
  android,
  web,
  chrome,
  edge,
  firefox,
  safari,
  other,
}

class _DeviceInfo {
  final _DeviceType type;
  final String iconAsset;

  const _DeviceInfo(this.type, this.iconAsset);
}

({Color top, Color bottom}) _gradientForType(_DeviceType type, TelegramPalette palette) {
  switch (type) {
    case _DeviceType.windows:
    case _DeviceType.mac:
    case _DeviceType.other:
      return (top: palette.historyPeer4UserpicBg, bottom: palette.historyPeer4UserpicBg2);
    case _DeviceType.ubuntu:
      return (top: palette.historyPeer8UserpicBg, bottom: palette.historyPeer8UserpicBg2);
    case _DeviceType.linux:
      return (top: palette.historyPeer5UserpicBg, bottom: palette.historyPeer5UserpicBg2);
    case _DeviceType.iphone:
    case _DeviceType.ipad:
      return (top: palette.historyPeer7UserpicBg, bottom: palette.historyPeer7UserpicBg2);
    case _DeviceType.android:
      return (top: palette.historyPeer2UserpicBg, bottom: palette.historyPeer2UserpicBg2);
    case _DeviceType.web:
    case _DeviceType.chrome:
    case _DeviceType.edge:
    case _DeviceType.firefox:
    case _DeviceType.safari:
      return (top: palette.historyPeer6UserpicBg, bottom: palette.historyPeer6UserpicBg2);
  }
}

const _kDeviceIconDir = 'assets/icons/devices';

String _iconPath(_DeviceType type) {
  switch (type) {
    case _DeviceType.windows: return '$_kDeviceIconDir/device_desktop_win.png';
    case _DeviceType.mac: return '$_kDeviceIconDir/device_desktop_mac.png';
    case _DeviceType.ubuntu: return '$_kDeviceIconDir/device_linux_ubuntu.png';
    case _DeviceType.linux: return '$_kDeviceIconDir/device_linux.png';
    case _DeviceType.iphone: return '$_kDeviceIconDir/device_phone_ios.png';
    case _DeviceType.ipad: return '$_kDeviceIconDir/device_tablet_ios.png';
    case _DeviceType.android: return '$_kDeviceIconDir/device_phone_android.png';
    case _DeviceType.web: return '$_kDeviceIconDir/device_web_other.png';
    case _DeviceType.chrome: return '$_kDeviceIconDir/device_web_chrome.png';
    case _DeviceType.edge: return '$_kDeviceIconDir/device_web_edge.png';
    case _DeviceType.firefox: return '$_kDeviceIconDir/device_web_firefox.png';
    case _DeviceType.safari: return '$_kDeviceIconDir/device_web_safari.png';
    case _DeviceType.other: return '$_kDeviceIconDir/device_other.png';
  }
}

String? _lottiePath(_DeviceType type) {
  const dir = 'assets/animations/devices';
  switch (type) {
    case _DeviceType.windows: return '$dir/device_desktop_win.lottie';
    case _DeviceType.mac: return '$dir/device_desktop_mac.lottie';
    case _DeviceType.ubuntu: return '$dir/device_linux_ubuntu.lottie';
    case _DeviceType.linux: return '$dir/device_linux.lottie';
    case _DeviceType.iphone: return '$dir/device_phone_ios.lottie';
    case _DeviceType.ipad: return '$dir/device_tablet_ios.lottie';
    case _DeviceType.android: return '$dir/device_phone_android.lottie';
    case _DeviceType.chrome: return '$dir/device_web_chrome.lottie';
    case _DeviceType.edge: return '$dir/device_web_edge.lottie';
    case _DeviceType.firefox: return '$dir/device_web_firefox.lottie';
    case _DeviceType.safari: return '$dir/device_web_safari.lottie';
    case _DeviceType.web:
    case _DeviceType.other:
      return null;
  }
}

String _bigIconPath(_DeviceType type) {
  switch (type) {
    case _DeviceType.web: return '$_kDeviceIconDir/device_web_other_large.png';
    case _DeviceType.other: return '$_kDeviceIconDir/device_other_large.png';
    default: return _iconPath(type);
  }
}

_DeviceInfo _classifyDevice(String device, String platform, String appName, {int? apiId, String? system}) {
  final d = device.toLowerCase();
  final p = (system ?? '').toLowerCase();
  final s = platform.toLowerCase();

  const kDesktop = {2040, 17349, 611335};
  const kMac = {2834};
  const kAndroid = {5, 6, 24, 1026, 1083, 2458, 2521, 21724};
  const kiOS = {1, 7, 10840, 16352};
  const kWeb = {2496, 739222, 1025907};

  _DeviceInfo make(_DeviceType t) => _DeviceInfo(t, _iconPath(t));

  _DeviceInfo? detectBrowser() {
    if (d.contains('edg/') || d.contains('edgios/') || d.contains('edga/')) {
      return make(_DeviceType.edge);
    } else if (d.contains('chrome')) {
      return make(_DeviceType.chrome);
    } else if (d.contains('safari')) {
      return make(_DeviceType.safari);
    } else if (d.contains('firefox')) {
      return make(_DeviceType.firefox);
    }
    return null;
  }

  _DeviceInfo? detectDesktop() {
    if (p.contains('windows') || s.contains('windows')) {
      return make(_DeviceType.windows);
    } else if (p.contains('macos') || s.contains('macos')) {
      return make(_DeviceType.mac);
    } else if (p.contains('ubuntu') || s.contains('ubuntu') || p.contains('unity') || s.contains('unity')) {
      return make(_DeviceType.ubuntu);
    } else if (p.contains('linux') || s.contains('linux')) {
      return make(_DeviceType.linux);
    }
    return null;
  }

  if (apiId != null) {
    if (kAndroid.contains(apiId)) {
      return make(_DeviceType.android);
    } else if (kDesktop.contains(apiId)) {
      return detectDesktop() ?? make(_DeviceType.linux);
    } else if (kMac.contains(apiId)) {
      return make(_DeviceType.mac);
    } else if (kWeb.contains(apiId)) {
      return detectBrowser() ?? make(_DeviceType.web);
    }
  }

  if (d.contains('chromebook')) {
    return make(_DeviceType.other);
  }
  final browser = detectBrowser();
  if (browser != null) return browser;
  if (d.contains('iphone')) {
    return make(_DeviceType.iphone);
  }
  if (d.contains('ipad')) {
    return make(_DeviceType.ipad);
  }
  if (apiId != null && kiOS.contains(apiId)) {
    return make(_DeviceType.iphone);
  }
  final desktop = detectDesktop();
  if (desktop != null) return desktop;
  if (p.contains('android') || s.contains('android')) {
    return make(_DeviceType.android);
  }
  if (p.contains('ios') || s.contains('ios')) {
    return make(_DeviceType.iphone);
  }
  return make(_DeviceType.other);
}

// Port of Core::FormatVersionDisplay (AyuGram core/changelogs.cpp:150-156):
// packs an integer build into a dotted version — 4016008 → "4.16.8",
// 4016000 → "4.16" (the patch segment is dropped when zero).
String _formatVersionDisplay(int version) {
  final major = version ~/ 1000000;
  final minor = (version % 1000000) ~/ 1000;
  final patch = version % 1000;
  return patch != 0 ? '$major.$minor.$patch' : '$major.$minor';
}

// Port of AyuGram Api::ParseEntry's app name/version normalization
// (api/api_authorizations.cpp:36-57,75-77) — the single source for the
// "Application" string shown in both the session row and the info box.
// Desktop api_ids (2040 DesktopApiId / 611335 SnapApiId / 17349 TestApiId)
// force the name to "Telegram Desktop" (+ " (GitHub)" for the test id) and
// reformat an integer app_version via FormatVersionDisplay (e.g. 4016008 →
// 4.16.8); non-desktop sessions reduce the version to its parenthetical build
// segment ("10.2.0 (12345)" → "(12345)"). Returns the joined "AppName AppVer".
String _formatApplication(String appName, String appVersion, int? apiId) {
  const desktopApiId = 2040;
  const snapApiId = 611335;
  const testApiId = 17349;
  final isTest = apiId == testApiId;
  final isDesktop = apiId == desktopApiId || apiId == snapApiId || isTest;

  final name = isDesktop
      ? 'Telegram Desktop${isTest ? ' (GitHub)' : ''}'
      : appName;

  final String ver;
  if (isDesktop) {
    // Desktop versions arrive as a packed integer; reformat only when the whole
    // string parses back to that integer (matches AyuGram's version == number(verInt)).
    final verInt = int.tryParse(appVersion);
    ver = (verInt != null && appVersion == verInt.toString())
        ? _formatVersionDisplay(verInt)
        : appVersion;
  } else {
    final idx = appVersion.indexOf('(');
    ver = idx >= 0 ? appVersion.substring(idx) : appVersion;
  }

  return ver.isEmpty ? name : '$name $ver';
}

class ActiveSessionsScreen extends StatefulWidget {
  final bool embedded;
  const ActiveSessionsScreen({super.key, this.embedded = false});

  @override
  State<ActiveSessionsScreen> createState() => _ActiveSessionsScreenState();
}

class _ActiveSessionsScreenState extends State<ActiveSessionsScreen> {
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;
  Timer? _refreshTimer;
  StreamSubscription<ConnStateEvent>? _connSub;
  int _autoTerminateDays = 0;

  List<Map<String, dynamic>> _cachedOtherSessions = [];
  List<Map<String, dynamic>> _cachedIncompleteSessions = [];
  Map<String, _DeviceInfo> _cachedDeviceInfos = {};
  bool _loadingInFlight = false;

  @override
  void initState() {
    super.initState();
    _loadSessions();
    _loadAutoTerminateDays();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) => _loadSessions());
    final engine = context.read<EngineService>();
    _connSub = engine.onConnState.listen((event) {
      if (event.state == 'connected' && mounted) {
        _loadSessions();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _connSub?.cancel();
    super.dispose();
  }

  // Parse `last_active` (Go serializes it as an RFC 3339 `time.Time`,
  // base.go:577) into a real DateTime so newest-first ordering survives
  // timezone-offset variation in the wire format. A lexicographic string
  // compare silently mis-sorts e.g. "...Z" against "...+05:30".
  static DateTime _lastActive(Map<String, dynamic> s) {
    final raw = s['last_active'] as String? ?? '';
    return DateTime.tryParse(raw)?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  void _recomputeCachedLists() {
    final other = _sessions.where((s) => s['is_current'] != true && s['password_pending'] != true).toList();
    other.sort((a, b) => _lastActive(b).compareTo(_lastActive(a)));
    _cachedOtherSessions = other;

    final incomplete = _sessions.where((s) => s['password_pending'] == true).toList();
    incomplete.sort((a, b) => _lastActive(b).compareTo(_lastActive(a)));
    _cachedIncompleteSessions = incomplete;

    final infos = <String, _DeviceInfo>{};
    for (final s in _sessions) {
      final id = s['id'] as String? ?? '';
      if (id.isNotEmpty) {
        infos[id] = _classifyDevice(
          s['device'] as String? ?? '',
          s['platform'] as String? ?? '',
          s['app_name'] as String? ?? '',
          apiId: s['api_id'] as int?,
          system: s['system'] as String?,
        );
      }
    }
    _cachedDeviceInfos = infos;
  }

  _DeviceInfo _getDeviceInfo(Map<String, dynamic> session) {
    final id = session['id'] as String? ?? '';
    return _cachedDeviceInfos[id] ?? _classifyDevice(
      session['device'] as String? ?? '',
      session['platform'] as String? ?? '',
      session['app_name'] as String? ?? '',
      apiId: session['api_id'] as int?,
      system: session['system'] as String?,
    );
  }

  Future<void> _loadSessions() async {
    if (_loadingInFlight) return;
    _loadingInFlight = true;
    try {
      final engine = context.read<EngineService>();
      final appState = context.read<AppState>();
      final accountId = appState.activeAccountId;
      if (accountId.isEmpty) return;

      final sessions = await engine.getSessions(accountId);
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _loading = false;
        _recomputeCachedLists();
      });
    } finally {
      _loadingInFlight = false;
    }
  }

  Map<String, dynamic>? get _currentSession {
    for (final s in _sessions) {
      if (s['is_current'] == true) return s;
    }
    return null;
  }

  Future<void> _terminateSession(String sessionId) async {
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final ok = await engine.terminateSession(appState.activeAccountId, sessionId);
    if (!mounted) return;
    if (ok) {
      // Match AyuGram SessionsContent::terminateOne (settings_active_sessions
      // .cpp:857-867): remove the row from the local list and re-render
      // immediately via showData, instead of a full GetSessions round-trip
      // that makes the row linger until the network reply lands.
      setState(() {
        _sessions.removeWhere((s) => (s['id'] as String? ?? '') == sessionId);
        _recomputeCachedLists();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to terminate session')),
      );
    }
  }

  Future<void> _terminateAllOther() async {
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final ok = await engine.terminateAllOtherSessions(appState.activeAccountId);
    if (!mounted) return;
    if (ok) {
      _loadSessions();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to terminate sessions')),
      );
    }
  }

  Future<void> _loadAutoTerminateDays() async {
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    if (accountId.isEmpty) return;
    final days = await engine.getSessionAutoTerminateDays(accountId);
    if (!mounted) return;
    setState(() => _autoTerminateDays = days);
  }

  static String _formatDaysLabel(int days) {
    if (days <= 0) return '';
    if (days > 25) {
      final months = (days ~/ 30).clamp(1, 999);
      return months == 1 ? '1 month' : '$months months';
    }
    final weeks = (days ~/ 7).clamp(1, 999);
    return weeks == 1 ? '1 week' : '$weeks weeks';
  }

  void _showAutoTerminateDialog() {
    final palette = context.palette;
    final bgColor = palette.boxBg;
    final textColor = palette.boxTextFg;
    final subtextColor = palette.windowSubTextFg;
    final accentColor = palette.windowBgActive;

    final options = [7, 30, 90, 180, 365];
    int selected = _autoTerminateDays;
    if (!options.contains(selected)) {
      var closest = options.first;
      for (final v in options) {
        if ((selected - v).abs() < (selected - closest).abs()) closest = v;
      }
      selected = closest;
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
                  child: Text(
                    TrStrings.lngSelfDestructSessionsTitle(),
                    style: TextStyle(
                      color: textColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 14),
                  child: Text(
                    TrStrings.lngSelfDestructSessionsDescription(),
                    style: TextStyle(color: subtextColor, fontSize: 13, height: 1.4),
                  ),
                ),
                for (final days in options)
                  InkWell(
                    onTap: () => setDialogState(() => selected = days),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: Radio<int>(
                              value: days,
                              groupValue: selected,
                              onChanged: (v) => setDialogState(() => selected = v!),
                              activeColor: accentColor,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Text(
                            _formatDaysLabel(days),
                            style: TextStyle(color: textColor, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          TrStrings.lngCancel(),
                          style: TextStyle(color: subtextColor),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          final engine = context.read<EngineService>();
                          final appState = context.read<AppState>();
                          final ok = await engine.setSessionAutoTerminateDays(
                            appState.activeAccountId, selected,
                          );
                          if (!mounted) return;
                          if (ok) {
                            // Reactive back-channel: reload the TTL the server
                            // actually accepted instead of optimistically
                            // trusting `selected`. Mirrors AyuGram binding the
                            // label to authorizations().updateTTL via rpl
                            // (settings_active_sessions.cpp:1003-1009).
                            await _loadAutoTerminateDays();
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Failed to update session termination period',
                                ),
                              ),
                            );
                          }
                        },
                        child: Text(
                          TrStrings.lngSettingsSave(),
                          style: TextStyle(color: accentColor, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Shared reset/terminate confirm box. Mirrors AyuGram's
  // SessionsContent::terminate → Ui::MakeConfirmBox: a titleless box with the
  // reset message, a red attention-styled "Terminate" confirm button
  // (st::attentionBoxButton / lng_settings_reset_button) and a Cancel button
  // (settings_active_sessions.cpp:829-848).
  void _showResetConfirmBox(String message, VoidCallback onConfirmed) {
    final palette = context.palette;
    final textColor = palette.boxTextFg;
    final accentColor = palette.windowBgActive;
    final attentionColor = palette.attentionButtonFg;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.boxBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Text(
          message,
          style: TextStyle(color: textColor, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              TrStrings.lngCancel(),
              style: TextStyle(color: accentColor),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: attentionColor),
            onPressed: () {
              Navigator.pop(ctx);
              onConfirmed();
            },
            child: Text(
              TrStrings.lngSettingsResetButton(),
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  void _showTerminateConfirmation(String sessionId) {
    _showResetConfirmBox(
      TrStrings.lngSettingsResetOneSure(),
      () => _terminateSession(sessionId),
    );
  }

  void _showTerminateAllConfirmation() {
    _showResetConfirmBox(
      TrStrings.lngSettingsResetSure(),
      _terminateAllOther,
    );
  }

  static int _isoWeekNumber(DateTime date) {
    final thursday = date.add(Duration(days: DateTime.thursday - date.weekday));
    final jan1 = DateTime(thursday.year, 1, 1);
    return ((thursday.difference(jan1).inDays) ~/ 7) + 1;
  }

  static const _weekdayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];

  String _formatActiveDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      // AyuGram renders local time via base::unixtime::parse
      // (api_authorizations.cpp:258-269); Dart's DateTime.parse yields a UTC
      // DateTime for any offset/Z string, so .toLocal() is required or every
      // timestamp is shifted by the user's UTC offset.
      final date = DateTime.parse(dateStr).toLocal();
      final now = DateTime.now();
      final nowDate = DateTime(now.year, now.month, now.day);
      final lastDate = DateTime(date.year, date.month, date.day);

      if (lastDate == nowDate) {
        return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      }
      if (date.year == now.year && _isoWeekNumber(date) == _isoWeekNumber(now)) {
        return _weekdayNames[date.weekday - 1];
      }
      return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    } catch (_) {
      return '';
    }
  }

  void _showSessionInfoBox(Map<String, dynamic> session) {
    final isCurrent = session['is_current'] == true;
    final rawDevice = session['device'] as String? ?? 'Unknown';
    final appState = context.read<AppState>();
    final device = (isCurrent && appState.customDeviceModel.isNotEmpty)
        ? appState.customDeviceModel
        : rawDevice;
    final platform = session['platform'] as String? ?? '';
    final appName = session['app_name'] as String? ?? '';
    final appVersion = session['app_version'] as String? ?? '';
    final ip = session['ip'] as String? ?? '';
    final location = session['location'] as String? ?? '';
    final lastActive = session['last_active'] as String? ?? '';
    final systemStr = session['system'] as String? ?? platform;
    final apiId = session['api_id'] as int?;
    final officialApp = session['official_app'] == true;
    final info = _classifyDevice(rawDevice, platform, appName, apiId: apiId, system: systemStr);

    final appStr = _formatApplication(appName, appVersion, apiId);
    // AyuGram's SessionInfoBox shows langDateTimeFull(unixtime::parse(activeTime))
    // for EVERY session including the current one (settings_active_sessions.cpp:443) —
    // activeTime is delivered for the current session too — not a literal "online".
    final fullDate = _formatFullDate(lastActive);

    // Token-driven colors — AyuGram's session info box is fully theme-bound
    // (e.g. sessionInfoFg: windowSubTextFg, settings/settings.style:359). Boxes
    // use boxBg/boxTextFg; the thin separators use shadowFg.
    final palette = context.palette;
    final bgColor = palette.boxBg;
    final textColor = palette.boxTextFg;
    final subtextColor = palette.windowSubTextFg;
    final iconColor = palette.windowSubTextFg;
    final accentColor = palette.windowBgActive;
    final dividerColor = palette.shadowFg;
    final sectionTitleColor = palette.windowActiveTextFg;

    final useLottie = info.type != _DeviceType.web && info.type != _DeviceType.other;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: SizedBox(
          width: 364,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 18),
              _DeviceUserpicBig(
                info: info,
                useLottie: useLottie,
              ),
              const SizedBox(height: 7),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  device,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (fullDate.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  fullDate,
                  style: TextStyle(color: subtextColor, fontSize: 13),
                ),
              ],
              const SizedBox(height: 19),
              Container(height: 1, color: dividerColor),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 20, bottom: 8),
                  child: Text(
                    'Info',
                    style: TextStyle(
                      color: sectionTitleColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              if (appStr.isNotEmpty)
                _SessionInfoRow(
                  icon: Icons.devices,
                  iconColor: iconColor,
                  label: 'Application',
                  value: appStr,
                  textColor: textColor,
                  subtextColor: subtextColor,
                ),
              if (systemStr.isNotEmpty)
                _SessionInfoRow(
                  icon: Icons.info_outline,
                  iconColor: iconColor,
                  label: 'System version',
                  value: systemStr,
                  textColor: textColor,
                  subtextColor: subtextColor,
                ),
              _SessionInfoRow(
                icon: Icons.info_outline,
                iconColor: iconColor,
                label: 'Official App',
                value: officialApp ? 'Yes' : 'No',
                textColor: textColor,
                subtextColor: subtextColor,
              ),
              if (ip.isNotEmpty)
                _SessionInfoRow(
                  icon: Icons.language,
                  iconColor: iconColor,
                  label: 'IP Address',
                  value: ip,
                  textColor: textColor,
                  subtextColor: subtextColor,
                ),
              if (location.isNotEmpty)
                _SessionInfoRow(
                  icon: Icons.location_on_outlined,
                  iconColor: iconColor,
                  label: 'Location',
                  value: location,
                  textColor: textColor,
                  subtextColor: subtextColor,
                ),
              const SizedBox(height: 8),
              if (location.isNotEmpty) ...[
                Container(height: 1, color: dividerColor),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Text(
                    'This location estimate is based on the IP address and may not always be accurate.',
                    style: TextStyle(color: subtextColor, fontSize: 12, height: 1.4),
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Row(
                  children: [
                    if (!isCurrent) ...[
                      Expanded(
                        child: TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: palette.attentionButtonFg,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showTerminateConfirmation(
                              session['id'] as String? ?? '',
                            );
                          },
                          child: const Text(
                            'Terminate Session',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                    ],
                    Expanded(
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: accentColor,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text(
                          'Done',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRenameDialog() {
    final current = _currentSession;
    final currentDevice = current?['device'] as String? ?? '';
    final appState = context.read<AppState>();
    final engine = context.read<EngineService>();
    final controller = TextEditingController(text: appState.customDeviceModel);
    final palette = context.palette;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.boxBg,
        title: Text(
          'Rename current device',
          style: TextStyle(
            color: palette.boxTextFg,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: TextField(
          controller: controller,
          maxLength: 32,
          autofocus: true,
          style: TextStyle(
            color: palette.boxTextFg,
            fontSize: 14,
          ),
          decoration: InputDecoration(
            hintText: currentDevice,
            hintStyle: TextStyle(
              color: palette.windowSubTextFg,
            ),
            border: InputBorder.none,
            counterStyle: TextStyle(
              color: palette.windowSubTextFg,
              fontSize: 12,
            ),
            constraints: const BoxConstraints(minHeight: 29),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(TrStrings.lngCancel()),
          ),
          TextButton(
            onPressed: () async {
              final text = controller.text.trim();
              Navigator.pop(ctx);
              // Single engine call → 'SetCustomDeviceModel'. The
              // customDeviceModel setter no longer fires its own (previously
              // bogus 'SetDeviceModel') call, so this writes exactly once.
              // setCustomDeviceModel returns false on failure (never throws),
              // so gate the local update on the bool result.
              final ok = await engine.setCustomDeviceModel(
                appState.activeAccountId, text);
              if (!mounted) return;
              if (ok) {
                appState.customDeviceModel = text;
                setState(() {});
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Failed to rename device')),
                );
              }
            },
            child: Text(TrStrings.lngSettingsSave()),
          ),
        ],
      ),
    );
  }

  String _formatFullDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      // .toLocal() — see _formatActiveDate; AyuGram's langDateTimeFull renders
      // the info-box "active" line in local time (settings_active_sessions.cpp:443).
      final date = DateTime.parse(dateStr).toLocal();
      final localizations = MaterialLocalizations.of(context);
      final dateFormatted = localizations.formatFullDate(date);
      final timeFormatted = localizations.formatTimeOfDay(
        TimeOfDay.fromDateTime(date),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );
      return '$dateFormatted at $timeFormatted';
    } catch (_) {
      return dateStr ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Token-driven colors so this screen tracks every app theme (incl. the
    // second dark theme, windowBg 0xFF282E33) instead of inlined hex pairs.
    // AyuGram is fully token-bound (sessionInfoFg: windowSubTextFg, etc.).
    final palette = context.palette;
    final bgColor = palette.windowBg;
    final textColor = palette.windowFg;
    final subtextColor = palette.windowSubTextFg;
    final dividerColor = palette.shadowFg;
    final accentColor = palette.windowBgActive;

    final otherSessions = _cachedOtherSessions;
    final incompleteSessions = _cachedIncompleteSessions;

    final body = _loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: accentColor),
                  const SizedBox(height: 16),
                  Text(
                    'Loading...',
                    style: TextStyle(color: subtextColor, fontSize: 14),
                  ),
                ],
              ),
            )
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _buildCurrentSession(textColor, subtextColor, accentColor, dividerColor),
                ),
                if (otherSessions.isNotEmpty || incompleteSessions.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _buildTerminateAllButton(dividerColor, subtextColor),
                  ),
                if (incompleteSessions.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _buildIncompleteSectionHeader(accentColor),
                  ),
                if (incompleteSessions.isNotEmpty)
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _SessionRow(
                        session: incompleteSessions[index],
                        deviceInfo: _getDeviceInfo(incompleteSessions[index]),
                        textColor: textColor,
                        subtextColor: subtextColor,
                        formatDate: _formatActiveDate,
                        showTerminate: true,
                        onTerminate: () => _showTerminateConfirmation(
                          incompleteSessions[index]['id'] as String? ?? '',
                        ),
                        onTap: () => _showSessionInfoBox(incompleteSessions[index]),
                      ),
                      childCount: incompleteSessions.length,
                    ),
                  ),
                if (incompleteSessions.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _buildIncompleteSectionFooter(dividerColor, subtextColor),
                  ),
                if (otherSessions.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _buildOtherSectionHeader(accentColor),
                  ),
                if (otherSessions.isNotEmpty)
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _SessionRow(
                        session: otherSessions[index],
                        deviceInfo: _getDeviceInfo(otherSessions[index]),
                        textColor: textColor,
                        subtextColor: subtextColor,
                        formatDate: _formatActiveDate,
                        showTerminate: true,
                        onTerminate: () => _showTerminateConfirmation(
                          otherSessions[index]['id'] as String? ?? '',
                        ),
                        onTap: () => _showSessionInfoBox(otherSessions[index]),
                      ),
                      childCount: otherSessions.length,
                    ),
                  ),
                if (otherSessions.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _buildOtherSectionFooter(dividerColor, subtextColor),
                  ),
                if (otherSessions.isEmpty)
                  SliverToBoxAdapter(
                    child: _buildEmptyPlaceholder(subtextColor),
                  ),
                // AyuGram gates the TTL section on the OTHER-sessions count:
                // ttlWrap->toggleOn(_list->itemsCount() > 0)
                // (settings_active_sessions.cpp:1030). With no other sessions
                // only the placeholder (toggleOn count == 0) is shown.
                if (otherSessions.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _buildAutoTerminateSection(textColor, subtextColor, dividerColor, accentColor),
                  ),
              ],
            );

    if (widget.embedded) return body;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Active Sessions',
          style: TextStyle(
            color: textColor,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: body,
    );
  }

  Widget _buildCurrentSession(
    Color textColor,
    Color subtextColor,
    Color accentColor,
    Color dividerColor,
  ) {
    final current = _currentSession;
    final customDeviceModel = context.select<AppState, String>((s) => s.customDeviceModel);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 23, 8),
          child: Row(
            children: [
              Text(
                'This device',
                style: TextStyle(
                  color: accentColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _showRenameDialog,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Text(
                    'Rename',
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (current != null) _SessionRow(
          session: current,
          deviceInfo: _getDeviceInfo(current),
          textColor: textColor,
          subtextColor: subtextColor,
          formatDate: _formatActiveDate,
          isCurrent: true,
          showTerminate: false,
          customDeviceName: customDeviceModel,
          onTap: () => _showSessionInfoBox(current),
        ),
        Container(height: 1, color: dividerColor),
      ],
    );
  }

  Widget _buildTerminateAllButton(Color dividerColor, Color subtextColor) {
    // AyuGram renders this as a standard full-width settings button —
    // CreateButtonWithIcon(..., st::infoBlockButton, {.icon=&st::infoIconBlock})
    // — left-aligned: block icon at iconLeft 22px, attention-red label at
    // padding.left 79px (info/info.style:731-735,754), NOT a centered row.
    final attentionColor = context.palette.attentionButtonFg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        InkWell(
          onTap: _showTerminateAllConfirmation,
          child: SizedBox(
            height: 44,
            child: Stack(
              children: [
                Positioned(
                  left: 22,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Icon(Icons.block, color: attentionColor, size: 22),
                  ),
                ),
                Positioned(
                  left: 79,
                  right: 8,
                  top: 0,
                  bottom: 0,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Terminate All Other Sessions',
                      style: TextStyle(color: attentionColor, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(height: 1, color: dividerColor),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
          child: Text(
            'Logs out all devices except for this one.',
            style: TextStyle(color: subtextColor, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildIncompleteSectionHeader(Color accentColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
      child: Text(
        'Incomplete Login Attempts',
        style: TextStyle(
          color: accentColor,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildIncompleteSectionFooter(Color dividerColor, Color subtextColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 1, color: dividerColor),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
          child: Text(
            'The devices above have no access to your messages. The code was entered correctly, but no correct password was given.',
            style: TextStyle(color: subtextColor, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildOtherSectionHeader(Color accentColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
      child: Text(
        'Active Devices',
        style: TextStyle(
          color: accentColor,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildOtherSectionFooter(Color dividerColor, Color subtextColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 1, color: dividerColor),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
          child: Text(
            'The official Telegram app is available for Android, iPhone, iPad, Windows, macOS and Linux.',
            style: TextStyle(color: subtextColor, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildAutoTerminateSection(
    Color textColor,
    Color subtextColor,
    Color dividerColor,
    Color accentColor,
  ) {
    final label = _autoTerminateDays > 0 ? _formatDaysLabel(_autoTerminateDays) : 'Never';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 1, color: dividerColor),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.only(left: 22, bottom: 8),
          child: Text(
            'Terminate old sessions',
            style: TextStyle(
              color: accentColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        InkWell(
          onTap: _showAutoTerminateDialog,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'If Inactive For',
                    style: TextStyle(color: textColor, fontSize: 14),
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(color: accentColor, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
        Container(height: 1, color: dividerColor),
      ],
    );
  }

  Widget _buildEmptyPlaceholder(Color subtextColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
      child: Text(
        'You can log in to Telegram from other mobile, tablet and desktop devices, using the same phone number. All your data will be instantly synchronized.',
        style: TextStyle(color: subtextColor, fontSize: 13),
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  final Map<String, dynamic> session;
  final _DeviceInfo deviceInfo;
  final Color textColor;
  final Color subtextColor;
  final String Function(String?) formatDate;
  final bool isCurrent;
  final bool showTerminate;
  final VoidCallback? onTerminate;
  final VoidCallback? onTap;
  final String? customDeviceName;

  const _SessionRow({
    required this.session,
    required this.deviceInfo,
    required this.textColor,
    required this.subtextColor,
    required this.formatDate,
    this.isCurrent = false,
    this.showTerminate = false,
    this.onTerminate,
    this.onTap,
    this.customDeviceName,
  });

  @override
  Widget build(BuildContext context) {
    final rawDevice = session['device'] as String? ?? 'Unknown';
    final device = (customDeviceName != null && customDeviceName!.isNotEmpty)
        ? customDeviceName!
        : rawDevice;
    final appName = session['app_name'] as String? ?? '';
    final appVersion = session['app_version'] as String? ?? '';
    final ip = session['ip'] as String? ?? '';
    final location = session['location'] as String? ?? '';
    final lastActive = session['last_active'] as String? ?? '';
    final info = deviceInfo;

    // AyuGram ParseEntry normalization (see _formatApplication): forces the
    // "Telegram Desktop" name + dotted version for desktop api_ids and trims
    // mobile/web versions to their build segment, instead of the raw concat.
    final status = _formatApplication(
        appName, appVersion, session['api_id'] as int?);

    final locationOrIp = location.isNotEmpty ? location : ip;
    final locationParts = <String>[];
    if (locationOrIp.isNotEmpty) locationParts.add(locationOrIp);
    if (!isCurrent) {
      final dateStr = formatDate(lastActive);
      if (dateStr.isNotEmpty) locationParts.add(dateStr);
    }
    final locationLine = locationParts.join(' • ');

    final hoverBg = context.palette.windowBgOver;

    return InkWell(
      hoverColor: hoverBg,
      onTap: onTap,
      child: SizedBox(
        height: 84,
        child: Stack(
          children: [
            Positioned(
              left: 21,
              top: 10,
              child: _DeviceUserpic(info: info, size: 42),
            ),
            Positioned(
              left: 78,
              top: 11,
              right: showTerminate ? 45 : 11,
              child: Text(
                device,
                style: TextStyle(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (status.isNotEmpty)
              Positioned(
                left: 78,
                top: 32,
                right: showTerminate ? 45 : 11,
                child: Text(
                  status,
                  style: TextStyle(color: textColor, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (locationLine.isNotEmpty)
              Positioned(
                left: 78,
                top: 54,
                right: showTerminate ? 45 : 11,
                child: Text(
                  locationLine,
                  style: TextStyle(color: subtextColor, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (showTerminate)
              Positioned(
                right: 11,
                top: 8,
                child: SizedBox(
                  width: 34,
                  height: 34,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    icon: Icon(Icons.close, color: subtextColor),
                    onPressed: onTerminate,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DeviceUserpic extends StatelessWidget {
  final _DeviceInfo info;
  final double size;

  const _DeviceUserpic({required this.info, required this.size});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final gradient = _gradientForType(info.type, palette);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheSize = (size * 0.52 * dpr).round();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [gradient.top, gradient.bottom],
        ),
      ),
      child: Center(
        child: Image.asset(
          info.iconAsset,
          width: size * 0.52,
          height: size * 0.52,
          cacheWidth: cacheSize,
          cacheHeight: cacheSize,
          color: palette.historyPeerUserpicFg,
          colorBlendMode: BlendMode.srcIn,
        ),
      ),
    );
  }
}

class _DeviceUserpicBig extends StatefulWidget {
  final _DeviceInfo info;
  final bool useLottie;

  const _DeviceUserpicBig({required this.info, required this.useLottie});

  @override
  State<_DeviceUserpicBig> createState() => _DeviceUserpicBigState();
}

class _DeviceUserpicBigState extends State<_DeviceUserpicBig> with SingleTickerProviderStateMixin {
  AnimationController? _lottieController;
  Animation<double>? _routeAnimation;
  void Function(AnimationStatus)? _routeAnimationListener;

  @override
  void initState() {
    super.initState();
    if (widget.useLottie) {
      _lottieController = AnimationController(vsync: this);
    }
  }

  @override
  void dispose() {
    if (_routeAnimationListener != null) {
      _routeAnimation?.removeStatusListener(_routeAnimationListener!);
    }
    _lottieController?.dispose();
    super.dispose();
  }

  void _onLottieLoaded(LottieComposition composition) {
    _lottieController?.duration = composition.duration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route?.animation?.isCompleted == true) {
        _lottieController?.forward();
      } else {
        void listener(AnimationStatus status) {
          if (status == AnimationStatus.completed) {
            if (mounted) _lottieController?.forward();
            route?.animation?.removeStatusListener(listener);
            _routeAnimationListener = null;
            _routeAnimation = null;
          }
        }
        _routeAnimation = route?.animation;
        _routeAnimationListener = listener;
        route?.animation?.addStatusListener(listener);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const size = 70.0;
    final palette = context.palette;
    final gradient = _gradientForType(widget.info.type, palette);
    final fgColor = palette.historyPeerUserpicFg;
    final lottieAsset = _lottiePath(widget.info.type);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheSize = (size * 0.52 * dpr).round();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [gradient.top, gradient.bottom],
        ),
      ),
      child: lottieAsset != null && widget.useLottie
          ? Lottie.asset(
              lottieAsset,
              controller: _lottieController,
              onLoaded: _onLottieLoaded,
              width: 52,
              height: 52,
              fit: BoxFit.contain,
              delegates: LottieDelegates(
                values: [
                  ValueDelegate.color(
                    const ['**'],
                    value: fgColor,
                  ),
                ],
              ),
            )
          : Center(
              child: Image.asset(
                _bigIconPath(widget.info.type),
                width: size * 0.52,
                height: size * 0.52,
                cacheWidth: cacheSize,
                cacheHeight: cacheSize,
                color: fgColor,
                colorBlendMode: BlendMode.srcIn,
              ),
            ),
    );
  }
}

class _SessionInfoRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final Color textColor;
  final Color subtextColor;

  const _SessionInfoRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.textColor,
    required this.subtextColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 9, 20, 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 21),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(color: textColor, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(color: subtextColor, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

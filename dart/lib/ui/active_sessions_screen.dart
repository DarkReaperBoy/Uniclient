import 'dart:async';

import 'package:flutter/material.dart';
import '../theme/telegram_palette.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
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
  final Color gradientTop;
  final Color gradientBottom;
  final IconData icon;

  const _DeviceInfo(this.type, this.gradientTop, this.gradientBottom, this.icon);
}

const _kGreen1 = Color(0xFF67B84D);
const _kGreen2 = Color(0xFF4DB847);
const _kOrange1 = Color(0xFFDE8C3E);
const _kOrange2 = Color(0xFFE67429);
const _kPurple1 = Color(0xFF8C79D2);
const _kPurple2 = Color(0xFF6B5EBF);
const _kCyan1 = Color(0xFF60C5E2);
const _kCyan2 = Color(0xFF41B5D8);
const _kRed1 = Color(0xFFDE6B6B);
const _kRed2 = Color(0xFFD45050);
const _kPink1 = Color(0xFFCB79D2);
const _kPink2 = Color(0xFFBF5EBF);

_DeviceInfo _classifyDevice(String device, String platform, String appName, {int? apiId, String? system}) {
  final d = device.toLowerCase();
  final p = (system ?? '').toLowerCase();
  final s = platform.toLowerCase();

  const kDesktop = {2040, 17349, 611335};
  const kMac = {2834};
  const kAndroid = {5, 6, 24, 1026, 1083, 2458, 2521, 21724};
  const kiOS = {1, 7, 10840, 16352};
  const kWeb = {2496, 739222, 1025907};

  _DeviceInfo? detectBrowser() {
    if (d.contains('edg/') || d.contains('edgios/') || d.contains('edga/')) {
      return const _DeviceInfo(_DeviceType.edge, _kPink1, _kPink2, Icons.web);
    } else if (d.contains('chrome')) {
      return const _DeviceInfo(_DeviceType.chrome, _kPink1, _kPink2, Icons.language);
    } else if (d.contains('safari')) {
      return const _DeviceInfo(_DeviceType.safari, _kPink1, _kPink2, Icons.explore);
    } else if (d.contains('firefox')) {
      return const _DeviceInfo(_DeviceType.firefox, _kPink1, _kPink2, Icons.local_fire_department);
    }
    return null;
  }

  _DeviceInfo? detectDesktop() {
    if (p.contains('windows') || s.contains('windows')) {
      return const _DeviceInfo(_DeviceType.windows, _kGreen1, _kGreen2, Icons.desktop_windows);
    } else if (p.contains('macos') || s.contains('macos')) {
      return const _DeviceInfo(_DeviceType.mac, _kGreen1, _kGreen2, Icons.desktop_mac);
    } else if (p.contains('ubuntu') || s.contains('ubuntu') || p.contains('unity') || s.contains('unity')) {
      return const _DeviceInfo(_DeviceType.ubuntu, _kOrange1, _kOrange2, Icons.terminal);
    } else if (p.contains('linux') || s.contains('linux')) {
      return const _DeviceInfo(_DeviceType.linux, _kPurple1, _kPurple2, Icons.computer);
    }
    return null;
  }

  if (apiId != null) {
    if (kAndroid.contains(apiId)) {
      return const _DeviceInfo(_DeviceType.android, _kRed1, _kRed2, Icons.phone_android);
    } else if (kDesktop.contains(apiId)) {
      return detectDesktop() ?? const _DeviceInfo(_DeviceType.linux, _kPurple1, _kPurple2, Icons.computer);
    } else if (kMac.contains(apiId)) {
      return const _DeviceInfo(_DeviceType.mac, _kGreen1, _kGreen2, Icons.desktop_mac);
    } else if (kWeb.contains(apiId)) {
      return detectBrowser() ?? const _DeviceInfo(_DeviceType.web, _kPink1, _kPink2, Icons.public);
    }
  }

  if (d.contains('chromebook')) {
    return const _DeviceInfo(_DeviceType.other, _kGreen1, _kGreen2, Icons.devices);
  }
  final browser = detectBrowser();
  if (browser != null) return browser;
  if (d.contains('iphone')) {
    return const _DeviceInfo(_DeviceType.iphone, _kCyan1, _kCyan2, Icons.phone_iphone);
  }
  if (d.contains('ipad')) {
    return const _DeviceInfo(_DeviceType.ipad, _kCyan1, _kCyan2, Icons.tablet_mac);
  }
  if (apiId != null && kiOS.contains(apiId)) {
    return const _DeviceInfo(_DeviceType.iphone, _kCyan1, _kCyan2, Icons.phone_iphone);
  }
  final desktop = detectDesktop();
  if (desktop != null) return desktop;
  if (p.contains('android') || s.contains('android')) {
    return const _DeviceInfo(_DeviceType.android, _kRed1, _kRed2, Icons.phone_android);
  }
  if (p.contains('ios') || s.contains('ios')) {
    return const _DeviceInfo(_DeviceType.iphone, _kCyan1, _kCyan2, Icons.phone_iphone);
  }
  return const _DeviceInfo(_DeviceType.other, _kGreen1, _kGreen2, Icons.devices);
}

class ActiveSessionsScreen extends StatefulWidget {
  const ActiveSessionsScreen({super.key});

  @override
  State<ActiveSessionsScreen> createState() => _ActiveSessionsScreenState();
}

class _ActiveSessionsScreenState extends State<ActiveSessionsScreen> {
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;
  Timer? _refreshTimer;
  int _autoTerminateDays = 0;

  List<Map<String, dynamic>> _cachedOtherSessions = [];
  List<Map<String, dynamic>> _cachedIncompleteSessions = [];

  @override
  void initState() {
    super.initState();
    _loadSessions();
    _loadAutoTerminateDays();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) => _loadSessions());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _recomputeCachedLists() {
    final other = _sessions.where((s) => s['is_current'] != true && s['password_pending'] != true).toList();
    other.sort((a, b) {
      final aDate = a['last_active'] as String? ?? '';
      final bDate = b['last_active'] as String? ?? '';
      return bDate.compareTo(aDate);
    });
    _cachedOtherSessions = other;

    final incomplete = _sessions.where((s) => s['password_pending'] == true).toList();
    incomplete.sort((a, b) {
      final aDate = a['last_active'] as String? ?? '';
      final bDate = b['last_active'] as String? ?? '';
      return bDate.compareTo(aDate);
    });
    _cachedIncompleteSessions = incomplete;
  }

  Future<void> _loadSessions() async {
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
    if (ok && mounted) {
      setState(() {
        _sessions.removeWhere((s) => s['id'] == sessionId);
        _recomputeCachedLists();
      });
    }
  }

  Future<void> _terminateAllOther() async {
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final ok = await engine.terminateAllOtherSessions(appState.activeAccountId);
    if (ok && mounted) {
      setState(() {
        _sessions.removeWhere((s) => s['is_current'] != true);
        _recomputeCachedLists();
      });
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
      final months = (days / 30).round().clamp(1, 999);
      return months == 1 ? '1 month' : '$months months';
    }
    final weeks = (days / 7).round().clamp(1, 999);
    return weeks == 1 ? '1 week' : '$weeks weeks';
  }

  void _showAutoTerminateDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor = isDark ? const Color(0xFFE1E3E6) : const Color(0xFF222222);
    final subtextColor = isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);
    final accentColor = context.palette.windowBgActive;

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
                    'Session termination',
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
                    'If you don\'t come online from a specific session at least once within this period, it will be terminated.',
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
                          'Cancel',
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
                          if (ok && mounted) {
                            setState(() => _autoTerminateDays = selected);
                          }
                        },
                        child: Text(
                          'Save',
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

  void _showTerminateConfirmation(String sessionId, String deviceName) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E2C3A) : Colors.white,
        title: const Text('Terminate Session'),
        content: Text('Are you sure you want to terminate the session on "$deviceName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _terminateSession(sessionId);
            },
            child: const Text('Terminate'),
          ),
        ],
      ),
    );
  }

  void _showTerminateAllConfirmation() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E2C3A) : Colors.white,
        title: const Text('Terminate All Other Sessions'),
        content: const Text('Are you sure you want to terminate all other sessions?'),
        titleTextStyle: TextStyle(
          color: isDark ? const Color(0xFFE1E3E6) : const Color(0xFF222222),
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _terminateAllOther();
            },
            child: const Text('Terminate'),
          ),
        ],
      ),
    );
  }

  String _formatActiveDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(date);
      if (diff.inMinutes < 1) return 'online';
      if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${date.day}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    } catch (_) {
      return '';
    }
  }

  void _showSessionInfoBox(Map<String, dynamic> session) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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

    final appStr = appVersion.isNotEmpty ? '$appName $appVersion' : appName;
    final fullDate = isCurrent ? 'online' : _formatFullDate(lastActive);

    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor = isDark ? const Color(0xFFE1E3E6) : const Color(0xFF222222);
    final subtextColor = isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);
    final iconColor = isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);
    final accentColor = context.palette.windowBgActive;
    final dividerColor = isDark ? const Color(0xFF101921) : const Color(0xFFE6E6E6);
    final sectionTitleColor = context.palette.windowActiveTextFg;

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
              _DeviceUserpic(
                info: info,
                size: 70,
                animate: info.type != _DeviceType.web && info.type != _DeviceType.other,
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
                    'Session info',
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
                  label: 'System',
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
                    'This location is based on the IP address and may not always be accurate.',
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
                            foregroundColor: Colors.red,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showTerminateConfirmation(
                              session['id'] as String? ?? '',
                              device,
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
                          'OK',
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
    final controller = TextEditingController(text: appState.customDeviceModel);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E2C3A) : Colors.white,
        title: Text(
          'Rename Device',
          style: TextStyle(
            color: isDark ? const Color(0xFFE1E3E6) : const Color(0xFF222222),
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: TextField(
          controller: controller,
          maxLength: 32,
          autofocus: true,
          style: TextStyle(
            color: isDark ? const Color(0xFFE1E3E6) : const Color(0xFF222222),
            fontSize: 14,
          ),
          decoration: InputDecoration(
            hintText: currentDevice,
            hintStyle: TextStyle(
              color: isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999),
            ),
            border: InputBorder.none,
            counterStyle: TextStyle(
              color: isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999),
              fontSize: 12,
            ),
            constraints: const BoxConstraints(minHeight: 29),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final text = controller.text.trim();
              appState.customDeviceModel = text;
              if (mounted) setState(() {});
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String _formatFullDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr);
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final h = date.hour.toString().padLeft(2, '0');
      final m = date.minute.toString().padLeft(2, '0');
      return '${months[date.month - 1]} ${date.day}, ${date.year} at $h:$m';
    } catch (_) {
      return dateStr ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : Colors.white;
    final textColor = isDark ? const Color(0xFFE1E3E6) : const Color(0xFF222222);
    final subtextColor = isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);
    final dividerColor = isDark ? const Color(0xFF101921) : const Color(0xFFE6E6E6);
    final accentColor = context.palette.windowBgActive;

    final otherSessions = _cachedOtherSessions;
    final incompleteSessions = _cachedIncompleteSessions;

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
      body: _loading
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
                        textColor: textColor,
                        subtextColor: subtextColor,
                        formatDate: _formatActiveDate,
                        showTerminate: true,
                        onTerminate: () => _showTerminateConfirmation(
                          incompleteSessions[index]['id'] as String? ?? '',
                          incompleteSessions[index]['device'] as String? ?? 'Unknown',
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
                        textColor: textColor,
                        subtextColor: subtextColor,
                        formatDate: _formatActiveDate,
                        showTerminate: true,
                        onTerminate: () => _showTerminateConfirmation(
                          otherSessions[index]['id'] as String? ?? '',
                          otherSessions[index]['device'] as String? ?? 'Unknown',
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
                if (otherSessions.isEmpty && incompleteSessions.isEmpty)
                  SliverToBoxAdapter(
                    child: _buildEmptyPlaceholder(subtextColor),
                  ),
                if (otherSessions.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _buildAutoTerminateSection(textColor, subtextColor, dividerColor, accentColor),
                  ),
              ],
            ),
    );
  }

  Widget _buildCurrentSession(
    Color textColor,
    Color subtextColor,
    Color accentColor,
    Color dividerColor,
  ) {
    final current = _currentSession;
    final appState = context.watch<AppState>();
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
          textColor: textColor,
          subtextColor: subtextColor,
          formatDate: _formatActiveDate,
          showTerminate: false,
          customDeviceName: appState.customDeviceModel,
          onTap: () => _showSessionInfoBox(current),
        ),
        Container(height: 1, color: dividerColor),
      ],
    );
  }

  Widget _buildTerminateAllButton(Color dividerColor, Color subtextColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        InkWell(
          onTap: _showTerminateAllConfirmation,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.block, color: Colors.red, size: 22),
                SizedBox(width: 16),
                Text(
                  'Terminate All Other Sessions',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
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
            'Interrupted sessions will have to go through the full authorization process with a new confirmation code.',
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
            'These attempts had the correct login code, but no password was provided. If these attempts weren\'t made by you, you can terminate them and change your 2FA password.',
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
        'Active sessions',
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
    final label = _autoTerminateDays > 0 ? _formatDaysLabel(_autoTerminateDays) : '';
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
                if (label.isNotEmpty)
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
  final Color textColor;
  final Color subtextColor;
  final String Function(String?) formatDate;
  final bool showTerminate;
  final VoidCallback? onTerminate;
  final VoidCallback? onTap;
  final String? customDeviceName;

  const _SessionRow({
    required this.session,
    required this.textColor,
    required this.subtextColor,
    required this.formatDate,
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
    final platform = session['platform'] as String? ?? '';
    final systemStr = session['system'] as String? ?? '';
    final appName = session['app_name'] as String? ?? '';
    final appVersion = session['app_version'] as String? ?? '';
    final ip = session['ip'] as String? ?? '';
    final location = session['location'] as String? ?? '';
    final lastActive = session['last_active'] as String? ?? '';
    final apiId = session['api_id'] as int?;
    final info = _classifyDevice(rawDevice, platform, appName, apiId: apiId, system: systemStr);

    final statusParts = <String>[];
    if (appName.isNotEmpty) statusParts.add(appName);
    if (appVersion.isNotEmpty) statusParts.add(appVersion);
    final status = statusParts.join(' ');

    final locationOrIp = location.isNotEmpty ? location : ip;
    final locationParts = <String>[];
    if (locationOrIp.isNotEmpty) locationParts.add(locationOrIp);
    final dateStr = formatDate(lastActive);
    if (dateStr.isNotEmpty) locationParts.add(dateStr);
    final locationLine = locationParts.join(' • ');

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hoverBg = isDark ? const Color(0xFF202B36) : const Color(0xFFF1F1F1);

    return InkWell(
      hoverColor: hoverBg,
      onTap: onTap,
      child: SizedBox(
        height: 84,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(21, 10, 11, 10),
          child: Row(
            children: [
              _DeviceUserpic(info: info, size: 42),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      device,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (status.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        status,
                        style: TextStyle(color: textColor, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (locationLine.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        locationLine,
                        style: TextStyle(color: subtextColor, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (showTerminate)
                SizedBox(
                  width: 34,
                  height: 34,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    icon: Icon(Icons.close, color: subtextColor),
                    onPressed: onTerminate,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceUserpic extends StatefulWidget {
  final _DeviceInfo info;
  final double size;
  final bool animate;

  const _DeviceUserpic({required this.info, required this.size, this.animate = false});

  @override
  State<_DeviceUserpic> createState() => _DeviceUserpicState();
}

class _DeviceUserpicState extends State<_DeviceUserpic> with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _scaleAnim;
  Animation<double>? _fadeAnim;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _controller = AnimationController(
        duration: const Duration(milliseconds: 600),
        vsync: this,
      );
      _scaleAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
        CurvedAnimation(parent: _controller!, curve: Curves.easeOutBack),
      );
      _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _controller!, curve: const Interval(0.0, 0.5, curve: Curves.easeIn)),
      );
      _controller!.forward();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [widget.info.gradientTop, widget.info.gradientBottom],
        ),
      ),
      child: Icon(widget.info.icon, color: Colors.white, size: widget.size * 0.52),
    );
    if (_controller != null) {
      child = AnimatedBuilder(
        animation: _controller!,
        builder: (context, child) => Opacity(
          opacity: _fadeAnim!.value,
          child: Transform.scale(scale: _scaleAnim!.value, child: child),
        ),
        child: child,
      );
    }
    return child;
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../state/app_state.dart';
import 'settings_style.dart';

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

_DeviceInfo _classifyDevice(String device, String platform, String appName) {
  final d = device.toLowerCase();
  final p = platform.toLowerCase();
  final a = appName.toLowerCase();

  if (a.contains('chrome')) return const _DeviceInfo(_DeviceType.chrome, _kPink1, _kPink2, Icons.language);
  if (a.contains('edge')) return const _DeviceInfo(_DeviceType.edge, _kPink1, _kPink2, Icons.language);
  if (a.contains('firefox')) return const _DeviceInfo(_DeviceType.firefox, _kPink1, _kPink2, Icons.language);
  if (a.contains('safari')) return const _DeviceInfo(_DeviceType.safari, _kPink1, _kPink2, Icons.language);
  if (a.contains('web') || p.contains('web')) return const _DeviceInfo(_DeviceType.web, _kPink1, _kPink2, Icons.language);

  if (d.contains('iphone') || p.contains('ios') && !d.contains('ipad')) {
    return const _DeviceInfo(_DeviceType.iphone, _kCyan1, _kCyan2, Icons.phone_iphone);
  }
  if (d.contains('ipad')) return const _DeviceInfo(_DeviceType.ipad, _kCyan1, _kCyan2, Icons.tablet_mac);
  if (d.contains('android') || p.contains('android')) {
    return const _DeviceInfo(_DeviceType.android, _kRed1, _kRed2, Icons.phone_android);
  }
  if (d.contains('ubuntu') || p.contains('ubuntu')) {
    return const _DeviceInfo(_DeviceType.ubuntu, _kOrange1, _kOrange2, Icons.desktop_windows);
  }
  if (p.contains('linux') || d.contains('linux')) {
    return const _DeviceInfo(_DeviceType.linux, _kPurple1, _kPurple2, Icons.desktop_windows);
  }
  if (d.contains('mac') || p.contains('macos')) {
    return const _DeviceInfo(_DeviceType.mac, _kGreen1, _kGreen2, Icons.desktop_mac);
  }
  if (d.contains('windows') || p.contains('windows')) {
    return const _DeviceInfo(_DeviceType.windows, _kGreen1, _kGreen2, Icons.desktop_windows);
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

  @override
  void initState() {
    super.initState();
    _loadSessions();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) => _loadSessions());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
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
    });
  }

  Map<String, dynamic>? get _currentSession {
    for (final s in _sessions) {
      if (s['is_current'] == true) return s;
    }
    return null;
  }

  List<Map<String, dynamic>> get _otherSessions {
    return _sessions.where((s) => s['is_current'] != true).toList();
  }

  Future<void> _terminateSession(String sessionId) async {
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final ok = await engine.terminateSession(appState.activeAccountId, sessionId);
    if (ok && mounted) {
      setState(() {
        _sessions.removeWhere((s) => s['id'] == sessionId);
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
      });
    }
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : Colors.white;
    final textColor = isDark ? const Color(0xFFE1E3E6) : const Color(0xFF222222);
    final subtextColor = isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);
    final dividerColor = isDark ? const Color(0xFF101921) : const Color(0xFFE6E6E6);
    final accentColor = isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);

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
          : ListView(
              children: [
                _buildCurrentSession(textColor, subtextColor, accentColor, dividerColor),
                if (_otherSessions.isNotEmpty) ...[
                  _buildTerminateAllButton(dividerColor),
                  _buildOtherSessionsList(textColor, subtextColor, dividerColor, accentColor),
                ],
                if (_otherSessions.isEmpty)
                  _buildEmptyPlaceholder(subtextColor),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
          child: Text(
            'This device',
            style: TextStyle(
              color: accentColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (current != null) _SessionRow(
          session: current,
          textColor: textColor,
          subtextColor: subtextColor,
          formatDate: _formatActiveDate,
          showTerminate: false,
        ),
        Container(height: 1, color: dividerColor),
      ],
    );
  }

  Widget _buildTerminateAllButton(Color dividerColor) {
    return Column(
      children: [
        const SizedBox(height: 8),
        InkWell(
          onTap: _showTerminateAllConfirmation,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            child: Row(
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
        Container(height: 1, color: dividerColor),
      ],
    );
  }

  Widget _buildOtherSessionsList(
    Color textColor,
    Color subtextColor,
    Color dividerColor,
    Color accentColor,
  ) {
    final others = _otherSessions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
          child: Text(
            'Active sessions',
            style: TextStyle(
              color: accentColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        for (final session in others)
          _SessionRow(
            session: session,
            textColor: textColor,
            subtextColor: subtextColor,
            formatDate: _formatActiveDate,
            showTerminate: true,
            onTerminate: () => _showTerminateConfirmation(
              session['id'] as String? ?? '',
              session['device'] as String? ?? 'Unknown',
            ),
          ),
        Container(height: 1, color: dividerColor),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
          child: Text(
            'Interrupted login attempts and sessions on other devices that haven\'t been confirmed will appear here.',
            style: TextStyle(color: subtextColor, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyPlaceholder(Color subtextColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 40),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.security, size: 48, color: subtextColor.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              'No other active sessions',
              style: TextStyle(color: subtextColor, fontSize: 14),
            ),
          ],
        ),
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

  const _SessionRow({
    required this.session,
    required this.textColor,
    required this.subtextColor,
    required this.formatDate,
    this.showTerminate = false,
    this.onTerminate,
  });

  @override
  Widget build(BuildContext context) {
    final device = session['device'] as String? ?? 'Unknown';
    final platform = session['platform'] as String? ?? '';
    final appName = session['app_name'] as String? ?? '';
    final appVersion = session['app_version'] as String? ?? '';
    final ip = session['ip'] as String? ?? '';
    final location = session['location'] as String? ?? '';
    final lastActive = session['last_active'] as String? ?? '';
    final info = _classifyDevice(device, platform, appName);

    final statusParts = <String>[];
    if (appName.isNotEmpty) statusParts.add(appName);
    if (appVersion.isNotEmpty) statusParts.add(appVersion);
    final status = statusParts.join(' ');

    final locationParts = <String>[];
    if (location.isNotEmpty) locationParts.add(location);
    final dateStr = formatDate(lastActive);
    if (dateStr.isNotEmpty) locationParts.add(dateStr);
    final locationLine = locationParts.join(' · ');

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hoverBg = isDark ? const Color(0xFF202B36) : const Color(0xFFF1F1F1);

    return InkWell(
      hoverColor: hoverBg,
      onTap: () {},
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

class _DeviceUserpic extends StatelessWidget {
  final _DeviceInfo info;
  final double size;

  const _DeviceUserpic({required this.info, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [info.gradientTop, info.gradientBottom],
        ),
      ),
      child: Icon(info.icon, color: Colors.white, size: size * 0.52),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import '../theme/telegram_palette.dart';
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
  String _customDeviceModel = '';
  int _autoTerminateDays = 0;

  @override
  void initState() {
    super.initState();
    _loadCustomDeviceModel();
    _loadSessions();
    _loadAutoTerminateDays();
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
    return _sessions.where((s) => s['is_current'] != true && s['password_pending'] != true).toList();
  }

  List<Map<String, dynamic>> get _incompleteSessions {
    final list = _sessions.where((s) => s['password_pending'] == true).toList();
    list.sort((a, b) {
      final aDate = a['last_active'] as String? ?? '';
      final bDate = b['last_active'] as String? ?? '';
      return bDate.compareTo(aDate);
    });
    return list;
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

  Future<void> _loadAutoTerminateDays() async {
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    if (accountId.isEmpty) return;
    final days = await engine.getSessionAutoTerminateDays(accountId);
    if (!mounted) return;
    setState(() => _autoTerminateDays = days);
  }

  String _formatDaysLabel(int days) {
    if (days <= 0) return '';
    if (days == 7) return '1 week';
    if (days < 30) return '$days days';
    final months = days ~/ 30;
    if (months == 1) return '1 month';
    return '$months months';
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
      selected = options.first;
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
                    'If Inactive For',
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
                    'If you don\'t connect from a device for this period, the session on that device will be terminated.',
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

  String get _devicePrefsPath {
    final configDir = context.read<AppState>().configDir;
    return configDir.isEmpty ? '' : '$configDir/device_prefs.json';
  }

  void _loadCustomDeviceModel() {
    try {
      final path = _devicePrefsPath;
      if (path.isEmpty) return;
      final file = File(path);
      if (!file.existsSync()) return;
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      _customDeviceModel = data['custom_device_model'] as String? ?? '';
    } catch (_) {}
  }

  void _saveCustomDeviceModel(String name) {
    setState(() => _customDeviceModel = name);
    try {
      final path = _devicePrefsPath;
      if (path.isEmpty) return;
      File(path).writeAsStringSync(jsonEncode({
        'custom_device_model': name,
      }));
    } catch (_) {}
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

  void _showSessionInfoBox(Map<String, dynamic> session) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isCurrent = session['is_current'] == true;
    final rawDevice = session['device'] as String? ?? 'Unknown';
    final device = (isCurrent && _customDeviceModel.isNotEmpty)
        ? _customDeviceModel
        : rawDevice;
    final platform = session['platform'] as String? ?? '';
    final appName = session['app_name'] as String? ?? '';
    final appVersion = session['app_version'] as String? ?? '';
    final ip = session['ip'] as String? ?? '';
    final location = session['location'] as String? ?? '';
    final lastActive = session['last_active'] as String? ?? '';
    final systemStr = session['system'] as String? ?? platform;
    final info = _classifyDevice(rawDevice, platform, appName);

    final appStr = appVersion.isNotEmpty ? '$appName $appVersion' : appName;
    final fullDate = isCurrent ? 'online' : _formatFullDate(lastActive);

    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor = isDark ? const Color(0xFFE1E3E6) : const Color(0xFF222222);
    final subtextColor = isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);
    final iconColor = isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);
    final accentColor = context.palette.windowBgActive;

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
              _DeviceUserpic(info: info, size: 70),
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
    final controller = TextEditingController(text: _customDeviceModel);
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
              _saveCustomDeviceModel(text);
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212B) : Colors.white;
    final textColor = isDark ? const Color(0xFFE1E3E6) : const Color(0xFF222222);
    final subtextColor = isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);
    final dividerColor = isDark ? const Color(0xFF101921) : const Color(0xFFE6E6E6);
    final accentColor = context.palette.windowBgActive;

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
                if (_otherSessions.isNotEmpty || _incompleteSessions.isNotEmpty) ...[
                  _buildTerminateAllButton(dividerColor),
                ],
                if (_incompleteSessions.isNotEmpty)
                  _buildIncompleteSessionsList(textColor, subtextColor, dividerColor, accentColor),
                if (_otherSessions.isNotEmpty)
                  _buildOtherSessionsList(textColor, subtextColor, dividerColor, accentColor),
                if (_otherSessions.isEmpty && _incompleteSessions.isEmpty)
                  _buildEmptyPlaceholder(subtextColor),
                _buildAutoTerminateButton(textColor, subtextColor, dividerColor, accentColor),
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
          customDeviceName: _customDeviceModel,
          onTap: () => _showSessionInfoBox(current),
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
        Container(height: 1, color: dividerColor),
      ],
    );
  }

  Widget _buildIncompleteSessionsList(
    Color textColor,
    Color subtextColor,
    Color dividerColor,
    Color accentColor,
  ) {
    final incomplete = _incompleteSessions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
          child: Text(
            'Incomplete Login Attempts',
            style: TextStyle(
              color: accentColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        for (final session in incomplete)
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
            onTap: () => _showSessionInfoBox(session),
          ),
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
            onTap: () => _showSessionInfoBox(session),
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

  Widget _buildAutoTerminateButton(
    Color textColor,
    Color subtextColor,
    Color dividerColor,
    Color accentColor,
  ) {
    final label = _autoTerminateDays > 0 ? _formatDaysLabel(_autoTerminateDays) : '';
    return Column(
      children: [
        Container(height: 1, color: dividerColor),
        InkWell(
          onTap: _showAutoTerminateDialog,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
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
    final appName = session['app_name'] as String? ?? '';
    final appVersion = session['app_version'] as String? ?? '';
    final ip = session['ip'] as String? ?? '';
    final location = session['location'] as String? ?? '';
    final lastActive = session['last_active'] as String? ?? '';
    final info = _classifyDevice(rawDevice, platform, appName);

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

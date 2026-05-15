import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/app_state.dart';
import 'ayu_section_builder.dart';

class AyuOtherPage extends StatelessWidget {
  const AyuOtherPage({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final b = AyuSectionBuilder(
        isDark: isDark, useMaterial: appState.materialSwitches);

    b.addSkip();

    // --- Support / Donations (§54.15) ---
    b.addSectionTitle('Support');
    b.addWidget(_DonateButton(
      label: 'Boosty',
      svgAsset: 'assets/icons/ayu/donates/boosty.svg',
      iconColor: const Color(0xFFF15F2C),
      isDark: isDark,
      onTap: () => launchUrl(Uri.parse('https://boosty.to/alexeyzavar'),
          mode: LaunchMode.externalApplication),
    ));
    b.addWidget(_DonateButton(
      label: 'TON',
      svgAsset: 'assets/icons/ayu/donates/ton.svg',
      iconColor: const Color(0xFF0098EA),
      isDark: isDark,
      onTap: () => _showDonateQr(context, 'TON',
          'UQA4i8U8vP3mYUZSV3KqDQEHPwmhninEqCkkKc7BITQ652de',
          const Color(0xFF0098EA), isDark, 'assets/icons/ayu/donates/ton.svg'),
    ));
    b.addWidget(_DonateButton(
      label: 'Bitcoin',
      svgAsset: 'assets/icons/ayu/donates/bitcoin.svg',
      iconColor: const Color(0xFFF7931A),
      isDark: isDark,
      onTap: () => _showDonateQr(context, 'Bitcoin',
          'bc1qdk6qq4mzq5yap3fpy0qau3246w3m3uwac9f0xd',
          const Color(0xFFF7931A), isDark, 'assets/icons/ayu/donates/bitcoin.svg'),
    ));
    b.addWidget(_DonateButton(
      label: 'Ethereum',
      svgAsset: 'assets/icons/ayu/donates/ethereum.svg',
      iconColor: const Color(0xFF627EEA),
      isDark: isDark,
      onTap: () => _showDonateQr(context, 'Ethereum',
          '0x405589857C8DFAb45B2027c68ad1e58877FDa347',
          const Color(0xFF627EEA), isDark, 'assets/icons/ayu/donates/ethereum.svg'),
    ));
    b.addWidget(_DonateButton(
      label: 'Solana',
      svgAsset: 'assets/icons/ayu/donates/solana.svg',
      iconColor: const Color(0xFF9945FF),
      isDark: isDark,
      onTap: () => _showDonateQr(context, 'Solana',
          '8ZHQpPxpsdRjsWoBcF1dmvRM5dB6zEhJ3jMBFZjYfyHs',
          const Color(0xFF9945FF), isDark, 'assets/icons/ayu/donates/solana.svg'),
    ));
    b.addWidget(_DonateButton(
      label: 'Tron',
      svgAsset: 'assets/icons/ayu/donates/tron.svg',
      iconColor: const Color(0xFFFF0013),
      isDark: isDark,
      onTap: () => _showDonateQr(context, 'Tron',
          'TRpbajq38qU8joThgAfKJLyEPbNjzsdPJ1',
          const Color(0xFFFF0013), isDark, 'assets/icons/ayu/donates/tron.svg'),
    ));
    b.addSkip();
    b.addWidget(_SupportDescription(
      isDark: isDark,
      onSupportTap: () => launchUrl(Uri.parse('tg://support'),
          mode: LaunchMode.externalApplication),
    ));
    b.addSkip();

    if (!const bool.fromEnvironment('TDESKTOP_DISABLE_AUTOUPDATE')) {
      b.addSectionDivider();
      b.addSectionTitle('Other');
      b.addSettingToggle(
        label: 'Crash Reporting',
        subtitle: 'Send crash reports to developers',
        value: appState.crashReporting,
        onChanged: (v) => appState.setCrashReporting(v),
        icon: Icons.bug_report_outlined,
      );
      b.addSkip();
      b.addDescription('Help improve AyuGram by automatically sending '
          'crash reports when the app encounters an error.');
    }

    b.addSectionDivider();

    // --- Utility Actions (§54.15) ---
    b.addWidget(_ActionButton(
      label: 'Register URL Scheme',
      icon: Icons.link,
      isDark: isDark,
      onTap: () => _registerUrlScheme(context),
    ));
    b.addWidget(_ActionButton(
      label: 'Reset Settings',
      icon: Icons.restore,
      isDark: isDark,
      onTap: () => _showResetConfirmation(context, appState),
    ));

    b.addSkip(24);

    return ayuSettingsScaffold(
      context: context,
      title: 'Other',
      children: b.build(),
    );
  }

  static void _showDonateQr(BuildContext context, String name, String address,
      Color accentColor, bool isDark, String svgAsset) {
    showDialog(
      context: context,
      builder: (ctx) => _DonateQrBox(
        name: name,
        address: address,
        accentColor: accentColor,
        isDark: isDark,
        svgAsset: svgAsset,
      ),
    );
  }

  static void _showDonateInfoBox(BuildContext context, bool isDark) {
    showDialog(
      context: context,
      builder: (ctx) => _DonateInfoBox(isDark: isDark),
    );
  }

  static void _registerUrlScheme(BuildContext context) {
    if (Platform.isLinux) {
      _registerLinuxUrlScheme(context);
    } else if (Platform.isMacOS) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('URL schemes are registered automatically on macOS')),
      );
    } else if (Platform.isWindows) {
      _registerWindowsUrlScheme(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('URL scheme registration is not supported on this platform')),
      );
    }
  }

  static Future<void> _registerLinuxUrlScheme(BuildContext context) async {
    final home = Platform.environment['HOME'] ?? '';
    if (home.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed: HOME not set')),
        );
      }
      return;
    }
    final appDir = '$home/.local/share/applications';
    final desktopFile = '$appDir/uniclient-tg.desktop';
    final execPath = Platform.resolvedExecutable;
    final content = '[Desktop Entry]\n'
        'Version=1.0\n'
        'Name=Uniclient\n'
        'Exec=$execPath -- %u\n'
        'Icon=uniclient\n'
        'Terminal=false\n'
        'Type=Application\n'
        'MimeType=x-scheme-handler/tg;x-scheme-handler/tdesktop;\n';
    try {
      await Directory(appDir).create(recursive: true);
      await File(desktopFile).writeAsString(content);
      await Process.run('xdg-mime', ['default', 'uniclient-tg.desktop', 'x-scheme-handler/tg']);
      await Process.run('xdg-mime', ['default', 'uniclient-tg.desktop', 'x-scheme-handler/tdesktop']);
      await Process.run('update-desktop-database', [appDir]);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('URL schemes registered (tg://, tdesktop://)')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  static Future<void> _registerWindowsUrlScheme(BuildContext context) async {
    final execPath = Platform.resolvedExecutable;
    try {
      for (final scheme in ['tg', 'tdesktop']) {
        await Process.run('reg', [
          'add', 'HKCU\\Software\\Classes\\$scheme',
          '/ve', '/d', 'URL:$scheme Protocol', '/f',
        ]);
        await Process.run('reg', [
          'add', 'HKCU\\Software\\Classes\\$scheme',
          '/v', 'URL Protocol', '/d', '', '/f',
        ]);
        await Process.run('reg', [
          'add', 'HKCU\\Software\\Classes\\$scheme\\shell\\open\\command',
          '/ve', '/d', '"$execPath" -- "%1"', '/f',
        ]);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('URL schemes registered (tg://, tdesktop://)')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  static void _showResetConfirmation(BuildContext context, AppState appState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1B2836) : Colors.white,
        title: Text('Reset Settings',
            style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600)),
        content: Text(
            'Are you sure you want to reset all AyuGram settings to defaults?\n\n'
            'This will reset ghost mode, appearance, filters, and all other AyuGram preferences.',
            style:
                TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel',
                style: TextStyle(
                    color: isDark
                        ? const Color(0xFF6AB2F2)
                        : const Color(0xFF3390EC))),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              appState.resetAyuSettings();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Done'), duration: Duration(seconds: 2)),
              );
            },
            child: Text('Reset',
                style: TextStyle(color: Colors.red.shade400)),
          ),
        ],
      ),
    );
  }
}

class _DonateButton extends StatelessWidget {
  final String label;
  final String svgAsset;
  final Color iconColor;
  final bool isDark;
  final VoidCallback onTap;

  const _DonateButton({
    required this.label,
    required this.svgAsset,
    required this.iconColor,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const iconSize = 28.0;
    final bgColor = isDark
        ? const Color(0xFFEEEEEE)
        : const Color(0xFF242B2C);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        child: Row(
          children: [
            Container(
              width: iconSize,
              height: iconSize,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(iconSize / 4),
              ),
              child: Center(
                child: SvgPicture.asset(
                  svgAsset,
                  width: iconSize - 4,
                  height: iconSize - 4,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87)),
            ),
            Icon(Icons.chevron_right,
                size: 20,
                color: isDark
                    ? const Color(0xFF6D7F8F)
                    : const Color(0xFF999999)),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor =
        isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 24, color: iconColor),
            const SizedBox(width: 16),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportDescription extends StatefulWidget {
  final bool isDark;
  final VoidCallback onSupportTap;

  const _SupportDescription({
    required this.isDark,
    required this.onSupportTap,
  });

  @override
  State<_SupportDescription> createState() => _SupportDescriptionState();
}

class _SupportDescriptionState extends State<_SupportDescription> {
  late final TapGestureRecognizer _recognizer;

  @override
  void initState() {
    super.initState();
    _recognizer = TapGestureRecognizer()..onTap = widget.onSupportTap;
  }

  @override
  void dispose() {
    _recognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subtextColor =
        widget.isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);
    final linkColor =
        widget.isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 12, color: subtextColor),
          children: [
            const TextSpan(
                text: 'You can support AyuGram development through donations. '
                    'For questions, '),
            TextSpan(
              text: 'contact support',
              style: TextStyle(color: linkColor),
              recognizer: _recognizer,
            ),
            const TextSpan(text: '.'),
          ],
        ),
      ),
    );
  }
}

class _DonateInfoBox extends StatefulWidget {
  final bool isDark;

  static const _donateAmountUsd =
      String.fromEnvironment('DONATE_AMOUNT_USD', defaultValue: '5');
  static const _donateAmountTon =
      String.fromEnvironment('DONATE_AMOUNT_TON', defaultValue: '10');
  static const _donateAmountRub =
      String.fromEnvironment('DONATE_AMOUNT_RUB', defaultValue: '300');
  static const _donateUsername =
      String.fromEnvironment('DONATE_USERNAME', defaultValue: 'RadianceTG');

  const _DonateInfoBox({required this.isDark});

  @override
  State<_DonateInfoBox> createState() => _DonateInfoBoxState();
}

class _DonateInfoBoxState extends State<_DonateInfoBox> {
  late final TapGestureRecognizer _usernameRecognizer;

  @override
  void initState() {
    super.initState();
    _usernameRecognizer = TapGestureRecognizer()
      ..onTap = () => launchUrl(
          Uri.parse('https://t.me/${_DonateInfoBox._donateUsername}'),
          mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() {
    _usernameRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bgColor = isDark ? const Color(0xFF1B2836) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtextColor =
        isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);
    final accentColor =
        isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC);

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              'assets/icons/ayu/donates/support_logo.svg',
              width: 96,
              height: 96,
            ),
            const SizedBox(height: 16),
            Text('Support AyuGram Desktop',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textColor)),
            const SizedBox(height: 12),
            Text(
              'Support AyuGram development by donating. '
              'Minimum amounts: \$${_DonateInfoBox._donateAmountUsd}, '
              '${_DonateInfoBox._donateAmountTon} TON, '
              '${_DonateInfoBox._donateAmountRub}₽.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: subtextColor),
            ),
            const SizedBox(height: 16),
            _DonateInfoRow(
              icon: Icons.monetization_on,
              title: 'Make a donation',
              description: 'Use the crypto buttons or visit Boosty.',
              textColor: textColor,
              subtextColor: subtextColor,
            ),
            const SizedBox(height: 12),
            _DonateInfoRow(
              icon: Icons.photo_camera,
              title: 'Send proof',
              descriptionSpan: TextSpan(
                children: [
                  const TextSpan(text: 'Forward your payment confirmation to '),
                  TextSpan(
                    text: '@${_DonateInfoBox._donateUsername}',
                    style: TextStyle(color: accentColor),
                    recognizer: _usernameRecognizer,
                  ),
                  const TextSpan(text: ' on Telegram.'),
                ],
              ),
              textColor: textColor,
              subtextColor: subtextColor,
            ),
            const SizedBox(height: 12),
            _DonateInfoRow(
              icon: Icons.verified,
              title: 'Receive your badge',
              description:
                  'After verification, you will receive a supporter badge.',
              textColor: textColor,
              subtextColor: subtextColor,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Close', style: TextStyle(color: accentColor)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DonateInfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;
  final TextSpan? descriptionSpan;
  final Color textColor;
  final Color subtextColor;

  const _DonateInfoRow({
    required this.icon,
    required this.title,
    this.description,
    this.descriptionSpan,
    required this.textColor,
    required this.subtextColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: subtextColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textColor)),
              const SizedBox(height: 2),
              if (descriptionSpan != null)
                Text.rich(descriptionSpan!,
                    style: TextStyle(fontSize: 12, color: subtextColor))
              else
                Text(description ?? '',
                    style: TextStyle(fontSize: 12, color: subtextColor)),
            ],
          ),
        ),
      ],
    );
  }
}

class _DonateQrBox extends StatelessWidget {
  final String name;
  final String address;
  final Color accentColor;
  final bool isDark;
  final String svgAsset;

  const _DonateQrBox({
    required this.name,
    required this.address,
    required this.accentColor,
    required this.isDark,
    required this.svgAsset,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark ? const Color(0xFF1B2836) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtextColor =
        isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);
    final buttonColor =
        isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC);
    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('QR Code',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: textColor)),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(12),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  QrImageView(
                    data: address,
                    version: QrVersions.auto,
                    size: 180,
                    eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square, color: Colors.black),
                    dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Colors.black),
                  ),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: SvgPicture.asset(
                        svgAsset,
                        width: 32,
                        height: 32,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SelectableText(
              address,
              style: TextStyle(fontSize: 13, color: subtextColor),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: address));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Address copied to clipboard')),
                  );
                },
                child: Text('Copy', style: TextStyle(color: buttonColor)),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Close', style: TextStyle(color: buttonColor)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../bridge/engine_service.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';
import '../theme/telegram_palette.dart';
import '../utils/rc_manager.dart';
import 'ayu_section_builder.dart';
import 'telegram_toast.dart';
import 'package:uniclient/utils/debug.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

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
      onSupportTap: () => _showDonateInfoBox(context, isDark),
    ));

    if (!const bool.fromEnvironment('TDESKTOP_DISABLE_AUTOUPDATE')) {
      // BuildCrashReporting (settings_other.cpp:178-194): opens with a plain
      // builder.addSkip() (:180) — this is the crash block's own leading skip,
      // so it belongs INSIDE this branch (it vanishes with the block when
      // autoupdate is disabled, exactly like the C++ #ifndef). Then the "Other"
      // subsection title (:181), the crash toggle (:183), another addSkip (:191),
      // and finally the description rendered ON a full-bleed boxDividerBg band via
      // builder.addDividerText() (:192 -> Ui::AddDividerText/DividerLabel) — the
      // SAME band treatment as the support description above, NOT a transparent
      // plain-text label. No separate empty divider band exists here.
      b.addSkip();
      b.addSectionTitle('Other');
      b.addSettingToggle(
        label: 'Crash Reporting',
        value: appState.crashReporting,
        onChanged: (v) => appState.setCrashReporting(v),
        icon: Icons.bug_report_outlined,
      );
      b.addSkip();
      b.addDividerText("When this option is enabled, you'll be prompted to "
          'send a report after the app crashes. You can decide whether to '
          'send it or not.');
    }

    // BuildOtherThings opens with a plain builder.addSkip() (settings_other.cpp:199),
    // NOT a divider band: the element immediately above (the crash divider-text
    // band when autoupdate is enabled, otherwise the support divider-text band)
    // already IS the boxDividerBg divider, so a second 8px band would be a
    // duplicate AyuGram never renders.
    b.addSkip();

    // --- Utility Actions (§54.15) ---
    // URL-scheme registration only applies to desktop platforms; don't offer the
    // action where it can't run (no fake "unsupported" message).
    if (!kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
      b.addWidget(_ActionButton(
        label: 'Register URL Scheme',
        icon: Icons.link,
        isDark: isDark,
        onTap: () => _registerUrlScheme(context),
      ));
    }
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
      _registerMacOsUrlScheme(context);
    } else if (Platform.isWindows) {
      _registerWindowsUrlScheme(context);
    } else {
      // The Register-URL-Scheme action is only offered on desktop (see the
      // visibility gate where the button is built), so this branch is
      // unreachable in practice; log defensively rather than showing a message.
      Debug.log('ayu_other_page', 'URL scheme registration unavailable on this platform');
    }
  }

  static Future<void> _registerMacOsUrlScheme(BuildContext context) async {
    try {
      final bundlePath = Platform.resolvedExecutable
          .replaceFirst(RegExp(r'/Contents/MacOS/.*$'), '');
      await Process.run('/System/Library/Frameworks/CoreServices.framework/'
          'Versions/A/Frameworks/LaunchServices.framework/'
          'Versions/A/Support/lsregister', ['-R', '-f', bundlePath]);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('URL schemes registered (tg://, tonsite://)')),
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
        'MimeType=x-scheme-handler/tg;x-scheme-handler/tonsite;\n';
    try {
      await Directory(appDir).create(recursive: true);
      await File(desktopFile).writeAsString(content);
      await Process.run('xdg-mime', ['default', 'uniclient-tg.desktop', 'x-scheme-handler/tg']);
      await Process.run('xdg-mime', ['default', 'uniclient-tg.desktop', 'x-scheme-handler/tonsite']);
      await Process.run('update-desktop-database', [appDir]);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('URL schemes registered (tg://, tonsite://)')),
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
      for (final scheme in ['tg', 'tonsite']) {
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
          const SnackBar(content: Text('URL schemes registered (tg://, tonsite://)')),
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
        content: Text.rich(
          TextSpan(
            children: const [
              TextSpan(text: 'Are you sure you want to reset '),
              TextSpan(
                  text: 'all',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              TextSpan(text: ' AyuGram preferences to their defaults?'),
            ],
          ),
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
        ),
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
            child: Text('Yes',
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
            // Flat row: icon + label only. AyuGram builds these with
            // AddButtonWithIcon(..., st::settingsButton), whose style defines no
            // right arrow/chevron (settings.style:13-17) — they open a URL or a
            // QR modal, not a drill-down, so no chevron is drawn
            // (settings_other.cpp:124-129). Matches the sibling _ActionButton.
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
  void didUpdateWidget(_SupportDescription oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onSupportTap != widget.onSupportTap) {
      _recognizer.onTap = widget.onSupportTap;
    }
  }

  @override
  void dispose() {
    _recognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // AyuGram builds this with Ui::AddDividerText -> DividerLabel: the label
    // sits ON a full-bleed boxDividerBg band using the 14px defaultTextStyle,
    // windowSubTextFg, defaultBoxDividerLabelPadding = margins(22,8,22,16)
    // (settings_other.cpp:161-167, vertical_list.cpp:50-67, widgets.style:687-703)
    // — NOT a 12px label in a plain Padding. The "Support Development" portion is
    // a tg://support link opening the donate-info box (ayu_SupportDescription2 =
    // "{item} and get an unique badge!", ayu_SupportDescription1 =
    // "Support Development").
    final linkColor =
        widget.isDark ? const Color(0xFF6AB2F2) : const Color(0xFF3390EC);
    return Container(
      width: double.infinity,
      color: p.boxDividerBg,
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 14, color: p.windowSubTextFg),
          children: [
            TextSpan(
              text: 'Support Development',
              style: TextStyle(color: linkColor),
              recognizer: _recognizer,
            ),
            const TextSpan(text: ' and get an unique badge!'),
          ],
        ),
      ),
    );
  }
}

class _DonateInfoBox extends StatefulWidget {
  final bool isDark;

  // All RC-config fetch/parse/storage now lives in the app-wide [RcManager]
  // (utils/rc_manager.dart), a faithful 1:1 port of AyuGram's RCManager started
  // at app startup (main.dart, == ayu_infra.cpp initRCManager()). The donate box
  // is just one consumer — it reads the donate amounts/username from the manager
  // and triggers a refresh on open. The manager additionally parses the
  // developers/officialChannels/supporters/supporterChannels/customBadges sets
  // (previously dropped) that source AyuGram's developer/supporter/custom badges.

  const _DonateInfoBox({required this.isDark});

  @override
  State<_DonateInfoBox> createState() => _DonateInfoBoxState();
}

class _DonateInfoBoxState extends State<_DonateInfoBox> {
  late final TapGestureRecognizer _usernameRecognizer;

  @override
  void initState() {
    super.initState();
    // The RcManager is already started at app startup; trigger (or join) a
    // refresh and rebuild once it lands so the freshest donate amounts/username
    // show. makeRequest() dedups, so this never double-fetches.
    RcManager.instance.makeRequest().then((_) {
      if (mounted) setState(() {});
    });
    _usernameRecognizer = TapGestureRecognizer()
      ..onTap = () {
        // AyuGram navigates to the trimmed (no '@') username while showing the
        // raw one (donate_info_box.cpp:203-208). Read live so a post-fetch
        // update is honored.
        final raw = RcManager.instance.donateUsername;
        final username = raw.startsWith('@') ? raw.substring(1) : raw;
        _navigateToUsername(username);
      };
  }

  void _navigateToUsername(String username) {
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    if (accountId.isEmpty) {
      launchUrl(Uri.parse('https://t.me/$username'),
          mode: LaunchMode.externalApplication);
      return;
    }
    final engine = context.read<EngineService>();
    engine.resolveUsername(accountId, username).then((chatId) {
      if (chatId != null && chatId.isNotEmpty && mounted) {
        Navigator.of(context).pop();
        context.read<ChatState>().openChatById(chatId);
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        launchUrl(Uri.parse('https://t.me/$username'),
            mode: LaunchMode.externalApplication);
      }
    }).catchError((_) {
      launchUrl(Uri.parse('https://t.me/$username'),
          mode: LaunchMode.externalApplication);
    });
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
      // AyuGram pins the box to int(aboutWidth * 1.1) = int(390 * 1.1) = 429
      // (donate_info_box.cpp:134, boxes.style aboutWidth: 390px). Without it
      // the Material Dialog stretches to nearly the full settings-window
      // width; the cap still shrinks to fit narrow (mobile) screens.
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 429),
        child: Stack(
          children: [
            Padding(
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
                  Text('Support Development',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: textColor)),
                  const SizedBox(height: 12),
                  Text(
                    'By supporting the project, you not only contribute to its '
                    'development but also get a unique badge.',
                    style: TextStyle(fontSize: 13, color: subtextColor),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  _DonateInfoRow(
                    icon: Icons.monetization_on,
                    title: 'Make a Donation',
                    descriptionSpan: TextSpan(
                      children: [
                        TextSpan(
                            text: 'Transfer an amount of '
                                '\$${RcManager.instance.donateAmountUsd} ('),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: SvgPicture.asset(
                            'assets/icons/ayu/donates/ton.svg',
                            width: 13,
                            height: 13,
                          ),
                        ),
                        TextSpan(
                            text: '${RcManager.instance.donateAmountTon}, '
                                '${RcManager.instance.donateAmountRub}₽) to any of '
                                "the project's payment details. These can be "
                                'found in the '),
                        const TextSpan(
                            text: 'Other',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const TextSpan(text: ' section of the app settings.'),
                      ],
                    ),
                    textColor: textColor,
                    subtextColor: subtextColor,
                  ),
                  const SizedBox(height: 12),
                  _DonateInfoRow(
                    icon: Icons.photo_camera,
                    title: 'Send Proof of Payment',
                    descriptionSpan: TextSpan(
                      children: [
                        const TextSpan(
                            text: 'Send a photo of the payment confirmation '
                                'to '),
                        TextSpan(
                          // Raw username as shown by AyuGram (donate_info_box.cpp:208
                          // uses the un-trimmed value as the link text); the default
                          // "@ayugramOwner" already carries the '@'.
                          text: RcManager.instance.donateUsername,
                          style: TextStyle(
                              color: accentColor,
                              fontWeight: FontWeight.w600),
                          recognizer: _usernameRecognizer,
                        ),
                        const TextSpan(
                            text: '. Make sure the photo clearly shows the '
                                'amount, date, and time of the transfer.'),
                      ],
                    ),
                    textColor: textColor,
                    subtextColor: subtextColor,
                  ),
                  const SizedBox(height: 12),
                  _DonateInfoRow(
                    icon: Icons.verified,
                    title: 'Receive Your Badge',
                    description:
                        'After payment verification, you will receive a unique '
                        'badge that will be displayed on your profile and '
                        'visible to other users.',
                    textColor: textColor,
                    subtextColor: subtextColor,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child:
                          Text('Close', style: TextStyle(color: accentColor)),
                    ),
                  ),
                ],
              ),
            ),
            // Top-right close button — mirrors AyuGram
            // `box->addTopButton(st::boxTitleClose, ...)`
            // (donate_info_box.cpp:137), in addition to the bottom Close button.
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Icon(Icons.close, size: 20, color: subtextColor),
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

    void copyAddress() {
      Clipboard.setData(ClipboardData(text: address));
      // Single copy path — matches AyuGram's lone copy button showing
      // `Ui::Toast::Show(tr::lng_text_copied)` (donate_qr_box.cpp:148-151).
      showTelegramToast(context, 'Text copied to clipboard');
    }

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // AyuGram sizes the box to int(aboutWidth * 1.25) = int(390 * 1.25)
          // = 487 and fills the QR to the box width minus boxRowPadding
          // (donate_qr_box.cpp:77,94). Cap to the available width so the box
          // still fits narrow (mobile) screens.
          const ayuBoxWidth = 487.0;
          final boxWidth = math.min(ayuBoxWidth, constraints.maxWidth);
          // QR fills the box minus the dialog padding (24*2) and the white
          // QR-container padding (12*2), replacing the old fixed 180px.
          final qrSize =
              (boxWidth - 48 - 24).clamp(120.0, ayuBoxWidth).toDouble();
          // Center logo scales with the QR (C++ kCenterRatio = 0.20,
          // donate_qr_box.cpp:54-65) instead of a fixed 36px square.
          final centerSize = qrSize * 0.20;
          return SizedBox(
            width: boxWidth,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(width: 32),
                      Text('Get QR Code',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: textColor)),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child:
                            Icon(Icons.close, size: 20, color: subtextColor),
                      ),
                    ],
                  ),
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
                          size: qrSize,
                          eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: Colors.black),
                          dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: Colors.black),
                        ),
                        Container(
                          width: centerSize,
                          height: centerSize,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: SvgPicture.asset(
                            svgAsset,
                            width: centerSize,
                            height: centerSize,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Address display — a plain label (no tap-to-copy), like
                  // AyuGram's InviteLinkLabel; the copy button below is the
                  // only copy path (donate_qr_box.cpp:142-158).
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1B2836)
                          : const Color(0xFFF0F0F0),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      address,
                      style: TextStyle(
                        fontSize: 13,
                        color: subtextColor,
                        fontFamily: 'monospace',
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: copyAddress,
                      child:
                          Text('Copy', style: TextStyle(color: buttonColor)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

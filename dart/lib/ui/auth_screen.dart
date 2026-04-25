import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/engine_models.dart';
import '../state/auth_state.dart';
import 'settings_screen.dart';

/// Authentication screen. Spec §11.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _inputController = TextEditingController();

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _submit(AuthState authState) {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    authState.submitInput(text);
    _inputController.clear();
  }

  bool _canGoBack(AuthStateData? data) {
    if (data == null) return false;
    return switch (data.state) {
      'input' || 'otp' || '2fa' || 'qr' => true,
      _ => false,
    };
  }

  bool _showNext(AuthStateData? data) {
    if (data == null) return false;
    return switch (data.state) {
      'input' || 'otp' || '2fa' => true,
      _ => false,
    };
  }

  String _nextButtonText(AuthStateData? data) {
    if (data == null) return 'Next';
    return switch (data.state) {
      'otp' => 'Next',
      '2fa' => 'Submit',
      _ => 'Next',
    };
  }

  bool _showResetAccount(AuthStateData? data) {
    if (data == null) return false;
    return data.state == '2fa' && !data.hasRecovery;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = context.watch<AuthState>();
    final data = authState.currentAuth;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outlined,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _title(data),
                    style: theme.textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  if (data?.label.isNotEmpty == true)
                    Text(
                      data!.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.textTheme.bodySmall?.color,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  if (data?.hint.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Hint: ${data!.hint}',
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (authState.error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        authState.error!,
                        style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (data?.state == 'choose' && data!.options.isNotEmpty)
                    ..._buildChoices(data.options, authState, theme),
                  if (data?.state == 'qr' && data!.qrData.isNotEmpty)
                    _buildQR(data, theme),
                  if (data?.state == 'input' || data?.state == 'otp' || data?.state == '2fa')
                    _buildInput(data!, authState, theme),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: _AuthBottomBar(
        showNext: _showNext(data),
        nextText: _nextButtonText(data),
        submitting: authState.submitting,
        canGoBack: _canGoBack(data),
        showResetAccount: _showResetAccount(data),
        onNext: () => _submit(authState),
        onBack: () => authState.cancelAuth(),
        onSettings: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        ),
        onResetAccount: () => _showResetAccountDialog(context),
      ),
    );
  }

  void _showResetAccountDialog(BuildContext context) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Account'),
        content: Text(
          'Since this account has no recovery email, you can reset it. '
          'This will delete your account after a 7-day waiting period. '
          'Your chats, messages, and contacts will be permanently lost.',
          style: theme.textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
            },
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            child: const Text('Reset Account'),
          ),
        ],
      ),
    );
  }

  String _title(AuthStateData? data) {
    if (data == null) return 'Authenticating...';
    return switch (data.state) {
      'choose' => 'Choose Login Method',
      'input' => data.fieldType == 'phone' ? 'Enter Phone Number' : 'Enter ${data.fieldType}',
      'otp' => 'Enter Verification Code',
      '2fa' => 'Two-Factor Authentication',
      'qr' => 'Scan QR Code',
      'ready' => 'Authenticated!',
      'error' => 'Authentication Error',
      _ => 'Authenticating...',
    };
  }

  List<Widget> _buildChoices(
      List<AuthOption> options, AuthState authState, ThemeData theme) {
    return [
      for (final opt in options)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton(
              onPressed: authState.submitting
                  ? null
                  : () {
                      authState.submitInput(opt.id);
                    },
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(opt.label),
            ),
          ),
        ),
    ];
  }

  Widget _buildQR(AuthStateData data, ThemeData theme) {
    final payload = utf8.decode(data.qrData, allowMalformed: true);
    return Column(
      children: [
        Container(
          width: 180,
          height: 180,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: QrImageView(
            data: payload,
            version: QrVersions.auto,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Colors.black,
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Colors.black,
            ),
            errorCorrectionLevel: QrErrorCorrectLevel.M,
            gapless: true,
          ),
        ),
        const SizedBox(height: 12),
        Text('Open Telegram on your phone', style: theme.textTheme.bodyMedium),
        Text('Go to Settings > Devices > Link Desktop Device',
            style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
      ],
    );
  }

  Widget _buildInput(AuthStateData data, AuthState authState, ThemeData theme) {
    final isPassword = data.state == '2fa';
    final isOtp = data.state == 'otp';

    return Column(
      children: [
        if (data.sentTo.isNotEmpty) ...[
          Text('Code sent to ${data.sentTo}',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
        ],
        SizedBox(
          width: 300,
          child: TextField(
            controller: _inputController,
            obscureText: isPassword,
            keyboardType: isOtp ? TextInputType.number : TextInputType.text,
            autofocus: true,
            maxLength: isOtp && data.codeLength > 0 ? data.codeLength : null,
            onSubmitted: (_) => _submit(authState),
            decoration: InputDecoration(
              hintText: data.hint.isNotEmpty ? data.hint : null,
              counterText: '',
            ),
          ),
        ),
      ],
    );
  }
}

/// Persistent bottom bar for auth screens. Spec §11.1.
class _AuthBottomBar extends StatelessWidget {
  final bool showNext;
  final String nextText;
  final bool submitting;
  final bool canGoBack;
  final bool showResetAccount;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final VoidCallback onSettings;
  final VoidCallback onResetAccount;

  const _AuthBottomBar({
    required this.showNext,
    required this.nextText,
    required this.submitting,
    required this.canGoBack,
    required this.showResetAccount,
    required this.onNext,
    required this.onBack,
    required this.onSettings,
    required this.onResetAccount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showNext)
              SizedBox(
                width: 300,
                height: 42,
                child: FilledButton(
                  onPressed: submitting ? null : onNext,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(nextText),
                ),
              ),
            if (showResetAccount) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onResetAccount,
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                child: const Text('Reset Account'),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                if (canGoBack)
                  IconButton(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Back',
                    iconSize: 20,
                  ),
                if (!canGoBack)
                  const SizedBox(width: 40),
                const Spacer(),
                TextButton(
                  onPressed: () => _showLanguageDialog(context),
                  child: Text(
                    'Change Language',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: onSettings,
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Settings',
                  iconSize: 20,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showLanguageDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Choose Language'),
        children: [
          RadioListTile<String>(
            title: const Text('English'),
            value: 'en',
            groupValue: 'en',
            onChanged: (_) => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/engine_models.dart';
import '../state/auth_state.dart';

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = context.watch<AuthState>();
    final data = authState.currentAuth;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Platform icon.
                Icon(
                  Icons.lock_outlined,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                // Title.
                Text(
                  _title(data),
                  style: theme.textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                // Description.
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
                // Error.
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
                // Auth method choice.
                if (data?.state == 'choose' && data!.options.isNotEmpty)
                  ..._buildChoices(data.options, authState, theme),
                // QR code.
                if (data?.state == 'qr' && data!.qrData.isNotEmpty)
                  _buildQR(data, theme),
                // Input field (phone, OTP, 2FA).
                if (data?.state == 'input' || data?.state == 'otp' || data?.state == '2fa')
                  _buildInput(data!, authState, theme),
                const SizedBox(height: 16),
                // Cancel button.
                TextButton(
                  onPressed: () => authState.cancelAuth(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
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
    // QR data is raw bytes — show as placeholder for now.
    // TODO: render QR from data.qrData bytes.
    return Column(
      children: [
        Container(
          width: 180,
          height: 180,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Icon(Icons.qr_code_2, size: 120, color: theme.colorScheme.primary),
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
        const SizedBox(height: 16),
        SizedBox(
          width: 300,
          height: 42,
          child: FilledButton(
            onPressed: authState.submitting ? null : () => _submit(authState),
            child: authState.submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Next'),
          ),
        ),
      ],
    );
  }
}

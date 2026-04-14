import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../state/auth_state.dart';
import '../models/engine_models.dart';
import '../theme/theme.dart';

/// Auth flow dialog — handles all 7 auth states for any platform.
class AuthScreen extends StatefulWidget {
  final String accountId;
  final String platform;

  const AuthScreen({
    super.key,
    required this.accountId,
    required this.platform,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _inputController = TextEditingController();
  bool _obscureText = false;

  @override
  void initState() {
    super.initState();
    // Start the auth flow.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthState>().startAuth(widget.accountId);
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthState>();
    final auth = authState.currentAuth;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, minWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  const Icon(Icons.lock_outline, color: AppColors.accent, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Sign in to ${_platformLabel(widget.platform)}',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () {
                      authState.cancelAuth();
                      Navigator.pop(context);
                    },
                    splashRadius: 16,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Body — varies by auth state
              if (auth == null)
                const Center(child: CircularProgressIndicator())
              else
                _buildAuthBody(context, auth, authState),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuthBody(BuildContext context, AuthStateData auth, AuthState authState) {
    return switch (auth.state) {
      'choose' => _buildChooseState(context, auth, authState),
      'input'  => _buildInputState(context, auth, authState),
      'otp'    => _buildOTPState(context, auth, authState),
      '2fa'    => _build2FAState(context, auth, authState),
      'qr'     => _buildQRState(context, auth, authState),
      'ready'  => _buildReadyState(context, auth),
      'error'  => _buildErrorState(context, auth, authState),
      _        => const Center(child: CircularProgressIndicator()),
    };
  }

  // ── Choose: pick auth method ──
  Widget _buildChooseState(BuildContext context, AuthStateData auth, AuthState authState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (auth.label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(auth.label, style: Theme.of(context).textTheme.bodyLarge),
          ),
        for (final option in auth.options)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              onPressed: authState.submitting ? null : () => authState.submitInput(option.id),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: AppColors.accent),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(option.label),
            ),
          ),
      ],
    );
  }

  // ── Input: text field (phone, username, etc.) ──
  Widget _buildInputState(BuildContext context, AuthStateData auth, AuthState authState) {
    _obscureText = auth.fieldType == 'password';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(auth.label.isNotEmpty ? auth.label : 'Enter your credentials',
            style: Theme.of(context).textTheme.bodyLarge),
        if (auth.hint.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(auth.hint, style: Theme.of(context).textTheme.bodySmall),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _inputController,
          obscureText: _obscureText,
          autofocus: true,
          onSubmitted: authState.submitting ? null : (_) => _submit(authState),
          decoration: InputDecoration(
            hintText: auth.hint.isNotEmpty ? auth.hint : auth.label,
            prefixIcon: Icon(_fieldIcon(auth.fieldType)),
          ),
        ),
        if (auth.error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(auth.error, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          ),
        const SizedBox(height: 16),
        _buildSubmitButton(authState),
      ],
    );
  }

  // ── OTP: code entry ──
  Widget _buildOTPState(BuildContext context, AuthStateData auth, AuthState authState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.sms_outlined, size: 48, color: AppColors.accent),
        const SizedBox(height: 12),
        Text(
          auth.label.isNotEmpty ? auth.label : 'Enter the code',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        if (auth.sentTo.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Sent to ${auth.sentTo}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ),
        const SizedBox(height: 16),
        TextField(
          controller: _inputController,
          autofocus: true,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: auth.codeLength > 0 ? auth.codeLength : null,
          onSubmitted: authState.submitting ? null : (_) => _submit(authState),
          style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            counterText: '',
            hintText: auth.codeLength > 0 ? '0' * auth.codeLength : '000000',
          ),
        ),
        if (auth.error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(auth.error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          ),
        const SizedBox(height: 16),
        _buildSubmitButton(authState),
        if (auth.canResend)
          TextButton(
            onPressed: () => authState.submitInput('__resend'),
            child: const Text('Resend code'),
          ),
      ],
    );
  }

  // ── 2FA: two-factor password ──
  Widget _build2FAState(BuildContext context, AuthStateData auth, AuthState authState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.shield_outlined, size: 48, color: AppColors.accent),
        const SizedBox(height: 12),
        Text(
          auth.label.isNotEmpty ? auth.label : 'Two-factor authentication',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _inputController,
          obscureText: true,
          autofocus: true,
          onSubmitted: authState.submitting ? null : (_) => _submit(authState),
          decoration: const InputDecoration(
            hintText: 'Password',
            prefixIcon: Icon(Icons.lock),
          ),
        ),
        if (auth.error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(auth.error, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          ),
        const SizedBox(height: 16),
        _buildSubmitButton(authState),
        if (auth.hasRecovery)
          TextButton(
            onPressed: () => authState.submitInput('__recovery'),
            child: const Text('Forgot password?'),
          ),
      ],
    );
  }

  // ── QR: scan QR code ──
  Widget _buildQRState(BuildContext context, AuthStateData auth, AuthState authState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          auth.label.isNotEmpty ? auth.label : 'Scan QR code with your phone',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        // QR code placeholder — actual rendering requires qr_flutter package
        Container(
          height: 200,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(
            child: Icon(Icons.qr_code_2, size: 160, color: Colors.black87),
          ),
        ),
        if (auth.timeoutSecs > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Expires in ${auth.timeoutSecs}s',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () => authState.cancelAuth(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  // ── Ready: auth complete ──
  Widget _buildReadyState(BuildContext context, AuthStateData auth) {
    return Column(
      children: [
        const Icon(Icons.check_circle_outline, size: 64, color: AppColors.online),
        const SizedBox(height: 16),
        Text(
          auth.displayName.isNotEmpty
              ? 'Welcome, ${auth.displayName}!'
              : 'Successfully signed in!',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        if (auth.message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(auth.message, textAlign: TextAlign.center),
          ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () {
            context.read<EngineService>().connectAccount(widget.accountId);
            context.read<AuthState>().clear();
            Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Continue'),
        ),
      ],
    );
  }

  // ── Error: auth failed ──
  Widget _buildErrorState(BuildContext context, AuthStateData auth, AuthState authState) {
    return Column(
      children: [
        const Icon(Icons.error_outline, size: 64, color: AppColors.danger),
        const SizedBox(height: 16),
        Text(
          'Authentication failed',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          auth.error.isNotEmpty ? auth.error : 'Unknown error',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.danger),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (auth.recoverable)
              ElevatedButton(
                onPressed: () => authState.startAuth(widget.accountId),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Try again'),
              ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: () {
                authState.clear();
                Navigator.pop(context);
              },
              child: const Text('Close'),
            ),
          ],
        ),
      ],
    );
  }

  // ── Helpers ──

  Widget _buildSubmitButton(AuthState authState) {
    return ElevatedButton(
      onPressed: authState.submitting ? null : () => _submit(authState),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: authState.submitting
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Text('Continue'),
    );
  }

  void _submit(AuthState authState) {
    final input = _inputController.text.trim();
    if (input.isEmpty) return;
    authState.submitInput(input);
    _inputController.clear();
  }

  IconData _fieldIcon(String fieldType) => switch (fieldType) {
    'phone' => Icons.phone,
    'email' => Icons.email,
    'password' => Icons.lock,
    'token' => Icons.key,
    'username' => Icons.person,
    _ => Icons.edit,
  };

  String _platformLabel(String platform) => switch (platform) {
    'telegram' => 'Telegram',
    'bale' => 'Bale',
    'matrix' => 'Matrix',
    'irc' => 'IRC',
    'xmpp' => 'XMPP',
    'github' => 'GitHub',
    'rubika' => 'Rubika',
    'deltachat' => 'Delta Chat',
    'teamspeak' => 'TeamSpeak',
    'mumble' => 'Mumble',
    _ => platform,
  };
}

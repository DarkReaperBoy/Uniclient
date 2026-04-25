import 'dart:convert';
import 'dart:math';

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

class _AuthScreenState extends State<AuthScreen>
    with TickerProviderStateMixin {
  final _inputController = TextEditingController();
  String _prevStep = '';
  bool _isForward = true;
  bool _isCover = false;

  late final AnimationController _shakeController;
  bool _showErrorBorder = false;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _shakeController.reset();
        }
      });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  static int _stepOrder(String s) => switch (s) {
    'choose' => 0,
    'qr' => 1,
    'input' => 2,
    'otp' => 3,
    '2fa' => 4,
    'ready' || 'error' => 5,
    _ => -1,
  };

  static bool _hasCover(String s) => s == 'qr' || s == 'input';

  void _submit(AuthState authState) {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    setState(() => _showErrorBorder = false);
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
    final currentStep = data?.state ?? '';

    if (currentStep != _prevStep && _prevStep.isNotEmpty && currentStep.isNotEmpty) {
      _isForward = _stepOrder(currentStep) >= _stepOrder(_prevStep);
      _isCover = _hasCover(_prevStep) && _hasCover(currentStep);
    }
    if (currentStep.isNotEmpty) {
      _prevStep = currentStep;
    }

    final err = authState.error;
    if (err != null && err != _lastError) {
      _showErrorBorder = true;
      _shakeController.forward(from: 0);
    }
    if (err == null && _showErrorBorder) {
      _showErrorBorder = false;
    }
    _lastError = err;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, animation) {
                  final isIncoming = child.key == ValueKey(currentStep);
                  final curve = _isCover ? Curves.easeOutCirc : Curves.linear;
                  final curved = CurvedAnimation(parent: animation, curve: curve);
                  final slideBegin = isIncoming
                      ? Offset(_isForward ? 0.5 : -0.5, 0.0)
                      : Offset(_isForward ? -0.5 : 0.5, 0.0);
                  return ClipRect(
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: slideBegin,
                        end: Offset.zero,
                      ).animate(curved),
                      child: FadeTransition(
                        opacity: curved,
                        child: child,
                      ),
                    ),
                  );
                },
                layoutBuilder: (currentChild, previousChildren) {
                  return Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      ...previousChildren,
                      if (currentChild != null) currentChild,
                    ],
                  );
                },
                child: _buildStepContent(data, authState, theme),
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

  Widget _buildStepContent(
      AuthStateData? data, AuthState authState, ThemeData theme) {
    final state = data?.state ?? '';
    return Column(
      key: ValueKey(state),
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
        if (data?.state == 'qr')
          _buildQR(data, authState, theme),
        if (data?.state == 'input' || data?.state == 'otp' || data?.state == '2fa')
          _buildInput(data!, authState, theme),
      ],
    );
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

  Widget _buildQR(AuthStateData? data, AuthState authState, ThemeData theme) {
    final hasQr = data != null && data.qrData.isNotEmpty;
    final payload = hasQr ? utf8.decode(data.qrData, allowMalformed: true) : '';
    const qrSize = 180.0;
    const cardPadding = 12.0;
    const cardSize = qrSize + cardPadding * 2;
    const logoSize = 44.0;

    return Column(
      children: [
        SizedBox(
          width: cardSize,
          height: cardSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedOpacity(
                opacity: hasQr ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 300),
                child: SizedBox(
                  width: qrSize,
                  height: qrSize,
                  child: const CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation(Color(0xFF40A7E3)),
                  ),
                ),
              ),
              AnimatedOpacity(
                opacity: hasQr ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  width: cardSize,
                  height: cardSize,
                  padding: const EdgeInsets.all(cardPadding),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (hasQr)
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: QrImageView(
                            key: ValueKey(payload),
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
                            errorCorrectionLevel: QrErrorCorrectLevel.Q,
                            gapless: true,
                          ),
                        ),
                      Container(
                        width: logoSize,
                        height: logoSize,
                        decoration: const BoxDecoration(
                          color: Color(0xFF40A7E3),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.send,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildInstruction(1, 'Open Telegram on your phone', theme),
        const SizedBox(height: 8),
        _buildInstruction(
            2, 'Go to Settings → Devices → Link Desktop Device', theme),
        const SizedBox(height: 8),
        _buildInstruction(
            3, 'Point your phone at this screen to confirm login', theme),
        const SizedBox(height: 20),
        TextButton(
          onPressed: () => authState.switchToMethod('phone'),
          child: const Text(
            'Log in by phone number',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF40A7E3),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInstruction(int number, String text, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            child: Text(
              '$number.',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(text, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
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
        AnimatedBuilder(
          animation: _shakeController,
          builder: (context, child) {
            final dx = _shakeController.isAnimating
                ? sin(_shakeController.value * pi * 4) *
                    6 *
                    (1 - _shakeController.value)
                : 0.0;
            return Transform.translate(
              offset: Offset(dx, 0),
              child: child,
            );
          },
          child: SizedBox(
            width: 300,
            child: TextField(
              controller: _inputController,
              obscureText: isPassword,
              keyboardType:
                  isOtp ? TextInputType.number : TextInputType.text,
              autofocus: true,
              maxLength:
                  isOtp && data.codeLength > 0 ? data.codeLength : null,
              onSubmitted: (_) => _submit(authState),
              decoration: InputDecoration(
                hintText: data.hint.isNotEmpty ? data.hint : null,
                counterText: '',
                enabledBorder: _showErrorBorder
                    ? OutlineInputBorder(
                        borderSide: BorderSide(
                          color: theme.colorScheme.error,
                          width: 2,
                        ),
                      )
                    : null,
                focusedBorder: _showErrorBorder
                    ? OutlineInputBorder(
                        borderSide: BorderSide(
                          color: theme.colorScheme.error,
                          width: 2,
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Persistent bottom bar for auth screens. Spec §11.1.
class _AuthBottomBar extends StatefulWidget {
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
  State<_AuthBottomBar> createState() => _AuthBottomBarState();
}

class _AuthBottomBarState extends State<_AuthBottomBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slideController;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
      value: widget.showNext ? 1.0 : 0.0,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 200),
      end: Offset.zero,
    ).animate(_slideController);
    _fadeAnim = _slideController;
  }

  @override
  void didUpdateWidget(_AuthBottomBar old) {
    super.didUpdateWidget(old);
    if (widget.showNext != old.showNext) {
      if (widget.showNext) {
        _slideController.forward();
      } else {
        _slideController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _slideController,
              builder: (context, child) {
                if (_slideController.isDismissed) {
                  return const SizedBox.shrink();
                }
                return Transform.translate(
                  offset: _slideAnim.value,
                  child: Opacity(
                    opacity: _fadeAnim.value,
                    child: child,
                  ),
                );
              },
              child: SizedBox(
                width: 300,
                height: 42,
                child: FilledButton(
                  onPressed: widget.submitting ? null : widget.onNext,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    padding: const EdgeInsets.only(top: 11, bottom: 17),
                  ),
                  child: widget.submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(widget.nextText),
                ),
              ),
            ),
            if (widget.showResetAccount) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: widget.onResetAccount,
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
                child: const Text('Reset Account'),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                if (widget.canGoBack)
                  IconButton(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Back',
                    iconSize: 20,
                  ),
                if (!widget.canGoBack)
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
                  onPressed: widget.onSettings,
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

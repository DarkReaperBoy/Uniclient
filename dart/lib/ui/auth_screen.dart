import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  _PhoneErrorType? _phoneErrorType;
  Timer? _floodTimer;
  int _floodSecondsLeft = 0;

  final _codeController = TextEditingController();
  final _phoneController = TextEditingController();
  late _CountryInfo _selectedCountry;

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
    _selectedCountry = _countries.firstWhere((c) => c.iso == 'US');
    _codeController.text = _selectedCountry.dialCode;
  }

  @override
  void dispose() {
    _inputController.dispose();
    _codeController.dispose();
    _phoneController.dispose();
    _shakeController.dispose();
    _floodTimer?.cancel();
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
    final data = authState.currentAuth;
    if (data?.state == 'input' && data?.fieldType == 'phone') {
      final code = _codeController.text.replaceAll(RegExp(r'\D'), '');
      final phone = _phoneController.text.replaceAll(RegExp(r'\D'), '');
      if (code.isEmpty || phone.length < 2) return;
      setState(() => _showErrorBorder = false);
      authState.submitInput('+$code$phone');
      return;
    }
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
      _phoneErrorType = _classifyPhoneError(err);
      if (_phoneErrorType == _PhoneErrorType.banned) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showBannedDialog(context, err);
        });
      } else if (_phoneErrorType == _PhoneErrorType.flood) {
        _startFloodCountdown(err);
      }
      _showErrorBorder = true;
      _shakeController.forward(from: 0);
    }
    if (err == null && _showErrorBorder) {
      _showErrorBorder = false;
      _phoneErrorType = null;
      _floodTimer?.cancel();
      _floodSecondsLeft = 0;
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
        if (authState.error != null && !_isPhoneScreenError(data)) ...[
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
    final isPhone = data.state == 'input' && data.fieldType == 'phone';

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
          child: isPhone
              ? _buildPhoneFields(authState, theme)
              : SizedBox(
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

  Widget _buildPhoneFields(AuthState authState, ThemeData theme) {
    final errBorder = _showErrorBorder
        ? BorderSide(color: theme.colorScheme.error, width: 2)
        : null;
    return Column(
      children: [
        GestureDetector(
          onTap: () => _showCountryPicker(theme),
          child: Container(
            width: 300,
            constraints: const BoxConstraints(minHeight: 61),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(
                color: errBorder?.color ?? theme.dividerColor,
                width: errBorder?.width ?? 1,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Text(_selectedCountry.flag,
                    style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedCountry.name,
                    style: theme.textTheme.bodyLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.arrow_drop_down, color: theme.hintColor),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 300,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 64,
                child: TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  onChanged: _onCodeChanged,
                  decoration: InputDecoration(
                    prefixText: '+',
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
                    border: const OutlineInputBorder(),
                    enabledBorder: errBorder != null
                        ? OutlineInputBorder(borderSide: errBorder)
                        : null,
                    focusedBorder: errBorder != null
                        ? OutlineInputBorder(borderSide: errBorder)
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  autofocus: true,
                  inputFormatters: [_PhoneNumberFormatter()],
                  onSubmitted: (_) => _submit(authState),
                  decoration: InputDecoration(
                    hintText: 'Phone number',
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 16),
                    border: const OutlineInputBorder(),
                    enabledBorder: errBorder != null
                        ? OutlineInputBorder(borderSide: errBorder)
                        : null,
                    focusedBorder: errBorder != null
                        ? OutlineInputBorder(borderSide: errBorder)
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_phoneErrorType == _PhoneErrorType.invalid) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: 300,
            child: Text(
              'Invalid phone number. Please check and try again.',
              style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
            ),
          ),
        ],
        if (_phoneErrorType == _PhoneErrorType.flood) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: 300,
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: theme.colorScheme.error, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _floodSecondsLeft > 0
                        ? 'Too many attempts. Try again in ${_formatFloodTime(_floodSecondsLeft)}.'
                        : 'Too many attempts. Please try again later.',
                    style:
                        TextStyle(color: theme.colorScheme.error, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  _PhoneErrorType? _classifyPhoneError(String error) {
    final upper = error.toUpperCase();
    if (upper.contains('PHONE_NUMBER_BANNED')) return _PhoneErrorType.banned;
    if (upper.contains('PHONE_NUMBER_INVALID')) return _PhoneErrorType.invalid;
    if (upper.contains('FLOOD_WAIT') || upper.contains('FLOOD_')) {
      return _PhoneErrorType.flood;
    }
    return null;
  }

  bool _isPhoneScreenError(AuthStateData? data) {
    if (data == null) return false;
    if (data.state != 'input' || data.fieldType != 'phone') return false;
    return _phoneErrorType != null;
  }

  void _startFloodCountdown(String error) {
    _floodTimer?.cancel();
    final match = RegExp(r'FLOOD_WAIT[_\s]*(\d+)', caseSensitive: false)
        .firstMatch(error);
    _floodSecondsLeft = match != null ? int.parse(match.group(1)!) : 0;
    if (_floodSecondsLeft > 0) {
      _floodTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _floodSecondsLeft--;
          if (_floodSecondsLeft <= 0) {
            timer.cancel();
            _floodTimer = null;
          }
        });
      });
    }
  }

  String _formatFloodTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0) return '$m:${s.toString().padLeft(2, '0')}';
    return '${s}s';
  }

  void _showBannedDialog(BuildContext context, String error) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Phone Number Banned'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This phone number has been banned from Telegram.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              'If you think this is a mistake, please contact Telegram support:',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            SelectableText(
              'login@stel.com',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _onCodeChanged(String val) {
    final code = val.replaceAll(RegExp(r'\D'), '');
    if (code.isEmpty) return;
    final match = _countries.where((c) => c.dialCode == code).firstOrNull;
    if (match != null && match != _selectedCountry) {
      setState(() => _selectedCountry = match);
    }
  }

  void _showCountryPicker(ThemeData theme) {
    showDialog(
      context: context,
      builder: (ctx) => _CountryPickerDialog(
        selected: _selectedCountry,
        onSelect: (country) {
          setState(() {
            _selectedCountry = country;
            _codeController.text = country.dialCode;
          });
          Navigator.of(ctx).pop();
        },
      ),
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

class _CountryPickerDialog extends StatefulWidget {
  final _CountryInfo selected;
  final void Function(_CountryInfo) onSelect;
  const _CountryPickerDialog(
      {super.key, required this.selected, required this.onSelect});
  @override
  State<_CountryPickerDialog> createState() => _CountryPickerDialogState();
}

class _CountryPickerDialogState extends State<_CountryPickerDialog> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _query.isEmpty
        ? _countries
        : _countries
            .where((c) =>
                c.name.toLowerCase().contains(_query) ||
                c.dialCode.contains(_query) ||
                c.iso.toLowerCase().contains(_query))
            .toList();

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360, maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search country',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v.toLowerCase()),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final c = filtered[i];
                  final isSelected = c.iso == widget.selected.iso;
                  return ListTile(
                    dense: true,
                    selected: isSelected,
                    leading:
                        Text(c.flag, style: const TextStyle(fontSize: 22)),
                    title:
                        Text(c.name, style: const TextStyle(fontSize: 14)),
                    trailing: Text('+${c.dialCode}',
                        style: TextStyle(
                          fontSize: 14,
                          color: theme.textTheme.bodySmall?.color,
                        )),
                    onTap: () => widget.onSelect(c),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 3 == 0) buf.write(' ');
      buf.write(digits[i]);
    }
    final formatted = buf.toString();
    final digitsBeforeCursor = newValue.text
        .substring(0, newValue.selection.end.clamp(0, newValue.text.length))
        .replaceAll(RegExp(r'\D'), '')
        .length;
    var cursor = 0;
    var count = 0;
    for (var i = 0; i < formatted.length && count < digitsBeforeCursor; i++) {
      cursor = i + 1;
      if (formatted[i] != ' ') count++;
    }
    return TextEditingValue(
      text: formatted,
      selection:
          TextSelection.collapsed(offset: cursor.clamp(0, formatted.length)),
    );
  }
}

class _CountryInfo {
  final String name;
  final String iso;
  final String dialCode;
  const _CountryInfo(this.name, this.iso, this.dialCode);
  String get flag => String.fromCharCodes(
        iso.codeUnits.map((c) => 0x1F1E6 - 0x41 + c),
      );
}

const _countries = <_CountryInfo>[
  _CountryInfo('Afghanistan', 'AF', '93'),
  _CountryInfo('Albania', 'AL', '355'),
  _CountryInfo('Algeria', 'DZ', '213'),
  _CountryInfo('Andorra', 'AD', '376'),
  _CountryInfo('Angola', 'AO', '244'),
  _CountryInfo('Antigua and Barbuda', 'AG', '1268'),
  _CountryInfo('Argentina', 'AR', '54'),
  _CountryInfo('Armenia', 'AM', '374'),
  _CountryInfo('Australia', 'AU', '61'),
  _CountryInfo('Austria', 'AT', '43'),
  _CountryInfo('Azerbaijan', 'AZ', '994'),
  _CountryInfo('Bahamas', 'BS', '1242'),
  _CountryInfo('Bahrain', 'BH', '973'),
  _CountryInfo('Bangladesh', 'BD', '880'),
  _CountryInfo('Barbados', 'BB', '1246'),
  _CountryInfo('Belarus', 'BY', '375'),
  _CountryInfo('Belgium', 'BE', '32'),
  _CountryInfo('Belize', 'BZ', '501'),
  _CountryInfo('Benin', 'BJ', '229'),
  _CountryInfo('Bhutan', 'BT', '975'),
  _CountryInfo('Bolivia', 'BO', '591'),
  _CountryInfo('Bosnia and Herzegovina', 'BA', '387'),
  _CountryInfo('Botswana', 'BW', '267'),
  _CountryInfo('Brazil', 'BR', '55'),
  _CountryInfo('Brunei', 'BN', '673'),
  _CountryInfo('Bulgaria', 'BG', '359'),
  _CountryInfo('Burkina Faso', 'BF', '226'),
  _CountryInfo('Burundi', 'BI', '257'),
  _CountryInfo('Cambodia', 'KH', '855'),
  _CountryInfo('Cameroon', 'CM', '237'),
  _CountryInfo('Canada', 'CA', '1'),
  _CountryInfo('Cape Verde', 'CV', '238'),
  _CountryInfo('Central African Republic', 'CF', '236'),
  _CountryInfo('Chad', 'TD', '235'),
  _CountryInfo('Chile', 'CL', '56'),
  _CountryInfo('China', 'CN', '86'),
  _CountryInfo('Colombia', 'CO', '57'),
  _CountryInfo('Comoros', 'KM', '269'),
  _CountryInfo('Congo', 'CG', '242'),
  _CountryInfo('Costa Rica', 'CR', '506'),
  _CountryInfo('Croatia', 'HR', '385'),
  _CountryInfo('Cuba', 'CU', '53'),
  _CountryInfo('Cyprus', 'CY', '357'),
  _CountryInfo('Czech Republic', 'CZ', '420'),
  _CountryInfo('DR Congo', 'CD', '243'),
  _CountryInfo('Denmark', 'DK', '45'),
  _CountryInfo('Djibouti', 'DJ', '253'),
  _CountryInfo('Dominica', 'DM', '1767'),
  _CountryInfo('Dominican Republic', 'DO', '1809'),
  _CountryInfo('Ecuador', 'EC', '593'),
  _CountryInfo('Egypt', 'EG', '20'),
  _CountryInfo('El Salvador', 'SV', '503'),
  _CountryInfo('Equatorial Guinea', 'GQ', '240'),
  _CountryInfo('Eritrea', 'ER', '291'),
  _CountryInfo('Estonia', 'EE', '372'),
  _CountryInfo('Eswatini', 'SZ', '268'),
  _CountryInfo('Ethiopia', 'ET', '251'),
  _CountryInfo('Fiji', 'FJ', '679'),
  _CountryInfo('Finland', 'FI', '358'),
  _CountryInfo('France', 'FR', '33'),
  _CountryInfo('Gabon', 'GA', '241'),
  _CountryInfo('Gambia', 'GM', '220'),
  _CountryInfo('Georgia', 'GE', '995'),
  _CountryInfo('Germany', 'DE', '49'),
  _CountryInfo('Ghana', 'GH', '233'),
  _CountryInfo('Greece', 'GR', '30'),
  _CountryInfo('Grenada', 'GD', '1473'),
  _CountryInfo('Guatemala', 'GT', '502'),
  _CountryInfo('Guinea', 'GN', '224'),
  _CountryInfo('Guinea-Bissau', 'GW', '245'),
  _CountryInfo('Guyana', 'GY', '592'),
  _CountryInfo('Haiti', 'HT', '509'),
  _CountryInfo('Honduras', 'HN', '504'),
  _CountryInfo('Hong Kong', 'HK', '852'),
  _CountryInfo('Hungary', 'HU', '36'),
  _CountryInfo('Iceland', 'IS', '354'),
  _CountryInfo('India', 'IN', '91'),
  _CountryInfo('Indonesia', 'ID', '62'),
  _CountryInfo('Iran', 'IR', '98'),
  _CountryInfo('Iraq', 'IQ', '964'),
  _CountryInfo('Ireland', 'IE', '353'),
  _CountryInfo('Israel', 'IL', '972'),
  _CountryInfo('Italy', 'IT', '39'),
  _CountryInfo('Ivory Coast', 'CI', '225'),
  _CountryInfo('Jamaica', 'JM', '1876'),
  _CountryInfo('Japan', 'JP', '81'),
  _CountryInfo('Jordan', 'JO', '962'),
  _CountryInfo('Kazakhstan', 'KZ', '77'),
  _CountryInfo('Kenya', 'KE', '254'),
  _CountryInfo('Kiribati', 'KI', '686'),
  _CountryInfo('Kosovo', 'XK', '383'),
  _CountryInfo('Kuwait', 'KW', '965'),
  _CountryInfo('Kyrgyzstan', 'KG', '996'),
  _CountryInfo('Laos', 'LA', '856'),
  _CountryInfo('Latvia', 'LV', '371'),
  _CountryInfo('Lebanon', 'LB', '961'),
  _CountryInfo('Lesotho', 'LS', '266'),
  _CountryInfo('Liberia', 'LR', '231'),
  _CountryInfo('Libya', 'LY', '218'),
  _CountryInfo('Liechtenstein', 'LI', '423'),
  _CountryInfo('Lithuania', 'LT', '370'),
  _CountryInfo('Luxembourg', 'LU', '352'),
  _CountryInfo('Macao', 'MO', '853'),
  _CountryInfo('Madagascar', 'MG', '261'),
  _CountryInfo('Malawi', 'MW', '265'),
  _CountryInfo('Malaysia', 'MY', '60'),
  _CountryInfo('Maldives', 'MV', '960'),
  _CountryInfo('Mali', 'ML', '223'),
  _CountryInfo('Malta', 'MT', '356'),
  _CountryInfo('Marshall Islands', 'MH', '692'),
  _CountryInfo('Mauritania', 'MR', '222'),
  _CountryInfo('Mauritius', 'MU', '230'),
  _CountryInfo('Mexico', 'MX', '52'),
  _CountryInfo('Micronesia', 'FM', '691'),
  _CountryInfo('Moldova', 'MD', '373'),
  _CountryInfo('Monaco', 'MC', '377'),
  _CountryInfo('Mongolia', 'MN', '976'),
  _CountryInfo('Montenegro', 'ME', '382'),
  _CountryInfo('Morocco', 'MA', '212'),
  _CountryInfo('Mozambique', 'MZ', '258'),
  _CountryInfo('Myanmar', 'MM', '95'),
  _CountryInfo('Namibia', 'NA', '264'),
  _CountryInfo('Nauru', 'NR', '674'),
  _CountryInfo('Nepal', 'NP', '977'),
  _CountryInfo('Netherlands', 'NL', '31'),
  _CountryInfo('New Zealand', 'NZ', '64'),
  _CountryInfo('Nicaragua', 'NI', '505'),
  _CountryInfo('Niger', 'NE', '227'),
  _CountryInfo('Nigeria', 'NG', '234'),
  _CountryInfo('North Korea', 'KP', '850'),
  _CountryInfo('North Macedonia', 'MK', '389'),
  _CountryInfo('Norway', 'NO', '47'),
  _CountryInfo('Oman', 'OM', '968'),
  _CountryInfo('Pakistan', 'PK', '92'),
  _CountryInfo('Palau', 'PW', '680'),
  _CountryInfo('Palestine', 'PS', '970'),
  _CountryInfo('Panama', 'PA', '507'),
  _CountryInfo('Papua New Guinea', 'PG', '675'),
  _CountryInfo('Paraguay', 'PY', '595'),
  _CountryInfo('Peru', 'PE', '51'),
  _CountryInfo('Philippines', 'PH', '63'),
  _CountryInfo('Poland', 'PL', '48'),
  _CountryInfo('Portugal', 'PT', '351'),
  _CountryInfo('Qatar', 'QA', '974'),
  _CountryInfo('Romania', 'RO', '40'),
  _CountryInfo('Russia', 'RU', '7'),
  _CountryInfo('Rwanda', 'RW', '250'),
  _CountryInfo('Saint Kitts and Nevis', 'KN', '1869'),
  _CountryInfo('Saint Lucia', 'LC', '1758'),
  _CountryInfo('Saint Vincent', 'VC', '1784'),
  _CountryInfo('Samoa', 'WS', '685'),
  _CountryInfo('San Marino', 'SM', '378'),
  _CountryInfo('Saudi Arabia', 'SA', '966'),
  _CountryInfo('Senegal', 'SN', '221'),
  _CountryInfo('Serbia', 'RS', '381'),
  _CountryInfo('Seychelles', 'SC', '248'),
  _CountryInfo('Sierra Leone', 'SL', '232'),
  _CountryInfo('Singapore', 'SG', '65'),
  _CountryInfo('Slovakia', 'SK', '421'),
  _CountryInfo('Slovenia', 'SI', '386'),
  _CountryInfo('Solomon Islands', 'SB', '677'),
  _CountryInfo('Somalia', 'SO', '252'),
  _CountryInfo('South Africa', 'ZA', '27'),
  _CountryInfo('South Korea', 'KR', '82'),
  _CountryInfo('South Sudan', 'SS', '211'),
  _CountryInfo('Spain', 'ES', '34'),
  _CountryInfo('Sri Lanka', 'LK', '94'),
  _CountryInfo('Sudan', 'SD', '249'),
  _CountryInfo('Suriname', 'SR', '597'),
  _CountryInfo('Sweden', 'SE', '46'),
  _CountryInfo('Switzerland', 'CH', '41'),
  _CountryInfo('Syria', 'SY', '963'),
  _CountryInfo('Taiwan', 'TW', '886'),
  _CountryInfo('Tajikistan', 'TJ', '992'),
  _CountryInfo('Tanzania', 'TZ', '255'),
  _CountryInfo('Thailand', 'TH', '66'),
  _CountryInfo('Timor-Leste', 'TL', '670'),
  _CountryInfo('Togo', 'TG', '228'),
  _CountryInfo('Tonga', 'TO', '676'),
  _CountryInfo('Trinidad and Tobago', 'TT', '1868'),
  _CountryInfo('Tunisia', 'TN', '216'),
  _CountryInfo('Turkey', 'TR', '90'),
  _CountryInfo('Turkmenistan', 'TM', '993'),
  _CountryInfo('Tuvalu', 'TV', '688'),
  _CountryInfo('Uganda', 'UG', '256'),
  _CountryInfo('Ukraine', 'UA', '380'),
  _CountryInfo('United Arab Emirates', 'AE', '971'),
  _CountryInfo('United Kingdom', 'GB', '44'),
  _CountryInfo('United States', 'US', '1'),
  _CountryInfo('Uruguay', 'UY', '598'),
  _CountryInfo('Uzbekistan', 'UZ', '998'),
  _CountryInfo('Vanuatu', 'VU', '678'),
  _CountryInfo('Vatican City', 'VA', '379'),
  _CountryInfo('Venezuela', 'VE', '58'),
  _CountryInfo('Vietnam', 'VN', '84'),
  _CountryInfo('Yemen', 'YE', '967'),
  _CountryInfo('Zambia', 'ZM', '260'),
  _CountryInfo('Zimbabwe', 'ZW', '263'),
];

enum _PhoneErrorType { invalid, banned, flood }

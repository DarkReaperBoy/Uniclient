import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import '../theme/telegram_palette.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/engine_models.dart';
import '../state/auth_state.dart';
import '../utils/country_data.dart';
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
  final _passwordController = TextEditingController();
  String _prevStep = '';
  bool _isForward = true;
  bool _isCover = false;

  late final AnimationController _shakeController;
  bool _showErrorBorder = false;
  String? _lastError;
  _PhoneErrorType? _phoneErrorType;
  Timer? _floodTimer;
  int _floodSecondsLeft = 0;
  bool _isRecoveryMode = false;
  bool _showResetButton = false;
  final _recoveryCodeController = TextEditingController();

  final _codeController = TextEditingController();
  final _phoneController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  late CountryInfo _selectedCountry;

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
    _selectedCountry = countries.firstWhere((c) => c.iso == 'US');
    _codeController.text = _selectedCountry.dialCode;
  }

  @override
  void dispose() {
    _inputController.dispose();
    _passwordController.dispose();
    _recoveryCodeController.dispose();
    _codeController.dispose();
    _phoneController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
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
    'signup' => 5,
    'ready' || 'error' => 6,
    _ => -1,
  };

  static const _kCoverHeight = 208.0;

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
    if (data?.state == '2fa') {
      if (_isRecoveryMode) {
        final code = _recoveryCodeController.text.trim();
        if (code.isEmpty) return;
        setState(() => _showErrorBorder = false);
        authState.submitInput(code);
        return;
      }
      final pwd = _passwordController.text;
      if (pwd.isEmpty) return;
      setState(() => _showErrorBorder = false);
      authState.submitInput(pwd);
      return;
    }
    if (data?.state == 'signup') {
      final firstName = _firstNameController.text.trim();
      if (firstName.isEmpty) return;
      final lastName = _lastNameController.text.trim();
      setState(() => _showErrorBorder = false);
      authState.submitInput('$firstName\n$lastName');
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
      'input' || '2fa' || 'signup' => true,
      _ => false,
    };
  }

  String _nextButtonText(AuthStateData? data) {
    if (data == null) return 'Next';
    return switch (data.state) {
      'signup' => 'Start Messaging',
      _ => 'Next',
    };
  }

  bool _showResetAccount(AuthStateData? data) {
    if (data == null) return false;
    return data.state == '2fa' && _showResetButton;
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
      if (_prevStep == '2fa' && currentStep != '2fa') {
        _isRecoveryMode = false;
        _showResetButton = false;
        _passwordController.clear();
        _recoveryCodeController.clear();
      }
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
      if (currentStep == '2fa' && !_isRecoveryMode) {
        _passwordController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _passwordController.text.length,
        );
      }
    }
    if (err == null && _showErrorBorder) {
      _showErrorBorder = false;
      _phoneErrorType = null;
      _floodTimer?.cancel();
      _floodSecondsLeft = 0;
    }
    _lastError = err;

    final showCover = _hasCover(currentStep);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCirc,
            height: showCover ? _kCoverHeight : 0,
            child: showCover
                ? _CoverGradient(isDark: theme.brightness == Brightness.dark)
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: Center(
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
          ),
        ],
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
      '2fa' => 'Enter Your Password',
      'qr' => 'Scan QR Code',
      'signup' => 'Your Name',
      'ready' => 'Authenticated!',
      'error' => 'Authentication Error',
      _ => 'Authenticating...',
    };
  }

  Widget _buildStepContent(
      AuthStateData? data, AuthState authState, ThemeData theme) {
    final state = data?.state ?? '';
    if (state == '2fa') {
      return _build2FA(data!, authState, theme);
    }
    if (state == 'signup') {
      return _buildSignUp(data!, authState, theme);
    }
    final hasCover = _hasCover(state);
    return Column(
      key: ValueKey(state),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!hasCover) ...[
          Icon(
            Icons.lock_outlined,
            size: 48,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
        ],
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
        if (data?.hint.isNotEmpty == true && data?.state != '2fa') ...[
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
        if (data?.state == 'input' || data?.state == 'otp')
          _buildInput(data!, authState, theme),
      ],
    );
  }

  Widget _build2FAField({
    required TextEditingController controller,
    required AuthState authState,
    required ThemeData theme,
    required bool obscure,
    required String label,
    TextInputType? keyboardType,
  }) {
    final errorBorder = _showErrorBorder
        ? OutlineInputBorder(
            borderSide: BorderSide(color: theme.colorScheme.error, width: 2),
          )
        : null;
    return AnimatedBuilder(
      animation: _shakeController,
      builder: (context, child) {
        final dx = _shakeController.isAnimating
            ? sin(_shakeController.value * pi * 4) *
                6 *
                (1 - _shakeController.value)
            : 0.0;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: SizedBox(
        width: 300,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 61),
          child: TextField(
            controller: controller,
            obscureText: obscure,
            autofocus: true,
            style: const TextStyle(fontSize: 16),
            keyboardType: keyboardType,
            onSubmitted: (_) => _submit(authState),
            decoration: InputDecoration(
              labelText: label,
              counterText: '',
              contentPadding: const EdgeInsets.fromLTRB(12, 3, 6, 27),
              border: const OutlineInputBorder(),
              enabledBorder: errorBorder,
              focusedBorder: errorBorder,
            ),
          ),
        ),
      ),
    );
  }

  Widget _build2FA(AuthStateData data, AuthState authState, ThemeData theme) {
    const fieldTop = 74.0;
    const recoveryFieldTop = 96.0;
    const fieldHeight = 61.0;
    const hintTop = 151.0;
    const errorTop = 220.0;
    final activeFieldTop = _isRecoveryMode ? recoveryFieldTop : fieldTop;
    final linkTop = activeFieldTop + fieldHeight + 24.0;

    return SizedBox(
      key: ValueKey(_isRecoveryMode ? '2fa_recovery' : '2fa'),
      height: errorTop + 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 1,
            left: 0,
            right: 0,
            child: Text(
              'Enter Your Password',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
          Positioned(
            top: 34,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: 300,
                child: Text(
                  _isRecoveryMode
                      ? 'Recovery code sent to ${data.sentTo.isNotEmpty ? data.sentTo : "your email"}.'
                      : 'You have Two-Step Verification enabled, so your account is protected with an additional password.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodySmall?.color,
                    height: 20 / 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          Positioned(
            top: activeFieldTop,
            left: 0,
            right: 0,
            child: Center(
              child: _build2FAField(
                controller:
                    _isRecoveryMode ? _recoveryCodeController : _passwordController,
                authState: authState,
                theme: theme,
                obscure: !_isRecoveryMode,
                label: _isRecoveryMode ? 'Recovery Code' : 'Password',
                keyboardType:
                    _isRecoveryMode ? TextInputType.number : null,
              ),
            ),
          ),
          if (!_isRecoveryMode && data.hint.isNotEmpty)
            Positioned(
              top: hintTop,
              left: 0,
              right: 0,
              child: Center(
                child: SizedBox(
                  width: 300,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      'Hint: ${data.hint}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodyMedium?.color,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            top: linkTop,
            left: 0,
            right: 0,
            child: Center(
              child: TextButton(
                onPressed: _isRecoveryMode
                    ? () => _handleTryPassword()
                    : () => _handleForgotPassword(data, authState),
                child: Text(
                  _isRecoveryMode ? 'Try password' : 'Forgot password?',
                  style: TextStyle(fontSize: 14, color: theme.colorScheme.primary),
                ),
              ),
            ),
          ),
          if (authState.error != null)
            Positioned(
              top: errorTop,
              left: 0,
              right: 0,
              child: Center(
                child: SizedBox(
                  width: 300,
                  child: Text(
                    _mapAuthError(authState.error!),
                    style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _mapAuthError(String raw) {
    if (raw.contains('PASSWORD_HASH_INVALID') || raw.contains('SRP_PASSWORD_CHANGED')) {
      return 'Wrong password, try again.';
    }
    if (raw.contains('FLOOD_WAIT')) return 'Too many attempts. Please try again later.';
    if (raw.contains('CODE_INVALID')) return 'Invalid code. Please try again.';
    if (raw.contains('EMAIL_HASH_EXPIRED')) return 'Email confirmation expired.';
    if (raw.contains('EMAIL_NOT_ALLOWED')) return 'This email address is not allowed.';
    if (raw.contains('EMAIL_INVALID')) return 'Please enter a valid email address.';
    if (raw.contains('PASSWORD_RECOVERY_NA')) return 'Recovery not available.';
    if (raw.contains('PASSWORD_RECOVERY_EXPIRED')) return 'Recovery code expired.';
    return raw;
  }

  void _handleTryPassword() {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Can\'t Access Email?'),
        content: Text(
          'If you can\'t restore access to your email, your remaining options are '
          'either to remember your password or to reset your account.',
          style: theme.textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    ).then((_) {
      setState(() {
        _isRecoveryMode = false;
        _showErrorBorder = false;
        _showResetButton = true;
        _recoveryCodeController.clear();
      });
    });
  }

  Widget _buildSignUp(
      AuthStateData data, AuthState authState, ThemeData theme) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return Column(
      key: const ValueKey('signup'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () {},
          child: CircleAvatar(
            radius: 40,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
            child: Icon(
              Icons.add_a_photo_outlined,
              size: 32,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Your Name',
          style: theme.textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 300,
          child: Text(
            'Enter your name and add a\nprofile photo',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodySmall?.color,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 24),
        if (authState.error != null) ...[
          SizedBox(
            width: 300,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                authState.error!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        SizedBox(
          width: 300,
          child: TextField(
            controller: isRtl ? _lastNameController : _firstNameController,
            autofocus: true,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: isRtl ? 'Last name' : 'First name',
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: 300,
          child: TextField(
            controller: isRtl ? _firstNameController : _lastNameController,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(authState),
            decoration: InputDecoration(
              labelText: isRtl ? 'First name' : 'Last name',
            ),
          ),
        ),
      ],
    );
  }

  void _handleForgotPassword(AuthStateData data, AuthState authState) {
    if (data.hasRecovery) {
      setState(() {
        _isRecoveryMode = true;
        _showErrorBorder = false;
      });
    } else {
      _showNoRecoveryDialog(context);
    }
  }

  void _showNoRecoveryDialog(BuildContext context) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Forgot Password'),
        content: Text(
          'Since you haven\'t provided a recovery email when setting up your password, '
          'your remaining options are either to remember your password or to reset your account.',
          style: theme.textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    ).then((_) {
      setState(() => _showResetButton = true);
    });
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
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation(context.palette.windowBgActive),
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
                        decoration: BoxDecoration(
                          color: context.palette.windowBgActive,
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
          child: Text(
            'Log in by phone number',
            style: TextStyle(
              fontSize: 14,
              color: context.palette.windowBgActive,
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
    final isOtp = data.state == 'otp';
    final isPhone = data.state == 'input' && data.fieldType == 'phone';

    return Column(
      children: [
        if (data.sentTo.isNotEmpty) ...[
          Text('Code sent to ${data.sentTo}',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
        ],
        if (isOtp)
          _OtpCodeInput(
            digitCount: data.codeLength > 0 ? data.codeLength : 5,
            hasError: _showErrorBorder,
            onComplete: (code) {
              setState(() => _showErrorBorder = false);
              authState.submitInput(code);
            },
            timeoutSecs: data.timeoutSecs,
          )
        else
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
                      keyboardType: TextInputType.text,
                      autofocus: true,
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
    final match = countries.where((c) => c.dialCode == code).firstOrNull;
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

class _CoverGradient extends StatelessWidget {
  final bool isDark;
  const _CoverGradient({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final topColor = isDark ? const Color(0xFF1B3A4B) : const Color(0xFF0088CC);
    final bottomColor = isDark ? const Color(0xFF0D2637) : const Color(0xFF0066AA);
    const iconSize = 80.0;

    return ClipRect(
      child: Container(
        width: double.infinity,
        height: _AuthScreenState._kCoverHeight,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [topColor, bottomColor],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 46,
              left: 0,
              right: 0,
              child: Center(
                child: Transform.translate(
                  offset: const Offset(-50, 0),
                  child: Icon(
                    Icons.send_rounded,
                    size: iconSize,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Spec §11.5 — Per-digit OTP code input cells.
/// Cell 40x50px, 4px border, 10px gap, 20px digit font.
/// Auto-submits when all cells filled. Shake on error.
class _OtpCodeInput extends StatefulWidget {
  final int digitCount;
  final bool hasError;
  final ValueChanged<String> onComplete;
  final int timeoutSecs;

  const _OtpCodeInput({
    required this.digitCount,
    required this.hasError,
    required this.onComplete,
    this.timeoutSecs = 0,
  });

  @override
  State<_OtpCodeInput> createState() => _OtpCodeInputState();
}

class _OtpCodeInputState extends State<_OtpCodeInput>
    with TickerProviderStateMixin
    implements TextInputClient {
  static const _cellWidth = 40.0;
  static const _cellHeight = 50.0;
  static const _cellGap = 10.0;
  static const _borderWidth = 4.0;
  static const _digitFontSize = 20.0;
  static const _cornerRadius = 3.0;

  late List<String> _digits;
  int _focusedIndex = 0;
  late List<AnimationController> _digitAnimControllers;
  late List<Animation<double>> _fadeAnims;
  late List<Animation<Offset>> _slideAnims;
  late AnimationController _shakeController;
  late FocusNode _focusNode;
  Timer? _callTimer;
  int _callSecondsLeft = 0;
  bool _calling = false;
  bool _submitted = false;
  TextInputConnection? _inputConnection;

  @override
  void initState() {
    super.initState();
    _digits = List.filled(widget.digitCount, '');
    _digitAnimControllers = List.generate(widget.digitCount, (_) {
      return AnimationController(
        duration: const Duration(milliseconds: 120),
        vsync: this,
      );
    });
    _fadeAnims = _digitAnimControllers
        .map((c) => Tween<double>(begin: 0.0, end: 1.0).animate(c))
        .toList();
    _slideAnims = _digitAnimControllers
        .map((c) => Tween<Offset>(begin: const Offset(0, 10), end: Offset.zero)
            .animate(c))
        .toList();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _focusNode = FocusNode();
    for (var i = 0; i < widget.digitCount; i++) {
      _digitAnimControllers[i].value = 0.0;
    }
    if (widget.timeoutSecs > 0) {
      _callSecondsLeft = widget.timeoutSecs;
      _startCallTimer();
    }
    _focusNode.addListener(_onFocusChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _inputConnection?.close();
      _inputConnection = TextInput.attach(
        this,
        const TextInputConfiguration(
          inputType: TextInputType.number,
          inputAction: TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
        ),
      );
      _inputConnection!.show();
    } else {
      _inputConnection?.close();
      _inputConnection = null;
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(_OtpCodeInput old) {
    super.didUpdateWidget(old);
    if (widget.hasError && !old.hasError) {
      _shakeController.forward(from: 0);
      _submitted = false;
      for (var i = 0; i < widget.digitCount; i++) {
        _digits[i] = '';
        _digitAnimControllers[i].value = 0.0;
      }
      _focusedIndex = 0;
    }
    if (widget.digitCount != old.digitCount) {
      _rebuildDigits();
    }
  }

  void _rebuildDigits() {
    for (final c in _digitAnimControllers) {
      c.dispose();
    }
    _digits = List.filled(widget.digitCount, '');
    _digitAnimControllers = List.generate(widget.digitCount, (_) {
      return AnimationController(
        duration: const Duration(milliseconds: 120),
        vsync: this,
      );
    });
    _fadeAnims = _digitAnimControllers
        .map((c) => Tween<double>(begin: 0.0, end: 1.0).animate(c))
        .toList();
    _slideAnims = _digitAnimControllers
        .map((c) => Tween<Offset>(begin: const Offset(0, 10), end: Offset.zero)
            .animate(c))
        .toList();
    _focusedIndex = 0;
    _submitted = false;
  }

  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() {
        _callSecondsLeft--;
        if (_callSecondsLeft <= 0) {
          t.cancel();
          _calling = true;
        }
      });
    });
  }

  @override
  void dispose() {
    _inputConnection?.close();
    for (final c in _digitAnimControllers) {
      c.dispose();
    }
    _shakeController.dispose();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _callTimer?.cancel();
    super.dispose();
  }

  void _insertDigit(String digit) {
    if (_submitted) return;
    if (_focusedIndex >= widget.digitCount) return;
    setState(() {
      _digits[_focusedIndex] = digit;
      _digitAnimControllers[_focusedIndex].forward(from: 0);
      if (_focusedIndex < widget.digitCount - 1) {
        _focusedIndex++;
      }
    });
    _checkComplete();
  }

  void _deleteDigit() {
    if (_submitted) return;
    if (_focusedIndex > 0 && _digits[_focusedIndex].isEmpty) {
      _focusedIndex--;
    }
    if (_digits[_focusedIndex].isNotEmpty) {
      setState(() {
        _digitAnimControllers[_focusedIndex].reverse();
        _digits[_focusedIndex] = '';
      });
    }
  }

  void _checkComplete() {
    if (_submitted) return;
    final code = _digits.join();
    if (code.length == widget.digitCount &&
        code.runes.every((r) => r >= 0x30 && r <= 0x39)) {
      _submitted = true;
      Future.delayed(const Duration(milliseconds: 80), () {
        widget.onComplete(code);
      });
    }
  }

  void _pasteCode() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null) return;
    final digits = data!.text!.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    setState(() {
      for (var i = 0; i < widget.digitCount && i < digits.length; i++) {
        _digits[i] = digits[i];
        _digitAnimControllers[i].forward(from: 0);
      }
      _focusedIndex = min(digits.length, widget.digitCount - 1);
    });
    _checkComplete();
  }

  void _copyCode() {
    final code = _digits.join();
    if (code.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: code));
    }
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final hasDigits = _digits.any((d) => d.isNotEmpty);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      items: [
        const PopupMenuItem(value: 'paste', child: Text('Paste')),
        if (hasDigits)
          const PopupMenuItem(value: 'copy', child: Text('Copy')),
      ],
    ).then((value) {
      if (value == 'paste') _pasteCode();
      if (value == 'copy') _copyCode();
    });
  }

  // ── TextInputClient implementation ──

  @override
  TextEditingValue? get currentTextEditingValue => TextEditingValue(
        text: _digits.join(),
        selection: TextSelection.collapsed(offset: _focusedIndex),
      );

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void updateEditingValue(TextEditingValue value) {
    if (_submitted) return;
    final newDigits = value.text.replaceAll(RegExp(r'\D'), '');
    if (newDigits.isEmpty) return;
    for (final char in newDigits.characters) {
      _insertDigit(char);
    }
  }

  @override
  void performAction(TextInputAction action) {
    if (action == TextInputAction.done) {
      _checkComplete();
    }
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void connectionClosed() {}

  @override
  void insertContent(KeyboardInsertedContent content) {}

  @override
  void showToolbar() {}

  @override
  void insertTextPlaceholder(Size size) {}

  @override
  void removeTextPlaceholder() {}

  @override
  void didChangeInputControl(TextInputControl? oldControl,
      TextInputControl? newControl) {}

  @override
  void performSelector(String selectorName) {}

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.backspace) {
      _deleteDigit();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      setState(() {
        _focusedIndex = max(0, _focusedIndex - 1);
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      setState(() {
        _focusedIndex = min(widget.digitCount - 1, _focusedIndex + 1);
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      setState(() => _focusedIndex = 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      setState(() => _focusedIndex = widget.digitCount - 1);
      return KeyEventResult.handled;
    }

    if (HardwareKeyboard.instance.isControlPressed) {
      if (key == LogicalKeyboardKey.keyV) {
        _pasteCode();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyC) {
        _copyCode();
        return KeyEventResult.handled;
      }
    }

    final char = event.character;
    if (char != null && char.length == 1 && RegExp(r'\d').hasMatch(char)) {
      _insertDigit(char);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF202B36) : const Color(0xFFEFEFEF);
    final unfocusedBorder =
        isDark ? const Color(0xFF3A4A5A) : const Color(0xFFD0D0D0);
    final focusedBorder = context.palette.activeLineFg;
    final errorBorder = theme.colorScheme.error;

    return Column(
      children: [
        Focus(
          focusNode: _focusNode,
          onKeyEvent: _handleKey,
          child: GestureDetector(
            onTap: () => _focusNode.requestFocus(),
            onSecondaryTapUp: (details) {
              _focusNode.requestFocus();
              _showContextMenu(context, details.globalPosition);
            },
            onLongPressStart: (details) {
              _focusNode.requestFocus();
              _showContextMenu(context, details.globalPosition);
            },
            child: AnimatedBuilder(
              animation: _shakeController,
              builder: (context, child) {
                final dx = _shakeController.isAnimating
                    ? sin(_shakeController.value * pi * 6) *
                        8 *
                        (1 - _shakeController.value)
                    : 0.0;
                return Transform.translate(
                  offset: Offset(dx, 0),
                  child: child,
                );
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(widget.digitCount, (i) {
                  final isFocused =
                      _focusNode.hasFocus && i == _focusedIndex;
                  final borderColor = widget.hasError
                      ? errorBorder
                      : isFocused
                          ? focusedBorder
                          : unfocusedBorder;

                  return Padding(
                    padding: EdgeInsets.only(
                        right: i < widget.digitCount - 1 ? _cellGap : 0),
                    child: Container(
                      width: _cellWidth,
                      height: _cellHeight,
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius:
                            BorderRadius.circular(_cornerRadius),
                        border: Border.all(
                          color: borderColor,
                          width: _borderWidth,
                        ),
                      ),
                      child: Center(
                        child: AnimatedBuilder(
                          animation: _digitAnimControllers[i],
                          builder: (context, child) {
                            final fade = _fadeAnims[i].value;
                            final slide = _slideAnims[i].value;
                            return Opacity(
                              opacity: fade,
                              child: Transform.translate(
                                offset: Offset(slide.dx,
                                    slide.dy * (1 - fade)),
                                child: child,
                              ),
                            );
                          },
                          child: Text(
                            _digits[i],
                            style: TextStyle(
                              fontSize: _digitFontSize,
                              fontWeight: FontWeight.w500,
                              color: theme.textTheme.bodyLarge?.color,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
        if (widget.timeoutSecs > 0) ...[
          const SizedBox(height: 16),
          _calling
              ? Text(
                  'Calling...',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                )
              : _callSecondsLeft > 0
                  ? Text(
                      'Telegram will call you in ${_callSecondsLeft ~/ 60}:${(_callSecondsLeft % 60).toString().padLeft(2, '0')}',
                      style: theme.textTheme.bodySmall,
                    )
                  : const SizedBox.shrink(),
        ],
        const SizedBox(height: 12),
        TextButton(
          onPressed: () {},
          child: Text(
            "Didn't get the code?",
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.primary,
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

class _CountryPickerDialog extends StatefulWidget {
  final CountryInfo selected;
  final void Function(CountryInfo) onSelect;
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
        ? countries
        : countries
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


enum _PhoneErrorType { invalid, banned, flood }

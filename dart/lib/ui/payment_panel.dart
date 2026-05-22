import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../bridge/engine_service.dart';
import '../theme/telegram_palette.dart';
import '../utils/country_data.dart';
import 'privacy_settings_screen.dart';
import 'settings_style.dart';

const _kPanelWidth = 392.0;
const _kPanelHeight = 600.0;
const _kCoverPadding = EdgeInsets.fromLTRB(26, 0, 26, 13);
const _kThumbSize = 80.0;
const _kThumbSkip = 18.0;
const _kThumbRadius = 6.0;
const _kPricePadding = EdgeInsets.fromLTRB(28, 6, 28, 5);
const _kPricesTopSkip = 12.0;
const _kPricesBottomSkip = 13.0;
const _kTipButtonsPadding = EdgeInsets.fromLTRB(26, 6, 26, 6);
const _kTipButtonHeight = 28.0;
const _kTipButtonSkip = 8.0;
const _kSectionButtonPadding = EdgeInsets.fromLTRB(68, 11, 14, 9);
const _kFieldPadding = EdgeInsets.fromLTRB(28, 0, 28, 2);
const _kSubmitHeight = 36.0;
const _kSubmitHPadding = 36.0;
const _kProgressSize = 24.0;
const _kProgressStroke = 4.0;
const _kProgressOpacity = 0.3;
const _kProgressFadeDuration = Duration(milliseconds: 200);
const _kSectionsTopSkip = 11.0;
const _kCornerRadius = 12.0;
const _kHeaderHeight = 54.0;

class PaymentPanelData {
  final String accountId;
  final String chatId;
  final String msgId;
  final String title;
  final String description;
  final String currency;
  final int totalAmount;
  final bool isTest;
  final bool isReceipt;
  final int receiptMsgId;
  final String photoUrl;
  final String botName;

  const PaymentPanelData({
    required this.accountId,
    required this.chatId,
    required this.msgId,
    this.title = '',
    this.description = '',
    this.currency = '',
    this.totalAmount = 0,
    this.isTest = false,
    this.isReceipt = false,
    this.receiptMsgId = 0,
    this.photoUrl = '',
    this.botName = '',
  });
}

class PaymentPanel extends StatefulWidget {
  final PaymentPanelData data;

  const PaymentPanel({super.key, required this.data});

  static void open(BuildContext context, {required PaymentPanelData data}) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: const Color(0x66000000),
        barrierDismissible: true,
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation.drive(CurveTween(curve: Curves.easeOut)),
            child: SlideTransition(
              position: animation.drive(
                Tween(begin: const Offset(0, 0.05), end: Offset.zero)
                    .chain(CurveTween(curve: Curves.easeOut)),
              ),
              child: PaymentPanel(data: data),
            ),
          );
        },
      ),
    );
  }

  @override
  State<PaymentPanel> createState() => _PaymentPanelState();
}

enum _PanelState { loading, form, submitting, done, error }

class _PaymentPanelState extends State<PaymentPanel>
    with TickerProviderStateMixin {
  _PanelState _state = _PanelState.loading;
  String _errorText = '';

  Map<String, dynamic> _formData = {};
  List<Map<String, dynamic>> _prices = [];
  List<int> _suggestedTips = [];
  List<List<int>> _tipRows = [];
  int _maxTip = 0;
  int _selectedTip = 0;
  bool _isReceipt = false;
  bool _termsAccepted = false;
  String _termsUrl = '';

  bool _shippingRequested = false;
  bool _nameRequested = false;
  bool _emailRequested = false;
  bool _phoneRequested = false;

  String? _paymentMethod;
  String? _shippingAddress;
  String? _shippingMethod;
  String? _savedName;
  String? _savedEmail;
  String? _savedPhone;
  List<Map<String, dynamic>> _shippingPrices = [];
  List<Map<String, dynamic>> _shippingOptions = [];
  String? _selectedShippingId;
  String? _requestedInfoId;
  String? _credentialsData;

  String? _street1;
  String? _street2;
  String? _city;
  String? _addrState;
  String? _country;
  String? _postcode;

  String? _initialPaymentMethod;
  String? _initialShippingAddress;
  String? _initialName;
  String? _initialEmail;
  String? _initialPhone;

  Map<String, String> _fieldErrors = {};

  int _receiptDate = 0;
  int _tipAmount = 0;

  late final AnimationController _progressFade;
  late final AnimationController _spinnerAnim;

  @override
  void initState() {
    super.initState();
    _isReceipt = widget.data.isReceipt;
    _progressFade = AnimationController(
      vsync: this,
      duration: _kProgressFadeDuration,
      value: 1.0,
    );
    _spinnerAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _fetchForm();
  }

  @override
  void dispose() {
    _progressFade.dispose();
    _spinnerAnim.dispose();
    super.dispose();
  }

  Future<void> _fetchForm() async {
    final engine = context.read<EngineService>();
    try {
      Map<String, dynamic> data;
      if (_isReceipt) {
        data = await engine.getPaymentReceipt(
          widget.data.accountId,
          widget.data.chatId,
          '${widget.data.receiptMsgId}',
        );
      } else {
        data = await engine.getPaymentForm(
          widget.data.accountId,
          widget.data.chatId,
          widget.data.msgId,
        );
      }
      if (!mounted) return;
      setState(() {
        _formData = data;
        _prices = (data['prices'] as List<dynamic>?)
                ?.map((p) => p as Map<String, dynamic>)
                .toList() ??
            [];
        _suggestedTips = (data['suggested_tips'] as List<dynamic>?)
                ?.map((t) => (t as num).toInt())
                .toList() ??
            [];
        _tipRows = _computeTipRows(_suggestedTips);
        _maxTip = (data['max_tip'] as num?)?.toInt() ?? 0;
        _shippingRequested = data['shipping_requested'] == true;
        _nameRequested = data['name_requested'] == true;
        _emailRequested = data['email_requested'] == true;
        _phoneRequested = data['phone_requested'] == true;
        _termsUrl = data['terms_url'] as String? ?? '';

        if (_isReceipt) {
          _receiptDate = (data['date'] as num?)?.toInt() ?? 0;
          _tipAmount = (data['tip_amount'] as num?)?.toInt() ?? 0;
        }

        final saved = data['saved_info'] as Map<String, dynamic>?;
        if (saved != null) {
          _savedName = saved['name'] as String?;
          _savedEmail = saved['email'] as String?;
          _savedPhone = saved['phone'] as String?;
          _street1 = saved['street1'] as String?;
          _street2 = saved['street2'] as String?;
          _city = saved['city'] as String?;
          _addrState = saved['state'] as String?;
          _country = saved['country'] as String?;
          _postcode = saved['postcode'] as String?;
          _shippingAddress = _buildFullAddress(saved);
        }

        final savedCreds = data['saved_credentials'] as Map<String, dynamic>?;
        if (savedCreds != null) {
          _paymentMethod = savedCreds['title'] as String?;
        }

        if (_isReceipt) {
          _shippingMethod = data['shipping_option'] as String?;
          _paymentMethod = data['credentials_title'] as String?;
        }

        final shippingOptionsList = data['shipping_options'] as List<dynamic>?;
        if (shippingOptionsList != null && shippingOptionsList.isNotEmpty) {
          _shippingOptions = shippingOptionsList
              .whereType<Map<String, dynamic>>()
              .toList();
          final selectedId = data['selected_shipping_id'] as String?;
          if (selectedId != null) {
            _selectedShippingId = selectedId;
            for (final opt in _shippingOptions) {
              if (opt['id'] == selectedId) {
                _shippingMethod = opt['title'] as String?;
                _shippingPrices = (opt['prices'] as List<dynamic>?)
                        ?.map((p) => p as Map<String, dynamic>)
                        .toList() ??
                    [];
                break;
              }
            }
          }
        }

        _passwordMissing = data['password_missing'] == true;

        _initialPaymentMethod = _paymentMethod;
        _initialShippingAddress = _shippingAddress;
        _initialName = _savedName;
        _initialEmail = _savedEmail;
        _initialPhone = _savedPhone;

        _state = _PanelState.form;
      });
      _progressFade.animateTo(0.0, duration: _kProgressFadeDuration);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _PanelState.error;
        _errorText = e.toString();
      });
    }
  }

  bool _passwordMissing = false;

  Future<void> _submitPayment() async {
    if (_passwordMissing) {
      _showPasswordMissingDialog();
      return;
    }
    if (_termsUrl.isNotEmpty && !_termsAccepted) {
      _showTermsDialog();
      return;
    }
    if (_shippingOptions.isNotEmpty && _selectedShippingId == null) {
      _chooseShippingOption();
      return;
    }
    setState(() {
      _state = _PanelState.submitting;
      _errorText = '';
      _fieldErrors = {};
    });
    final engine = context.read<EngineService>();
    try {
      if (_requestedInfoId == null && _hasRequestedInfo) {
        final info = <String, dynamic>{};
        if (_nameRequested && _savedName != null) info['name'] = _savedName;
        if (_phoneRequested && _savedPhone != null) info['phone'] = _savedPhone;
        if (_emailRequested && _savedEmail != null) info['email'] = _savedEmail;
        if (_shippingRequested) {
          info['street1'] = _street1 ?? '';
          info['street2'] = _street2 ?? '';
          info['city'] = _city ?? '';
          info['state'] = _addrState ?? '';
          info['country'] = _country ?? '';
          info['postcode'] = _postcode ?? '';
        }
        final validationResult = await engine.validatePaymentInfo(
          widget.data.accountId,
          widget.data.chatId,
          widget.data.msgId,
          info,
          save: true,
        );
        if (!mounted) return;
        _requestedInfoId = validationResult['id'] as String?;
        final opts = validationResult['shipping_options'] as List<dynamic>?;
        if (opts != null && opts.isNotEmpty) {
          setState(() {
            _shippingOptions = opts.whereType<Map<String, dynamic>>().toList();
          });
        }
      }

      final submitData = <String, dynamic>{
        'form_id': _formData['form_id'],
      };
      if (_selectedTip > 0) {
        submitData['tip_amount'] = _selectedTip;
      }
      if (_requestedInfoId != null) {
        submitData['requested_info_id'] = _requestedInfoId;
      }
      if (_selectedShippingId != null) {
        submitData['shipping_option_id'] = _selectedShippingId;
      }
      if (_credentialsData != null) {
        submitData['credentials_data'] = _credentialsData;
      }
      if (_termsUrl.isNotEmpty && _termsAccepted) {
        submitData['accept_terms'] = true;
      }
      await engine.sendPaymentForm(
        widget.data.accountId,
        widget.data.chatId,
        widget.data.msgId,
        submitData,
      );
      if (!mounted) return;
      setState(() => _state = _PanelState.done);
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) Navigator.of(context).pop();
      });
    } catch (e) {
      if (!mounted) return;
      final errStr = e.toString();
      final newFieldErrors = <String, String>{};
      String displayError = errStr;

      if (errStr.contains('BOT_TRUST_REQUIRED')) {
        _showBotTrustWarning();
        setState(() => _state = _PanelState.form);
        return;
      }

      if (errStr.contains('REQ_INFO_NAME_INVALID')) {
        newFieldErrors['Name'] = 'Invalid name';
        displayError = 'Please check your name';
      } else if (errStr.contains('REQ_INFO_EMAIL_INVALID')) {
        newFieldErrors['Email'] = 'Invalid email';
        displayError = 'Please check your email address';
      } else if (errStr.contains('REQ_INFO_PHONE_INVALID')) {
        newFieldErrors['Phone'] = 'Invalid phone number';
        displayError = 'Please check your phone number';
      } else if (errStr.contains('ADDRESS_STREET_LINE1_INVALID')) {
        newFieldErrors['Shipping Address'] = 'Invalid street address';
        displayError = 'Please check your street address';
      } else if (errStr.contains('ADDRESS_CITY_INVALID')) {
        newFieldErrors['Shipping Address'] = 'Invalid city';
        displayError = 'Please check your city';
      } else if (errStr.contains('ADDRESS_STATE_INVALID')) {
        newFieldErrors['Shipping Address'] = 'Invalid state';
        displayError = 'Please check your state/province';
      } else if (errStr.contains('ADDRESS_COUNTRY_INVALID')) {
        newFieldErrors['Shipping Address'] = 'Invalid country';
        displayError = 'Please check your country';
      } else if (errStr.contains('ADDRESS_POSTCODE_INVALID')) {
        newFieldErrors['Shipping Address'] = 'Invalid postal code';
        displayError = 'Please check your postal code';
      } else if (errStr.contains('LOCAL_CARD_NUMBER_INVALID')) {
        newFieldErrors['Payment Method'] = 'Invalid card number';
        displayError = 'Please check your card number';
      } else if (errStr.contains('LOCAL_CARD_EXPIRE_DATE_INVALID')) {
        newFieldErrors['Payment Method'] = 'Invalid expiry date';
        displayError = 'Please check your card expiry date';
      } else if (errStr.contains('LOCAL_CARD_CVC_INVALID')) {
        newFieldErrors['Payment Method'] = 'Invalid CVC';
        displayError = 'Please check your card CVC';
      } else if (errStr.contains('LOCAL_CARD_HOLDER_NAME_INVALID')) {
        newFieldErrors['Payment Method'] = 'Invalid cardholder name';
        displayError = 'Please check the cardholder name';
      } else if (errStr.contains('LOCAL_CARD_BILLING_COUNTRY_INVALID')) {
        newFieldErrors['Payment Method'] = 'Invalid billing country';
        displayError = 'Please check your billing country';
      } else if (errStr.contains('LOCAL_CARD_BILLING_ZIP_INVALID')) {
        newFieldErrors['Payment Method'] = 'Invalid billing ZIP';
        displayError = 'Please check your billing postal code';
      } else if (errStr.contains('SHIPPING_BOT_TIMEOUT')) {
        displayError = 'Bot timeout — please try again';
      } else if (errStr.contains('SHIPPING_NOT_AVAILABLE')) {
        displayError = 'Shipping is not available to your location';
      } else if (errStr.contains('INVOICE_ALREADY_PAID')) {
        displayError = 'This invoice has already been paid';
      } else if (errStr.contains('PAYMENT_FAILED')) {
        displayError = 'Payment failed — please try again';
      } else if (errStr.contains('BOT_PRECHECKOUT_FAILED')) {
        displayError = 'The bot could not process your order';
      } else if (errStr.contains('BOT_PRECHECKOUT_TIMEOUT')) {
        displayError = 'The bot did not respond — please try again';
      }

      setState(() {
        _state = _PanelState.form;
        _errorText = displayError;
        _fieldErrors = newFieldErrors;
      });
    }
  }

  void _showBotTrustWarning() {
    final botName = widget.data.botName.isNotEmpty
        ? widget.data.botName
        : 'this bot';
    final providerName =
        _formData['native_provider'] as String? ?? 'the payment provider';
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Payment Confirmation'),
        content: Text(
          'You are about to pay via $providerName as requested by @$botName. '
          'Please confirm that you want to proceed with this payment.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop(true);
              _submitPayment();
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  bool get _hasRequestedInfo =>
      _nameRequested || _phoneRequested || _emailRequested || _shippingRequested;

  void _showTermsDialog() {
    var accepted = _termsAccepted;
    String? errorText;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Terms of Service'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'By completing this payment, you agree to the Terms of Service of the payment provider.',
              ),
              if (_termsUrl.isNotEmpty) ...[
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => launchUrl(Uri.parse(_termsUrl),
                      mode: LaunchMode.externalApplication),
                  child: Text(
                    _termsUrl,
                    style: const TextStyle(
                      color: Colors.blue,
                      decoration: TextDecoration.underline,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(
                    value: accepted,
                    onChanged: (v) {
                      setDialogState(() {
                        accepted = v ?? false;
                        errorText = null;
                      });
                    },
                  ),
                  const Expanded(child: Text('I agree to the Terms of Service')),
                ],
              ),
              if (errorText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    errorText!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (!accepted) {
                  setDialogState(() {
                    errorText = 'You must accept the Terms of Service to continue.';
                  });
                  return;
                }
                setState(() => _termsAccepted = true);
                Navigator.of(ctx).pop();
                _submitPayment();
              },
              child: const Text('Accept'),
            ),
          ],
        ),
      ),
    );
  }

  void _showPasswordMissingDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cloud Password Required'),
        content: const Text(
          'To complete this payment, you need to set a Two-Step Verification password.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              final engine = context.read<EngineService>();
              Navigator.of(context).push(settingsPageRoute(
                CloudPasswordStart(
                  accountId: widget.data.accountId,
                  engine: engine,
                  onPasswordSet: () {
                    setState(() => _passwordMissing = false);
                  },
                ),
              ));
            },
            child: const Text('Set Password'),
          ),
        ],
      ),
    );
  }

  static int _currencyExponent(String code) {
    switch (code.toUpperCase()) {
      case 'JPY': case 'KRW': case 'CLP': case 'ISK':
      case 'PYG': case 'UGX': case 'VND': case 'VUV':
      case 'XAF': case 'XOF': case 'XPF': case 'RWF':
      case 'GNF': case 'KMF': case 'DJF': case 'MGA':
        return 0;
      case 'BHD': case 'IQD': case 'JOD': case 'KWD':
      case 'LYD': case 'OMR': case 'TND':
        return 3;
      default:
        return 2;
    }
  }

  String _formatAmount(int amount, String currency) {
    final isNeg = amount < 0;
    final abs = amount.abs();
    final exp = _currencyExponent(currency);
    int divisor = 1;
    for (int i = 0; i < exp; i++) divisor *= 10;
    final major = abs ~/ divisor;
    final minor = abs % divisor;
    final sym = _currencySymbol(currency);
    String s;
    if (exp == 0 || minor == 0) {
      s = '$sym$major';
    } else {
      s = '$sym$major.${minor.toString().padLeft(exp, '0')}';
    }
    return isNeg ? '-$s' : s;
  }

  String _currencySymbol(String code) {
    switch (code.toUpperCase()) {
      case 'USD':
        return '\$';
      case 'EUR':
        return '\u20AC';
      case 'GBP':
        return '\u00A3';
      case 'RUB':
        return '\u20BD';
      case 'JPY':
        return '\u00A5';
      case 'CNY':
        return '\u00A5';
      case 'IRR':
        return '\uFDFC';
      case 'TRY':
        return '\u20BA';
      case 'INR':
        return '\u20B9';
      case 'KRW':
        return '\u20A9';
      default:
        return '$code ';
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final windowBg = isDark ? const Color(0xFF17212b) : Colors.white;
    final windowFg = isDark ? Colors.white : Colors.black87;
    final subFg = isDark ? const Color(0xFF7e919f) : const Color(0xFF999999);
    final divider = isDark ? const Color(0xFF1e2c3a) : const Color(0xFFe7e7e7);
    final accentBg = palette.windowBgActive;
    const accentFg = Colors.white;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: _kPanelWidth,
          height: _kPanelHeight,
          decoration: BoxDecoration(
            color: windowBg,
            borderRadius: BorderRadius.circular(_kCornerRadius),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_kCornerRadius),
            child: Column(
              children: [
                _buildHeader(windowBg, windowFg, subFg, divider),
                Expanded(
                  child: _state == _PanelState.loading ||
                          _state == _PanelState.submitting
                      ? _buildLoading(subFg)
                      : _state == _PanelState.error
                          ? _buildError(windowFg, subFg)
                          : _buildFormContent(
                              windowFg, subFg, divider, accentBg, isDark),
                ),
                if (_state == _PanelState.form || _state == _PanelState.done)
                  _buildBottomButtons(accentBg, accentFg, windowFg, divider),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
      Color windowBg, Color windowFg, Color subFg, Color divider) {
    final title = _isReceipt ? 'Receipt' : 'Checkout';
    return Container(
      height: _kHeaderHeight,
      decoration: BoxDecoration(
        color: windowBg,
        border: Border(bottom: BorderSide(color: divider, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: windowFg,
              ),
            ),
          ),
          if (widget.data.isTest)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFe53935),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text(
                'TEST',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white),
              ),
            ),
          IconButton(
            icon: Icon(Icons.close, color: windowFg, size: 20),
            onPressed: _requestClose,
            splashRadius: 18,
          ),
        ],
      ),
    );
  }

  Widget _buildLoading(Color subFg) {
    return Center(
      child: AnimatedBuilder(
        animation: _progressFade,
        builder: (_, __) => Opacity(
          opacity: _progressFade.value.clamp(0.0, 1.0),
          child: SizedBox(
            width: _kProgressSize,
            height: _kProgressSize,
            child: CircularProgressIndicator(
              strokeWidth: _kProgressStroke,
              valueColor: AlwaysStoppedAnimation(subFg),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError(Color fg, Color subFg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: subFg, size: 48),
            const SizedBox(height: 12),
            Text(
              'Failed to load payment form',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600, color: fg),
            ),
            if (_errorText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _errorText,
                style: TextStyle(fontSize: 13, color: subFg),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFormContent(
      Color fg, Color subFg, Color divider, Color accent, bool isDark) {
    final currency = _formData['currency'] as String? ??
        widget.data.currency;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (_errorText.isNotEmpty && _state == _PanelState.form)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
            color: Colors.red.withValues(alpha: 0.1),
            child: Text(
              _errorText,
              style: const TextStyle(fontSize: 13, color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ),
        const SizedBox(height: 16),
        _buildCoverSection(fg, subFg),
        Divider(height: 1, color: divider),
        const SizedBox(height: _kPricesTopSkip),
        if (_isReceipt && _receiptDate > 0) ...[
          Padding(
            padding: _kPricePadding,
            child: _priceRow(
                'Date', _formatReceiptDate(_receiptDate), fg, subFg, true),
          ),
          const SizedBox(height: _kPricesBottomSkip),
          Divider(height: 1, color: divider),
          const SizedBox(height: _kPricesTopSkip),
        ],
        _buildPricesSection(fg, subFg, currency),
        if (_suggestedTips.isNotEmpty && !_isReceipt) ...[
          const SizedBox(height: 4),
          _buildTipsSection(accent, fg, isDark, currency),
          if (_selectedTip > 0)
            Padding(
              padding: _kPricePadding,
              child: GestureDetector(
                onTap: () => _panelChooseTips(currency, accent, fg, isDark),
                child: _priceRow(
                  'Tips',
                  _formatAmount(_selectedTip, currency),
                  fg,
                  accent,
                  false,
                ),
              ),
            ),
        ],
        if (_isReceipt && _tipAmount > 0) ...[
          Padding(
            padding: _kPricePadding,
            child: _priceRow('Tips', _formatAmount(_tipAmount, currency), fg,
                subFg, false),
          ),
        ],
        const SizedBox(height: _kPricesBottomSkip),
        Divider(height: 1, color: divider),
        const SizedBox(height: _kSectionsTopSkip),
        _buildSectionButtons(fg, subFg, divider),
        if (_formData['native_provider'] != null) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 6),
            child: Text(
              'Processed by ${_formData['native_provider']}',
              style: TextStyle(fontSize: 12, color: subFg),
              textAlign: TextAlign.center,
            ),
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildCoverSection(Color fg, Color subFg) {
    final title = _formData['title'] as String? ?? widget.data.title;
    final desc =
        _formData['description'] as String? ?? widget.data.description;
    final seller = widget.data.botName.isNotEmpty
        ? '@${widget.data.botName}'
        : '';
    final photoUrl = _formData['photo_url'] as String? ?? widget.data.photoUrl;

    return Padding(
      padding: _kCoverPadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (photoUrl.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(_kThumbRadius),
              child: Container(
                width: _kThumbSize,
                height: _kThumbSize,
                color: const Color(0xFFf0f0f0),
                child: _buildThumbnail(photoUrl, subFg),
              ),
            ),
            const SizedBox(width: _kThumbSkip),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title.isNotEmpty)
                  Text(
                    title,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: fg),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    desc,
                    style: TextStyle(fontSize: 14, color: fg),
                    maxLines: 10,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (seller.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    seller,
                    style: TextStyle(fontSize: 13, color: subFg),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail(String photoUrl, Color subFg) {
    return Image.network(
      photoUrl,
      width: _kThumbSize,
      height: _kThumbSize,
      cacheWidth: (_kThumbSize * 2).toInt(),
      cacheHeight: (_kThumbSize * 2).toInt(),
      fit: BoxFit.cover,
      loadingBuilder: (_, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                  : null,
              valueColor: AlwaysStoppedAnimation(subFg.withValues(alpha: 0.4)),
            ),
          ),
        );
      },
      errorBuilder: (_, __, ___) => Icon(
        Icons.receipt_long,
        size: 40,
        color: subFg.withValues(alpha: 0.4),
      ),
    );
  }

  Widget _buildPricesSection(Color fg, Color subFg, String currency) {
    final totalAmount = _isReceipt
        ? ((_formData['total_amount'] as num?)?.toInt() ?? 0)
        : _computeTotal();

    return Column(
      children: [
        for (final price in _prices)
          Padding(
            padding: _kPricePadding,
            child: _priceRow(
              price['label'] as String? ?? '',
              _formatAmount(
                  (price['amount'] as num?)?.toInt() ?? 0, currency),
              fg,
              subFg,
              false,
            ),
          ),
        for (final price in _shippingPrices)
          Padding(
            padding: _kPricePadding,
            child: _priceRow(
              price['label'] as String? ?? '',
              _formatAmount(
                  (price['amount'] as num?)?.toInt() ?? 0, currency),
              fg,
              subFg,
              false,
            ),
          ),
        Padding(
          padding: _kPricePadding,
          child: _priceRow(
            'Total',
            _formatAmount(totalAmount + _selectedTip, currency),
            fg,
            subFg,
            true,
          ),
        ),
      ],
    );
  }

  int _computeTotal() {
    int sum = 0;
    for (final p in _prices) {
      sum += (p['amount'] as num?)?.toInt() ?? 0;
    }
    for (final p in _shippingPrices) {
      sum += (p['amount'] as num?)?.toInt() ?? 0;
    }
    return sum;
  }

  Widget _priceRow(
      String label, String amount, Color fg, Color subFg, bool isTotal) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isTotal ? FontWeight.w600 : FontWeight.normal,
              color: fg,
            ),
          ),
        ),
        Text(
          amount,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isTotal ? FontWeight.w700 : FontWeight.normal,
            color: fg,
          ),
        ),
      ],
    );
  }

  Widget _buildTipButton(int tip, String currency, Color accent, bool isDark) {
    final isSelected = _selectedTip == tip;
    return Expanded(
      child: SizedBox(
        height: _kTipButtonHeight,
        child: TextButton(
          onPressed: () {
            setState(() {
              _selectedTip = isSelected ? 0 : tip;
            });
          },
          style: TextButton.styleFrom(
            backgroundColor: isSelected
                ? accent.withValues(alpha: 0.8)
                : accent.withValues(alpha: 0.1),
            foregroundColor: isSelected
                ? Colors.white
                : accent,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            textStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          child: Text(_formatAmount(tip, currency), overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }

  static List<List<int>> _computeTipRows(List<int> tips) {
    const maxPerRow = 3;
    final rows = <List<int>>[];
    for (var i = 0; i < tips.length; i += maxPerRow) {
      rows.add(tips.sublist(i, (i + maxPerRow).clamp(0, tips.length)));
    }
    return rows;
  }

  Widget _buildTipsSection(
      Color accent, Color fg, bool isDark, String currency) {
    return Padding(
      padding: _kTipButtonsPadding,
      child: Column(
        children: [
          for (final row in _tipRows) ...[
            Row(
              children: [
                for (var i = 0; i < row.length; i++) ...[
                  if (i > 0) const SizedBox(width: _kTipButtonSkip),
                  _buildTipButton(row[i], currency, accent, isDark),
                ],
              ],
            ),
            const SizedBox(height: _kTipButtonSkip),
          ],
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: _kTipButtonHeight,
                  child: TextButton(
                    onPressed: () =>
                        _panelChooseTips(currency, accent, fg, isDark),
                    style: TextButton.styleFrom(
                      backgroundColor: accent.withValues(alpha: 0.1),
                      foregroundColor: accent,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    child: const Text('Other'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionButtons(Color fg, Color subFg, Color divider) {
    final sections = <_SectionData>[];

    sections.add(_SectionData(
      icon: Icons.credit_card,
      label: 'Payment Method',
      value: _paymentMethod ?? 'Not selected',
    ));

    if (_shippingRequested) {
      sections.add(_SectionData(
        icon: Icons.location_on_outlined,
        label: 'Shipping Address',
        value: _shippingAddress ?? 'Not provided',
      ));
      sections.add(_SectionData(
        icon: Icons.local_shipping_outlined,
        label: 'Shipping Method',
        value: _shippingMethod ?? 'Not selected',
      ));
    }

    if (_nameRequested) {
      sections.add(_SectionData(
        icon: Icons.person_outline,
        label: 'Name',
        value: _savedName ?? 'Not provided',
      ));
    }

    if (_emailRequested) {
      sections.add(_SectionData(
        icon: Icons.email_outlined,
        label: 'Email',
        value: _savedEmail ?? 'Not provided',
      ));
    }

    if (_phoneRequested) {
      sections.add(_SectionData(
        icon: Icons.phone_outlined,
        label: 'Phone',
        value: _savedPhone != null
            ? _formatPhoneDisplay(_savedPhone!)
            : 'Not provided',
      ));
    }

    if (sections.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (final section in sections)
          InkWell(
            onTap: _isReceipt ? null : () => _onSectionTap(section.label),
            child: Padding(
              padding: _kSectionButtonPadding,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: Icon(section.icon, size: 20, color: subFg),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          section.label,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _fieldErrors.containsKey(section.label)
                                  ? Colors.red
                                  : fg),
                        ),
                        Text(
                          _fieldErrors[section.label] ?? section.value,
                          style: TextStyle(
                              fontSize: 13,
                              color: _fieldErrors.containsKey(section.label)
                                  ? Colors.red
                                  : subFg),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (!_isReceipt)
                    Icon(Icons.chevron_right, size: 20, color: subFg),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _onSectionTap(String sectionLabel) {
    setState(() => _fieldErrors.remove(sectionLabel));
    switch (sectionLabel) {
      case 'Payment Method':
        _editPaymentMethod();
      case 'Shipping Address':
        _editShippingAddress();
      case 'Shipping Method':
        _chooseShippingOption();
      case 'Name':
        _editName();
      case 'Email':
        _editEmail();
      case 'Phone':
        _editPhone();
    }
  }

  void _editPaymentMethod() {
    final savedMethods = (_formData['saved_methods'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];
    final additionalMethods = (_formData['additional_methods'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];

    if (savedMethods.isEmpty && additionalMethods.isEmpty) {
      _openPaymentMethodDirect();
      return;
    }

    final options = <Map<String, dynamic>>[
      {'title': 'New card', 'id': '__new_card__'},
      ...savedMethods,
      ...additionalMethods,
    ];

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Payment Method'),
        children: options.map((opt) {
          final title = opt['title'] as String? ?? '';
          return SimpleDialogOption(
            onPressed: () {
              Navigator.of(ctx).pop();
              final id = opt['id'] as String? ?? '';
              if (id == '__new_card__') {
                _openPaymentMethodDirect();
              } else {
                setState(() {
                  _paymentMethod = title;
                  _credentialsData = json.encode({
                    'type': 'saved',
                    'id': id,
                    'tmp_password': opt['tmp_password'] ?? '',
                  });
                });
              }
            },
            child: ListTile(
              title: Text(title),
              contentPadding: EdgeInsets.zero,
            ),
          );
        }).toList(),
      ),
    );
  }

  void _openPaymentMethodDirect() {
    final url = _formData['url'] as String?;
    if (url != null && url.isNotEmpty) {
      _showWebViewPayment(url);
      return;
    }
    final nativeParams = _formData['native_params'] as Map<String, dynamic>?;
    final publishableKey = nativeParams?['publishable_key'] as String? ??
        nativeParams?['publishableKey'] as String?;
    if (publishableKey != null && publishableKey.isNotEmpty) {
      _showNativeCardForm(publishableKey, nativeParams!);
      return;
    }
    final providerUrl = nativeParams?['url'] as String?;
    if (providerUrl != null && providerUrl.isNotEmpty) {
      _showWebViewPayment(providerUrl);
    }
  }

  void _showNativeCardForm(String publishableKey, Map<String, dynamic> nativeParams) {
    final needCountry = nativeParams['need_country'] == true;
    final needZip = nativeParams['need_zip'] == true;
    final needCardholderName = nativeParams['need_cardholder_name'] == true;
    final cardNumberCtrl = TextEditingController();
    final expiryCtrl = TextEditingController();
    final cvcCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final countryCtrl = TextEditingController();
    final zipCtrl = TextEditingController();
    bool isLoading = false;
    Map<String, String> cardErrors = {};

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Card Details'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: cardNumberCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d ]')),
                    _CardNumberFormatter(),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Card Number',
                    hintText: '4242 4242 4242 4242',
                    border: const OutlineInputBorder(),
                    errorText: cardErrors['number'],
                  ),
                  onChanged: (_) {
                    if (cardErrors.containsKey('number')) {
                      setDialogState(() => cardErrors.remove('number'));
                    }
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: expiryCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[\d/]')),
                          _ExpiryDateFormatter(),
                        ],
                        decoration: InputDecoration(
                          labelText: 'MM/YY',
                          hintText: 'MM/YY',
                          border: const OutlineInputBorder(),
                          errorText: cardErrors['expiry'],
                        ),
                        onChanged: (_) {
                          if (cardErrors.containsKey('expiry')) {
                            setDialogState(() => cardErrors.remove('expiry'));
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: cvcCtrl,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        decoration: InputDecoration(
                          labelText: 'CVC',
                          border: const OutlineInputBorder(),
                          errorText: cardErrors['cvc'],
                        ),
                        onChanged: (_) {
                          if (cardErrors.containsKey('cvc')) {
                            setDialogState(() => cardErrors.remove('cvc'));
                          }
                        },
                      ),
                    ),
                  ],
                ),
                if (needCardholderName) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(64),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Cardholder Name',
                      border: const OutlineInputBorder(),
                      errorText: cardErrors['name'],
                    ),
                  ),
                ],
                if (needCountry) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: countryCtrl,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(2),
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z]')),
                    ],
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: 'Country',
                      hintText: 'US',
                      border: const OutlineInputBorder(),
                      errorText: cardErrors['country'],
                    ),
                  ),
                ],
                if (needZip) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: zipCtrl,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(10),
                    ],
                    decoration: InputDecoration(
                      labelText: 'ZIP / Postal Code',
                      border: const OutlineInputBorder(),
                      errorText: cardErrors['zip'],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      final rawNumber = cardNumberCtrl.text.replaceAll(' ', '');
                      final errors = <String, String>{};

                      if (rawNumber.length < 13 || !_luhnCheck(rawNumber)) {
                        errors['number'] = 'Invalid card number';
                      }

                      final expiryParts = expiryCtrl.text.split('/');
                      if (expiryParts.length != 2 ||
                          expiryParts[0].length != 2 ||
                          expiryParts[1].length != 2) {
                        errors['expiry'] = 'Invalid date';
                      } else {
                        final month = int.tryParse(expiryParts[0]) ?? 0;
                        final year =
                            2000 + (int.tryParse(expiryParts[1]) ?? 0);
                        if (month < 1 || month > 12) {
                          errors['expiry'] = 'Invalid month';
                        } else {
                          final now = DateTime.now();
                          if (year < now.year ||
                              (year == now.year && month < now.month)) {
                            errors['expiry'] = 'Card expired';
                          }
                        }
                      }

                      if (cvcCtrl.text.length < 3) {
                        errors['cvc'] = 'Invalid CVC';
                      }

                      if (needCardholderName && nameCtrl.text.trim().isEmpty) {
                        errors['name'] = 'Name required';
                      }
                      if (needCountry && countryCtrl.text.trim().length != 2) {
                        errors['country'] = 'Invalid country code';
                      }
                      if (needZip && zipCtrl.text.trim().isEmpty) {
                        errors['zip'] = 'ZIP required';
                      }

                      if (errors.isNotEmpty) {
                        setDialogState(() => cardErrors = errors);
                        return;
                      }

                      setDialogState(() => isLoading = true);
                      try {
                        final expMonth = expiryParts[0];
                        final expYear = expiryParts[1];
                        final token = await _tokenizeCard(
                          publishableKey: publishableKey,
                          cardNumber: rawNumber,
                          expMonth: expMonth,
                          expYear: expYear,
                          cvc: cvcCtrl.text,
                          name: needCardholderName ? nameCtrl.text : null,
                          country: needCountry ? countryCtrl.text : null,
                          zip: needZip ? zipCtrl.text : null,
                        );
                        if (!mounted) return;
                        setState(() {
                          _credentialsData = token;
                          _paymentMethod =
                              'Card ****${rawNumber.substring(rawNumber.length - 4)}';
                        });
                        Navigator.of(ctx).pop();
                      } catch (e) {
                        setDialogState(() => isLoading = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Card error: $e')),
                          );
                        }
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String> _tokenizeCard({
    required String publishableKey,
    required String cardNumber,
    required String expMonth,
    required String expYear,
    required String cvc,
    String? name,
    String? country,
    String? zip,
  }) async {
    final provider = _formData['native_provider'] as String? ?? '';
    if (provider.toLowerCase().contains('stripe')) {
      return _tokenizeStripe(
        publishableKey: publishableKey,
        cardNumber: cardNumber,
        expMonth: expMonth,
        expYear: expYear,
        cvc: cvc,
        name: name,
        country: country,
        zip: zip,
      );
    }
    if (provider.toLowerCase().contains('smartglocal')) {
      return _tokenizeSmartGlocal(
        publishableKey: publishableKey,
        cardNumber: cardNumber,
        expMonth: expMonth,
        expYear: expYear,
        cvc: cvc,
      );
    }
    throw UnsupportedError('Unsupported native provider: $provider');
  }

  Future<String> _tokenizeStripe({
    required String publishableKey,
    required String cardNumber,
    required String expMonth,
    required String expYear,
    required String cvc,
    String? name,
    String? country,
    String? zip,
  }) async {
    final body = <String, String>{
      'card[number]': cardNumber,
      'card[exp_month]': expMonth,
      'card[exp_year]': expYear,
      'card[cvc]': cvc,
    };
    if (name != null && name.isNotEmpty) body['card[name]'] = name;
    if (country != null && country.isNotEmpty) body['card[address_country]'] = country;
    if (zip != null && zip.isNotEmpty) body['card[address_zip]'] = zip;

    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('https://api.stripe.com/v1/tokens'));
      request.headers.set('Authorization', 'Bearer $publishableKey');
      request.headers.set('Content-Type', 'application/x-www-form-urlencoded');
      request.headers.set('Stripe-Version', '2015-10-12');
      request.headers.set('X-Stripe-User-Agent', '{"lang":"dart","publisher":"anthropic"}');
      final encodedBody = body.entries
          .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
          .join('&');
      request.write(encodedBody);
      final response = await request.close();
      final respBody = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        final err = json.decode(respBody);
        throw Exception(err['error']?['message'] ?? 'Stripe tokenization failed');
      }
      final tokenData = json.decode(respBody) as Map<String, dynamic>;
      return json.encode({'type': 'card', 'id': tokenData['id']});
    } finally {
      client.close();
    }
  }

  Future<String> _tokenizeSmartGlocal({
    required String publishableKey,
    required String cardNumber,
    required String expMonth,
    required String expYear,
    required String cvc,
  }) async {
    final body = json.encode({
      'card': {
        'number': cardNumber,
        'expiration_month': expMonth,
        'expiration_year': expYear,
        'security_code': cvc,
      },
    });
    final nativeParams = _formData['native_params'] as Map<String, dynamic>? ?? {};
    final tokenizeUrl = nativeParams['tokenize_url'] as String? ?? '';
    final publicToken = nativeParams['public_token'] as String? ?? publishableKey;
    final String apiUrl;
    if (tokenizeUrl.isNotEmpty) {
      apiUrl = tokenizeUrl.endsWith('/') ? '${tokenizeUrl}cds/v1/tokenize/card' : tokenizeUrl;
    } else {
      final isTest = widget.data.isTest || (_formData['invoice_is_test'] == true);
      apiUrl = isTest
          ? 'https://tgb-playground.smart-glocal.com/cds/v1/tokenize/card'
          : 'https://tgb.smart-glocal.com/cds/v1/tokenize/card';
    }
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(apiUrl));
      request.headers.set('X-PUBLIC-TOKEN', publicToken);
      request.headers.set('Content-Type', 'application/json');
      request.write(body);
      final response = await request.close();
      final respBody = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw Exception('SmartGlocal tokenization failed');
      }
      final tokenData = json.decode(respBody) as Map<String, dynamic>;
      final data = tokenData['data'] as Map<String, dynamic>?;
      return json.encode({'type': 'card', 'token': data?['token'] ?? ''});
    } finally {
      client.close();
    }
  }

  void _editShippingAddress() {
    final street1Ctrl = TextEditingController(text: _street1 ?? '');
    final street2Ctrl = TextEditingController(text: _street2 ?? '');
    final cityCtrl = TextEditingController(text: _city ?? '');
    final stateCtrl = TextEditingController(text: _addrState ?? '');
    final countryCtrl = TextEditingController(text: _country ?? '');
    final postcodeCtrl = TextEditingController(text: _postcode ?? '');
    Map<String, String> addrErrors = {};

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Shipping Address'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: street1Ctrl,
                  autofocus: true,
                  inputFormatters: [LengthLimitingTextInputFormatter(64)],
                  decoration: InputDecoration(
                    labelText: 'Street Address',
                    border: const OutlineInputBorder(),
                    errorText: addrErrors['street1'],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: street2Ctrl,
                  inputFormatters: [LengthLimitingTextInputFormatter(64)],
                  decoration: const InputDecoration(
                    labelText: 'Street Address 2 (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cityCtrl,
                  inputFormatters: [LengthLimitingTextInputFormatter(64)],
                  decoration: InputDecoration(
                    labelText: 'City',
                    border: const OutlineInputBorder(),
                    errorText: addrErrors['city'],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: stateCtrl,
                  inputFormatters: [LengthLimitingTextInputFormatter(64)],
                  decoration: const InputDecoration(
                    labelText: 'State / Province',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: countryCtrl,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(2),
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z]')),
                  ],
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Country (ISO code)',
                    hintText: 'US',
                    border: const OutlineInputBorder(),
                    errorText: addrErrors['country'],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: postcodeCtrl,
                  inputFormatters: [LengthLimitingTextInputFormatter(10)],
                  decoration: InputDecoration(
                    labelText: 'Postal Code',
                    border: const OutlineInputBorder(),
                    errorText: addrErrors['postcode'],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final errors = <String, String>{};
                if (street1Ctrl.text.trim().isEmpty) {
                  errors['street1'] = 'Street address required';
                }
                if (cityCtrl.text.trim().length < 2) {
                  errors['city'] = 'City required';
                }
                if (countryCtrl.text.trim().isEmpty) {
                  errors['country'] = 'Country required';
                }
                if (postcodeCtrl.text.trim().isEmpty) {
                  errors['postcode'] = 'Postal code required';
                }
                if (errors.isNotEmpty) {
                  setDialogState(() => addrErrors = errors);
                  return;
                }
                setState(() {
                  _street1 = street1Ctrl.text.trim();
                  _street2 = street2Ctrl.text.trim();
                  _city = cityCtrl.text.trim();
                  _addrState = stateCtrl.text.trim();
                  _country = countryCtrl.text.trim().toUpperCase();
                  _postcode = postcodeCtrl.text.trim();
                  _shippingAddress = _buildFullAddress({
                    'street1': _street1,
                    'street2': _street2,
                    'city': _city,
                    'state': _addrState,
                    'country': _country,
                    'postcode': _postcode,
                  });
                  _requestedInfoId = null;
                });
                Navigator.of(ctx).pop();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _editName() {
    final controller = TextEditingController(text: _savedName ?? '');
    String? errorText;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Name'),
          content: TextField(
            controller: controller,
            autofocus: true,
            inputFormatters: [LengthLimitingTextInputFormatter(64)],
            decoration: InputDecoration(
              labelText: 'Full Name',
              border: const OutlineInputBorder(),
              errorText: errorText,
            ),
            onChanged: (_) {
              if (errorText != null) {
                setDialogState(() => errorText = null);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (controller.text.trim().isEmpty) {
                  setDialogState(() => errorText = 'Name is required');
                  return;
                }
                setState(() {
                  _savedName = controller.text.trim();
                  _requestedInfoId = null;
                });
                Navigator.of(ctx).pop();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _editEmail() {
    final controller = TextEditingController(text: _savedEmail ?? '');
    String? errorText;
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Email'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            inputFormatters: [LengthLimitingTextInputFormatter(128)],
            decoration: InputDecoration(
              labelText: 'Email Address',
              border: const OutlineInputBorder(),
              errorText: errorText,
            ),
            onChanged: (_) {
              if (errorText != null) {
                setDialogState(() => errorText = null);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final val = controller.text.trim();
                if (val.isEmpty || !emailRegex.hasMatch(val)) {
                  setDialogState(
                      () => errorText = 'Enter a valid email address');
                  return;
                }
                setState(() {
                  _savedEmail = val;
                  _requestedInfoId = null;
                });
                Navigator.of(ctx).pop();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _editPhone() {
    final controller = TextEditingController(text: _savedPhone ?? '');
    String? errorText;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Phone'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              LengthLimitingTextInputFormatter(16),
              FilteringTextInputFormatter.allow(RegExp(r'[\d+() -]')),
            ],
            decoration: InputDecoration(
              labelText: 'Phone Number',
              hintText: '+1 234 567 8900',
              border: const OutlineInputBorder(),
              errorText: errorText,
            ),
            onChanged: (_) {
              if (errorText != null) {
                setDialogState(() => errorText = null);
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final digits =
                    controller.text.replaceAll(RegExp(r'[^\d+]'), '');
                if (digits.length < 7) {
                  setDialogState(
                      () => errorText = 'Enter a valid phone number');
                  return;
                }
                setState(() {
                  _savedPhone = digits;
                  _requestedInfoId = null;
                });
                Navigator.of(ctx).pop();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _chooseShippingOption() {
    if (_shippingOptions.isEmpty) return;
    final currency = _formData['currency'] as String? ?? widget.data.currency;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Shipping Method'),
        children: _shippingOptions.map((opt) {
          final title = opt['title'] as String? ?? '';
          final prices = (opt['prices'] as List<dynamic>?)
                  ?.whereType<Map<String, dynamic>>()
                  .toList() ??
              [];
          int optTotal = 0;
          for (final p in prices) {
            optTotal += (p['amount'] as num?)?.toInt() ?? 0;
          }
          final priceStr = _formatAmount(optTotal, currency);
          return SimpleDialogOption(
            onPressed: () {
              setState(() {
                _selectedShippingId = opt['id'] as String?;
                _shippingMethod = title;
                _shippingPrices = prices;
              });
              Navigator.of(ctx).pop();
            },
            child: ListTile(
              title: Text(title),
              trailing: Text(priceStr),
              selected: _selectedShippingId == opt['id'],
              contentPadding: EdgeInsets.zero,
            ),
          );
        }).toList(),
      ),
    );
  }

  void _panelChooseTips(
      String currency, Color accent, Color fg, bool isDark) {
    final controller = TextEditingController();
    String? tipError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Custom Tip'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Enter tip amount',
                  prefixText: _currencySymbol(currency),
                  border: const OutlineInputBorder(),
                  errorText: tipError,
                ),
                onChanged: (_) {
                  if (tipError != null) {
                    setDialogState(() => tipError = null);
                  }
                },
              ),
              if (_suggestedTips.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: _suggestedTips.map((tip) {
                    return ActionChip(
                      label: Text(_formatAmount(tip, currency)),
                      onPressed: () {
                        setState(() => _selectedTip = tip);
                        Navigator.of(ctx).pop();
                      },
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final val = double.tryParse(controller.text);
                if (val != null && val >= 0) {
                  final exp = _currencyExponent(currency);
                  int multiplier = 1;
                  for (int i = 0; i < exp; i++) multiplier *= 10;
                  final minorVal = (val * multiplier).round();
                  if (_maxTip > 0 && minorVal > _maxTip) {
                    setDialogState(() {
                      tipError =
                          'Max tip: ${_formatAmount(_maxTip, currency)}';
                    });
                    return;
                  }
                  setState(() => _selectedTip = minorVal);
                  Navigator.of(ctx).pop();
                } else {
                  setDialogState(() => tipError = 'Enter a valid amount');
                }
              },
              child: const Text('Set'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomButtons(
      Color accentBg, Color accentFg, Color fg, Color divider) {
    final currency = _formData['currency'] as String? ?? widget.data.currency;
    final total = _isReceipt
        ? ((_formData['total_amount'] as num?)?.toInt() ?? 0)
        : _computeTotal() + _selectedTip;

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: divider, width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(8, 12, 15, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_isReceipt && _state != _PanelState.done)
            SizedBox(
              width: double.infinity,
              height: _kSubmitHeight,
              child: FilledButton(
                onPressed:
                    _state == _PanelState.submitting ? null : _submitPayment,
                style: FilledButton.styleFrom(
                  backgroundColor: accentBg,
                  foregroundColor: accentFg,
                  textStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
                child: _state == _PanelState.submitting
                    ? SizedBox(
                        width: _kProgressSize,
                        height: _kProgressSize,
                        child: CircularProgressIndicator(
                          strokeWidth: _kProgressStroke,
                          valueColor: AlwaysStoppedAnimation(accentFg),
                        ),
                      )
                    : Text(
                        'PAY ${_formatAmount(total, currency)}',
                      ),
              ),
            ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: _kSubmitHeight,
            child: TextButton(
              onPressed: (_isReceipt || _state == _PanelState.done)
                  ? () => Navigator.of(context).pop()
                  : _requestClose,
              style: TextButton.styleFrom(
                foregroundColor: fg,
                textStyle:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              child: Text(_isReceipt || _state == _PanelState.done
                  ? 'DONE'
                  : 'CANCEL'),
            ),
          ),
        ],
      ),
    );
  }

  String _formatReceiptDate(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  String? _buildFullAddress(Map<String, dynamic> saved) {
    final parts = <String>[];
    final s1 = saved['street1'] as String? ?? '';
    if (s1.isNotEmpty) parts.add(s1);
    final s2 = saved['street2'] as String? ?? '';
    if (s2.isNotEmpty) parts.add(s2);
    final city = saved['city'] as String? ?? '';
    if (city.isNotEmpty) parts.add(city);
    final state = saved['state'] as String? ?? '';
    if (state.isNotEmpty) parts.add(state);
    final countryISO = saved['country'] as String? ?? '';
    if (countryISO.isNotEmpty) {
      parts.add(_countryName(countryISO));
    }
    final postcode = saved['postcode'] as String? ?? '';
    if (postcode.isNotEmpty) parts.add(postcode);
    return parts.isEmpty ? null : parts.join(', ');
  }

  static String _countryName(String iso2) => countryNameByIso(iso2);

  static String _formatPhoneDisplay(String phone) {
    if (phone.isEmpty) return phone;
    String digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (!digits.startsWith('+')) digits = '+$digits';
    if (digits.length <= 4) return digits;
    if (digits.startsWith('+1') && digits.length == 12) {
      return '+1 (${digits.substring(2, 5)}) ${digits.substring(5, 8)}-${digits.substring(8)}';
    }
    if (digits.startsWith('+44') && digits.length >= 13) {
      return '+44 ${digits.substring(3, 7)} ${digits.substring(7)}';
    }
    if (digits.startsWith('+7') && digits.length == 12) {
      return '+7 (${digits.substring(2, 5)}) ${digits.substring(5, 8)}-${digits.substring(8, 10)}-${digits.substring(10)}';
    }
    final cc = digits.substring(0, digits.length <= 12 ? 2 : 3);
    final rest = digits.substring(cc.length);
    final buf = StringBuffer(cc);
    for (int i = 0; i < rest.length; i++) {
      if (i > 0 && i % 3 == 0) buf.write(' ');
      buf.write(rest[i]);
    }
    return buf.toString();
  }

  bool _hasChanges() {
    return _paymentMethod != _initialPaymentMethod ||
        _shippingAddress != _initialShippingAddress ||
        _savedName != _initialName ||
        _savedEmail != _initialEmail ||
        _savedPhone != _initialPhone;
  }

  void _requestClose() {
    if (_state == _PanelState.form && _hasChanges()) {
      showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Discard changes?'),
          content: const Text(
            'You have unsaved changes. Are you sure you want to close?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop(true);
                Navigator.of(context).pop();
              },
              child: const Text('Discard'),
            ),
          ],
        ),
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  void _showWebViewPayment(String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeCtx) => _PaymentWebViewPage(
          url: url,
          onPaymentDone: (token) {
            if (token != null) {
              setState(() {
                _credentialsData = token;
                _paymentMethod = 'Card (web)';
              });
            }
          },
        ),
      ),
    );
  }

  static bool _luhnCheck(String number) {
    var odd = true;
    var sum = 0;
    for (var i = number.length - 1; i >= 0; i--) {
      var digit = number.codeUnitAt(i) - 48;
      if (digit < 0 || digit > 9) return false;
      odd = !odd;
      if (odd) digit *= 2;
      if (digit > 9) digit -= 9;
      sum += digit;
    }
    return sum % 10 == 0;
  }

  static List<int> _cardNumberGroups(String sanitized) {
    if (sanitized.length >= 2) {
      final prefix = int.tryParse(sanitized.substring(0, 2)) ?? 0;
      if (prefix == 34 || prefix == 37) return [4, 6, 5];
      if (prefix == 30 || prefix == 36 || prefix == 38 || prefix == 39) {
        if (sanitized.length <= 14) return [4, 6, 4];
      }
    }
    return [4, 4, 4, 4];
  }
}

class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(' ', '');
    if (digits.length > 19) digits = digits.substring(0, 19);

    final groups = _PaymentPanelState._cardNumberGroups(digits);
    final buf = StringBuffer();
    var pos = 0;
    var cursorTarget = newValue.selection.baseOffset;
    var newCursor = cursorTarget;

    for (final len in groups) {
      if (pos >= digits.length) break;
      if (buf.isNotEmpty) {
        buf.write(' ');
        if (pos < cursorTarget ||
            (pos == cursorTarget && buf.length <= cursorTarget + 1)) {
          newCursor++;
        }
      }
      final end = (pos + len).clamp(0, digits.length);
      buf.write(digits.substring(pos, end));
      pos = end;
    }

    final text = buf.toString();
    newCursor = newCursor.clamp(0, text.length);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: newCursor),
    );
  }
}

class _ExpiryDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll('/', '');
    digits = digits.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
          text: '', selection: TextSelection.collapsed(offset: 0));
    }

    if (digits[0] != '0' && digits[0] != '1') {
      digits = '0$digits';
    } else if (digits.length > 1 &&
        digits[0] == '1' &&
        digits.codeUnitAt(1) - 48 > 2) {
      digits = digits.substring(0, 2);
    }

    if (digits.length > 4) digits = digits.substring(0, 4);

    String text;
    if (digits.length <= 2) {
      text = digits;
    } else {
      text = '${digits.substring(0, 2)}/${digits.substring(2)}';
    }

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _PaymentWebViewPage extends StatefulWidget {
  final String url;
  final ValueChanged<String?> onPaymentDone;

  const _PaymentWebViewPage({required this.url, required this.onPaymentDone});

  @override
  State<_PaymentWebViewPage> createState() => _PaymentWebViewPageState();
}

class _PaymentWebViewPageState extends State<_PaymentWebViewPage> {
  WebViewController? _controller;
  bool _webViewAvailable = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    try {
      final ctrl = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri != null && uri.scheme == 'tg') {
              final token = uri.queryParameters['payment_token'] ??
                  uri.queryParameters['token'];
              widget.onPaymentDone(token);
              Navigator.of(context).pop();
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ))
        ..loadRequest(Uri.parse(widget.url));
      _controller = ctrl;
      _webViewAvailable = true;
    } catch (_) {
      _webViewAvailable = false;
      launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_webViewAvailable || _controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller!),
          if (_loading)
            const LinearProgressIndicator(),
        ],
      ),
    );
  }
}

class _SectionData {
  final IconData icon;
  final String label;
  final String value;

  const _SectionData({
    required this.icon,
    required this.label,
    required this.value,
  });
}

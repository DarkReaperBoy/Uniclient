import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../bridge/engine_service.dart';
import '../theme/telegram_palette.dart';

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
const _kProgressFadeDuration = Duration(milliseconds: 400);
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
  String? _cachedPhotoPath;

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

  Future<void> _submitPayment() async {
    if (_termsUrl.isNotEmpty && !_termsAccepted) {
      _showTermsDialog();
      return;
    }
    setState(() => _state = _PanelState.submitting);
    final engine = context.read<EngineService>();
    try {
      if (_requestedInfoId == null && _hasRequestedInfo) {
        final info = <String, dynamic>{};
        if (_nameRequested && _savedName != null) info['name'] = _savedName;
        if (_phoneRequested && _savedPhone != null) info['phone'] = _savedPhone;
        if (_emailRequested && _savedEmail != null) info['email'] = _savedEmail;
        if (_shippingRequested && _shippingAddress != null) {
          final saved = _formData['saved_info'] as Map<String, dynamic>?;
          if (saved != null) {
            info['street1'] = saved['street1'] ?? '';
            info['street2'] = saved['street2'] ?? '';
            info['city'] = saved['city'] ?? '';
            info['state'] = saved['state'] ?? '';
            info['country'] = saved['country'] ?? '';
            info['postcode'] = saved['postcode'] ?? '';
          }
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
      setState(() {
        _state = _PanelState.form;
        _errorText = e.toString();
      });
    }
  }

  bool get _hasRequestedInfo =>
      _nameRequested || _phoneRequested || _emailRequested || _shippingRequested;

  void _showTermsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
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
                  value: _termsAccepted,
                  onChanged: (v) {
                    setState(() => _termsAccepted = v ?? false);
                    Navigator.of(ctx).pop();
                    if (v == true) _submitPayment();
                  },
                ),
                const Expanded(child: Text('I agree to the Terms of Service')),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
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
    final accentFg = isDark ? Colors.white : Colors.white;

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
            onPressed: () => Navigator.of(context).pop(),
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
    if (_cachedPhotoPath != null) {
      return Image.file(
        File(_cachedPhotoPath!),
        width: _kThumbSize,
        height: _kThumbSize,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(
          Icons.receipt_long, size: 40,
          color: subFg.withValues(alpha: 0.4),
        ),
      );
    }
    _downloadAndCachePhoto(photoUrl);
    return Icon(
      Icons.receipt_long, size: 40,
      color: subFg.withValues(alpha: 0.4),
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

  Widget _buildTipsSection(
      Color accent, Color fg, bool isDark, String currency) {
    return Padding(
      padding: _kTipButtonsPadding,
      child: Wrap(
        spacing: _kTipButtonSkip,
        runSpacing: _kTipButtonSkip,
        children: _suggestedTips.map((tip) {
          final isSelected = _selectedTip == tip;
          return SizedBox(
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
                    ? (isDark ? Colors.white : Colors.white)
                    : accent,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                textStyle:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              child: Text(_formatAmount(tip, currency)),
            ),
          );
        }).toList(),
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
                              color: fg),
                        ),
                        Text(
                          section.value,
                          style: TextStyle(fontSize: 13, color: subFg),
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
    switch (sectionLabel) {
      case 'Payment Method':
        _editPaymentMethod();
      case 'Shipping Address':
        _editField('Shipping Address', _shippingAddress ?? '', (v) {
          setState(() => _shippingAddress = v);
        });
      case 'Shipping Method':
        _chooseShippingOption();
      case 'Name':
        _editField('Name', _savedName ?? '', (v) {
          setState(() => _savedName = v);
        });
      case 'Email':
        _editField('Email', _savedEmail ?? '', (v) {
          setState(() => _savedEmail = v);
        });
      case 'Phone':
        _editField('Phone', _savedPhone ?? '', (v) {
          setState(() => _savedPhone = v);
        });
    }
  }

  void _editPaymentMethod() {
    final url = _formData['url'] as String?;
    if (url != null && url.isNotEmpty) {
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
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
      launchUrl(Uri.parse(providerUrl), mode: LaunchMode.externalApplication);
    }
  }

  void _showNativeCardForm(String publishableKey, Map<String, dynamic> nativeParams) {
    final needCountry = nativeParams['need_country'] == true;
    final needZip = nativeParams['need_zip'] == true;
    final needCardholderName = nativeParams['need_cardholder_name'] == true;
    final cardNumberCtrl = TextEditingController();
    final expMonthCtrl = TextEditingController();
    final expYearCtrl = TextEditingController();
    final cvcCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final countryCtrl = TextEditingController();
    final zipCtrl = TextEditingController();
    bool isLoading = false;

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
                  decoration: const InputDecoration(
                    labelText: 'Card Number',
                    hintText: '4242 4242 4242 4242',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: expMonthCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'MM',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: expYearCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'YY',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: cvcCtrl,
                        keyboardType: TextInputType.number,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'CVC',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                if (needCardholderName) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Cardholder Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (needCountry) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: countryCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Country',
                      hintText: 'US',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                if (needZip) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: zipCtrl,
                    decoration: const InputDecoration(
                      labelText: 'ZIP / Postal Code',
                      border: OutlineInputBorder(),
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
                      setDialogState(() => isLoading = true);
                      try {
                        final token = await _tokenizeCard(
                          publishableKey: publishableKey,
                          cardNumber: cardNumberCtrl.text.replaceAll(' ', ''),
                          expMonth: expMonthCtrl.text,
                          expYear: expYearCtrl.text,
                          cvc: cvcCtrl.text,
                          name: needCardholderName ? nameCtrl.text : null,
                          country: needCountry ? countryCtrl.text : null,
                          zip: needZip ? zipCtrl.text : null,
                        );
                        if (!mounted) return;
                        setState(() {
                          _credentialsData = token;
                          _paymentMethod = 'Card ****${cardNumberCtrl.text.replaceAll(' ', '').substring(cardNumberCtrl.text.replaceAll(' ', '').length - 4)}';
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
                      width: 16, height: 16,
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
    final client = HttpClient();
    try {
      final request = await client.postUrl(
        Uri.parse('https://tgb-playground.smart-glocal.com/cds/v1/tokenize/card'),
      );
      request.headers.set('X-PUBLIC-TOKEN', publishableKey);
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

  void _editField(String label, String currentValue, ValueChanged<String> onSave) {
    final controller = TextEditingController(text: currentValue);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit $label'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Enter $label',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              onSave(controller.text);
              Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom Tip'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Enter tip amount',
                prefixText: _currencySymbol(currency),
                border: const OutlineInputBorder(),
              ),
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
              final val = int.tryParse(controller.text);
              if (val != null && val >= 0) {
                final exp = _currencyExponent(currency);
                int multiplier = 1;
                for (int i = 0; i < exp; i++) multiplier *= 10;
                final minorVal = val * multiplier;
                if (_maxTip <= 0 || minorVal <= _maxTip) {
                  setState(() => _selectedTip = minorVal);
                }
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Set'),
          ),
        ],
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
      padding: const EdgeInsets.symmetric(
          horizontal: _kSubmitHPadding / 2, vertical: 8),
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
              onPressed: () => Navigator.of(context).pop(),
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

  static String _countryName(String iso2) {
    const countries = {
      'US': 'United States', 'GB': 'United Kingdom', 'DE': 'Germany',
      'FR': 'France', 'IT': 'Italy', 'ES': 'Spain', 'CA': 'Canada',
      'AU': 'Australia', 'JP': 'Japan', 'CN': 'China', 'IN': 'India',
      'BR': 'Brazil', 'RU': 'Russia', 'KR': 'South Korea', 'MX': 'Mexico',
      'NL': 'Netherlands', 'SE': 'Sweden', 'NO': 'Norway', 'DK': 'Denmark',
      'FI': 'Finland', 'PL': 'Poland', 'AT': 'Austria', 'CH': 'Switzerland',
      'BE': 'Belgium', 'PT': 'Portugal', 'CZ': 'Czech Republic',
      'IE': 'Ireland', 'NZ': 'New Zealand', 'SG': 'Singapore',
      'HK': 'Hong Kong', 'TW': 'Taiwan', 'TH': 'Thailand',
      'MY': 'Malaysia', 'PH': 'Philippines', 'ID': 'Indonesia',
      'TR': 'Turkey', 'SA': 'Saudi Arabia', 'AE': 'United Arab Emirates',
      'IL': 'Israel', 'EG': 'Egypt', 'ZA': 'South Africa', 'NG': 'Nigeria',
      'AR': 'Argentina', 'CL': 'Chile', 'CO': 'Colombia', 'PE': 'Peru',
      'UA': 'Ukraine', 'RO': 'Romania', 'HU': 'Hungary', 'GR': 'Greece',
      'IR': 'Iran',
    };
    return countries[iso2.toUpperCase()] ?? iso2;
  }

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

  Future<void> _downloadAndCachePhoto(String url) async {
    if (_cachedPhotoPath != null) return;
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode == 200) {
        final bytes = await response.fold<List<int>>(
          <int>[],
          (prev, chunk) => prev..addAll(chunk),
        );
        final tmpFile = File('${Directory.systemTemp.path}/payment_thumb_${url.hashCode}.jpg');
        await tmpFile.writeAsBytes(bytes);
        if (mounted) {
          setState(() => _cachedPhotoPath = tmpFile.path);
        }
      }
      client.close();
    } catch (_) {}
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

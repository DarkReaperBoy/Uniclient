import 'dart:async';

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
          final street1 = saved['street1'] as String? ?? '';
          final city = saved['city'] as String? ?? '';
          if (street1.isNotEmpty && city.isNotEmpty) {
            _shippingAddress = '$street1, $city';
          }
        }

        final savedCreds = data['saved_credentials'] as Map<String, dynamic>?;
        if (savedCreds != null) {
          _paymentMethod = savedCreds['title'] as String?;
        }

        if (_isReceipt) {
          _shippingMethod = data['shipping_option'] as String?;
          _paymentMethod = data['credentials_title'] as String?;
        }

        final shippingOptions = data['shipping_options'] as List<dynamic>?;
        if (shippingOptions != null && shippingOptions.isNotEmpty) {
          final selectedId = data['selected_shipping_id'] as String?;
          if (selectedId != null) {
            for (final opt in shippingOptions) {
              if (opt is Map<String, dynamic> && opt['id'] == selectedId) {
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
      final submitData = <String, dynamic>{
        'form_id': _formData['form_id'],
      };
      if (_selectedTip > 0) {
        submitData['tip_amount'] = _selectedTip;
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
        animation: Listenable.merge([_spinnerAnim, _progressFade]),
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
            child: GestureDetector(
              onTap: () => _panelChooseTips(currency, accent, fg, isDark),
              child: _priceRow('Tips', _formatAmount(_tipAmount, currency), fg,
                  accent, false),
            ),
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
                child: Image.network(
                  photoUrl,
                  width: _kThumbSize,
                  height: _kThumbSize,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.receipt_long,
                    size: 40,
                    color: subFg.withValues(alpha: 0.4),
                  ),
                ),
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
        value: _savedPhone ?? 'Not provided',
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
        break;
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
    } else {
      final nativeParams = _formData['native_params'] as Map<String, dynamic>?;
      final providerUrl = nativeParams?['url'] as String?;
      if (providerUrl != null && providerUrl.isNotEmpty) {
        launchUrl(Uri.parse(providerUrl), mode: LaunchMode.externalApplication);
      }
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
              if (val != null && val >= 0 && val <= _maxTip) {
                final exp = _currencyExponent(currency);
                int multiplier = 1;
                for (int i = 0; i < exp; i++) multiplier *= 10;
                setState(() => _selectedTip = val * multiplier);
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

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../state/app_state.dart';
import '../bridge/engine_service.dart';
import 'confirm_box.dart';
import 'choose_datetime_box.dart';
import 'telegram_toast.dart';

enum _GiveawayType { random, prepaid }

Future<void> showCreateGiveawayBox(
  BuildContext context, {
  required String accountId,
  required String chatId,
  required ThemeData theme,
  List<Map<String, dynamic>>? prepaidGiveaways,
}) {
  return showTelegramBox(
    context: context,
    builder: (ctx) => _CreateGiveawayBox(
      accountId: accountId,
      chatId: chatId,
      theme: theme,
      prepaidGiveaways: prepaidGiveaways ?? [],
    ),
  );
}

class _CreateGiveawayBox extends StatefulWidget {
  final String accountId;
  final String chatId;
  final ThemeData theme;
  final List<Map<String, dynamic>> prepaidGiveaways;

  const _CreateGiveawayBox({
    required this.accountId,
    required this.chatId,
    required this.theme,
    required this.prepaidGiveaways,
  });

  @override
  State<_CreateGiveawayBox> createState() => _CreateGiveawayBoxState();
}

class _CreateGiveawayBoxState extends State<_CreateGiveawayBox> {
  _GiveawayType _type = _GiveawayType.random;
  bool _loading = true;
  bool _launching = false;
  String? _error;

  List<Map<String, dynamic>> _options = [];
  List<int> _uniqueMonths = [];
  List<int> _uniqueUsers = [];
  int _selectedOptionIndex = 0;
  int _selectedPrepaidIndex = 0;

  bool _onlyNewSubscribers = false;
  bool _showWinners = true;
  DateTime _untilDate = DateTime.now().add(const Duration(days: 7));
  final _prizeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadOptions();
    if (widget.prepaidGiveaways.isNotEmpty) {
      _type = _GiveawayType.prepaid;
    }
  }

  @override
  void dispose() {
    _prizeController.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    try {
      final engine = Provider.of<AppState>(context, listen: false).engine;
      final opts = await engine.getGiftCodeOptions(widget.accountId, widget.chatId);
      if (!mounted) return;
      setState(() {
        _options = opts;
        _uniqueMonths = opts.map((o) => o['months'] as int).toSet().toList()..sort();
        _uniqueUsers = opts.map((o) => o['users'] as int).toSet().toList()..sort();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _launchPrepaid() async {
    if (_launching) return;
    setState(() => _launching = true);

    final prepaid = widget.prepaidGiveaways[_selectedPrepaidIndex];
    final giveawayId = (prepaid['id'] as num).toInt();
    final engine = Provider.of<AppState>(context, listen: false).engine;

    try {
      await engine.launchPrepaidGiveaway(
        widget.accountId,
        widget.chatId,
        giveawayId,
        {
          'only_new_subscribers': _onlyNewSubscribers,
          'winners_are_visible': _showWinners,
          'until_date': _untilDate.millisecondsSinceEpoch ~/ 1000,
          'random_id': Random().nextInt(1 << 31),
          if (_prizeController.text.isNotEmpty)
            'prize_description': _prizeController.text,
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      showTelegramToast(context, 'Giveaway launched!');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _launching = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _launchRandomGiveaway() async {
    if (_launching || _options.isEmpty) return;
    setState(() => _launching = true);

    final selectedOpt = _selectedOptionIndex < _options.length
        ? _options[_selectedOptionIndex]
        : _options.first;
    final engine = Provider.of<AppState>(context, listen: false).engine;

    try {
      final result = await engine.launchRandomGiveaway(
        widget.accountId,
        widget.chatId,
        {
          'users': selectedOpt['users'],
          'months': selectedOpt['months'],
          'currency': selectedOpt['currency'] ?? 'USD',
          'amount': selectedOpt['amount'] ?? 0,
          if (selectedOpt['store_product'] != null)
            'store_product': selectedOpt['store_product'],
          if (selectedOpt['store_quantity'] != null)
            'store_quantity': selectedOpt['store_quantity'],
          'only_new_subscribers': _onlyNewSubscribers,
          'winners_are_visible': _showWinners,
          'until_date': _untilDate.millisecondsSinceEpoch ~/ 1000,
          'random_id': Random().nextInt(1 << 31),
          if (_prizeController.text.isNotEmpty)
            'prize_description': _prizeController.text,
        },
      );
      if (!mounted) return;
      final url = result['url'] as String?;
      if (url != null && url.isNotEmpty) {
        Navigator.of(context).pop();
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        Navigator.of(context).pop();
        showTelegramToast(context, 'Giveaway launched!');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _launching = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.theme.brightness == Brightness.dark;
    final primary = widget.theme.colorScheme.primary;
    final subColor = isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 380,
        constraints: const BoxConstraints(maxHeight: 560),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(kBoxRadius),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(isDark, primary),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _error != null
                      ? _buildError(subColor)
                      : _buildContent(isDark, primary, subColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark, Color primary) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, primary.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(kBoxRadius)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          const Icon(Icons.rocket_launch, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Boosts via Gifts', style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white,
            )),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildError(Color subColor) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: subColor),
          const SizedBox(height: 12),
          Text(
            'Failed to load giveaway options',
            style: TextStyle(fontSize: 14, color: subColor),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _error ?? '',
            style: TextStyle(fontSize: 12, color: subColor.withValues(alpha: 0.7)),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () {
              setState(() {
                _error = null;
                _loading = true;
              });
              _loadOptions();
            },
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(bool isDark, Color primary, Color subColor) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        if (widget.prepaidGiveaways.isNotEmpty) ...[
          _buildTypeSelector(isDark, primary, subColor),
          const SizedBox(height: 16),
        ],
        if (_type == _GiveawayType.prepaid)
          ..._buildPrepaidSection(isDark, primary, subColor)
        else
          ..._buildRandomSection(isDark, primary, subColor),
        const SizedBox(height: 12),
        _buildSettingsSection(isDark, primary, subColor),
        const SizedBox(height: 16),
        _buildActionButton(primary),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildTypeSelector(bool isDark, Color primary, Color subColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Giveaway Type', style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600, color: primary,
        )),
        const SizedBox(height: 8),
        _TypeRadioTile(
          title: 'Random Subscribers',
          subtitle: 'Create new premium giveaway',
          icon: Icons.people_outline,
          selected: _type == _GiveawayType.random,
          theme: widget.theme,
          onTap: () => setState(() => _type = _GiveawayType.random),
        ),
        const SizedBox(height: 4),
        _TypeRadioTile(
          title: 'Prepaid Giveaway',
          subtitle: '${widget.prepaidGiveaways.length} prepaid available',
          icon: Icons.card_giftcard,
          selected: _type == _GiveawayType.prepaid,
          theme: widget.theme,
          onTap: () => setState(() => _type = _GiveawayType.prepaid),
        ),
      ],
    );
  }

  List<Widget> _buildPrepaidSection(bool isDark, Color primary, Color subColor) {
    return [
      Text('Select prepaid giveaway', style: TextStyle(
        fontSize: 13, fontWeight: FontWeight.w600, color: primary,
      )),
      const SizedBox(height: 8),
      ...List.generate(widget.prepaidGiveaways.length, (i) {
        final g = widget.prepaidGiveaways[i];
        final months = g['months'] as int? ?? 0;
        final qty = g['quantity'] as int? ?? 0;
        final selected = _selectedPrepaidIndex == i;
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: InkWell(
            onTap: () => setState(() => _selectedPrepaidIndex = i),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: selected
                    ? primary.withValues(alpha: 0.1)
                    : (isDark ? const Color(0xFF2B3945) : const Color(0xFFF0F2F5)),
                borderRadius: BorderRadius.circular(8),
                border: selected ? Border.all(color: primary, width: 1.5) : null,
              ),
              child: Row(
                children: [
                  Icon(
                    selected ? Icons.radio_button_checked : Icons.radio_button_off,
                    size: 20, color: selected ? primary : subColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$qty × $months months Premium',
                        style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      Text(
                        '${qty * 4} boosts for your channel',
                        style: TextStyle(fontSize: 12, color: subColor),
                      ),
                    ],
                  )),
                ],
              ),
            ),
          ),
        );
      }),
    ];
  }

  List<Widget> _buildRandomSection(bool isDark, Color primary, Color subColor) {
    if (_options.isEmpty) {
      return [
        Text(
          'No premium gift options available for this channel.',
          style: TextStyle(fontSize: 13, color: subColor),
        ),
        const SizedBox(height: 12),
        Text(
          'You can share the boost link to get more boosts from subscribers.',
          style: TextStyle(fontSize: 12, color: subColor),
        ),
      ];
    }

    final selectedOpt = _selectedOptionIndex < _options.length
        ? _options[_selectedOptionIndex]
        : _options.first;
    final currency = selectedOpt['currency'] as String? ?? 'USD';
    final amount = selectedOpt['amount'] as num? ?? 0;

    return [
      Text('Premium Subscription Gifts', style: TextStyle(
        fontSize: 13, fontWeight: FontWeight.w600, color: primary,
      )),
      const SizedBox(height: 4),
      Text(
        'Gift Telegram Premium subscriptions to random subscribers.',
        style: TextStyle(fontSize: 12, color: subColor),
      ),
      const SizedBox(height: 12),
      Text('Winners', style: TextStyle(fontSize: 12, color: subColor)),
      const SizedBox(height: 4),
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: _uniqueUsers.map((u) {
          final isSelected = selectedOpt['users'] == u;
          return ChoiceChip(
            label: Text('$u'),
            selected: isSelected,
            selectedColor: primary.withValues(alpha: 0.2),
            labelStyle: TextStyle(
              fontSize: 12,
              color: isSelected ? primary : (isDark ? Colors.white70 : Colors.black54),
            ),
            onSelected: (_) {
              final idx = _options.indexWhere((o) =>
                o['users'] == u && o['months'] == selectedOpt['months']);
              if (idx >= 0) setState(() => _selectedOptionIndex = idx);
            },
          );
        }).toList(),
      ),
      const SizedBox(height: 12),
      Text('Duration', style: TextStyle(fontSize: 12, color: subColor)),
      const SizedBox(height: 4),
      Wrap(
        spacing: 6,
        runSpacing: 4,
        children: _uniqueMonths.map((m) {
          final isSelected = selectedOpt['months'] == m;
          return ChoiceChip(
            label: Text('$m mo'),
            selected: isSelected,
            selectedColor: primary.withValues(alpha: 0.2),
            labelStyle: TextStyle(
              fontSize: 12,
              color: isSelected ? primary : (isDark ? Colors.white70 : Colors.black54),
            ),
            onSelected: (_) {
              final idx = _options.indexWhere((o) =>
                o['months'] == m && o['users'] == selectedOpt['users']);
              if (idx >= 0) setState(() => _selectedOptionIndex = idx);
            },
          );
        }).toList(),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2B3945) : const Color(0xFFF0F2F5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Total', style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87)),
            Text(
              _formatAmount(amount.toInt(), currency),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primary),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildSettingsSection(bool isDark, Color primary, Color subColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: widget.theme.dividerColor),
        const SizedBox(height: 8),
        _SettingSwitch(
          label: 'Only New Subscribers',
          value: _onlyNewSubscribers,
          subColor: subColor,
          isDark: isDark,
          onChanged: (v) => setState(() => _onlyNewSubscribers = v),
        ),
        _SettingSwitch(
          label: 'Show Winners',
          value: _showWinners,
          subColor: subColor,
          isDark: isDark,
          onChanged: (v) => setState(() => _showWinners = v),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final minDate = DateTime.now().add(const Duration(days: 3));
            final maxDate = DateTime.now().add(const Duration(days: 365));
            final picked = await showCalendarBox(
              context,
              initialDate: _untilDate,
              minDate: minDate,
              maxDate: maxDate,
            );
            if (picked != null && mounted) {
              setState(() => _untilDate = picked);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(Icons.calendar_today, size: 18, color: subColor),
                const SizedBox(width: 10),
                Expanded(child: Text('End Date', style: TextStyle(
                  fontSize: 13, color: isDark ? Colors.white : Colors.black87,
                ))),
                Text(
                  '${_untilDate.day}/${_untilDate.month}/${_untilDate.year}',
                  style: TextStyle(fontSize: 13, color: primary),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 18, color: subColor),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _prizeController,
          maxLength: 128,
          style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            hintText: 'Additional Prize (optional)',
            hintStyle: TextStyle(fontSize: 13, color: subColor),
            counterText: '',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: widget.theme.dividerColor),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(Color primary) {
    if (_type == _GiveawayType.prepaid) {
      return SizedBox(
        width: double.infinity,
        height: 44,
        child: ElevatedButton(
          onPressed: _launching ? null : _launchPrepaid,
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: _launching
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Start Giveaway', style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton(
        onPressed: _launching ? null : _launchRandomGiveaway,
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: _launching
            ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('Start Giveaway', style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white,
              )),
      ),
    );
  }

  String _formatAmount(int amount, String currency) {
    final dollars = amount / 100.0;
    if (currency == 'USD') return '\$${dollars.toStringAsFixed(2)}';
    if (currency == 'EUR') return '€${dollars.toStringAsFixed(2)}';
    return '${dollars.toStringAsFixed(2)} $currency';
  }
}

class _TypeRadioTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final ThemeData theme;
  final VoidCallback onTap;

  const _TypeRadioTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    final subColor = isDark ? const Color(0xFF6D7F8F) : const Color(0xFF999999);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? primary.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: selected ? Border.all(color: primary, width: 1.5) : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: selected ? primary : subColor),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : Colors.black87,
                )),
                Text(subtitle, style: TextStyle(fontSize: 12, color: subColor)),
              ],
            )),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20, color: selected ? primary : subColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingSwitch extends StatelessWidget {
  final String label;
  final bool value;
  final Color subColor;
  final bool isDark;
  final ValueChanged<bool> onChanged;

  const _SettingSwitch({
    required this.label,
    required this.value,
    required this.subColor,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(
            fontSize: 13, color: isDark ? Colors.white : Colors.black87,
          ))),
          SizedBox(
            height: 24,
            child: Switch(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

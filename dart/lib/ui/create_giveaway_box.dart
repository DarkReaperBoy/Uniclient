import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';
import '../theme/telegram_palette.dart';
import 'confirm_box.dart';
import 'choose_datetime_box.dart';
import 'telegram_toast.dart';

enum _GiveawayType { random, credits, prepaid }

enum _MemberFilter { all, onlyNew }

DateTime _threeDaysAfterToday() {
  var dt = DateTime.now().add(const Duration(days: 3));
  var minute = dt.minute;
  while (minute % 5 != 0) {
    minute++;
  }
  dt = DateTime(dt.year, dt.month, dt.day, dt.hour, minute);
  return dt;
}

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
  List<int> _uniqueUsers = [];
  int _selectedOptionIndex = 0;
  int _selectedPrepaidIndex = 0;

  _MemberFilter _memberFilter = _MemberFilter.all;
  bool _showWinners = false;
  DateTime _untilDate = _threeDaysAfterToday();
  final _prizeController = TextEditingController();
  bool _showAdditionalPrize = false;

  final List<String> _selectedCountries = [];
  final List<String> _additionalChannelIds = [];
  final List<String> _additionalChannelNames = [];

  final int _boostsPerPremium = 4;
  final int _giveawayPeriodMax = 365 * 86400;

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

      if (!mounted) return;
      setState(() {
        _options = opts;
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

  Map<String, dynamic> get _currentOption {
    if (_options.isEmpty) return {};
    return _selectedOptionIndex < _options.length
        ? _options[_selectedOptionIndex]
        : _options.first;
  }

  int get _currentWinners => (_currentOption['users'] as int?) ?? 0;

  int get _currentBoosts => _boostsPerPremium * _currentWinners;

  Future<void> _launchPrepaid() async {
    if (_launching) return;

    showConfirmBox(
      context,
      text: 'Are you sure you want to start this giveaway?',
      confirmText: 'Start',
      onConfirm: () => _doLaunchPrepaid(),
    );
  }

  Future<void> _doLaunchPrepaid() async {
    if (!mounted) return;
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
          'only_new_subscribers': _memberFilter == _MemberFilter.onlyNew,
          'winners_are_visible': _showWinners,
          'until_date': _untilDate.millisecondsSinceEpoch ~/ 1000,
          'random_id': Random().nextInt(1 << 31),
          if (_showAdditionalPrize && _prizeController.text.isNotEmpty)
            'prize_description': _prizeController.text,
          if (_selectedCountries.isNotEmpty)
            'countries': _selectedCountries,
          if (_additionalChannelIds.isNotEmpty)
            'additional_peers': _additionalChannelIds,
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

    final selectedOpt = _currentOption;
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
          'only_new_subscribers': _memberFilter == _MemberFilter.onlyNew,
          'winners_are_visible': _showWinners,
          'until_date': _untilDate.millisecondsSinceEpoch ~/ 1000,
          'random_id': Random().nextInt(1 << 31),
          if (_showAdditionalPrize && _prizeController.text.isNotEmpty)
            'prize_description': _prizeController.text,
          if (_selectedCountries.isNotEmpty)
            'countries': _selectedCountries,
          if (_additionalChannelIds.isNotEmpty)
            'additional_peers': _additionalChannelIds,
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

  void _addChannel() async {
    final chatState = context.read<ChatState>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    if (accountId.isEmpty) return;

    final chats = chatState.chatsForAccount(accountId);
    final channels = chats.where((c) =>
      (c.type == ChatType.channel || c.type == ChatType.group) &&
      !_additionalChannelIds.contains(c.chatId) &&
      c.chatId != widget.chatId
    ).toList();

    if (channels.isEmpty) {
      showTelegramToast(context, 'No more channels available to add');
      return;
    }

    final p = context.palette;
    final selected = await showTelegramBox<String>(
      context: context,
      builder: (ctx) => _ChannelPickerBox(
        channels: channels,
        palette: p,
      ),
    );
    if (selected != null && mounted) {
      final chat = channels.firstWhere((c) => c.chatId == selected, orElse: () => channels.first);
      setState(() {
        _additionalChannelIds.add(selected);
        _additionalChannelNames.add(chat.title);
      });
    }
  }

  void _removeChannel(int index) {
    setState(() {
      _additionalChannelIds.removeAt(index);
      _additionalChannelNames.removeAt(index);
    });
  }

  void _openCountryPicker() async {
    final p = context.palette;
    final result = await showTelegramBox<List<String>>(
      context: context,
      builder: (ctx) => _CountryPickerBox(
        selectedCodes: List.from(_selectedCountries),
        palette: p,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _selectedCountries
          ..clear()
          ..addAll(result);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isDark = widget.theme.brightness == Brightness.dark;
    final primary = widget.theme.colorScheme.primary;
    final subColor = p.windowSubTextFg;
    final bgColor = p.boxBg;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 380,
        constraints: const BoxConstraints(maxHeight: 600),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(kBoxRadius),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(p, primary),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _error != null
                      ? _buildError(subColor)
                      : _buildContent(p, isDark, primary, subColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(TelegramPalette p, Color primary) {
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

  Widget _buildContent(TelegramPalette p, bool isDark, Color primary, Color subColor) {
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
          ..._buildRandomSection(p, isDark, primary, subColor),
        const SizedBox(height: 12),
        ..._buildChannelsSection(p, isDark, primary, subColor),
        const SizedBox(height: 12),
        ..._buildMemberFilterSection(p, isDark, primary, subColor),
        const SizedBox(height: 12),
        _buildSettingsSection(p, isDark, primary, subColor),
        const SizedBox(height: 16),
        _buildActionButton(p, primary),
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
          title: 'Premium Subscriptions',
          subtitle: 'Create new premium giveaway',
          icon: Icons.people_outline,
          selected: _type == _GiveawayType.random,
          theme: widget.theme,
          onTap: () => setState(() => _type = _GiveawayType.random),
        ),
        const SizedBox(height: 4),
        _TypeRadioTile(
          title: 'Telegram Stars',
          subtitle: 'Give stars to random subscribers',
          icon: Icons.star_outline,
          selected: _type == _GiveawayType.credits,
          theme: widget.theme,
          onTap: () => setState(() => _type = _GiveawayType.credits),
        ),
        if (widget.prepaidGiveaways.isNotEmpty) ...[
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
        final boosts = g['boosts'] as int? ?? (qty * _boostsPerPremium);
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
                        '$boosts boosts for your channel',
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

  List<Widget> _buildRandomSection(TelegramPalette p, bool isDark, Color primary, Color subColor) {
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

    final selectedOpt = _currentOption;
    final currency = selectedOpt['currency'] as String? ?? 'USD';
    final amount = selectedOpt['amount'] as num? ?? 0;
    final isCredits = _type == _GiveawayType.credits;

    return [
      Text(
        isCredits ? 'Telegram Stars' : 'Premium Subscription Gifts',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primary),
      ),
      const SizedBox(height: 4),
      Text(
        isCredits
            ? 'Give Telegram Stars to random subscribers of your channel.'
            : 'Gift Telegram Premium subscriptions to random subscribers.',
        style: TextStyle(fontSize: 12, color: subColor),
      ),
      const SizedBox(height: 12),

      // Winners slider
      if (_uniqueUsers.length > 1) ...[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Winners', style: TextStyle(fontSize: 12, color: subColor)),
            Text(
              '$_currentWinners winners · $_currentBoosts boosts',
              style: TextStyle(fontSize: 11, color: primary, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _WinnerSlider(
          values: _uniqueUsers,
          currentValue: (selectedOpt['users'] as int?) ?? _uniqueUsers.first,
          primary: primary,
          subColor: subColor,
          isDark: isDark,
          boostsPerPremium: _boostsPerPremium,
          onChanged: (users) {
            final idx = _options.indexWhere((o) =>
              o['users'] == users && o['months'] == selectedOpt['months']);
            if (idx >= 0) setState(() => _selectedOptionIndex = idx);
          },
        ),
        const SizedBox(height: 12),
      ],

      // Duration as gift option cards
      if (!isCredits) ...[
        Text(
          'Duration for $_currentWinners winner${_currentWinners == 1 ? '' : 's'}',
          style: TextStyle(fontSize: 12, color: subColor),
        ),
        const SizedBox(height: 8),
        ..._buildDurationCards(isDark, primary, subColor, selectedOpt),
        const SizedBox(height: 12),
      ],

      // Total price
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

  List<Widget> _buildDurationCards(bool isDark, Color primary, Color subColor, Map<String, dynamic> selectedOpt) {
    final currentUsers = (selectedOpt['users'] as int?) ?? 0;
    final matchingOptions = _options.where((o) => o['users'] == currentUsers).toList();
    if (matchingOptions.isEmpty) return [];

    return matchingOptions.map((opt) {
      final months = opt['months'] as int;
      final currency = opt['currency'] as String? ?? 'USD';
      final amount = opt['amount'] as num? ?? 0;
      final isSelected = opt['months'] == selectedOpt['months'];
      final perUser = currentUsers > 0 ? amount.toInt() ~/ currentUsers : amount.toInt();

      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: InkWell(
          onTap: () {
            final idx = _options.indexOf(opt);
            if (idx >= 0) setState(() => _selectedOptionIndex = idx);
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? primary.withValues(alpha: 0.08)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? primary : (isDark ? const Color(0xFF3A4A5A) : const Color(0xFFD0D5DB)),
                width: isSelected ? 2.0 : 1.0,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$months',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: primary),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$months month${months == 1 ? '' : 's'}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      Text(
                        '${_formatAmount(perUser, currency)} per user',
                        style: TextStyle(fontSize: 11, color: subColor),
                      ),
                    ],
                  ),
                ),
                Text(
                  _formatAmount(amount.toInt(), currency),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  List<Widget> _buildChannelsSection(TelegramPalette p, bool isDark, Color primary, Color subColor) {
    if (_type == _GiveawayType.prepaid) return [];

    return [
      Text('Channels', style: TextStyle(
        fontSize: 13, fontWeight: FontWeight.w600, color: primary,
      )),
      const SizedBox(height: 4),
      Text(
        'Choose channels that users must subscribe to in order to participate.',
        style: TextStyle(fontSize: 12, color: subColor),
      ),
      const SizedBox(height: 8),
      ..._additionalChannelNames.asMap().entries.map((entry) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2B3945) : const Color(0xFFF0F2F5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.group, size: 18, color: subColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.value,
                    style: TextStyle(fontSize: 13, color: isDark ? Colors.white : Colors.black87),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                InkWell(
                  onTap: () => _removeChannel(entry.key),
                  borderRadius: BorderRadius.circular(12),
                  child: Icon(Icons.close, size: 16, color: subColor),
                ),
              ],
            ),
          ),
        );
      }),
      InkWell(
        onTap: _addChannel,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add, size: 14, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Text(
                'Add Channel',
                style: TextStyle(fontSize: 13, color: primary, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildMemberFilterSection(TelegramPalette p, bool isDark, Color primary, Color subColor) {
    return [
      Text('Users who can participate', style: TextStyle(
        fontSize: 13, fontWeight: FontWeight.w600, color: primary,
      )),
      const SizedBox(height: 8),
      _MemberFilterRow(
        label: 'All subscribers',
        subtitle: _selectedCountries.isEmpty
            ? 'From all countries'
            : '${_selectedCountries.length} countr${_selectedCountries.length == 1 ? 'y' : 'ies'} selected',
        selected: _memberFilter == _MemberFilter.all,
        primary: primary,
        subColor: subColor,
        isDark: isDark,
        onTap: () => setState(() => _memberFilter = _MemberFilter.all),
      ),
      const SizedBox(height: 4),
      _MemberFilterRow(
        label: 'Only new subscribers',
        subtitle: 'Subscribers who joined after the giveaway started',
        selected: _memberFilter == _MemberFilter.onlyNew,
        primary: primary,
        subColor: subColor,
        isDark: isDark,
        onTap: () => setState(() => _memberFilter = _MemberFilter.onlyNew),
      ),
      const SizedBox(height: 8),
      InkWell(
        onTap: _openCountryPicker,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.public, size: 18, color: primary),
              const SizedBox(width: 10),
              Expanded(child: Text(
                _selectedCountries.isEmpty
                    ? 'From all countries'
                    : '${_selectedCountries.length} countr${_selectedCountries.length == 1 ? 'y' : 'ies'} selected',
                style: TextStyle(fontSize: 13, color: primary, fontWeight: FontWeight.w500),
              )),
              if (_selectedCountries.isNotEmpty)
                InkWell(
                  onTap: () => setState(() => _selectedCountries.clear()),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.clear, size: 14, color: subColor),
                  ),
                ),
              Icon(Icons.chevron_right, size: 18, color: subColor),
            ],
          ),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        'Choose who among the subscribers of the selected channels will be able to participate in the giveaway.',
        style: TextStyle(fontSize: 11, color: subColor),
      ),
    ];
  }

  Widget _buildSettingsSection(TelegramPalette p, bool isDark, Color primary, Color subColor) {
    final fgColor = isDark ? Colors.white : Colors.black87;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: widget.theme.dividerColor),
        const SizedBox(height: 4),

        // Show Winners toggle
        _SettingsToggleRow(
          label: 'Show Winners',
          value: _showWinners,
          fgColor: fgColor,
          primary: primary,
          onTap: () => setState(() => _showWinners = !_showWinners),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 0, bottom: 8),
          child: Text(
            'The list of winners will be publicly visible after the giveaway ends.',
            style: TextStyle(fontSize: 11, color: subColor),
          ),
        ),

        // Additional Prize toggle
        _SettingsToggleRow(
          label: 'Additional Prize',
          value: _showAdditionalPrize,
          fgColor: fgColor,
          primary: primary,
          onTap: () => setState(() {
            _showAdditionalPrize = !_showAdditionalPrize;
            if (!_showAdditionalPrize) _prizeController.clear();
          }),
        ),
        if (_showAdditionalPrize) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _prizeController,
            maxLength: 128,
            style: TextStyle(fontSize: 13, color: fgColor),
            decoration: InputDecoration(
              hintText: 'Enter additional prize description',
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

        const SizedBox(height: 8),
        // End Date
        InkWell(
          onTap: () async {
            final minDate = DateTime.now().add(const Duration(days: 3));
            final maxDate = DateTime.now().add(Duration(seconds: _giveawayPeriodMax));
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
                  fontSize: 13, color: fgColor,
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
      ],
    );
  }

  Widget _buildActionButton(TelegramPalette p, Color primary) {
    final boostCount = _type == _GiveawayType.prepaid
        ? (widget.prepaidGiveaways.isNotEmpty
            ? (widget.prepaidGiveaways[_selectedPrepaidIndex]['boosts'] as int? ??
                ((widget.prepaidGiveaways[_selectedPrepaidIndex]['quantity'] as int? ?? 0) * _boostsPerPremium))
            : 0)
        : _currentBoosts;

    final onTap = _type == _GiveawayType.prepaid ? _launchPrepaid : _launchRandomGiveaway;

    return SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton(
        onPressed: _launching ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: _launching
            ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Start Giveaway', style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white,
                  )),
                  if (boostCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.bolt, size: 12, color: Colors.white),
                          const SizedBox(width: 2),
                          Text(
                            '$boostCount',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
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

// ─── Winner Slider ───────────────────────────────────────────────────────────

class _WinnerSlider extends StatelessWidget {
  final List<int> values;
  final int currentValue;
  final Color primary;
  final Color subColor;
  final bool isDark;
  final int boostsPerPremium;
  final ValueChanged<int> onChanged;

  const _WinnerSlider({
    required this.values,
    required this.currentValue,
    required this.primary,
    required this.subColor,
    required this.isDark,
    required this.boostsPerPremium,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (values.length <= 1) return const SizedBox.shrink();

    final currentIdx = values.indexOf(currentValue).clamp(0, values.length - 1);

    return Column(
      children: [
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: primary,
            inactiveTrackColor: isDark ? const Color(0xFF3A4A5A) : const Color(0xFFD0D5DB),
            thumbColor: primary,
            overlayColor: primary.withValues(alpha: 0.1),
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          ),
          child: Slider(
            value: currentIdx.toDouble(),
            min: 0,
            max: (values.length - 1).toDouble(),
            divisions: values.length > 1 ? values.length - 1 : null,
            label: '${values[currentIdx]}',
            onChanged: (v) {
              final idx = v.round().clamp(0, values.length - 1);
              onChanged(values[idx]);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${values.first}', style: TextStyle(fontSize: 10, color: subColor)),
              Text('${values.last}', style: TextStyle(fontSize: 10, color: subColor)),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Type Radio Tile ─────────────────────────────────────────────────────────

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

// ─── Settings Toggle Row (replaces Material Switch) ─────────────────────────

class _SettingsToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final Color fgColor;
  final Color primary;
  final VoidCallback onTap;

  const _SettingsToggleRow({
    required this.label,
    required this.value,
    required this.fgColor,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(
              fontSize: 13, color: fgColor,
            ))),
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 34,
              height: 20,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: value ? primary : fgColor.withValues(alpha: 0.25),
              ),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              padding: const EdgeInsets.all(2),
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Member Filter Row ──────────────────────────────────────────────────────

class _MemberFilterRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool selected;
  final Color primary;
  final Color subColor;
  final bool isDark;
  final VoidCallback onTap;

  const _MemberFilterRow({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.primary,
    required this.subColor,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20,
              color: selected ? primary : subColor,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black87,
                  )),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: subColor)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Channel Picker Box ─────────────────────────────────────────────────────

class _ChannelPickerBox extends StatelessWidget {
  final List<ChatInfo> channels;
  final TelegramPalette palette;

  const _ChannelPickerBox({
    required this.channels,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final textFg = palette.boxTextFg;

    return TelegramBox(
      title: 'Add Channel',
      content: SizedBox(
        height: min(channels.length * 48.0, 300),
        child: ListView.builder(
          itemCount: channels.length,
          itemBuilder: (ctx, i) {
            final ch = channels[i];
            return InkWell(
              onTap: () => Navigator.of(ctx).pop(ch.chatId),
              hoverColor: palette.windowBgOver,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
                child: Row(
                  children: [
                    Icon(
                      ch.type == ChatType.channel ? Icons.campaign : Icons.group,
                      size: 20,
                      color: textFg,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        ch.title,
                        style: TextStyle(fontSize: 14, color: textFg),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      buttons: const [],
    );
  }
}

// ─── Country Picker Box ────────────────────────────────────────────────────

class _CountryPickerBox extends StatefulWidget {
  final List<String> selectedCodes;
  final TelegramPalette palette;

  const _CountryPickerBox({
    required this.selectedCodes,
    required this.palette,
  });

  @override
  State<_CountryPickerBox> createState() => _CountryPickerBoxState();
}

class _CountryPickerBoxState extends State<_CountryPickerBox> {
  late final Set<String> _selected;
  String _query = '';
  final _searchController = TextEditingController();

  static const _countries = <String, String>{
    'AF': 'Afghanistan', 'AL': 'Albania', 'DZ': 'Algeria', 'AR': 'Argentina',
    'AM': 'Armenia', 'AU': 'Australia', 'AT': 'Austria', 'AZ': 'Azerbaijan',
    'BD': 'Bangladesh', 'BY': 'Belarus', 'BE': 'Belgium', 'BR': 'Brazil',
    'BG': 'Bulgaria', 'CA': 'Canada', 'CL': 'Chile', 'CN': 'China',
    'CO': 'Colombia', 'HR': 'Croatia', 'CZ': 'Czech Republic', 'DK': 'Denmark',
    'EG': 'Egypt', 'EE': 'Estonia', 'FI': 'Finland', 'FR': 'France',
    'GE': 'Georgia', 'DE': 'Germany', 'GR': 'Greece', 'HU': 'Hungary',
    'IN': 'India', 'ID': 'Indonesia', 'IR': 'Iran', 'IQ': 'Iraq',
    'IE': 'Ireland', 'IL': 'Israel', 'IT': 'Italy', 'JP': 'Japan',
    'KZ': 'Kazakhstan', 'KR': 'South Korea', 'KW': 'Kuwait', 'LV': 'Latvia',
    'LT': 'Lithuania', 'MY': 'Malaysia', 'MX': 'Mexico', 'MD': 'Moldova',
    'NL': 'Netherlands', 'NZ': 'New Zealand', 'NG': 'Nigeria', 'NO': 'Norway',
    'PK': 'Pakistan', 'PE': 'Peru', 'PH': 'Philippines', 'PL': 'Poland',
    'PT': 'Portugal', 'QA': 'Qatar', 'RO': 'Romania', 'RU': 'Russia',
    'SA': 'Saudi Arabia', 'RS': 'Serbia', 'SG': 'Singapore', 'SK': 'Slovakia',
    'ZA': 'South Africa', 'ES': 'Spain', 'SE': 'Sweden', 'CH': 'Switzerland',
    'TW': 'Taiwan', 'TH': 'Thailand', 'TR': 'Turkey', 'UA': 'Ukraine',
    'AE': 'United Arab Emirates', 'GB': 'United Kingdom', 'US': 'United States',
    'UZ': 'Uzbekistan', 'VN': 'Vietnam',
  };

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.selectedCodes);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static String _countryFlag(String code) {
    return String.fromCharCodes(
      code.toUpperCase().codeUnits.map((c) => c - 0x41 + 0x1F1E6),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final textFg = p.boxTextFg;
    final subColor = p.windowSubTextFg;

    final filtered = _countries.entries.where((e) =>
      _query.isEmpty ||
      e.value.toLowerCase().contains(_query.toLowerCase()) ||
      e.key.toLowerCase().contains(_query.toLowerCase())
    ).toList();

    return TelegramBox(
      title: 'Select Countries',
      showClose: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              style: TextStyle(fontSize: 14, color: textFg),
              decoration: InputDecoration(
                hintText: 'Filter participants',
                hintStyle: TextStyle(fontSize: 14, color: subColor),
                prefixIcon: Icon(Icons.search, size: 20, color: subColor),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: p.windowBgRipple),
                ),
              ),
            ),
          ),
          if (_selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: _selected.map((code) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: p.windowBgActive,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_countryFlag(code)} ${_countries[code] ?? code}',
                          style: const TextStyle(fontSize: 12, color: Colors.white),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => setState(() => _selected.remove(code)),
                          child: const Icon(Icons.close, size: 14, color: Colors.white),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          SizedBox(
            height: min(filtered.length * 44.0, 300),
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (ctx, i) {
                final entry = filtered[i];
                final isSelected = _selected.contains(entry.key);
                return InkWell(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selected.remove(entry.key);
                      } else {
                        _selected.add(entry.key);
                      }
                    });
                  },
                  hoverColor: p.windowBgOver,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                    child: Row(
                      children: [
                        Icon(
                          isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                          size: 20,
                          color: isSelected ? p.windowBgActive : subColor,
                        ),
                        const SizedBox(width: 12),
                        Text(_countryFlag(entry.key),
                            style: const TextStyle(fontSize: 20)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            entry.value,
                            style: TextStyle(fontSize: 14, color: textFg),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      buttons: [
        TelegramBoxButton(
          text: 'Save',
          onPressed: () => Navigator.of(context).pop(_selected.toList()),
        ),
        TelegramBoxButton(
          text: 'Cancel',
          onPressed: () => Navigator.of(context).pop(null),
        ),
      ],
      onConfirm: () => Navigator.of(context).pop(_selected.toList()),
    );
  }
}

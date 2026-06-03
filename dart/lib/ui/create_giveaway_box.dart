import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';
import '../theme/telegram_palette.dart';
import '../utils/country_data.dart';
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

  List<Map<String, dynamic>> _creditsOptions = [];
  int _selectedCreditsOptionIndex = 0;
  int _selectedCreditsWinnerIndex = 0;
  // Whether extended (hidden) star tiers have been revealed via "Show more".
  bool _creditsExtended = false;

  _MemberFilter _memberFilter = _MemberFilter.all;
  bool _showWinners = false;
  DateTime _untilDate = _threeDaysAfterToday();
  final _prizeController = TextEditingController();
  bool _showAdditionalPrize = false;

  final List<String> _selectedCountries = [];
  final List<String> _additionalChannelIds = [];
  final List<String> _additionalChannelNames = [];

  // "Award Specific Users" mode: explicitly chosen recipients to gift Premium.
  // Non-empty ⇒ isSpecificUsers() ⇒ the Award flow replaces the random giveaway.
  final List<String> _awardUserIds = [];
  final List<String> _awardUserNames = [];
  int _awardMonths = 0;

  int _boostsPerPremium = 4;
  int _countriesMax = 10;
  int _addPeersMax = 10;
  int _giveawayPeriodMax = 604800;

  bool get _isSpecificUsers => _awardUserIds.isNotEmpty;

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
      final results = await Future.wait([
        engine.getGiftCodeOptions(widget.accountId, widget.chatId),
        engine.getStarsGiveawayOptions(widget.accountId),
        engine.getGiveawayConfig(widget.accountId),
      ]);
      if (!mounted) return;

      final opts = results[0] as List<Map<String, dynamic>>;
      final creditsOpts = results[1] as List<Map<String, dynamic>>;
      final config = results[2] as Map<String, int>;

      int defaultCreditsIdx = 0;
      for (int i = 0; i < creditsOpts.length; i++) {
        if (creditsOpts[i]['is_default'] == true) {
          defaultCreditsIdx = i;
          break;
        }
      }

      setState(() {
        _options = opts;
        _uniqueUsers = opts.map((o) => o['users'] as int).toSet().toList()..sort();
        _creditsOptions = creditsOpts;
        _selectedCreditsOptionIndex = defaultCreditsIdx;
        _boostsPerPremium = config['boosts_per_premium'] ?? 4;
        _countriesMax = config['countries_max'] ?? 10;
        _addPeersMax = config['add_peers_max'] ?? 10;
        _giveawayPeriodMax = config['period_max'] ?? 604800;
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

  Future<void> _launchCreditsGiveaway() async {
    if (_launching || _creditsOptions.isEmpty) return;
    setState(() => _launching = true);

    final selectedOpt = _creditsOptions[_selectedCreditsOptionIndex];
    final winners = (selectedOpt['winners'] as List?) ?? [];
    final winnerOpt = _selectedCreditsWinnerIndex < winners.length
        ? winners[_selectedCreditsWinnerIndex] as Map<String, dynamic>
        : (winners.isNotEmpty ? winners[0] as Map<String, dynamic> : <String, dynamic>{});
    final engine = Provider.of<AppState>(context, listen: false).engine;

    try {
      final result = await engine.launchCreditsGiveaway(
        widget.accountId,
        widget.chatId,
        {
          'stars': selectedOpt['stars'] ?? 0,
          'users': winnerOpt['users'] ?? 1,
          'currency': selectedOpt['currency'] ?? 'USD',
          'amount': selectedOpt['amount'] ?? 0,
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
    // Enforce the app-config maximum (AyuGram giveawayAddPeersMax, fallback 10).
    if (_additionalChannelIds.length >= _addPeersMax) {
      showTelegramToast(context, 'You can select up to $_addPeersMax groups and channels.');
      return;
    }

    final chatState = context.read<ChatState>();
    final accountId = widget.accountId;

    // Source collects only broadcast channels (!channel->isMegagroup()); the
    // local cache's ChatType.channel is exactly the broadcast set. Megagroups
    // (ChatType.group) are excluded.
    final chats = chatState.chatsForAccount(accountId);
    final channels = chats.where((c) =>
      c.type == ChatType.channel &&
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
    if (selected == null || !mounted) return;

    final chat = channels.firstWhere((c) => c.chatId == selected, orElse: () => channels.first);

    void add() {
      if (!mounted) return;
      setState(() {
        _additionalChannelIds.add(selected);
        _additionalChannelNames.add(chat.title);
      });
    }

    // A channel without a public username is private — confirm before adding,
    // since users can't join it without an invite link (lng_giveaway_channels_confirm).
    if (chat.username.isEmpty) {
      showConfirmBox(
        context,
        title: 'Channel is Private',
        text: "Are you sure you want to add a private channel? "
            "Users won't be able to join it without an invite link.",
        confirmText: 'Add',
        onConfirm: add,
      );
    } else {
      add();
    }
  }

  /// Opens the member peer-picker for the "Award Specific Users" mode. Mirrors
  /// AyuGram's AwardMembersListController flow: selecting members enters the
  /// Award flow; "Choose randomly" clears the selection back to a random
  /// giveaway. Cancelling leaves the current state untouched.
  void _openAwardPicker() async {
    if (_type != _GiveawayType.random) {
      setState(() => _type = _GiveawayType.random);
    }
    final p = context.palette;
    final result = await showTelegramBox<List<MemberInfo>>(
      context: context,
      builder: (ctx) => _AwardMembersBox(
        accountId: widget.accountId,
        chatId: widget.chatId,
        palette: p,
        maxUsers: _addPeersMax,
        initialSelectedIds: List.from(_awardUserIds),
      ),
    );
    if (result == null || !mounted) return; // cancelled

    setState(() {
      _awardUserIds
        ..clear()
        ..addAll(result.map((m) => m.userId));
      _awardUserNames
        ..clear()
        ..addAll(result.map((m) => m.label));
      if (_awardUserIds.isNotEmpty) {
        final durOpts = _perUserDurationOptions();
        if (!durOpts.any((o) => o['months'] == _awardMonths)) {
          _awardMonths = durOpts.isNotEmpty ? durOpts.first['months'] as int : 0;
        }
      }
    });
  }

  /// Per-user duration options derived from the gift-code options, keyed by
  /// month length. Price per user is amount/users (linear in users — AyuGram
  /// scales the one-person cost by usersCount in optionsForGiveaway). Used by
  /// the Award flow where the winner count is the number of chosen recipients.
  List<Map<String, dynamic>> _perUserDurationOptions() {
    final byMonths = <int, Map<String, dynamic>>{};
    for (final o in _options) {
      final months = (o['months'] as int?) ?? 0;
      final users = (o['users'] as int?) ?? 1;
      if (users <= 0 || months <= 0) continue;
      final amount = (o['amount'] as num?)?.toInt() ?? 0;
      final perUser = amount ~/ users;
      // Prefer the users==1 option for exact per-user pricing.
      if (!byMonths.containsKey(months) || users == 1) {
        byMonths[months] = {
          'months': months,
          'currency': (o['currency'] as String?) ?? 'USD',
          'per_user_amount': perUser,
        };
      }
    }
    final list = byMonths.values.toList()
      ..sort((a, b) => (a['months'] as int).compareTo(b['months'] as int));
    return list;
  }

  Future<void> _launchAward() async {
    if (_launching || _awardUserIds.isEmpty) return;
    final durOpts = _perUserDurationOptions();
    if (durOpts.isEmpty) return;
    final selected = durOpts.firstWhere(
      (o) => o['months'] == _awardMonths,
      orElse: () => durOpts.first,
    );
    final n = _awardUserIds.length;
    final perUser = selected['per_user_amount'] as int;

    setState(() => _launching = true);
    final engine = Provider.of<AppState>(context, listen: false).engine;

    try {
      final result = await engine.awardPremiumGiveaway(
        widget.accountId,
        widget.chatId,
        {
          'user_ids': _awardUserIds,
          'months': selected['months'],
          'currency': selected['currency'] ?? 'USD',
          'amount': perUser * n,
          'random_id': Random().nextInt(1 << 31),
        },
      );
      if (!mounted) return;
      final url = result['url'] as String?;
      Navigator.of(context).pop();
      if (url != null && url.isNotEmpty) {
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        showTelegramToast(context, 'Premium gifted!');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _launching = false;
        _error = e.toString();
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
        maxCountries: _countriesMax,
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
    // Award Specific Users mode: the random-giveaway sections (winners slider,
    // channels, countries, schedule, prizes) collapse — only the type selector,
    // the gift-duration options and the Award button remain, matching the
    // source's isSpecificUsers() layout.
    if (_isSpecificUsers && _type == _GiveawayType.random) {
      return Builder(builder: (_) {
        final _lvKids = <Widget>[
          _buildTypeSelector(isDark, primary, subColor),
          const SizedBox(height: 16),
          ..._buildAwardSection(p, isDark, primary, subColor),
          const SizedBox(height: 16),
          _buildActionButton(p, primary),
          const SizedBox(height: 8),
        ];
        return ListView.builder(
          shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          itemCount: _lvKids.length,
          itemBuilder: (_, _lvI) => _lvKids[_lvI],
        );
      });
    }

    return Builder(builder: (_) {
      final _lvKids = <Widget>[
        _buildTypeSelector(isDark, primary, subColor),
        const SizedBox(height: 16),
        if (_type == _GiveawayType.prepaid)
          ..._buildPrepaidSection(isDark, primary, subColor)
        else if (_type == _GiveawayType.credits)
          ..._buildCreditsSection(p, isDark, primary, subColor)
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
      ];
      return ListView.builder(
        shrinkWrap: true,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        itemCount: _lvKids.length,
        itemBuilder: (_, _lvI) => _lvKids[_lvI],
      );
    });
  }

  /// The Award flow body: gift-duration cards priced per chosen recipient.
  List<Widget> _buildAwardSection(TelegramPalette p, bool isDark, Color primary, Color subColor) {
    final n = _awardUserIds.length;
    final durOpts = _perUserDurationOptions();
    if (durOpts.isEmpty) {
      return [
        Text(
          'No premium gift options available for this channel.',
          style: TextStyle(fontSize: 13, color: subColor),
        ),
      ];
    }
    final selectedMonths = durOpts.any((o) => o['months'] == _awardMonths)
        ? _awardMonths
        : durOpts.first['months'] as int;
    final selected = durOpts.firstWhere(
      (o) => o['months'] == selectedMonths,
      orElse: () => durOpts.first,
    );
    final currency = selected['currency'] as String? ?? 'USD';
    final total = (selected['per_user_amount'] as int) * n;

    return [
      Text(
        'Premium Subscription Gifts',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primary),
      ),
      const SizedBox(height: 4),
      Text(
        'Gift Telegram Premium subscriptions to the chosen recipients.',
        style: TextStyle(fontSize: 12, color: subColor),
      ),
      const SizedBox(height: 12),
      Text(
        'Duration for $n recipient${n == 1 ? '' : 's'}',
        style: TextStyle(fontSize: 12, color: subColor),
      ),
      const SizedBox(height: 8),
      ...durOpts.map((o) {
        final months = o['months'] as int;
        final perUser = o['per_user_amount'] as int;
        final cur = o['currency'] as String? ?? 'USD';
        final isSelected = months == selectedMonths;
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: InkWell(
            onTap: () => setState(() => _awardMonths = months),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? primary.withValues(alpha: 0.08) : Colors.transparent,
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
                            fontSize: 14, fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        Text(
                          '${_formatAmount(perUser, cur)} per user',
                          style: TextStyle(fontSize: 11, color: subColor),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _formatAmount(perUser * n, cur),
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primary),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
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
              _formatAmount(total, currency),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primary),
            ),
          ],
        ),
      ),
    ];
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
          subtitle: _isSpecificUsers
              ? (_awardUserIds.length == 1
                  ? _awardUserNames.first
                  : '${_awardUserIds.length} recipients')
              : 'winners are chosen randomly',
          icon: Icons.people_outline,
          selected: _type == _GiveawayType.random,
          theme: widget.theme,
          onTap: _openAwardPicker,
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

    return [
      Text(
        'Premium Subscription Gifts',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primary),
      ),
      const SizedBox(height: 4),
      Text(
        'Gift Telegram Premium subscriptions to random subscribers.',
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
      Text(
        'Duration for $_currentWinners winner${_currentWinners == 1 ? '' : 's'}',
        style: TextStyle(fontSize: 12, color: subColor),
      ),
      const SizedBox(height: 8),
      ..._buildDurationCards(isDark, primary, subColor, selectedOpt),
      const SizedBox(height: 12),

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

  List<Widget> _buildCreditsSection(TelegramPalette p, bool isDark, Color primary, Color subColor) {
    if (_creditsOptions.isEmpty) {
      return [
        Text(
          'No star giveaway options available.',
          style: TextStyle(fontSize: 13, color: subColor),
        ),
      ];
    }

    final selectedOpt = _creditsOptions[_selectedCreditsOptionIndex];
    final winners = (selectedOpt['winners'] as List?) ?? [];
    final winnerOpt = _selectedCreditsWinnerIndex < winners.length
        ? winners[_selectedCreditsWinnerIndex] as Map<String, dynamic>
        : (winners.isNotEmpty ? winners[0] as Map<String, dynamic> : <String, dynamic>{});
    final currentUsers = (winnerOpt['users'] as num?)?.toInt() ?? 0;
    final perUserStars = (winnerOpt['per_user_stars'] as num?)?.toInt() ?? 0;
    final yearlyBoosts = (selectedOpt['yearly_boosts'] as num?)?.toInt() ?? 0;

    final uniqueWinnerUsers = winners
        .map((w) => (w as Map<String, dynamic>)['users'] as int)
        .toSet()
        .toList()
      ..sort();

    return [
      Text(
        'Telegram Stars',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primary),
      ),
      const SizedBox(height: 4),
      Text(
        'Give Telegram Stars to random subscribers of your channel.',
        style: TextStyle(fontSize: 12, color: subColor),
      ),
      const SizedBox(height: 12),

      if (uniqueWinnerUsers.length > 1) ...[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Winners', style: TextStyle(fontSize: 12, color: subColor)),
            Text(
              '$currentUsers winners · $perUserStars stars each',
              style: TextStyle(fontSize: 11, color: primary, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _WinnerSlider(
          values: uniqueWinnerUsers,
          currentValue: currentUsers,
          primary: primary,
          subColor: subColor,
          isDark: isDark,
          boostsPerPremium: _boostsPerPremium,
          onChanged: (users) {
            final idx = winners.indexWhere((w) => (w as Map<String, dynamic>)['users'] == users);
            if (idx >= 0) setState(() => _selectedCreditsWinnerIndex = idx);
          },
        ),
        const SizedBox(height: 12),
      ],

      Text(
        'Star Options',
        style: TextStyle(fontSize: 12, color: subColor),
      ),
      if (yearlyBoosts > 0)
        Text(
          '$yearlyBoosts boosts',
          style: TextStyle(fontSize: 11, color: primary, fontWeight: FontWeight.w500),
        ),
      const SizedBox(height: 8),
      ..._buildCreditsOptionCards(isDark, primary, subColor),
      if (!_creditsExtended && _hasHiddenExtendedCredits()) _buildShowMoreButton(primary),
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
              _formatAmount((selectedOpt['amount'] as num?)?.toInt() ?? 0, (selectedOpt['currency'] as String?) ?? 'USD'),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: primary),
            ),
          ],
        ),
      ),
    ];
  }

  /// True when there are extended star tiers not yet visible (hidden behind
  /// "Show more"). Mirrors the source which gates `option.isExtended` rows.
  bool _hasHiddenExtendedCredits() {
    return _creditsOptions.asMap().entries.any((e) =>
        e.value['extended'] == true &&
        e.value['is_default'] != true &&
        e.key != _selectedCreditsOptionIndex);
  }

  Widget _buildShowMoreButton(Color primary) {
    return InkWell(
      onTap: () => setState(() => _creditsExtended = true),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.keyboard_arrow_down, size: 18, color: primary),
            const SizedBox(width: 8),
            Text(
              'Show more',
              style: TextStyle(fontSize: 13, color: primary, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCreditsOptionCards(bool isDark, Color primary, Color subColor) {
    return _creditsOptions.asMap().entries.where((entry) {
      final opt = entry.value;
      // Extended tiers stay hidden until "Show more" is tapped (or if this tier
      // is the default / currently-selected one).
      return !(opt['extended'] == true) ||
          opt['is_default'] == true ||
          _creditsExtended ||
          entry.key == _selectedCreditsOptionIndex;
    }).map((entry) {
      final i = entry.key;
      final opt = entry.value;
      final stars = (opt['stars'] as num?)?.toInt() ?? 0;
      final currency = opt['currency'] as String? ?? 'USD';
      final amount = (opt['amount'] as num?)?.toInt() ?? 0;
      final yearlyBoosts = (opt['yearly_boosts'] as num?)?.toInt() ?? 0;
      final isSelected = i == _selectedCreditsOptionIndex;

      final winners = (opt['winners'] as List?) ?? [];
      final winnerOpt = _selectedCreditsWinnerIndex < winners.length
          ? winners[_selectedCreditsWinnerIndex] as Map<String, dynamic>
          : (winners.isNotEmpty ? winners[0] as Map<String, dynamic> : <String, dynamic>{});
      final perUserStars = (winnerOpt['per_user_stars'] as num?)?.toInt() ?? 0;

      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: InkWell(
          onTap: () => setState(() => _selectedCreditsOptionIndex = i),
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
                    color: const Color(0xFFFFA500).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.star, size: 18, color: Color(0xFFFFA500)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$stars Stars',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      Text(
                        '$perUserStars stars per winner',
                        style: TextStyle(fontSize: 11, color: subColor),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatAmount(amount, currency),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: primary,
                      ),
                    ),
                    if (yearlyBoosts > 0)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bolt, size: 10, color: primary),
                            const SizedBox(width: 2),
                            Text(
                              '$yearlyBoosts',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: primary),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
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

    // The boosted channel itself is always listed first (source's
    // SelectedChannelsListController::prepare appends the host as row 0), with a
    // "this channel will receive N boosts" status (setTopStatus).
    final chatState = context.read<ChatState>();
    ChatInfo? host;
    for (final c in chatState.chatsForAccount(widget.accountId)) {
      if (c.chatId == widget.chatId) {
        host = c;
        break;
      }
    }
    final hostTitle = (host != null && host.title.isNotEmpty) ? host.title : 'This channel';
    final isGroup = host?.type == ChatType.group;
    final int hostBoosts;
    if (_type == _GiveawayType.credits && _creditsOptions.isNotEmpty) {
      hostBoosts = (_creditsOptions[_selectedCreditsOptionIndex]['yearly_boosts'] as num?)?.toInt() ?? 0;
    } else {
      hostBoosts = _currentBoosts;
    }
    final hostStatus = isGroup
        ? 'this group will receive $hostBoosts boost${hostBoosts == 1 ? '' : 's'}'
        : 'this channel will receive $hostBoosts boost${hostBoosts == 1 ? '' : 's'}';

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
      // Host channel row (non-removable).
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2B3945) : const Color(0xFFF0F2F5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(isGroup ? Icons.group : Icons.campaign, size: 18, color: primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hostTitle,
                      style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(hostStatus, style: TextStyle(fontSize: 11, color: primary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
    final isSpecific = _isSpecificUsers && _type == _GiveawayType.random;

    final int boostCount;
    if (isSpecific) {
      boostCount = _boostsPerPremium * _awardUserIds.length;
    } else if (_type == _GiveawayType.prepaid) {
      boostCount = widget.prepaidGiveaways.isNotEmpty
          ? (widget.prepaidGiveaways[_selectedPrepaidIndex]['boosts'] as int? ??
              ((widget.prepaidGiveaways[_selectedPrepaidIndex]['quantity'] as int? ?? 0) * _boostsPerPremium))
          : 0;
    } else if (_type == _GiveawayType.credits && _creditsOptions.isNotEmpty) {
      boostCount = (_creditsOptions[_selectedCreditsOptionIndex]['yearly_boosts'] as num?)?.toInt() ?? 0;
    } else {
      boostCount = _currentBoosts;
    }

    final VoidCallback onTap;
    if (isSpecific) {
      onTap = _launchAward;
    } else if (_type == _GiveawayType.prepaid) {
      onTap = _launchPrepaid;
    } else if (_type == _GiveawayType.credits) {
      onTap = _launchCreditsGiveaway;
    } else {
      onTap = _launchRandomGiveaway;
    }

    // "Gift Premium" (lng_giveaway_award) when awarding specific users, else the
    // standard "Start Giveaway" (lng_giveaway_start).
    final buttonLabel = isSpecific ? 'Gift Premium' : 'Start Giveaway';

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
                  Text(buttonLabel, style: const TextStyle(
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

// ─── Award Members Box ──────────────────────────────────────────────────────
//
// Member peer-picker for the "Award Specific Users" giveaway mode (mirrors
// AyuGram's AwardMembersListController). Returns: null when cancelled (no
// change), an empty list for "Choose randomly" (clears the award selection), or
// the chosen members to gift Premium to.

class _AwardMembersBox extends StatefulWidget {
  final String accountId;
  final String chatId;
  final TelegramPalette palette;
  final int maxUsers;
  final List<String> initialSelectedIds;

  const _AwardMembersBox({
    required this.accountId,
    required this.chatId,
    required this.palette,
    required this.maxUsers,
    required this.initialSelectedIds,
  });

  @override
  State<_AwardMembersBox> createState() => _AwardMembersBoxState();
}

class _AwardMembersBoxState extends State<_AwardMembersBox> {
  bool _loading = true;
  String? _error;
  List<MemberInfo> _members = [];
  late final Set<String> _selectedIds;
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedIds = Set.from(widget.initialSelectedIds);
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final engine = Provider.of<AppState>(context, listen: false).engine;
      final members = await engine.getChatMembers(
        widget.accountId,
        widget.chatId,
        limit: 200,
      );
      if (!mounted) return;
      setState(() {
        // Source's createRow drops bots and self.
        _members = members.where((m) => !m.isBot && !m.isSelf).toList();
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

  void _toggle(MemberInfo m) {
    if (_selectedIds.contains(m.userId)) {
      setState(() => _selectedIds.remove(m.userId));
      return;
    }
    // Enforce the app-config maximum (giveawayAddPeersMax, fallback 10).
    if (_selectedIds.length >= widget.maxUsers) {
      showTelegramToast(context, 'You can select up to ${widget.maxUsers} subscribers.');
      return;
    }
    setState(() => _selectedIds.add(m.userId));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final textFg = p.boxTextFg;
    final subColor = p.windowSubTextFg;

    final q = _query.toLowerCase();
    final filtered = _members.where((m) =>
      q.isEmpty ||
      m.label.toLowerCase().contains(q) ||
      m.username.toLowerCase().contains(q)
    ).toList();

    Widget list;
    if (_loading) {
      list = const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_error != null) {
      list = Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
        child: Text(
          'Failed to load members.\n$_error',
          style: TextStyle(fontSize: 12, color: subColor),
          textAlign: TextAlign.center,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
        ),
      );
    } else if (filtered.isEmpty) {
      list = Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No members found.',
          style: TextStyle(fontSize: 13, color: subColor),
        ),
      );
    } else {
      list = SizedBox(
        height: min(filtered.length * 52.0, 320),
        child: ListView.builder(
          itemCount: filtered.length,
          itemBuilder: (ctx, i) {
            final m = filtered[i];
            final sel = _selectedIds.contains(m.userId);
            return InkWell(
              onTap: () => _toggle(m),
              hoverColor: p.windowBgOver,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                child: Row(
                  children: [
                    Icon(
                      sel ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 20,
                      color: sel ? p.windowBgActive : subColor,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.label,
                            style: TextStyle(fontSize: 14, color: textFg),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (m.username.isNotEmpty)
                            Text(
                              '@${m.username}',
                              style: TextStyle(fontSize: 12, color: subColor),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }

    return TelegramBox(
      title: 'Award Specific Users',
      showClose: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // "Choose randomly" — clears the award selection back to a random giveaway.
          InkWell(
            onTap: () => Navigator.of(context).pop(<MemberInfo>[]),
            hoverColor: p.windowBgOver,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
              child: Row(
                children: [
                  Icon(Icons.shuffle, size: 20, color: p.windowActiveTextFg),
                  const SizedBox(width: 12),
                  Text(
                    'Choose randomly',
                    style: TextStyle(
                      fontSize: 14,
                      color: p.windowActiveTextFg,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              style: TextStyle(fontSize: 14, color: textFg),
              decoration: InputDecoration(
                hintText: 'Search members',
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
          list,
        ],
      ),
      buttons: [
        TelegramBoxButton(
          text: 'Save',
          onPressed: () {
            final selected = _members.where((m) => _selectedIds.contains(m.userId)).toList();
            Navigator.of(context).pop(selected);
          },
        ),
        TelegramBoxButton(
          text: 'Cancel',
          onPressed: () => Navigator.of(context).pop(null),
        ),
      ],
    );
  }
}

// ─── Country Picker Box ────────────────────────────────────────────────────

class _CountryPickerBox extends StatefulWidget {
  final List<String> selectedCodes;
  final TelegramPalette palette;
  final int maxCountries;

  const _CountryPickerBox({
    required this.selectedCodes,
    required this.palette,
    required this.maxCountries,
  });

  @override
  State<_CountryPickerBox> createState() => _CountryPickerBoxState();
}

class _CountryPickerBoxState extends State<_CountryPickerBox> {
  late final Set<String> _selected;
  String _query = '';
  final _searchController = TextEditingController();

  // Full ISO country database (mirrors AyuGram's Countries::Instance().list()),
  // sorted by name — replaces the previous hardcoded 73-country subset. Flags
  // come from CountryInfo.flag rather than a duplicated local helper.
  static final List<CountryInfo> _allCountries = [...countries]
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  static final Map<String, CountryInfo> _byIso = {
    for (final c in countries) c.iso: c,
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

  void _toggle(CountryInfo c) {
    if (_selected.contains(c.iso)) {
      setState(() => _selected.remove(c.iso));
      return;
    }
    // Enforce the app-config maximum (giveawayCountriesMax, fallback 10) — the
    // source wraps the add path in CreateErrorCallback(giveawayCountriesMax()).
    if (_selected.length >= widget.maxCountries) {
      showTelegramToast(context, 'You can select up to ${widget.maxCountries} countries.');
      return;
    }
    setState(() => _selected.add(c.iso));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final textFg = p.boxTextFg;
    final subColor = p.windowSubTextFg;

    final q = _query.toLowerCase();
    final filtered = _allCountries.where((c) =>
      q.isEmpty ||
      c.name.toLowerCase().contains(q) ||
      c.iso.toLowerCase().contains(q)
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
                  final info = _byIso[code];
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
                          '${info?.flag ?? ''} ${info?.name ?? code}',
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
                final c = filtered[i];
                final isSelected = _selected.contains(c.iso);
                return InkWell(
                  onTap: () => _toggle(c),
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
                        Text(c.flag, style: const TextStyle(fontSize: 20)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            c.name,
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

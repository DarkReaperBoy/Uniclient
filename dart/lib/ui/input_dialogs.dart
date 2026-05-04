import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../state/app_state.dart';
import '../utils/country_data.dart';
import '../theme/telegram_palette.dart';
import 'confirm_box.dart';
import 'telegram_toast.dart';

// ─── §36.4 Input Dialogs ────────────────────────────────────────────────────

// ─── BoxInputField — styled text field for TelegramBox forms ────────────────

class BoxInputField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final bool obscureText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool enabled;

  const BoxInputField({
    super.key,
    required this.controller,
    this.focusNode,
    required this.label,
    this.obscureText = false,
    this.keyboardType,
    this.inputFormatters,
    this.onSubmitted,
    this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textColor = p.boxTextFg;
    final labelColor = p.boxTitleAdditionalFg;
    final borderColor = p.boxDividerBg;
    final focusBorderColor = p.activeLineFg;

    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      style: TextStyle(fontSize: 15, color: textColor),
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      enabled: enabled,
      textInputAction: onSubmitted != null ? TextInputAction.next : null,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 14, color: labelColor),
        floatingLabelStyle: TextStyle(fontSize: 12, color: focusBorderColor),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        enabledBorder:
            UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
        focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: focusBorderColor, width: 2)),
        disabledBorder:
            UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
      ),
    );
  }
}

// ─── showUsernameBox — §36.4 Username input with live validation ────────────

Future<String?> showUsernameBox(
  BuildContext context, {
  required String accountId,
  String currentUsername = '',
}) {
  final engine = context.read<EngineService>();
  return showTelegramBox<String>(
    context: context,
    builder: (ctx) => _UsernameBoxContent(
      accountId: accountId,
      currentUsername: currentUsername,
      engine: engine,
    ),
  );
}

class _UsernameBoxContent extends StatefulWidget {
  final String accountId;
  final EngineService engine;
  final String currentUsername;

  const _UsernameBoxContent({
    required this.accountId,
    required this.currentUsername,
    required this.engine,
  });

  @override
  State<_UsernameBoxContent> createState() => _UsernameBoxContentState();
}

class _UsernameBoxContentState extends State<_UsernameBoxContent> {
  late final TextEditingController _ctrl;
  late final FocusNode _focusNode;
  Timer? _debounce;
  String? _statusText;
  bool _isValid = false;
  bool _checking = false;
  bool _saving = false;
  static final _usernameRegex = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{4,31}$');

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.currentUsername);
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final username = value.trim();

    if (username.isEmpty) {
      setState(() {
        _statusText = null;
        _isValid = false;
        _checking = false;
      });
      return;
    }

    if (username == widget.currentUsername) {
      setState(() {
        _statusText = null;
        _isValid = false;
        _checking = false;
      });
      return;
    }

    if (username.length < 5) {
      setState(() {
        _statusText = 'Username must be at least 5 characters';
        _isValid = false;
        _checking = false;
      });
      return;
    }

    if (username.length > 32) {
      setState(() {
        _statusText = 'Username is too long';
        _isValid = false;
        _checking = false;
      });
      return;
    }

    if (!_usernameRegex.hasMatch(username)) {
      setState(() {
        _statusText = 'Sorry, this username is invalid';
        _isValid = false;
        _checking = false;
      });
      return;
    }

    setState(() {
      _statusText = null;
      _isValid = false;
      _checking = true;
    });

    _debounce = Timer(const Duration(milliseconds: 400), () {
      _checkApi(username);
    });
  }

  Future<void> _checkApi(String username) async {
    final engine = widget.engine;
    try {
      final available =
          await engine.checkAccountUsername(widget.accountId, username);
      if (!mounted) return;
      if (_ctrl.text.trim() != username) return;
      setState(() {
        _checking = false;
        if (available) {
          _statusText = '$username is available';
          _isValid = true;
        } else {
          _statusText = 'Sorry, this username is already taken';
          _isValid = false;
        }
      });
    } catch (e) {
      if (!mounted) return;
      if (_ctrl.text.trim() != username) return;
      final msg = e.toString();
      setState(() {
        _checking = false;
        _isValid = false;
        if (msg.contains('USERNAME_INVALID')) {
          _statusText = 'Sorry, this username is invalid';
        } else if (msg.contains('USERNAME_OCCUPIED')) {
          _statusText = 'Sorry, this username is already taken';
        } else {
          _statusText = 'Sorry, this username is invalid';
        }
      });
    }
  }

  Future<void> _save() async {
    final username = _ctrl.text.trim();
    if (!_isValid && username.isNotEmpty) return;

    setState(() => _saving = true);
    try {
      await widget.engine.updateAccountUsername(widget.accountId, username);
      if (mounted) Navigator.of(context).pop(username);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _statusText = e.toString().replaceFirst('Exception: ', '');
          _isValid = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final goodColor = p.boxTextFgGood;
    final errorColor = p.boxTextFgError;
    final subColor = p.boxTitleAdditionalFg;
    final textFg = p.boxTextFg;

    return TelegramBox(
      title: 'Username',
      onConfirm: (_isValid || _ctrl.text.trim().isEmpty) && !_saving
          ? _save
          : null,
      content: Padding(
        padding: EdgeInsets.fromLTRB(
            kBoxPadding.left, 0, kBoxPadding.right, kBoxPadding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You can choose a username on Telegram. If you do, people will be able to find you by this username.',
              style: TextStyle(fontSize: 14, height: 22 / 14, color: textFg),
            ),
            const SizedBox(height: 16),
            BoxInputField(
              controller: _ctrl,
              focusNode: _focusNode,
              label: 'Username',
              onChanged: _onChanged,
              enabled: !_saving,
            ),
            const SizedBox(height: 8),
            if (_checking)
              Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: subColor),
                  ),
                  const SizedBox(width: 8),
                  Text('Checking...',
                      style: TextStyle(fontSize: 13, color: subColor)),
                ],
              )
            else if (_statusText != null)
              Text(
                _statusText!,
                style: TextStyle(
                  fontSize: 13,
                  color: _isValid ? goodColor : errorColor,
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'You can use a–z, 0–9 and underscores. Minimum length is 5 characters.',
              style: TextStyle(fontSize: 13, color: subColor),
            ),
          ],
        ),
      ),
      buttons: [
        TelegramBoxButton(
          text: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        TelegramBoxButton(
          text: _saving ? 'Saving...' : 'Save',
          onPressed:
              (_isValid || _ctrl.text.trim().isEmpty) && !_saving ? _save : null,
        ),
      ],
    );
  }
}

// ─── showAddContactBox — §36.4 Add Contact with PhoneInput + country ────────

Future<bool?> showAddContactBox(
  BuildContext context, {
  String initialPhone = '',
  String initialFirstName = '',
  String initialLastName = '',
}) {
  final engine = context.read<EngineService>();
  final appState = context.read<AppState>();
  return showTelegramBox<bool>(
    context: context,
    builder: (ctx) => _AddContactBoxContent(
      initialPhone: initialPhone,
      initialFirstName: initialFirstName,
      initialLastName: initialLastName,
      engine: engine,
      appState: appState,
    ),
  );
}

class _AddContactBoxContent extends StatefulWidget {
  final String initialPhone;
  final String initialFirstName;
  final String initialLastName;
  final EngineService engine;
  final AppState appState;

  const _AddContactBoxContent({
    required this.initialPhone,
    required this.initialFirstName,
    required this.initialLastName,
    required this.engine,
    required this.appState,
  });

  @override
  State<_AddContactBoxContent> createState() => _AddContactBoxContentState();
}

class _AddContactBoxContentState extends State<_AddContactBoxContent> {
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  late final FocusNode _firstNameFocus;
  late final FocusNode _lastNameFocus;
  late final FocusNode _phoneFocus;
  CountryInfo _selectedCountry = countries.firstWhere((c) => c.iso == 'US');
  bool _saving = false;
  String? _error;
  bool _retry = false;

  @override
  void initState() {
    super.initState();
    _firstNameCtrl.text = widget.initialFirstName;
    _lastNameCtrl.text = widget.initialLastName;
    _phoneCtrl.text = widget.initialPhone;
    _firstNameFocus = FocusNode();
    _lastNameFocus = FocusNode();
    _phoneFocus = FocusNode();
    _codeCtrl.text = _selectedCountry.dialCode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _firstNameFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _firstNameFocus.dispose();
    _lastNameFocus.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  bool _isValidPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits == '333' || RegExp(r'^42\d\d$').hasMatch(digits)) return true;
    return digits.length >= 8;
  }

  void _onCodeChanged(String val) {
    final code = val.replaceAll(RegExp(r'\D'), '');
    if (code.isEmpty) return;
    final match = countries.where((c) => c.dialCode == code).firstOrNull;
    if (match != null && match != _selectedCountry) {
      setState(() => _selectedCountry = match);
    }
  }

  void _showCountryPicker() {
    showTelegramBox(
      context: context,
      builder: (ctx) => _CountryPickerContent(
        selected: _selectedCountry,
        onSelect: (country) {
          setState(() {
            _selectedCountry = country;
            _codeCtrl.text = country.dialCode;
          });
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  void _submit() {
    if (_retry) {
      setState(() {
        _firstNameCtrl.clear();
        _lastNameCtrl.clear();
        _phoneCtrl.clear();
        _error = null;
        _retry = false;
      });
      _firstNameFocus.requestFocus();
      return;
    }

    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    if (firstName.isEmpty && lastName.isEmpty) {
      setState(() => _error = 'Please enter a name');
      return;
    }

    final code = _codeCtrl.text.replaceAll(RegExp(r'\D'), '');
    final number = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    final fullPhone = '+$code$number';

    if (!_isValidPhone(number)) {
      setState(() => _error = 'Please enter a valid phone number');
      return;
    }

    _save(fullPhone, firstName, lastName);
  }

  Future<void> _save(String phone, String firstName, String lastName) async {
    final account = widget.appState.activeAccount;
    if (account == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.engine.addContact(account.id, phone, firstName, lastName);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        final msg = e.toString();
        if (msg.contains('not on Telegram') ||
            msg.contains('PHONE_NOT_OCCUPIED') ||
            msg.contains('no new users')) {
          setState(() {
            _saving = false;
            _error = 'This phone number is not on Telegram yet.';
            _retry = true;
          });
        } else {
          setState(() {
            _saving = false;
            _error = msg.replaceFirst('Exception: ', '');
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final errorColor = p.boxTextFgError;
    final borderColor = p.boxDividerBg;
    final textColor = p.boxTextFg;
    final subColor = p.boxTitleAdditionalFg;
    final focusBorderColor = p.activeLineFg;

    return TelegramBox(
      title: 'Add Contact',
      wide: true,
      onConfirm: !_saving ? _submit : null,
      content: Padding(
        padding: EdgeInsets.fromLTRB(
            kBoxPadding.left, 0, kBoxPadding.right, kBoxPadding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BoxInputField(
              controller: _firstNameCtrl,
              focusNode: _firstNameFocus,
              label: 'First name',
              enabled: !_saving,
              onSubmitted: (_) => _lastNameFocus.requestFocus(),
            ),
            const SizedBox(height: 9),
            BoxInputField(
              controller: _lastNameCtrl,
              focusNode: _lastNameFocus,
              label: 'Last name',
              enabled: !_saving,
              onSubmitted: (_) => _phoneFocus.requestFocus(),
            ),
            const SizedBox(height: 20),
            InkWell(
              onTap: _showCountryPicker,
              child: Row(
                children: [
                  Text(
                    _selectedCountry.flag,
                    style: const TextStyle(fontSize: 20),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _selectedCountry.name,
                    style: TextStyle(fontSize: 14, color: textColor),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, size: 18, color: subColor),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 70,
                  child: Row(
                    children: [
                      Text('+',
                          style: TextStyle(fontSize: 15, color: textColor)),
                      Expanded(
                        child: TextField(
                          controller: _codeCtrl,
                          style: TextStyle(fontSize: 15, color: textColor),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 8),
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          onChanged: _onCodeChanged,
                          enabled: !_saving,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  height: 30,
                  color: borderColor,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                ),
                Expanded(
                  child: TextField(
                    controller: _phoneCtrl,
                    focusNode: _phoneFocus,
                    style: TextStyle(fontSize: 15, color: textColor),
                    keyboardType: TextInputType.phone,
                    inputFormatters: [_PhoneNumberFormatter()],
                    enabled: !_saving,
                    decoration: InputDecoration(
                      hintText: 'Phone number',
                      hintStyle: TextStyle(fontSize: 14, color: subColor),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: borderColor)),
                      focusedBorder: UnderlineInputBorder(
                          borderSide:
                              BorderSide(color: focusBorderColor, width: 2)),
                    ),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(fontSize: 13, color: errorColor)),
            ],
            if (_saving) ...[
              const SizedBox(height: 12),
              const Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            ],
          ],
        ),
      ),
      buttons: [
        TelegramBoxButton(
          text: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        TelegramBoxButton(
          text: _retry ? 'Try Again' : 'Add',
          onPressed: !_saving ? _submit : null,
        ),
      ],
    );
  }
}

class _PhoneNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
          text: '', selection: TextSelection.collapsed(offset: 0));
    }
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 3 == 0) buf.write(' ');
      buf.write(digits[i]);
    }
    final formatted = buf.toString();
    final digitsBeforeCursor = newValue.text
        .substring(
            0, newValue.selection.end.clamp(0, newValue.text.length))
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

class _CountryPickerContent extends StatefulWidget {
  final CountryInfo selected;
  final void Function(CountryInfo) onSelect;

  const _CountryPickerContent({
    required this.selected,
    required this.onSelect,
  });

  @override
  State<_CountryPickerContent> createState() => _CountryPickerContentState();
}

class _CountryPickerContentState extends State<_CountryPickerContent> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<CountryInfo> get _filtered {
    if (_query.isEmpty) return countries.toList();
    final q = _query.toLowerCase();
    return countries
        .where(
            (c) => c.name.toLowerCase().contains(q) || c.dialCode.contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textColor = p.boxTextFg;
    final subColor = p.boxTitleAdditionalFg;
    final filtered = _filtered;

    return TelegramBox(
      title: 'Country',
      wide: true,
      showClose: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: TextStyle(fontSize: 14, color: textColor),
              decoration: InputDecoration(
                hintText: 'Search country',
                hintStyle: TextStyle(fontSize: 14, color: subColor),
                isDense: true,
                prefixIcon:
                    Icon(Icons.search, size: 20, color: subColor),
                border: InputBorder.none,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: filtered.length,
              itemExtent: 40,
              itemBuilder: (ctx, i) {
                final c = filtered[i];
                final isSelected = c.iso == widget.selected.iso;
                return InkWell(
                  onTap: () => widget.onSelect(c),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        Text(c.flag, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            c.name,
                            style: TextStyle(
                              fontSize: 14,
                              color: textColor,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text('+${c.dialCode}',
                            style: TextStyle(fontSize: 13, color: subColor)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      buttons: const [],
    );
  }
}

// ─── showEditInviteLinkBox — §36.4 Edit/Create invite link ──────────────────

class EditInviteLinkResult {
  final bool saved;
  EditInviteLinkResult({this.saved = false});
}

Future<EditInviteLinkResult?> showEditInviteLinkBox(
  BuildContext context, {
  required String accountId,
  required String chatId,
  String? existingLink,
  String existingLabel = '',
  int existingExpire = 0,
  int existingUsageLimit = 0,
  bool existingRequestApproval = false,
}) {
  final engine = context.read<EngineService>();
  return showTelegramBox<EditInviteLinkResult>(
    context: context,
    builder: (ctx) => _EditInviteLinkContent(
      accountId: accountId,
      chatId: chatId,
      existingLink: existingLink,
      existingLabel: existingLabel,
      existingExpire: existingExpire,
      existingUsageLimit: existingUsageLimit,
      existingRequestApproval: existingRequestApproval,
      engine: engine,
    ),
  );
}

class _EditInviteLinkContent extends StatefulWidget {
  final String accountId;
  final String chatId;
  final String? existingLink;
  final String existingLabel;
  final int existingExpire;
  final int existingUsageLimit;
  final bool existingRequestApproval;
  final EngineService engine;

  const _EditInviteLinkContent({
    required this.accountId,
    required this.chatId,
    this.existingLink,
    required this.existingLabel,
    required this.existingExpire,
    required this.existingUsageLimit,
    required this.existingRequestApproval,
    required this.engine,
  });

  @override
  State<_EditInviteLinkContent> createState() => _EditInviteLinkContentState();
}

class _EditInviteLinkContentState extends State<_EditInviteLinkContent> {
  late final TextEditingController _labelCtrl;
  int _expireOption = 2592000;
  int _usageLimitOption = 0;
  bool _requestApproval = false;
  bool _saving = false;

  bool get _isEdit => widget.existingLink != null;

  static const _expireOptions = <int, String>{
    0: 'Never',
    3600: '1 hour',
    86400: '1 day',
    604800: '7 days',
    2592000: '30 days',
  };

  static const _usageOptions = <int, String>{
    0: 'Unlimited',
    1: '1 use',
    10: '10 uses',
    100: '100 uses',
  };

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.existingLabel);
    _requestApproval = widget.existingRequestApproval;
    if (_isEdit) {
      if (widget.existingExpire > 0) {
        _expireOption = _expireOptions.keys.firstWhere(
          (k) => k > 0 && (widget.existingExpire - k).abs() < k * 0.1,
          orElse: () => 2592000,
        );
      } else {
        _expireOption = 0;
      }
      _usageLimitOption = _usageOptions.containsKey(widget.existingUsageLimit)
          ? widget.existingUsageLimit
          : 0;
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final engine = widget.engine;
    final label = _labelCtrl.text.trim();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expireDate = _expireOption > 0 ? now + _expireOption : 0;
    final usageLimit = _requestApproval ? 0 : _usageLimitOption;

    try {
      if (_isEdit) {
        await engine.editChatInviteLink(
          widget.accountId,
          widget.chatId,
          widget.existingLink!,
          label: label,
          expireDate: expireDate,
          usageLimit: usageLimit,
          requestApproval: _requestApproval,
        );
      } else {
        await engine.createChatInviteLink(
          widget.accountId,
          widget.chatId,
          label: label,
          expireDate: expireDate,
          usageLimit: usageLimit,
          requestApproval: _requestApproval,
        );
      }
      if (mounted) {
        Navigator.of(context).pop(EditInviteLinkResult(saved: true));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showTelegramToast(context, 'Failed: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textColor = p.boxTextFg;
    final subColor = p.boxTitleAdditionalFg;
    final accentColor = p.windowActiveTextFg;
    final checkClr = p.windowBgActive;
    final chipBg = p.windowBgOver;

    return TelegramBox(
      title: _isEdit ? 'Edit Link' : 'Create New Link',
      wide: true,
      onConfirm: !_saving ? _save : null,
      content: Padding(
        padding: EdgeInsets.fromLTRB(
            kBoxPadding.left, 0, kBoxPadding.right, kBoxPadding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Link Name',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: accentColor)),
            const SizedBox(height: 8),
            BoxInputField(
              controller: _labelCtrl,
              label: 'Label (optional)',
              enabled: !_saving,
            ),
            const SizedBox(height: 20),
            Text('Expire After',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: accentColor)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _expireOptions.entries.map((entry) {
                final selected = _expireOption == entry.key;
                return ChoiceChip(
                  label: Text(entry.value),
                  selected: selected,
                  onSelected:
                      _saving ? null : (v) => setState(() => _expireOption = entry.key),
                  labelStyle: TextStyle(
                    fontSize: 13,
                    color: selected ? Colors.white : textColor,
                  ),
                  selectedColor: checkClr,
                  backgroundColor: chipBg,
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            Text('Usage Limit',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: accentColor)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _usageOptions.entries.map((entry) {
                final selected = _usageLimitOption == entry.key;
                return ChoiceChip(
                  label: Text(entry.value),
                  selected: selected,
                  onSelected: _saving || _requestApproval
                      ? null
                      : (v) => setState(() => _usageLimitOption = entry.key),
                  labelStyle: TextStyle(
                    fontSize: 13,
                    color: selected ? Colors.white : textColor,
                  ),
                  selectedColor: checkClr,
                  backgroundColor: chipBg,
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _saving
                  ? null
                  : () => setState(() => _requestApproval = !_requestApproval),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: Checkbox(
                      value: _requestApproval,
                      onChanged: _saving
                          ? null
                          : (v) =>
                              setState(() => _requestApproval = v ?? false),
                      activeColor: checkClr,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Request Admin Approval',
                        style: TextStyle(fontSize: 14, color: textColor)),
                  ),
                ],
              ),
            ),
            if (_requestApproval) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Text(
                  'Users will request to join and admins will approve them.',
                  style: TextStyle(fontSize: 12, color: subColor),
                ),
              ),
            ],
            if (_saving) ...[
              const SizedBox(height: 12),
              const Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            ],
          ],
        ),
      ),
      buttons: [
        TelegramBoxButton(
          text: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        TelegramBoxButton(
          text: _isEdit ? 'Save' : 'Create',
          onPressed: !_saving ? _save : null,
        ),
      ],
    );
  }
}

// ─── showCreatePollBox — §36.4 Create Poll dialog ───────────────────────────

class CreatePollResult {
  final String question;
  final List<String> options;
  final bool multipleChoice;
  final bool anonymous;
  final bool quiz;

  const CreatePollResult({
    required this.question,
    required this.options,
    this.multipleChoice = false,
    this.anonymous = true,
    this.quiz = false,
  });
}

Future<CreatePollResult?> showCreatePollBox(BuildContext context) {
  return showTelegramBox<CreatePollResult>(
    context: context,
    builder: (ctx) => const _CreatePollContent(),
  );
}

class _CreatePollContent extends StatefulWidget {
  const _CreatePollContent();

  @override
  State<_CreatePollContent> createState() => _CreatePollContentState();
}

class _CreatePollContentState extends State<_CreatePollContent> {
  final _questionCtrl = TextEditingController();
  final List<TextEditingController> _optionCtrls = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _multipleChoice = false;
  bool _anonymous = true;
  bool _quiz = false;

  @override
  void dispose() {
    _questionCtrl.dispose();
    for (final c in _optionCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_optionCtrls.length >= 10) return;
    setState(() => _optionCtrls.add(TextEditingController()));
  }

  void _removeOption(int index) {
    if (_optionCtrls.length <= 2) return;
    setState(() {
      _optionCtrls[index].dispose();
      _optionCtrls.removeAt(index);
    });
  }

  bool get _canSubmit {
    final q = _questionCtrl.text.trim();
    if (q.isEmpty) return false;
    final opts =
        _optionCtrls.map((c) => c.text.trim()).where((s) => s.isNotEmpty);
    return opts.length >= 2;
  }

  void _submit() {
    if (!_canSubmit) return;
    final question = _questionCtrl.text.trim();
    final options =
        _optionCtrls.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
    Navigator.of(context).pop(CreatePollResult(
      question: question,
      options: options,
      multipleChoice: _multipleChoice,
      anonymous: _anonymous,
      quiz: _quiz,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textColor = p.boxTextFg;
    final subColor = p.boxTitleAdditionalFg;
    final accentColor = p.windowActiveTextFg;
    final checkClr = p.windowBgActive;

    return TelegramBox(
      title: 'Create Poll',
      wide: true,
      onConfirm: _canSubmit ? _submit : null,
      content: Padding(
        padding: EdgeInsets.fromLTRB(
            kBoxPadding.left, 0, kBoxPadding.right, kBoxPadding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BoxInputField(
              controller: _questionCtrl,
              label: 'Ask a question',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),
            Text('Answer Options',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: accentColor)),
            const SizedBox(height: 8),
            for (var i = 0; i < _optionCtrls.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: BoxInputField(
                        controller: _optionCtrls[i],
                        label: 'Option ${i + 1}',
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    if (_optionCtrls.length > 2)
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: IconButton(
                          icon: Icon(Icons.close, size: 16, color: subColor),
                          padding: EdgeInsets.zero,
                          onPressed: () => _removeOption(i),
                        ),
                      ),
                  ],
                ),
              ),
            if (_optionCtrls.length < 10)
              TextButton.icon(
                onPressed: _addOption,
                icon: Icon(Icons.add, size: 18, color: accentColor),
                label: Text('Add Option',
                    style: TextStyle(fontSize: 13, color: accentColor)),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
              ),
            const SizedBox(height: 16),
            Text('Settings',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: accentColor)),
            const SizedBox(height: 8),
            _checkRow('Anonymous Voting', _anonymous,
                (v) => setState(() => _anonymous = v ?? true), checkClr, textColor),
            const SizedBox(height: 8),
            _checkRow('Multiple Answers', _multipleChoice,
                (v) => setState(() {
                  _multipleChoice = v ?? false;
                  if (_multipleChoice) _quiz = false;
                }), checkClr, textColor),
            const SizedBox(height: 8),
            _checkRow('Quiz Mode', _quiz, (v) => setState(() {
              _quiz = v ?? false;
              if (_quiz) _multipleChoice = false;
            }), checkClr, textColor),
          ],
        ),
      ),
      buttons: [
        TelegramBoxButton(
          text: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        TelegramBoxButton(
          text: 'Create',
          onPressed: _canSubmit ? _submit : null,
        ),
      ],
    );
  }

  Widget _checkRow(String label, bool value, ValueChanged<bool?> onChanged,
      Color checkColor, Color textColor) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: checkColor,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 14, color: textColor)),
          ),
        ],
      ),
    );
  }
}

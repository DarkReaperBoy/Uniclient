import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';
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
  String? _purchaseUsername;
  bool _isValid = false;
  bool _checking = false;
  bool _saving = false;
  List<Map<String, dynamic>> _additionalUsernames = [];
  bool _loadingUsernames = false;
  static final _usernameRegex = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{3,31}$');

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.currentUsername);
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
    _loadUsernames();
  }

  Future<void> _loadUsernames() async {
    setState(() => _loadingUsernames = true);
    try {
      final usernames = await widget.engine.getAccountUsernames(widget.accountId);
      if (mounted) {
        setState(() {
          _additionalUsernames = usernames.where((u) {
            final name = u['username'] as String? ?? '';
            return name != widget.currentUsername;
          }).toList();
          _loadingUsernames = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingUsernames = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String _cleanUsername(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('@')) return trimmed.substring(1);
    return trimmed;
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final username = _cleanUsername(value);

    if (username.isEmpty) {
      setState(() {
        _statusText = null;
        _purchaseUsername = null;
        _isValid = false;
        _checking = false;
      });
      return;
    }

    if (username == widget.currentUsername) {
      setState(() {
        _statusText = null;
        _purchaseUsername = null;
        _isValid = false;
        _checking = false;
      });
      return;
    }

    if (username.length < 5) {
      setState(() {
        _statusText = 'Username must be at least 5 characters';
        _purchaseUsername = null;
        _isValid = false;
        _checking = false;
      });
      return;
    }

    if (username.length > 32) {
      setState(() {
        _statusText = 'Username is too long';
        _purchaseUsername = null;
        _isValid = false;
        _checking = false;
      });
      return;
    }

    if (!_usernameRegex.hasMatch(username)) {
      setState(() {
        _statusText = 'Sorry, this username is invalid';
        _purchaseUsername = null;
        _isValid = false;
        _checking = false;
      });
      return;
    }

    setState(() {
      _statusText = null;
      _purchaseUsername = null;
      _isValid = false;
      _checking = true;
    });

    _debounce = Timer(const Duration(milliseconds: 200), () {
      _checkApi(username);
    });
  }

  Future<void> _checkApi(String username) async {
    final engine = widget.engine;
    try {
      final available =
          await engine.checkAccountUsername(widget.accountId, username);
      if (!mounted) return;
      if (_cleanUsername(_ctrl.text) != username) return;
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
      if (_cleanUsername(_ctrl.text) != username) return;
      final msg = e.toString();
      setState(() {
        _checking = false;
        _isValid = false;
        _purchaseUsername = null;
        if (msg.contains('USERNAME_PURCHASE_AVAILABLE')) {
          _purchaseUsername = username;
          _statusText = null;
        } else if (msg.contains('USERNAME_INVALID')) {
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
    final username = _cleanUsername(_ctrl.text);
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

  Future<void> _toggleUsername(String username, bool active) async {
    try {
      await widget.engine.toggleAccountUsername(widget.accountId, username, active);
      await _loadUsernames();
    } catch (e) {
      if (mounted) showTelegramToast(context, 'Failed: $e');
    }
  }

  Widget _usernameRow(Map<String, dynamic> u, Color textColor, Color subColor, TelegramPalette p) {
    final name = u['username'] as String? ?? '';
    final active = u['active'] as bool? ?? false;
    final editable = u['editable'] as bool? ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            Icons.drag_handle,
            size: 18,
            color: editable ? subColor : subColor.withValues(alpha: 0.3),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '@$name',
              style: TextStyle(
                fontSize: 14,
                color: active ? textColor : subColor,
              ),
            ),
          ),
          if (editable)
            SizedBox(
              width: 40,
              height: 28,
              child: Switch(
                value: active,
                onChanged: (v) => _toggleUsername(name, v),
                activeColor: p.windowBgActive,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
    );
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
      onConfirm: (_isValid || _cleanUsername(_ctrl.text).isEmpty) && !_saving
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
            else if (_purchaseUsername != null)
              RichText(
                text: TextSpan(
                  style: TextStyle(fontSize: 13, color: textFg),
                  children: [
                    const TextSpan(text: 'This username can be purchased on '),
                    TextSpan(
                      text: 'Fragment',
                      style: TextStyle(color: p.windowActiveTextFg),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () {
                          launchUrl(Uri.parse(
                              'https://fragment.com/username/$_purchaseUsername'));
                        },
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
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
            if (_additionalUsernames.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Additional usernames',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.windowActiveTextFg),
              ),
              const SizedBox(height: 8),
              for (final u in _additionalUsernames)
                _usernameRow(u, textFg, subColor, p),
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
          text: _saving ? 'Saving...' : 'Save',
          onPressed:
              (_isValid || _cleanUsername(_ctrl.text).isEmpty) && !_saving ? _save : null,
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
  late final _PhoneNumberFormatter _phoneFormatter;
  late CountryInfo _selectedCountry;
  bool _saving = false;
  String? _error;
  bool _retry = false;
  bool _invertNameOrder = false;

  @override
  void initState() {
    super.initState();
    final account = widget.appState.activeAccount;
    final userPhone = account?.phone ?? '';
    final fromPhone = countryFromPhone(userPhone);
    _selectedCountry = fromPhone ?? countries.firstWhere((c) => c.iso == 'US');
    _firstNameCtrl.text = widget.initialFirstName;
    _lastNameCtrl.text = widget.initialLastName;
    _phoneCtrl.text = widget.initialPhone;
    _firstNameFocus = FocusNode();
    _lastNameFocus = FocusNode();
    _phoneFocus = FocusNode();
    _codeCtrl.text = _selectedCountry.dialCode;
    _phoneFormatter = _PhoneNumberFormatter(dialCode: _selectedCountry.dialCode);
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    _invertNameOrder = const {'ja', 'ko', 'zh', 'hu', 'vi'}.contains(locale.languageCode);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      (_invertNameOrder ? _lastNameFocus : _firstNameFocus).requestFocus();
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
    if (digits == '333') return true;
    if (digits.startsWith('42') &&
        (digits.length == 2 || digits.length == 5 ||
         digits.length == 6 || digits == '4242')) {
      return true;
    }
    return digits.length >= 8;
  }

  void _onCodeChanged(String val) {
    final code = val.replaceAll(RegExp(r'\D'), '');
    if (code.isEmpty) return;
    final match = countries.where((c) => c.dialCode == code).firstOrNull;
    if (match != null && match != _selectedCountry) {
      _phoneFormatter.dialCode = code;
      setState(() => _selectedCountry = match);
    }
  }

  void _showCountryPicker() {
    showTelegramBox(
      context: context,
      builder: (ctx) => _CountryPickerContent(
        selected: _selectedCountry,
        onSelect: (country) {
          _phoneFormatter.dialCode = country.dialCode;
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
      final userId = await widget.engine.addContact(account.id, phone, firstName, lastName);
      if (mounted) {
        final chatState = context.read<ChatState>();
        chatState.loadChats();
        if (userId.isNotEmpty) {
          chatState.openChatById(userId);
        }
        if (mounted) Navigator.of(context).pop(true);
      }
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
              controller: _invertNameOrder ? _lastNameCtrl : _firstNameCtrl,
              focusNode: _invertNameOrder ? _lastNameFocus : _firstNameFocus,
              label: _invertNameOrder ? 'Last name' : 'First name',
              enabled: !_saving,
              onSubmitted: (_) => (_invertNameOrder ? _firstNameFocus : _lastNameFocus).requestFocus(),
            ),
            const SizedBox(height: 9),
            BoxInputField(
              controller: _invertNameOrder ? _firstNameCtrl : _lastNameCtrl,
              focusNode: _invertNameOrder ? _firstNameFocus : _lastNameFocus,
              label: _invertNameOrder ? 'First name' : 'Last name',
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
                    inputFormatters: [_phoneFormatter],
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
  String dialCode;
  _PhoneNumberFormatter({this.dialCode = ''});

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
          text: '', selection: TextSelection.collapsed(offset: 0));
    }
    final formatted = formatPhoneDigits(digits, dialCode);
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

  List<CountryInfo> _buildList() {
    List<CountryInfo> list;
    if (_query.isEmpty) {
      list = countries.toList();
    } else {
      final q = _query.toLowerCase();
      list = countries.where((c) {
        if (c.dialCode.contains(q)) return true;
        final words = c.name.toLowerCase().split(RegExp(r'[\s\-]+'));
        return words.any((w) => w.startsWith(q));
      }).toList();
    }
    final selIso = widget.selected.iso;
    final idx = list.indexWhere((c) => c.iso == selIso);
    if (idx > 0) {
      final sel = list.removeAt(idx);
      list.insert(0, sel);
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textColor = p.boxTextFg;
    final subColor = p.boxTitleAdditionalFg;
    final filtered = _buildList();

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
            child: filtered.isEmpty
                ? SizedBox(
                    height: 52,
                    child: Center(
                      child: Text(
                        'No countries found',
                        style: TextStyle(fontSize: 14, color: subColor),
                      ),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemExtent: 36,
                    itemBuilder: (ctx, i) {
                      final c = filtered[i];
                      final isSelected = c.iso == widget.selected.iso;
                      return InkWell(
                        onTap: () => widget.onSelect(c),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 22, right: 8),
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
  bool isPublic = false,
  int existingSubscriptionCredits = 0,
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
      isPublic: isPublic,
      existingSubscriptionCredits: existingSubscriptionCredits,
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
  final bool isPublic;
  final int existingSubscriptionCredits;
  final EngineService engine;

  const _EditInviteLinkContent({
    required this.accountId,
    required this.chatId,
    this.existingLink,
    required this.existingLabel,
    required this.existingExpire,
    required this.existingUsageLimit,
    required this.existingRequestApproval,
    this.isPublic = false,
    this.existingSubscriptionCredits = 0,
    required this.engine,
  });

  @override
  State<_EditInviteLinkContent> createState() => _EditInviteLinkContentState();
}

class _EditInviteLinkContentState extends State<_EditInviteLinkContent> {
  late final TextEditingController _labelCtrl;
  late final TextEditingController _creditsCtrl;
  int _expireOption = 0;
  int _usageLimitOption = 0;
  int _customExpireDate = 0;
  int _customUsageLimit = 0;
  bool _requestApproval = false;
  bool _subscription = false;
  bool _subscriptionLocked = false;
  bool _saving = false;

  static const _kMaxLabelLength = 32;

  bool get _isEdit => widget.existingLink != null;

  static const _expireOptions = <int, String>{
    0: 'Never',
    3600: '1 hour',
    86400: '1 day',
    604800: '7 days',
    2592000: '30 days',
    -1: 'Custom',
  };

  static const _usageOptions = <int, String>{
    0: 'Unlimited',
    1: '1 use',
    10: '10 uses',
    100: '100 uses',
    -1: 'Custom',
  };

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: widget.existingLabel);
    _subscriptionLocked = widget.existingSubscriptionCredits > 0;
    _subscription = _subscriptionLocked;
    _creditsCtrl = TextEditingController(
      text: widget.existingSubscriptionCredits > 0
          ? '${widget.existingSubscriptionCredits}'
          : '',
    );
    _requestApproval = widget.existingRequestApproval;
    if (_isEdit) {
      if (widget.existingExpire > 0) {
        final match = _expireOptions.keys.where(
          (k) => k > 0 && (widget.existingExpire - k).abs() < k * 0.1,
        ).firstOrNull;
        if (match != null) {
          _expireOption = match;
        } else {
          _expireOption = -1;
          _customExpireDate = widget.existingExpire;
        }
      } else {
        _expireOption = 0;
      }
      if (_usageOptions.containsKey(widget.existingUsageLimit)) {
        _usageLimitOption = widget.existingUsageLimit;
      } else if (widget.existingUsageLimit > 0) {
        _usageLimitOption = -1;
        _customUsageLimit = widget.existingUsageLimit;
      }
    }
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _creditsCtrl.dispose();
    super.dispose();
  }

  Future<void> _showCustomExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _customExpireDate > 0
          ? DateTime.fromMillisecondsSinceEpoch(_customExpireDate * 1000)
          : now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );
      if (mounted) {
        final dt = time != null
            ? DateTime(picked.year, picked.month, picked.day, time.hour, time.minute)
            : DateTime(picked.year, picked.month, picked.day, 23, 59);
        setState(() {
          _customExpireDate = dt.millisecondsSinceEpoch ~/ 1000;
          _expireOption = -1;
        });
      }
    }
  }

  Future<void> _showCustomUsageLimit() async {
    final ctrl = TextEditingController(
      text: _customUsageLimit > 0 ? '$_customUsageLimit' : '',
    );
    final result = await showTelegramBox<int>(
      context: context,
      builder: (ctx) => TelegramBox(
        title: 'Usage Limit',
        onConfirm: () {
          final val = int.tryParse(ctrl.text.trim()) ?? 0;
          if (val > 0) Navigator.of(ctx).pop(val);
        },
        content: Padding(
          padding: EdgeInsets.fromLTRB(kBoxPadding.left, 0, kBoxPadding.right, kBoxPadding.bottom),
          child: BoxInputField(
            controller: ctrl,
            label: 'Enter limit (max 200000)',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
        ),
        buttons: [
          TelegramBoxButton(text: 'Cancel', onPressed: () => Navigator.of(ctx).pop()),
          TelegramBoxButton(text: 'Save', onPressed: () {
            final val = int.tryParse(ctrl.text.trim()) ?? 0;
            if (val > 0 && val <= 200000) Navigator.of(ctx).pop(val);
          }),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null && result > 0 && mounted) {
      setState(() {
        _customUsageLimit = result;
        _usageLimitOption = -1;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final engine = widget.engine;
    final label = _labelCtrl.text.trim();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    int expireDate;
    if (_expireOption == -1 && _customExpireDate > 0) {
      expireDate = _customExpireDate;
    } else if (_expireOption > 0) {
      expireDate = now + _expireOption;
    } else {
      expireDate = 0;
    }
    final usageLimit = _requestApproval
        ? 0
        : (_usageLimitOption == -1 ? _customUsageLimit : _usageLimitOption);
    final subscriptionCredits = _subscription
        ? (int.tryParse(_creditsCtrl.text.trim()) ?? 0)
        : 0;

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
          subscriptionCredits: subscriptionCredits,
        );
      } else {
        await engine.createChatInviteLink(
          widget.accountId,
          widget.chatId,
          label: label,
          expireDate: expireDate,
          usageLimit: usageLimit,
          requestApproval: _requestApproval,
          subscriptionCredits: subscriptionCredits,
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
              inputFormatters: [LengthLimitingTextInputFormatter(_kMaxLabelLength)],
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
                String label = entry.value;
                if (entry.key == -1 && _customExpireDate > 0 && selected) {
                  final dt = DateTime.fromMillisecondsSinceEpoch(_customExpireDate * 1000);
                  label = '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
                }
                return ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: _saving
                      ? null
                      : (v) {
                          if (entry.key == -1) {
                            _showCustomExpiry();
                          } else {
                            setState(() => _expireOption = entry.key);
                          }
                        },
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
                String label = entry.value;
                if (entry.key == -1 && _customUsageLimit > 0 && selected) {
                  label = '$_customUsageLimit uses';
                }
                return ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: _saving || _requestApproval
                      ? null
                      : (v) {
                          if (entry.key == -1) {
                            _showCustomUsageLimit();
                          } else {
                            setState(() => _usageLimitOption = entry.key);
                          }
                        },
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
            if (!widget.isPublic) ...[
              const SizedBox(height: 12),
              InkWell(
                onTap: (_saving || _subscriptionLocked)
                    ? () {
                        if (_subscriptionLocked) {
                          showTelegramToast(context,
                              'Subscription links cannot be changed after creation.');
                        }
                      }
                    : () => setState(() {
                          _subscription = !_subscription;
                          if (_subscription) _requestApproval = false;
                        }),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: Checkbox(
                        value: _subscription,
                        onChanged: (_saving || _subscriptionLocked)
                            ? null
                            : (v) => setState(() {
                                  _subscription = v ?? false;
                                  if (_subscription) _requestApproval = false;
                                }),
                        activeColor: checkClr,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Subscription',
                          style: TextStyle(fontSize: 14, color: textColor)),
                    ),
                  ],
                ),
              ),
              if (_subscription) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Users will pay star credits to subscribe via this link.',
                        style: TextStyle(fontSize: 12, color: subColor),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: 180,
                        child: BoxInputField(
                          controller: _creditsCtrl,
                          label: 'Star credits',
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          enabled: !_saving && !_subscriptionLocked,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
  final bool allowRevoting;
  final int correctOptionIndex;
  final String solution;

  const CreatePollResult({
    required this.question,
    required this.options,
    this.multipleChoice = false,
    this.anonymous = true,
    this.quiz = false,
    this.allowRevoting = true,
    this.correctOptionIndex = -1,
    this.solution = '',
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
  static const _kQuestionLimit = 255;
  static const _kOptionLimit = 100;
  static const _kWarnOptionLimit = 30;
  static const _kSolutionLimit = 200;
  static const _kMaxOptions = 32;

  final _questionCtrl = TextEditingController();
  final _solutionCtrl = TextEditingController();
  final List<TextEditingController> _optionCtrls = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _multipleChoice = false;
  bool _anonymous = true;
  bool _quiz = false;
  bool _allowRevoting = true;
  int _correctOption = -1;

  @override
  void dispose() {
    _questionCtrl.dispose();
    _solutionCtrl.dispose();
    for (final c in _optionCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _addOption() {
    if (_optionCtrls.length >= _kMaxOptions) return;
    setState(() => _optionCtrls.add(TextEditingController()));
  }

  void _removeOption(int index) {
    if (_optionCtrls.length <= 2) return;
    setState(() {
      _optionCtrls[index].dispose();
      _optionCtrls.removeAt(index);
      if (_correctOption == index) {
        _correctOption = -1;
      } else if (_correctOption > index) {
        _correctOption--;
      }
    });
  }

  bool get _canSubmit {
    final q = _questionCtrl.text.trim();
    if (q.isEmpty || q.length > _kQuestionLimit) return false;
    final opts =
        _optionCtrls.map((c) => c.text.trim()).where((s) => s.isNotEmpty);
    if (opts.length < 2) return false;
    if (_quiz && (_correctOption < 0 || _correctOption >= _optionCtrls.length)) return false;
    return true;
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
      allowRevoting: _allowRevoting,
      correctOptionIndex: _quiz ? _correctOption : -1,
      solution: _quiz ? _solutionCtrl.text.trim() : '',
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
              inputFormatters: [LengthLimitingTextInputFormatter(_kQuestionLimit)],
            ),
            if (_questionCtrl.text.length > 80)
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${_questionCtrl.text.length}/$_kQuestionLimit',
                  style: TextStyle(
                    fontSize: 12,
                    color: _questionCtrl.text.length > _kQuestionLimit
                        ? p.boxTextFgError
                        : subColor,
                  ),
                ),
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (_quiz)
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Radio<int>(
                              value: i,
                              groupValue: _correctOption,
                              onChanged: (v) => setState(() => _correctOption = v ?? -1),
                              activeColor: p.windowBgActive,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        if (_quiz) const SizedBox(width: 4),
                        Expanded(
                          child: BoxInputField(
                            controller: _optionCtrls[i],
                            label: 'Option ${i + 1}',
                            onChanged: (_) => setState(() {}),
                            inputFormatters: [LengthLimitingTextInputFormatter(_kOptionLimit)],
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
                    if (_optionCtrls[i].text.length >= _kWarnOptionLimit)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '${_optionCtrls[i].text.length}/$_kOptionLimit',
                          style: TextStyle(
                            fontSize: 12,
                            color: _optionCtrls[i].text.length > _kOptionLimit
                                ? p.boxTextFgError
                                : subColor,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (_optionCtrls.length < _kMaxOptions)
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
            _checkRow('Allow Revoting', _allowRevoting,
                (v) => setState(() => _allowRevoting = v ?? true),
                checkClr, textColor),
            const SizedBox(height: 8),
            _checkRow('Quiz Mode', _quiz, (v) => setState(() {
              _quiz = v ?? false;
              if (_quiz) {
                _multipleChoice = false;
              } else {
                _correctOption = -1;
                _solutionCtrl.clear();
              }
            }), checkClr, textColor),
            if (_quiz) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: Text(
                  'Select the correct answer by tapping the radio button next to an option.',
                  style: TextStyle(fontSize: 12, color: subColor),
                ),
              ),
              const SizedBox(height: 12),
              Text('Explanation (optional)',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: accentColor)),
              const SizedBox(height: 8),
              BoxInputField(
                controller: _solutionCtrl,
                label: 'Add a comment',
                onChanged: (_) => setState(() {}),
                inputFormatters: [LengthLimitingTextInputFormatter(_kSolutionLimit)],
              ),
              if (_solutionCtrl.text.length > 60)
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${_solutionCtrl.text.length}/$_kSolutionLimit',
                    style: TextStyle(fontSize: 12, color: subColor),
                  ),
                ),
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

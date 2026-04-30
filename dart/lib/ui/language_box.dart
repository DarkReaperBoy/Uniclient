import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../state/app_state.dart';
import 'popup_menu.dart';
import 'telegram_toast.dart';

class LanguageBox extends StatefulWidget {
  const LanguageBox({super.key});

  @override
  State<LanguageBox> createState() => _LanguageBoxState();
}

class _LanguageBoxState extends State<LanguageBox> {
  List<_LangEntry> _allLanguages = [];
  List<_LangEntry> _filtered = [];
  bool _loading = true;
  String _searchQuery = '';
  late String _selectedCode;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _selectedCode = context.read<AppState>().selectedLanguageCode;
    _loadLanguages();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _loadLanguages() async {
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccountId;
    if (accountId.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final rawLangs = await engine.getLanguages(accountId);
    if (!mounted) return;

    final langs = <_LangEntry>[];
    for (final m in rawLangs) {
      langs.add(_LangEntry(
        langCode: m['lang_code'] as String? ?? '',
        name: m['name'] as String? ?? '',
        nativeName: m['native_name'] as String? ?? '',
        official: m['official'] as bool? ?? false,
        rtl: m['rtl'] as bool? ?? false,
        beta: m['beta'] as bool? ?? false,
      ));
    }
    setState(() {
      _allLanguages = langs;
      _filtered = _buildFilteredList(langs, _searchQuery);
      _loading = false;
    });
  }

  List<_LangEntry> _buildFilteredList(List<_LangEntry> all, String query) {
    if (query.isEmpty) return all;
    final q = query.toLowerCase();
    return all.where((l) =>
        l.name.toLowerCase().contains(q) ||
        l.nativeName.toLowerCase().contains(q) ||
        l.langCode.toLowerCase().contains(q)).toList();
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
      _filtered = _buildFilteredList(_allLanguages, value);
    });
  }

  void _selectLanguage(String langCode) {
    context.read<AppState>().addRecentLanguage(langCode);
    setState(() => _selectedCode = langCode);
    Navigator.of(context).pop(langCode);
  }

  String _skipLangsLabel(AppState appState) {
    final langs = appState.skipTranslationLanguages;
    if (langs.length == 1) {
      final entry = _allLanguages.where((l) => l.langCode == langs.first).firstOrNull;
      if (entry != null) {
        return entry.nativeName.isNotEmpty ? entry.nativeName : entry.name;
      }
      return langs.first.toUpperCase();
    }
    return '${langs.length} languages';
  }

  void _openSkipLanguagesEditor(AppState appState) {
    showDialog(
      context: context,
      builder: (_) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: appState),
          Provider.value(value: context.read<EngineService>()),
        ],
        child: _SkipLanguagesEditor(allLanguages: _allLanguages),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subTextColor = isDark ? const Color(0xFF7B8D9D) : const Color(0xFF999999);
    final accentColor = isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final hoverColor = isDark ? const Color(0xFF202B36) : const Color(0xFFF1F1F1);
    final dividerColor = isDark ? const Color(0xFF101921) : const Color(0xFFE0E0E0);
    final searchBgColor = isDark ? const Color(0xFF242F3D) : const Color(0xFFF0F0F0);

    final appState = context.watch<AppState>();
    final isLoggedIn = appState.activeAccountId.isNotEmpty;
    final showTranslate = appState.showTranslateButton;
    final translateChats = appState.translateEntireChats;
    final showDoNotTranslate = showTranslate || translateChats;

    final screenHeight = MediaQuery.of(context).size.height;
    final maxDialogHeight = screenHeight - 48;

    return Dialog(
      backgroundColor: bgColor,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 320, maxHeight: maxDialogHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 4),
              child: Text(
                'Language',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
            // §19.14: Translation toggles (logged-in only)
            if (isLoggedIn) ...[
              const SizedBox(height: 4),
              _ToggleRow(
                label: 'Show Translate Button',
                value: showTranslate,
                isDark: isDark,
                textColor: textColor,
                hoverColor: hoverColor,
                onChanged: (v) => appState.setShowTranslateButton(v),
              ),
              _ToggleRow(
                label: 'Translate Entire Chats',
                value: translateChats,
                isDark: isDark,
                textColor: textColor,
                hoverColor: hoverColor,
                locked: true,
                onChanged: (v) => appState.setTranslateEntireChats(v),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: showDoNotTranslate
                    ? InkWell(
                        onTap: () => _openSkipLanguagesEditor(appState),
                        hoverColor: hoverColor,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(22, 10, 22, 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Do Not Translate',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: textColor,
                                  ),
                                ),
                              ),
                              Text(
                                _skipLangsLabel(appState),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: accentColor,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.chevron_right, size: 18, color: subTextColor),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
                child: Text(
                  'Translate messages in chats with a different language.',
                  style: TextStyle(fontSize: 12, color: subTextColor),
                ),
              ),
              Container(height: 7, color: dividerColor),
            ],
            const SizedBox(height: 8),
            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: searchBgColor,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  onChanged: _onSearchChanged,
                  style: TextStyle(fontSize: 13, color: textColor),
                  decoration: InputDecoration(
                    hintText: 'Search',
                    hintStyle: TextStyle(fontSize: 13, color: subTextColor),
                    prefixIcon: Icon(Icons.search, size: 18, color: subTextColor),
                    prefixIconConstraints: const BoxConstraints(minWidth: 36),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    isDense: true,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Container(height: 1, color: dividerColor),
            // Language list
            if (_loading)
              const SizedBox(
                height: 100,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_filtered.isEmpty)
              SizedBox(
                height: 100,
                child: Center(
                  child: Text(
                    'No languages found',
                    style: TextStyle(fontSize: 13, color: subTextColor),
                  ),
                ),
              )
            else
              Flexible(
                child: _buildLanguageList(
                  isDark, textColor, subTextColor, accentColor,
                  hoverColor, dividerColor,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageList(
    bool isDark,
    Color textColor,
    Color subTextColor,
    Color accentColor,
    Color hoverColor,
    Color dividerColor,
  ) {
    final appState = context.read<AppState>();
    final recentCodes = appState.recentLanguageCodes;

    // §19.15: Recent = languages whose code is in recentLanguageCodes, ordered by recency.
    // Current selected language is always first if it's in the filtered list.
    final recent = <_LangEntry>[];
    final recentCodeSet = <String>{};
    for (final code in recentCodes) {
      final entry = _filtered.where((l) => l.langCode == code).firstOrNull;
      if (entry != null) {
        recent.add(entry);
        recentCodeSet.add(code);
      }
    }

    // §19.15: Official = official languages NOT already in Recent (de-duplicated).
    final official = _filtered
        .where((l) => l.official && !recentCodeSet.contains(l.langCode))
        .toList();

    return ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      itemCount: _sectionItemCount(official, recent),
      itemBuilder: (context, index) {
        return _buildSectionItem(
          index, official, recent,
          isDark, textColor, subTextColor, accentColor,
          hoverColor, dividerColor,
        );
      },
    );
  }

  int _sectionItemCount(List<_LangEntry> official, List<_LangEntry> recent) {
    int count = 0;
    if (recent.isNotEmpty) count += 1 + recent.length; // header + rows
    if (official.isNotEmpty) {
      if (recent.isNotEmpty) count += 1; // BoxContentDivider
      count += 1 + official.length; // header + rows
    }
    return count;
  }

  Widget _buildSectionItem(
    int index,
    List<_LangEntry> official,
    List<_LangEntry> recent,
    bool isDark,
    Color textColor,
    Color subTextColor,
    Color accentColor,
    Color hoverColor,
    Color dividerColor,
  ) {
    int offset = 0;

    if (recent.isNotEmpty) {
      if (index == offset) return _sectionHeader('Recent', isDark);
      offset++;
      if (index < offset + recent.length) {
        return _languageRow(recent[index - offset], isDark, textColor, subTextColor, accentColor, hoverColor);
      }
      offset += recent.length;

      if (official.isNotEmpty) {
        if (index == offset) {
          // §19.15: BoxContentDivider between Recent and Official sections.
          return Container(height: 7, color: dividerColor);
        }
        offset++;
      }
    }

    if (official.isNotEmpty) {
      if (index == offset) return _sectionHeader('Official', isDark);
      offset++;
      if (index < offset + official.length) {
        return _languageRow(official[index - offset], isDark, textColor, subTextColor, accentColor, hoverColor);
      }
    }

    return const SizedBox.shrink();
  }

  Widget _sectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3),
        ),
      ),
    );
  }

  Widget _languageRow(
    _LangEntry lang,
    bool isDark,
    Color textColor,
    Color subTextColor,
    Color accentColor,
    Color hoverColor,
  ) {
    final selected = _selectedCode == lang.langCode;
    final appState = context.watch<AppState>();
    final isRemoved = appState.removedLanguageCodes.contains(lang.langCode);
    final dimOpacity = isRemoved ? 0.4 : 1.0;
    final showMenu = !lang.official;

    return Opacity(
      opacity: dimOpacity,
      child: InkWell(
        onTap: () => _selectLanguage(lang.langCode),
        hoverColor: hoverColor,
        child: Padding(
          // §19.16: passportRowPadding = 22/8/25/8 (left/top/right/bottom)
          padding: const EdgeInsets.fromLTRB(22, 8, 25, 8),
          child: Row(
            children: [
              // §19.16: langsRadio 22px diameter
              _LangsRadio(selected: selected, accentColor: accentColor, subTextColor: subTextColor),
              // Gap: 66px left offset - 22px padding - 22px radio = 22px
              const SizedBox(width: 22),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // §19.16: Title = native name, semiboldTextStyle, windowFg
                    Text(
                      lang.nativeName.isNotEmpty ? lang.nativeName : lang.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // §19.16.1: passportRowSkip ≈ 4px
                    const SizedBox(height: 4),
                    // §19.16: Description = English name, defaultTextStyle, windowSubTextFg
                    Text(
                      lang.name,
                      style: TextStyle(
                        fontSize: 13,
                        color: subTextColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // §19.16: 3-dot menu toggle (non-official rows only)
              if (showMenu)
                _LangMenuToggle(
                  lang: lang,
                  isDark: isDark,
                  subTextColor: subTextColor,
                  isRemoved: isRemoved,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// §19.16: Radio button — 22px diameter, outer ring + inner dot when selected.
class _LangsRadio extends StatelessWidget {
  final bool selected;
  final Color accentColor;
  final Color subTextColor;

  const _LangsRadio({
    required this.selected,
    required this.accentColor,
    required this.subTextColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(
        painter: _RadioPainter(
          selected: selected,
          activeColor: accentColor,
          inactiveColor: subTextColor,
        ),
      ),
    );
  }
}

class _RadioPainter extends CustomPainter {
  final bool selected;
  final Color activeColor;
  final Color inactiveColor;

  _RadioPainter({
    required this.selected,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final paint = Paint()..style = PaintingStyle.stroke;

    if (selected) {
      paint
        ..color = activeColor
        ..strokeWidth = 2;
      canvas.drawCircle(center, radius - 1, paint);
      final dotPaint = Paint()
        ..color = activeColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, 5, dotPaint);
    } else {
      paint
        ..color = inactiveColor
        ..strokeWidth = 2;
      canvas.drawCircle(center, radius - 1, paint);
    }
  }

  @override
  bool shouldRepaint(_RadioPainter old) =>
      selected != old.selected ||
      activeColor != old.activeColor ||
      inactiveColor != old.inactiveColor;
}

// §19.16 + §19.17: 3-dot menu toggle with context menu (non-official rows only).
class _LangMenuToggle extends StatelessWidget {
  final _LangEntry lang;
  final bool isDark;
  final Color subTextColor;
  final bool isRemoved;

  const _LangMenuToggle({
    required this.lang,
    required this.isDark,
    required this.subTextColor,
    required this.isRemoved,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 34,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 18,
        icon: Icon(Icons.more_vert, color: subTextColor),
        onPressed: () => _showLangContextMenu(context),
      ),
    );
  }

  void _showLangContextMenu(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox;
    final pos = box.localToGlobal(Offset(box.size.width, box.size.height / 2));
    final appState = context.read<AppState>();

    final items = <TelegramMenuItem<String>>[
      TelegramMenuItem(
        value: 'share',
        icon: const Icon(Icons.share, size: 18),
        label: 'Share',
      ),
      if (isRemoved)
        TelegramMenuItem(
          value: 'restore',
          icon: const Icon(Icons.restore, size: 18),
          label: 'Restore',
        )
      else
        TelegramMenuItem(
          value: 'delete',
          icon: const Icon(Icons.delete_outline, size: 18),
          label: 'Delete',
          isAttention: true,
        ),
    ];

    final result = await showTelegramMenu<String>(
      context: context,
      position: pos,
      items: items,
    );

    if (result == null || !context.mounted) return;

    switch (result) {
      case 'share':
        final link = 'https://t.me/setlanguage/${lang.langCode}';
        await Clipboard.setData(ClipboardData(text: link));
        if (context.mounted) {
          showTelegramToast(context, 'Language link copied to clipboard.');
        }
      case 'delete':
        appState.addRemovedLanguage(lang.langCode);
      case 'restore':
        appState.restoreRemovedLanguage(lang.langCode);
    }
  }
}

// §19.14: Toggle row used for "Show Translate Button" and "Translate Entire Chats"
class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final bool isDark;
  final Color textColor;
  final Color hoverColor;
  final bool locked;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.value,
    required this.isDark,
    required this.textColor,
    required this.hoverColor,
    required this.onChanged,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final subTextColor = isDark ? const Color(0xFF7B8D9D) : const Color(0xFF999999);
    return InkWell(
      onTap: () => onChanged(!value),
      hoverColor: hoverColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 8, 16, 8),
        child: Row(
          children: [
            if (locked) ...[
              Icon(Icons.lock_outline, size: 16, color: subTextColor),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 14, color: textColor),
              ),
            ),
            SizedBox(
              height: 20,
              width: 36,
              child: Switch(
                value: value,
                onChanged: onChanged,
                activeColor: accentColor,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// §19.14.2: Skip-languages editor (checkbox multi-select)
class _SkipLanguagesEditor extends StatefulWidget {
  final List<_LangEntry> allLanguages;

  const _SkipLanguagesEditor({required this.allLanguages});

  @override
  State<_SkipLanguagesEditor> createState() => _SkipLanguagesEditorState();
}

class _SkipLanguagesEditorState extends State<_SkipLanguagesEditor> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _selected = Set<String>.from(appState.skipTranslationLanguages);
  }

  void _toggle(String langCode) {
    setState(() {
      if (_selected.contains(langCode)) {
        if (_selected.length <= 1) {
          showTelegramToast(context, 'You must keep at least one language.');
          return;
        }
        _selected.remove(langCode);
      } else {
        _selected.add(langCode);
      }
    });
    context.read<AppState>().setSkipTranslationLanguages(_selected.toList());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E2C3A) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subTextColor = isDark ? const Color(0xFF7B8D9D) : const Color(0xFF999999);
    final accentColor = isDark ? const Color(0xFF5288C1) : const Color(0xFF40A7E3);
    final hoverColor = isDark ? const Color(0xFF202B36) : const Color(0xFFF1F1F1);

    final screenHeight = MediaQuery.of(context).size.height;
    final maxDialogHeight = screenHeight - 48;

    final langs = widget.allLanguages.isNotEmpty
        ? widget.allLanguages
        : _selected.map((c) => _LangEntry(
            langCode: c,
            name: c.toUpperCase(),
            nativeName: c.toUpperCase(),
            official: true,
            rtl: false,
            beta: false,
          )).toList();

    return Dialog(
      backgroundColor: bgColor,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 320, maxHeight: maxDialogHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
              child: Text(
                'Do Not Translate',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: langs.length,
                itemBuilder: (context, index) {
                  final lang = langs[index];
                  final checked = _selected.contains(lang.langCode);
                  return InkWell(
                    onTap: () => _toggle(lang.langCode),
                    hoverColor: hoverColor,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: Checkbox(
                              value: checked,
                              onChanged: (_) => _toggle(lang.langCode),
                              activeColor: accentColor,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          const SizedBox(width: 22),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  lang.nativeName.isNotEmpty
                                      ? lang.nativeName
                                      : lang.name,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: textColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  lang.name,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: subTextColor,
                                  ),
                                  maxLines: 1,
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
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Close', style: TextStyle(color: accentColor)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LangEntry {
  final String langCode;
  final String name;
  final String nativeName;
  final bool official;
  final bool rtl;
  final bool beta;

  const _LangEntry({
    required this.langCode,
    required this.name,
    required this.nativeName,
    required this.official,
    required this.rtl,
    required this.beta,
  });
}

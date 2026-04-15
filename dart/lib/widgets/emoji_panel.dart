import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Panel tab types.
enum _PanelTab { emoji, stickers, gifs }

/// Emoji/Sticker/GIF picker panel that slides open from the chat input area.
///
/// Displays a searchable grid of emojis organized by category,
/// with a recently-used section at the top (session-only, not persisted).
/// Also includes placeholder Stickers and GIFs tabs.
class EmojiPanel extends StatefulWidget {
  /// Called when the user taps an emoji, sticker, or GIF.
  final void Function(String emoji) onEmojiSelected;

  /// Called when the user wants to close the panel.
  final VoidCallback onClose;

  const EmojiPanel({
    super.key,
    required this.onEmojiSelected,
    required this.onClose,
  });

  @override
  State<EmojiPanel> createState() => _EmojiPanelState();
}

class _EmojiPanelState extends State<EmojiPanel> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _gifSearchController = TextEditingController();
  int _activeCategoryIndex = 0;
  String _searchQuery = '';
  _PanelTab _activeTab = _PanelTab.emoji;
  int _selectedSkinTone = 0; // 0 = default/yellow, 1-5 = Fitzpatrick modifiers
  int _selectedStickerPack = 0;

  /// Fitzpatrick skin tone modifier code points (indices 1–5).
  static const _skinToneModifiers = [
    '\u{1F3FB}', // light
    '\u{1F3FC}', // medium-light
    '\u{1F3FD}', // medium
    '\u{1F3FE}', // medium-dark
    '\u{1F3FF}', // dark
  ];

  /// Colors for the six skin tone circles (index 0 = default yellow).
  static const _skinToneColors = [
    Color(0xFFFFCC4D),
    Color(0xFFF7DECE),
    Color(0xFFF0C8A0),
    Color(0xFFD5A06E),
    Color(0xFFA56B43),
    Color(0xFF5C4033),
  ];

  /// Session-only recently used emojis (max 24).
  static final List<String> _recentEmojis = [];

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _gifSearchController.dispose();
    super.dispose();
  }

  void _onEmojiTap(String emoji) {
    // Update recents.
    _recentEmojis.remove(emoji);
    _recentEmojis.insert(0, emoji);
    if (_recentEmojis.length > 24) {
      _recentEmojis.removeLast();
    }
    widget.onEmojiSelected(emoji);
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
    });
  }

  void _onCategoryTap(int index) {
    setState(() {
      _activeCategoryIndex = index;
      _searchQuery = '';
      _searchController.clear();
    });
    _scrollController.jumpTo(0);
  }

  void _onTabChanged(_PanelTab tab) {
    setState(() {
      _activeTab = tab;
      _searchQuery = '';
      _searchController.clear();
    });
  }

  List<String> _filteredEmojis() {
    if (_searchQuery.isEmpty) {
      return _emojiCategories[_activeCategoryIndex].emojis;
    }
    final results = <String>[];
    for (final category in _emojiCategories) {
      for (final emoji in category.emojis) {
        final keyword = _emojiKeywords[emoji];
        if (keyword != null && keyword.contains(_searchQuery)) {
          results.add(emoji);
        } else if (emoji.contains(_searchQuery)) {
          results.add(emoji);
        }
      }
    }
    return results;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: AppSizes.emojiPanelWidth,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        border: Border(
          left: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
      ),
      child: Column(
        children: [
          // Header with close button.
          _buildHeader(isDark),

          // Top-level tab bar: Emoji / Stickers / GIFs.
          _buildTopTabs(isDark),

          // Tab content.
          Expanded(
            child: switch (_activeTab) {
              _PanelTab.emoji => _buildEmojiContent(isDark),
              _PanelTab.stickers => _buildStickersContent(isDark),
              _PanelTab.gifs => _buildGifsContent(isDark),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Text(
            switch (_activeTab) {
              _PanelTab.emoji => 'Emoji',
              _PanelTab.stickers => 'Stickers',
              _PanelTab.gifs => 'GIFs',
            },
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.darkText : AppColors.lightText,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 28,
            height: 28,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 18,
              icon: Icon(
                Icons.close,
                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
              ),
              onPressed: widget.onClose,
              splashRadius: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopTabs(bool isDark) {
    Widget tabItem(String label, String icon, _PanelTab tab) {
      final isActive = _activeTab == tab;
      return Expanded(
        child: GestureDetector(
          onTap: () => _onTabChanged(tab),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isActive ? AppColors.accent : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(icon, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    color: isActive
                        ? AppColors.accent
                        : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
      ),
      child: Row(
        children: [
          tabItem('Emoji', '\u{1F600}', _PanelTab.emoji),
          tabItem('Stickers', '\u{1F3AD}', _PanelTab.stickers),
          tabItem('GIFs', '\u{1F3AC}', _PanelTab.gifs),
        ],
      ),
    );
  }

  // ── Emoji tab content ──

  Widget _buildEmojiContent(bool isDark) {
    final filtered = _filteredEmojis();
    final showRecents = _searchQuery.isEmpty && _recentEmojis.isNotEmpty;

    return Column(
      children: [
        // Search bar.
        _buildSearchBar(isDark),

        // Skin tone selector.
        _buildSkinToneSelector(),

        // Category tabs.
        _buildCategoryTabs(isDark),

        // Emoji grid.
        Expanded(
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            children: [
              // Recently used section.
              if (showRecents) ...[
                _buildSectionLabel('Recently Used', isDark),
                _buildEmojiGrid(_recentEmojis),
                const SizedBox(height: 8),
              ],

              // Category label (only when not searching).
              if (_searchQuery.isEmpty)
                _buildSectionLabel(
                  _emojiCategories[_activeCategoryIndex].name,
                  isDark,
                ),

              if (_searchQuery.isNotEmpty && filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'No emojis found',
                      style: TextStyle(
                        color: isDark
                            ? AppColors.darkTextMuted
                            : AppColors.lightTextMuted,
                        fontSize: 13,
                      ),
                    ),
                  ),
                )
              else
                _buildEmojiGrid(filtered),
            ],
          ),
        ),
      ],
    );
  }

  // ── Stickers tab content ──

  /// Mock sticker pack definitions: (label, icon, item count, thumbnail emoji,
  /// list of (emoji, bg color) for each sticker slot).
  static final _stickerPacks = [
    (
      label: 'Favorites',
      icon: Icons.star_rounded,
      thumbnail: '⭐',
      stickers: [
        ('⭐', const Color(0xFFFFF9C4)),
        ('💖', const Color(0xFFFFCDD2)),
        ('✨', const Color(0xFFFFF3E0)),
        ('🌟', const Color(0xFFFFF9C4)),
        ('💫', const Color(0xFFE3F2FD)),
        ('🎉', const Color(0xFFF3E5F5)),
        ('🏆', const Color(0xFFFFF9C4)),
        ('🎁', const Color(0xFFE8F5E9)),
      ],
    ),
    (
      label: 'Animals',
      icon: Icons.pets_rounded,
      thumbnail: '🐾',
      stickers: [
        ('🐶', const Color(0xFFFFECB3)),
        ('🐱', const Color(0xFFF8BBD0)),
        ('🐼', const Color(0xFFEEEEEE)),
        ('🦊', const Color(0xFFFFCCBC)),
        ('🐸', const Color(0xFFC8E6C9)),
        ('🐧', const Color(0xFFB3E5FC)),
        ('🦁', const Color(0xFFFFE0B2)),
        ('🐻', const Color(0xFFD7CCC8)),
        ('🦋', const Color(0xFFE1BEE7)),
        ('🐙', const Color(0xFFFFCDD2)),
        ('🦄', Color(0xFFE040FB).withValues(alpha: 0.2)),
        ('🐬', const Color(0xFFB3E5FC)),
      ],
    ),
    (
      label: 'Expressions',
      icon: Icons.sentiment_very_satisfied_rounded,
      thumbnail: '😄',
      stickers: [
        ('😄', const Color(0xFFFFF9C4)),
        ('😂', const Color(0xFFFFF9C4)),
        ('🥹', const Color(0xFFE3F2FD)),
        ('😍', const Color(0xFFFFCDD2)),
        ('🤩', const Color(0xFFFFF9C4)),
        ('😎', const Color(0xFFE3F2FD)),
        ('🥳', const Color(0xFFF3E5F5)),
        ('😤', const Color(0xFFFFCCBC)),
        ('😭', const Color(0xFFE3F2FD)),
        ('🤔', const Color(0xFFFFF9C4)),
      ],
    ),
    (
      label: 'Memes',
      icon: Icons.local_fire_department_rounded,
      thumbnail: '🔥',
      stickers: [
        ('🔥', const Color(0xFFFFCCBC)),
        ('💀', const Color(0xFFEEEEEE)),
        ('🗿', const Color(0xFFD7CCC8)),
        ('👀', const Color(0xFFE3F2FD)),
        ('🫡', const Color(0xFFE8F5E9)),
        ('😳', const Color(0xFFFFCDD2)),
        ('🤡', const Color(0xFFF3E5F5)),
        ('🦆', const Color(0xFFFFF9C4)),
      ],
    ),
  ];

  Widget _buildStickersContent(bool isDark) {
    final pack = _stickerPacks[_selectedStickerPack];
    final stickers = pack.stickers;

    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final activeBg = AppColors.accent.withValues(alpha: 0.15);
    const activeIndicator = AppColors.accent;
    final tabBg = isDark ? AppColors.darkSurface : AppColors.lightSurface;

    return Column(
      children: [
        // ── Pack tabs row ──
        Container(
          height: 52,
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
            border: Border(
              bottom: BorderSide(color: borderColor),
            ),
          ),
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            itemCount: _stickerPacks.length,
            itemBuilder: (context, packIndex) {
              final p = _stickerPacks[packIndex];
              final isActive = packIndex == _selectedStickerPack;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedStickerPack = packIndex),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: isActive ? activeBg : tabBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border(
                        bottom: BorderSide(
                          color: isActive ? activeIndicator : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                    child: Tooltip(
                      message: p.label,
                      preferBelow: true,
                      waitDuration: const Duration(milliseconds: 400),
                      child: Center(
                        child: Icon(
                          p.icon,
                          size: 20,
                          color: isActive
                              ? activeIndicator
                              : (isDark
                                  ? AppColors.darkTextDim
                                  : AppColors.lightTextDim),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // ── Pack label ──
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(
            children: [
              Icon(pack.icon, size: 14, color: AppColors.accent),
              const SizedBox(width: 6),
              Text(
                pack.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${stickers.length}',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? AppColors.darkTextMuted
                      : AppColors.lightTextMuted,
                ),
              ),
            ],
          ),
        ),

        // ── Sticker grid ──
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 1,
            ),
            itemCount: stickers.length,
            itemBuilder: (context, index) {
              final (emoji, bgColor) = stickers[index];
              return Tooltip(
                message: '${pack.label} sticker ${index + 1}',
                preferBelow: false,
                waitDuration: const Duration(milliseconds: 300),
                child: GestureDetector(
                  onTap: () => widget.onEmojiSelected(emoji),
                  child: Container(
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: borderColor),
                    ),
                    child: Center(
                      child: Text(
                        emoji,
                        style: const TextStyle(fontSize: 28),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── GIFs tab content ──

  Widget _buildGifsContent(bool isDark) {
    // Deterministic pseudo-random heights for masonry-like effect.
    final rng = Random(42);
    final heights = List.generate(8, (_) => 80.0 + rng.nextInt(60));

    final placeholderColors = [
      AppColors.accent.withValues(alpha: 0.25),
      AppColors.online.withValues(alpha: 0.25),
      AppColors.warning.withValues(alpha: 0.25),
      AppColors.danger.withValues(alpha: 0.25),
      AppColors.accentLight.withValues(alpha: 0.25),
      AppColors.accentDark.withValues(alpha: 0.25),
    ];

    return Column(
      children: [
        // GIF search bar.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: SizedBox(
            height: 36,
            child: TextField(
              controller: _gifSearchController,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? AppColors.darkText : AppColors.lightText,
              ),
              decoration: InputDecoration(
                hintText: 'Search GIFs...',
                prefixIcon: Icon(
                  Icons.search,
                  size: 18,
                  color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                filled: true,
                fillColor: isDark ? AppColors.darkBase : AppColors.lightBase,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
                ),
              ),
            ),
          ),
        ),

        // GIF grid.
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            children: [
              // 2-column layout with varying heights.
              for (int i = 0; i < heights.length; i += 2)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Tooltip(
                          message: 'GIF ${i + 1}',
                          preferBelow: false,
                          waitDuration: const Duration(milliseconds: 300),
                          child: GestureDetector(
                            onTap: () => widget.onEmojiSelected('[gif]'),
                            child: Container(
                              height: heights[i],
                              decoration: BoxDecoration(
                                color: placeholderColors[i % placeholderColors.length],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  'GIF',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? AppColors.darkTextMuted
                                        : AppColors.lightTextMuted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (i + 1 < heights.length)
                        Expanded(
                          child: Tooltip(
                            message: 'GIF ${i + 2}',
                            preferBelow: false,
                            waitDuration: const Duration(milliseconds: 300),
                            child: GestureDetector(
                              onTap: () => widget.onEmojiSelected('[gif]'),
                              child: Container(
                                height: heights[i + 1],
                                decoration: BoxDecoration(
                                  color: placeholderColors[(i + 1) % placeholderColors.length],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    'GIF',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? AppColors.darkTextMuted
                                          : AppColors.lightTextMuted,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        const Expanded(child: SizedBox()),
                    ],
                  ),
                ),

              const SizedBox(height: 12),

              // Coming soon notice.
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkSurfaceAlt
                      : AppColors.lightSurfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'GIF search coming soon',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Shared builders ──

  Widget _buildSearchBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SizedBox(
        height: 36,
        child: TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? AppColors.darkText : AppColors.lightText,
          ),
          decoration: InputDecoration(
            hintText: 'Search emoji',
            prefixIcon: Icon(
              Icons.search,
              size: 18,
              color: isDark ? AppColors.darkTextDim : AppColors.lightTextDim,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
            filled: true,
            fillColor: isDark ? AppColors.darkBase : AppColors.lightBase,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryTabs(bool isDark) {
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: _emojiCategories.length,
        itemBuilder: (context, index) {
          final cat = _emojiCategories[index];
          final isActive = index == _activeCategoryIndex && _searchQuery.isEmpty;
          return GestureDetector(
            onTap: () => _onCategoryTap(index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isActive ? AppColors.accent : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Center(
                child: Text(
                  cat.icon,
                  style: TextStyle(
                    fontSize: 18,
                    color: isActive
                        ? null
                        : (isDark ? AppColors.darkTextDim : AppColors.lightTextDim),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Returns true if [emoji] is in a category that supports skin tone modifiers.
  bool _supportsSkinTone(String emoji) => _skinToneEligible.contains(emoji);

  /// Returns [emoji] with the active skin tone modifier appended, or [emoji]
  /// unchanged when the default tone (0) is selected or the emoji doesn't
  /// support modifiers.
  String _applyTone(String emoji) {
    if (_selectedSkinTone == 0 || !_supportsSkinTone(emoji)) return emoji;
    return emoji + _skinToneModifiers[_selectedSkinTone - 1];
  }

  Widget _buildSkinToneSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: List.generate(6, (index) {
          final isSelected = _selectedSkinTone == index;
          return GestureDetector(
            onTap: () => setState(() => _selectedSkinTone = index),
            child: Container(
              width: 20,
              height: 20,
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                color: _skinToneColors[index],
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? AppColors.accent
                      : Colors.black.withValues(alpha: 0.18),
                  width: isSelected ? 2 : 1,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildSectionLabel(String label, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 4, bottom: 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
        ),
      ),
    );
  }

  Widget _buildEmojiGrid(List<String> emojis) {
    return Wrap(
      children: emojis.map((emoji) {
        final display = _applyTone(emoji);
        return GestureDetector(
          onTap: () => _onEmojiTap(display),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Center(
              child: Text(display, style: const TextStyle(fontSize: 22)),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Emoji data
// ---------------------------------------------------------------------------

class _EmojiCategory {
  final String name;
  final String icon;
  final List<String> emojis;
  const _EmojiCategory(this.name, this.icon, this.emojis);
}

const _emojiCategories = <_EmojiCategory>[
  _EmojiCategory('Smileys', '\u{1F600}', [
    '\u{1F600}', '\u{1F603}', '\u{1F604}', '\u{1F601}', '\u{1F606}',
    '\u{1F605}', '\u{1F923}', '\u{1F602}', '\u{1F642}', '\u{1F643}',
    '\u{1F609}', '\u{1F60A}', '\u{1F607}', '\u{1F970}', '\u{1F60D}',
    '\u{1F929}', '\u{1F618}', '\u{1F617}', '\u{1F61A}', '\u{1F619}',
    '\u{1F972}', '\u{1F60B}', '\u{1F61B}', '\u{1F61C}', '\u{1F92A}',
    '\u{1F61D}', '\u{1F911}', '\u{1F917}', '\u{1F92D}', '\u{1F92B}',
    '\u{1F914}', '\u{1FAE1}', '\u{1F910}', '\u{1FAE0}', '\u{1F610}',
    '\u{1F611}', '\u{1F636}', '\u{1FAE5}', '\u{1F60F}', '\u{1F612}',
    '\u{1F644}', '\u{1F62C}', '\u{1F925}', '\u{1FAE8}', '\u{1F60C}',
    '\u{1F614}', '\u{1F62A}', '\u{1F924}', '\u{1F634}', '\u{1F637}',
    '\u{1F912}', '\u{1F915}', '\u{1F922}', '\u{1F92E}', '\u{1F927}',
    '\u{1F975}', '\u{1F976}', '\u{1F974}', '\u{1F635}', '\u{1F4AB}',
    '\u{1F92F}', '\u{1F920}', '\u{1F973}', '\u{1F978}', '\u{1F60E}',
    '\u{1F913}', '\u{1F9D0}', '\u{1F615}', '\u{1FAE4}', '\u{1F61F}',
    '\u{1F641}', '\u{2639}\u{FE0F}', '\u{1F62E}', '\u{1F62F}', '\u{1F632}',
    '\u{1F633}', '\u{1F97A}', '\u{1F979}', '\u{1F626}', '\u{1F627}',
    '\u{1F628}', '\u{1F630}', '\u{1F625}', '\u{1F622}', '\u{1F62D}',
    '\u{1F631}', '\u{1F616}', '\u{1F623}', '\u{1F61E}', '\u{1F613}',
    '\u{1F629}', '\u{1F62B}', '\u{1F971}', '\u{1F624}', '\u{1F621}',
    '\u{1F620}', '\u{1F92C}',
  ]),
  _EmojiCategory('People', '\u{1F44B}', [
    '\u{1F44B}', '\u{1F91A}', '\u{1F590}\u{FE0F}', '\u{270B}', '\u{1F596}',
    '\u{1F44C}', '\u{1F90C}', '\u{1F90F}', '\u{270C}\u{FE0F}', '\u{1F91E}',
    '\u{1FAF0}', '\u{1F91F}', '\u{1F918}', '\u{1F919}', '\u{1F448}',
    '\u{1F449}', '\u{1F446}', '\u{1F595}', '\u{1F447}', '\u{261D}\u{FE0F}',
    '\u{1FAF5}', '\u{1F44D}', '\u{1F44E}', '\u{270A}', '\u{1F44A}',
    '\u{1F91B}', '\u{1F91C}', '\u{1F44F}', '\u{1F64C}', '\u{1FAF6}',
    '\u{1F450}', '\u{1F932}', '\u{1F91D}', '\u{1F64F}', '\u{1F4AA}',
    '\u{1F9BE}', '\u{1F9BF}', '\u{1F9B5}', '\u{1F9B6}', '\u{1F442}',
    '\u{1F9BB}', '\u{1F443}', '\u{1F9E0}', '\u{1FAC0}', '\u{1FAC1}',
    '\u{1F9B7}', '\u{1F9B4}', '\u{1F440}', '\u{1F441}\u{FE0F}', '\u{1F445}',
    '\u{1F444}',
  ]),
  _EmojiCategory('Animals', '\u{1F436}', [
    '\u{1F436}', '\u{1F431}', '\u{1F42D}', '\u{1F439}', '\u{1F430}',
    '\u{1F98A}', '\u{1F43B}', '\u{1F43C}', '\u{1F428}', '\u{1F42F}',
    '\u{1F981}', '\u{1F42E}', '\u{1F437}', '\u{1F438}', '\u{1F435}',
    '\u{1F648}', '\u{1F649}', '\u{1F64A}', '\u{1F412}', '\u{1F414}',
    '\u{1F427}', '\u{1F426}', '\u{1F424}', '\u{1F423}', '\u{1F425}',
    '\u{1F986}', '\u{1F985}', '\u{1F989}', '\u{1F987}', '\u{1F43A}',
    '\u{1F417}', '\u{1F434}', '\u{1F984}', '\u{1F41D}', '\u{1FAB1}',
    '\u{1F41B}', '\u{1F98B}', '\u{1F40C}', '\u{1F41E}', '\u{1F41C}',
    '\u{1FAB0}', '\u{1FAB2}', '\u{1FAB3}', '\u{1F99F}', '\u{1F997}',
    '\u{1F577}\u{FE0F}', '\u{1F982}', '\u{1F422}', '\u{1F40D}', '\u{1F98E}',
    '\u{1F996}', '\u{1F995}', '\u{1F419}', '\u{1F991}', '\u{1F990}',
    '\u{1F99E}', '\u{1F980}', '\u{1F421}', '\u{1F420}', '\u{1F41F}',
    '\u{1F42C}', '\u{1F433}', '\u{1F40B}', '\u{1F988}', '\u{1F9AD}',
    '\u{1F40A}', '\u{1F405}', '\u{1F406}', '\u{1F993}', '\u{1F98D}',
    '\u{1F9A7}', '\u{1F418}', '\u{1F99B}', '\u{1F98F}', '\u{1F42A}',
    '\u{1F42B}', '\u{1F992}', '\u{1F998}', '\u{1F9AC}',
  ]),
  _EmojiCategory('Food', '\u{1F354}', [
    '\u{1F34E}', '\u{1F34F}', '\u{1F350}', '\u{1F34A}', '\u{1F34B}',
    '\u{1F34C}', '\u{1F349}', '\u{1F347}', '\u{1F353}', '\u{1FAD0}',
    '\u{1F348}', '\u{1F352}', '\u{1F351}', '\u{1F96D}', '\u{1F34D}',
    '\u{1F965}', '\u{1F95D}', '\u{1F345}', '\u{1F346}', '\u{1F951}',
    '\u{1F966}', '\u{1F96C}', '\u{1F952}', '\u{1F336}\u{FE0F}', '\u{1FAD1}',
    '\u{1F33D}', '\u{1F955}', '\u{1F9C4}', '\u{1F9C5}', '\u{1F954}',
    '\u{1F360}', '\u{1F950}', '\u{1F35E}', '\u{1F956}', '\u{1FAD3}',
    '\u{1F968}', '\u{1F96F}', '\u{1F9C0}', '\u{1F356}', '\u{1F357}',
    '\u{1F969}', '\u{1F953}', '\u{1F354}', '\u{1F35F}', '\u{1F355}',
    '\u{1F32D}', '\u{1F96A}', '\u{1F32E}', '\u{1F32F}', '\u{1FAD4}',
    '\u{1F959}', '\u{1F9C6}', '\u{1F95A}', '\u{1F373}', '\u{1F958}',
    '\u{1F372}', '\u{1FAD5}', '\u{1F963}', '\u{1F957}', '\u{1F37F}',
    '\u{1F9C8}', '\u{1F9C2}', '\u{1F96B}',
  ]),
  _EmojiCategory('Travel', '\u{1F697}', [
    '\u{1F697}', '\u{1F695}', '\u{1F699}', '\u{1F68C}', '\u{1F68E}',
    '\u{1F3CE}\u{FE0F}', '\u{1F693}', '\u{1F691}', '\u{1F692}', '\u{1F690}',
    '\u{1F69A}', '\u{1F69B}', '\u{1F69C}', '\u{1F6F5}', '\u{1F3CD}\u{FE0F}',
    '\u{1F6B2}', '\u{1F6F4}', '\u{1F6F9}', '\u{1F6FC}', '\u{1F6A8}',
    '\u{2708}\u{FE0F}', '\u{1F680}', '\u{1F6F8}', '\u{1F681}', '\u{1F6A2}',
    '\u{26F5}', '\u{1F6A4}', '\u{1F6F3}\u{FE0F}', '\u{1F682}', '\u{1F683}',
    '\u{1F684}', '\u{1F685}', '\u{1F687}', '\u{1F689}', '\u{1F3E0}',
    '\u{1F3D7}\u{FE0F}', '\u{1F3D8}\u{FE0F}', '\u{1F3D9}\u{FE0F}', '\u{1F3DB}\u{FE0F}', '\u{1F3DF}\u{FE0F}',
    '\u{26FA}', '\u{1F3D6}\u{FE0F}', '\u{1F3DD}\u{FE0F}', '\u{1F305}', '\u{1F304}',
    '\u{1F307}', '\u{1F306}', '\u{1F3DE}\u{FE0F}', '\u{1F30B}', '\u{1F3F0}',
  ]),
  _EmojiCategory('Activities', '\u{26BD}', [
    '\u{26BD}', '\u{1F3C0}', '\u{1F3C8}', '\u{26BE}', '\u{1F94E}',
    '\u{1F3BE}', '\u{1F3D0}', '\u{1F3C9}', '\u{1F94F}', '\u{1FA83}',
    '\u{1F3B1}', '\u{1F3D3}', '\u{1F3F8}', '\u{1F3D2}', '\u{1F3D1}',
    '\u{1F94D}', '\u{1F3CF}', '\u{1F945}', '\u{26F3}', '\u{1FA81}',
    '\u{1F3A3}', '\u{1F93F}', '\u{1F3BD}', '\u{1F3BF}', '\u{1F6F7}',
    '\u{1F94C}', '\u{1F3AF}', '\u{1FA80}', '\u{1FA84}', '\u{1F3AE}',
    '\u{1F579}\u{FE0F}', '\u{1F3B2}', '\u{1F9E9}', '\u{1F3AD}', '\u{1F3A8}',
    '\u{1F3B5}', '\u{1F3B6}', '\u{1F3A4}', '\u{1F3A7}', '\u{1F3B9}',
    '\u{1F3B7}', '\u{1FA95}', '\u{1F3B8}', '\u{1F3BB}', '\u{1FA98}',
    '\u{1F941}',
  ]),
  _EmojiCategory('Objects', '\u{1F4A1}', [
    '\u{1F4A1}', '\u{1F526}', '\u{1F3EE}', '\u{1FA94}', '\u{1F4D4}',
    '\u{1F4D5}', '\u{1F4D6}', '\u{1F4D7}', '\u{1F4D8}', '\u{1F4D9}',
    '\u{1F4DA}', '\u{1F4D3}', '\u{1F4D2}', '\u{1F4C3}', '\u{1F4DC}',
    '\u{1F4C4}', '\u{1F4F0}', '\u{1F4F1}', '\u{1F4F2}', '\u{260E}\u{FE0F}',
    '\u{1F4BB}', '\u{1F5A5}\u{FE0F}', '\u{1F5A8}\u{FE0F}', '\u{2328}\u{FE0F}', '\u{1F5B1}\u{FE0F}',
    '\u{1F4BD}', '\u{1F4BE}', '\u{1F4BF}', '\u{1F4C0}', '\u{1F3A5}',
    '\u{1F4F7}', '\u{1F4F8}', '\u{1F4F9}', '\u{1F4FA}', '\u{1F4FB}',
    '\u{1F50A}', '\u{1F509}', '\u{1F508}', '\u{1F507}', '\u{1F514}',
    '\u{1F515}', '\u{1F4E7}', '\u{2709}\u{FE0F}', '\u{1F4E8}', '\u{1F4E9}',
    '\u{1F4E6}', '\u{1F4EE}', '\u{1F5F3}\u{FE0F}', '\u{270F}\u{FE0F}', '\u{1F58A}\u{FE0F}',
    '\u{1F58B}\u{FE0F}', '\u{1F58C}\u{FE0F}', '\u{1F58D}\u{FE0F}', '\u{1F4DD}', '\u{1F4BC}',
    '\u{1F4C1}', '\u{1F4C2}', '\u{1F5C2}\u{FE0F}', '\u{1F4C5}', '\u{1F4C6}',
    '\u{1F4CB}', '\u{1F4CC}', '\u{1F4CE}', '\u{1F587}\u{FE0F}', '\u{1F4CF}',
    '\u{1F4D0}', '\u{2702}\u{FE0F}', '\u{1F5D1}\u{FE0F}', '\u{1F512}', '\u{1F513}',
    '\u{1F50D}', '\u{1F50E}',
  ]),
  _EmojiCategory('Symbols', '\u{2764}\u{FE0F}', [
    '\u{2764}\u{FE0F}', '\u{1F9E1}', '\u{1F49B}', '\u{1F49A}', '\u{1F499}',
    '\u{1F49C}', '\u{1F5A4}', '\u{1F90D}', '\u{1F90E}', '\u{1F494}',
    '\u{2764}\u{FE0F}\u{200D}\u{1F525}', '\u{1F4AF}', '\u{1F4A2}', '\u{1F4A5}', '\u{1F4AB}',
    '\u{1F4A6}', '\u{1F4A8}', '\u{1F573}\u{FE0F}', '\u{1F4A3}', '\u{1F4AC}',
    '\u{1F441}\u{FE0F}\u{200D}\u{1F5E8}\u{FE0F}', '\u{1F5E8}\u{FE0F}', '\u{1F5EF}\u{FE0F}', '\u{1F4AD}', '\u{1F4A4}',
    '\u{2705}', '\u{274C}', '\u{2753}', '\u{2757}', '\u{1F4B2}',
    '\u{1F4B1}', '\u{1F534}', '\u{1F7E0}', '\u{1F7E1}', '\u{1F7E2}',
    '\u{1F535}', '\u{1F7E3}', '\u{26AB}', '\u{26AA}', '\u{1F7E4}',
    '\u{2B50}', '\u{1F31F}', '\u{1F4AB}', '\u{2728}', '\u{1F525}',
    '\u{1F4A5}', '\u{1F3B5}', '\u{1F3B6}', '\u{1F495}', '\u{1F49E}',
    '\u{1F493}', '\u{1F497}', '\u{1F496}', '\u{1F498}', '\u{1F49D}',
  ]),
  _EmojiCategory('Flags', '\u{1F3F3}\u{FE0F}', [
    '\u{1F1FA}\u{1F1F8}', '\u{1F1EC}\u{1F1E7}', '\u{1F1E9}\u{1F1EA}', '\u{1F1EB}\u{1F1F7}', '\u{1F1EE}\u{1F1F9}',
    '\u{1F1EA}\u{1F1F8}', '\u{1F1F7}\u{1F1FA}', '\u{1F1E8}\u{1F1F3}', '\u{1F1EF}\u{1F1F5}', '\u{1F1F0}\u{1F1F7}',
    '\u{1F1E7}\u{1F1F7}', '\u{1F1EE}\u{1F1F3}', '\u{1F1E6}\u{1F1FA}', '\u{1F1E8}\u{1F1E6}', '\u{1F1F2}\u{1F1FD}',
    '\u{1F1F8}\u{1F1E6}', '\u{1F1F9}\u{1F1F7}', '\u{1F1EE}\u{1F1F7}', '\u{1F1E6}\u{1F1EA}', '\u{1F1F8}\u{1F1EA}',
    '\u{1F1F3}\u{1F1F4}', '\u{1F1E8}\u{1F1ED}', '\u{1F1F3}\u{1F1F1}', '\u{1F1E7}\u{1F1EA}', '\u{1F1E6}\u{1F1F9}',
    '\u{1F1F5}\u{1F1F1}', '\u{1F1F5}\u{1F1F9}', '\u{1F1EC}\u{1F1F7}', '\u{1F1E8}\u{1F1FF}', '\u{1F1F7}\u{1F1F4}',
    '\u{1F1E8}\u{1F1F1}', '\u{1F1E8}\u{1F1F4}', '\u{1F1E6}\u{1F1F7}', '\u{1F1F5}\u{1F1EA}', '\u{1F1FB}\u{1F1EA}',
    '\u{1F1EA}\u{1F1EC}', '\u{1F1F3}\u{1F1EC}', '\u{1F1F0}\u{1F1EA}', '\u{1F1FF}\u{1F1E6}', '\u{1F1F5}\u{1F1ED}',
    '\u{1F1F9}\u{1F1ED}', '\u{1F1FB}\u{1F1F3}', '\u{1F1EE}\u{1F1E9}', '\u{1F1F2}\u{1F1FE}', '\u{1F1F8}\u{1F1EC}',
    '\u{1F1F5}\u{1F1F0}', '\u{1F1E7}\u{1F1E9}', '\u{1F1F1}\u{1F1F0}', '\u{1F1F3}\u{1F1F5}',
    '\u{1F3F3}\u{FE0F}', '\u{1F3F4}', '\u{1F3F3}\u{FE0F}\u{200D}\u{1F308}',
  ]),
];

/// Basic keyword map for search. Maps emoji to lowercase search terms.
const _emojiKeywords = <String, String>{
  // Smileys
  '\u{1F600}': 'grinning grin happy smile',
  '\u{1F603}': 'smiley happy smile open mouth',
  '\u{1F604}': 'smile happy eyes grin',
  '\u{1F601}': 'grin beaming smile eyes',
  '\u{1F606}': 'laughing laugh happy squint',
  '\u{1F605}': 'sweat smile nervous happy',
  '\u{1F923}': 'rofl rolling floor laughing lol',
  '\u{1F602}': 'joy laugh crying tears lol',
  '\u{1F642}': 'slightly smiling smile',
  '\u{1F643}': 'upside down flip smile',
  '\u{1F609}': 'wink winking face',
  '\u{1F60A}': 'blush smile happy warm',
  '\u{1F607}': 'angel halo innocent',
  '\u{1F970}': 'smiling hearts love adore',
  '\u{1F60D}': 'heart eyes love adore',
  '\u{1F929}': 'star struck excited stars',
  '\u{1F618}': 'kiss blowing heart love',
  '\u{1F617}': 'kissing face kiss',
  '\u{1F61A}': 'kissing closed eyes kiss',
  '\u{1F619}': 'kissing smiling eyes kiss',
  '\u{1F60B}': 'yum delicious tongue food',
  '\u{1F61B}': 'tongue stuck out playful',
  '\u{1F61C}': 'wink tongue crazy playful',
  '\u{1F92A}': 'zany crazy wild goofy',
  '\u{1F61D}': 'squinting tongue playful silly',
  '\u{1F911}': 'money face rich dollar',
  '\u{1F917}': 'hugging hug hands warm',
  '\u{1F92D}': 'shh covering mouth giggle',
  '\u{1F92B}': 'shh shushing quiet secret',
  '\u{1F914}': 'thinking think hmm wondering',
  '\u{1F910}': 'zipper mouth shut silent',
  '\u{1F610}': 'neutral face expressionless meh',
  '\u{1F611}': 'expressionless deadpan blank',
  '\u{1F636}': 'no mouth silent quiet',
  '\u{1F60F}': 'smirk smug sly',
  '\u{1F612}': 'unamused annoyed disappointed',
  '\u{1F644}': 'eye roll rolling eyes whatever',
  '\u{1F62C}': 'grimacing awkward cringe',
  '\u{1F925}': 'lying liar pinocchio nose',
  '\u{1F60C}': 'relieved relief calm peaceful',
  '\u{1F614}': 'pensive thoughtful sad',
  '\u{1F62A}': 'sleepy tired drowsy',
  '\u{1F924}': 'drooling drool hungry',
  '\u{1F634}': 'sleeping sleep zzz',
  '\u{1F637}': 'mask sick medical face',
  '\u{1F912}': 'thermometer sick fever ill',
  '\u{1F915}': 'bandage hurt injured',
  '\u{1F922}': 'nauseated sick nausea green',
  '\u{1F92E}': 'vomiting puke sick throw up',
  '\u{1F927}': 'sneezing sneeze sick cold',
  '\u{1F975}': 'hot sweating warm heat',
  '\u{1F976}': 'cold freezing ice frozen',
  '\u{1F974}': 'woozy dizzy drunk tipsy',
  '\u{1F635}': 'dizzy face spiral knocked out',
  '\u{1F92F}': 'exploding head mind blown shock',
  '\u{1F920}': 'cowboy hat western',
  '\u{1F973}': 'party face celebration birthday',
  '\u{1F978}': 'disguised face glasses nose',
  '\u{1F60E}': 'sunglasses cool shades',
  '\u{1F913}': 'nerd glasses geek',
  '\u{1F9D0}': 'monocle detective curious',
  '\u{1F615}': 'confused unsure uncertain',
  '\u{1F61F}': 'worried anxious concern',
  '\u{1F641}': 'slightly frowning sad',
  '\u{1F62E}': 'open mouth surprised oh',
  '\u{1F62F}': 'hushed surprised stunned',
  '\u{1F632}': 'astonished shocked amazed',
  '\u{1F633}': 'flushed embarrassed red',
  '\u{1F97A}': 'pleading puppy eyes sad',
  '\u{1F979}': 'holding back tears sad',
  '\u{1F626}': 'frowning open mouth worried',
  '\u{1F627}': 'anguished pain distress',
  '\u{1F628}': 'fearful afraid scared',
  '\u{1F630}': 'anxious sweat nervous',
  '\u{1F625}': 'sad relieved disappointed',
  '\u{1F622}': 'crying tear sad',
  '\u{1F62D}': 'sobbing crying loudly sad',
  '\u{1F631}': 'scream fear horror shocked',
  '\u{1F616}': 'confounded frustrated',
  '\u{1F623}': 'persevere struggling',
  '\u{1F61E}': 'disappointed sad unhappy',
  '\u{1F613}': 'sweat cold stress',
  '\u{1F629}': 'weary tired exhausted',
  '\u{1F62B}': 'tired face exhausted',
  '\u{1F971}': 'yawning yawn bored tired',
  '\u{1F624}': 'huffing triumph steam nose',
  '\u{1F621}': 'pouting angry mad rage',
  '\u{1F620}': 'angry mad furious',
  '\u{1F92C}': 'cursing swearing angry symbols',
  // People / hands
  '\u{1F44B}': 'wave hi hello hand',
  '\u{1F44D}': 'thumbs up like good yes',
  '\u{1F44E}': 'thumbs down dislike bad no',
  '\u{270A}': 'fist raised power',
  '\u{1F44A}': 'fist bump punch',
  '\u{1F44F}': 'clap clapping hands bravo',
  '\u{1F64C}': 'raising hands celebrate hooray',
  '\u{1F450}': 'open hands palms',
  '\u{1F64F}': 'pray please thank you hope',
  '\u{1F4AA}': 'muscle strong flex bicep',
  '\u{1F440}': 'eyes look see watching',
  '\u{1F445}': 'tongue lick taste',
  '\u{1F444}': 'lips mouth kiss',
  '\u{1F9E0}': 'brain smart think mind',
  '\u{270C}\u{FE0F}': 'victory peace sign v',
  '\u{1F596}': 'vulcan spock star trek',
  '\u{1F44C}': 'ok okay perfect fine',
  '\u{1F918}': 'rock on metal horns',
  '\u{1F919}': 'call me hand shaka',
  '\u{1F595}': 'middle finger flip off rude',
  '\u{1F91D}': 'handshake deal agreement',
  // Animals
  '\u{1F436}': 'dog puppy pet',
  '\u{1F431}': 'cat kitten pet',
  '\u{1F42D}': 'mouse rat',
  '\u{1F439}': 'hamster pet',
  '\u{1F430}': 'rabbit bunny',
  '\u{1F98A}': 'fox',
  '\u{1F43B}': 'bear grizzly',
  '\u{1F43C}': 'panda bear',
  '\u{1F428}': 'koala bear',
  '\u{1F42F}': 'tiger cat',
  '\u{1F981}': 'lion king cat',
  '\u{1F42E}': 'cow cattle',
  '\u{1F437}': 'pig oink',
  '\u{1F438}': 'frog toad',
  '\u{1F435}': 'monkey face ape',
  '\u{1F984}': 'unicorn horn magic',
  '\u{1F41D}': 'bee honey buzz',
  '\u{1F98B}': 'butterfly insect',
  '\u{1F40C}': 'snail slow shell',
  '\u{1F422}': 'turtle tortoise slow',
  '\u{1F40D}': 'snake serpent',
  '\u{1F419}': 'octopus tentacles',
  '\u{1F42C}': 'dolphin ocean',
  '\u{1F433}': 'whale ocean',
  '\u{1F988}': 'shark ocean danger',
  '\u{1F418}': 'elephant trunk big',
  // Hearts / symbols
  '\u{2764}\u{FE0F}': 'red heart love',
  '\u{1F9E1}': 'orange heart love',
  '\u{1F49B}': 'yellow heart love',
  '\u{1F49A}': 'green heart love',
  '\u{1F499}': 'blue heart love',
  '\u{1F49C}': 'purple heart love',
  '\u{1F5A4}': 'black heart dark love',
  '\u{1F90D}': 'white heart love pure',
  '\u{1F494}': 'broken heart love sad',
  '\u{1F525}': 'fire hot lit flame',
  '\u{2B50}': 'star gold favorite',
  '\u{2728}': 'sparkles magic shine',
  '\u{1F4AF}': 'hundred percent perfect score',
  '\u{2705}': 'check mark done yes',
  '\u{274C}': 'cross mark no wrong',
  '\u{2753}': 'question mark',
  '\u{2757}': 'exclamation mark important',
  '\u{1F4AC}': 'speech bubble chat talk',
  '\u{1F4AD}': 'thought bubble think',
  '\u{1F4A4}': 'zzz sleep snore',
  '\u{1F3B5}': 'music note song',
  '\u{1F3B6}': 'music notes song singing',
  '\u{1F495}': 'two hearts love',
  '\u{1F493}': 'heartbeat pulse love',
  '\u{1F496}': 'sparkling heart love shine',
  '\u{1F498}': 'cupid arrow heart love',
  '\u{1F49D}': 'gift heart ribbon love',
  // Objects
  '\u{1F4F1}': 'phone mobile cell',
  '\u{1F4BB}': 'laptop computer',
  '\u{1F4F7}': 'camera photo picture',
  '\u{1F4FA}': 'tv television screen',
  '\u{1F4E7}': 'email mail letter',
  '\u{1F512}': 'lock locked secure',
  '\u{1F513}': 'unlock unlocked open',
  '\u{1F50D}': 'magnifying glass search left',
  '\u{1F4DD}': 'memo note write',
  '\u{1F4A1}': 'light bulb idea',
  '\u{1F526}': 'flashlight torch light',
  '\u{1F4DA}': 'books reading library',
};

/// Set of emoji that support Fitzpatrick skin tone modifiers.
/// Covers hand gestures and body-part emoji from the People category.
const _skinToneEligible = <String>{
  // Hands / gestures
  '\u{1F44B}', // waving hand
  '\u{1F91A}', // raised back of hand
  '\u{1F590}\u{FE0F}', // raised hand with fingers splayed
  '\u{270B}',  // raised hand
  '\u{1F596}', // vulcan salute
  '\u{1F44C}', // ok hand
  '\u{1F90C}', // pinched fingers
  '\u{1F90F}', // pinching hand
  '\u{270C}\u{FE0F}', // victory hand
  '\u{1F91E}', // crossed fingers
  '\u{1FAF0}', // hand with index finger and thumb crossed
  '\u{1F91F}', // love-you gesture
  '\u{1F918}', // sign of the horns
  '\u{1F919}', // call me hand
  '\u{1F448}', // backhand index pointing left
  '\u{1F449}', // backhand index pointing right
  '\u{1F446}', // backhand index pointing up
  '\u{1F595}', // middle finger
  '\u{1F447}', // backhand index pointing down
  '\u{261D}\u{FE0F}', // index pointing up
  '\u{1FAF5}', // index pointing at viewer
  '\u{1F44D}', // thumbs up
  '\u{1F44E}', // thumbs down
  '\u{270A}',  // raised fist
  '\u{1F44A}', // oncoming fist
  '\u{1F91B}', // left-facing fist
  '\u{1F91C}', // right-facing fist
  '\u{1F44F}', // clapping hands
  '\u{1F64C}', // raising hands
  '\u{1FAF6}', // hand with fingers splayed (alt)
  '\u{1F450}', // open hands
  '\u{1F932}', // palms up together
  '\u{1F91D}', // handshake
  '\u{1F64F}', // folded hands / pray
  '\u{1F4AA}', // flexed bicep
  '\u{1F9B5}', // leg
  '\u{1F9B6}', // foot
  '\u{1F442}', // ear
  '\u{1F443}', // nose
};

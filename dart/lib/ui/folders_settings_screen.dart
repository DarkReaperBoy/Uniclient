import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';
import 'filter_column.dart';
import 'settings_style.dart';

const _kFilterIconOrder = <String>[
  'Cat', 'Book', 'Money', 'Game', 'Light', 'Like',
  'Note', 'Palette', 'Travel', 'Sport', 'Favorite', 'Study',
  'Airplane', 'Private', 'Groups', 'All', 'Unread', 'Bots',
  'Crown', 'Flower', 'Home', 'Love', 'Mask', 'Party',
  'Trade', 'Work', 'Unmuted', 'Channels', 'Custom', 'Setup',
];

const _kFilterIcons = <String, IconData>{
  'Cat': Icons.pets,
  'Book': Icons.menu_book,
  'Money': Icons.attach_money,
  'Game': Icons.sports_esports,
  'Light': Icons.lightbulb_outline,
  'Like': Icons.thumb_up_outlined,
  'Note': Icons.note_outlined,
  'Palette': Icons.palette_outlined,
  'Travel': Icons.luggage_outlined,
  'Sport': Icons.sports_soccer_outlined,
  'Favorite': Icons.star_outline,
  'Study': Icons.school_outlined,
  'Airplane': Icons.flight,
  'Private': Icons.person_outline,
  'Groups': Icons.group_outlined,
  'All': Icons.chat_outlined,
  'Unread': Icons.mark_email_unread_outlined,
  'Bots': Icons.smart_toy_outlined,
  'Crown': Icons.workspace_premium_outlined,
  'Flower': Icons.local_florist_outlined,
  'Home': Icons.home_outlined,
  'Love': Icons.favorite_outline,
  'Mask': Icons.masks_outlined,
  'Party': Icons.celebration_outlined,
  'Trade': Icons.trending_up,
  'Work': Icons.work_outline,
  'Unmuted': Icons.volume_up_outlined,
  'Channels': Icons.campaign_outlined,
  'Custom': Icons.edit_outlined,
  'Setup': Icons.settings_outlined,
};

class FoldersSettingsScreen extends StatefulWidget {
  const FoldersSettingsScreen({super.key});

  @override
  State<FoldersSettingsScreen> createState() => _FoldersSettingsScreenState();
}

class _FoldersSettingsScreenState extends State<FoldersSettingsScreen> {
  List<FolderInfo> _folders = [];
  List<SuggestedFolderInfo> _recommended = [];
  bool _showTags = false;
  bool _useVerticalTabs = true;
  bool _loaded = false;
  final List<String> _pendingRemovals = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _saveChanges();
    super.dispose();
  }

  Future<void> _loadData() async {
    final appState = context.read<AppState>();
    final account = appState.activeAccount;
    if (account == null) return;
    final chatState = context.read<ChatState>();
    final engine = context.read<EngineService>();
    setState(() {
      _folders = List.of(chatState.folders);
      _loaded = true;
    });
    try {
      final suggestions = await engine.getSuggestedFolders(account.id);
      if (mounted) {
        setState(() => _recommended = suggestions);
      }
    } catch (_) {}
  }

  Future<void> _saveChanges() async {
    if (_pendingRemovals.isEmpty) return;
    final appState = context.read<AppState>();
    final account = appState.activeAccount;
    if (account == null) return;
    final chatState = context.read<ChatState>();
    for (final folderId in _pendingRemovals) {
      try {
        await chatState.deleteFolder(account.id, folderId);
      } catch (_) {}
    }
  }

  void _removeFolder(int index) {
    final folder = _folders[index];
    if (folder.isChatList) {
      _showChatListRemoveConfirmation(folder, index);
      return;
    }
    setState(() {
      _pendingRemovals.add(folder.id);
    });
  }

  void _showChatListRemoveConfirmation(FolderInfo folder, int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E2C3A) : Colors.white,
        title: const Text('Remove folder'),
        content: const Text(
          'This will also delete all invite links created for this folder.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFE53935),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        setState(() {
          _pendingRemovals.add(folder.id);
        });
      }
    });
  }

  void _restoreFolder(String folderId) {
    setState(() {
      _pendingRemovals.remove(folderId);
    });
  }

  static const int _folderLimitFree = 10;
  static const int _folderLimitPremium = 20;

  void _onCreateFolder(bool isDark, Color accentColor) {
    final currentCount = _folders.length;
    final limit = _folderLimitFree;
    if (currentCount >= limit) {
      _showFiltersLimitBox(isDark, currentCount, limit);
      return;
    }
    _showEditFilterBox(isDark, accentColor);
  }

  void _showFiltersLimitBox(bool isDark, int current, int limit) {
    final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = isDark ? const Color(0xFF6AB3F3) : const Color(0xFF168ACD);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text(
          'Folder Limit Reached',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Text(
                    '$current / $limit',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: current / _folderLimitPremium,
                      backgroundColor: isDark
                          ? const Color(0xFF2B3A48)
                          : const Color(0xFFE0E0E0),
                      valueColor: AlwaysStoppedAnimation(accentColor),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              'You have reached the limit of $limit folders. '
              'Remove an existing folder to create a new one.',
              style: TextStyle(fontSize: 14, color: subtextColor),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('OK', style: TextStyle(color: accentColor)),
          ),
        ],
      ),
    );
  }

  void _addRecommendedFolder(int index) {
    final suggestion = _recommended[index];
    final appState = context.read<AppState>();
    final account = appState.activeAccount;
    if (account == null) return;
    final chatState = context.read<ChatState>();
    setState(() {
      _recommended = List.of(_recommended)..removeAt(index);
    });
    chatState.createFolder(
      account.id,
      suggestion.name,
      const [],
      contacts: suggestion.contacts,
      nonContacts: suggestion.nonContacts,
      groups: suggestion.groups,
      channels: suggestion.channels,
      bots: suggestion.bots,
    ).then((_) {
      if (mounted) {
        chatState.loadFoldersForAccount(account.id).then((_) {
          if (mounted) {
            setState(() => _folders = List.of(chatState.folders));
          }
        });
      }
    });
  }

  void _showEditFilterBox(bool isDark, Color accentColor, {FolderInfo? existingFolder}) {
    showDialog<FolderInfo>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _EditFilterBox(
        isDark: isDark,
        accentColor: accentColor,
        existingFolder: existingFolder,
      ),
    ).then((result) {
      if (result != null && mounted) {
        final appState = context.read<AppState>();
        final account = appState.activeAccount;
        if (account == null) return;
        final chatState = context.read<ChatState>();
        if (existingFolder != null) {
          chatState.editFolder(
            account.id, existingFolder.id, result.name, result.chatIds,
            contacts: result.contacts,
            nonContacts: result.nonContacts,
            groups: result.groups,
            channels: result.channels,
            bots: result.bots,
            excludeMuted: result.excludeMuted,
            excludeRead: result.excludeRead,
            excludeArchived: result.excludeArchived,
            excludeChatIds: result.excludeChatIds,
          ).then((_) {
            if (mounted) {
              setState(() => _folders = List.of(chatState.folders));
            }
          });
        } else {
          chatState.createFolder(
            account.id, result.name, result.chatIds,
            contacts: result.contacts,
            nonContacts: result.nonContacts,
            groups: result.groups,
            channels: result.channels,
            bots: result.bots,
          ).then((_) {
            if (mounted) {
              chatState.loadFoldersForAccount(account.id).then((_) {
                if (mounted) {
                  setState(() {
                    _folders = List.of(chatState.folders);
                  });
                }
              });
            }
          });
        }
      }
    });
  }

  int _countChatsInFolder(FolderInfo folder) {
    int count = folder.chatIds.length;
    if (folder.contacts) count++;
    if (folder.nonContacts) count++;
    if (folder.groups) count++;
    if (folder.channels) count++;
    if (folder.bots) count++;
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final dividerBg = isDark ? const Color(0xFF101921) : const Color(0xFFF1F1F1);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = isDark ? const Color(0xFF6AB3F3) : const Color(0xFF168ACD);
    final sectionTitleColor = isDark ? const Color(0xFF6AB3F3) : const Color(0xFF168ACD);
    final hoverColor = isDark ? const Color(0xFF202B36) : const Color(0xFFF1F1F1);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Folders',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ),
      body: ListView(
        children: [
          // §18.2 Animated Header
          _AnimatedHeader(
            isDark: isDark,
            dividerBg: dividerBg,
            subtextColor: subtextColor,
          ),

          // §18.3 Existing Folders List
          _SectionTitle(
            text: 'Folders',
            color: sectionTitleColor,
          ),
          if (_loaded && _folders.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              child: Text(
                'No folders yet.',
                style: TextStyle(fontSize: 14, color: subtextColor),
              ),
            ),
          for (int i = 0; i < _folders.length; i++)
            _FolderRow(
              folder: _folders[i],
              isRemoved: _pendingRemovals.contains(_folders[i].id),
              chatCount: _countChatsInFolder(_folders[i]),
              showTags: _showTags,
              isDark: isDark,
              hoverColor: hoverColor,
              textColor: textColor,
              subtextColor: subtextColor,
              onRemove: () => _removeFolder(i),
              onRestore: () => _restoreFolder(_folders[i].id),
              onTap: () => _showEditFilterBox(isDark, accentColor, existingFolder: _folders[i]),
            ),

          // §18.4 Create New Folder button
          _CreateFolderButton(
            isDark: isDark,
            accentColor: accentColor,
            hoverColor: hoverColor,
            onTap: () => _onCreateFolder(isDark, accentColor),
          ),

          // Divider between folders and recommended
          const SizedBox(height: 7),
          Container(height: 1, color: dividerBg),
          const SizedBox(height: 7),

          // §18.5 Recommended Folders — visible when suggestions > 0 AND count < limit
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: (_recommended.isNotEmpty && _folders.length < _folderLimitFree)
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionTitle(
                        text: 'Recommended folders',
                        color: sectionTitleColor,
                      ),
                      for (int i = 0; i < _recommended.length; i++)
                        _RecommendedRow(
                          suggestion: _recommended[i],
                          isDark: isDark,
                          hoverColor: hoverColor,
                          textColor: textColor,
                          subtextColor: subtextColor,
                          accentColor: accentColor,
                          onAdd: () => _addRecommendedFolder(i),
                        ),
                      const SizedBox(height: 7),
                      Container(height: 1, color: dividerBg),
                      const SizedBox(height: 7),
                    ],
                  )
                : const SizedBox.shrink(),
          ),

          // §18.11 Show Folder Tags toggle
          _TagsToggle(
            value: _showTags,
            isDark: isDark,
            textColor: textColor,
            subtextColor: subtextColor,
            hoverColor: hoverColor,
            onChanged: (v) => setState(() => _showTags = v),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
            child: Text(
              'Show folder names next to unread counters in the chat list.',
              style: TextStyle(fontSize: 13, color: subtextColor),
            ),
          ),

          const SizedBox(height: 7),
          Container(height: 1, color: dividerBg),
          const SizedBox(height: 7),

          // §18.12 Tab View Section
          _ViewSection(
            useVerticalTabs: _useVerticalTabs,
            isDark: isDark,
            textColor: textColor,
            accentColor: accentColor,
            hoverColor: hoverColor,
            onChanged: (v) => setState(() => _useVerticalTabs = v),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _AnimatedHeader extends StatefulWidget {
  final bool isDark;
  final Color dividerBg;
  final Color subtextColor;

  const _AnimatedHeader({
    required this.isDark,
    required this.dividerBg,
    required this.subtextColor,
  });

  @override
  State<_AnimatedHeader> createState() => _AnimatedHeaderState();
}

class _AnimatedHeaderState extends State<_AnimatedHeader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _lottieController;

  @override
  void initState() {
    super.initState();
    _lottieController = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _lottieController.dispose();
    super.dispose();
  }

  void _onLottieLoaded(LottieComposition composition) {
    _lottieController
      ..duration = composition.duration
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: widget.dividerBg,
      width: double.infinity,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 17, 0, 5),
            child: SizedBox(
              width: 74,
              height: 74,
              child: Lottie.asset(
                'assets/animations/filters.json',
                controller: _lottieController,
                onLoaded: _onLottieLoaded,
                fit: BoxFit.contain,
              ),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 200),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 22),
              child: Text(
                'Create folders for different groups of chats\nand quickly switch between them.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: widget.subtextColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Section title (e.g. "Folders", "Recommended folders")
class _SectionTitle extends StatelessWidget {
  final String text;
  final Color color;

  const _SectionTitle({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _FolderRow extends StatefulWidget {
  final FolderInfo folder;
  final bool isRemoved;
  final int chatCount;
  final bool showTags;
  final bool isDark;
  final Color hoverColor;
  final Color textColor;
  final Color subtextColor;
  final VoidCallback onRemove;
  final VoidCallback onRestore;
  final VoidCallback onTap;

  const _FolderRow({
    required this.folder,
    required this.isRemoved,
    required this.chatCount,
    required this.showTags,
    required this.isDark,
    required this.hoverColor,
    required this.textColor,
    required this.subtextColor,
    required this.onRemove,
    required this.onRestore,
    required this.onTap,
  });

  static const _userpicColors = [
    Color(0xFFe17076), Color(0xFF7bc862), Color(0xFFe5ca77), Color(0xFF65aadd),
    Color(0xFFa695e7), Color(0xFFee7aae), Color(0xFF6ec9cb), Color(0xFFe8a64e),
  ];

  @override
  State<_FolderRow> createState() => _FolderRowState();
}

class _FolderRowState extends State<_FolderRow>
    with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  late final AnimationController _colorDotAnim;

  @override
  void initState() {
    super.initState();
    _colorDotAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      value: (widget.showTags && widget.folder.hasTagColor) ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(_FolderRow old) {
    super.didUpdateWidget(old);
    final shouldShow = widget.showTags && widget.folder.hasTagColor;
    final wasShowing = old.showTags && old.folder.hasTagColor;
    if (shouldShow && !wasShowing) {
      _colorDotAnim.forward();
    } else if (!shouldShow && wasShowing) {
      _colorDotAnim.reverse();
    }
  }

  @override
  void dispose() {
    _colorDotAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeButtonBg = widget.isDark
        ? const Color(0xFF5288C1)
        : const Color(0xFF40A7E3);
    final activeButtonBgOver = widget.isDark
        ? const Color(0xFF4B7FB0)
        : const Color(0xFF359AD5);
    final iconColor = _isHovered ? activeButtonBgOver : activeButtonBg;

    final statusText = StringBuffer('${widget.chatCount} chats');
    if (widget.folder.isChatList) {
      statusText.write(' \u00b7 shareable');
    }

    return Opacity(
      opacity: widget.isRemoved ? 0.4 : 1.0,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Container(
          height: 52,
          color: (_isHovered && !widget.isRemoved)
              ? widget.hoverColor
              : Colors.transparent,
          child: Row(
            children: [
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.isRemoved ? null : widget.onTap,
                    hoverColor: Colors.transparent,
                    splashColor: Colors.black.withValues(alpha: 0.07),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 0, 0),
                      child: Row(
                        children: [
                          Icon(
                            FilterColumn.folderIcon(widget.folder.name),
                            size: 24,
                            color: iconColor,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.folder.name,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: widget.textColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  statusText.toString(),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: widget.subtextColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.folder.hasTagColor)
                AnimatedBuilder(
                  animation: _colorDotAnim,
                  builder: (context, child) {
                    final size = 17.0 * _colorDotAnim.value;
                    if (size < 0.5) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: SizedBox(
                        width: size,
                        height: size,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _FolderRow._userpicColors[
                                widget.folder.colorIndex.clamp(0, 7)],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: widget.isRemoved
                    ? SizedBox(
                        height: 26,
                        child: TextButton(
                          onPressed: widget.onRestore,
                          style: TextButton.styleFrom(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                            backgroundColor: activeButtonBg,
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Restore',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      )
                    : SizedBox(
                        width: 34,
                        height: 34,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: widget.onRemove,
                            customBorder: const CircleBorder(),
                            child: Center(
                              child: Icon(
                                Icons.close,
                                size: 16,
                                color: widget.subtextColor
                                    .withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// §18.4 Create New Folder button
class _CreateFolderButton extends StatelessWidget {
  final bool isDark;
  final Color accentColor;
  final Color hoverColor;
  final VoidCallback onTap;

  const _CreateFolderButton({
    required this.isDark,
    required this.accentColor,
    required this.hoverColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: hoverColor,
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 22, 0),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add, size: 16, color: Colors.white),
                ),
                const SizedBox(width: 16),
                Text(
                  'Create New Folder',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: accentColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// §18.5 Recommended folder row — FilterRowButton in Suggested state
class _RecommendedRow extends StatelessWidget {
  final SuggestedFolderInfo suggestion;
  final bool isDark;
  final Color hoverColor;
  final Color textColor;
  final Color subtextColor;
  final Color accentColor;
  final VoidCallback onAdd;

  const _RecommendedRow({
    required this.suggestion,
    required this.isDark,
    required this.hoverColor,
    required this.textColor,
    required this.subtextColor,
    required this.accentColor,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onAdd,
        hoverColor: hoverColor,
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 10, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        suggestion.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (suggestion.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          suggestion.description,
                          style: TextStyle(
                            fontSize: 13,
                            color: subtextColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 26,
                  child: TextButton(
                    onPressed: onAdd,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                      backgroundColor: accentColor,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Add',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// §18.11 Show Folder Tags toggle
class _TagsToggle extends StatelessWidget {
  final bool value;
  final bool isDark;
  final Color textColor;
  final Color subtextColor;
  final Color hoverColor;
  final ValueChanged<bool> onChanged;

  const _TagsToggle({
    required this.value,
    required this.isDark,
    required this.textColor,
    required this.subtextColor,
    required this.hoverColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!value),
        hoverColor: hoverColor,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Show Folder Tags',
                  style: TextStyle(
                    fontSize: 14,
                    color: textColor,
                  ),
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeColor: isDark
                    ? const Color(0xFF6AB3F3)
                    : const Color(0xFF40A7E3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// §18.12 View section — vertical / horizontal tab radio
class _ViewSection extends StatelessWidget {
  final bool useVerticalTabs;
  final bool isDark;
  final Color textColor;
  final Color accentColor;
  final Color hoverColor;
  final ValueChanged<bool> onChanged;

  const _ViewSection({
    required this.useVerticalTabs,
    required this.isDark,
    required this.textColor,
    required this.accentColor,
    required this.hoverColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
          child: Text(
            'View',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: accentColor,
            ),
          ),
        ),
        _RadioRow(
          label: 'Side panel',
          selected: useVerticalTabs,
          textColor: textColor,
          accentColor: accentColor,
          hoverColor: hoverColor,
          onTap: () => onChanged(true),
        ),
        _RadioRow(
          label: 'Top bar',
          selected: !useVerticalTabs,
          textColor: textColor,
          accentColor: accentColor,
          hoverColor: hoverColor,
          onTap: () => onChanged(false),
        ),
      ],
    );
  }
}

class _RadioRow extends StatelessWidget {
  final String label;
  final bool selected;
  final Color textColor;
  final Color accentColor;
  final Color hoverColor;
  final VoidCallback onTap;

  const _RadioRow({
    required this.label,
    required this.selected,
    required this.textColor,
    required this.accentColor,
    required this.hoverColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: hoverColor,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 5, 10, 5),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Radio<bool>(
                  value: true,
                  groupValue: selected ? true : null,
                  onChanged: (_) => onTap(),
                  activeColor: accentColor,
                ),
              ),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(fontSize: 14, color: textColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditFilterBox extends StatefulWidget {
  final bool isDark;
  final Color accentColor;
  final FolderInfo? existingFolder;

  const _EditFilterBox({
    required this.isDark,
    required this.accentColor,
    this.existingFolder,
  });

  bool get isEditMode => existingFolder != null;

  @override
  State<_EditFilterBox> createState() => _EditFilterBoxState();
}

class _EditFilterBoxState extends State<_EditFilterBox> {
  final _nameController = TextEditingController();
  final _iconToggleKey = GlobalKey();
  bool _contacts = false;
  bool _nonContacts = false;
  bool _groups = false;
  bool _channels = false;
  bool _bots = false;
  bool _excludeMuted = false;
  bool _excludeRead = false;
  bool _excludeArchived = false;
  bool _userTyped = false;
  String? _selectedIconName;

  @override
  void initState() {
    super.initState();
    final f = widget.existingFolder;
    if (f != null) {
      _nameController.text = f.name;
      _contacts = f.contacts;
      _nonContacts = f.nonContacts;
      _groups = f.groups;
      _channels = f.channels;
      _bots = f.bots;
      _excludeMuted = f.excludeMuted;
      _excludeRead = f.excludeRead;
      _excludeArchived = f.excludeArchived;
      _userTyped = f.name.isNotEmpty;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _updateAutoTitle() {
    if (_userTyped) return;
    String auto = '';
    if (_contacts && !_nonContacts && !_groups && !_channels && !_bots) {
      auto = 'Contacts';
    } else if (_nonContacts && !_contacts && !_groups && !_channels && !_bots) {
      auto = 'Non-Contacts';
    } else if (_groups && !_contacts && !_nonContacts && !_channels && !_bots) {
      auto = 'Groups';
    } else if (_channels && !_contacts && !_nonContacts && !_groups && !_bots) {
      auto = 'Channels';
    } else if (_bots && !_contacts && !_nonContacts && !_groups && !_channels) {
      auto = 'Bots';
    }
    if (auto.length > 12) auto = auto.substring(0, 12);
    _nameController.text = auto;
  }

  String _getAutoIconName() {
    if (_contacts && !_nonContacts && !_groups && !_channels && !_bots) {
      return 'Private';
    }
    if (_groups && !_contacts && !_nonContacts && !_channels && !_bots) {
      return 'Groups';
    }
    if (_channels && !_contacts && !_nonContacts && !_groups && !_bots) {
      return 'Channels';
    }
    if (_bots && !_contacts && !_nonContacts && !_groups && !_channels) {
      return 'Bots';
    }
    if (_excludeRead) return 'Unread';
    if (_excludeMuted) return 'Unmuted';
    if (_contacts || _nonContacts || _groups || _channels || _bots) {
      return 'Custom';
    }
    return 'All';
  }

  String get _effectiveIconName => _selectedIconName ?? _getAutoIconName();

  void _showIconPicker() {
    final box = _iconToggleKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final offset = box.localToGlobal(Offset.zero);
    final size = box.size;
    const panelWidth = 284.0;
    final screenWidth = MediaQuery.of(context).size.width;
    var left = offset.dx + size.width - panelWidth - 2;
    if (left < 8) left = 8;
    if (left + panelWidth > screenWidth - 8) left = screenWidth - panelWidth - 8;
    final top = offset.dy + size.height - 1;

    showDialog<String>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            child: _FilterIconPanel(
              isDark: widget.isDark,
              selectedIcon: _effectiveIconName,
              onSelect: (name) {
                Navigator.of(ctx).pop(name);
              },
            ),
          ),
        ],
      ),
    ).then((name) {
      if (name != null && mounted) {
        setState(() => _selectedIconName = name);
      }
    });
  }

  void _onToggle(String key, bool value) {
    setState(() {
      switch (key) {
        case 'contacts':
          _contacts = value;
        case 'nonContacts':
          _nonContacts = value;
        case 'groups':
          _groups = value;
        case 'channels':
          _channels = value;
        case 'bots':
          _bots = value;
        case 'excludeMuted':
          _excludeMuted = value;
        case 'excludeRead':
          _excludeRead = value;
        case 'excludeArchived':
          _excludeArchived = value;
      }
      _updateAutoTitle();
    });
  }

  void _onSave() {
    final name = _nameController.text.trim();
    if (name.isEmpty || name.characters.length > 12) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(name.isEmpty
              ? 'Please enter a folder name.'
              : 'Folder name must be 12 characters or less.'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    if (!_contacts && !_nonContacts && !_groups && !_channels && !_bots) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("The folder can't be empty."),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    if (_contacts && _nonContacts && _groups && _channels && _bots &&
        _excludeArchived && widget.existingFolder?.chatIds.isEmpty != false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This folder would include all your chats.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final existing = widget.existingFolder;
    Navigator.of(context).pop(FolderInfo(
      id: existing?.id ?? '',
      name: name,
      chatIds: existing?.chatIds ?? const [],
      excludeChatIds: existing?.excludeChatIds ?? const [],
      pinnedChatIds: existing?.pinnedChatIds ?? const [],
      contacts: _contacts,
      nonContacts: _nonContacts,
      groups: _groups,
      channels: _channels,
      bots: _bots,
      excludeMuted: _excludeMuted,
      excludeRead: _excludeRead,
      excludeArchived: _excludeArchived,
      isChatList: existing?.isChatList ?? false,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor =
        widget.isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        widget.isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final inputBg =
        widget.isDark ? const Color(0xFF242F3D) : const Color(0xFFF1F1F1);
    final charCount = _nameController.text.characters.length;

    final isChatList = widget.existingFolder?.isChatList ?? false;

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: SizedBox(
        width: 364,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
                child: Text(
                  widget.isEditMode ? 'Edit Folder' : 'New Folder',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            TextField(
                              controller: _nameController,
                              maxLength: 12,
                              autofocus: !widget.isEditMode,
                              onChanged: (v) {
                                if (!_userTyped && v.isNotEmpty) _userTyped = true;
                                if (v.isEmpty) _userTyped = false;
                                setState(() {});
                              },
                              decoration: InputDecoration(
                                hintText: 'Folder name',
                                hintStyle: TextStyle(color: subtextColor),
                                counterText: '',
                                filled: true,
                                fillColor: inputBg,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.fromLTRB(14, 12, 87, 12),
                              ),
                              style: TextStyle(fontSize: 14, color: textColor),
                            ),
                            Positioned(
                              right: 46,
                              top: 0,
                              bottom: 0,
                              child: Center(
                                child: Text(
                                  '$charCount/12',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: charCount >= 12
                                        ? const Color(0xFFE53935)
                                        : subtextColor,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              right: 4,
                              top: 0,
                              bottom: 0,
                              child: Center(
                                child: _FilterIconToggle(
                                  key: _iconToggleKey,
                                  iconName: _effectiveIconName,
                                  isDark: widget.isDark,
                                  onTap: _showIconPicker,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
                        child: Text(
                          'Included Chats',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: widget.accentColor,
                          ),
                        ),
                      ),
                      _TypeToggleRow(
                        label: 'Contacts',
                        icon: Icons.person,
                        color: const Color(0xFF7bc862),
                        value: _contacts,
                        isDark: widget.isDark,
                        textColor: textColor,
                        onChanged: (v) => _onToggle('contacts', v),
                      ),
                      _TypeToggleRow(
                        label: 'Non-Contacts',
                        icon: Icons.person_outline,
                        color: const Color(0xFF6ec9cb),
                        value: _nonContacts,
                        isDark: widget.isDark,
                        textColor: textColor,
                        onChanged: (v) => _onToggle('nonContacts', v),
                      ),
                      _TypeToggleRow(
                        label: 'Groups',
                        icon: Icons.group,
                        color: const Color(0xFF7bc862),
                        value: _groups,
                        isDark: widget.isDark,
                        textColor: textColor,
                        onChanged: (v) => _onToggle('groups', v),
                      ),
                      _TypeToggleRow(
                        label: 'Channels',
                        icon: Icons.campaign,
                        color: const Color(0xFFe17076),
                        value: _channels,
                        isDark: widget.isDark,
                        textColor: textColor,
                        onChanged: (v) => _onToggle('channels', v),
                      ),
                      _TypeToggleRow(
                        label: 'Bots',
                        icon: Icons.smart_toy,
                        color: const Color(0xFFa695e7),
                        value: _bots,
                        isDark: widget.isDark,
                        textColor: textColor,
                        onChanged: (v) => _onToggle('bots', v),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
                        child: Text(
                          'Choose chats and types of chats that will appear in this folder.',
                          style: TextStyle(fontSize: 13, color: subtextColor),
                        ),
                      ),
                      if (!isChatList) ...[
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
                          child: Text(
                            'Excluded Chats',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: widget.accentColor,
                            ),
                          ),
                        ),
                        _TypeToggleRow(
                          label: 'Muted',
                          icon: Icons.volume_off,
                          color: const Color(0xFFa695e7),
                          value: _excludeMuted,
                          isDark: widget.isDark,
                          textColor: textColor,
                          onChanged: (v) => _onToggle('excludeMuted', v),
                        ),
                        _TypeToggleRow(
                          label: 'Archived',
                          icon: Icons.archive,
                          color: const Color(0xFF7bc862),
                          value: _excludeArchived,
                          isDark: widget.isDark,
                          textColor: textColor,
                          onChanged: (v) => _onToggle('excludeArchived', v),
                        ),
                        _TypeToggleRow(
                          label: 'Read',
                          icon: Icons.done_all,
                          color: const Color(0xFF6ec9cb),
                          value: _excludeRead,
                          isDark: widget.isDark,
                          textColor: textColor,
                          onChanged: (v) => _onToggle('excludeRead', v),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
                          child: Text(
                            'Choose chats and types of chats that will never appear in this folder.',
                            style: TextStyle(fontSize: 13, color: subtextColor),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        'Cancel',
                        style: TextStyle(color: subtextColor, fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _onSave,
                      style: TextButton.styleFrom(
                        backgroundColor: widget.accentColor,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: Text(
                        widget.isEditMode ? 'Save' : 'Create',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterIconToggle extends StatefulWidget {
  final String iconName;
  final bool isDark;
  final VoidCallback onTap;

  const _FilterIconToggle({
    super.key,
    required this.iconName,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_FilterIconToggle> createState() => _FilterIconToggleState();
}

class _FilterIconToggleState extends State<_FilterIconToggle> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final mutedColor = widget.isDark
        ? const Color(0xFF3E546A)
        : const Color(0xFFBBBBBB);
    final hoverColor = widget.isDark
        ? const Color(0xFF4E647A)
        : const Color(0xFFAAAAAA);
    final iconData = _kFilterIcons[widget.iconName] ?? Icons.folder_outlined;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: Icon(
              iconData,
              size: 22,
              color: _hovering ? hoverColor : mutedColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterIconPanel extends StatelessWidget {
  final bool isDark;
  final String selectedIcon;
  final ValueChanged<String> onSelect;

  const _FilterIconPanel({
    required this.isDark,
    required this.selectedIcon,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark ? const Color(0xFF17212B) : Colors.white;
    final headerColor = isDark
        ? const Color(0xFF6C7883)
        : const Color(0xFF999999);

    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      color: bgColor,
      child: SizedBox(
        width: 284,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 14, 0, 6),
                child: Text(
                  'Folder Icon',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: headerColor,
                  ),
                ),
              ),
              for (var row = 0; row < 5; row++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var col = 0; col < 6; col++)
                      _IconCell(
                        iconName: _kFilterIconOrder[row * 6 + col],
                        isSelected:
                            _kFilterIconOrder[row * 6 + col] == selectedIcon,
                        isDark: isDark,
                        onTap: () =>
                            onSelect(_kFilterIconOrder[row * 6 + col]),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconCell extends StatefulWidget {
  final String iconName;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _IconCell({
    required this.iconName,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_IconCell> createState() => _IconCellState();
}

class _IconCellState extends State<_IconCell> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final normalColor = widget.isDark
        ? const Color(0xFF3E546A)
        : const Color(0xFFBBBBBB);
    final activeColor = widget.isDark
        ? const Color(0xFF6AB3F3)
        : const Color(0xFF40A7E3);
    final hoverBg = widget.isDark
        ? const Color(0xFF202B36)
        : const Color(0xFFF1F1F1);
    final iconData = _kFilterIcons[widget.iconName] ?? Icons.folder_outlined;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 44,
          height: 42,
          decoration: BoxDecoration(
            color: _hovering ? hoverBg : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            iconData,
            size: 22,
            color: widget.isSelected
                ? activeColor
                : _hovering
                    ? normalColor.withValues(alpha: 0.8)
                    : normalColor,
          ),
        ),
      ),
    );
  }
}

class _TypeToggleRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool value;
  final bool isDark;
  final Color textColor;
  final ValueChanged<bool> onChanged;

  const _TypeToggleRow({
    required this.label,
    required this.icon,
    required this.color,
    required this.value,
    required this.isDark,
    required this.textColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hoverColor =
        isDark ? const Color(0xFF202B36) : const Color(0xFFF1F1F1);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!value),
        hoverColor: hoverColor,
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [color, color.withValues(alpha: 0.8)],
                    ),
                  ),
                  child: Icon(icon, size: 18, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 14, color: textColor),
                  ),
                ),
                Checkbox(
                  value: value,
                  onChanged: (v) => onChanged(v ?? false),
                  activeColor: isDark
                      ? const Color(0xFF6AB3F3)
                      : const Color(0xFF40A7E3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

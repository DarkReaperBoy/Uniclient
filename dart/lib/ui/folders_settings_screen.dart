import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';
import '../theme/theme.dart';
import 'filter_column.dart';
import 'settings_style.dart';
import 'telegram_toast.dart';

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

void showEditFolderBox(BuildContext context, FolderInfo folder) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;
  final accentColor = theme.colorScheme.primary;
  showDialog<FolderInfo>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _EditFilterBox(
      isDark: isDark,
      accentColor: accentColor,
      existingFolder: folder,
    ),
  ).then((result) {
    if (result != null && context.mounted) {
      final appState = context.read<AppState>();
      final account = appState.activeAccount;
      if (account == null) return;
      final chatState = context.read<ChatState>();
      chatState.editFolder(
        account.id, folder.id, result.name, result.chatIds,
        contacts: result.contacts,
        nonContacts: result.nonContacts,
        groups: result.groups,
        channels: result.channels,
        bots: result.bots,
        excludeMuted: result.excludeMuted,
        excludeRead: result.excludeRead,
        excludeArchived: result.excludeArchived,
        excludeChatIds: result.excludeChatIds,
      );
    }
  });
}

class FoldersSettingsScreen extends StatefulWidget {
  const FoldersSettingsScreen({super.key});

  @override
  State<FoldersSettingsScreen> createState() => _FoldersSettingsScreenState();
}

class _FoldersSettingsScreenState extends State<FoldersSettingsScreen> {
  List<FolderInfo> _folders = [];
  List<SuggestedFolderInfo> _recommended = [];
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
    final accentColor = context.palette.windowBgActive;
    showDialog<bool>(
      context: context,
      builder: (ctx) => _ChatlistFolderRemovalDialog(
        isDark: isDark,
        accentColor: accentColor,
        folder: folder,
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

  int get _folderLimitFree => context.read<ChatState>().folderLimitFree;
  int get _folderLimitPremium => context.read<ChatState>().folderLimitPremium;

  void _onCreateFolder(bool isDark, Color accentColor) {
    final isPremium = context.read<AppState>().activeAccount?.isPremium ?? false;
    final currentCount = _folders.length;
    final limit = isPremium ? _folderLimitPremium : _folderLimitFree;
    if (currentCount >= limit) {
      showDialog(
        context: context,
        builder: (_) => SimpleLimitBox(
          isDark: isDark,
          title: 'Folder Limit Reached',
          current: currentCount,
          limitFree: _folderLimitFree,
          limitPremium: _folderLimitPremium,
          isPremium: isPremium,
          icon: Icons.folder_outlined,
          description: isPremium
              ? 'You have reached the limit of $limit folders. Remove an existing folder to create a new one.'
              : 'You have reached the limit of $limit folders. Subscribe to Premium to increase the limit to $_folderLimitPremium.',
        ),
      );
      return;
    }
    _showEditFilterBox(isDark, accentColor);
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
              showTags: context.read<ChatState>().showFolderTags,
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
            child: (_recommended.isNotEmpty && _folders.length < ((context.read<AppState>().activeAccount?.isPremium ?? false) ? _folderLimitPremium : _folderLimitFree))
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
            value: context.read<ChatState>().showFolderTags,
            isPremium: context.read<AppState>().activeAccount?.isPremium ?? false,
            isDark: isDark,
            textColor: textColor,
            subtextColor: subtextColor,
            hoverColor: hoverColor,
            onChanged: (v) {
              context.read<ChatState>().showFolderTags = v;
              setState(() {});
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 12),
            child: Text(
              'Show folder names next to unread counters in the chat list.',
              style: TextStyle(fontSize: 13, color: subtextColor),
            ),
          ),

          // §18.12 Tab View Section — visible only when window ≥ 452px
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 452) return const SizedBox.shrink();
              final chatState = context.read<ChatState>();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 7),
                  Container(height: 1, color: dividerBg),
                  const SizedBox(height: 7),
                  _ViewSection(
                    useVerticalTabs: chatState.useVerticalFilters,
                    isDark: isDark,
                    textColor: textColor,
                    accentColor: accentColor,
                    hoverColor: hoverColor,
                    onChanged: (v) {
                      chatState.useVerticalFilters = v;
                      setState(() {});
                    },
                  ),
                ],
              );
            },
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
    final activeButtonBg = context.palette.windowBgActive;
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
                            FilterColumn.folderIconForInfo(widget.folder),
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
                            color: context.palette.peerUserpicBg(
                                widget.folder.colorIndex.clamp(0, 7)),
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
class _TagsToggle extends StatefulWidget {
  final bool value;
  final bool isPremium;
  final bool isDark;
  final Color textColor;
  final Color subtextColor;
  final Color hoverColor;
  final ValueChanged<bool> onChanged;

  const _TagsToggle({
    required this.value,
    required this.isPremium,
    required this.isDark,
    required this.textColor,
    required this.subtextColor,
    required this.hoverColor,
    required this.onChanged,
  });

  @override
  State<_TagsToggle> createState() => _TagsToggleState();
}

class _TagsToggleState extends State<_TagsToggle> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onToggle(bool v) {
    if (!widget.isPremium) {
      _showPremiumPreview();
      return;
    }
    widget.onChanged(v);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      final engine = context.read<EngineService>();
      final accountId = context.read<AppState>().activeAccount?.id ?? '';
      if (accountId.isNotEmpty) {
        engine.toggleDialogFilterTags(accountId, v);
      }
    });
  }

  void _showPremiumPreview() {
    final bgColor = widget.isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor = widget.isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = widget.isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = widget.isDark ? const Color(0xFF6AB3F3) : const Color(0xFF168ACD);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Row(
          children: [
            Icon(Icons.workspace_premium, color: accentColor, size: 24),
            const SizedBox(width: 10),
            Text(
              'Folder Tags',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
        ),
        content: Text(
          'Show folder names as colored tags next to unread counters in the chat list.\n\n'
          'This is a Premium feature.',
          style: TextStyle(fontSize: 14, color: subtextColor),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _showPremiumPurchaseDialog(context, widget.isDark);
            },
            child: Text('Subscribe to Premium', style: TextStyle(color: const Color(0xFFCB7DFF))),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Close', style: TextStyle(color: accentColor)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = widget.isDark
        ? const Color(0xFF6AB3F3)
        : context.palette.windowBgActive;
    final lockColor = widget.isDark
        ? const Color(0xFF6C7883)
        : const Color(0xFF999999);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onToggle(!widget.value),
        hoverColor: widget.hoverColor,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 8),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      'Show Folder Tags',
                      style: TextStyle(
                        fontSize: 14,
                        color: widget.textColor,
                      ),
                    ),
                    if (!widget.isPremium) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.lock, size: 16, color: lockColor),
                    ],
                  ],
                ),
              ),
              Switch(
                value: widget.value,
                onChanged: _onToggle,
                activeColor: accentColor,
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
  final _scrollController = ScrollController();
  final _iconToggleKey = GlobalKey();
  String? _nameError;
  bool _contacts = false;
  bool _nonContacts = false;
  bool _groups = false;
  bool _channels = false;
  bool _bots = false;
  bool _newChats = false;
  bool _existingChats = false;
  bool _excludeMuted = false;
  bool _excludeRead = false;
  bool _excludeArchived = false;
  bool _userTyped = false;
  String? _selectedIconName;
  int _colorIndex = -1;
  List<ChatlistInviteLink> _inviteLinks = [];
  bool _loadingLinks = false;
  List<String> _includedChatIds = [];
  List<String> _excludedChatIds = [];

  static const _allIncludeTypes = <_PreviewTypeInfo>[
    _PreviewTypeInfo('newChats', 'New Chats', Icons.fiber_new, Color(0xFF7bc862)),
    _PreviewTypeInfo('existingChats', 'Existing Chats', Icons.chat_bubble, Color(0xFF40a7e3)),
    _PreviewTypeInfo('contacts', 'Contacts', Icons.person, Color(0xFF7bc862)),
    _PreviewTypeInfo('nonContacts', 'Non-Contacts', Icons.person_outline, Color(0xFF6ec9cb)),
    _PreviewTypeInfo('groups', 'Groups', Icons.group, Color(0xFF7bc862)),
    _PreviewTypeInfo('channels', 'Channels', Icons.campaign, Color(0xFFe17076)),
    _PreviewTypeInfo('bots', 'Bots', Icons.smart_toy, Color(0xFFa695e7)),
  ];

  static const _allExcludeTypes = <_PreviewTypeInfo>[
    _PreviewTypeInfo('excludeMuted', 'Muted', Icons.volume_off, Color(0xFFa695e7)),
    _PreviewTypeInfo('excludeArchived', 'Archived', Icons.archive, Color(0xFF7bc862)),
    _PreviewTypeInfo('excludeRead', 'Read', Icons.done_all, Color(0xFF6ec9cb)),
  ];

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
      _newChats = f.newChats;
      _existingChats = f.existingChats;
      _excludeMuted = f.excludeMuted;
      _excludeRead = f.excludeRead;
      _excludeArchived = f.excludeArchived;
      _userTyped = f.name.isNotEmpty;
      _colorIndex = f.colorIndex;
      _includedChatIds = List<String>.from(f.chatIds);
      _excludedChatIds = List<String>.from(f.excludeChatIds);
    }
    if (widget.isEditMode) {
      _loadInviteLinks();
    }
  }

  void _loadInviteLinks() {
    final f = widget.existingFolder;
    if (f == null || f.id.isEmpty) return;
    final folderId = int.tryParse(f.id);
    if (folderId == null) return;
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccount?.id ?? '';
    if (accountId.isEmpty) return;
    setState(() => _loadingLinks = true);
    engine.getFolderInviteLinks(accountId, folderId).then((links) {
      if (mounted) setState(() { _inviteLinks = links; _loadingLinks = false; });
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _scrollController.dispose();
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

  void _insertEmoji(String emoji) {
    final text = _nameController.text;
    final sel = _nameController.selection;
    final chars = text.characters;
    if (chars.length >= 12) return;
    final offset = sel.isValid ? sel.baseOffset : text.length;
    final newText = text.substring(0, offset) + emoji + text.substring(offset);
    if (newText.characters.length > 12) return;
    _nameController.text = newText;
    final newOffset = offset + emoji.length;
    _nameController.selection = TextSelection.collapsed(offset: newOffset);
    if (!_userTyped) _userTyped = true;
    setState(() {});
  }

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
        case 'newChats':
          _newChats = value;
        case 'existingChats':
          _existingChats = value;
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

  List<_PreviewTypeInfo> _buildIncludeTypeList() {
    final list = <_PreviewTypeInfo>[];
    final isChatList = widget.existingFolder?.isChatList ?? false;
    if (isChatList) {
      if (_newChats) list.add(_allIncludeTypes[0]);
      if (_existingChats) list.add(_allIncludeTypes[1]);
    }
    if (_contacts) list.add(_allIncludeTypes[2]);
    if (_nonContacts) list.add(_allIncludeTypes[3]);
    if (_groups) list.add(_allIncludeTypes[4]);
    if (_channels) list.add(_allIncludeTypes[5]);
    if (_bots) list.add(_allIncludeTypes[6]);
    return list;
  }

  void _removeIncludeType(String key) {
    _onToggle(key, false);
  }

  List<_PreviewTypeInfo> _buildExcludeTypeList() {
    final list = <_PreviewTypeInfo>[];
    if (_excludeMuted) list.add(_allExcludeTypes[0]);
    if (_excludeArchived) list.add(_allExcludeTypes[1]);
    if (_excludeRead) list.add(_allExcludeTypes[2]);
    return list;
  }

  void _removeExcludeType(String key) {
    _onToggle(key, false);
  }

  bool get _hasExclusions =>
      _excludeMuted || _excludeRead || _excludeArchived ||
      (widget.existingFolder?.excludeChatIds.isNotEmpty ?? false);

  void _createInviteLink() {
    if (_hasExclusions) {
      showTelegramToast(context, "Can't create links for this folder.");
      return;
    }
    final f = widget.existingFolder;
    if (f == null || f.id.isEmpty) return;
    final folderId = int.tryParse(f.id);
    if (folderId == null) return;
    final appState = context.read<AppState>();
    final isPremium = appState.activeAccount?.isPremium ?? false;
    final isDark = widget.isDark;

    final chatState = context.read<ChatState>();
    final shareableCount = chatState.folders.where((fo) => fo.isChatList).length;
    final shareLimit = isPremium
        ? chatState.sharedFoldersPremium
        : chatState.sharedFoldersFree;
    if (!f.isChatList && shareableCount >= shareLimit) {
      showDialog(
        context: context,
        builder: (_) => SimpleLimitBox(
          isDark: isDark,
          title: 'Shareable Folder Limit',
          current: shareableCount,
          limitFree: chatState.sharedFoldersFree,
          limitPremium: chatState.sharedFoldersPremium,
          isPremium: isPremium,
          icon: Icons.share_outlined,
          description: isPremium
              ? 'You have $shareableCount shareable folders, the maximum is $shareLimit.'
              : 'You can share up to $shareLimit folders for free. Subscribe to Premium for up to ${chatState.sharedFoldersPremium}.',
        ),
      );
      return;
    }

    final linkLimit = isPremium
        ? chatState.linksPerFolderPremium
        : chatState.linksPerFolderFree;
    if (_inviteLinks.length >= linkLimit) {
      showDialog(
        context: context,
        builder: (_) => SimpleLimitBox(
          isDark: isDark,
          title: 'Link Limit Reached',
          current: _inviteLinks.length,
          limitFree: chatState.linksPerFolderFree,
          limitPremium: chatState.linksPerFolderPremium,
          isPremium: isPremium,
          icon: Icons.link,
          description: isPremium
              ? 'This folder has ${_inviteLinks.length} links, the maximum is $linkLimit.'
              : 'You can create up to $linkLimit links per folder for free. Subscribe to Premium for up to ${chatState.linksPerFolderPremium}.',
        ),
      );
      return;
    }

    final engine = context.read<EngineService>();
    final accountId = appState.activeAccount?.id ?? '';
    if (accountId.isEmpty) return;
    engine.createFolderInviteLink(accountId, folderId, f.name, f.chatIds).then((url) {
      if (mounted && url != null) {
        _loadInviteLinks();
      }
    });
  }

  void _deleteInviteLink(ChatlistInviteLink link) {
    final f = widget.existingFolder;
    if (f == null || f.id.isEmpty) return;
    final folderId = int.tryParse(f.id);
    if (folderId == null) return;
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccount?.id ?? '';
    if (accountId.isEmpty) return;
    engine.deleteFolderInviteLink(accountId, folderId, link.slug).then((ok) {
      if (mounted && ok) {
        setState(() => _inviteLinks.remove(link));
      }
    });
  }

  void _showLinkContextMenu(BuildContext context, ChatlistInviteLink link, Offset position) {
    final isDark = widget.isDark;
    final menuBg = isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final menuText = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final deleteColor = isDark ? const Color(0xFFE53935) : const Color(0xFFE53935);
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      color: menuBg,
      items: [
        PopupMenuItem(value: 'copy', child: Text('Copy Link', style: TextStyle(color: menuText, fontSize: 14))),
        PopupMenuItem(value: 'delete', child: Text('Delete Link', style: TextStyle(color: deleteColor, fontSize: 14))),
      ],
    ).then((action) {
      if (!mounted || action == null) return;
      switch (action) {
        case 'copy':
          Clipboard.setData(ClipboardData(text: link.url));
          showTelegramToast(context, 'Link copied');
        case 'delete':
          _deleteInviteLink(link);
      }
    });
  }

  void _showLinkDetail(ChatlistInviteLink link) {
    final f = widget.existingFolder;
    if (f == null) return;
    showDialog<ChatlistInviteLink>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ShowLinkBox(
        isDark: widget.isDark,
        accentColor: widget.accentColor,
        link: link,
        folder: f,
      ),
    ).then((updatedLink) {
      if (updatedLink != null && mounted) {
        setState(() {
          final idx = _inviteLinks.indexWhere((l) => l.slug == updatedLink.slug);
          if (idx >= 0) {
            _inviteLinks[idx] = updatedLink;
          }
        });
      }
    });
  }

  void _openExcludeTypePicker() {
    final appState = context.read<AppState>();
    final accountId = appState.activeAccount?.id ?? '';
    final allChats = context.read<ChatState>().chatsForAccount(accountId);
    showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ExcludeTypePicker(
        isDark: widget.isDark,
        accentColor: widget.accentColor,
        excludeMuted: _excludeMuted,
        excludeArchived: _excludeArchived,
        excludeRead: _excludeRead,
        selectedChatIds: _excludedChatIds,
        allChats: allChats,
      ),
    ).then((result) {
      if (result != null && mounted) {
        setState(() {
          _excludeMuted = result['excludeMuted'] as bool? ?? _excludeMuted;
          _excludeArchived = result['excludeArchived'] as bool? ?? _excludeArchived;
          _excludeRead = result['excludeRead'] as bool? ?? _excludeRead;
          _excludedChatIds = (result['chatIds'] as List<String>?) ?? _excludedChatIds;
          _updateAutoTitle();
        });
      }
    });
  }

  void _openIncludeTypePicker() {
    final isChatList = widget.existingFolder?.isChatList ?? false;
    final appState = context.read<AppState>();
    final accountId = appState.activeAccount?.id ?? '';
    final allChats = context.read<ChatState>().chatsForAccount(accountId);
    showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _IncludeTypePicker(
        isDark: widget.isDark,
        accentColor: widget.accentColor,
        isChatList: isChatList,
        newChats: _newChats,
        existingChats: _existingChats,
        contacts: _contacts,
        nonContacts: _nonContacts,
        groups: _groups,
        channels: _channels,
        bots: _bots,
        selectedChatIds: _includedChatIds,
        allChats: allChats,
      ),
    ).then((result) {
      if (result != null && mounted) {
        setState(() {
          _newChats = result['newChats'] as bool? ?? _newChats;
          _existingChats = result['existingChats'] as bool? ?? _existingChats;
          _contacts = result['contacts'] as bool? ?? _contacts;
          _nonContacts = result['nonContacts'] as bool? ?? _nonContacts;
          _groups = result['groups'] as bool? ?? _groups;
          _channels = result['channels'] as bool? ?? _channels;
          _bots = result['bots'] as bool? ?? _bots;
          _includedChatIds = (result['chatIds'] as List<String>?) ?? _includedChatIds;
          _updateAutoTitle();
        });
      }
    });
  }

  void _onSave() {
    final name = _nameController.text.trim();
    final hasIncludeTypes =
        _contacts || _nonContacts || _groups || _channels || _bots ||
        _newChats || _existingChats;
    final hasIncludeChats = _includedChatIds.isNotEmpty;

    if (name.isEmpty || name.characters.length > 12) {
      setState(() {
        _nameError = name.isEmpty
            ? 'Please enter a folder name.'
            : 'Folder name must be 12 characters or less.';
      });
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
      return;
    }
    if (!hasIncludeTypes && !hasIncludeChats) {
      showTelegramToast(context, "The folder can't be empty.");
      return;
    }
    if (_contacts && _nonContacts && _groups && _channels && _bots &&
        _excludeArchived && !hasIncludeChats) {
      showTelegramToast(context, 'This folder would include all your chats.');
      return;
    }
    final existing = widget.existingFolder;
    final chatCount = _includedChatIds.length;
    final isPremium = context.read<AppState>().activeAccount?.isPremium ?? false;
    final cs = context.read<ChatState>();
    final chatLimit = isPremium ? cs.chatsPerFolderPremium : cs.chatsPerFolderFree;
    if (chatCount > chatLimit) {
      showDialog(
        context: context,
        builder: (_) => SimpleLimitBox(
          isDark: widget.isDark,
          title: 'Chat Limit Reached',
          current: chatCount,
          limitFree: cs.chatsPerFolderFree,
          limitPremium: cs.chatsPerFolderPremium,
          isPremium: isPremium,
          icon: Icons.chat_outlined,
          description: isPremium
              ? 'This folder contains $chatCount chats, exceeding the limit of $chatLimit.'
              : 'This folder contains $chatCount chats, exceeding the free limit of $chatLimit. Subscribe to Premium for up to ${cs.chatsPerFolderPremium}.',
        ),
      );
      return;
    }
    Navigator.of(context).pop(FolderInfo(
      id: existing?.id ?? '',
      name: name,
      chatIds: _includedChatIds,
      excludeChatIds: _excludedChatIds,
      pinnedChatIds: existing?.pinnedChatIds ?? const [],
      contacts: _contacts,
      nonContacts: _nonContacts,
      groups: _groups,
      channels: _channels,
      bots: _bots,
      newChats: _newChats,
      existingChats: _existingChats,
      excludeMuted: _excludeMuted,
      excludeRead: _excludeRead,
      excludeArchived: _excludeArchived,
      colorIndex: _colorIndex,
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
                  controller: _scrollController,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                TextField(
                                  controller: _nameController,
                                  maxLength: 12,
                                  autofocus: !widget.isEditMode,
                                  onChanged: (v) {
                                    if (!_userTyped && v.isNotEmpty) _userTyped = true;
                                    if (v.isEmpty) _userTyped = false;
                                    if (_nameError != null) _nameError = null;
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
                                    enabledBorder: _nameError != null
                                        ? OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: const BorderSide(
                                              color: Color(0xFFE53935),
                                              width: 1.5,
                                            ),
                                          )
                                        : OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: BorderSide.none,
                                          ),
                                    contentPadding: const EdgeInsets.fromLTRB(14, 12, 100, 12),
                                  ),
                                  style: TextStyle(fontSize: 14, color: textColor),
                                ),
                                Positioned(
                                  right: 65,
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
                                  right: 40,
                                  top: 0,
                                  bottom: 0,
                                  child: Center(
                                    child: _EmojiButton(
                                      isDark: widget.isDark,
                                      onEmojiSelected: _insertEmoji,
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
                            if (_nameError != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  _nameError!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFFE53935),
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
                      _AddChatsButton(
                        isDark: widget.isDark,
                        accentColor: widget.accentColor,
                        onTap: _openIncludeTypePicker,
                      ),
                      _FilterChatsPreview(
                        types: _buildIncludeTypeList(),
                        isDark: widget.isDark,
                        textColor: textColor,
                        onRemove: _removeIncludeType,
                      ),
                      _SelectedChatsPreview(
                        chatIds: _includedChatIds,
                        isDark: widget.isDark,
                        textColor: textColor,
                        onRemove: (id) => setState(() => _includedChatIds.remove(id)),
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
                        _RemoveChatsButton(
                          isDark: widget.isDark,
                          accentColor: widget.accentColor,
                          onTap: _openExcludeTypePicker,
                        ),
                        _FilterChatsPreview(
                          types: _buildExcludeTypeList(),
                          isDark: widget.isDark,
                          textColor: textColor,
                          onRemove: _removeExcludeType,
                        ),
                        _SelectedChatsPreview(
                          chatIds: _excludedChatIds,
                          isDark: widget.isDark,
                          textColor: textColor,
                          onRemove: (id) => setState(() => _excludedChatIds.remove(id)),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
                          child: Text(
                            'Choose chats and types of chats that will never appear in this folder.',
                            style: TextStyle(fontSize: 13, color: subtextColor),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      _TagColorSection(
                        isDark: widget.isDark,
                        accentColor: widget.accentColor,
                        selectedIndex: _colorIndex,
                        folderName: _nameController.text.trim(),
                        onSelect: (idx) => setState(() => _colorIndex = idx),
                      ),
                      if (widget.isEditMode) ...[
                        const SizedBox(height: 16),
                        _ShareableLinkSection(
                          isDark: widget.isDark,
                          accentColor: widget.accentColor,
                          links: _inviteLinks,
                          loading: _loadingLinks,
                          hasExclusions: _hasExclusions,
                          onCreateLink: _createInviteLink,
                          onDeleteLink: _deleteInviteLink,
                          onShowLink: _showLinkDetail,
                          onShowContextMenu: _showLinkContextMenu,
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

class _TagColorSection extends StatelessWidget {
  final bool isDark;
  final Color accentColor;
  final int selectedIndex;
  final String folderName;
  final ValueChanged<int> onSelect;

  static const _tagColors = [
    Color(0xFFe17076), // 0 red
    Color(0xFF7bc862), // 1 green
    Color(0xFFe5ca77), // 2 yellow
    Color(0xFF65aadd), // 3 blue
    Color(0xFFa695e7), // 4 purple
    Color(0xFFee7aae), // 5 pink
    Color(0xFF6ec9cb), // 6 cyan
  ];

  const _TagColorSection({
    required this.isDark,
    required this.accentColor,
    required this.selectedIndex,
    required this.folderName,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final noTagColor =
        isDark ? const Color(0xFF4E5B65) : const Color(0xFF9DA4AD);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
          child: Row(
            children: [
              Text(
                'Tag Color',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: accentColor,
                ),
              ),
              if (selectedIndex >= 0 && selectedIndex <= 6) ...[
                const SizedBox(width: 14),
                _TagPreviewBadge(
                  color: _tagColors[selectedIndex],
                  name: folderName.isEmpty ? 'Folder' : folderName,
                  isDark: isDark,
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              const chipCount = 8;
              const chipSize = 30.0;
              final totalWidth = constraints.maxWidth;
              final gap = (totalWidth - chipCount * chipSize) / (chipCount - 1);
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(chipCount, (i) {
                  final isNoTag = i == 7;
                  final chipColor = isNoTag ? noTagColor : _tagColors[i];
                  final isSelected = selectedIndex == i;
                  return _TagColorChip(
                    color: chipColor,
                    isNoTag: isNoTag,
                    isSelected: isSelected,
                    isDark: isDark,
                    onTap: () => onSelect(isSelected ? -1 : i),
                  );
                }),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
          child: Text(
            'Choose a color for the folder tag.',
            style: TextStyle(fontSize: 13, color: subtextColor),
          ),
        ),
      ],
    );
  }
}

class _TagPreviewBadge extends StatelessWidget {
  final Color color;
  final String name;
  final bool isDark;

  const _TagPreviewBadge({
    required this.color,
    required this.name,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        name,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _TagColorChip extends StatefulWidget {
  final Color color;
  final bool isNoTag;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _TagColorChip({
    required this.color,
    required this.isNoTag,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_TagColorChip> createState() => _TagColorChipState();
}

class _TagColorChipState extends State<_TagColorChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      value: widget.isSelected ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(_TagColorChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected != oldWidget.isSelected) {
      if (widget.isSelected) {
        _anim.forward();
      } else {
        _anim.reverse();
      }
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) {
          final t = _anim.value;
          return SizedBox(
            width: 30,
            height: 30,
            child: CustomPaint(
              painter: _TagChipPainter(
                color: widget.color,
                isNoTag: widget.isNoTag,
                selectionProgress: t,
                isDark: widget.isDark,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TagChipPainter extends CustomPainter {
  final Color color;
  final bool isNoTag;
  final double selectionProgress;
  final bool isDark;

  _TagChipPainter({
    required this.color,
    required this.isNoTag,
    required this.selectionProgress,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    if (selectionProgress > 0) {
      final ringPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      final ringRadius = radius;
      canvas.drawCircle(center, ringRadius, ringPaint);

      final fillRadius = radius - 2.0 - 2.0;
      final fillPaint = Paint()..color = color;
      canvas.drawCircle(center, fillRadius, fillPaint);
    } else {
      final fillPaint = Paint()..color = color;
      canvas.drawCircle(center, radius, fillPaint);
    }

    if (isNoTag) {
      final xPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round;
      const xSize = 6.0;
      canvas.drawLine(
        center + const Offset(-xSize / 2, -xSize / 2),
        center + const Offset(xSize / 2, xSize / 2),
        xPaint,
      );
      canvas.drawLine(
        center + const Offset(xSize / 2, -xSize / 2),
        center + const Offset(-xSize / 2, xSize / 2),
        xPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_TagChipPainter old) =>
      color != old.color ||
      isNoTag != old.isNoTag ||
      selectionProgress != old.selectionProgress;
}

class _ShareableLinkSection extends StatelessWidget {
  final bool isDark;
  final Color accentColor;
  final List<ChatlistInviteLink> links;
  final bool loading;
  final bool hasExclusions;
  final VoidCallback onCreateLink;
  final void Function(ChatlistInviteLink) onDeleteLink;
  final void Function(ChatlistInviteLink) onShowLink;
  final void Function(BuildContext, ChatlistInviteLink, Offset) onShowContextMenu;

  const _ShareableLinkSection({
    required this.isDark,
    required this.accentColor,
    required this.links,
    required this.loading,
    required this.hasExclusions,
    required this.onCreateLink,
    required this.onDeleteLink,
    required this.onShowLink,
    required this.onShowContextMenu,
  });

  @override
  Widget build(BuildContext context) {
    final subtextColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final textColor =
        isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final hasLinks = links.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 4),
          child: Text(
            hasLinks ? 'Invite Links' : 'Share Folder',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: accentColor,
            ),
          ),
        ),
        _ShareLinkButton(
          isDark: isDark,
          accentColor: accentColor,
          hasLinks: hasLinks,
          onTap: onCreateLink,
        ),
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          ),
        for (final link in links)
          _InviteLinkRow(
            link: link,
            isDark: isDark,
            textColor: textColor,
            subtextColor: subtextColor,
            onDelete: () => onDeleteLink(link),
            onTapLink: () => onShowLink(link),
            onContextMenu: (pos) => onShowContextMenu(context, link, pos),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
          child: Text(
            hasExclusions
                ? "Folders with exclusions can't have shareable links."
                : 'Create an invite link to let others join this folder.',
            style: TextStyle(fontSize: 13, color: subtextColor),
          ),
        ),
      ],
    );
  }
}

class _ShareLinkButton extends StatelessWidget {
  final bool isDark;
  final Color accentColor;
  final bool hasLinks;
  final VoidCallback onTap;

  const _ShareLinkButton({
    required this.isDark,
    required this.accentColor,
    required this.hasLinks,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hoverColor =
        isDark ? const Color(0xFF202B36) : const Color(0xFFF1F1F1);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: hoverColor,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(21, 11, 20, 9),
          child: Row(
            children: [
              Icon(
                hasLinks ? Icons.add : Icons.link,
                size: 24,
                color: accentColor,
              ),
              const SizedBox(width: 15),
              Text(
                hasLinks ? 'Add Link' : 'Create Link',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: accentColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InviteLinkRow extends StatelessWidget {
  final ChatlistInviteLink link;
  final bool isDark;
  final Color textColor;
  final Color subtextColor;
  final VoidCallback onDelete;
  final VoidCallback onTapLink;
  final void Function(Offset) onContextMenu;

  static const _greenCircle = Color(0xFF4fae4e);

  const _InviteLinkRow({
    required this.link,
    required this.isDark,
    required this.textColor,
    required this.subtextColor,
    required this.onDelete,
    required this.onTapLink,
    required this.onContextMenu,
  });

  @override
  Widget build(BuildContext context) {
    final hoverColor =
        isDark ? const Color(0xFF202B36) : const Color(0xFFF1F1F1);
    final dotsColor =
        isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTapLink,
        hoverColor: hoverColor,
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(9, 4, 0, 0),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: _greenCircle,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.link, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        link.displayName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${link.peerCount} chat${link.peerCount == 1 ? '' : 's'}',
                        style: TextStyle(fontSize: 12, color: subtextColor),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) => onContextMenu(details.globalPosition),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Icon(Icons.more_vert, size: 20, color: dotsColor),
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

class _ShowLinkBox extends StatefulWidget {
  final bool isDark;
  final Color accentColor;
  final ChatlistInviteLink link;
  final FolderInfo folder;

  const _ShowLinkBox({
    required this.isDark,
    required this.accentColor,
    required this.link,
    required this.folder,
  });

  @override
  State<_ShowLinkBox> createState() => _ShowLinkBoxState();
}

class _ShowLinkBoxState extends State<_ShowLinkBox> {
  late Set<String> _selectedPeerIds;
  late Set<String> _initialPeerIds;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedPeerIds = Set<String>.from(widget.link.peerIds);
    _initialPeerIds = Set<String>.from(widget.link.peerIds);
  }

  bool get _hasChanges {
    if (_selectedPeerIds.length != _initialPeerIds.length) return true;
    return !_selectedPeerIds.containsAll(_initialPeerIds);
  }

  bool _isPeerDisabled(ChatInfo chat) {
    if (chat.isBot) return true;
    if (chat.type == ChatType.dm) return true;
    return false;
  }

  String _disabledReason(ChatInfo chat) {
    if (chat.isBot) return 'Bots can\'t be shared via links';
    if (chat.type == ChatType.dm) return 'Private chats can\'t be shared';
    return '';
  }

  void _toggleSelectAll() {
    final chats = _getFolderChats();
    final enabledIds = chats.where((c) => !_isPeerDisabled(c)).map((c) => c.chatId).toSet();
    final allSelected = enabledIds.every(_selectedPeerIds.contains);
    setState(() {
      if (allSelected) {
        _selectedPeerIds.clear();
      } else {
        _selectedPeerIds.addAll(enabledIds);
      }
    });
  }

  List<ChatInfo> _getFolderChats() {
    final chatState = context.read<ChatState>();
    final allChats = chatState.chatsForAccount(widget.folder.chatIds.isNotEmpty
        ? (context.read<AppState>().activeAccount?.id ?? '')
        : '');
    final folderChatIds = widget.folder.chatIds.toSet();
    if (folderChatIds.isEmpty) return allChats;
    return allChats.where((c) => folderChatIds.contains(c.chatId)).toList();
  }

  Future<void> _onSave() async {
    if (_saving) return;
    setState(() => _saving = true);
    final engine = context.read<EngineService>();
    final appState = context.read<AppState>();
    final accountId = appState.activeAccount?.id ?? '';
    final folderId = int.tryParse(widget.folder.id);
    if (accountId.isEmpty || folderId == null) {
      setState(() => _saving = false);
      return;
    }
    final updatedLink = await engine.editFolderInviteLink(
      accountId, folderId, widget.link.slug, _selectedPeerIds.toList(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (updatedLink != null) {
      Navigator.of(context).pop(updatedLink);
    } else {
      showTelegramToast(context, 'Failed to save link changes');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor = widget.isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = widget.isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final dividerColor = widget.isDark ? const Color(0xFF101921) : const Color(0xFFE8E8E8);
    final chats = _getFolderChats();
    final enabledChats = chats.where((c) => !_isPeerDisabled(c)).toList();
    final allSelected = enabledChats.isNotEmpty &&
        enabledChats.every((c) => _selectedPeerIds.contains(c.chatId));

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
                padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
                child: Center(
                  child: SizedBox(
                    width: 74,
                    height: 74,
                    child: Lottie.asset(
                      'assets/animations/filters.json',
                      repeat: false,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'Share a link to let others add the '),
                      TextSpan(
                        text: widget.folder.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const TextSpan(text: ' folder and the chats included in it.'),
                    ],
                  ),
                  style: TextStyle(fontSize: 13, color: subtextColor),
                  textAlign: TextAlign.center,
                ),
              ),
              Container(
                margin: const EdgeInsets.fromLTRB(22, 4, 22, 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: widget.isDark ? const Color(0xFF17212B) : const Color(0xFFF1F1F1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.link.url,
                      style: TextStyle(fontSize: 13, color: textColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _LinkActionButton(
                          label: 'Copy',
                          icon: Icons.copy,
                          accentColor: widget.accentColor,
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: widget.link.url));
                            showTelegramToast(context, 'Link copied');
                          },
                        ),
                        const SizedBox(width: 8),
                        _LinkActionButton(
                          label: 'Share',
                          icon: Icons.share,
                          accentColor: widget.accentColor,
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: widget.link.url));
                            showTelegramToast(context, 'Link copied to share');
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: dividerColor),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Chats',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: widget.accentColor,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _toggleSelectAll,
                      child: Text(
                        allSelected ? 'Deselect All' : 'Select All',
                        style: TextStyle(
                          fontSize: 13,
                          color: widget.accentColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: chats.length,
                  itemExtent: 52,
                  itemBuilder: (ctx, i) {
                    final chat = chats[i];
                    final disabled = _isPeerDisabled(chat);
                    final checked = _selectedPeerIds.contains(chat.chatId);
                    return _ShowLinkPeerRow(
                      chat: chat,
                      isDark: widget.isDark,
                      accentColor: widget.accentColor,
                      checked: checked,
                      disabled: disabled,
                      disabledReason: disabled ? _disabledReason(chat) : '',
                      onToggle: disabled ? null : () {
                        setState(() {
                          if (checked) {
                            _selectedPeerIds.remove(chat.chatId);
                          } else {
                            _selectedPeerIds.add(chat.chatId);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              Divider(height: 1, thickness: 1, color: dividerColor),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_hasChanges) ...[
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text('Cancel', style: TextStyle(color: subtextColor, fontSize: 14)),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _saving ? null : _onSave,
                        style: TextButton.styleFrom(
                          backgroundColor: widget.accentColor,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        child: _saving
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Save', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                    ] else
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          backgroundColor: widget.accentColor,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        child: const Text('Done', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
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

class _ShowLinkPeerRow extends StatelessWidget {
  final ChatInfo chat;
  final bool isDark;
  final Color accentColor;
  final bool checked;
  final bool disabled;
  final String disabledReason;
  final VoidCallback? onToggle;

  const _ShowLinkPeerRow({
    required this.chat,
    required this.isDark,
    required this.accentColor,
    required this.checked,
    required this.disabled,
    required this.disabledReason,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final hoverColor = isDark ? const Color(0xFF202B36) : const Color(0xFFF1F1F1);
    final opacity = disabled ? 0.5 : 1.0;

    return Opacity(
      opacity: opacity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onToggle,
          hoverColor: hoverColor,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(9, 4, 14, 4),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: disabled
                      ? CustomPaint(
                          painter: _DashedCirclePainter(
                            color: subtextColor,
                            dashWidth: 1.5,
                            segments: 11,
                          ),
                          child: Center(
                            child: Icon(
                              chat.isBot ? Icons.smart_toy : Icons.lock,
                              size: 18,
                              color: subtextColor,
                            ),
                          ),
                        )
                      : _PeerAvatar(chat: chat),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        chat.title,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (disabled)
                        Text(
                          disabledReason,
                          style: TextStyle(fontSize: 12, color: subtextColor),
                          maxLines: 1,
                        ),
                    ],
                  ),
                ),
                if (!disabled)
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: checked,
                      onChanged: (_) => onToggle?.call(),
                      activeColor: accentColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
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

class _PeerAvatar extends StatelessWidget {
  final ChatInfo chat;

  const _PeerAvatar({required this.chat});

  @override
  Widget build(BuildContext context) {
    if (chat.avatarPath.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          chat.avatarPath,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorBuilder: (ctx, __, ___) => _fallbackAvatar(ctx),
        ),
      );
    }
    return _fallbackAvatar(context);
  }

  Widget _fallbackAvatar(BuildContext context) {
    final colors = [
      const Color(0xFFE17076),
      const Color(0xFF7BC862),
      context.palette.windowBgActive,
      const Color(0xFFFAA74A),
      const Color(0xFF6EC9CB),
      const Color(0xFF65AADD),
      const Color(0xFFEE7AAE),
    ];
    final idx = chat.title.isNotEmpty ? chat.title.codeUnitAt(0) % colors.length : 0;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: colors[idx], shape: BoxShape.circle),
      child: Center(
        child: Text(
          chat.title.isNotEmpty ? chat.title[0].toUpperCase() : '?',
          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  final Color color;
  final double dashWidth;
  final int segments;

  const _DashedCirclePainter({
    required this.color,
    required this.dashWidth,
    required this.segments,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = dashWidth
      ..style = PaintingStyle.stroke;
    final radius = (size.shortestSide - dashWidth) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final totalAngle = 2 * 3.14159265;
    final gapFraction = 0.3;
    final segAngle = totalAngle / segments;
    final dashAngle = segAngle * (1 - gapFraction);
    for (var i = 0; i < segments; i++) {
      final start = i * segAngle - (totalAngle / 4);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        dashAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter old) =>
      color != old.color || dashWidth != old.dashWidth || segments != old.segments;
}

class _LinkActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;

  const _LinkActionButton({
    required this.label,
    required this.icon,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16, color: accentColor),
      label: Text(label, style: TextStyle(fontSize: 13, color: accentColor)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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

class _EmojiButton extends StatefulWidget {
  final bool isDark;
  final ValueChanged<String> onEmojiSelected;

  const _EmojiButton({
    required this.isDark,
    required this.onEmojiSelected,
  });

  @override
  State<_EmojiButton> createState() => _EmojiButtonState();
}

class _EmojiButtonState extends State<_EmojiButton> {
  bool _hovering = false;

  static const _commonEmoji = [
    '\u{1F4AC}', '\u{2B50}', '\u{1F4E2}', '\u{1F3AE}', '\u{1F4DA}',
    '\u{1F3A8}', '\u{2708}', '\u{1F3C6}', '\u{1F4BC}', '\u{1F3E0}',
    '\u{2764}', '\u{1F451}', '\u{1F338}', '\u{1F389}', '\u{1F4B0}',
    '\u{1F431}', '\u{1F436}', '\u{1F525}', '\u{2705}', '\u{1F4CC}',
    '\u{1F512}', '\u{1F514}', '\u{1F4A1}', '\u{1F4DD}', '\u{1F30D}',
    '\u{1F3B5}', '\u{1F4F7}', '\u{1F4E6}', '\u{26A1}', '\u{1F680}',
  ];

  void _showEmojiPicker() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final offset = box.localToGlobal(Offset.zero);
    final bgColor = widget.isDark ? const Color(0xFF17212B) : Colors.white;
    final headerColor = widget.isDark
        ? const Color(0xFF6C7883)
        : const Color(0xFF999999);

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
            left: offset.dx - 200,
            top: offset.dy + 30,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              color: bgColor,
              child: SizedBox(
                width: 244,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 14, 0, 6),
                        child: Text(
                          'Emoji',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: headerColor,
                          ),
                        ),
                      ),
                      Wrap(
                        children: [
                          for (final emoji in _commonEmoji)
                            GestureDetector(
                              onTap: () => Navigator.of(ctx).pop(emoji),
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: Center(
                                    child: Text(
                                      emoji,
                                      style: const TextStyle(fontSize: 20),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ).then((emoji) {
      if (emoji != null) {
        widget.onEmojiSelected(emoji);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final normalColor = widget.isDark
        ? const Color(0xFF3E546A)
        : const Color(0xFFBBBBBB);
    final hoverColor = widget.isDark
        ? const Color(0xFF4E647A)
        : const Color(0xFFAAAAAA);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _showEmojiPicker,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Center(
            child: Icon(
              Icons.emoji_emotions_outlined,
              size: 20,
              color: _hovering ? hoverColor : normalColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterIconPanel extends StatefulWidget {
  final bool isDark;
  final String selectedIcon;
  final ValueChanged<String> onSelect;

  const _FilterIconPanel({
    required this.isDark,
    required this.selectedIcon,
    required this.onSelect,
  });

  @override
  State<_FilterIconPanel> createState() => _FilterIconPanelState();
}

class _FilterIconPanelState extends State<_FilterIconPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut),
    );
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _animCtrl.dispose();
    super.dispose();
  }

  void _onMouseEnter() {
    _hideTimer?.cancel();
    _hideTimer = null;
  }

  void _onMouseExit() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark ? const Color(0xFF17212B) : Colors.white;
    final headerColor = widget.isDark
        ? const Color(0xFF6C7883)
        : const Color(0xFF999999);

    return MouseRegion(
      onEnter: (_) => _onMouseEnter(),
      onExit: (_) => _onMouseExit(),
      child: AnimatedBuilder(
        animation: _animCtrl,
        builder: (context, child) => Opacity(
          opacity: _fadeAnim.value,
          child: Transform(
            alignment: Alignment.topRight,
            // ignore: deprecated_member_use
            transform: Matrix4.identity()..scale(_scaleAnim.value),
            child: child,
          ),
        ),
        child: Material(
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
                                _kFilterIconOrder[row * 6 + col] ==
                                    widget.selectedIcon,
                            isDark: widget.isDark,
                            onTap: () => widget
                                .onSelect(_kFilterIconOrder[row * 6 + col]),
                          ),
                      ],
                    ),
                ],
              ),
            ),
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
    // dialogsUnreadBgMuted
    final normalColor = widget.isDark
        ? const Color(0xFF3E546A)
        : const Color(0xFFBBBBBB);
    // dialogsUnreadBgMutedOver
    final hoverIconColor = widget.isDark
        ? const Color(0xFF425C72)
        : const Color(0xFFB1B1B1);
    final activeColor = widget.isDark
        ? const Color(0xFF6AB3F3)
        : context.palette.windowBgActive;
    // dialogsBgOver
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
                    ? hoverIconColor
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
                      : context.palette.windowBgActive,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewTypeInfo {
  final String key;
  final String label;
  final IconData icon;
  final Color color;
  const _PreviewTypeInfo(this.key, this.label, this.icon, this.color);
}

class _AddChatsButton extends StatelessWidget {
  final bool isDark;
  final Color accentColor;
  final VoidCallback onTap;

  const _AddChatsButton({
    required this.isDark,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hoverColor = isDark ? const Color(0xFF202B36) : const Color(0xFFF1F1F1);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: hoverColor,
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(13, 0, 22, 0),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentColor,
                  ),
                  child: const Icon(Icons.add, size: 18, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Text(
                  'Add Chats',
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

class _RemoveChatsButton extends StatelessWidget {
  final bool isDark;
  final Color accentColor;
  final VoidCallback onTap;

  const _RemoveChatsButton({
    required this.isDark,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hoverColor = isDark ? const Color(0xFF202B36) : const Color(0xFFF1F1F1);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: hoverColor,
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(13, 0, 22, 0),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentColor,
                  ),
                  child: const Icon(Icons.remove, size: 18, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Text(
                  'Remove Chats',
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

class _FilterChatsPreview extends StatelessWidget {
  final List<_PreviewTypeInfo> types;
  final bool isDark;
  final Color textColor;
  final ValueChanged<String> onRemove;

  const _FilterChatsPreview({
    required this.types,
    required this.isDark,
    required this.textColor,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (types.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final type in types)
          _PreviewRow(
            type: type,
            isDark: isDark,
            textColor: textColor,
            onRemove: () => onRemove(type.key),
          ),
      ],
    );
  }
}

class _PreviewRow extends StatefulWidget {
  final _PreviewTypeInfo type;
  final bool isDark;
  final Color textColor;
  final VoidCallback onRemove;

  const _PreviewRow({
    required this.type,
    required this.isDark,
    required this.textColor,
    required this.onRemove,
  });

  @override
  State<_PreviewRow> createState() => _PreviewRowState();
}

class _PreviewRowState extends State<_PreviewRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final removeBtnColor = widget.isDark
        ? const Color(0xFF6C7883)
        : const Color(0xFF999999);
    final hoverColor = widget.isDark
        ? const Color(0xFF202B36)
        : const Color(0xFFF1F1F1);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Container(
        height: 44,
        color: _hovering ? hoverColor : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 5, 10, 5),
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
                    colors: [
                      widget.type.color,
                      widget.type.color.withValues(alpha: 0.8),
                    ],
                  ),
                ),
                child: Icon(widget.type.icon, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.type.label,
                  style: TextStyle(fontSize: 14, color: widget.textColor),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              SizedBox(
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
                        color: removeBtnColor,
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

class _IncludeTypePicker extends StatefulWidget {
  final bool isDark;
  final Color accentColor;
  final bool isChatList;
  final bool newChats;
  final bool existingChats;
  final bool contacts;
  final bool nonContacts;
  final bool groups;
  final bool channels;
  final bool bots;
  final List<String> selectedChatIds;
  final List<ChatInfo> allChats;

  const _IncludeTypePicker({
    required this.isDark,
    required this.accentColor,
    required this.isChatList,
    required this.newChats,
    required this.existingChats,
    required this.contacts,
    required this.nonContacts,
    required this.groups,
    required this.channels,
    required this.bots,
    required this.selectedChatIds,
    required this.allChats,
  });

  @override
  State<_IncludeTypePicker> createState() => _IncludeTypePickerState();
}

class _IncludeTypePickerState extends State<_IncludeTypePicker> {
  late bool _newChats;
  late bool _existingChats;
  late bool _contacts;
  late bool _nonContacts;
  late bool _groups;
  late bool _channels;
  late bool _bots;
  late Set<String> _selectedIds;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _newChats = widget.newChats;
    _existingChats = widget.existingChats;
    _contacts = widget.contacts;
    _nonContacts = widget.nonContacts;
    _groups = widget.groups;
    _channels = widget.channels;
    _bots = widget.bots;
    _selectedIds = Set<String>.from(widget.selectedChatIds);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ChatInfo> get _filteredChats {
    final q = _searchQuery.toLowerCase();
    final chats = widget.allChats.where((c) => !c.isArchived);
    if (q.isEmpty) return chats.toList();
    return chats.where((c) => c.title.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor = widget.isDark
        ? const Color(0xFFF5F5F5)
        : const Color(0xFF000000);
    final subtextColor = widget.isDark
        ? const Color(0xFF6C7883)
        : const Color(0xFF999999);
    final searchBarBg = widget.isDark
        ? const Color(0xFF213240)
        : const Color(0xFFE2E7EB);
    final searchBarFg = widget.isDark
        ? const Color(0xFF6C818D)
        : const Color(0xFF88949E);

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
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
                child: Text(
                  'Include Chats',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    style: TextStyle(fontSize: 13, color: textColor),
                    decoration: InputDecoration(
                      hintText: 'Search',
                      hintStyle: TextStyle(fontSize: 13, color: subtextColor),
                      prefixIcon: Icon(Icons.search, size: 18, color: subtextColor),
                      filled: true,
                      fillColor: searchBarBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                    ),
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (_searchQuery.isEmpty) ...[
                      Container(
                        height: 28,
                        color: searchBarBg,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: Text(
                          'Chat types',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: searchBarFg),
                        ),
                      ),
                      if (widget.isChatList) ...[
                        _TypeToggleRow(label: 'New Chats', icon: Icons.fiber_new, color: const Color(0xFF7bc862), value: _newChats, isDark: widget.isDark, textColor: textColor, onChanged: (v) => setState(() => _newChats = v)),
                        _TypeToggleRow(label: 'Existing Chats', icon: Icons.chat_bubble, color: const Color(0xFF40a7e3), value: _existingChats, isDark: widget.isDark, textColor: textColor, onChanged: (v) => setState(() => _existingChats = v)),
                      ],
                      _TypeToggleRow(label: 'Contacts', icon: Icons.person, color: const Color(0xFF7bc862), value: _contacts, isDark: widget.isDark, textColor: textColor, onChanged: (v) => setState(() => _contacts = v)),
                      _TypeToggleRow(label: 'Non-Contacts', icon: Icons.person_outline, color: const Color(0xFF6ec9cb), value: _nonContacts, isDark: widget.isDark, textColor: textColor, onChanged: (v) => setState(() => _nonContacts = v)),
                      _TypeToggleRow(label: 'Groups', icon: Icons.group, color: const Color(0xFF7bc862), value: _groups, isDark: widget.isDark, textColor: textColor, onChanged: (v) => setState(() => _groups = v)),
                      _TypeToggleRow(label: 'Channels', icon: Icons.campaign, color: const Color(0xFFe17076), value: _channels, isDark: widget.isDark, textColor: textColor, onChanged: (v) => setState(() => _channels = v)),
                      _TypeToggleRow(label: 'Bots', icon: Icons.smart_toy, color: const Color(0xFFa695e7), value: _bots, isDark: widget.isDark, textColor: textColor, onChanged: (v) => setState(() => _bots = v)),
                    ],
                    Container(
                      height: 28,
                      color: searchBarBg,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Text(
                        'Chats',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: searchBarFg),
                      ),
                    ),
                    for (final chat in _filteredChats)
                      _ChatToggleRow(
                        chat: chat,
                        selected: _selectedIds.contains(chat.chatId),
                        isDark: widget.isDark,
                        textColor: textColor,
                        onChanged: (v) {
                          setState(() {
                            if (v) { _selectedIds.add(chat.chatId); }
                            else { _selectedIds.remove(chat.chatId); }
                          });
                        },
                      ),
                    if (_filteredChats.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(22),
                        child: Text(
                          _searchQuery.isEmpty ? 'No chats available' : 'No chats matching "$_searchQuery"',
                          style: TextStyle(fontSize: 13, color: subtextColor),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Cancel', style: TextStyle(color: subtextColor, fontSize: 14)),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(<String, dynamic>{
                        'newChats': _newChats,
                        'existingChats': _existingChats,
                        'contacts': _contacts,
                        'nonContacts': _nonContacts,
                        'groups': _groups,
                        'channels': _channels,
                        'bots': _bots,
                        'chatIds': _selectedIds.toList(),
                      }),
                      style: TextButton.styleFrom(
                        backgroundColor: widget.accentColor,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      child: const Text('Done', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
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

class _ExcludeTypePicker extends StatefulWidget {
  final bool isDark;
  final Color accentColor;
  final bool excludeMuted;
  final bool excludeArchived;
  final bool excludeRead;
  final List<String> selectedChatIds;
  final List<ChatInfo> allChats;

  const _ExcludeTypePicker({
    required this.isDark,
    required this.accentColor,
    required this.excludeMuted,
    required this.excludeArchived,
    required this.excludeRead,
    required this.selectedChatIds,
    required this.allChats,
  });

  @override
  State<_ExcludeTypePicker> createState() => _ExcludeTypePickerState();
}

class _ExcludeTypePickerState extends State<_ExcludeTypePicker> {
  late bool _excludeMuted;
  late bool _excludeArchived;
  late bool _excludeRead;
  late Set<String> _selectedIds;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _excludeMuted = widget.excludeMuted;
    _excludeArchived = widget.excludeArchived;
    _excludeRead = widget.excludeRead;
    _selectedIds = Set<String>.from(widget.selectedChatIds);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ChatInfo> get _filteredChats {
    final q = _searchQuery.toLowerCase();
    final chats = widget.allChats.where((c) => !c.isArchived);
    if (q.isEmpty) return chats.toList();
    return chats.where((c) => c.title.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor = widget.isDark
        ? const Color(0xFFF5F5F5)
        : const Color(0xFF000000);
    final subtextColor = widget.isDark
        ? const Color(0xFF6C7883)
        : const Color(0xFF999999);
    final searchBarBg = widget.isDark
        ? const Color(0xFF213240)
        : const Color(0xFFE2E7EB);
    final searchBarFg = widget.isDark
        ? const Color(0xFF6C818D)
        : const Color(0xFF88949E);

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
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
                child: Text(
                  'Exclude Chats',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 10),
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    style: TextStyle(fontSize: 13, color: textColor),
                    decoration: InputDecoration(
                      hintText: 'Search',
                      hintStyle: TextStyle(fontSize: 13, color: subtextColor),
                      prefixIcon: Icon(Icons.search, size: 18, color: subtextColor),
                      filled: true,
                      fillColor: searchBarBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                    ),
                  ),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (_searchQuery.isEmpty) ...[
                      Container(
                        height: 28,
                        color: searchBarBg,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: Text(
                          'Chat types',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: searchBarFg),
                        ),
                      ),
                      _TypeToggleRow(label: 'Muted', icon: Icons.volume_off, color: const Color(0xFFa695e7), value: _excludeMuted, isDark: widget.isDark, textColor: textColor, onChanged: (v) => setState(() => _excludeMuted = v)),
                      _TypeToggleRow(label: 'Archived', icon: Icons.archive, color: const Color(0xFF7bc862), value: _excludeArchived, isDark: widget.isDark, textColor: textColor, onChanged: (v) => setState(() => _excludeArchived = v)),
                      _TypeToggleRow(label: 'Read', icon: Icons.done_all, color: const Color(0xFF6ec9cb), value: _excludeRead, isDark: widget.isDark, textColor: textColor, onChanged: (v) => setState(() => _excludeRead = v)),
                    ],
                    Container(
                      height: 28,
                      color: searchBarBg,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Text(
                        'Chats',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: searchBarFg),
                      ),
                    ),
                    for (final chat in _filteredChats)
                      _ChatToggleRow(
                        chat: chat,
                        selected: _selectedIds.contains(chat.chatId),
                        isDark: widget.isDark,
                        textColor: textColor,
                        onChanged: (v) {
                          setState(() {
                            if (v) { _selectedIds.add(chat.chatId); }
                            else { _selectedIds.remove(chat.chatId); }
                          });
                        },
                      ),
                    if (_filteredChats.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(22),
                        child: Text(
                          _searchQuery.isEmpty ? 'No chats available' : 'No chats matching "$_searchQuery"',
                          style: TextStyle(fontSize: 13, color: subtextColor),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Cancel', style: TextStyle(color: subtextColor, fontSize: 14)),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(<String, dynamic>{
                        'excludeMuted': _excludeMuted,
                        'excludeArchived': _excludeArchived,
                        'excludeRead': _excludeRead,
                        'chatIds': _selectedIds.toList(),
                      }),
                      style: TextButton.styleFrom(
                        backgroundColor: widget.accentColor,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      child: const Text('Done', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
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

class _ChatToggleRow extends StatelessWidget {
  final ChatInfo chat;
  final bool selected;
  final bool isDark;
  final Color textColor;
  final ValueChanged<bool> onChanged;

  const _ChatToggleRow({
    required this.chat,
    required this.selected,
    required this.isDark,
    required this.textColor,
    required this.onChanged,
  });

  IconData get _chatIcon {
    if (chat.isBot) return Icons.smart_toy;
    switch (chat.type) {
      case ChatType.dm: return Icons.person;
      case ChatType.group: return Icons.group;
      case ChatType.channel: return Icons.campaign;
      default: return Icons.chat;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hoverColor = isDark ? const Color(0xFF202B36) : const Color(0xFFF1F1F1);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!selected),
        hoverColor: hoverColor,
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(13, 5, 16, 5),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? const Color(0xFF3A4A5A) : const Color(0xFFE0E0E0),
                  ),
                  child: chat.avatarPath.isNotEmpty && File(chat.avatarPath).existsSync()
                      ? ClipOval(child: Image.file(
                          File(chat.avatarPath),
                          fit: BoxFit.cover, width: 34, height: 34,
                          errorBuilder: (_, __, ___) => Icon(_chatIcon, size: 18, color: subtextColor),
                        ))
                      : Icon(_chatIcon, size: 18, color: subtextColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    chat.title,
                    style: TextStyle(fontSize: 14, color: textColor),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: selected,
                    onChanged: (v) => onChanged(v ?? false),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
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

class _SelectedChatsPreview extends StatelessWidget {
  final List<String> chatIds;
  final bool isDark;
  final Color textColor;
  final ValueChanged<String> onRemove;

  const _SelectedChatsPreview({
    required this.chatIds,
    required this.isDark,
    required this.textColor,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (chatIds.isEmpty) return const SizedBox.shrink();
    final chatState = context.watch<ChatState>();
    final accountChats = chatState.chats;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final id in chatIds)
          _SelectedChatRow(
            chatId: id,
            chatName: accountChats.where((c) => c.chatId == id).firstOrNull?.title ?? id,
            isDark: isDark,
            textColor: textColor,
            onRemove: () => onRemove(id),
          ),
      ],
    );
  }
}

class _SelectedChatRow extends StatefulWidget {
  final String chatId;
  final String chatName;
  final bool isDark;
  final Color textColor;
  final VoidCallback onRemove;

  const _SelectedChatRow({
    required this.chatId,
    required this.chatName,
    required this.isDark,
    required this.textColor,
    required this.onRemove,
  });

  @override
  State<_SelectedChatRow> createState() => _SelectedChatRowState();
}

class _SelectedChatRowState extends State<_SelectedChatRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final removeBtnColor = widget.isDark
        ? const Color(0xFF6C7883)
        : const Color(0xFF999999);
    final hoverColor = widget.isDark
        ? const Color(0xFF202B36)
        : const Color(0xFFF1F1F1);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Container(
        height: 44,
        color: _hovering ? hoverColor : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 5, 10, 5),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.isDark ? const Color(0xFF3A4A5A) : const Color(0xFFE0E0E0),
                ),
                child: const Icon(Icons.person, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.chatName,
                  style: TextStyle(fontSize: 14, color: widget.textColor),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              SizedBox(
                width: 34,
                height: 34,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: widget.onRemove,
                    customBorder: const CircleBorder(),
                    child: Center(
                      child: Icon(Icons.close, size: 16, color: removeBtnColor),
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

class _ChatlistFolderRemovalDialog extends StatefulWidget {
  final bool isDark;
  final Color accentColor;
  final FolderInfo folder;

  const _ChatlistFolderRemovalDialog({
    required this.isDark,
    required this.accentColor,
    required this.folder,
  });

  @override
  State<_ChatlistFolderRemovalDialog> createState() =>
      _ChatlistFolderRemovalDialogState();
}

class _ChatlistFolderRemovalDialogState
    extends State<_ChatlistFolderRemovalDialog> {
  Set<String> _selectedPeerIds = {};
  List<ChatInfo> _alwaysChats = [];
  bool _loading = true;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  Future<void> _loadSuggestions() async {
    final appState = context.read<AppState>();
    final engine = context.read<EngineService>();
    final chatState = context.read<ChatState>();
    final accountId = appState.activeAccount?.id ?? '';
    final folderId = int.tryParse(widget.folder.id);
    if (accountId.isEmpty || folderId == null) {
      setState(() => _loading = false);
      return;
    }

    final allChats = chatState.chatsForAccount(accountId);
    final folderChatIds = widget.folder.chatIds.toSet();
    final chats = folderChatIds.isEmpty
        ? <ChatInfo>[]
        : allChats.where((c) => folderChatIds.contains(c.chatId)).toList();

    List<String> suggestedIds = [];
    try {
      suggestedIds =
          await engine.getLeaveChatlistSuggestions(accountId, folderId);
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _alwaysChats = chats;
      _selectedPeerIds = Set<String>.from(suggestedIds);
      _loading = false;
    });
  }

  Future<void> _onLeave() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    final appState = context.read<AppState>();
    final engine = context.read<EngineService>();
    final accountId = appState.activeAccount?.id ?? '';
    final folderId = int.tryParse(widget.folder.id);
    if (accountId.isEmpty || folderId == null) {
      setState(() => _leaving = false);
      return;
    }
    final ok = await engine.leaveChatlistFolder(
      accountId,
      folderId,
      _selectedPeerIds.toList(),
    );
    if (!mounted) return;
    setState(() => _leaving = false);
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      showTelegramToast(context, 'Failed to leave folder');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor =
        widget.isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor =
        widget.isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final dividerColor =
        widget.isDark ? const Color(0xFF101921) : const Color(0xFFE8E8E8);

    final selectedCount = _selectedPeerIds.length;
    final buttonLabel =
        selectedCount > 0 ? 'Remove and leave $selectedCount' : 'Remove';

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
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 8),
                child: Text(
                  'Remove folder',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
                child: Text(
                  'Do you also want to leave the channels and groups that are in this folder?',
                  style: TextStyle(fontSize: 13, color: subtextColor),
                  textAlign: TextAlign.center,
                ),
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (_alwaysChats.isNotEmpty) ...[
                Divider(height: 1, thickness: 1, color: dividerColor),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 6),
                  child: Text(
                    'Chats',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: widget.accentColor,
                    ),
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _alwaysChats.length,
                    itemExtent: 52,
                    itemBuilder: (ctx, i) {
                      final chat = _alwaysChats[i];
                      final checked =
                          _selectedPeerIds.contains(chat.chatId);
                      return _ShowLinkPeerRow(
                        chat: chat,
                        isDark: widget.isDark,
                        accentColor: widget.accentColor,
                        checked: checked,
                        disabled: false,
                        disabledReason: '',
                        onToggle: () {
                          setState(() {
                            if (checked) {
                              _selectedPeerIds.remove(chat.chatId);
                            } else {
                              _selectedPeerIds.add(chat.chatId);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
              Divider(height: 1, thickness: 1, color: dividerColor),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
                child: SizedBox(
                  height: 42,
                  child: TextButton(
                    onPressed: _leaving ? null : _onLeave,
                    style: TextButton.styleFrom(
                      backgroundColor: widget.accentColor,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _leaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            buttonLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
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

class SimpleLimitBox extends StatefulWidget {
  final bool isDark;
  final String title;
  final int current;
  final int limitFree;
  final int limitPremium;
  final bool isPremium;
  final IconData icon;
  final String description;

  const SimpleLimitBox({
    required this.isDark,
    required this.title,
    required this.current,
    required this.limitFree,
    required this.limitPremium,
    required this.isPremium,
    required this.icon,
    required this.description,
  });

  @override
  State<SimpleLimitBox> createState() => _SimpleLimitBoxState();
}

class _SimpleLimitBoxState extends State<SimpleLimitBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _barAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    final target = widget.current / widget.limitPremium;
    _barAnimation = Tween<double>(begin: 0, end: target.clamp(0.0, 1.0))
        .animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark ? const Color(0xFF1E2C3A) : Colors.white;
    final textColor = widget.isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = widget.isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final accentColor = widget.isDark ? const Color(0xFF6AB3F3) : const Color(0xFF168ACD);
    final premiumColor = const Color(0xFFCB7DFF);
    final trackBg = widget.isDark ? const Color(0xFF2B3A48) : const Color(0xFFE0E0E0);
    final limit = widget.isPremium ? widget.limitPremium : widget.limitFree;
    final freeRatio = widget.limitFree / widget.limitPremium;

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: SizedBox(
        width: 364,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 48, color: accentColor),
              const SizedBox(height: 12),
              Text(
                widget.title,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor),
              ),
              const SizedBox(height: 16),
              AnimatedBuilder(
                animation: _barAnimation,
                builder: (context, _) {
                  return Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${widget.current}',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: widget.current >= limit ? const Color(0xFFE53935) : accentColor,
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!widget.isPremium) ...[
                                Icon(Icons.workspace_premium, size: 16, color: premiumColor),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                '$limit',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: subtextColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 6,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: CustomPaint(
                            size: const Size(double.infinity, 6),
                            painter: _LimitBarPainter(
                              progress: _barAnimation.value,
                              freeRatio: freeRatio,
                              isPremium: widget.isPremium,
                              accentColor: accentColor,
                              premiumColor: premiumColor,
                              trackBg: trackBg,
                              overLimit: widget.current >= limit,
                            ),
                          ),
                        ),
                      ),
                      if (!widget.isPremium) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            SizedBox(
                              width: freeRatio * 320,
                              child: Text(
                                'Free',
                                style: TextStyle(fontSize: 11, color: subtextColor),
                                textAlign: TextAlign.right,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              'Premium',
                              style: TextStyle(fontSize: 11, color: premiumColor),
                            ),
                          ],
                        ),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              Text(
                widget.description,
                style: TextStyle(fontSize: 14, color: subtextColor),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (!widget.isPremium)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SizedBox(
                    width: double.infinity,
                    height: 38,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.workspace_premium, size: 18),
                      label: const Text('Increase Limit', style: TextStyle(fontSize: 14)),
                      style: FilledButton.styleFrom(
                        backgroundColor: premiumColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        _showPremiumPurchaseDialog(context, widget.isDark);
                      },
                    ),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                height: 38,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('OK', style: TextStyle(color: accentColor, fontSize: 14)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showPremiumPurchaseDialog(BuildContext context, bool isDark) {
  final bgColor = isDark ? const Color(0xFF1E2C3A) : Colors.white;
  final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
  final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
  final premiumColor = const Color(0xFFCB7DFF);

  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: SizedBox(
        width: 320,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.workspace_premium, size: 48, color: premiumColor),
              const SizedBox(height: 12),
              Text(
                'Telegram Premium',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textColor),
              ),
              const SizedBox(height: 12),
              Text(
                'Subscribe to Telegram Premium in the official Telegram app to increase limits and unlock exclusive features.',
                style: TextStyle(fontSize: 14, color: subtextColor),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 38,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text('OK', style: TextStyle(color: premiumColor, fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _LimitBarPainter extends CustomPainter {
  final double progress;
  final double freeRatio;
  final bool isPremium;
  final Color accentColor;
  final Color premiumColor;
  final Color trackBg;
  final bool overLimit;

  _LimitBarPainter({
    required this.progress,
    required this.freeRatio,
    required this.isPremium,
    required this.accentColor,
    required this.premiumColor,
    required this.trackBg,
    required this.overLimit,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final trackPaint = Paint()..color = trackBg;
    final rr = RRect.fromLTRBR(0, 0, size.width, size.height, const Radius.circular(3));
    canvas.drawRRect(rr, trackPaint);

    if (progress <= 0) return;
    final barWidth = size.width * progress;
    final barColor = overLimit ? const Color(0xFFE53935) : accentColor;
    final barPaint = Paint()..color = barColor;
    final barRr = RRect.fromLTRBR(0, 0, barWidth, size.height, const Radius.circular(3));
    canvas.drawRRect(barRr, barPaint);

    if (!isPremium && progress > freeRatio) {
      final freeWidth = size.width * freeRatio;
      final premiumPaint = Paint()..color = premiumColor.withValues(alpha: 0.6);
      final premRr = RRect.fromLTRBR(freeWidth, 0, barWidth, size.height, Radius.zero);
      canvas.drawRRect(premRr, premiumPaint);
    }
  }

  @override
  bool shouldRepaint(_LimitBarPainter old) =>
      progress != old.progress || overLimit != old.overLimit;
}

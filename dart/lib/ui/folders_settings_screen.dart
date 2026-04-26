import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';
import 'filter_column.dart';
import 'settings_style.dart';

class FoldersSettingsScreen extends StatefulWidget {
  const FoldersSettingsScreen({super.key});

  @override
  State<FoldersSettingsScreen> createState() => _FoldersSettingsScreenState();
}

class _FoldersSettingsScreenState extends State<FoldersSettingsScreen> {
  List<FolderInfo> _folders = [];
  List<FolderInfo> _recommended = [];
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
    setState(() {
      _folders = List.of(chatState.folders);
      _loaded = true;
    });
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
              onTap: () {},
            ),

          // §18.4 Create New Folder button
          _CreateFolderButton(
            isDark: isDark,
            accentColor: accentColor,
            hoverColor: hoverColor,
            onTap: () {},
          ),

          // Divider between folders and recommended
          const SizedBox(height: 7),
          Container(height: 1, color: dividerBg),
          const SizedBox(height: 7),

          // §18.5 Recommended Folders
          if (_recommended.isNotEmpty) ...[
            _SectionTitle(
              text: 'Recommended folders',
              color: sectionTitleColor,
            ),
            for (final rec in _recommended)
              _RecommendedRow(
                folder: rec,
                isDark: isDark,
                hoverColor: hoverColor,
                textColor: textColor,
                subtextColor: subtextColor,
                accentColor: accentColor,
                onAdd: () {},
              ),
            const SizedBox(height: 7),
            Container(height: 1, color: dividerBg),
            const SizedBox(height: 7),
          ],

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

// §18.5 Recommended folder row
class _RecommendedRow extends StatelessWidget {
  final FolderInfo folder;
  final bool isDark;
  final Color hoverColor;
  final Color textColor;
  final Color subtextColor;
  final Color accentColor;
  final VoidCallback onAdd;

  const _RecommendedRow({
    required this.folder,
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
            padding: const EdgeInsets.fromLTRB(20, 0, 10, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        folder.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: onAdd,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(50, 26),
                    maximumSize: const Size(70, 26),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                    backgroundColor: accentColor,
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/chat_state.dart';
import '../models/engine_models.dart';
import '../theme/theme.dart';

/// Dialog for forwarding a message to another chat.
///
/// Shows a searchable list of chats from [ChatState]. Tapping a chat
/// presents a confirmation prompt; confirming returns the selected [ChatInfo].
class ForwardDialog extends StatefulWidget {
  /// The text of the message being forwarded (shown as preview).
  final String messageText;

  /// The title of the chat the message is from.
  final String fromChatTitle;

  /// Called when the user confirms forwarding to a chat.
  final void Function(ChatInfo chat)? onForward;

  const ForwardDialog({
    super.key,
    required this.messageText,
    required this.fromChatTitle,
    this.onForward,
  });

  /// Show the forward dialog and return the selected [ChatInfo], or null if cancelled.
  static Future<ChatInfo?> show(
    BuildContext context, {
    required String messageText,
    required String fromChatTitle,
  }) {
    return showDialog<ChatInfo>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => ForwardDialog(
        messageText: messageText,
        fromChatTitle: fromChatTitle,
      ),
    );
  }

  @override
  State<ForwardDialog> createState() => _ForwardDialogState();
}

class _ForwardDialogState extends State<ForwardDialog> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ChatInfo> _filteredChats(List<ChatInfo> chats) {
    if (_query.isEmpty) return chats;
    final q = _query.toLowerCase();
    return chats.where((c) => c.title.toLowerCase().contains(q)).toList();
  }

  void _onChatTap(BuildContext context, ChatInfo chat) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Forward to ${chat.title}?',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: isDark ? AppColors.darkText : AppColors.lightText,
          ),
        ),
        content: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurfaceAlt : AppColors.lightSurfaceAlt,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            widget.messageText.length > 120
                ? '${widget.messageText.substring(0, 120)}...'
                : widget.messageText,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
            ),
            child: const Text('Forward'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        widget.onForward?.call(chat);
        if (context.mounted) Navigator.of(context).pop(chat);
      }
    });
  }

  Color _avatarColor(String title) {
    // Deterministic color from title hash.
    const colors = [
      AppColors.accent,
      AppColors.online,
      AppColors.warning,
      AppColors.danger,
      AppColors.accentLight,
      AppColors.accentDark,
    ];
    final hash = title.isEmpty ? 0 : title.codeUnits.fold(0, (a, b) => a + b);
    return colors[hash % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chatState = context.watch<ChatState>();
    final allChats = chatState.chats;
    final filtered = _filteredChats(allChats);

    return Dialog(
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Forward message',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDark ? AppColors.darkText : AppColors.lightText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'From: ${widget.fromChatTitle}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      size: 20,
                      color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    splashRadius: 18,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Search bar.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                height: 38,
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _query = v),
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? AppColors.darkText : AppColors.lightText,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search chats...',
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

            const SizedBox(height: 8),

            // Divider.
            Divider(
              height: 1,
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            ),

            // Chat list.
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        _query.isEmpty ? 'No chats available' : 'No chats found',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemBuilder: (context, index) {
                        final chat = filtered[index];
                        final initial = chat.title.isNotEmpty
                            ? chat.title[0].toUpperCase()
                            : '?';
                        final color = _avatarColor(chat.title);
                        final preview = chat.lastMsgText.isNotEmpty
                            ? (chat.lastMsgText.length > 40
                                ? '${chat.lastMsgText.substring(0, 40)}...'
                                : chat.lastMsgText)
                            : null;

                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: color,
                            child: Text(
                              initial,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          title: Text(
                            chat.title,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: isDark ? AppColors.darkText : AppColors.lightText,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: preview != null
                              ? Text(
                                  preview,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? AppColors.darkTextMuted
                                        : AppColors.lightTextMuted,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : null,
                          hoverColor: isDark
                              ? AppColors.darkSurfaceAlt
                              : AppColors.lightSurfaceAlt,
                          onTap: () => _onChatTap(context, chat),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

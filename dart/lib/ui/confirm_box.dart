import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:provider/provider.dart';

import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../bridge/engine_service.dart';
import '../theme/telegram_palette.dart';
import '../l10n/strings.dart';
import 'telegram_toast.dart';
import 'package:uniclient/utils/debug.dart';

// ─── §36.1 Box/Dialog Infrastructure Constants ───────────────────────────────

const double kBoxWidth = 320;
const double kBoxWideWidth = 364;
const EdgeInsets kBoxPadding = EdgeInsets.fromLTRB(24, 14, 24, 8);
const double kBoxRadius = 6;
const double kBoxTitleHeight = 48;
const double kBoxMaxListHeight = 492;
const double kBoxMediumSkip = 20;
const double kBoxLittleSkip = 10;
const Duration kBoxDuration = Duration(milliseconds: 200);
const IconData kBoxButtonCloseIcon = Icons.close;

// ─── showTelegramBox — spec §36.1 animation: 200ms easeOutCirc dim, linear
//     opacity on the box itself ───────────────────────────────────────────────

Future<T?> showTelegramBox<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: kBoxDuration,
    transitionBuilder: (ctx, animation, _, child) {
      final dimAnim = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCirc,
      );
      return Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: FadeTransition(
                opacity: dimAnim,
                child: const ColoredBox(color: Color(0x8A000000)),
              ),
            ),
          ),
          FadeTransition(
            opacity: animation,
            child: Center(child: child),
          ),
        ],
      );
    },
    pageBuilder: (ctx, _, __) => builder(ctx),
  );
}

// ─── TelegramBoxButton ───────────────────────────────────────────────────────

class TelegramBoxButton {
  final String text;
  final VoidCallback? onPressed;
  final bool isDestructive;
  final bool isLeft;

  const TelegramBoxButton({
    required this.text,
    this.onPressed,
    this.isDestructive = false,
    this.isLeft = false,
  });
}

// ─── TelegramBox — reusable box chrome (§36.1) ──────────────────────────────
//
// 48px title bar (16px semibold at (24,13)), scrollable content 24px h-padding,
// right-aligned button row, 320/364px width, 8px radius, Enter confirms.

class TelegramBox extends StatefulWidget {
  final String? title;
  final Widget? titleWidget;
  final Widget? titleTrailing;
  final bool showClose;
  final bool wide;
  final Widget content;
  final List<TelegramBoxButton> buttons;
  final VoidCallback? onConfirm;
  final KeyEventResult Function(FocusNode, KeyEvent)? onKeyEvent;
  final bool scrollableContent;

  const TelegramBox({
    super.key,
    this.title,
    this.titleWidget,
    this.titleTrailing,
    this.showClose = false,
    this.wide = false,
    required this.content,
    this.buttons = const [],
    this.onConfirm,
    this.onKeyEvent,
    this.scrollableContent = true,
  });

  @override
  State<TelegramBox> createState() => _TelegramBoxState();
}

class _TelegramBoxState extends State<TelegramBox> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (widget.onKeyEvent != null) {
      final result = widget.onKeyEvent!(node, event);
      if (result == KeyEventResult.handled) return result;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (widget.onConfirm != null) {
        widget.onConfirm!();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final width = widget.wide ? kBoxWideWidth : kBoxWidth;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: Material(
        color: p.boxBg,
        borderRadius: BorderRadius.circular(kBoxRadius),
        elevation: 4,
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.title != null || widget.titleWidget != null) _buildTitleBar(p.boxTitleFg),
              Flexible(
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxHeight: kBoxMaxListHeight),
                  child: widget.scrollableContent
                      ? SingleChildScrollView(child: widget.content)
                      : widget.content,
                ),
              ),
              if (widget.buttons.isNotEmpty) _buildButtonRow(p),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBar(Color fg) {
    return SizedBox(
      height: kBoxTitleHeight,
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 13, 0, 0),
              child: Align(
                alignment: Alignment.topLeft,
                child: widget.titleWidget ?? Text(
                  widget.title ?? '',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
            ),
          ),
          if (widget.titleTrailing != null) widget.titleTrailing!,
          if (widget.showClose)
            SizedBox(
              width: kBoxTitleHeight,
              height: kBoxTitleHeight,
              child: IconButton(
                icon: Icon(kBoxButtonCloseIcon, size: 20, color: fg),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildButtonRow(TelegramPalette p) {
    final left = widget.buttons.where((b) => b.isLeft).toList();
    final right = widget.buttons.where((b) => !b.isLeft).toList();

    Widget btn(TelegramBoxButton b) {
      final fg = b.isDestructive ? p.attentionButtonFg : p.windowBgActive;
      return ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 30),
        child: SizedBox(
          height: 34,
          child: TextButton(
            onPressed: b.onPressed,
            style: TextButton.styleFrom(
              foregroundColor: fg,
              overlayColor:
                  b.isDestructive ? fg.withOpacity(0.1) : null,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text(b.text),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 10, 10, 10),
      child: Row(
        children: [
          for (final b in left) ...[btn(b), const SizedBox(width: 4)],
          const Spacer(),
          for (int i = 0; i < right.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            btn(right[i]),
          ],
        ],
      ),
    );
  }
}

// ─── showConfirmBox — §36.2 ConfirmBox ───────────────────────────────────────

Future<void> showConfirmBox(
  BuildContext context, {
  required String text,
  String? confirmText,
  String? cancelText,
  VoidCallback? onConfirm,
  VoidCallback? onCancel,
  bool isDestructive = false,
  String? title,
  bool inform = false,
  bool strictCancel = false,
  void Function(String)? labelFilter,
  EdgeInsets? labelPadding,
  bool boldMarkup = false,
}) {
  bool confirmed = false;
  bool explicitCancel = false;

  return showTelegramBox<void>(
    context: context,
    builder: (ctx) {
      final textFg = ctx.palette.boxTextFg;
      final linkFg = ctx.palette.windowActiveTextFg;

      void confirm() {
        confirmed = true;
        Navigator.of(ctx).pop();
        onConfirm?.call();
      }

      void cancel() {
        explicitCancel = true;
        Navigator.of(ctx).pop();
        if (!strictCancel) onCancel?.call();
      }

      final defaultPadding = title != null
          ? EdgeInsets.fromLTRB(
              kBoxPadding.left, 0, kBoxPadding.right, kBoxPadding.bottom)
          : kBoxPadding;

      final bodyWidget = labelFilter != null
          ? _buildLinkableText(text, textFg, linkFg, labelFilter)
          : boldMarkup
              ? _buildBoldText(text, textFg)
              : Text(
                  text,
                  style: TextStyle(fontSize: 14, height: 22 / 14, color: textFg),
                );

      return TelegramBox(
        title: title,
        onConfirm: confirm,
        content: Padding(
          padding: labelPadding ?? defaultPadding,
          child: bodyWidget,
        ),
        buttons: [
          if (!inform)
            TelegramBoxButton(
              text: cancelText ?? 'Cancel',
              onPressed: cancel,
            ),
          TelegramBoxButton(
            text: confirmText ?? 'OK',
            isDestructive: isDestructive,
            onPressed: confirm,
          ),
        ],
      );
    },
  ).then((_) {
    if (!confirmed && !explicitCancel && !strictCancel) {
      onCancel?.call();
    }
  });
}

Widget _buildLinkableText(
  String text,
  Color textFg,
  Color linkFg,
  void Function(String) onLinkTap,
) {
  final urlPattern = RegExp(r'https?://\S+');
  final matches = urlPattern.allMatches(text);

  if (matches.isEmpty) {
    return Text(
      text,
      style: TextStyle(fontSize: 14, height: 22 / 14, color: textFg),
    );
  }

  final spans = <InlineSpan>[];
  int lastEnd = 0;
  for (final match in matches) {
    if (match.start > lastEnd) {
      spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
    }
    final url = match.group(0)!;
    spans.add(TextSpan(
      text: url,
      style: TextStyle(color: linkFg, decoration: TextDecoration.underline),
      recognizer: TapGestureRecognizer()..onTap = () => onLinkTap(url),
    ));
    lastEnd = match.end;
  }
  if (lastEnd < text.length) {
    spans.add(TextSpan(text: text.substring(lastEnd)));
  }

  return Text.rich(
    TextSpan(
      style: TextStyle(fontSize: 14, height: 22 / 14, color: textFg),
      children: spans,
    ),
  );
}

// Renders `**bold**` markup as bold spans (Telegram `tr::rich` semantics), used
// e.g. for the paid-post deletion warning whose lang strings embed **TON** /
// **24 hours** (lang.strings:5420-5421). Plain text falls through unchanged.
Widget _buildBoldText(String text, Color textFg) {
  final boldPattern = RegExp(r'\*\*(.+?)\*\*');
  final matches = boldPattern.allMatches(text);
  final baseStyle = TextStyle(fontSize: 14, height: 22 / 14, color: textFg);

  if (matches.isEmpty) {
    return Text(text, style: baseStyle);
  }

  final spans = <InlineSpan>[];
  int lastEnd = 0;
  for (final match in matches) {
    if (match.start > lastEnd) {
      spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
    }
    spans.add(TextSpan(
      text: match.group(1),
      style: const TextStyle(fontWeight: FontWeight.w600),
    ));
    lastEnd = match.end;
  }
  if (lastEnd < text.length) {
    spans.add(TextSpan(text: text.substring(lastEnd)));
  }

  return Text.rich(TextSpan(style: baseStyle, children: spans));
}

// ─── Delete / Leave ConfirmBox — §36.2 destructive variant ───────────────────

enum DeleteBoxMode { singleMessage, bulkMessages, clearHistory, leaveChat, deleteTopic, dateRange }

class DeleteConfirmResult {
  final bool confirmed;
  final bool revoke;
  final bool banUser;
  final bool reportSpam;
  final bool deleteAll;
  final bool rememberRevoke;
  final bool openAutoDelete;
  final bool blockBot;
  final bool removeFromFolders;

  const DeleteConfirmResult({
    this.confirmed = false,
    this.revoke = false,
    this.banUser = false,
    this.reportSpam = false,
    this.deleteAll = false,
    this.rememberRevoke = false,
    this.openAutoDelete = false,
    this.blockBot = false,
    this.removeFromFolders = false,
  });
}

enum PaidPostType { stars, ton }

/// `stars_suggested_post_age_min` app-config default (main_app_config.cpp:249-251),
/// expressed in milliseconds to match CachedMessage.timestamp (Unix ms).
const int kSuggestedPostAgeMinMs = 86400 * 1000;

/// Computes the paid-suggested-post delete warning for a set of messages, mirroring
/// `DeleteMessagesBox::paidPostType` (delete_messages_box.cpp:527-548): a recent
/// (now < date, or now-date ≤ the suggested-post age window) paid suggested post
/// triggers the warning, with Ton taking precedence over Stars. Returns null when no
/// message warrants a warning.
PaidPostType? computePaidPostWarning(Iterable<CachedMessage> messages) {
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  PaidPostType? result;
  for (final m in messages) {
    if (m.paidPostType == 0) continue;
    if (m.timestamp > nowMs || nowMs - m.timestamp <= kSuggestedPostAgeMinMs) {
      if (m.paidPostType == 2) return PaidPostType.ton; // Ton wins immediately
      if (m.paidPostType == 1) result = PaidPostType.stars;
    }
  }
  return result;
}

Future<DeleteConfirmResult> showDeleteConfirmBox(
  BuildContext context, {
  required DeleteBoxMode mode,
  ChatType chatType = ChatType.dm,
  String peerName = '',
  int messageCount = 1,
  bool canRevoke = false,
  bool showModeratePanel = false,
  bool isSavedMessages = false,
  bool isSavedMusic = false,
  bool isScheduled = false,
  bool isPaidPost = false,
  PaidPostType paidPostType = PaidPostType.stars,
  int messagesTTL = 0,
  bool isBot = false,
  bool isInFolder = false,
  String peerAvatarPath = '',
  String? moderateFromId,
  String? moderateFromName,
  String? chatId,
  String? accountId,
  DateTime? firstDayToDelete,
  DateTime? lastDayToDelete,
}) {
  return showTelegramBox<DeleteConfirmResult>(
    context: context,
    builder: (ctx) => _DeleteContent(
      mode: mode,
      chatType: chatType,
      peerName: peerName,
      messageCount: messageCount,
      canRevoke: canRevoke,
      showModeratePanel: showModeratePanel,
      isSavedMessages: isSavedMessages,
      isSavedMusic: isSavedMusic,
      isScheduled: isScheduled,
      isPaidPost: isPaidPost,
      paidPostType: paidPostType,
      messagesTTL: messagesTTL,
      isBot: isBot,
      isInFolder: isInFolder,
      peerAvatarPath: peerAvatarPath,
      moderateFromId: moderateFromId,
      moderateFromName: moderateFromName,
      chatId: chatId,
      accountId: accountId,
      firstDayToDelete: firstDayToDelete,
      lastDayToDelete: lastDayToDelete,
    ),
  ).then((r) => r ?? const DeleteConfirmResult());
}

class _DeleteContent extends StatefulWidget {
  final DeleteBoxMode mode;
  final ChatType chatType;
  final String peerName;
  final int messageCount;
  final bool canRevoke;
  final bool showModeratePanel;
  final bool isSavedMessages;
  final bool isSavedMusic;
  final bool isScheduled;
  final bool isPaidPost;
  final PaidPostType paidPostType;
  final int messagesTTL;
  final bool isBot;
  final bool isInFolder;
  final String peerAvatarPath;
  final String? moderateFromId;
  final String? moderateFromName;
  final String? chatId;
  final String? accountId;
  final DateTime? firstDayToDelete;
  final DateTime? lastDayToDelete;

  const _DeleteContent({
    required this.mode,
    required this.chatType,
    required this.peerName,
    required this.messageCount,
    required this.canRevoke,
    required this.showModeratePanel,
    required this.isSavedMessages,
    this.isSavedMusic = false,
    this.isScheduled = false,
    this.isPaidPost = false,
    this.paidPostType = PaidPostType.stars,
    this.messagesTTL = 0,
    this.isBot = false,
    this.isInFolder = false,
    this.peerAvatarPath = '',
    this.moderateFromId,
    this.moderateFromName,
    this.chatId,
    this.accountId,
    this.firstDayToDelete,
    this.lastDayToDelete,
  });

  @override
  State<_DeleteContent> createState() => _DeleteContentState();
}

class _DeleteContentState extends State<_DeleteContent> {
  late bool _revokeDefault;
  late bool _revoke;
  bool _revokeRemember = false;
  bool _banUser = false;
  bool _reportSpam = false;
  bool _deleteAll = false;
  bool _initialized = false;
  bool _confirmedPaidPost = false;
  int _totalFromSender = 0;
  bool _countLoading = false;
  bool _blockBot = false;
  bool _removeFromFolders = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final appState = context.read<AppState>();
      _revokeDefault = !appState.deleteOnlyForYouRemembered;
      _revoke = _revokeDefault;
      _fetchModerateCount(appState);
    }
  }

  void _fetchModerateCount(AppState appState) {
    if (!widget.showModeratePanel) return;
    final fromId = widget.moderateFromId;
    final chatId = widget.chatId;
    final accountId = widget.accountId ?? appState.activeAccountId;
    if (fromId == null || chatId == null) return;
    setState(() => _countLoading = true);
    appState.engine.searchMessagesFromCount(accountId, chatId, fromId).then((count) {
      if (mounted) {
        setState(() {
          _totalFromSender = count;
          _countLoading = false;
        });
      }
    }).catchError((_) {
      if (mounted) {
        setState(() => _countLoading = false);
      }
    });
  }

  String get _bodyText {
    final name = widget.peerName;
    switch (widget.mode) {
      case DeleteBoxMode.singleMessage:
        if (widget.isSavedMusic) {
          return 'Are you sure you want to remove this track from your Saved Music?';
        }
        return 'Are you sure you want to delete this message?';
      case DeleteBoxMode.bulkMessages:
        if (widget.isSavedMusic) {
          final n = widget.messageCount;
          return n == 1
              ? 'Are you sure you want to remove this track from your Saved Music?'
              : 'Are you sure you want to remove $n tracks from your Saved Music?';
        }
        final n = widget.messageCount;
        if (n == 1) return 'Are you sure you want to delete this message?';
        return 'Are you sure you want to delete $n messages?';
      case DeleteBoxMode.clearHistory:
        if (widget.isSavedMessages) {
          return 'Are you sure you want to delete your Saved Messages?';
        }
        switch (widget.chatType) {
          case ChatType.channel:
            return 'Are you sure you want to delete all message history in "$name"?';
          case ChatType.group:
          case ChatType.topic:
            return 'Are you sure you want to delete all message history in "$name"?';
          case ChatType.dm:
          default:
            return 'Are you sure you want to delete all message history with $name?';
        }
      case DeleteBoxMode.leaveChat:
        if (widget.isSavedMessages) {
          return 'Are you sure you want to delete your Saved Messages?';
        }
        switch (widget.chatType) {
          case ChatType.channel:
            return 'Are you sure you want to leave this channel?';
          case ChatType.group:
          case ChatType.topic:
            return 'Are you sure you want to delete and leave "$name"?';
          case ChatType.dm:
          default:
            return 'Are you sure you want to delete all message history with $name?';
        }
      case DeleteBoxMode.deleteTopic:
        return 'Are you sure you want to delete the topic "$name"?';
      case DeleteBoxMode.dateRange:
        final first = widget.firstDayToDelete;
        final last = widget.lastDayToDelete;
        if (first != null && last != null && first != last) {
          final f = '${first.day}/${first.month}/${first.year}';
          final l = '${last.day}/${last.month}/${last.year}';
          return 'Are you sure you want to delete all messages from $f to $l?';
        }
        if (first != null) {
          final f = '${first.day}/${first.month}/${first.year}';
          return 'Are you sure you want to delete all messages from $f?';
        }
        return 'Are you sure you want to delete messages for the selected dates?';
    }
  }

  String get _confirmLabel {
    switch (widget.mode) {
      case DeleteBoxMode.leaveChat:
        if (widget.chatType == ChatType.channel ||
            widget.chatType == ChatType.group ||
            widget.chatType == ChatType.topic) {
          return _revoke ? 'Delete' : 'Leave';
        }
        return 'Delete';
      case DeleteBoxMode.clearHistory:
      case DeleteBoxMode.deleteTopic:
      case DeleteBoxMode.dateRange:
        return 'Delete';
      case DeleteBoxMode.singleMessage:
      case DeleteBoxMode.bulkMessages:
        if (widget.isSavedMusic) return 'Remove';
        if (!_deleteAll || _countLoading) return 'Delete';
        final count = _totalFromSender > 0
            ? _totalFromSender
            : (widget.messageCount > 0 ? widget.messageCount : 0);
        final suffix = count > 0 ? ' ($count)' : '';
        return 'Delete$suffix';
    }
  }

  String? get _revokeLabel {
    if (!widget.canRevoke) return null;
    if (widget.isScheduled || widget.isSavedMusic) return null;
    if (_revokeJustClearForChannel) return null;
    // AyuGram shows the revoke checkbox for per-message deletes (revokeText) AND
    // for full-history wipes — clearHistory / deleteConversation — whenever
    // canRevokeFullHistory() (delete_messages_box.cpp:166-181 &
    // moderate_messages_box.cpp:998-1018). The label is per-user for a DM,
    // "for everyone" otherwise.
    switch (widget.mode) {
      case DeleteBoxMode.singleMessage:
      case DeleteBoxMode.bulkMessages:
      case DeleteBoxMode.clearHistory:
      case DeleteBoxMode.leaveChat:
        if (widget.chatType == ChatType.dm) {
          return 'Also delete for ${widget.peerName}';
        }
        return 'Also delete for everyone';
      case DeleteBoxMode.deleteTopic:
      case DeleteBoxMode.dateRange:
        return null;
    }
  }

  void _confirm() {
    if (widget.isPaidPost && !_confirmedPaidPost) {
      _showPaidPostWarning();
      return;
    }
    _doConfirm();
  }

  void _doConfirm() {
    if (_revokeRemember) {
      final appState = context.read<AppState>();
      appState.deleteOnlyForYouRemembered = !_revoke;
    }
    final isChannel = widget.chatType == ChatType.channel;
    Navigator.of(context).pop(DeleteConfirmResult(
      confirmed: true,
      revoke: _revokeJustClearForChannel ? true : _revoke,
      banUser: _banUser,
      reportSpam: _reportSpam,
      deleteAll: _deleteAll,
      rememberRevoke: _revokeRemember,
      blockBot: _blockBot,
      removeFromFolders: _removeFromFolders,
    ));
  }

  bool get _revokeJustClearForChannel =>
      widget.mode == DeleteBoxMode.clearHistory &&
      widget.chatType == ChatType.channel;

  void _showPaidPostWarning() {
    final isTon = widget.paidPostType == PaidPostType.ton;
    showConfirmBox(
      context,
      title: isTon
          ? TrStrings.lngSuggestWarnTitleTon()
          : TrStrings.lngSuggestWarnTitleStars(),
      text: isTon
          ? TrStrings.lngSuggestWarnTextTon()
          : TrStrings.lngSuggestWarnTextStars(),
      boldMarkup: true,
      confirmText: TrStrings.lngSuggestWarnDeleteAnyway(),
      isDestructive: true,
      onConfirm: () {
        _confirmedPaidPost = true;
        _doConfirm();
      },
    );
  }

  bool get _showAutoDeleteLink =>
      widget.mode == DeleteBoxMode.clearHistory &&
      (widget.chatType == ChatType.dm ||
       widget.chatType == ChatType.group);

  String get _autoDeleteLinkText =>
      widget.messagesTTL > 0
          ? 'Edit auto-delete settings'
          : 'Enable auto-delete';

  // AyuGram maybeChatsFiltersCheckbox gate (moderate_messages_box.cpp:1045-1051):
  // history = (isBot || !maybeUser) ? owner().history(peer) : nullptr, then only if
  // removeFromChatsFilters(history) is non-empty. In Dart terms: a bot OR a non-user peer
  // (group/channel/topic — never a plain user DM), and only when the chat is in ≥1 folder.
  bool get _showRemoveFromFoldersCheckbox {
    if (widget.mode != DeleteBoxMode.leaveChat) return false;
    if (!widget.isInFolder) return false;
    return widget.isBot || widget.chatType != ChatType.dm;
  }

  // AyuGram label selection (moderate_messages_box.cpp:1057-1063):
  // bot → remove_bot; broadcast channel (isChannel && !isMegagroup) → remove_channel;
  // otherwise (group/megagroup) → remove_group.
  String get _removeFromFoldersLabel {
    if (widget.isBot) return TrStrings.lngFiltersCheckboxRemoveBot();
    if (widget.chatType == ChatType.channel) {
      return TrStrings.lngFiltersCheckboxRemoveChannel();
    }
    return TrStrings.lngFiltersCheckboxRemoveGroup();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textFg = p.boxTextFg;
    final checkClr = p.windowBgActive;
    final linkFg = p.windowActiveTextFg;

    final blockEnter = widget.mode == DeleteBoxMode.clearHistory ||
        widget.mode == DeleteBoxMode.leaveChat ||
        widget.mode == DeleteBoxMode.deleteTopic ||
        widget.mode == DeleteBoxMode.dateRange;

    final showUserpic = widget.mode == DeleteBoxMode.leaveChat && !widget.isSavedMessages;

    return TelegramBox(
      onConfirm: blockEnter ? null : _confirm,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showUserpic) ...[
            const SizedBox(height: 12),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: widget.peerAvatarPath.isNotEmpty
                        ? FileImage(File(widget.peerAvatarPath))
                        : null,
                    backgroundColor: p.windowBgActive,
                    child: widget.peerAvatarPath.isEmpty
                        ? Text(
                            widget.peerName.isNotEmpty ? widget.peerName[0].toUpperCase() : '?',
                            style: const TextStyle(fontSize: 18, color: Colors.white),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      // AyuGram DeleteChatBox title (moderate_messages_box.cpp:970-979):
                      // a user/DM shows the action "Delete chat", groups/channels
                      // show the peer name (Saved Messages is handled by the
                      // isSavedMessages branch that hides this userpic block).
                      widget.chatType == ChatType.dm
                          ? TrStrings.lngProfileDeleteConversation()
                          : widget.peerName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textFg,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Padding(
            padding: kBoxPadding,
            child: Text(
              _bodyText,
              style: TextStyle(fontSize: 14, height: 22 / 14, color: textFg),
            ),
          ),
          if (widget.showModeratePanel) ...[
            const SizedBox(height: kBoxMediumSkip),
            _checkbox('Ban User', _banUser,
                (v) => setState(() => _banUser = v ?? false), checkClr, textFg),
            const SizedBox(height: kBoxLittleSkip),
            _checkbox(
                'Report Spam',
                _reportSpam,
                (v) => setState(() => _reportSpam = v ?? false),
                checkClr,
                textFg),
            const SizedBox(height: kBoxLittleSkip),
            _checkbox(
              'Delete All from ${widget.moderateFromName ?? widget.peerName}',
              _deleteAll,
              (v) => setState(() => _deleteAll = v ?? false),
              checkClr,
              textFg,
            ),
          ],
          if (_revokeLabel != null) ...[
            const SizedBox(height: kBoxMediumSkip),
            _checkbox(_revokeLabel!, _revoke,
                (v) => setState(() => _revoke = v ?? false), checkClr, textFg),
            AnimatedSize(
              duration: kBoxDuration,
              alignment: Alignment.topCenter,
              child: _revoke != _revokeDefault
                  ? Padding(
                      padding: const EdgeInsets.only(top: kBoxLittleSkip),
                      child: _checkbox('Remember this choice', _revokeRemember,
                          (v) => setState(() => _revokeRemember = v ?? false), checkClr, textFg),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
          // "Stop and block bot" — AyuGram maybeBotCheckbox (moderate_messages_box.cpp:1020-1032),
          // shown for any bot peer regardless of folder membership.
          if (widget.isBot && widget.mode == DeleteBoxMode.leaveChat) ...[
            const SizedBox(height: kBoxMediumSkip),
            _checkbox(TrStrings.lngProfileBlockBot(), _blockBot,
                (v) => setState(() => _blockBot = v ?? false), checkClr, textFg),
          ],
          // "Remove {bot|group|channel} from all folders" — AyuGram maybeChatsFiltersCheckbox
          // (moderate_messages_box.cpp:1045-1066): shown for a bot OR a group/channel (never a
          // plain user DM), and only when the chat is actually in at least one folder. The label
          // is chosen by entity type.
          if (_showRemoveFromFoldersCheckbox) ...[
            SizedBox(height: widget.isBot ? kBoxLittleSkip : kBoxMediumSkip),
            _checkbox(_removeFromFoldersLabel, _removeFromFolders,
                (v) => setState(() => _removeFromFolders = v ?? false), checkClr, textFg),
          ],
          if (_showAutoDeleteLink) ...[
            const SizedBox(height: kBoxMediumSkip),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).pop(
                    const DeleteConfirmResult(openAutoDelete: true),
                  );
                },
                child: Text(
                  _autoDeleteLinkText,
                  style: TextStyle(
                    fontSize: 14,
                    color: linkFg,
                    decoration: TextDecoration.underline,
                    decorationColor: linkFg,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      buttons: [
        TelegramBoxButton(
          text: 'Cancel',
          onPressed: () =>
              Navigator.of(context).pop(const DeleteConfirmResult()),
        ),
        TelegramBoxButton(
          text: _confirmLabel,
          isDestructive: true,
          onPressed: _confirm,
        ),
      ],
    );
  }

  Widget _checkbox(
    String label,
    bool value,
    ValueChanged<bool?> onChanged,
    Color checkColor,
    Color textColor,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: InkWell(
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
              child: Text(
                label,
                style: TextStyle(fontSize: 14, color: textColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── showSingleChoiceBox — §36.5 SingleChoiceBox ────────────────────────────

Future<int?> showSingleChoiceBox(
  BuildContext context, {
  required String title,
  required List<String> options,
  int initialSelection = 0,
  ValueChanged<int>? onChanged,
}) {
  return showTelegramBox<int>(
    context: context,
    builder: (ctx) => _SingleChoiceContent(
      title: title,
      options: options,
      initialSelection: initialSelection,
      onChanged: onChanged,
    ),
  );
}

class _SingleChoiceContent extends StatefulWidget {
  final String title;
  final List<String> options;
  final int initialSelection;
  final ValueChanged<int>? onChanged;

  const _SingleChoiceContent({
    required this.title,
    required this.options,
    required this.initialSelection,
    this.onChanged,
  });

  @override
  State<_SingleChoiceContent> createState() => _SingleChoiceContentState();
}

class _SingleChoiceContentState extends State<_SingleChoiceContent> {
  late int _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSelection;
  }

  void _select(int index) {
    widget.onChanged?.call(index);
    Navigator.of(context).pop(index);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textFg = p.boxTextFg;
    final accentFg = p.windowBgActive;
    final hoverBg = p.windowBgOver;

    return TelegramBox(
      title: widget.title,
      content: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(widget.options.length, (i) {
            return _RadioRow(
              label: widget.options[i],
              selected: _selected == i,
              textColor: textFg,
              accentColor: accentFg,
              hoverColor: hoverBg,
              onTap: () => _select(i),
            );
          }),
        ),
      ),
      buttons: const [],
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
    return InkWell(
      onTap: onTap,
      hoverColor: hoverColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Radio<bool>(
                value: true,
                groupValue: selected,
                onChanged: (_) => onTap(),
                activeColor: accentColor,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Auto-Delete Timer Box ──────────────────────────────────────────────────

// AyuGram indexToPeriod (auto_delete_settings.cpp:221-231): disable / 1 day /
// 1 week / 1 month, where "1 month" is 31 days (NOT 30) → 2678400s.
const List<int> _kTtlPeriods = [0, 86400, 7 * 86400, 31 * 86400];

// SliderForTTL geometry (chat.style:800-811 defaultSliderForTTL).
const double _kTtlPointSize = 6;
const double _kTtlChosenSize = 12;
const double _kTtlSkip = 8;
const double _kTtlStroke = 2;
const double _kTtlFontSize = 13;
const double _kTtlLabelHeight = 17;

Future<void> showAutoDeleteTimerBox(
  BuildContext context, {
  required EngineService engine,
  required String accountId,
  required String chatId,
  int currentTTL = 0,
  ChatType chatType = ChatType.dm,
  String peerName = '',
}) {
  return showTelegramBox<void>(
    context: context,
    builder: (ctx) => _AutoDeleteContent(
      engine: engine,
      accountId: accountId,
      chatId: chatId,
      currentTTL: currentTTL,
      chatType: chatType,
      peerName: peerName,
    ),
  );
}

class _AutoDeleteContent extends StatefulWidget {
  final EngineService engine;
  final String accountId;
  final String chatId;
  final int currentTTL;
  final ChatType chatType;
  final String peerName;

  const _AutoDeleteContent({
    required this.engine,
    required this.accountId,
    required this.chatId,
    required this.currentTTL,
    required this.chatType,
    required this.peerName,
  });

  @override
  State<_AutoDeleteContent> createState() => _AutoDeleteContentState();
}

class _AutoDeleteContentState extends State<_AutoDeleteContent> {
  late int _selected;

  @override
  void initState() {
    super.initState();
    _selected = _periodToIndex(widget.currentTTL);
  }

  // AyuGram periodToIndex (auto_delete_settings.cpp:210-220).
  int _periodToIndex(int period) {
    if (period == 0) return 0;
    if (period < 2 * 86400) return 1;
    if (period < 8 * 86400) return 2;
    return 3;
  }

  String get _aboutText {
    final about1 = switch (widget.chatType) {
      ChatType.dm => TrStrings.lngTtlEditAbout(widget.peerName),
      ChatType.channel => TrStrings.lngTtlEditAboutChannel(),
      _ => TrStrings.lngTtlEditAboutGroup(),
    };
    final about2 = TrStrings.lngTtlEditAbout2(TrStrings.lngTtlEditAbout2Link());
    return '$about1\n\n$about2';
  }

  void _save() {
    widget.engine.setHistoryTTL(widget.accountId, widget.chatId, _kTtlPeriods[_selected]);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final labels = [
      TrStrings.lngManageMessagesTtlDisable(),
      TrStrings.lngManageMessagesTtlAfter1(),
      TrStrings.lngManageMessagesTtlAfter2(),
      TrStrings.lngManageMessagesTtlAfter3(),
    ];

    return TelegramBox(
      title: TrStrings.lngManageMessagesTtlTitle(),
      scrollableContent: false,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, kBoxMediumSkip),
            child: _TTLSlider(
              labels: labels,
              selected: _selected,
              textFg: p.windowSubTextFg,
              activeFg: p.mediaPlayerActiveFg,
              inactiveFg: p.mediaPlayerInactiveFg,
              onChanged: (i) => setState(() => _selected = i),
            ),
          ),
          // DividerLabel (auto_delete_settings.cpp:248-256): explanatory text on
          // a full-width divider band.
          Container(
            width: double.infinity,
            color: p.boxDividerBg,
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
            child: Text(
              _aboutText,
              style: TextStyle(
                fontSize: 13,
                height: 18 / 13,
                color: p.windowSubTextFg,
              ),
            ),
          ),
        ],
      ),
      buttons: [
        TelegramBoxButton(
          text: TrStrings.lngCancel(),
          onPressed: () => Navigator.of(context).pop(),
        ),
        TelegramBoxButton(
          text: TrStrings.lngSettingsSave(),
          onPressed: _save,
        ),
      ],
    );
  }
}

// Draggable TTL slider — port of AyuGram CreateSliderForTTL
// (auto_delete_settings.cpp:19-184). Labels on top, a row of points joined by
// lines below; tap or drag to pick. Points ≤ selected use activeFg.
class _TTLSlider extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final Color textFg;
  final Color activeFg;
  final Color inactiveFg;
  final ValueChanged<int> onChanged;

  const _TTLSlider({
    required this.labels,
    required this.selected,
    required this.textFg,
    required this.activeFg,
    required this.inactiveFg,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const height = _kTtlLabelHeight + _kTtlSkip + _kTtlChosenSize;
    final count = labels.length;
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final width = constraints.maxWidth;
          final step = count > 1 ? width / (count - 1) : width;
          void handle(double dx) {
            if (step <= 0) return;
            final idx = ((dx + step / 2) ~/ step).clamp(0, count - 1);
            if (idx != selected) onChanged(idx);
          }

          // Tap or drag to pick (AyuGram tracks press→move; here onTapDown
          // handles a click and the horizontal-drag callbacks handle a drag).
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => handle(d.localPosition.dx),
            onHorizontalDragStart: (d) => handle(d.localPosition.dx),
            onHorizontalDragUpdate: (d) => handle(d.localPosition.dx),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: CustomPaint(
                size: Size(width, height),
                painter: _TTLSliderPainter(
                  labels: labels,
                  selected: selected,
                  textFg: textFg,
                  activeFg: activeFg,
                  inactiveFg: inactiveFg,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TTLSliderPainter extends CustomPainter {
  final List<String> labels;
  final int selected;
  final Color textFg;
  final Color activeFg;
  final Color inactiveFg;

  _TTLSliderPainter({
    required this.labels,
    required this.selected,
    required this.textFg,
    required this.activeFg,
    required this.inactiveFg,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final count = labels.length;
    if (count < 2) return;
    final width = size.width;
    final points = List<double>.generate(count, (i) => width * i / (count - 1));
    final centerY = _kTtlLabelHeight + _kTtlSkip + _kTtlChosenSize / 2;

    // Labels: first left-aligned, last right-aligned, others centered.
    for (var i = 0; i < count; i++) {
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(fontSize: _kTtlFontSize, color: textFg),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final shift = (i == count - 1)
          ? tp.width
          : (i > 0 ? tp.width / 2 : 0.0);
      tp.paint(canvas, Offset(points[i] - shift, 0));
    }

    // Points + connecting lines.
    for (var i = 0; i < count; i++) {
      final sz = (i == selected) ? _kTtlChosenSize : _kTtlPointSize;
      final pointFg = (i <= selected) ? activeFg : inactiveFg;
      final shift = (i == count - 1) ? sz : (i > 0 ? sz / 2 : 0.0);
      final px = points[i] - shift;
      canvas.drawOval(
        Rect.fromLTWH(px, centerY - sz / 2, sz, sz),
        Paint()..color = pointFg..style = PaintingStyle.fill,
      );

      if (i + 1 == count) break;
      final nextSz = (i + 1 == selected) ? _kTtlChosenSize : _kTtlPointSize;
      final nextShift = (i + 1 == count - 1) ? nextSz : nextSz / 2;
      final lineFg = (i + 1 <= selected) ? activeFg : inactiveFg;
      final from = px + sz + _kTtlStroke * 1.5;
      final till = points[i + 1] - nextShift - _kTtlStroke * 1.5;
      if (till > from) {
        canvas.drawLine(
          Offset(from, centerY),
          Offset(till, centerY),
          Paint()
            ..color = lineFg
            ..strokeWidth = _kTtlStroke
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TTLSliderPainter old) =>
      old.selected != selected ||
      old.textFg != textFg ||
      old.activeFg != activeFg ||
      old.inactiveFg != inactiveFg ||
      old.labels.length != labels.length;
}

// ─── §36.12 Permission Request Dialogs ──────────────────────────────────────

enum PermissionType { microphone, camera }

enum PermissionStatus { granted, canRequest, denied }

Future<PermissionStatus> getPermissionStatus(PermissionType type) async {
  if (!Platform.isLinux && !Platform.isMacOS && !Platform.isWindows) {
    return PermissionStatus.granted;
  }
  try {
    if (type == PermissionType.microphone) {
      final pactl = await Process.run('pactl', ['list', 'sources', 'short']);
      if (pactl.exitCode == 0) {
        final output = (pactl.stdout as String).trim();
        if (output.isNotEmpty) {
          final hasNonMonitor = output
              .split('\n')
              .any((l) => !l.contains('.monitor'));
          if (hasNonMonitor) return PermissionStatus.granted;
        }
      }
      final pw = await Process.run('pw-cli', ['list-objects']);
      if (pw.exitCode == 0) {
        final output = (pw.stdout as String);
        if (output.contains('Audio/Source') || output.contains('alsa_input')) {
          return PermissionStatus.granted;
        }
      }
      return PermissionStatus.denied;
    } else {
      final devices = await Process.run('bash', ['-c',
        'ls /dev/video* 2>/dev/null || ls /sys/class/video4linux/ 2>/dev/null']);
      if (devices.exitCode == 0 && (devices.stdout as String).trim().isNotEmpty) {
        return PermissionStatus.granted;
      }
      final pw = await Process.run('pw-cli', ['list-objects']);
      if (pw.exitCode == 0 && (pw.stdout as String).contains('Video/Source')) {
        return PermissionStatus.granted;
      }
      return PermissionStatus.denied;
    }
  } catch (_) {
    return PermissionStatus.canRequest;
  }
}

void openSystemSettingsForPermission(PermissionType type) {
  if (Platform.isLinux) {
    final panel = type == PermissionType.microphone ? 'sound' : 'sound';
    Process.run('gnome-control-center', [panel]).then((r) {
      if (r.exitCode != 0) {
        return Process.run('systemsettings', ['kcm_pulseaudio']);
      }
      return r;
    }).catchError((_) {
      Process.run('pavucontrol', []);
    });
  } else if (Platform.isMacOS) {
    final pane = type == PermissionType.microphone
        ? 'Privacy_Microphone'
        : 'Privacy_Camera';
    Process.run(
      'open',
      ['x-apple.systempreferences:com.apple.preference.security?$pane'],
    );
  } else if (Platform.isWindows) {
    final page = type == PermissionType.microphone
        ? 'ms-settings:privacy-microphone'
        : 'ms-settings:privacy-webcam';
    Process.run('cmd', ['/c', 'start', page]);
  }
}

String _permissionLabel(PermissionType type) {
  return switch (type) {
    PermissionType.microphone => 'microphone',
    PermissionType.camera => 'camera',
  };
}

Future<bool> showPermissionDeniedBox(
  BuildContext context,
  PermissionType type,
) async {
  final text = type == PermissionType.microphone
      ? 'UniClient needs microphone access so that you can make calls and record voice messages.'
      : 'UniClient needs camera access so that you can make video calls.';

  bool openedSettings = false;
  await showConfirmBox(
    context,
    text: text,
    confirmText: 'Settings',
    cancelText: 'Cancel',
    onConfirm: () {
      openedSettings = true;
      openSystemSettingsForPermission(type);
    },
  );
  return openedSettings;
}

Future<bool> requestPermissionOrFail(
  BuildContext context,
  PermissionType type, {
  VoidCallback? onDenied,
}) async {
  final status = await getPermissionStatus(type);
  switch (status) {
    case PermissionStatus.granted:
      return true;
    case PermissionStatus.canRequest:
      // Desktop platforms (Linux/macOS/Windows) have no runtime permission
      // request API — canRequest means the detection command failed. Show
      // the settings dialog so the user can resolve it manually.
      onDenied?.call();
      if (context.mounted) {
        await showPermissionDeniedBox(context, type);
      }
      return false;
    case PermissionStatus.denied:
      onDenied?.call();
      if (context.mounted) {
        await showPermissionDeniedBox(context, type);
      }
      return false;
  }
}

Future<bool> requestCallPermissions(
  BuildContext context, {
  bool video = false,
  VoidCallback? onDenied,
}) async {
  final micOk = await requestPermissionOrFail(
    context,
    PermissionType.microphone,
    onDenied: onDenied,
  );
  if (!micOk) return false;
  if (video) {
    final camOk = await requestPermissionOrFail(
      context,
      PermissionType.camera,
      onDenied: onDenied,
    );
    if (!camOk) return false;
  }
  return true;
}

// ─── §36.12 Screen Share Chooser ────────────────────────────────────────────

class ScreenShareSource {
  final String id;
  final String name;
  final bool isScreen;

  const ScreenShareSource({
    required this.id,
    required this.name,
    this.isScreen = false,
  });
}

class ScreenShareResult {
  final ScreenShareSource source;
  final bool withAudio;

  const ScreenShareResult({required this.source, this.withAudio = false});
}

Future<ScreenShareResult?> showScreenShareChooser(BuildContext context) async {
  if (Platform.isLinux) {
    final isWayland = Platform.environment['WAYLAND_DISPLAY']?.isNotEmpty == true ||
        Platform.environment['XDG_SESSION_TYPE'] == 'wayland';
    if (isWayland) {
      final portalSource = await _tryPortalScreenCast();
      if (portalSource != null) {
        return ScreenShareResult(source: portalSource);
      }
    }
  }
  if (!context.mounted) return null;
  return showTelegramBox<ScreenShareResult>(
    context: context,
    builder: (ctx) => const _ScreenShareChooser(),
  );
}

Future<ScreenShareSource?> _tryPortalScreenCast() async {
  final client = DBusClient.session();
  try {
    final object = DBusRemoteObject(
      client,
      name: 'org.freedesktop.portal.Desktop',
      path: DBusObjectPath('/org/freedesktop/portal/desktop'),
    );

    final uniqueName = client.uniqueName;
    if (uniqueName.isEmpty) return null;
    final senderName = uniqueName.substring(1).replaceAll('.', '_');
    final ts = DateTime.now().millisecondsSinceEpoch;
    final token = 'uc_$ts';
    final sessionToken = 'uc_s_$ts';

    final createReqPath = DBusObjectPath(
        '/org/freedesktop/portal/desktop/request/$senderName/$token');
    final createCompleter = Completer<DBusSignal>();
    final createSub = DBusSignalStream(
      client,
      interface: 'org.freedesktop.portal.Request',
      name: 'Response',
      path: createReqPath,
    ).listen(createCompleter.complete);

    await object.callMethod(
      'org.freedesktop.portal.ScreenCast', 'CreateSession',
      [DBusDict(DBusSignature('s'), DBusSignature('v'), {
        DBusString('handle_token'): DBusVariant(DBusString(token)),
        DBusString('session_handle_token'): DBusVariant(DBusString(sessionToken)),
      })],
      replySignature: DBusSignature('o'),
    );

    final createSig = await createCompleter.future.timeout(const Duration(seconds: 5));
    await createSub.cancel();
    if ((createSig.values[0] as DBusUint32).value != 0) return null;

    final createOpts = createSig.values[1] as DBusDict;
    final sessionHandle = ((createOpts.children[DBusString('session_handle')]
        as DBusVariant).value as DBusObjectPath);

    final selToken = 'uc_sel_$ts';
    final selReqPath = DBusObjectPath(
        '/org/freedesktop/portal/desktop/request/$senderName/$selToken');
    final selCompleter = Completer<DBusSignal>();
    final selSub = DBusSignalStream(
      client,
      interface: 'org.freedesktop.portal.Request',
      name: 'Response',
      path: selReqPath,
    ).listen(selCompleter.complete);

    await object.callMethod(
      'org.freedesktop.portal.ScreenCast', 'SelectSources',
      [sessionHandle, DBusDict(DBusSignature('s'), DBusSignature('v'), {
        DBusString('types'): DBusVariant(DBusUint32(3)),
        DBusString('multiple'): DBusVariant(DBusBoolean(false)),
        DBusString('handle_token'): DBusVariant(DBusString(selToken)),
      })],
      replySignature: DBusSignature('o'),
    );

    final selSig = await selCompleter.future.timeout(const Duration(seconds: 120));
    await selSub.cancel();
    if ((selSig.values[0] as DBusUint32).value != 0) return null;

    final startToken = 'uc_st_$ts';
    final startReqPath = DBusObjectPath(
        '/org/freedesktop/portal/desktop/request/$senderName/$startToken');
    final startCompleter = Completer<DBusSignal>();
    final startSub = DBusSignalStream(
      client,
      interface: 'org.freedesktop.portal.Request',
      name: 'Response',
      path: startReqPath,
    ).listen(startCompleter.complete);

    await object.callMethod(
      'org.freedesktop.portal.ScreenCast', 'Start',
      [sessionHandle, DBusString(''), DBusDict(DBusSignature('s'), DBusSignature('v'), {
        DBusString('handle_token'): DBusVariant(DBusString(startToken)),
      })],
      replySignature: DBusSignature('o'),
    );

    final startSig = await startCompleter.future.timeout(const Duration(seconds: 120));
    await startSub.cancel();
    if ((startSig.values[0] as DBusUint32).value != 0) return null;

    final startOpts = startSig.values[1] as DBusDict;
    final streamsVar = startOpts.children[DBusString('streams')] as DBusVariant;
    final streams = streamsVar.value as DBusArray;
    if (streams.children.isEmpty) return null;

    final first = streams.children.first as DBusStruct;
    final nodeId = (first.children[0] as DBusUint32).value;
    final props = first.children[1] as DBusDict;
    final srcTypeVar = props.children[DBusString('source_type')];
    final srcType = srcTypeVar is DBusVariant
        ? (srcTypeVar.value as DBusUint32).value
        : 1;
    final isScreen = srcType == 1;

    return ScreenShareSource(
      id: 'pipewire:$nodeId',
      name: isScreen ? 'Screen' : 'Window',
      isScreen: isScreen,
    );
  } catch (_) {
    return null;
  } finally {
    await client.close();
  }
}

class _ScreenShareChooser extends StatefulWidget {
  const _ScreenShareChooser();

  @override
  State<_ScreenShareChooser> createState() => _ScreenShareChooserState();
}

class _ScreenShareChooserState extends State<_ScreenShareChooser> {
  List<ScreenShareSource> _sources = [];
  final Map<int, String> _thumbnails = {};
  bool _loading = true;
  bool _isWayland = false;
  int _selectedIndex = -1;
  bool _withAudio = false;
  // AyuGram only shows the "Share audio" checkbox when loopback capture is
  // supported (desktop_capture_choose_source.cpp:456 →
  // Webrtc::LoopbackAudioCaptureSupported()). On an unsupported platform the
  // control would be a no-op, so it must be hidden entirely.
  bool _audioSupported = false;

  // Mirror of Webrtc::LoopbackAudioCaptureSupported(): always on Windows, and on
  // Linux when a PulseAudio/PipeWire monitor (loopback) source is present.
  Future<bool> _loopbackAudioSupported() async {
    if (Platform.isWindows) return true;
    if (Platform.isLinux) {
      try {
        final pactl = await Process.run('pactl', ['list', 'sources', 'short']);
        if (pactl.exitCode == 0 &&
            (pactl.stdout as String).contains('.monitor')) {
          return true;
        }
      } catch (e) {
        Debug.log('confirm_box', 'final pactl = await Process.run(\'pactl\', [\'list\', \'source...: $e');
      }
      try {
        final pw = await Process.run('pw-cli', ['list-objects']);
        if (pw.exitCode == 0 &&
            (pw.stdout as String).contains('Audio/Source')) {
          return true;
        }
      } catch (e) {
        Debug.log('confirm_box', 'final pw = await Process.run(\'pw-cli\', [\'list-objects\']): $e');
      }
      return false;
    }
    // macOS loopback needs a virtual device that isn't present by default.
    return false;
  }

  @override
  void initState() {
    super.initState();
    _loadSources();
  }

  @override
  void dispose() {
    for (final path in _thumbnails.values) {
      try { File(path).deleteSync(); } catch (e) {
        Debug.log('confirm_box', 'File(path).deleteSync(): $e');
      }
    }
    super.dispose();
  }

  Future<void> _loadSources() async {
    final sources = <ScreenShareSource>[];

    final isWayland = Platform.environment['WAYLAND_DISPLAY']?.isNotEmpty == true ||
        Platform.environment['XDG_SESSION_TYPE'] == 'wayland';
    _isWayland = isWayland;

    if (isWayland) {
      sources.add(const ScreenShareSource(
        id: 'portal:screen',
        name: 'Entire Screen',
        isScreen: true,
      ));
      try {
        final kdotool = await Process.run('kdotool', ['search', '--name', '']);
        if (kdotool.exitCode == 0) {
          final ids = (kdotool.stdout as String)
              .split('\n')
              .where((l) => l.trim().isNotEmpty)
              .toList();
          for (final wid in ids) {
            try {
              final nameRes = await Process.run('kdotool', ['getwindowname', wid.trim()]);
              if (nameRes.exitCode == 0) {
                final name = (nameRes.stdout as String).trim();
                if (name.isNotEmpty) {
                  sources.add(ScreenShareSource(id: 'window:$wid', name: name));
                }
              }
            } catch (e) {
              Debug.log('confirm_box', 'final nameRes = await Process.run(\'kdotool\', [\'getwindown...: $e');
            }
          }
        }
      } catch (e) {
        Debug.log('confirm_box', 'final nameRes = await Process.run(\'kdotool\', [\'getwindown...: $e');
      }
    } else {
      try {
        final xrandr = await Process.run('xrandr', ['--listmonitors']);
        if (xrandr.exitCode == 0) {
          final lines = (xrandr.stdout as String).split('\n');
          for (int i = 1; i < lines.length; i++) {
            final line = lines[i].trim();
            if (line.isEmpty) continue;
            final parts = line.split(RegExp(r'\s+'));
            final name = parts.length > 1 ? parts.last : 'Screen $i';
            sources.add(ScreenShareSource(
              id: 'screen:${i - 1}',
              name: name,
              isScreen: true,
            ));
          }
        }
      } catch (e) {
        Debug.log('confirm_box', 'final xrandr = await Process.run(\'xrandr\', [\'--listmonito...: $e');
      }

      try {
        final wmctrl = await Process.run('wmctrl', ['-l']);
        if (wmctrl.exitCode == 0) {
          final lines = (wmctrl.stdout as String).split('\n');
          for (final line in lines) {
            if (line.trim().isEmpty) continue;
            final parts = line.split(RegExp(r'\s+'));
            if (parts.length < 4) continue;
            final windowId = parts[0];
            final windowName = parts.sublist(3).join(' ').trim();
            if (windowName.isEmpty || windowName == 'N/A') continue;
            sources.add(ScreenShareSource(
              id: 'window:$windowId',
              name: windowName,
            ));
          }
        }
      } catch (_) {
        try {
          final xdotool = await Process.run(
            'xdotool', ['search', '--onlyvisible', '--name', ''],
          );
          if (xdotool.exitCode == 0) {
            final windowIds = (xdotool.stdout as String)
                .split('\n')
                .where((l) => l.trim().isNotEmpty)
                .toList();
            for (final wid in windowIds) {
              try {
                final nameResult = await Process.run(
                  'xdotool', ['getwindowname', wid.trim()],
                );
                if (nameResult.exitCode == 0) {
                  final name = (nameResult.stdout as String).trim();
                  if (name.isNotEmpty) {
                    sources.add(ScreenShareSource(
                      id: 'window:$wid',
                      name: name,
                    ));
                  }
                }
              } catch (e) {
                Debug.log('confirm_box', 'final nameResult = await Process.run(: $e');
              }
            }
          }
        } catch (e) {
          Debug.log('confirm_box', 'final nameResult = await Process.run(: $e');
        }
      }
    }

    if (sources.isEmpty) {
      sources.add(const ScreenShareSource(
        id: 'screen:0',
        name: 'Entire Screen',
        isScreen: true,
      ));
    }

    final audioSupported = await _loopbackAudioSupported();

    if (mounted) {
      setState(() {
        _sources = sources;
        _loading = false;
        _audioSupported = audioSupported;
        if (sources.isNotEmpty) _selectedIndex = 0;
      });
      _captureThumbnails();
    }
  }

  Future<void> _captureThumbnails() async {
    final count = _sources.length < 12 ? _sources.length : 12;
    final futures = List.generate(count, (i) async {
      final path = await _captureThumb(_sources[i], i);
      return path != null ? MapEntry(i, path) : null;
    });
    final results = await Future.wait(futures);
    if (!mounted) return;
    final captured = <int, String>{};
    for (final entry in results) {
      if (entry != null) captured[entry.key] = entry.value;
    }
    if (captured.isNotEmpty) {
      setState(() => _thumbnails.addAll(captured));
    }
  }

  Future<String?> _captureThumb(ScreenShareSource source, int index) async {
    final path = '/tmp/uniclient_ss_thumb_$index.png';
    try {
      if (source.isScreen) {
        if (_isWayland) {
          final r = await Process.run('grim', ['-s', '0.1', path])
              .timeout(const Duration(seconds: 3));
          return r.exitCode == 0 ? path : null;
        } else {
          final r = await Process.run(
              'import', ['-window', 'root', '-resize', '160x100', path])
              .timeout(const Duration(seconds: 3));
          return r.exitCode == 0 ? path : null;
        }
      } else if (!_isWayland) {
        final wid = source.id.replaceFirst('window:', '');
        final r = await Process.run(
            'import', ['-window', wid, '-resize', '160x100', path])
            .timeout(const Duration(seconds: 3));
        return r.exitCode == 0 ? path : null;
      }
    } catch (e) {
      Debug.log('confirm_box', 'if (source.isScreen): $e');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textColor = p.boxTextFg;
    final subTextColor = p.boxTitleAdditionalFg;
    final accentColor = p.windowActiveTextFg;
    final selectedBorder = accentColor;
    final cardBg = p.boxSearchBg;

    return TelegramBox(
      title: 'Choose what to share',
      wide: true,
      scrollableContent: false,
      content: SizedBox(
        height: 340,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _sources.isEmpty
                          ? Center(
                              child: Text(
                                'No sources available',
                                style: TextStyle(
                                    color: subTextColor, fontSize: 14),
                              ),
                            )
                          : GridView.builder(
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                // AyuGram lays sources out in a 3-column grid
                                // (kColumns = 3, desktop_capture_choose_source.cpp:31).
                                crossAxisCount: 3,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                                childAspectRatio: 16 / 10,
                              ),
                              itemCount: _sources.length,
                              itemBuilder: (ctx, i) {
                                final source = _sources[i];
                                final selected = i == _selectedIndex;
                                return GestureDetector(
                                  onTap: () =>
                                      setState(() => _selectedIndex = i),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: cardBg,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: selected
                                            ? selectedBorder
                                            : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Expanded(
                                          child: Padding(
                                            padding: const EdgeInsets.all(4),
                                            child: _thumbnails.containsKey(i)
                                                ? ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(4),
                                                    child: Image.file(
                                                      File(_thumbnails[i]!),
                                                      fit: BoxFit.cover,
                                                      width: double.infinity,
                                                      cacheWidth: 160,
                                                      cacheHeight: 100,
                                                      errorBuilder:
                                                          (_, __, ___) => Icon(
                                                        source.isScreen
                                                            ? Icons
                                                                .desktop_windows
                                                            : Icons.web_asset,
                                                        size: 40,
                                                        color: selected
                                                            ? accentColor
                                                            : subTextColor,
                                                      ),
                                                    ),
                                                  )
                                                : Icon(
                                                    source.isScreen
                                                        ? Icons.desktop_windows
                                                        : Icons.web_asset,
                                                    size: 40,
                                                    color: selected
                                                        ? accentColor
                                                        : subTextColor,
                                                  ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              bottom: 4),
                                          child: Text(
                                            source.name,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: textColor,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                  if (_audioSupported)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: Checkbox(
                              value: _withAudio,
                              onChanged: (v) =>
                                  setState(() => _withAudio = v ?? false),
                              activeColor: accentColor,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () =>
                                setState(() => _withAudio = !_withAudio),
                            child: Text(
                              'SHARE AUDIO',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
      buttons: [
        TelegramBoxButton(
          text: 'CANCEL',
          onPressed: () => Navigator.of(context).pop(),
        ),
        TelegramBoxButton(
          text: 'START SHARING',
          onPressed: _selectedIndex >= 0
              ? () {
                  Navigator.of(context).pop(ScreenShareResult(
                    source: _sources[_selectedIndex],
                    withAudio: _withAudio,
                  ));
                }
              : null,
        ),
      ],
    );
  }
}

// ─── §36.13 Report Flow ─────────────────────────────────────────────────────

const String _kReportBack = '__back__';

// Whole-peer / per-message report. Mirrors AyuGram's ShowReportMessageBox:
// messages.report is issued with whatever ids we have (possibly none, for a
// chat-info "Report"); the server drives the dynamic option/comment flow. If it
// answers MESSAGE_ID_REQUIRED, a message chooser is shown and messages.report is
// re-issued with the picked ids (the rest of reportInput preserved) — it never
// falls back to account.reportPeer.
// ← boxes/report_messages_box.cpp:69-207 / window_session_controller.cpp:2958
//   → mainwidget.cpp:1291 (showChooseReportMessages → in-chat message selection).
Future<bool> showDynamicReportFlow(
  BuildContext context, {
  required EngineService engine,
  required String accountId,
  required String chatId,
  required List<int> msgIds,
}) async {
  // Mutable so a MESSAGE_ID_REQUIRED chooser can fill in the ids and retry, just
  // like AyuGram's `copy.ids = std::move(ids)` re-issue (report_messages_box.cpp:92).
  var ids = List<int>.from(msgIds);
  final optionStack = <List<int>>[];
  List<int> currentOption = [];

  while (true) {
    final result = await engine.reportMessage(
      accountId,
      chatId,
      ids,
      option: currentOption,
    );
    if (result == null || !context.mounted) return false;

    // Server needs specific messages: open the recent-messages chooser, then
    // retry messages.report with the chosen ids (currentOption preserved).
    // ← report_messages_box.cpp:84-100 (MESSAGE_ID_REQUIRED → showChooseReportMessages).
    if (result.resultType == 'message_id_required') {
      final chosen = await _showReportMessageChooser(
        context,
        engine: engine,
        accountId: accountId,
        chatId: chatId,
      );
      if (chosen == null || chosen.isEmpty || !context.mounted) return false;
      ids = chosen;
      continue;
    }

    if (result.resultType == 'reported') {
      if (context.mounted) {
        showTelegramToast(context, 'Report submitted');
      }
      return true;
    }

    if (result.resultType == 'choose_option') {
      final hasComment = result.commentOption.isNotEmpty;
      final picked = await showTelegramBox<dynamic>(
        context: context,
        builder: (ctx) => _ReportOptionPickerBox(
          title: result.title.isNotEmpty ? result.title : 'Report',
          options: result.options,
          hasComment: hasComment,
          commentOptional: result.commentOptional,
          commentOption: result.commentOption,
          showBackButton: optionStack.isNotEmpty,
        ),
      );
      if (picked == null || !context.mounted) return false;

      if (picked == _kReportBack) {
        if (optionStack.isNotEmpty) {
          currentOption = optionStack.removeLast();
          continue;
        }
        return false;
      }

      if (picked is Map) {
        final comment = picked['comment'] as String? ?? '';
        final commentOpt = picked['option'] as List<int>? ?? [];
        final finalResult = await engine.reportMessage(
          accountId,
          chatId,
          ids,
          option: commentOpt,
          message: comment,
        );
        if (context.mounted) {
          showTelegramToast(
            context,
            finalResult == null
                ? 'Report failed. Please try again.'
                : (finalResult.resultType == 'reported'
                    ? 'Report submitted'
                    : 'Report sent'),
          );
        }
        return finalResult != null;
      }

      optionStack.add(currentOption);
      currentOption = picked as List<int>;
      continue;
    }

    if (result.resultType == 'add_comment') {
      final comment = await showReportDetailsBox(
        context,
        optional: result.commentOptional,
      );
      if (comment == null || !context.mounted) return false;
      final finalResult = await engine.reportMessage(
        accountId,
        chatId,
        ids,
        option: result.commentOption,
        message: comment,
      );
      if (context.mounted) {
        showTelegramToast(
          context,
          finalResult == null
              ? 'Report failed. Please try again.'
              : (finalResult.resultType == 'reported'
                  ? 'Report submitted'
                  : 'Report sent'),
        );
      }
      return finalResult != null;
    }

    return false;
  }
}

// Recent-messages chooser shown when messages.report answers MESSAGE_ID_REQUIRED.
// AyuGram opens the chat in a selection mode and, once the user has picked at
// least one message, re-issues messages.report with `getSelectedItems()`
// (history_widget.cpp:5421 reportSelectedMessages → done(ids)). We present the
// equivalent as a multi-select list of the peer's recent messages; "Report"
// returns the chosen server ids so showDynamicReportFlow can retry.
Future<List<int>?> _showReportMessageChooser(
  BuildContext context, {
  required EngineService engine,
  required String accountId,
  required String chatId,
}) {
  return showTelegramBox<List<int>>(
    context: context,
    builder: (ctx) => _ReportMessageChooserBox(
      engine: engine,
      accountId: accountId,
      chatId: chatId,
    ),
  );
}

class _ReportMessageChooserBox extends StatefulWidget {
  final EngineService engine;
  final String accountId;
  final String chatId;
  const _ReportMessageChooserBox({
    required this.engine,
    required this.accountId,
    required this.chatId,
  });

  @override
  State<_ReportMessageChooserBox> createState() =>
      _ReportMessageChooserBoxState();
}

class _ReportMessageChooserBoxState extends State<_ReportMessageChooserBox> {
  bool _loading = true;
  bool _failed = false;
  List<CachedMessage> _messages = const [];
  final Set<int> _selected = <int>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final msgs = await widget.engine.fetchLiveMessages(
        widget.accountId,
        widget.chatId,
        limit: 60,
      );
      // Only real, reportable messages: drop service events and any unsent /
      // local-only message that has no server id to pass to messages.report.
      final list = msgs
          .where((m) => !m.isService && (int.tryParse(m.msgId) ?? 0) > 0)
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (mounted) {
        setState(() {
          _messages = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  void _toggle(int id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textFg = p.boxTextFg;
    final subFg = p.windowSubTextFg;
    final accent = p.windowBgActive;
    final hoverBg = p.windowBgOver;

    Widget body;
    if (_loading) {
      body = SizedBox(
        height: 120,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: accent),
          ),
        ),
      );
    } else if (_failed || _messages.isEmpty) {
      body = SizedBox(
        height: 120,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _failed
                  ? "Couldn't load messages. Please try again."
                  : 'There are no messages to report here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: subFg),
            ),
          ),
        ),
      );
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in _messages)
            _buildRow(m, textFg, subFg, accent, hoverBg),
        ],
      );
    }

    return TelegramBox(
      title: TrStrings.lngReportSelectMessages(),
      showClose: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              TrStrings.lngReportPleaseSelectMessages(),
              style: TextStyle(fontSize: 13, color: p.boxTitleAdditionalFg),
            ),
          ),
          body,
        ],
      ),
      buttons: [
        TelegramBoxButton(
          text: 'CANCEL',
          onPressed: () => Navigator.of(context).pop(),
        ),
        TelegramBoxButton(
          text: 'REPORT',
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(_selected.toList()),
        ),
      ],
      scrollableContent: true,
    );
  }

  Widget _buildRow(
    CachedMessage m,
    Color textFg,
    Color subFg,
    Color accent,
    Color hoverBg,
  ) {
    final id = int.parse(m.msgId);
    final selected = _selected.contains(id);
    final preview = _reportChooserPreview(m);
    final time = _reportChooserTime(m.timestamp);
    final hasSender = m.senderName.trim().isNotEmpty;
    return InkWell(
      onTap: () => _toggle(id),
      hoverColor: hoverBg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: selected,
                onChanged: (_) => _toggle(id),
                activeColor: accent,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (hasSender)
                        Expanded(
                          child: Text(
                            m.senderName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: textFg,
                            ),
                          ),
                        )
                      else
                        const Spacer(),
                      if (time.isNotEmpty)
                        Text(
                          time,
                          style: TextStyle(fontSize: 12, color: subFg),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    preview,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: textFg),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// One-line preview of a message for the report chooser: caption/text if present,
// otherwise a media-kind label (matches the chat-list media fallbacks).
String _reportChooserPreview(CachedMessage m) {
  final text = m.contentText.trim();
  if (text.isNotEmpty) return text.replaceAll(RegExp(r'\s+'), ' ');
  switch (m.mediaType) {
    case 1:
      return 'Photo';
    case 2:
      return 'Video';
    case 3:
      return 'Audio';
    case 4:
      return 'Voice message';
    case 5:
      return 'Video message';
    case 6:
      return 'Sticker';
    case 7:
      return 'GIF';
    case 8:
      return m.mediaFileName.isNotEmpty ? m.mediaFileName : 'File';
  }
  return 'Message';
}

String _reportChooserTime(int timestampMs) {
  if (timestampMs == 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);
  return '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}

// AddReportDetailsIconButton (report_box_graphics.cpp:209): the
// `blocked_peers_empty` Lottie, played once after the box finishes appearing.
// Shared by the standalone report-details box AND the combined options+comment
// box so both report paths show the same illustration.
class _ReportDetailsLottie extends StatefulWidget {
  const _ReportDetailsLottie();

  @override
  State<_ReportDetailsLottie> createState() => _ReportDetailsLottieState();
}

class _ReportDetailsLottieState extends State<_ReportDetailsLottie>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onLoaded(LottieComposition composition) {
    _controller.duration = composition.duration;
    final anim = ModalRoute.of(context)?.animation;
    if (anim != null && !anim.isCompleted) {
      void listener(AnimationStatus status) {
        if (status == AnimationStatus.completed && mounted) {
          _controller.forward();
          anim.removeStatusListener(listener);
        }
      }
      anim.addStatusListener(listener);
    } else {
      if (mounted) _controller.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 16),
        child: SizedBox(
          width: 120,
          height: 120,
          child: Lottie.asset(
            'assets/animations/blocked_peers_empty.json',
            controller: _controller,
            onLoaded: _onLoaded,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

class _ReportOptionPickerBox extends StatefulWidget {
  final String title;
  final List<ReportOptionItem> options;
  final bool hasComment;
  final bool commentOptional;
  final List<int> commentOption;
  final bool showBackButton;
  const _ReportOptionPickerBox({
    required this.title,
    required this.options,
    this.hasComment = false,
    this.commentOptional = false,
    this.commentOption = const [],
    this.showBackButton = false,
  });

  @override
  State<_ReportOptionPickerBox> createState() => _ReportOptionPickerBoxState();
}

class _ReportOptionPickerBoxState extends State<_ReportOptionPickerBox> {
  final _commentController = TextEditingController();
  final _commentFocus = FocusNode();
  final _commentError = ValueNotifier<String?>(null);

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocus.dispose();
    _commentError.dispose();
    super.dispose();
  }

  void _submitComment() {
    if (!widget.commentOptional && _commentController.text.trim().isEmpty) {
      _commentError.value = 'This field is required';
      _commentFocus.requestFocus();
      return;
    }
    Navigator.of(context).pop({
      'type': 'comment',
      'option': widget.commentOption,
      'comment': _commentController.text,
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textFg = p.boxTextFg;
    final hoverBg = p.windowBgOver;

    return TelegramBox(
      title: widget.title,
      showClose: true,
      content: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...widget.options.map((opt) {
              return InkWell(
                onTap: () => Navigator.of(context).pop(opt.option),
                hoverColor: hoverBg,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 11, 24, 11),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          opt.text,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: textFg,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 20,
                        color: textFg.withValues(alpha: 0.5),
                      ),
                    ],
                  ),
                ),
              );
            }),
            if (widget.hasComment) ...[
              // AyuGram's combined options+comment box shows the
              // AddReportDetailsIconButton illustration above the field
              // (report_messages_box.cpp:124-130).
              const _ReportDetailsLottie(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ValueListenableBuilder<String?>(
                  valueListenable: _commentError,
                  builder: (context, error, _) => TextField(
                    controller: _commentController,
                    focusNode: _commentFocus,
                    maxLines: 3,
                    maxLength: 512,
                    onChanged: (_) {
                      if (_commentError.value != null) _commentError.value = null;
                    },
                    onSubmitted: (_) => _submitComment(),
                    decoration: InputDecoration(
                      hintText: widget.commentOptional
                          ? 'Add Comment (Optional)'
                          : 'Add Comment',
                      errorText: error,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  'Please enter any additional details relevant to your report.',
                  style: TextStyle(fontSize: 13, color: p.boxTitleAdditionalFg),
                ),
              ),
            ],
          ],
        ),
      ),
      buttons: [
        if (widget.showBackButton)
          TelegramBoxButton(
            text: 'Back',
            isLeft: true,
            onPressed: () => Navigator.of(context).pop(_kReportBack),
          ),
        if (!widget.showBackButton)
          TelegramBoxButton(
            text: 'CANCEL',
            onPressed: () => Navigator.of(context).pop(),
          ),
        if (widget.hasComment)
          TelegramBoxButton(
            text: 'REPORT',
            onPressed: _submitComment,
          ),
      ],
      scrollableContent: true,
    );
  }
}

Future<String?> showReportDetailsBox(
  BuildContext context, {
  bool optional = true,
}) {
  return showTelegramBox<String>(
    context: context,
    builder: (ctx) => _ReportDetailsBox(optional: optional),
  );
}

class _ReportDetailsBox extends StatefulWidget {
  final bool optional;
  const _ReportDetailsBox({required this.optional});

  @override
  State<_ReportDetailsBox> createState() => _ReportDetailsBoxState();
}

class _ReportDetailsBoxState extends State<_ReportDetailsBox> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  final _errorText = ValueNotifier<String?>(null);

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    _errorText.dispose();
    super.dispose();
  }

  void _submit() {
    if (!widget.optional && _textController.text.trim().isEmpty) {
      _errorText.value = 'This field is required';
      _focusNode.requestFocus();
      return;
    }
    Navigator.of(context).pop(_textController.text);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textFg = p.boxTextFg;

    return TelegramBox(
      title: 'Report',
      onConfirm: _submit,
      content: Padding(
        padding: kBoxPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _ReportDetailsLottie(),
            Text(
              'Please enter any additional details relevant to your report.',
              style: TextStyle(fontSize: 14, color: textFg),
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<String?>(
              valueListenable: _errorText,
              builder: (context, error, _) => TextField(
                controller: _textController,
                focusNode: _focusNode,
                maxLines: 3,
                maxLength: 512,
                autofocus: true,
                onChanged: (_) {
                  if (_errorText.value != null) _errorText.value = null;
                },
                decoration: InputDecoration(
                  hintText: widget.optional
                      ? 'Add Comment (Optional)'
                      : 'Add Comment',
                  errorText: error,
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      buttons: [
        TelegramBoxButton(
          text: 'CANCEL',
          onPressed: () => Navigator.of(context).pop(),
        ),
        TelegramBoxButton(
          text: 'REPORT',
          onPressed: _submit,
        ),
      ],
    );
  }
}

class ReportReactionResult {
  final bool confirmed;
  final bool ban;
  const ReportReactionResult({this.confirmed = false, this.ban = false});
}

Future<bool> showReportReactionBox(
  BuildContext context, {
  required EngineService engine,
  required String accountId,
  required String chatId,
  required String participantId,
  required int messageId,
  bool showBanCheckbox = false,
}) async {
  final result = await showTelegramBox<ReportReactionResult>(
    context: context,
    builder: (ctx) => _ReportReactionContent(
      showBanCheckbox: showBanCheckbox,
    ),
  );
  if (result == null || !result.confirmed) return false;

  try {
    if (result.ban) {
      await engine.banMember(accountId, chatId, participantId);
    }
    await engine.reportReaction(accountId, chatId, messageId, participantId);
    if (context.mounted) {
      showTelegramToast(context, 'Report submitted. Thank you!');
    }
  } catch (e) {
    Debug.log('confirm_box', 'if (result.ban): $e');
  }
  return true;
}

class _ReportReactionContent extends StatefulWidget {
  final bool showBanCheckbox;
  const _ReportReactionContent({required this.showBanCheckbox});

  @override
  State<_ReportReactionContent> createState() => _ReportReactionContentState();
}

class _ReportReactionContentState extends State<_ReportReactionContent> {
  bool _banUser = true;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final textFg = p.boxTextFg;
    final checkClr = p.windowBgActive;

    return TelegramBox(
      title: TrStrings.lngReportReactionTitle(),
      onConfirm: () => Navigator.of(context).pop(
        ReportReactionResult(confirmed: true, ban: _banUser && widget.showBanCheckbox),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: kBoxPadding,
            child: Text(
              TrStrings.lngReportReactionAbout(),
              style: TextStyle(fontSize: 14, color: textFg),
            ),
          ),
          if (widget.showBanCheckbox) ...[
            const SizedBox(height: kBoxLittleSkip),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: InkWell(
                onTap: () => setState(() => _banUser = !_banUser),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: Checkbox(
                        value: _banUser,
                        onChanged: (v) => setState(() => _banUser = v ?? false),
                        activeColor: checkClr,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        TrStrings.lngReportAndBanButton(),
                        style: TextStyle(fontSize: 14, color: textFg),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
      buttons: [
        TelegramBoxButton(
          text: 'CANCEL',
          onPressed: () => Navigator.of(context).pop(const ReportReactionResult()),
        ),
        TelegramBoxButton(
          text: 'REPORT',
          isDestructive: true,
          onPressed: () => Navigator.of(context).pop(
            ReportReactionResult(confirmed: true, ban: _banUser && widget.showBanCheckbox),
          ),
        ),
      ],
    );
  }
}

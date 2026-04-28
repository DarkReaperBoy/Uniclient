import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import 'gesture_utils.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/audio_service.dart';
import '../state/chat_state.dart';
import '../theme/theme.dart';
import '../data/emoji_data.dart';
import 'chat_list_row.dart' show ForwardDragData;
import 'sticker_pack_viewer.dart';
import 'message_bubble.dart';
import 'popup_menu.dart';
import 'send_files_box.dart';
import 'confirm_box.dart';
import 'call_panel.dart';
import 'forum_topic_icon.dart';
import 'edit_forum_topic_box.dart';
import 'choose_datetime_box.dart';
import 'emoji_panel.dart';
import '../utils/web_drop.dart';

/// Chat column: top bar + message list + compose area.
/// Spec §4 (top bar 54px), §5 (messages), §7 (compose).
class ChatView extends StatefulWidget {
  /// Global hook used by app-level keyboard shortcuts (ArrowUp with nothing
  /// focused) to trigger edit-last-outgoing-message behavior on the active
  /// chat (spec §24.7). Set by the active [_ChatViewState] on mount, cleared
  /// on dispose. Returns true if the active ChatView entered edit mode.
  static bool Function()? editLastOutgoingRequest;

  /// Invoked by the app-level ArrowUp binding. Returns true if consumed.
  static bool requestEditLastOutgoing() =>
      editLastOutgoingRequest?.call() ?? false;

  /// Global hook used by app-level keyboard shortcuts (Ctrl+R with a chat
  /// open) to mark the currently active chat as read (spec §24.4
  /// `read_chat`). Set by the active [_ChatViewState] on mount, cleared on
  /// dispose. Returns true if the active chat was successfully marked read.
  static bool Function()? markActiveChatReadRequest;

  /// Invoked by the app-level Ctrl+R binding. Returns true if consumed.
  static bool requestMarkActiveChatRead() =>
      markActiveChatReadRequest?.call() ?? false;

  /// Global hook used by app-level keyboard shortcuts (Ctrl+\ with a chat
  /// open) to open the chat-level action menu (spec §24.4 `show_chat_menu`,
  /// the "peer menu"). Set by the active [_ChatViewState] on mount, cleared
  /// on dispose. Returns true if the menu was shown.
  static bool Function()? showActiveChatMenuRequest;

  /// Invoked by the app-level Ctrl+\ binding. Returns true if consumed.
  static bool requestShowActiveChatMenu() =>
      showActiveChatMenuRequest?.call() ?? false;

  static bool Function()? showChatPreviewRequest;
  static bool requestShowChatPreview() =>
      showChatPreviewRequest?.call() ?? false;

  static bool Function()? archiveActiveChatRequest;
  static bool requestArchiveActiveChat() =>
      archiveActiveChatRequest?.call() ?? false;

  static bool Function()? showScheduledRequest;
  static bool requestShowScheduled() =>
      showScheduledRequest?.call() ?? false;

  /// Harness hook for always-send (spec §24.4 line 2978: Ctrl+Shift+Enter
  /// always sends regardless of mode). Real OS-delivered Ctrl+Shift+Enter
  /// reaches the compose TextField's FocusNode.onKeyEvent directly; this hook
  /// exists so the test harness (which uses HardwareKeyboard.handleKeyEvent
  /// and does not route through FocusManager in all cases) can drive the
  /// shortcut. Returns true iff the send fired (non-empty compose + active
  /// chat).
  static bool Function()? sendComposeRequest;

  /// Invoked by the harness `ctrl+shift+enter` binding. Returns true if
  /// consumed (send dispatched).
  static bool requestSendCompose() => sendComposeRequest?.call() ?? false;

  static void Function(String text, {int? selStart, int? selEnd})? setComposeRequest;
  static void Function(FormatType type)? toggleFormatRequest;
  static String Function()? getComposeEntitiesRequest;

  /// Global hook used by Ctrl+Up / Ctrl+Down (spec §24.6 lines 2982-2983) to
  /// cycle the reply target. direction=+1 → older message (Ctrl+Up), -1 →
  /// newer message (Ctrl+Down). Ctrl+Down on the newest message cancels the
  /// reply. Set by the active [_ChatViewState] on mount, cleared on dispose.
  /// Returns true if consumed (active chat with messages and non-edit state).
  static bool Function(int direction)? cycleReplyRequest;

  static void Function(List<String> paths)? showSendFilesBoxRequest;

  static VoidCallback? testVideoTipToast;
  static VoidCallback? testVideoPublishedToast;

  static void Function(bool isUp)? scrollPageRequest;
  static void requestScrollPage(bool isUp) =>
      scrollPageRequest?.call(isUp);

  /// Invoked by the app-level Ctrl+Up / Ctrl+Down bindings. Returns true if
  /// consumed.
  static bool requestCycleReply(int direction) =>
      cycleReplyRequest?.call(direction) ?? false;

  final bool showBackButton;
  final VoidCallback? onBack;
  final VoidCallback? onToggleInfo;
  /// Spec §4.3: true when the info panel is open so the info toggle icon
  /// renders in `windowActiveTextFg` (blue).
  final bool isInfoOpen;
  /// Spec §1: Wide chat mode (chat width >= 880px) centers the message bubble
  /// column within the chat area.
  final bool wideChatMode;
  /// Spec §4.1: hide the 1px divider below the top bar during one-column
  /// slide transitions. Re-shown after the transition completes.
  final bool hideTopBarDivider;
  /// Spec §4.7: when viewing the scheduled messages section, the selection bar
  /// shows "SEND NOW" instead of "FORWARD" and hides "COPY".
  final bool isScheduledView;

  const ChatView({
    super.key,
    this.showBackButton = false,
    this.onBack,
    this.onToggleInfo,
    this.isInfoOpen = false,
    this.wideChatMode = false,
    this.hideTopBarDivider = false,
    this.isScheduledView = false,
  });

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView>
    with TickerProviderStateMixin {
  static const _kRescheduleLimit = 20;
  static final _urlRegExp = RegExp(r'https?://[^\s<>"{}|\\^`\[\]]+', caseSensitive: false);
  final _composeController = RichTextEditingController();
  final _scrollController = ScrollController();
  String? _replyToId;
  String? _editingMsgId;
  String _editOriginalText = '';
  bool _showScrollToBottom = false;
  /// Spec §5: 150ms slide-up animation for scroll-to-bottom FAB.
  late final AnimationController _fabAnimCtrl;
  /// Spec §5 / §49.17: corner button stack — Mentions, Reactions, PollVotes
  /// slide from right (150ms linear), stacked above Jump-down with 4px gaps.
  late final AnimationController _mentionsAnimCtrl;
  late final AnimationController _reactionsAnimCtrl;
  late final AnimationController _pollVotesAnimCtrl;
  bool _showMentionsBtn = false;
  bool _showReactionsBtn = false;
  bool _showPollVotesBtn = false;
  /// §23.10: slide animation (200ms) for scheduled section enter/exit.
  late final AnimationController _scheduledSlideCtrl;
  bool _scheduledSlideForward = true;
  String? _lastChatId;
  /// Spec §4.4: when the user taps the close button on the pinned bar,
  /// the bar is hidden locally for the current chat until the chat changes.
  bool _pinnedBarDismissed = false;
  final Set<String> _selectedMsgIds = {};
  bool get _selectionMode => _selectedMsgIds.isNotEmpty;
  /// Spec §4.7: selection bar slide animation (200ms easeOutCirc).
  late final AnimationController _selectionAnimCtrl;
  late final CurvedAnimation _selectionCurvedAnim;
  int _lastSelectionCount = 0;
  /// Spec §4.3: when true, the top bar shows an inline search text field
  /// instead of the title/subtitle. Toggled by the search button.
  bool _isSearching = false;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  /// Spec §4.3: search results — list of message IDs matching the query
  /// in the current chat, and the index of the currently highlighted result.
  List<String> _searchResultIds = [];
  int _searchResultIndex = -1;
  /// Currently active search query (for highlight in message list).
  String _activeSearchQuery = '';
  final Set<String> _hiddenMsgIds = {};
  List<String> _forwardingMsgIds = [];
  bool _forwardHideSender = false;
  bool get _isForwarding => _forwardingMsgIds.isNotEmpty;
  // GlobalKey attached to the top-bar more_vert IconButton so the Ctrl+\
  // keyboard shortcut (spec §24.4 `show_chat_menu`) can anchor the menu
  // at the same pixel position as clicking the button. The key is passed
  // into _ChatTopBar on every rebuild; the button's RenderBox is read
  // from `_moreVertKey.currentContext` when the shortcut fires.
  final GlobalKey _moreVertKey = GlobalKey();
  List<String> _detectedLinks = const [];
  WebPagePreview? _webPreview;
  bool _isDragOver = false;
  int _dragHoveredCard = 0; // 0=none, 1=document, 2=photo
  late final AnimationController _dragOverlayAnimCtrl;
  bool _webPreviewCancelled = false;
  String _lastPreviewUrl = '';
  Timer? _previewDebounce;
  AutocompleteQuery? _acQuery;
  List<MemberInfo> _acMembers = [];
  List<MemberInfo> _acFilteredMembers = [];
  List<EmojiEntry> _acFilteredEmojis = [];
  List<StickerInfoItem> _acStickerSuggestions = [];
  List<BotCommandInfo> _acBotCommands = [];
  List<BotCommandInfo> _acFilteredCommands = [];
  int _acSelectedIndex = 0;
  bool _acMembersLoaded = false;
  String? _acMembersChatId;
  bool _acCommandsLoaded = false;
  String? _acCommandsChatId;

  // Send As state (channel sender identity selector)
  List<SendAsPeerInfo> _sendAsPeers = [];
  String? _selectedSendAsPeerId;
  String? _sendAsChatId;

  // Inline bot results state
  InlineBotResults? _inlineBotResults;
  String? _inlineBotUsername;
  String? _inlineBotUserId;
  String _inlineBotQuery = '';
  Timer? _inlineBotDebounce;
  bool _inlineBotLoading = false;

  bool _emojiPanelVisible = false;

  // §23.8: Video processing toasts state
  bool _showVideoTipToast = false;
  bool _showVideoTooltip = false;
  String? _videoTooltipMsgId;
  Timer? _videoTipTimer;
  Timer? _videoTooltipTimer;
  bool _showVideoPublishedToast = false;
  String? _publishedVideoMsgId;
  Uint8List? _publishedVideoThumb;
  Timer? _videoPublishedTimer;
  bool _wasScheduledView = false;

  @override
  void initState() {
    super.initState();
    _selectionAnimCtrl = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _selectionCurvedAnim = CurvedAnimation(
      parent: _selectionAnimCtrl,
      curve: Curves.easeOutCirc,
    );
    _fabAnimCtrl = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _mentionsAnimCtrl = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _reactionsAnimCtrl = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _pollVotesAnimCtrl = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _dragOverlayAnimCtrl = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scheduledSlideCtrl = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
      value: 1.0,
    );
    _scrollController.addListener(_onScroll);
    // Register the app-level ArrowUp hook (spec §24.7: edit last outgoing
    // when compose field is empty and no edit/reply is active).
    ChatView.editLastOutgoingRequest = _editLastOutgoing;
    // Register the app-level Ctrl+R hook (spec §24.4 `read_chat`: mark the
    // currently active chat as read).
    ChatView.markActiveChatReadRequest = _markActiveChatRead;
    // Register the app-level Ctrl+\ hook (spec §24.4 `show_chat_menu`:
    // open the chat-level action menu anchored to the top-bar more_vert).
    ChatView.showActiveChatMenuRequest = _showActiveChatMenu;
    ChatView.showChatPreviewRequest = _showChatPreview;
    ChatView.archiveActiveChatRequest = _archiveActiveChat;
    ChatView.showScheduledRequest = _showScheduled;
    // Register the harness Ctrl+Shift+Enter hook (spec §24.4 line 2978:
    // always send regardless of mode). The real FocusNode.onKeyEvent path on
    // the compose TextField catches OS-delivered Ctrl+Shift+Enter directly;
    // this hook lets the automated harness exercise the same _sendMessage
    // entry point without having to synthesize the full modifier keystream.
    ChatView.sendComposeRequest = _requestSendCompose;
    // Register the Ctrl+Up / Ctrl+Down reply-cycling hook (spec §24.6 lines
    // 2982-2983). Real OS-delivered keystrokes land in the compose TextField's
    // FocusNode.onKeyEvent; this hook exists for the harness path AND for
    // app-level CallbackShortcuts so the shortcut works regardless of current
    // focus.
    ChatView.cycleReplyRequest = _cycleReply;
    ChatView.setComposeRequest = _setComposeText;
    ChatView.toggleFormatRequest = _toggleComposeFormat;
    ChatView.getComposeEntitiesRequest = _getComposeEntities;
    ChatView.scrollPageRequest = _scrollPage;
    ChatView.showSendFilesBoxRequest = (paths) {
      _uploadFiles(context.read<ChatState>(), paths);
    };
    ChatView.testVideoTipToast = _showVideoProcessingTip;
    ChatView.testVideoPublishedToast = () => showVideoPublishedToast('test', null);
    _searchController.addListener(_onSearchQueryChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchQueryChanged);
    if (ChatView.editLastOutgoingRequest == _editLastOutgoing) {
      ChatView.editLastOutgoingRequest = null;
    }
    if (ChatView.markActiveChatReadRequest == _markActiveChatRead) {
      ChatView.markActiveChatReadRequest = null;
    }
    if (ChatView.showActiveChatMenuRequest == _showActiveChatMenu) {
      ChatView.showActiveChatMenuRequest = null;
    }
    if (ChatView.showChatPreviewRequest == _showChatPreview) {
      ChatView.showChatPreviewRequest = null;
    }
    if (ChatView.archiveActiveChatRequest == _archiveActiveChat) {
      ChatView.archiveActiveChatRequest = null;
    }
    if (ChatView.showScheduledRequest == _showScheduled) {
      ChatView.showScheduledRequest = null;
    }
    if (ChatView.sendComposeRequest == _requestSendCompose) {
      ChatView.sendComposeRequest = null;
    }
    if (ChatView.cycleReplyRequest == _cycleReply) {
      ChatView.cycleReplyRequest = null;
    }
    if (ChatView.setComposeRequest == _setComposeText) {
      ChatView.setComposeRequest = null;
    }
    if (ChatView.toggleFormatRequest == _toggleComposeFormat) {
      ChatView.toggleFormatRequest = null;
    }
    if (ChatView.getComposeEntitiesRequest == _getComposeEntities) {
      ChatView.getComposeEntitiesRequest = null;
    }
    if (ChatView.scrollPageRequest == _scrollPage) {
      ChatView.scrollPageRequest = null;
    }
    ChatView.showSendFilesBoxRequest = null;
    if (ChatView.testVideoTipToast == _showVideoProcessingTip) {
      ChatView.testVideoTipToast = null;
    }
    ChatView.testVideoPublishedToast = null;
    _dragOverlayAnimCtrl.dispose();
    _scheduledSlideCtrl.dispose();
    _selectionCurvedAnim.dispose();
    _selectionAnimCtrl.dispose();
    _fabAnimCtrl.dispose();
    _mentionsAnimCtrl.dispose();
    _reactionsAnimCtrl.dispose();
    _pollVotesAnimCtrl.dispose();
    _composeController.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _previewDebounce?.cancel();
    _inlineBotDebounce?.cancel();
    _videoTipTimer?.cancel();
    _videoTooltipTimer?.cancel();
    _videoPublishedTimer?.cancel();
    super.dispose();
  }

  /// Open the chat-level action menu (Mute/Read/Pin/Archive/Leave) anchored
  /// at the top-bar more_vert button. No-op when no chat is active or the
  /// top-bar button hasn't been laid out yet (e.g. narrow-layout shell with
  /// chat column hidden). Returns true if the menu was shown.
  bool _showActiveChatMenu() {
    if (!mounted) return false;
    final chat = context.read<ChatState>().activeChat;
    if (chat == null) return false;
    final btnCtx = _moreVertKey.currentContext;
    if (btnCtx == null) return false;
    _ChatTopBar._showTopBarMenu(btnCtx, chat, onToggleInfo: widget.onToggleInfo);
    return true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Mark as read when opening a new chat.
    final chatState = context.read<ChatState>();
    final chatId = chatState.activeChat?.chatId;
    if (chatId != null && chatId != _lastChatId) {
      _lastChatId = chatId;
      // Chat changed — cancel any in-progress edit/reply/search so stale
      // state doesn't leak into the new chat's compose area.
      // Also reset pinned bar dismiss state and corner button tracking.
      _showMentionsBtn = false;
      _showReactionsBtn = false;
      _showPollVotesBtn = false;
      _mentionsAnimCtrl.value = 0;
      _reactionsAnimCtrl.value = 0;
      _pollVotesAnimCtrl.value = 0;
      if (_editingMsgId != null || _replyToId != null || _isSearching || _pinnedBarDismissed || _isForwarding) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _editingMsgId = null;
            _editOriginalText = '';
            _replyToId = null;
            _forwardingMsgIds = [];
            _forwardHideSender = false;
            _composeController.clear();
            _isSearching = false;
            _searchController.clear();
            _searchResultIds = [];
            _searchResultIndex = -1;
            _activeSearchQuery = '';
            _pinnedBarDismissed = false;
            _hiddenMsgIds.clear();
            _acQuery = null;
            _acFilteredMembers = [];
            _acFilteredCommands = [];
            _acStickerSuggestions = [];
            _acMembersLoaded = false;
            _acCommandsLoaded = false;
          });
        });
      }
      // Delay slightly to ensure messages are loaded.
      Future.microtask(() => chatState.markRead());
      // Fetch send-as peers for channels.
      _loadSendAs(chatState);
    }
  }

  void _onScroll() {
    // Load more messages when near the top (oldest messages).
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<ChatState>().loadMoreMessages();
    }
    // Spec §5: show FAB after scrolling 480px from bottom.
    final showFab = _scrollController.offset > 480;
    if (showFab != _showScrollToBottom) {
      _showScrollToBottom = showFab;
      if (showFab) {
        _fabAnimCtrl.forward();
      } else {
        _fabAnimCtrl.reverse();
      }
    }
    // Spec §49.4: destroy unread bar when user scrolls to bottom.
    if (_scrollController.offset < 10) {
      context.read<ChatState>().clearOpenedUnread();
    }
  }

  /// §23.8: Check if entering scheduled view with video messages and show tip toast.
  void _checkScheduledVideoTip(ChatState chatState) {
    if (!chatState.isScheduledView) return;
    final hasVideo = chatState.messages.any((m) => m.isVideo);
    if (!hasVideo) return;
    _showVideoProcessingTip();
  }

  void _showVideoProcessingTip() {
    if (_showVideoTipToast) return;
    setState(() => _showVideoTipToast = true);
    _videoTipTimer?.cancel();
    _videoTipTimer = Timer(const Duration(milliseconds: 4000), () {
      if (!mounted) return;
      setState(() {
        _showVideoTipToast = false;
        _showVideoTooltipForFirstVideo();
      });
    });
  }

  void _showVideoTooltipForFirstVideo() {
    final chatState = context.read<ChatState>();
    final videoMsg = chatState.messages.where((m) => m.isVideo).firstOrNull;
    if (videoMsg == null) return;
    setState(() {
      _showVideoTooltip = true;
      _videoTooltipMsgId = videoMsg.msgId;
    });
    _videoTooltipTimer?.cancel();
    _videoTooltipTimer = Timer(const Duration(milliseconds: 4000), () {
      if (!mounted) return;
      setState(() => _showVideoTooltip = false);
    });
  }

  /// §23.8: Show the "Scheduled video published" toast with thumbnail and "View" button.
  void showVideoPublishedToast(String msgId, [Uint8List? thumbnail]) {
    setState(() {
      _showVideoPublishedToast = true;
      _publishedVideoMsgId = msgId;
      _publishedVideoThumb = thumbnail;
    });
    _videoPublishedTimer?.cancel();
    _videoPublishedTimer = Timer(const Duration(milliseconds: 4000), () {
      if (!mounted) return;
      setState(() => _showVideoPublishedToast = false);
    });
  }

  void _dismissVideoPublishedToast() {
    _videoPublishedTimer?.cancel();
    setState(() => _showVideoPublishedToast = false);
  }

  bool _shouldShowContactStatusBar(ChatInfo chat) {
    if (chat.type != ChatType.dm) return false;
    if (chat.title == 'Saved Messages') return false;
    // Show for: non-contacts, blocked users, or bots.
    return !chat.isContact || chat.isBlocked || chat.isBot;
  }

  void _scrollToBottom() {
    final chatState = context.read<ChatState>();
    if (chatState.isJumped) {
      // If we jumped to a pinned message, reload latest messages first.
      chatState.returnToLatest();
    }
    _scrollController.animateTo(
      0, // reverse: true means 0 is the bottom
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCirc,
    );
  }

  void _scrollPage(bool isUp) {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final pageHeight = pos.viewportDimension * 0.85;
    final target = isUp
        ? (pos.pixels + pageHeight).clamp(pos.minScrollExtent, pos.maxScrollExtent)
        : (pos.pixels - pageHeight).clamp(pos.minScrollExtent, pos.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  /// Jump to the replied-to message when a user taps a reply preview.
  /// If the target message is already loaded, calls `jumpToMessage` with its
  /// timestamp so it becomes the newest visible (index 0 in the reversed list)
  /// and scrolls the viewport to it. If not loaded (e.g. older than the
  /// currently paged-in window), shows a snackbar instead of silently failing.
  void _showAllPinnedMessages(BuildContext context, ChatState chatState) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark ? const Color(0xFF6ab3f3) : const Color(0xFF168acd);
    final textColor = isDark ? const Color(0xFFdcdcdc) : const Color(0xFF000000);
    final dividerColor = isDark ? const Color(0xFF1e2c3a) : const Color(0xFFe8e8e8);

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1b2734) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Pinned Messages',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: accentColor,
                  ),
                ),
              ),
              Divider(height: 1, color: dividerColor),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.4,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: chatState.pinnedMessages.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: dividerColor),
                  itemBuilder: (_, i) {
                    final msg = chatState.pinnedMessages[i];
                    return InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        chatState.jumpToMessage(msg.timestamp);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_scrollController.hasClients) {
                            _scrollController.jumpTo(0);
                          }
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Container(
                              width: 2,
                              height: 36,
                              color: accentColor,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Pinned Message #${chatState.pinnedMessages.length - i}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: accentColor,
                                    ),
                                  ),
                                  Text(
                                    msg.contentText.isNotEmpty
                                        ? msg.contentText
                                        : '[media]',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: textColor,
                                    ),
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
            ],
          ),
        );
      },
    );
  }

  void _jumpToReply(ChatState chatState, String replyToId) {
    if (replyToId.isEmpty) return;
    final target = chatState.messages.where((m) => m.msgId == replyToId).firstOrNull;
    if (target == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message not loaded'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    chatState.jumpToMessage(target.timestamp);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  void _showMessageContextMenu(String msgId, Offset position, [String selectedText = '']) {
    final chatState = context.read<ChatState>();
    final msg = chatState.messages.where((m) => m.msgId == msgId).firstOrNull;
    if (msg == null) return;

    final isScheduled = widget.isScheduledView || chatState.isScheduledView;
    final chat = chatState.activeChat;
    final isGroupOrChannel = chat != null && (chat.type == ChatType.group || chat.type == ChatType.channel || chat.type == ChatType.topic);
    final isSavedMessages = chat != null && chat.title == 'Saved Messages';
    final hasPhoto = msg.mediaType == 1 && msg.mediaLocalPath.isNotEmpty;
    final hasVideo = msg.mediaType == 2 && msg.mediaLocalPath.isNotEmpty;
    final hasFile = msg.hasMedia && msg.mediaLocalPath.isNotEmpty && msg.mediaType == 8;
    final hasForwardOrigin = msg.forwardFrom.isNotEmpty;
    final isVoice = msg.mediaType == 3;
    final audioService = context.read<AudioService>();
    final isVoicePlaying = isVoice && audioService.isActiveMsg(msgId);
    final isSticker = msg.mediaType == 6;
    final isGif = msg.mediaType == 7;
    final isPoll = msg.isPoll;
    final hasVoted = isPoll && msg.pollOptions.any((o) => o.chosen);
    final canStopPoll = isPoll && msg.isOutgoing && !msg.pollClosed;
    final hasStickerSet = isSticker && msg.hasStickerSet;
    final hasDocId = msg.mediaRemoteRef.isNotEmpty;
    final hasLocalFile = msg.mediaLocalPath.isNotEmpty;
    final urls = _urlRegExp.allMatches(msg.contentText).map((m) => m.group(0)!).toSet().toList();

    final inSelection = _selectionMode && _selectedMsgIds.isNotEmpty;
    final canSendNow = isScheduled && msg.allowsSendNow;
    final canReschedule = isScheduled && msg.allowsReschedule;
    final groupMsgIds = (isScheduled && msg.isAlbumMember)
        ? chatState.messages
            .where((m) => m.groupedId == msg.groupedId && m.allowsSendNow)
            .map((m) => m.msgId)
            .toList()
        : <String>[msgId];
    final allSelectedCanSendNow = inSelection &&
        _selectedMsgIds.every((id) =>
            chatState.messages.where((m) => m.msgId == id).firstOrNull?.allowsSendNow ?? false);
    final allSelectedCanReschedule = inSelection &&
        _selectedMsgIds.length <= _kRescheduleLimit &&
        _selectedMsgIds.every((id) =>
            chatState.messages.where((m) => m.msgId == id).firstOrNull?.allowsReschedule ?? false);

    showTelegramMenu<String>(
      context: context,
      position: position,
      items: [
        // Pass 1: top actions (FillContextMenuItems inline)
        const TelegramMenuItem(value: 'reply', icon: Icon(Icons.reply), label: 'Reply'),
        if (msg.contentText.isNotEmpty)
          const TelegramMenuItem(value: 'quote_reply', icon: Icon(Icons.format_quote), label: 'Quote and Reply'),
        if (isVoicePlaying)
          TelegramMenuItem(value: 'voice_timecode', icon: const Icon(Icons.access_time), label: 'at ${_formatTimecode(audioService.position)}'),
        if (selectedText.isNotEmpty)
          const TelegramMenuItem(value: 'copy_selected', icon: Icon(Icons.copy), label: 'Copy Selected Text'),
        if (msg.contentText.isNotEmpty)
          const TelegramMenuItem(value: 'copy', icon: Icon(Icons.copy), label: 'Copy Text'),
        if (msg.contentText.isNotEmpty && !isPoll)
          const TelegramMenuItem(value: 'translate', icon: Icon(Icons.translate), label: 'Translate'),
        if (selectedText.isNotEmpty)
          const TelegramMenuItem(value: 'translate_selected', icon: Icon(Icons.translate), label: 'Translate Selected'),
        if (isPoll && msg.pollQuestion.isNotEmpty)
          const TelegramMenuItem(value: 'translate_poll', icon: Icon(Icons.translate), label: 'Translate Poll'),
        for (final url in urls.take(3))
          TelegramMenuItem(value: 'copy_url:$url', icon: const Icon(Icons.link), label: urls.length == 1 ? 'Copy Link' : 'Copy Link: ${Uri.tryParse(url)?.host ?? url}'),
        // Pass 2: message actions (AddMessageActions)
        const TelegramMenuItem.separator(),
        if (msg.editedAt > 0)
          const TelegramMenuItem(value: 'edits_history', icon: Icon(Icons.history), label: 'Edits History'),
        if (!isSavedMessages)
          const TelegramMenuItem(value: 'hide_message', icon: Icon(Icons.visibility_off), label: 'Hide Message'),
        if (isGroupOrChannel && msg.senderId.isNotEmpty)
          TelegramMenuItem(value: 'user_messages', icon: const Icon(Icons.person_search), label: "${msg.senderName.split(' ').first}'s Messages"),
        const TelegramMenuItem(value: 'repeat_message', icon: Icon(Icons.repeat), label: 'Repeat Message'),
        const TelegramMenuItem(value: 'message_details', icon: Icon(Icons.info_outline), label: 'Message Details'),
        if (hasForwardOrigin)
          const TelegramMenuItem(value: 'go_to_message', icon: Icon(Icons.shortcut), label: 'Go to Message'),
        if (msg.hasThread)
          TelegramMenuItem(
            value: 'view_thread',
            icon: const Icon(Icons.forum_outlined),
            label: msg.topicId.isNotEmpty
                ? 'View Topic'
                : msg.repliesIsComments
                    ? 'View Replies (${msg.repliesCount})'
                    : 'View Thread (${msg.repliesCount})',
          ),
        if (msg.isOutgoing)
          const TelegramMenuItem(value: 'edit', icon: Icon(Icons.edit), label: 'Edit'),
        TelegramMenuItem(
          value: 'pin',
          icon: Icon(msg.isPinned ? Icons.push_pin : Icons.push_pin_outlined),
          label: msg.isPinned ? 'Unpin Message' : 'Pin Message',
        ),
        if (chat != null)
          const TelegramMenuItem(value: 'copy_link', icon: Icon(Icons.link), label: 'Copy Message Link'),
        const TelegramMenuItem(value: 'forward', icon: Icon(Icons.forward), label: 'Forward'),
        if (canSendNow && !inSelection)
          const TelegramMenuItem(value: 'send_now', icon: Icon(Icons.send), label: 'Send now'),
        if (inSelection && allSelectedCanSendNow)
          const TelegramMenuItem(value: 'send_now_selected', icon: Icon(Icons.send), label: 'Send now selected'),
        const TelegramMenuItem(value: 'delete', icon: Icon(Icons.delete_outline), label: 'Delete', isAttention: true),
        if (hasPhoto)
          const TelegramMenuItem(value: 'save_image', icon: Icon(Icons.save_alt), label: 'Save Image'),
        if (hasVideo)
          const TelegramMenuItem(value: 'save_image', icon: Icon(Icons.save_alt), label: 'Save Video'),
        if (hasFile)
          const TelegramMenuItem(value: 'save_image', icon: Icon(Icons.save_alt), label: 'Save File'),
        if (isGif && hasDocId)
          const TelegramMenuItem(value: 'save_gif', icon: Icon(Icons.gif_box), label: 'Save GIF'),
        if (hasVoted && !msg.pollClosed)
          const TelegramMenuItem(value: 'retract_vote', icon: Icon(Icons.undo), label: 'Retract Vote'),
        if (isPoll && !msg.pollClosed)
          for (int i = 0; i < msg.pollOptions.length; i++)
            if (!msg.pollOptions[i].chosen)
              TelegramMenuItem(value: 'vote_option:$i', icon: const Icon(Icons.how_to_vote), label: 'Vote: ${msg.pollOptions[i].text}'),
        if (canStopPoll)
          const TelegramMenuItem(value: 'stop_poll', icon: Icon(Icons.poll), label: 'Stop Poll'),
        if (!msg.isOutgoing)
          const TelegramMenuItem(value: 'report', icon: Icon(Icons.flag_outlined), label: 'Report', isAttention: true),
        const TelegramMenuItem(value: 'select', icon: Icon(Icons.check_circle_outline), label: 'Select'),
        if (canReschedule && !inSelection)
          const TelegramMenuItem(value: 'reschedule', icon: Icon(Icons.schedule_send), label: 'Reschedule'),
        if (inSelection && allSelectedCanReschedule)
          const TelegramMenuItem(value: 'reschedule_selected', icon: Icon(Icons.schedule_send), label: 'Reschedule selected'),
        const TelegramMenuItem(value: 'read_until', icon: Icon(Icons.done_all), label: 'Read Until Here'),
        // Pass 3: post-actions
        const TelegramMenuItem.separator(),
        if (hasStickerSet)
          const TelegramMenuItem(value: 'view_sticker_set', icon: Icon(Icons.emoji_emotions), label: 'View Sticker Set'),
        if (isSticker && hasDocId)
          const TelegramMenuItem(value: 'fave_sticker', icon: Icon(Icons.star_outline), label: 'Add to Favorites'),
        if (hasLocalFile)
          const TelegramMenuItem(value: 'show_in_folder', icon: Icon(Icons.folder_open), label: 'Show in Folder'),
      ],
    ).then((action) {
      if (action == null) return;
      switch (action) {
        case 'reply':
          setState(() => _replyToId = msgId);
        case 'quote_reply':
          _quoteAndReply(msg);
        case 'voice_timecode':
          _insertVoiceTimecode(msg);
        case 'copy_selected':
          Clipboard.setData(ClipboardData(text: selectedText));
        case 'translate_selected':
          _translateText(msg, selectedText: selectedText);
        case 'copy':
          Clipboard.setData(ClipboardData(text: msg.contentText));
        case 'translate':
          _translateText(msg);
        case 'translate_poll':
          _translatePoll(msg);
        case 'retract_vote':
          _retractPollVote(msg);
        case 'stop_poll':
          _stopPoll(msg);
        case 'go_to_message':
          _goToForwardedMessage(msg);
        case 'view_thread':
          _viewThread(msg);
        case 'forward':
          _forwardSingle(context, chatState, msgId);
        case 'select':
          _modifySelection(() => _selectedMsgIds.add(msgId));
        case 'pin':
          chatState.pinMessage(msgId, !msg.isPinned);
        case 'edit':
          setState(() {
            _editingMsgId = msgId;
            _editOriginalText = msg.contentText;
            _replyToId = null;
            _composeController.text = msg.contentText;
            _composeController.selection = TextSelection.fromPosition(
              TextPosition(offset: _composeController.text.length),
            );
          });
        case 'send_now':
          _showSendNowConfirm(chatState, groupMsgIds);
        case 'send_now_selected':
          _showSendNowConfirm(chatState, _selectedMsgIds.toList());
        case 'reschedule':
          _showReschedulePicker(chatState, [msgId], msg);
        case 'reschedule_selected':
          _showRescheduleSelectedPicker(chatState);
        case 'save_image':
          _saveMediaToDownloads(msg);
        case 'save_gif':
          _saveGif(msg);
        case 'view_sticker_set':
          StickerPackViewer.show(context, msg);
        case 'fave_sticker':
          _faveSticker(msg);
        case 'copy_link':
          _copyMessageLink(msg, chat);
        case 'show_in_folder':
          _showInFolder(msg);
        case 'report':
          _reportMessage(msg);
        case 'delete':
          _showDeleteMessageConfirm(chatState, msg, chat);
        case 'edits_history':
          _showEditsHistory(msg);
        case 'hide_message':
          _hideMessage(msgId);
        case 'user_messages':
          _showUserMessages(chatState, msg);
        case 'repeat_message':
          _repeatMessage(chatState, msg);
        case 'message_details':
          _showMessageDetails(msg, position);
        case 'read_until':
          _readUntilHere(chatState, msg);
        default:
          if (action.startsWith('copy_url:')) {
            final url = action.substring('copy_url:'.length);
            Clipboard.setData(ClipboardData(text: url));
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Link copied'), behavior: SnackBarBehavior.floating, duration: Duration(seconds: 2)),
              );
            }
          } else if (action.startsWith('vote_option:')) {
            final idx = int.tryParse(action.substring('vote_option:'.length));
            if (idx != null) _votePollOption(msg, idx);
          }
      }
    });
  }

  void _quoteAndReply(CachedMessage msg) {
    setState(() {
      _replyToId = msg.msgId;
      final quoted = msg.contentText.split('\n').map((l) => '> $l').join('\n');
      _composeController.text = '$quoted\n';
      _composeController.selection = TextSelection.fromPosition(
        TextPosition(offset: _composeController.text.length),
      );
    });
  }

  void _goToForwardedMessage(CachedMessage msg) {
    final chatState = context.read<ChatState>();
    chatState.jumpToMessage(msg.timestamp);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  void _viewThread(CachedMessage msg) {
    final chatState = context.read<ChatState>();
    if (msg.topicId.isNotEmpty) {
      chatState.setActiveChannel(msg.topicId);
      return;
    }
    if (msg.repliesChannelId.isNotEmpty) {
      chatState.openChatById(msg.repliesChannelId);
      return;
    }
    if (msg.hasReplies) {
      chatState.setActiveChannel(msg.msgId);
    }
  }

  void _saveMediaToDownloads(CachedMessage msg) async {
    if (msg.mediaLocalPath.isEmpty) return;
    final sourceFile = File(msg.mediaLocalPath);
    if (!await sourceFile.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File not found'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    final downloadsDir = Directory('${Platform.environment['HOME'] ?? '/tmp'}/Downloads');
    if (!await downloadsDir.exists()) {
      await downloadsDir.create(recursive: true);
    }
    final fileName = msg.mediaFileName.isNotEmpty
        ? msg.mediaFileName
        : sourceFile.uri.pathSegments.last;
    var destPath = '${downloadsDir.path}/$fileName';
    var counter = 1;
    while (await File(destPath).exists()) {
      final ext = fileName.contains('.') ? '.${fileName.split('.').last}' : '';
      final base = fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName;
      destPath = '${downloadsDir.path}/${base}_($counter)$ext';
      counter++;
    }
    await sourceFile.copy(destPath);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved to ${destPath.split('/').last}'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _faveSticker(CachedMessage msg) async {
    if (msg.mediaRemoteRef.isEmpty) return;
    final fileId = int.tryParse(msg.mediaRemoteRef);
    if (fileId == null) return;
    final engine = context.read<EngineService>();
    final ok = await engine.faveSticker(msg.accountId, fileId, extra: msg.mediaExtra);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Added to favorites' : 'Failed to add to favorites'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _saveGif(CachedMessage msg) async {
    if (msg.mediaRemoteRef.isEmpty) return;
    final fileId = int.tryParse(msg.mediaRemoteRef);
    if (fileId == null) return;
    final engine = context.read<EngineService>();
    final ok = await engine.saveGif(msg.accountId, fileId, extra: msg.mediaExtra);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'GIF saved' : 'Failed to save GIF'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _copyMessageLink(CachedMessage msg, ChatInfo? chat) {
    if (chat == null) return;
    final chatId = chat.chatId;
    final msgId = msg.msgId;
    String link;
    if (chat.type == ChatType.channel || chat.type == ChatType.group) {
      final numericId = chatId.replaceFirst('-100', '').replaceFirst('-', '');
      link = 'https://t.me/c/$numericId/$msgId';
    } else {
      link = 'https://t.me/c/$chatId/$msgId';
    }
    Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Message link copied'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showInFolder(CachedMessage msg) async {
    if (msg.mediaLocalPath.isEmpty) return;
    final file = File(msg.mediaLocalPath);
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File not found'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    final dir = file.parent.path;
    if (Platform.isLinux) {
      await Process.run('xdg-open', [dir]);
    } else if (Platform.isMacOS) {
      await Process.run('open', ['-R', msg.mediaLocalPath]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', ['/select,', msg.mediaLocalPath]);
    }
  }

  void _showSendNowConfirm(ChatState chatState, List<String> msgIds) {
    if (msgIds.isEmpty) return;
    final count = msgIds.length;
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send now'),
        content: Text(count == 1
            ? 'Send this message now?'
            : 'Send $count messages now?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Send')),
        ],
      ),
    ).then((confirmed) {
      if (confirmed != true || !mounted) return;
      final sorted = List<String>.from(msgIds)
        ..sort((a, b) {
          final ma = chatState.messages.where((m) => m.msgId == a).firstOrNull;
          final mb = chatState.messages.where((m) => m.msgId == b).firstOrNull;
          return (ma?.scheduleDate ?? 0).compareTo(mb?.scheduleDate ?? 0);
        });
      chatState.sendScheduledNow(sorted);
      if (_selectionMode) _modifySelection(() => _selectedMsgIds.clear());
    });
  }

  Future<void> _showReschedulePicker(ChatState chatState, List<String> msgIds, CachedMessage msg) async {
    final initialDate = msg.isScheduledUntilOnline
        ? null
        : DateTime.fromMillisecondsSinceEpoch(msg.scheduleDate * 1000);
    final chat = chatState.activeChat;
    final isSelf = chat != null && chat.title == 'Saved Messages';
    final result = await showChooseDateTimeBox(
      context,
      initialDate: initialDate,
      isSelfChat: isSelf,
      isScheduledToUser: chat?.type == ChatType.dm && !isSelf,
    );
    if (result == null || !mounted) return;
    final baseTs = result.sendWhenOnline
        ? ScheduledMessages.kScheduledUntilOnlineTimestamp
        : result.dateTime.millisecondsSinceEpoch ~/ 1000;
    final deduped = _deduplicateGroupedIds(chatState, msgIds);
    for (var i = 0; i < deduped.length; i++) {
      await chatState.rescheduleMessage(deduped[i], baseTs + i);
    }
  }

  Future<void> _showRescheduleSelectedPicker(ChatState chatState) async {
    final selected = _selectedMsgIds.toList();
    if (selected.isEmpty) return;
    final firstMsg = chatState.messages
        .where((m) => selected.contains(m.msgId))
        .firstOrNull;
    if (firstMsg == null) return;
    await _showReschedulePicker(chatState, selected, firstMsg);
    if (mounted) _modifySelection(() => _selectedMsgIds.clear());
  }

  List<String> _deduplicateGroupedIds(ChatState chatState, List<String> msgIds) {
    final seen = <String>{};
    final result = <String>[];
    for (final id in msgIds) {
      final msg = chatState.messages.where((m) => m.msgId == id).firstOrNull;
      if (msg == null) continue;
      if (msg.isAlbumMember) {
        if (seen.contains(msg.groupedId)) continue;
        seen.add(msg.groupedId);
      }
      result.add(id);
    }
    result.sort((a, b) {
      final ma = chatState.messages.where((m) => m.msgId == a).firstOrNull;
      final mb = chatState.messages.where((m) => m.msgId == b).firstOrNull;
      return (ma?.scheduleDate ?? 0).compareTo(mb?.scheduleDate ?? 0);
    });
    return result;
  }

  static String _formatTimecode(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _insertVoiceTimecode(CachedMessage msg) {
    final audioService = context.read<AudioService>();
    final timecode = _formatTimecode(audioService.position);
    setState(() {
      _replyToId = msg.msgId;
      _composeController.text = timecode;
      _composeController.selection = TextSelection.fromPosition(
        TextPosition(offset: timecode.length),
      );
    });
  }

  void _translateText(CachedMessage msg, {String selectedText = ''}) async {
    final chatState = context.read<ChatState>();
    final engine = context.read<EngineService>();
    final chat = chatState.activeChat;
    if (chat == null) return;
    final langCode = ui.PlatformDispatcher.instance.locale.languageCode;
    final result = await engine.translateText(
      msg.accountId,
      chat.chatId,
      msg.msgId,
      langCode,
    );
    if (!mounted) return;
    if (result == null || result.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Translation not available'), behavior: SnackBarBehavior.floating, duration: Duration(seconds: 2)),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Translation'),
        content: SelectableText(result),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: result));
              Navigator.pop(ctx);
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _translatePoll(CachedMessage msg) async {
    final chatState = context.read<ChatState>();
    final engine = context.read<EngineService>();
    final chat = chatState.activeChat;
    if (chat == null) return;
    final langCode = ui.PlatformDispatcher.instance.locale.languageCode;
    final result = await engine.translateText(
      msg.accountId,
      chat.chatId,
      msg.msgId,
      langCode,
    );
    if (!mounted) return;
    if (result == null || result.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Translation not available'), behavior: SnackBarBehavior.floating, duration: Duration(seconds: 2)),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Poll Translation'),
        content: SelectableText(result),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: result));
              Navigator.pop(ctx);
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _retractPollVote(CachedMessage msg) async {
    final chatState = context.read<ChatState>();
    final engine = context.read<EngineService>();
    final chat = chatState.activeChat;
    if (chat == null) return;
    final ok = await engine.retractPollVote(msg.accountId, chat.chatId, msg.msgId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Vote retracted' : 'Failed to retract vote'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
    if (ok) chatState.refreshMessages();
  }

  void _stopPoll(CachedMessage msg) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop Poll'),
        content: const Text('Are you sure you want to stop this poll? No more votes will be accepted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Stop Poll'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final chatState = context.read<ChatState>();
    final engine = context.read<EngineService>();
    final chat = chatState.activeChat;
    if (chat == null) return;
    final ok = await engine.stopPoll(msg.accountId, chat.chatId, msg.msgId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Poll stopped' : 'Failed to stop poll'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
    if (ok) chatState.refreshMessages();
  }

  void _votePollOption(CachedMessage msg, int optionIndex) async {
    final chatState = context.read<ChatState>();
    final engine = context.read<EngineService>();
    final chat = chatState.activeChat;
    if (chat == null) return;
    final ok = await engine.votePoll(msg.accountId, chat.chatId, msg.msgId, optionIndex);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Vote submitted' : 'Failed to vote'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
    if (ok) chatState.refreshMessages();
  }

  void _reportMessage(CachedMessage msg) async {
    final chatState = context.read<ChatState>();
    final engine = context.read<EngineService>();
    final chat = chatState.activeChat;
    if (chat == null) return;
    final msgIdInt = int.tryParse(msg.msgId);
    if (msgIdInt == null) return;

    List<int> currentOption = [];

    while (true) {
      final result = await engine.reportMessage(
        msg.accountId,
        chat.chatId,
        [msgIdInt],
        option: currentOption,
      );
      if (!mounted) return;

      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report failed'), behavior: SnackBarBehavior.floating, duration: Duration(seconds: 2)),
        );
        return;
      }

      if (result.resultType == 'reported') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message reported'), behavior: SnackBarBehavior.floating, duration: Duration(seconds: 2)),
        );
        return;
      }

      if (result.resultType == 'choose_option') {
        final picked = await showDialog<List<int>>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text(result.title.isNotEmpty ? result.title : 'Report'),
            children: result.options.map((opt) => SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, opt.option),
              child: Text(opt.text),
            )).toList(),
          ),
        );
        if (picked == null || !mounted) return;
        currentOption = picked;
        continue;
      }

      if (result.resultType == 'add_comment') {
        final comment = await showDialog<String>(
          context: context,
          builder: (ctx) {
            final controller = TextEditingController();
            return AlertDialog(
              title: const Text('Additional comment'),
              content: TextField(
                controller: controller,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: result.commentOptional ? 'Optional comment...' : 'Describe the issue...',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, controller.text),
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
        if (comment == null || !mounted) return;
        final finalResult = await engine.reportMessage(
          msg.accountId,
          chat.chatId,
          [msgIdInt],
          option: result.commentOption,
          message: comment,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(finalResult?.resultType == 'reported' ? 'Message reported' : 'Report submitted'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }

      return;
    }
  }

  // AyuGram §9.6: Edits History — show edit timestamp info.
  void _showEditsHistory(CachedMessage msg) {
    final editDate = DateTime.fromMillisecondsSinceEpoch(msg.editedAt);
    final origDate = DateTime.fromMillisecondsSinceEpoch(msg.timestamp);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edits History'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _detailRow('Original', _formatFullDate(origDate)),
            const SizedBox(height: 8),
            _detailRow('Last edited', _formatFullDate(editDate)),
            if (msg.contentText.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Text('Current text:', style: Theme.of(ctx).textTheme.labelSmall),
              const SizedBox(height: 4),
              Text(msg.contentText, maxLines: 8, overflow: TextOverflow.ellipsis),
            ],
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  // AyuGram §9.6: Hide Message — locally remove from view.
  void _hideMessage(String msgId) {
    setState(() => _hiddenMsgIds.add(msgId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Message hidden'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => setState(() => _hiddenMsgIds.remove(msgId)),
        ),
      ),
    );
  }

  // AyuGram §9.6: User's Messages — search messages by this sender in the current chat.
  void _showUserMessages(ChatState chatState, CachedMessage msg) {
    final senderMsgs = chatState.messages
        .where((m) => m.senderId == msg.senderId && !m.isService)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (senderMsgs.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text("${msg.senderName}'s Messages (${senderMsgs.length})",
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: senderMsgs.length,
                    itemBuilder: (_, i) {
                      final m = senderMsgs[i];
                      final dt = DateTime.fromMillisecondsSinceEpoch(m.timestamp);
                      return ListTile(
                        dense: true,
                        title: Text(
                          m.contentText.isNotEmpty ? m.contentText : (m.hasMedia ? '[Media]' : '[Empty]'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                        subtitle: Text(_formatFullDate(dt), style: theme.textTheme.labelSmall),
                        onTap: () {
                          Navigator.pop(ctx);
                          chatState.jumpToMessage(m.timestamp);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // AyuGram §9.6: Repeat Message — re-send the message content.
  void _repeatMessage(ChatState chatState, CachedMessage msg) {
    if (msg.contentText.isNotEmpty) {
      chatState.sendMessage(msg.contentText);
    } else if (msg.hasMedia && msg.forwardFrom.isNotEmpty) {
      _forwardSingle(context, chatState, msg.msgId);
    } else if (msg.contentText.isNotEmpty || msg.hasMedia) {
      chatState.sendMessage(msg.contentText.isNotEmpty ? msg.contentText : '[Repeated message]');
    }
  }

  // AyuGram §9.6: Message Details — submenu with metadata (views, shares, ID, dates, media info).
  void _showMessageDetails(CachedMessage msg, Offset position) {
    final origDate = DateTime.fromMillisecondsSinceEpoch(msg.timestamp);
    final editDate = msg.editedAt > 0 ? DateTime.fromMillisecondsSinceEpoch(msg.editedAt) : null;

    final items = <TelegramMenuItem<String>>[
      if (msg.views > 0)
        TelegramMenuItem(value: 'views', icon: const Icon(Icons.visibility), label: 'Views: ${msg.views}'),
      if (msg.forwards > 0)
        TelegramMenuItem(value: 'forwards', icon: const Icon(Icons.forward), label: 'Shares: ${msg.forwards}'),
      TelegramMenuItem(value: 'msg_id', icon: const Icon(Icons.tag), label: 'ID: ${msg.msgId}'),
      TelegramMenuItem(value: 'date', icon: const Icon(Icons.calendar_today), label: 'Date: ${_formatFullDate(origDate)}'),
      if (editDate != null)
        TelegramMenuItem(value: 'edit_date', icon: const Icon(Icons.edit_calendar), label: 'Edited: ${_formatFullDate(editDate)}'),
      if (msg.forwardFrom.isNotEmpty)
        TelegramMenuItem(value: 'fwd_from', icon: const Icon(Icons.shortcut), label: 'From: ${msg.forwardFrom}'),
      if (msg.senderId.isNotEmpty)
        TelegramMenuItem(value: 'sender_id', icon: const Icon(Icons.person), label: 'Sender ID: ${msg.senderId}'),
      TelegramMenuItem(value: 'chat_id', icon: const Icon(Icons.chat), label: 'Chat ID: ${msg.chatId}'),
      if (msg.hasMedia) ...[
        const TelegramMenuItem.separator(),
        if (msg.mediaMimeType.isNotEmpty)
          TelegramMenuItem(value: 'mime', icon: const Icon(Icons.description), label: 'Type: ${msg.mediaMimeType}'),
        if (msg.mediaFileSize > 0)
          TelegramMenuItem(value: 'size', icon: const Icon(Icons.storage), label: 'Size: ${_formatFileSize(msg.mediaFileSize)}'),
        if (msg.mediaFileName.isNotEmpty)
          TelegramMenuItem(value: 'filename', icon: const Icon(Icons.insert_drive_file), label: 'File: ${msg.mediaFileName}'),
        if (msg.mediaWidth > 0 && msg.mediaHeight > 0)
          TelegramMenuItem(value: 'resolution', icon: const Icon(Icons.aspect_ratio), label: 'Resolution: ${msg.mediaWidth}×${msg.mediaHeight}'),
        if (msg.mediaDuration > 0)
          TelegramMenuItem(value: 'duration', icon: const Icon(Icons.timer), label: 'Duration: ${_formatDuration(msg.mediaDuration)}'),
      ],
    ];

    showTelegramMenu<String>(
      context: context,
      position: position,
      items: items,
    ).then((value) {
      if (value == null) return;
      final copyText = switch (value) {
        'views' => msg.views.toString(),
        'forwards' => msg.forwards.toString(),
        'msg_id' => msg.msgId,
        'date' => _formatFullDate(origDate),
        'edit_date' => editDate != null ? _formatFullDate(editDate) : '',
        'fwd_from' => msg.forwardFrom,
        'sender_id' => msg.senderId,
        'chat_id' => msg.chatId,
        'mime' => msg.mediaMimeType,
        'size' => msg.mediaFileSize.toString(),
        'filename' => msg.mediaFileName,
        'resolution' => '${msg.mediaWidth}×${msg.mediaHeight}',
        'duration' => _formatDuration(msg.mediaDuration),
        _ => '',
      };
      if (copyText.isNotEmpty) {
        Clipboard.setData(ClipboardData(text: copyText));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Copied'), behavior: SnackBarBehavior.floating, duration: Duration(seconds: 1)),
          );
        }
      }
    });
  }

  // AyuGram §9.6: Read Until Here — mark messages read up to this point.
  void _readUntilHere(ChatState chatState, CachedMessage msg) {
    final chat = chatState.activeChat;
    if (chat == null) return;
    final engine = context.read<EngineService>();
    engine.markChatRead(chat.accountId, chat.chatId, msg.msgId);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Marked as read'), behavior: SnackBarBehavior.floating, duration: Duration(seconds: 2)),
    );
  }

  static String _formatFullDate(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} $h:$m:$s';
  }

  static String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  static String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _detailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 100, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
      ],
    );
  }

  void _showSenderProfile(BuildContext context, ChatState chatState, String senderId) {
    // Find sender info from messages.
    final msg = chatState.messages.where((m) => m.senderId == senderId).firstOrNull;
    final avatarB64 = chatState.senderAvatar(senderId);
    final senderName = msg?.senderName ?? senderId;

    showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        const avatarRadius = 36.0;
        Widget avatar;
        if (avatarB64 != null && avatarB64.isNotEmpty) {
          try {
            final bytes = base64Decode(avatarB64);
            avatar = ClipOval(
              child: Image.memory(bytes, width: avatarRadius * 2, height: avatarRadius * 2, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _senderFallbackAvatar(senderId, senderName, avatarRadius)),
            );
          } catch (_) {
            avatar = _senderFallbackAvatar(senderId, senderName, avatarRadius);
          }
        } else {
          avatar = _senderFallbackAvatar(senderId, senderName, avatarRadius);
        }

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Profile header with avatar + name.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                  child: Row(
                    children: [
                      avatar,
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              senderName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'ID: $senderId',
                              style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Actions.
                InkWell(
                  onTap: () {
                    Navigator.of(ctx).pop();
                    final dmChat = chatState.chats.where((c) =>
                      c.chatId == senderId && c.accountId == chatState.activeChat?.accountId).firstOrNull;
                    if (dmChat != null) chatState.openChat(dmChat);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Icon(Icons.message_outlined, size: 20, color: theme.colorScheme.primary),
                        const SizedBox(width: 14),
                        Text('Send Message', style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showUserContextMenu(BuildContext context, ChatState chatState, String senderId, Offset position) async {
    final chat = chatState.activeChat;
    if (chat == null) return;
    final accountId = chat.accountId;
    final isGroupOrChannel = chat.type == ChatType.group || chat.type == ChatType.channel || chat.type == ChatType.topic;

    final engine = context.read<EngineService>();
    final profile = await engine.getUserProfile(accountId, senderId);

    final senderMsg = chatState.messages.where((m) => m.senderId == senderId).firstOrNull;
    final senderName = profile?.displayName ?? senderMsg?.senderName ?? senderId;
    final username = profile?.username ?? '';
    final isContact = profile?.isContact ?? false;
    final isBlocked = profile?.isBlocked ?? false;
    final isBot = profile?.isBot ?? false;

    if (!mounted) return;

    final result = await showTelegramMenu<String>(
      context: context,
      position: position,
      items: [
        const TelegramMenuItem(value: 'view_profile', icon: Icon(Icons.person_outline), label: 'View Profile'),
        if (isGroupOrChannel && !isBot)
          TelegramMenuItem(value: 'mention', icon: const Icon(Icons.alternate_email), label: 'Mention $senderName'),
        const TelegramMenuItem(value: 'send_message', icon: Icon(Icons.message_outlined), label: 'Send Message'),
        const TelegramMenuItem.separator(),
        if (!isContact)
          const TelegramMenuItem(value: 'add_contact', icon: Icon(Icons.person_add_outlined), label: 'Add Contact')
        else
          const TelegramMenuItem(value: 'delete_contact', icon: Icon(Icons.person_remove_outlined), label: 'Delete Contact'),
        if (!isBot)
          const TelegramMenuItem(value: 'share_contact', icon: Icon(Icons.share), label: 'Share Contact'),
        const TelegramMenuItem.separator(),
        TelegramMenuItem(
          value: isBlocked ? 'unblock' : 'block',
          icon: Icon(isBlocked ? Icons.lock_open : Icons.block),
          label: isBlocked ? 'Unblock User' : 'Block User',
          isAttention: !isBlocked,
        ),
        const TelegramMenuItem(value: 'report', icon: Icon(Icons.flag_outlined), label: 'Report', isAttention: true),
        if (isGroupOrChannel) ...[
          const TelegramMenuItem.separator(),
          const TelegramMenuItem(value: 'promote', icon: Icon(Icons.admin_panel_settings_outlined), label: 'Promote to Admin'),
          const TelegramMenuItem(value: 'restrict', icon: Icon(Icons.do_not_disturb_on_outlined), label: 'Restrict User'),
          const TelegramMenuItem(value: 'ban', icon: Icon(Icons.gavel), label: 'Ban User', isAttention: true),
          const TelegramMenuItem(value: 'delete_all', icon: Icon(Icons.delete_sweep_outlined), label: 'Delete All from User', isAttention: true),
        ],
      ],
    );

    if (result == null || !mounted) return;

    switch (result) {
      case 'view_profile':
        _showSenderProfile(context, chatState, senderId);
      case 'mention':
        final mention = username.isNotEmpty ? '@$username ' : senderName;
        final text = _composeController.text;
        final newText = text.isEmpty ? mention : '$text $mention';
        _composeController.text = newText;
        _composeController.selection = TextSelection.fromPosition(
          TextPosition(offset: newText.length),
        );
      case 'send_message':
        final dmChat = chatState.chats.where((c) =>
          c.chatId == senderId && c.accountId == accountId).firstOrNull;
        if (dmChat != null) chatState.openChat(dmChat);
      case 'add_contact':
        _showAddContactDialog(context, engine, accountId, senderId, senderName);
      case 'delete_contact':
        try {
          await engine.deleteContact(accountId, senderId);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$senderName removed from contacts')),
            );
          }
        } catch (_) {}
      case 'share_contact':
        final phone = profile?.phone ?? '';
        if (phone.isNotEmpty) {
          Clipboard.setData(ClipboardData(text: phone));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Contact phone copied: $phone')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Phone number not available')),
            );
          }
        }
      case 'block':
        final confirmed = await _showConfirmDialog(
          context, 'Block User', 'Block $senderName? They will not be able to message you.');
        if (confirmed && mounted) {
          try {
            await engine.blockUser(accountId, senderId);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$senderName blocked')),
              );
            }
          } catch (_) {}
        }
      case 'unblock':
        try {
          await engine.unblockUser(accountId, senderId);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$senderName unblocked')),
            );
          }
        } catch (_) {}
      case 'report':
        try {
          await engine.reportSpam(accountId, senderId);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('User reported')),
            );
          }
        } catch (_) {}
      case 'promote':
        final confirmed = await _showConfirmDialog(
          context, 'Promote to Admin', 'Promote $senderName to admin?');
        if (confirmed && mounted) {
          try {
            await engine.promoteAdmin(accountId, chat.chatId, senderId);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$senderName promoted to admin')),
              );
            }
          } catch (_) {}
        }
      case 'restrict':
        final confirmed = await _showConfirmDialog(
          context, 'Restrict User', 'Restrict $senderName?');
        if (confirmed && mounted) {
          try {
            await engine.restrictMember(accountId, chat.chatId, senderId);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$senderName restricted')),
              );
            }
          } catch (_) {}
        }
      case 'ban':
        final confirmed = await _showConfirmDialog(
          context, 'Ban User', 'Ban $senderName from this chat? This action cannot be undone easily.');
        if (confirmed && mounted) {
          try {
            await engine.banMember(accountId, chat.chatId, senderId);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('$senderName banned')),
              );
            }
          } catch (_) {}
        }
      case 'delete_all':
        final confirmed = await _showConfirmDialog(
          context, 'Delete All Messages', 'Delete all messages from $senderName in this chat?');
        if (confirmed && mounted) {
          try {
            await engine.banMember(accountId, chat.chatId, senderId);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('All messages from $senderName deleted')),
              );
            }
          } catch (_) {}
        }
    }
  }

  void _showAddContactDialog(BuildContext context, EngineService engine, String accountId, String userId, String displayName) {
    final parts = displayName.split(' ');
    final firstCtrl = TextEditingController(text: parts.first);
    final lastCtrl = TextEditingController(text: parts.length > 1 ? parts.sublist(1).join(' ') : '');
    final phoneCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: const Text('Add Contact'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: firstCtrl,
                decoration: const InputDecoration(labelText: 'First name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: lastCtrl,
                decoration: const InputDecoration(labelText: 'Last name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'Phone number'),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                try {
                  await engine.addContact(
                    accountId,
                    phoneCtrl.text.trim(),
                    firstCtrl.text.trim(),
                    lastCtrl.text.trim(),
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${firstCtrl.text.trim()} added to contacts')),
                    );
                  }
                } catch (_) {}
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _showConfirmDialog(BuildContext context, String title, String message) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ) ?? false;
  }

  static const _colorIndexRemap = [0, 7, 4, 1, 6, 3, 5];
  static const _userpicColors = [
    Color(0xFFe17076), Color(0xFF7bc862), Color(0xFFe5ca77), Color(0xFF65aadd),
    Color(0xFFa695e7), Color(0xFFee7aae), Color(0xFF6ec9cb), Color(0xFFe8a64e),
  ];

  static Widget _senderFallbackAvatar(String senderId, String name, double radius) {
    final numId = int.tryParse(senderId) ?? senderId.hashCode.abs();
    final paletteIndex = _colorIndexRemap[numId.abs() % 7];
    return CircleAvatar(
      radius: radius,
      backgroundColor: _userpicColors[paletteIndex],
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(color: Colors.white, fontSize: radius * 0.6, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// Spec §4.7: modify selection set and trigger slide animation on transitions.
  void _modifySelection(void Function() fn) {
    final wasSelecting = _selectionMode;
    setState(fn);
    if (_selectionMode) _lastSelectionCount = _selectedMsgIds.length;
    if (_selectionMode && !wasSelecting) {
      _selectionAnimCtrl.forward();
    } else if (!_selectionMode && wasSelecting) {
      _selectionAnimCtrl.reverse();
    }
  }

  void _sendNowSelected(ChatState chatState) {
    _showSendNowConfirm(chatState, _selectedMsgIds.toList());
  }

  void _deleteSelected(ChatState chatState) {
    final chat = chatState.activeChat;
    final count = _selectedMsgIds.length;
    final ids = _selectedMsgIds.toList();
    showDeleteConfirmBox(
      context,
      mode: DeleteBoxMode.bulkMessages,
      chatType: chat?.type ?? ChatType.dm,
      peerName: chat?.title ?? '',
      messageCount: count,
      canRevoke: chat?.type == ChatType.dm,
    ).then((result) {
      if (!result.confirmed) return;
      for (final id in ids) {
        chatState.deleteMessage(id);
      }
      _modifySelection(() => _selectedMsgIds.clear());
    });
  }

  void _showDeleteMessageConfirm(ChatState chatState, CachedMessage msg, ChatInfo? chat) {
    showDeleteConfirmBox(
      context,
      mode: DeleteBoxMode.singleMessage,
      chatType: chat?.type ?? ChatType.dm,
      peerName: chat?.title ?? '',
      canRevoke: chat?.type == ChatType.dm && msg.isOutgoing,
    ).then((result) {
      if (result.confirmed) chatState.deleteMessage(msg.msgId);
    });
  }

  void _forwardSingle(BuildContext context, ChatState chatState, String msgId) {
    setState(() {
      _forwardingMsgIds = [msgId];
      _forwardHideSender = false;
    });
  }

  void _forwardSelected(BuildContext context, ChatState chatState) {
    final msgIds = _selectedMsgIds.toList();
    _modifySelection(() => _selectedMsgIds.clear());
    setState(() {
      _forwardingMsgIds = msgIds;
      _forwardHideSender = false;
    });
  }

  void _executeForward(BuildContext context, ChatState chatState) {
    final msgIds = _forwardingMsgIds.toList();
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Forward',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (ctx, anim, _, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          child: child,
        );
      },
      pageBuilder: (ctx, _, __) => _ShareBox(
        chats: chatState.chats,
        folders: chatState.folders,
        hasSenders: true,
        hasCaptions: msgIds.length > 0,
        onSend: (opts) async {
          Navigator.of(ctx).pop();
          for (final toChatId in opts.chatIds) {
            await chatState.forwardMessages(msgIds, toChatId,
              dropAuthor: opts.dropAuthor,
              dropCaptions: opts.dropCaptions,
              silent: opts.silent,
              scheduleDate: opts.scheduleDate,
            );
          }
          setState(() {
            _forwardingMsgIds = [];
            _forwardHideSender = false;
          });
        },
      ),
    );
  }

  void _cancelForward() {
    setState(() {
      _forwardingMsgIds = [];
      _forwardHideSender = false;
    });
  }

  void _onLinksChanged(List<String> links, ChatState chatState) {
    _previewDebounce?.cancel();
    if (links.isEmpty || _editingMsgId != null) {
      if (_webPreview != null) {
        setState(() {
          _webPreview = null;
          _lastPreviewUrl = '';
        });
      }
      return;
    }
    final url = links.first;
    if (url == _lastPreviewUrl) return;
    if (_webPreviewCancelled && url == _lastPreviewUrl) return;
    _webPreviewCancelled = false;
    _previewDebounce = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      final accountId = chatState.activeChat?.accountId ?? '';
      if (accountId.isEmpty) return;
      final engine = context.read<EngineService>();
      engine.getWebPagePreview(accountId, url).then((preview) {
        if (!mounted) return;
        if (preview != null) {
          setState(() {
            _webPreview = preview;
            _lastPreviewUrl = url;
          });
        } else {
          setState(() {
            _webPreview = null;
            _lastPreviewUrl = url;
          });
        }
      });
    });
  }

  void _cancelWebPreview() {
    setState(() {
      _webPreview = null;
      _webPreviewCancelled = true;
    });
  }

  void _onAutocompleteQuery(AutocompleteQuery? query) {
    if (query == null) {
      if (_acQuery != null) setState(() { _acQuery = null; _acFilteredEmojis = []; _acStickerSuggestions = []; _acFilteredCommands = []; });
      return;
    }
    final chatState = context.read<ChatState>();
    final chat = chatState.activeChat;
    if (chat == null) return;

    if (query.type == AutocompleteType.mention) {
      _ensureMembersLoaded(chat.accountId, chat.chatId);
      final q = query.query.toLowerCase();
      final filtered = _acMembers.where((m) {
        if (q.isEmpty) return true;
        return m.displayName.toLowerCase().contains(q) ||
            m.username.toLowerCase().contains(q);
      }).toList();
      setState(() {
        _acQuery = query;
        _acFilteredMembers = filtered;
        _acFilteredEmojis = [];
        _acStickerSuggestions = [];
        _acFilteredCommands = [];
        _acSelectedIndex = 0;
      });
    } else if (query.type == AutocompleteType.command) {
      _ensureCommandsLoaded(chat.accountId, chat.chatId);
      final q = query.query.toLowerCase();
      final filtered = _acBotCommands.where((c) {
        if (q.isEmpty) return true;
        return c.command.toLowerCase().contains(q) ||
            c.description.toLowerCase().contains(q);
      }).toList();
      setState(() {
        _acQuery = query;
        _acFilteredCommands = filtered;
        _acFilteredMembers = [];
        _acFilteredEmojis = [];
        _acStickerSuggestions = [];
        _acSelectedIndex = 0;
      });
    } else if (query.type == AutocompleteType.emoji) {
      final results = searchEmoji(query.query, limit: 30);
      setState(() {
        _acQuery = query;
        _acFilteredMembers = [];
        _acFilteredEmojis = results;
        _acStickerSuggestions = [];
        _acFilteredCommands = [];
        _acSelectedIndex = 0;
      });
    } else if (query.type == AutocompleteType.stickerSuggestion) {
      setState(() {
        _acQuery = query;
        _acFilteredMembers = [];
        _acFilteredEmojis = [];
        _acFilteredCommands = [];
        _acSelectedIndex = 0;
      });
      _loadStickerSuggestions(chat.accountId, query.query);
    } else {
      setState(() {
        _acQuery = query;
        _acFilteredMembers = [];
        _acFilteredEmojis = [];
        _acStickerSuggestions = [];
        _acFilteredCommands = [];
        _acSelectedIndex = 0;
      });
    }
  }

  void _loadSendAs(ChatState chatState) {
    final chat = chatState.activeChat;
    if (chat == null) return;
    if (chat.chatId == _sendAsChatId) return;
    _sendAsChatId = chat.chatId;
    if (chat.type != ChatType.channel && chat.type != ChatType.group) {
      if (_sendAsPeers.isNotEmpty) {
        setState(() {
          _sendAsPeers = [];
          _selectedSendAsPeerId = null;
        });
      }
      return;
    }
    final engine = context.read<EngineService>();
    engine.getSendAs(chat.accountId, chat.chatId).then((peers) {
      if (mounted && _sendAsChatId == chat.chatId) {
        setState(() {
          _sendAsPeers = peers;
          _selectedSendAsPeerId = peers.isNotEmpty ? peers.first.peerId : null;
        });
      }
    }).catchError((_) {});
  }

  void _ensureMembersLoaded(String accountId, String chatId) {
    if (_acMembersLoaded && _acMembersChatId == chatId) return;
    _acMembersChatId = chatId;
    _acMembersLoaded = true;
    final engine = context.read<EngineService>();
    engine.getChatMembers(accountId, chatId, limit: 200).then((members) {
      if (mounted && _acMembersChatId == chatId) {
        _acMembers = members;
        if (_acQuery?.type == AutocompleteType.mention) {
          _onAutocompleteQuery(_acQuery);
        }
      }
    }).catchError((_) {});
  }

  void _ensureCommandsLoaded(String accountId, String chatId) {
    if (_acCommandsLoaded && _acCommandsChatId == chatId) return;
    _acCommandsChatId = chatId;
    _acCommandsLoaded = true;
    final engine = context.read<EngineService>();
    engine.getChatBotCommands(accountId, chatId).then((commands) {
      if (mounted && _acCommandsChatId == chatId) {
        _acBotCommands = commands;
        if (_acQuery?.type == AutocompleteType.command) {
          _onAutocompleteQuery(_acQuery);
        }
      }
    }).catchError((_) {});
  }

  String? _stickerSuggestEmoji;

  void _loadStickerSuggestions(String accountId, String emoji) {
    _stickerSuggestEmoji = emoji;
    final engine = context.read<EngineService>();
    engine.getStickerSuggestions(accountId, emoji).then((stickers) {
      if (mounted && _stickerSuggestEmoji == emoji && _acQuery?.type == AutocompleteType.stickerSuggestion) {
        setState(() {
          _acStickerSuggestions = stickers;
          _acSelectedIndex = 0;
        });
      }
    }).catchError((_) {});
  }

  int get _acItemCount {
    if (_acQuery?.type == AutocompleteType.emoji) return _acFilteredEmojis.length;
    if (_acQuery?.type == AutocompleteType.stickerSuggestion) return _acStickerSuggestions.length;
    if (_acQuery?.type == AutocompleteType.command) return _acFilteredCommands.length;
    return _acFilteredMembers.length;
  }

  void _acMoveUp() {
    if (_acItemCount == 0) return;
    setState(() {
      _acSelectedIndex = (_acSelectedIndex - 1).clamp(0, _acItemCount - 1);
    });
  }

  void _acMoveDown() {
    if (_acItemCount == 0) return;
    setState(() {
      _acSelectedIndex = (_acSelectedIndex + 1).clamp(0, _acItemCount - 1);
    });
  }

  void _acPick() {
    if (_acQuery == null) return;
    if (_acQuery!.type == AutocompleteType.emoji && _acSelectedIndex < _acFilteredEmojis.length) {
      _insertAutocomplete(_acFilteredEmojis[_acSelectedIndex].emoji);
      return;
    }
    if (_acQuery!.type == AutocompleteType.mention && _acSelectedIndex < _acFilteredMembers.length) {
      final member = _acFilteredMembers[_acSelectedIndex];
      _insertAutocomplete(member.username.isNotEmpty ? '@${member.username} ' : '@${member.displayName} ');
      return;
    }
    if (_acQuery!.type == AutocompleteType.command && _acSelectedIndex < _acFilteredCommands.length) {
      _insertAutocomplete('/${_acFilteredCommands[_acSelectedIndex].command} ');
      return;
    }
    if (_acQuery!.type == AutocompleteType.stickerSuggestion && _acSelectedIndex < _acStickerSuggestions.length) {
      _sendStickerSuggestion(_acStickerSuggestions[_acSelectedIndex]);
    }
  }

  void _acPickIndex(int index) {
    if (_acQuery?.type == AutocompleteType.emoji && index < _acFilteredEmojis.length) {
      _insertAutocomplete(_acFilteredEmojis[index].emoji);
      return;
    }
    if (_acQuery?.type == AutocompleteType.mention && index < _acFilteredMembers.length) {
      final member = _acFilteredMembers[index];
      _insertAutocomplete(member.username.isNotEmpty ? '@${member.username} ' : '@${member.displayName} ');
      return;
    }
    if (_acQuery?.type == AutocompleteType.command && index < _acFilteredCommands.length) {
      _insertAutocomplete('/${_acFilteredCommands[index].command} ');
      return;
    }
    if (_acQuery?.type == AutocompleteType.stickerSuggestion && index < _acStickerSuggestions.length) {
      _sendStickerSuggestion(_acStickerSuggestions[index]);
    }
  }

  void _sendStickerSuggestion(StickerInfoItem sticker) {
    final chatState = context.read<ChatState>();
    final chat = chatState.activeChat;
    if (chat == null) return;
    final engine = context.read<EngineService>();
    engine.sendSticker(chat.accountId, chat.chatId, sticker.fileId);
    _composeController.clear();
    setState(() {
      _acQuery = null;
      _acStickerSuggestions = [];
    });
  }

  void _insertAutocomplete(String replacement) {
    final q = _acQuery;
    if (q == null) return;
    final text = _composeController.text;
    final sel = _composeController.selection;
    if (!sel.isValid || !sel.isCollapsed) return;
    final cursor = sel.baseOffset;
    final before = text.substring(0, cursor);
    final RegExpMatch? match;
    if (q.type == AutocompleteType.emoji) {
      match = RegExp(r'(?:^|(?<=\s)):(\w+)$').firstMatch(before);
    } else {
      match = RegExp(r'(?:^|(?<=\s))([@#/])(\S*)$').firstMatch(before);
    }
    if (match == null) return;
    final triggerStart = q.type == AutocompleteType.emoji
        ? match.start + match.group(0)!.indexOf(':')
        : match.start + match.group(0)!.indexOf(match.group(1)!);
    final newText = text.substring(0, triggerStart) + replacement + text.substring(cursor);
    _composeController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: triggerStart + replacement.length),
    );
    setState(() { _acQuery = null; _acFilteredEmojis = []; });
  }

  static final _inlineBotRegex = RegExp(r'^@([a-zA-Z][a-zA-Z0-9_]{2,}[bB]ot)\s(.*)$', dotAll: true);
  static final _inlineBotAnyRegex = RegExp(r'^@([a-zA-Z][a-zA-Z0-9_]{2,})\s(.*)$', dotAll: true);

  void _checkInlineBot(String text) {
    final match = _inlineBotRegex.firstMatch(text) ?? _inlineBotAnyRegex.firstMatch(text);
    if (match == null) {
      if (_inlineBotUsername != null) {
        _inlineBotDebounce?.cancel();
        setState(() {
          _inlineBotResults = null;
          _inlineBotUsername = null;
          _inlineBotUserId = null;
          _inlineBotQuery = '';
          _inlineBotLoading = false;
        });
      }
      return;
    }
    final botUsername = match.group(1)!;
    final query = match.group(2) ?? '';
    if (botUsername == _inlineBotUsername && query == _inlineBotQuery) return;
    _inlineBotQuery = query;
    if (botUsername != _inlineBotUsername) {
      _inlineBotUsername = botUsername;
      _inlineBotUserId = null;
      _resolveInlineBot(botUsername);
    } else if (_inlineBotUserId != null) {
      _debounceInlineQuery();
    }
  }

  void _resolveInlineBot(String username) {
    final chatState = context.read<ChatState>();
    final chat = chatState.activeChat;
    if (chat == null) return;
    final engine = context.read<EngineService>();
    engine.resolveUsername(chat.accountId, username).then((userId) {
      if (!mounted || _inlineBotUsername != username) return;
      if (userId == null) {
        setState(() { _inlineBotUsername = null; _inlineBotResults = null; });
        return;
      }
      _inlineBotUserId = userId;
      _debounceInlineQuery();
    });
  }

  void _debounceInlineQuery() {
    _inlineBotDebounce?.cancel();
    setState(() => _inlineBotLoading = true);
    _inlineBotDebounce = Timer(const Duration(milliseconds: 400), _fetchInlineResults);
  }

  void _fetchInlineResults() {
    final chatState = context.read<ChatState>();
    final chat = chatState.activeChat;
    if (chat == null || _inlineBotUserId == null) return;
    final engine = context.read<EngineService>();
    final botId = _inlineBotUserId!;
    final query = _inlineBotQuery;
    engine.getInlineBotResults(chat.accountId, botId, query, chatId: chat.chatId).then((results) {
      if (!mounted || _inlineBotUserId != botId) return;
      setState(() {
        _inlineBotResults = results;
        _inlineBotLoading = false;
      });
    });
  }

  void _pickInlineResult(InlineBotResult result) {
    if (_inlineBotResults == null) return;
    final chatState = context.read<ChatState>();
    final chat = chatState.activeChat;
    if (chat == null) return;
    final engine = context.read<EngineService>();
    engine.sendInlineBotResult(
      chat.accountId, chat.chatId, _inlineBotResults!.queryId, result.id,
    ).then((_) {
      if (!mounted) return;
      _composeController.clear();
      setState(() {
        _inlineBotResults = null;
        _inlineBotUsername = null;
        _inlineBotUserId = null;
        _inlineBotQuery = '';
      });
      _scrollToBottom();
    });
  }

  void _copySelected(ChatState chatState) {
    final msgs = chatState.messages
        .where((m) => _selectedMsgIds.contains(m.msgId))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final text = msgs.map((m) => m.contentText).join('\n');
    Clipboard.setData(ClipboardData(text: text));
    _modifySelection(() => _selectedMsgIds.clear());
  }

  void _downloadSelectedFiles(ChatState chatState) async {
    final msgs = chatState.messages
        .where((m) => _selectedMsgIds.contains(m.msgId) && m.hasMedia && m.mediaLocalPath.isNotEmpty)
        .toList();
    if (msgs.isEmpty) return;
    final downloadsDir = Directory('${Platform.environment['HOME'] ?? '/tmp'}/Downloads');
    if (!await downloadsDir.exists()) {
      await downloadsDir.create(recursive: true);
    }
    int saved = 0;
    for (final msg in msgs) {
      final sourceFile = File(msg.mediaLocalPath);
      if (!await sourceFile.exists()) continue;
      final fileName = msg.mediaFileName.isNotEmpty
          ? msg.mediaFileName
          : sourceFile.uri.pathSegments.last;
      var destPath = '${downloadsDir.path}/$fileName';
      var counter = 1;
      while (await File(destPath).exists()) {
        final ext = fileName.contains('.') ? '.${fileName.split('.').last}' : '';
        final base = fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName;
        destPath = '${downloadsDir.path}/${base}_($counter)$ext';
        counter++;
      }
      await sourceFile.copy(destPath);
      final stat = await File(destPath).stat();
      if (mounted) {
        context.read<AppState>().addRecentDownload(
          fileName, destPath, stat.size,
        );
      }
      saved++;
    }
    _modifySelection(() => _selectedMsgIds.clear());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved $saved file${saved != 1 ? 's' : ''} to Downloads'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Harness entry point for spec §24.4 line 2978 "Ctrl+Shift+Enter always
  /// sends". Gates on the same preconditions as the FocusNode-level Enter
  /// handler: compose text must be non-empty and a chat must be active.
  /// Returns true iff the send (or edit) fired.
  bool _requestSendCompose() {
    if (!mounted) return false;
    if (context.read<ChatState>().activeChat == null) return false;
    if (_isForwarding) {
      _sendMessage();
      return true;
    }
    if (_composeController.text.trim().isEmpty) return false;
    _sendMessage();
    return true;
  }

  void _setComposeText(String text, {int? selStart, int? selEnd}) {
    if (text != _composeController.text) {
      _composeController.entities.clear();
    }
    _composeController.value = TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: selStart ?? text.length,
        extentOffset: selEnd ?? text.length,
      ),
    );
    final urlRegex = RegExp(r'https?://[^\s<]+', caseSensitive: false);
    final urls = urlRegex.allMatches(text).map((m) => m.group(0)!).toList();
    if (urls.toString() != _detectedLinks.toString()) {
      setState(() => _detectedLinks = urls);
      final chatState = context.read<ChatState>();
      _onLinksChanged(urls, chatState);
    }
    _checkInlineBot(text);
  }

  void _toggleComposeFormat(FormatType type) {
    _composeController.toggleFormat(type);
  }

  String _getComposeEntities() {
    return _composeController.entitiesJson;
  }

  void _sendMessage({bool silent = false, int scheduleDate = 0}) {
    if (_isForwarding) {
      _executeForward(context, context.read<ChatState>());
      return;
    }
    final text = _composeController.text.trim();
    if (text.isEmpty) return;
    final entities = _composeController.entitiesJson;
    final chatState = context.read<ChatState>();
    if (_editingMsgId != null) {
      chatState.editMessage(_editingMsgId!, text, entities: entities);
      _composeController.clear();
      setState(() { _editingMsgId = null; _editOriginalText = ''; });
      return;
    }
    chatState.sendMessage(text, replyToId: _replyToId ?? '', entities: entities,
        silent: silent, scheduleDate: scheduleDate);
    _composeController.clear();
    setState(() {
      _replyToId = null;
      _webPreview = null;
      _webPreviewCancelled = false;
      _lastPreviewUrl = '';
    });
    if (scheduleDate > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message scheduled'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      _scrollToBottom();
    }
  }

  bool _isBotStartVisible(ChatInfo chat) {
    return !chat.isBlocked &&
        chat.isBot &&
        chat.type == ChatType.dm &&
        chat.lastMsgId.isEmpty;
  }

  void _sendStartBot(ChatState chatState) {
    chatState.sendMessage('/start');
  }

  Future<void> _uploadFiles(ChatState chatState, List<String> paths) async {
    final chat = chatState.activeChat;
    final result = await showSendFilesBox(
      context,
      filePaths: paths,
      chatType: chat?.type ?? ChatType.dm,
      isSelfChat: chat != null && chat.title == 'Saved Messages' && chat.type == ChatType.dm,
      starsPerMessage: chat?.starsToSend ?? 0,
    );
    if (result == null || result.paths.isEmpty) return;
    for (final path in result.paths) {
      chatState.uploadFile(path, caption: result.caption);
    }
  }

  /// Up-arrow-to-edit-last-message — Telegram Desktop spec §24.7: when the
  /// compose field is empty and no edit/reply is active, pressing Up enters
  /// edit mode on the newest outgoing message. `_messages` is newest-first
  /// (see ChatState._onNewMessage which inserts at index 0), so we scan from
  /// the front and pick the first `isOutgoing` message. Returns true if edit
  /// mode was entered, so the key event can be consumed.
  bool _editLastOutgoing() {
    if (_composeController.text.isNotEmpty) return false;
    if (_editingMsgId != null || _replyToId != null) return false;
    final chatState = context.read<ChatState>();
    final target = chatState.messages
        .where((m) => m.isOutgoing && m.contentText.isNotEmpty)
        .firstOrNull;
    if (target == null) return false;
    setState(() {
      _editingMsgId = target.msgId;
      _editOriginalText = target.contentText;
      _composeController.text = target.contentText;
      _composeController.selection = TextSelection.fromPosition(
        TextPosition(offset: _composeController.text.length),
      );
    });
    return true;
  }

  /// Ctrl+R handler — Telegram Desktop spec §24.4 `read_chat`: marks the
  /// currently active chat as read. Uses [ChatState.markChatRead] (not the
  /// active-only [ChatState.markRead]) so that chats with no messages
  /// currently loaded still get their unread count cleared, and so the
  /// sidebar unread badges refresh via the follow-up `loadChats()`.
  /// Returns true if a chat was active and the mark-read call was issued.
  bool _markActiveChatRead() {
    final chatState = context.read<ChatState>();
    final chat = chatState.activeChat;
    if (chat == null) return false;
    chatState.markChatRead(chat.accountId, chat.chatId);
    return true;
  }

  bool _showChatPreview() {
    if (!mounted) return false;
    final chatState = context.read<ChatState>();
    final chat = chatState.activeChat;
    if (chat == null) return false;
    _showChatPreviewPopup(context, chat, chatState);
    return true;
  }

  bool _archiveActiveChat() {
    if (!mounted) return false;
    final chatState = context.read<ChatState>();
    final chat = chatState.activeChat;
    if (chat == null) return false;
    chatState.archiveChat(chat.accountId, chat.chatId, !chat.isArchived);
    return true;
  }

  bool _showScheduled() {
    if (!mounted) return false;
    final chatState = context.read<ChatState>();
    final chat = chatState.activeChat;
    if (chat == null) return false;
    chatState.toggleScheduledView();
    return true;
  }

  /// Ctrl+Up / Ctrl+Down reply-navigation handler — Telegram Desktop spec
  /// §24.6 lines 2982-2983. `direction` is +1 for Ctrl+Up (older message)
  /// and -1 for Ctrl+Down (newer message). `chatState.messages` is newest-
  /// first (ChatState._onNewMessage inserts at index 0), so "older" is
  /// `idx + 1` and "newer" is `idx - 1`.
  ///
  /// Behavior:
  /// * If editing, no-op (edit mode takes precedence; cursor movement stays
  ///   default).
  /// * If no chat loaded / no messages, no-op.
  /// * If no reply is set and direction is +1 (Ctrl+Up): set reply to the
  ///   newest message (index 0).
  /// * If no reply is set and direction is -1 (Ctrl+Down): no-op (nothing to
  ///   cancel, nothing newer than "no reply").
  /// * If a reply is set, move the target by `direction`. Moving past the
  ///   oldest message clamps (no-op). Moving past the newest message (i.e.
  ///   Ctrl+Down on index 0) cancels the reply.
  /// * If the current reply id has scrolled out of the loaded window, restart
  ///   from the appropriate end.
  ///
  /// Returns true iff the event should be consumed.
  bool _cycleReply(int direction) {
    if (_editingMsgId != null) return false;
    final chatState = context.read<ChatState>();
    final messages = chatState.messages;
    if (messages.isEmpty) return false;
    int currentIdx;
    if (_replyToId == null) {
      if (direction < 0) return false;
      currentIdx = -1;
    } else {
      currentIdx = messages.indexWhere((m) => m.msgId == _replyToId);
      if (currentIdx < 0) currentIdx = direction > 0 ? -1 : 0;
    }
    final newIdx = currentIdx + direction;
    if (newIdx >= messages.length) {
      return true;
    }
    if (newIdx < 0) {
      setState(() => _replyToId = null);
      return true;
    }
    setState(() => _replyToId = messages[newIdx].msgId);
    return true;
  }

  /// Spec §4.3: execute in-chat search — filter current chat messages matching
  /// the query text. Results are ordered newest-first (matching the reversed
  /// ListView). Navigating results jumps the message list to each match.
  void _onSearchQueryChanged() {
    if (!mounted) return;
    final query = _searchController.text.trim().toLowerCase();
    // Avoid redundant updates if query hasn't actually changed.
    if (query == _activeSearchQuery) return;
    if (query.isEmpty) {
      setState(() {
        _searchResultIds = [];
        _searchResultIndex = -1;
        _activeSearchQuery = '';
      });
      return;
    }
    final chatState = context.read<ChatState>();
    final matches = <String>[];
    for (final msg in chatState.messages) {
      if (msg.contentText.toLowerCase().contains(query)) {
        matches.add(msg.msgId);
      }
    }
    setState(() {
      _activeSearchQuery = query;
      _searchResultIds = matches;
      _searchResultIndex = matches.isNotEmpty ? 0 : -1;
    });
    if (matches.isNotEmpty) {
      _jumpToSearchResult(chatState, 0);
    }
  }

  /// Navigate to the next search result (down = older messages).
  void _searchNext() {
    if (_searchResultIds.isEmpty) return;
    final next = (_searchResultIndex + 1) % _searchResultIds.length;
    setState(() => _searchResultIndex = next);
    _jumpToSearchResult(context.read<ChatState>(), next);
  }

  /// Navigate to the previous search result (up = newer messages).
  void _searchPrev() {
    if (_searchResultIds.isEmpty) return;
    final prev = (_searchResultIndex - 1 + _searchResultIds.length) %
        _searchResultIds.length;
    setState(() => _searchResultIndex = prev);
    _jumpToSearchResult(context.read<ChatState>(), prev);
  }

  /// Scroll the message list so the search result at [index] is visible.
  void _jumpToSearchResult(ChatState chatState, int index) {
    if (index < 0 || index >= _searchResultIds.length) return;
    final targetId = _searchResultIds[index];
    // Find the message in the currently loaded list.
    final msgIndex = chatState.messages.indexWhere((m) => m.msgId == targetId);
    if (msgIndex < 0) return;
    // The ListView is reversed (index 0 = newest = bottom). Estimate
    // pixel position: each message row ~72px average. Jump to approximate
    // position so the target is visible.
    final target = chatState.messages[msgIndex];
    chatState.jumpToMessage(target.timestamp);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  Future<void> _cancelEditing() async {
    if (_composeController.text != _editOriginalText) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Discard changes?'),
          content: const Text('You have unsaved changes to this message.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep Editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    setState(() {
      _editingMsgId = null;
      _editOriginalText = '';
      _composeController.clear();
    });
  }

  /// Escape key handler — Telegram Desktop spec §8: cancels reply, edit,
  /// or selection in priority order (selection > edit > reply). Returns
  /// `handled` if anything was cancelled so the event doesn't bubble further.
  KeyEventResult _handleEscape() {
    if (_isSearching) {
      setState(() {
        _isSearching = false;
        _searchController.clear();
        _searchResultIds = [];
        _searchResultIndex = -1;
        _activeSearchQuery = '';
      });
      return KeyEventResult.handled;
    }
    if (_selectionMode) {
      _modifySelection(() => _selectedMsgIds.clear());
      return KeyEventResult.handled;
    }
    if (_editingMsgId != null) {
      _cancelEditing();
      return KeyEventResult.handled;
    }
    if (_isForwarding) {
      _cancelForward();
      return KeyEventResult.handled;
    }
    if (_replyToId != null) {
      setState(() => _replyToId = null);
      return KeyEventResult.handled;
    }
    final chatState = context.read<ChatState>();
    if (chatState.isScheduledView) {
      chatState.toggleScheduledView();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _wrapDropTarget(Widget child) {
    if (kIsWeb) {
      return buildWebDropZone(
        child: child,
        onDrop: (names) async {
          if (names.isEmpty) return;
          final result = await FilePicker.platform.pickFiles(allowMultiple: true);
          if (result == null || result.files.isEmpty) return;
          final paths = result.files.where((f) => f.path != null).map((f) => f.path!).toList();
          if (paths.isNotEmpty) {
            _uploadFiles(context.read<ChatState>(), paths);
          }
        },
      );
    }
    return DropTarget(
      onDragEntered: (_) {
        setState(() => _isDragOver = true);
        _dragOverlayAnimCtrl.forward();
      },
      onDragExited: (_) {
        setState(() {
          _isDragOver = false;
          _dragHoveredCard = 0;
        });
        _dragOverlayAnimCtrl.reverse();
      },
      onDragUpdated: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final localY = details.localPosition.dy;
        final h = box.size.height;
        final newCard = localY < h / 2 ? 1 : 2;
        if (newCard != _dragHoveredCard) {
          setState(() => _dragHoveredCard = newCard);
        }
      },
      onDragDone: (details) {
        setState(() {
          _isDragOver = false;
          _dragHoveredCard = 0;
        });
        _dragOverlayAnimCtrl.reverse();
        final paths = details.files.map((f) => f.path).toList();
        if (paths.isNotEmpty) {
          _uploadFiles(context.read<ChatState>(), paths);
        }
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatState = context.watch<ChatState>();
    final chat = chatState.activeChat;

    if (chat == null) {
      return const SizedBox.shrink();
    }

    // §23.8: detect transition into scheduled view and trigger video tip toast.
    // §23.10: track slide direction for section enter/exit animation.
    final isScheduled = widget.isScheduledView || chatState.isScheduledView;
    if (isScheduled && !_wasScheduledView) {
      _scheduledSlideForward = true;
      _scheduledSlideCtrl.forward(from: 0);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _checkScheduledVideoTip(chatState);
      });
    } else if (!isScheduled && _wasScheduledView) {
      _scheduledSlideForward = false;
      _scheduledSlideCtrl.forward(from: 0);
      _videoTipTimer?.cancel();
      _videoTooltipTimer?.cancel();
      _showVideoTipToast = false;
      _showVideoTooltip = false;
    }
    _wasScheduledView = isScheduled;

    // Spec §5 / §49.17: drive corner button visibility from chat data.
    final wantMentions = chat.unreadMentionCount > 0;
    if (wantMentions != _showMentionsBtn) {
      _showMentionsBtn = wantMentions;
      if (wantMentions) _mentionsAnimCtrl.forward(); else _mentionsAnimCtrl.reverse();
    }
    final wantReactions = chat.unreadReactionCount > 0;
    if (wantReactions != _showReactionsBtn) {
      _showReactionsBtn = wantReactions;
      if (wantReactions) _reactionsAnimCtrl.forward(); else _reactionsAnimCtrl.reverse();
    }
    // PollVotes: no data field yet — always hidden.
    if (_showPollVotesBtn) {
      _showPollVotesBtn = false;
      _pollVotesAnimCtrl.reverse();
    }

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          return _handleEscape();
        }
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) {
          if (_isBotStartVisible(chat)) {
            _sendStartBot(context.read<ChatState>());
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: _wrapDropTarget(Stack(
      children: [
      Container(
      color: theme.scaffoldBackgroundColor,
      child: Column(
        children: [
          // Spec §4.7: selection bar slides in from below (200ms easeOutCirc)
          // while the top bar title/subtitle translates up by topBarHeight.
          SizedBox(
            height: 54, // topBarHeight
            child: ClipRect(
              child: AnimatedBuilder(
                animation: _selectionCurvedAnim,
                builder: (context, _) {
                  final v = _selectionCurvedAnim.value;
                  return Stack(
                    children: [
                      // Top bar translates up as selection bar appears
                      Transform.translate(
                        offset: Offset(0, -54 * v),
                        child: _ChatTopBar(
                          chat: chat,
                          typingUser: chatState.typingUserFor(chat.chatId),
                          isOnline: chatState.isChatOnline(chat),
                          lastSeen: chatState.chatLastSeen(chat),
                          showBackButton: widget.showBackButton,
                          onBack: widget.onBack,
                          onToggleInfo: widget.onToggleInfo,
                          isInfoOpen: widget.isInfoOpen,
                          moreVertKey: _moreVertKey,
                          hideDivider: widget.hideTopBarDivider,
                          groupOnlineCount: chatState.groupOnlineCount,
                          isSearching: _isSearching,
                          searchController: _searchController,
                          searchFocusNode: _searchFocusNode,
                          searchResultCount: _searchResultIds.length,
                          searchResultIndex: _searchResultIndex,
                          hasSearchQuery: _activeSearchQuery.isNotEmpty,
                          onToggleSearch: () {
                            setState(() {
                              _isSearching = !_isSearching;
                              if (_isSearching) {
                                _searchFocusNode.requestFocus();
                              } else {
                                _searchController.clear();
                                _searchResultIds = [];
                                _searchResultIndex = -1;
                                _activeSearchQuery = '';
                              }
                            });
                          },
                          onSearchPrev: _searchPrev,
                          onSearchNext: _searchNext,
                          onSearchChanged: (_) => _onSearchQueryChanged(),
                          activeTopic: chat.type == ChatType.topic
                              ? chatState.forumTopics
                                  .cast<ForumTopic?>()
                                  .firstWhere((t) => t!.id == chat.chatId, orElse: () => null)
                              : null,
                          parentChat: chat.type == ChatType.topic
                              ? chatState.forumParentChat
                              : null,
                          isScheduledView: widget.isScheduledView || chatState.isScheduledView,
                          onExitScheduled: () => chatState.toggleScheduledView(),
                        ),
                      ),
                      // Selection bar slides in from below
                      if (v > 0)
                        Transform.translate(
                          offset: Offset(0, 54 * (1 - v)),
                          child: _SelectionBar(
                            count: _selectionMode ? _selectedMsgIds.length : _lastSelectionCount,
                            onCancel: () => _modifySelection(() => _selectedMsgIds.clear()),
                            onDelete: () => _deleteSelected(chatState),
                            onCopy: () => _copySelected(chatState),
                            onForward: () => _forwardSelected(context, chatState),
                            onDownloadFiles: () => _downloadSelectedFiles(chatState),
                            isScheduledView: widget.isScheduledView || chatState.isScheduledView,
                            onSendNow: (widget.isScheduledView || chatState.isScheduledView)
                                ? () => _sendNowSelected(chatState)
                                : null,
                            forwardDragData: ForwardDragData(
                              accountId: chat.accountId,
                              sourceChatId: chat.chatId,
                              messageIds: _selectedMsgIds.toList(),
                            ),
                            hideDivider: widget.hideTopBarDivider,
                            hasDownloadableMedia: chatState.messages
                                .where((m) => _selectedMsgIds.contains(m.msgId) && m.hasMedia && m.mediaLocalPath.isNotEmpty)
                                .isNotEmpty,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          // Group call bar (§4.6) — shown when there's an active group call.
          if (chatState.activeGroupCall != null)
            _GroupCallBar(
              groupCall: chatState.activeGroupCall!,
              onJoin: () => chatState.joinGroupCall(),
            ),
          // Pinned message bar (if any pinned messages).
          if (chatState.pinnedMessages.isNotEmpty && !_pinnedBarDismissed)
            _PinnedBar(
              pinned: chatState.pinnedMessages.first,
              pinnedCount: chatState.pinnedMessages.length,
              pinnedIndex: 0,
              onTap: () {
                final pinned = chatState.pinnedMessages.first;
                // Load messages with pinned message as the newest (index 0).
                chatState.jumpToMessage(pinned.timestamp);
                // Scroll to bottom (offset 0 in reversed list = newest = pinned message).
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(0);
                  }
                });
              },
              onClose: () {
                setState(() => _pinnedBarDismissed = true);
              },
              onShowAll: chatState.pinnedMessages.length > 1
                  ? () => _showAllPinnedMessages(context, chatState)
                  : null,
            ),
          // Contact status / action bar (§4.5) — shown for non-contact DMs, blocked users, or bots.
          if (_shouldShowContactStatusBar(chat))
            _ContactStatusBar(
              chat: chat,
              chatState: chatState,
            ),
          // Message list with scroll-to-bottom FAB.
          Expanded(
            child: Stack(
              children: [
                // §23.10: 200ms slide+fade when entering/exiting scheduled section.
                AnimatedBuilder(
                  animation: _scheduledSlideCtrl,
                  builder: (context, child) {
                    if (_scheduledSlideCtrl.isCompleted) return child!;
                    final t = Curves.easeOutCubic.transform(_scheduledSlideCtrl.value);
                    final dx = _scheduledSlideForward ? (1.0 - t) : -(1.0 - t);
                    return Opacity(
                      opacity: t.clamp(0.0, 1.0),
                      child: FractionalTranslation(
                        translation: Offset(dx * 0.3, 0),
                        child: child,
                      ),
                    );
                  },
                  child: _MessageList(
                    messages: _hiddenMsgIds.isEmpty
                        ? chatState.messages
                        : chatState.messages.where((m) => !_hiddenMsgIds.contains(m.msgId)).toList(),
                    loading: chatState.loadingMessages,
                    isGroupChat: chat.type == ChatType.group || chat.type == ChatType.channel || chat.type == ChatType.topic,
                    senderAvatars: chatState,
                    scrollController: _scrollController,
                    onReply: (msgId) => setState(() => _replyToId = msgId),
                    selectedIds: _selectedMsgIds,
                    onToggleSelect: (msgId) => _modifySelection(() {
                      if (_selectedMsgIds.contains(msgId)) {
                        _selectedMsgIds.remove(msgId);
                      } else {
                        final inScheduled = widget.isScheduledView || chatState.isScheduledView;
                        if (inScheduled) {
                          final msg = chatState.messages.where((m) => m.msgId == msgId).firstOrNull;
                          if (msg != null && (msg.isSending || msg.isFailed)) return;
                        }
                        _selectedMsgIds.add(msgId);
                      }
                    }),
                    onLongPress: (msgId) => _modifySelection(() {
                      final inScheduled = widget.isScheduledView || chatState.isScheduledView;
                      if (inScheduled) {
                        final msg = chatState.messages.where((m) => m.msgId == msgId).firstOrNull;
                        if (msg != null && (msg.isSending || msg.isFailed)) return;
                      }
                      _selectedMsgIds.add(msgId);
                    }),
                    onContextMenu: (msgId, pos, selectedText) => _showMessageContextMenu(msgId, pos, selectedText),
                    onSenderTap: (senderId) => _showSenderProfile(context, chatState, senderId),
                    onSenderContextMenu: (senderId, pos) => _showUserContextMenu(context, chatState, senderId, pos),
                    onReplyTap: (replyToId) => _jumpToReply(chatState, replyToId),
                    searchHighlightId: _searchResultIndex >= 0 && _searchResultIndex < _searchResultIds.length
                        ? _searchResultIds[_searchResultIndex]
                        : null,
                    searchQuery: _activeSearchQuery,
                    openedUnreadCount: chatState.openedUnreadCount,
                    isScheduledView: widget.isScheduledView || chatState.isScheduledView,
                  ),
                ),
                // Spec §5 / §49.17: Stacked corner buttons.
                // Order bottom→top: Jump-down → Mentions → Reactions → PollVotes.
                // 4px gap (historyUnreadThingsSkip) between buttons, 12px right, 10px bottom.
                // Jump-down slides up; others slide from right. 150ms linear.
                // Each button: 52×62px hit-area.
                // --- Jump-down button (bottommost) ---
                Positioned(
                  right: 12,
                  bottom: 10,
                  child: AnimatedBuilder(
                    animation: _fabAnimCtrl,
                    builder: (context, child) {
                      if (_fabAnimCtrl.isDismissed) return const SizedBox.shrink();
                      final dy = (1.0 - _fabAnimCtrl.value) * 82.0;
                      return Transform.translate(
                        offset: Offset(0, dy),
                        child: child,
                      );
                    },
                    child: _ScrollToBottomFab(
                      unreadCount: chatState.openedUnreadCount,
                      onTap: _scrollToBottom,
                    ),
                  ),
                ),
                // --- Mentions button ---
                Positioned(
                  right: 12,
                  bottom: 10,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_fabAnimCtrl, _mentionsAnimCtrl]),
                    builder: (context, child) {
                      if (_mentionsAnimCtrl.isDismissed) return const SizedBox.shrink();
                      // Y: stacks above jump-down (66 = 62 + 4px gap).
                      final dy = -(66.0 * _fabAnimCtrl.value);
                      // X: slides from off-screen right.
                      final dx = (1.0 - _mentionsAnimCtrl.value) * 64.0;
                      return Transform.translate(
                        offset: Offset(dx, dy),
                        child: child,
                      );
                    },
                    child: _CornerButton(
                      icon: Icons.alternate_email,
                      count: chat.unreadMentionCount,
                      onTap: _scrollToBottom,
                    ),
                  ),
                ),
                // --- Reactions button ---
                Positioned(
                  right: 12,
                  bottom: 10,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_fabAnimCtrl, _mentionsAnimCtrl, _reactionsAnimCtrl]),
                    builder: (context, child) {
                      if (_reactionsAnimCtrl.isDismissed) return const SizedBox.shrink();
                      final dy = -(66.0 * _fabAnimCtrl.value + 66.0 * _mentionsAnimCtrl.value);
                      final dx = (1.0 - _reactionsAnimCtrl.value) * 64.0;
                      return Transform.translate(
                        offset: Offset(dx, dy),
                        child: child,
                      );
                    },
                    child: _CornerButton(
                      icon: Icons.favorite_border,
                      count: chat.unreadReactionCount,
                      onTap: _scrollToBottom,
                    ),
                  ),
                ),
                // --- PollVotes button (no data yet — always hidden) ---
                Positioned(
                  right: 12,
                  bottom: 10,
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_fabAnimCtrl, _mentionsAnimCtrl, _reactionsAnimCtrl, _pollVotesAnimCtrl]),
                    builder: (context, child) {
                      if (_pollVotesAnimCtrl.isDismissed) return const SizedBox.shrink();
                      final dy = -(66.0 * _fabAnimCtrl.value + 66.0 * _mentionsAnimCtrl.value + 66.0 * _reactionsAnimCtrl.value);
                      final dx = (1.0 - _pollVotesAnimCtrl.value) * 64.0;
                      return Transform.translate(
                        offset: Offset(dx, dy),
                        child: child,
                      );
                    },
                    child: _CornerButton(
                      icon: Icons.poll,
                      count: 0,
                      onTap: _scrollToBottom,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Edit bar (takes precedence over reply/forward bar).
          if (_editingMsgId != null)
            _EditBar(
              editingId: _editingMsgId!,
              messages: chatState.messages,
              onCancel: _cancelEditing,
            )
          else if (_isForwarding)
            _ForwardBar(
              forwardingMsgIds: _forwardingMsgIds,
              messages: chatState.messages,
              hideSender: _forwardHideSender,
              onToggleHideSender: () => setState(() => _forwardHideSender = !_forwardHideSender),
              onSend: () => _executeForward(context, chatState),
              onCancel: _cancelForward,
            )
          else if (_replyToId != null)
            _ReplyBar(
              replyId: _replyToId!,
              messages: chatState.messages,
              onCancel: () => setState(() => _replyToId = null),
            )
          else if (_webPreview != null)
            _WebPreviewBar(
              preview: _webPreview!,
              onCancel: _cancelWebPreview,
            ),
          if (_acQuery != null && _acQuery!.type == AutocompleteType.mention && _acFilteredMembers.isNotEmpty)
            _AutocompletePanel(
              members: _acFilteredMembers,
              selectedIndex: _acSelectedIndex,
              onPick: _acPickIndex,
              onHover: (i) => setState(() => _acSelectedIndex = i),
            ),
          if (_acQuery != null && _acQuery!.type == AutocompleteType.command && _acFilteredCommands.isNotEmpty)
            _CommandAutocompletePanel(
              commands: _acFilteredCommands,
              selectedIndex: _acSelectedIndex,
              onPick: _acPickIndex,
              onHover: (i) => setState(() => _acSelectedIndex = i),
            ),
          if (_acQuery != null && _acQuery!.type == AutocompleteType.emoji && _acFilteredEmojis.isNotEmpty)
            _EmojiSuggestionPanel(
              emojis: _acFilteredEmojis,
              selectedIndex: _acSelectedIndex,
              onPick: _acPickIndex,
              onHover: (i) => setState(() => _acSelectedIndex = i),
            ),
          if (_acQuery != null && _acQuery!.type == AutocompleteType.stickerSuggestion && _acStickerSuggestions.isNotEmpty)
            _StickerSuggestionPanel(
              stickers: _acStickerSuggestions,
              selectedIndex: _acSelectedIndex,
              onPick: (i) => _acPickIndex(i),
              onHover: (i) => setState(() => _acSelectedIndex = i),
            ),
          if (_inlineBotResults != null && _inlineBotResults!.results.isNotEmpty)
            _InlineBotResultsPanel(
              results: _inlineBotResults!,
              gallery: _inlineBotResults!.gallery,
              onPick: _pickInlineResult,
              loading: _inlineBotLoading,
            ),
          // Compose area — or fallback buttons for blocked/bot/channel/spam.
          if (chat.isBlocked)
            _FallbackComposeButton(
              label: chat.isBot ? 'RESTART' : 'UNBLOCK',
              color: const Color(0xFFdf3f40),
              onTap: () => chatState.unblockUser(chat.accountId, chat.chatId),
            )
          else if (chat.isBot && chat.type == ChatType.dm && chat.lastMsgId.isEmpty)
            _FallbackComposeButton(
              label: 'START',
              color: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFF6ab3f3) : const Color(0xFF168acd),
              onTap: () => _sendStartBot(chatState),
            )
          else if ((chat.isScam || chat.isFake) && chat.type == ChatType.dm)
            _FallbackComposeButton(
              label: 'REPORT SPAM',
              color: const Color(0xFFdf3f40),
              onTap: () => chatState.reportSpam(chat.accountId, chat.chatId),
            )
          else if (chat.type == ChatType.channel)
            _ChannelComposeBar(
              chat: chat,
              chatState: chatState,
              linkedChatId: chatState.linkedChatId,
            )
          // §23.9: Topic-level write restriction — closed topics block compose.
          else if (chat.type == ChatType.topic && (() {
            final t = chatState.forumTopics.cast<ForumTopic?>().firstWhere(
                (t) => t!.id == chat.chatId, orElse: () => null);
            return t != null && t.isClosed;
          })())
            Container(
              height: 49,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.12))),
              ),
              child: Text('This topic is closed.',
                style: TextStyle(color: theme.hintColor, fontSize: 13)),
            )
          else
            _ComposeArea(
              controller: _composeController,
              onSend: _sendMessage,
              onSendSilent: () => _sendMessage(silent: true),
              onSendScheduled: (date) => _sendMessage(scheduleDate: date.millisecondsSinceEpoch ~/ 1000),
              onSendWhenOnline: () => _sendMessage(scheduleDate: 0x7FFFFFFE),
              onDraftChanged: (text) {
                chatState.saveDraft(text);
                _checkInlineBot(text);
              },
              isEditing: _editingMsgId != null,
              isForwarding: _isForwarding,
              chatType: chat.type,
              isSelfChat: chat.title == 'Saved Messages' && chat.type == ChatType.dm,
              voiceRestricted: chat.voiceRestricted,
              videoRestricted: chat.videoRestricted,
              slowmodeSeconds: chat.slowmodeSeconds,
              slowmodeNextSendDate: chat.slowmodeNextSendDate,
              starsToSend: chat.starsToSend,
              onEditLast: _editLastOutgoing,
              onCycleReply: _cycleReply,
              onLinksDetected: (links) {
                setState(() => _detectedLinks = links);
                _onLinksChanged(links, chatState);
              },
              onFilesSelected: (paths) => _uploadFiles(chatState, paths),
              onAutocompleteQuery: _onAutocompleteQuery,
              autocompleteActive: _acQuery != null && (_acFilteredMembers.isNotEmpty || _acFilteredEmojis.isNotEmpty || _acStickerSuggestions.isNotEmpty || _acFilteredCommands.isNotEmpty),
              onAutocompleteUp: _acMoveUp,
              onAutocompleteDown: _acMoveDown,
              onAutocompletePick: _acPick,
              sendAsPeers: _sendAsPeers,
              selectedSendAsPeerId: _selectedSendAsPeerId,
              onSendAsChanged: (peerId) {
                setState(() => _selectedSendAsPeerId = peerId);
                final engine = context.read<EngineService>();
                engine.saveDefaultSendAs(chat.accountId, chat.chatId, peerId);
              },
              scheduledCount: chatState.scheduledCount,
              onScheduledPressed: () => chatState.toggleScheduledView(),
              ttlPeriod: chat.ttlPeriod,
              onTtlChanged: (period) {
                chatState.setHistoryTTL(chat.accountId, chat.chatId, period);
              },
              isBot: chat.isBot,
              emojiPanelVisible: _emojiPanelVisible,
              onEmojiToggle: () => setState(() => _emojiPanelVisible = !_emojiPanelVisible),
              onEscape: () => _handleEscape(),
              onScrollPage: (isUp) => _scrollPage(isUp),
              sendBy: context.read<AppState>().sendBy,
            ),
          if (chatState.visibleReplyKeyboard != null)
            _BotReplyKeyboard(
              keyboard: chatState.visibleReplyKeyboard!,
              onButtonPressed: (text) {
                _composeController.text = text;
                _sendMessage();
                if (chatState.visibleReplyKeyboard?.singleUse == true) {
                  for (final m in chatState.messages.reversed) {
                    if (m.hasReplyKeyboard) {
                      chatState.hideReplyKeyboard(m.msgId);
                      break;
                    }
                  }
                }
              },
            ),
        ],
      ),
      ),
      Positioned(
        right: 0,
        bottom: 64,
        child: EmojiTabbedPanel(
          visible: _emojiPanelVisible,
          onHide: () => setState(() => _emojiPanelVisible = false),
          onEmojiSelected: (emoji) {
            final text = _composeController.text;
            final sel = _composeController.selection;
            final start = sel.isValid ? sel.start : text.length;
            final end = sel.isValid ? sel.end : text.length;
            final newText = text.replaceRange(start, end, emoji);
            _composeController.value = TextEditingValue(
              text: newText,
              selection: TextSelection.collapsed(offset: start + emoji.length),
            );
          },
        ),
      ),
      // §23.8: Video processing tip toast (top-attached, 4000ms).
      if (_showVideoTipToast)
        _VideoProcessingTipToast(
          onDismiss: () {
            _videoTipTimer?.cancel();
            setState(() {
              _showVideoTipToast = false;
              _showVideoTooltipForFirstVideo();
            });
          },
        ),
      // §23.8: Video processing tooltip (anchored to message, 4000ms after tip toast).
      if (_showVideoTooltip)
        _VideoProcessingTooltip(
          maxWidth: 364,
          onDismiss: () {
            _videoTooltipTimer?.cancel();
            setState(() => _showVideoTooltip = false);
          },
        ),
      // §23.8: Published video notification toast.
      if (_showVideoPublishedToast)
        _VideoPublishedToast(
          thumbnail: _publishedVideoThumb,
          onView: () {
            _dismissVideoPublishedToast();
            final chatState = context.read<ChatState>();
            if (chatState.isScheduledView) {
              chatState.toggleScheduledView();
            }
            if (_publishedVideoMsgId != null) {
              chatState.jumpToMessage(0);
            }
          },
          onDismiss: _dismissVideoPublishedToast,
        ),
      Positioned.fill(
        child: AnimatedBuilder(
          animation: _dragOverlayAnimCtrl,
          builder: (context, child) {
            if (_dragOverlayAnimCtrl.isDismissed) return const SizedBox.shrink();
            return Opacity(
              opacity: _dragOverlayAnimCtrl.value,
              child: child,
            );
          },
          child: _DragOverlay(
            hoveredCard: _dragHoveredCard,
          ),
        ),
      ),
      ],
      ),
      ),
    );
  }
}

/// Chat top bar. Spec §4: 54px height.
/// Spec §4.3: shared top-bar button chrome — 40px width (overridable),
/// 54px height, 40px circular ripple centered at (0, 7), 20px icon glyph.
/// Colors: menuIconFg resting, menuIconFgOver on hover, windowBgOver overlay.
class _TopBarButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double width;
  /// Optional padding inside the 40×40 ripple circle to offset the icon
  /// from center. Used by menu toggle to place icon at spec position (16, 17).
  final EdgeInsetsGeometry? iconPadding;
  /// Spec §4.3: active state uses `windowActiveTextFg` (blue) instead of
  /// `menuIconFg`. Used by the info toggle when the info panel is open.
  final bool isActive;
  const _TopBarButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.width = 40,
    this.iconPadding,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final menuIconFg = isDark
        ? const Color(0xFF6c7883)
        : const Color(0xFF999999);
    final menuIconFgOver = isDark
        ? const Color(0xFFdcdcdc)
        : const Color(0xFF8a8a8a);
    final windowBgOver = isDark
        ? const Color(0xFF202b36)
        : const Color(0xFFf1f1f1);
    // Spec §4.3: windowActiveTextFg — day #168acd, night #6ab3f3.
    final windowActiveTextFg = isDark
        ? const Color(0xFF6ab3f3)
        : const Color(0xFF168acd);

    final restColor = isActive ? windowActiveTextFg : menuIconFg;
    final hoverColor = isActive ? windowActiveTextFg : menuIconFgOver;

    Widget btn = SizedBox(
      width: width,
      height: 54,
      child: Center(
        child: IconButton(
          icon: Icon(icon, size: 20),
          onPressed: onPressed,
          padding: iconPadding ?? EdgeInsets.zero,
          constraints: const BoxConstraints(),
          style: ButtonStyle(
            fixedSize: const WidgetStatePropertyAll(Size(40, 40)),
            minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
            maximumSize: const WidgetStatePropertyAll(Size(40, 40)),
            shape: const WidgetStatePropertyAll(CircleBorder()),
            iconColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return menuIconFg.withAlpha((0.4 * 255).round());
              }
              if (states.contains(WidgetState.hovered)) return hoverColor;
              return restColor;
            }),
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return Colors.transparent;
              }
              return windowBgOver;
            }),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
    return btn;
  }
}

class _ChatTopBar extends StatelessWidget {
  final ChatInfo chat;
  final String? typingUser;
  final bool isOnline;
  final ({String kind, int lastSeenMs}) lastSeen;
  final bool showBackButton;
  final VoidCallback? onBack;
  final VoidCallback? onToggleInfo;
  /// Attached to the more_vert IconButton so the Ctrl+\ shortcut (spec
  /// §24.4 `show_chat_menu`) can anchor the menu at the same pixel
  /// position as clicking the button.
  final Key? moreVertKey;
  /// Spec §4.1: hide the bottom divider during one-column slide transitions.
  final bool hideDivider;

  final int groupOnlineCount;
  /// Spec §4.3: when true, the info toggle icon uses `windowActiveTextFg`
  /// (blue) instead of the default `menuIconFg`.
  final bool isInfoOpen;

  /// Spec §4.3: search button state — when true, the title/subtitle area is
  /// replaced with an inline search text field.
  final bool isSearching;
  final VoidCallback? onToggleSearch;
  final TextEditingController? searchController;
  final FocusNode? searchFocusNode;
  /// Spec §4.3: search results navigation state.
  final int searchResultCount;
  final int searchResultIndex;
  /// True when a search query has been entered (to show counter/nav).
  final bool hasSearchQuery;
  final VoidCallback? onSearchPrev;
  final VoidCallback? onSearchNext;
  final ValueChanged<String>? onSearchChanged;

  /// §22.6: Active forum topic (when chat.type == topic).
  final ForumTopic? activeTopic;
  /// §22.6: Parent group chat for topic subtitle (member count).
  final ChatInfo? parentChat;

  /// §23.4: When true, this top bar renders the scheduled messages section
  /// header instead of the normal chat header.
  final bool isScheduledView;
  final VoidCallback? onExitScheduled;

  const _ChatTopBar({
    required this.chat,
    this.typingUser,
    this.isOnline = false,
    this.lastSeen = (kind: '', lastSeenMs: 0),
    required this.showBackButton,
    this.onBack,
    this.onToggleInfo,
    this.moreVertKey,
    this.hideDivider = false,
    this.groupOnlineCount = 0,
    this.isInfoOpen = false,
    this.isSearching = false,
    this.onToggleSearch,
    this.searchController,
    this.searchFocusNode,
    this.searchResultCount = 0,
    this.searchResultIndex = -1,
    this.hasSearchQuery = false,
    this.onSearchPrev,
    this.onSearchNext,
    this.onSearchChanged,
    this.activeTopic,
    this.parentChat,
    this.isScheduledView = false,
    this.onExitScheduled,
  });

  /// Format a last-seen descriptor per Telegram Desktop spec §1.4 / §7588.
  static String _formatLastSeen(({String kind, int lastSeenMs}) ls) =>
      formatChatLastSeen(ls);

  static Widget _chatAvatar(ChatInfo chat, ThemeData theme, double radius) {
    if (chat.avatarPath.isNotEmpty) {
      final file = File(chat.avatarPath);
      return ClipOval(
        child: Image.file(
          file,
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallbackAvatar(chat, theme, radius),
        ),
      );
    }
    return _fallbackAvatar(chat, theme, radius);
  }

  /// Show the chat-level action menu anchored to the more_vert button.
  /// Spec §4.3: New Window, Archive, Pin, View Profile, Mute, Mark Read/Unread,
  /// Clear History, Delete Chat, Leave Channel.
  static void _showTopBarMenu(BuildContext btnCtx, ChatInfo chat, {VoidCallback? onToggleInfo}) {
    final chatState = btnCtx.read<ChatState>();
    final button = btnCtx.findRenderObject() as RenderBox;
    final buttonPos = button.localToGlobal(Offset(0, button.size.height));
    final isTopic = chat.type == ChatType.topic;

    if (isTopic) {
      _showTopicBurgerMenu(btnCtx, chat, chatState, buttonPos, onToggleInfo: onToggleInfo);
      return;
    }

    final isGroupy = chat.type == ChatType.group ||
        chat.type == ChatType.channel;
    final isDm = chat.type == ChatType.dm;
    final isForumAsMessages = chatState.isForumViewAsMessages;
    showTelegramMenu<String>(
      context: btnCtx,
      position: buttonPos,
      items: [
        if (onToggleInfo != null)
          const TelegramMenuItem(value: 'view_profile', label: 'View Profile'),
        if (isForumAsMessages)
          const TelegramMenuItem(
            value: 'view_as_topics',
            icon: Icon(Icons.topic_outlined, size: 20),
            label: 'View as Topics',
          ),
        TelegramMenuItem(value: 'mute', label: chat.isMuted ? 'Unmute' : 'Mute'),
        TelegramMenuItem(
          value: 'read',
          label: chat.unreadCount > 0 ? 'Mark as Read' : 'Mark as Unread',
        ),
        TelegramMenuItem(value: 'pin', label: chat.isPinned ? 'Unpin' : 'Pin'),
        TelegramMenuItem(value: 'archive', label: chat.isArchived ? 'Unarchive' : 'Archive'),
        const TelegramMenuItem.separator(),
        const TelegramMenuItem(value: 'clear_history', label: 'Clear History'),
        if (isDm)
          const TelegramMenuItem(value: 'delete_chat', label: 'Delete Chat', isAttention: true),
        if (isGroupy)
          TelegramMenuItem(value: 'leave', label: chat.type == ChatType.channel ? 'Leave Channel' : 'Leave Chat', isAttention: true),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'view_profile':
          onToggleInfo?.call();
        case 'view_as_topics':
          chatState.toggleForumViewAsMessages();
        case 'mute':
          chatState.muteChat(chat.accountId, chat.chatId, !chat.isMuted);
        case 'read':
          if (chat.unreadCount > 0) {
            chatState.markChatRead(chat.accountId, chat.chatId);
          }
        case 'pin':
          chatState.pinChat(chat.accountId, chat.chatId, !chat.isPinned);
        case 'archive':
          chatState.archiveChat(chat.accountId, chat.chatId, !chat.isArchived);
        case 'clear_history':
          showDeleteConfirmBox(
            btnCtx,
            mode: DeleteBoxMode.clearHistory,
            chatType: chat.type,
            peerName: chat.title,
            isSavedMessages: chat.title == 'Saved Messages',
          ).then((r) {
            if (r.confirmed) chatState.clearHistory(chat.accountId, chat.chatId);
          });
        case 'delete_chat':
          showDeleteConfirmBox(
            btnCtx,
            mode: DeleteBoxMode.leaveChat,
            chatType: chat.type,
            peerName: chat.title,
            canRevoke: chat.type == ChatType.dm,
          ).then((r) {
            if (r.confirmed) chatState.deleteChat(chat.accountId, chat.chatId);
          });
        case 'leave':
          showDeleteConfirmBox(
            btnCtx,
            mode: DeleteBoxMode.leaveChat,
            chatType: chat.type,
            peerName: chat.title,
          ).then((r) {
            if (r.confirmed) chatState.leaveChat(chat.accountId, chat.chatId);
          });
      }
    });
  }

  /// §22.8: Burger menu when inside a forum topic.
  /// Items: Mute, Create Topic, Topic Info, Group Info, View as Topics, Manage Group.
  static void _showTopicBurgerMenu(
    BuildContext btnCtx,
    ChatInfo chat,
    ChatState chatState,
    Offset buttonPos, {
    VoidCallback? onToggleInfo,
  }) {
    final parentChat = chatState.forumParentChat;
    final activeTopic = chatState.forumTopics
        .cast<ForumTopic?>()
        .firstWhere((t) => t!.id == chat.chatId, orElse: () => null);
    showTelegramMenu<String>(
      context: btnCtx,
      position: buttonPos,
      items: [
        TelegramMenuItem(
          value: 'mute',
          icon: Icon(chat.isMuted ? Icons.notifications : Icons.notifications_off_outlined, size: 20),
          label: chat.isMuted ? 'Unmute' : 'Mute',
        ),
        const TelegramMenuItem(
          value: 'create_topic',
          icon: Icon(Icons.add_circle_outline, size: 20),
          label: 'Create Topic',
        ),
        const TelegramMenuItem.separator(),
        const TelegramMenuItem(
          value: 'topic_info',
          icon: Icon(Icons.info_outline, size: 20),
          label: 'Topic Info',
        ),
        const TelegramMenuItem(
          value: 'group_info',
          icon: Icon(Icons.group_outlined, size: 20),
          label: 'Group Info',
        ),
        const TelegramMenuItem(
          value: 'view_as_topics',
          icon: Icon(Icons.topic_outlined, size: 20),
          label: 'View as Topics',
        ),
        if (activeTopic != null && activeTopic.canEdit)
          const TelegramMenuItem(
            value: 'manage_group',
            icon: Icon(Icons.settings_outlined, size: 20),
            label: 'Manage Group',
          ),
      ],
    ).then((value) {
      if (value == null || !btnCtx.mounted) return;
      switch (value) {
        case 'mute':
          chatState.muteChat(chat.accountId, chat.chatId, !chat.isMuted);
        case 'create_topic':
          _createTopicFromBurger(btnCtx, chatState, parentChat);
        case 'topic_info':
          onToggleInfo?.call();
        case 'group_info':
          if (parentChat != null) {
            chatState.openChat(parentChat);
            Future.microtask(() => onToggleInfo?.call());
          }
        case 'view_as_topics':
          chatState.closeChat();
        case 'manage_group':
          if (parentChat != null) {
            chatState.openChat(parentChat);
            Future.microtask(() => onToggleInfo?.call());
          }
      }
    });
  }

  static void _createTopicFromBurger(BuildContext ctx, ChatState chatState, ChatInfo? parentChat) async {
    if (parentChat == null) return;
    final result = await showEditForumTopicBox(ctx);
    if (result == null) return;
    try {
      final engine = ctx.read<EngineService>();
      final topicId = await engine.createForumTopic(
        parentChat.accountId, parentChat.chatId, result.title, result.colorId, result.iconEmojiId,
      );
      await chatState.refreshForumTopics();
      if (topicId > 0) {
        final newTopic = chatState.forumTopics.cast<ForumTopic?>().firstWhere(
          (t) => t!.id == topicId.toString(),
          orElse: () => null,
        );
        if (newTopic != null) chatState.openTopic(newTopic);
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('Failed to create topic: $e')),
        );
      }
    }
  }

  /// Spec §4.3: right-click on call button opens audio/video call submenu.
  void _showCallMenu(BuildContext context, Offset globalPos) {
    showTelegramMenu<String>(
      context: context,
      position: globalPos,
      items: const [
        TelegramMenuItem(value: 'audio_call', icon: Icon(Icons.call), label: 'Audio Call'),
        TelegramMenuItem(value: 'video_call', icon: Icon(Icons.videocam), label: 'Video Call'),
      ],
    ).then((value) {
      if (value == null || !context.mounted) return;
      showCallPanel(context, CallPanelInfo(
        callerId: chat.chatId,
        callerName: chat.title,
        callerAvatarUrl: chat.avatarPath,
        isVideo: value == 'video_call',
        state: CallPanelState.connecting,
      ));
    });
  }

  /// Spec §4.2: right-click on back button opens a call-type menu.
  void _showBackButtonCallMenu(BuildContext context, Offset globalPos) {
    showTelegramMenu<String>(
      context: context,
      position: globalPos,
      items: const [
        TelegramMenuItem(value: 'audio_call', icon: Icon(Icons.call), label: 'Audio Call'),
        TelegramMenuItem(value: 'video_call', icon: Icon(Icons.videocam), label: 'Video Call'),
      ],
    ).then((value) {
      if (value == null || !context.mounted) return;
      showCallPanel(context, CallPanelInfo(
        callerId: chat.chatId,
        callerName: chat.title,
        callerAvatarUrl: chat.avatarPath,
        isVideo: value == 'video_call',
        state: CallPanelState.connecting,
      ));
    });
  }

  static const _colorRemap = [0, 7, 4, 1, 6, 3, 5];
  static const _userpicPalette = [
    Color(0xFFe17076), Color(0xFF7bc862), Color(0xFFe5ca77), Color(0xFF65aadd),
    Color(0xFFa695e7), Color(0xFFee7aae), Color(0xFF6ec9cb), Color(0xFFe8a64e),
  ];

  static Widget _fallbackAvatar(ChatInfo chat, ThemeData theme, double radius) {
    final numId = int.tryParse(chat.chatId) ?? chat.chatId.hashCode.abs();
    final paletteIndex = _colorRemap[numId.abs() % 7];
    return CircleAvatar(
      radius: radius,
      backgroundColor: _userpicPalette[paletteIndex],
      child: Text(
        chat.title.isNotEmpty ? chat.title[0].toUpperCase() : '?',
        style: TextStyle(color: Colors.white, fontSize: radius * 0.7, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// §22.6: Build the topic icon widget for the title prefix.
  /// Uses normalForumTopicIcon size (19px) per spec §22.2.1.
  Widget _buildTopicTitleIcon(BuildContext context) {
    final topic = activeTopic!;
    if (topic.isGeneral) {
      return const GeneralForumTopicIcon(size: ForumTopicIcon.normalSize);
    }
    if (topic.hasCustomIcon) {
      final engine = context.read<EngineService>();
      return CustomEmojiTopicIcon(
        documentId: topic.iconEmojiId,
        accountId: chat.accountId,
        engine: engine,
        size: ForumTopicIcon.normalSize,
      );
    }
    return ForumTopicIcon(
      colorId: topic.colorId,
      title: topic.title,
      size: ForumTopicIcon.normalSize,
    );
  }

  static void _showScheduledMenu(BuildContext btnCtx, ChatInfo chat) {
    final button = btnCtx.findRenderObject() as RenderBox;
    final buttonPos = button.localToGlobal(Offset(0, button.size.height));
    showTelegramMenu<String>(
      context: btnCtx,
      position: buttonPos,
      items: const [
        TelegramMenuItem(value: 'create_poll', icon: Icon(Icons.poll_outlined, size: 20), label: 'Create Poll'),
        TelegramMenuItem(value: 'create_todo', icon: Icon(Icons.checklist_outlined, size: 20), label: 'Create To-do List'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (isScheduledView) {
      return _buildScheduledTopBar(context, theme, isDark);
    }

    // Subtitle: typing, online status, member count, or last seen.
    String subtitle;
    Color? subtitleColor;
    final bool isTopic = chat.type == ChatType.topic && activeTopic != null;
    final bool isTyping = typingUser != null;
    if (isTyping) {
      subtitle = ''; // rendered via _TopBarTypingDots widget instead
      subtitleColor = theme.colorScheme.primary;
    } else if (isTopic) {
      // §22.6: topic subtitle shows parent group member count.
      final pc = parentChat;
      if (pc != null && pc.memberCount > 0) {
        subtitle = '${pc.memberCount} members';
        if (groupOnlineCount > 1) {
          subtitle = '${pc.memberCount} members, $groupOnlineCount online';
        }
      } else {
        subtitle = chat.parentTitle;
      }
      subtitleColor = isDark
          ? const Color(0xFF98b4d3)
          : const Color(0xFF999999);
    } else if (chat.type == ChatType.dm && isOnline) {
      subtitle = 'online';
      subtitleColor = const Color(0xFF3BA55C); // online green
    } else if (chat.type == ChatType.dm) {
      subtitle = _formatLastSeen(lastSeen);
      subtitleColor = isDark
          ? const Color(0xFF98b4d3)
          : const Color(0xFF999999);
    } else if (chat.memberCount > 0) {
      subtitleColor = isDark
          ? const Color(0xFF98b4d3)
          : const Color(0xFF999999);
      if (chat.type == ChatType.channel) {
        subtitle = '${chat.memberCount} subscribers';
      } else if (groupOnlineCount > 1) {
        subtitle = '${chat.memberCount} members, $groupOnlineCount online';
      } else {
        subtitle = '${chat.memberCount} members';
      }
    } else {
      subtitle = '';
    }
    // Spec §4.1: topBarBg = windowBg. Day #ffffff, night #17212b.
    final topBarBg = isDark ? const Color(0xFF17212b) : Colors.white;
    // Spec §4.1: shadowFg divider. Day #00000018 (~9% black), night #04080e56 (~34%).
    final shadowFg = isDark ? const Color(0x5604080e) : const Color(0x18000000);

    return Container(
      height: 54, // topBarHeight per spec §4.1
      decoration: BoxDecoration(
        color: topBarBg,
        // Spec §4.1: divider hidden during one-column slide transitions.
        border: hideDivider ? null : Border(
          bottom: BorderSide(color: shadowFg, width: 1),
        ),
      ),
      // Spec §4.2: left uses _leftTaken (60px with back, 17px without).
      // Spec §4.3: buttons flush (0-gap) — no right padding; the menu toggle's
      // 44px width provides the right-side breathing room for the icon.
      child: Row(
        children: [
          if (showBackButton)
            // Spec §4.2: historyTopBarBack — exact 60px width, full 54px height.
            // Right-click opens call-type menu per spec §4.2.
            GestureDetector(
              onSecondaryTapUp: (details) {
                _showBackButtonCallMenu(context, details.globalPosition);
              },
              child: SizedBox(
                width: 60,
                height: 54,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, size: 20),
                  onPressed: onBack,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 20,
                ),
              ),
            )
          else
            // Spec §4.2: _leftTaken = 17px when no back button.
            const SizedBox(width: 17),
          // §22.6: For topic chats, skip the avatar — the topic icon is shown
          // inline before the title text. For other types, show the 42px avatar.
          if (!isTopic)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggleInfo,
              child: SizedBox(
                width: 52,
                height: 54,
                child: Stack(
                  children: [
                    Positioned(
                      left: 2,
                      top: 5,
                      child: _chatAvatar(chat, theme, 21),
                    ),
                  ],
                ),
              ),
            )
          else
            const SizedBox(width: 8),
          // Spec §4.3: when searching, replace title/subtitle with inline
          // search text field + filter buttons + results navigation.
          if (isSearching)
            Expanded(
              child: Row(
                children: [
                  // Search text field fills available space.
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: TextField(
                        controller: searchController,
                        focusNode: searchFocusNode,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.normal,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search',
                          hintStyle: TextStyle(
                            color: isDark
                                ? const Color(0xFF6c7883)
                                : const Color(0xFF999999),
                            fontSize: 14,
                          ),
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 8,
                          ),
                        ),
                        onChanged: onSearchChanged,
                        onSubmitted: (_) => onSearchNext?.call(),
                      ),
                    ),
                  ),
                  // Spec §4.3: when query is active, show results counter
                  // and navigation arrows. When empty, show filter buttons.
                  if (hasSearchQuery) ...[
                    // Results counter text.
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Text(
                        searchResultCount > 0
                            ? '${searchResultIndex + 1} of $searchResultCount'
                            : 'No results',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark
                              ? const Color(0xFF6c7883)
                              : const Color(0xFF999999),
                        ),
                      ),
                    ),
                    // Up arrow — previous (newer) result.
                    SizedBox(
                      width: 28,
                      height: 54,
                      child: IconButton(
                        icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                        onPressed: searchResultCount > 0
                            ? onSearchPrev
                            : null,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        splashRadius: 14,
                        color: isDark
                            ? const Color(0xFF6c7883)
                            : const Color(0xFF999999),
                      ),
                    ),
                    // Down arrow — next (older) result.
                    SizedBox(
                      width: 28,
                      height: 54,
                      child: IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                        onPressed: searchResultCount > 0
                            ? onSearchNext
                            : null,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        splashRadius: 14,
                        color: isDark
                            ? const Color(0xFF6c7883)
                            : const Color(0xFF999999),
                      ),
                    ),
                  ] else ...[
                    // Spec §4.3: "jump to date" filter button (calendar icon).
                    _TopBarButton(
                      icon: Icons.calendar_today,
                      onPressed: () {
                        final ctx = searchFocusNode?.context;
                        if (ctx == null) return;
                        showDatePicker(
                          context: ctx,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2013, 8),
                          lastDate: DateTime.now(),
                        ).then((date) {
                          if (date == null) return;
                          final chatState = ctx.read<ChatState>();
                          chatState.jumpToMessage(date.millisecondsSinceEpoch);
                        });
                      },
                    ),
                    // Spec §4.3: "choose from user" filter button (person icon).
                    if (chat.type == ChatType.group ||
                        chat.type == ChatType.channel ||
                        chat.type == ChatType.topic)
                      _TopBarButton(
                        icon: Icons.person_search,
                        onPressed: () {
                          // TODO: open user picker for "from user" filter
                        },
                      ),
                  ],
                ],
              ),
            )
          else
            // Tappable title block — toggles info panel.
            Expanded(
              child: InkWell(
                onTap: onToggleInfo,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // §22.6: topic icon prefix before title.
                          if (isTopic) ...[
                            _buildTopicTitleIcon(context),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              isTopic && activeTopic != null && activeTopic!.isGeneral
                                  ? '# ${chat.title.isNotEmpty ? chat.title : chat.chatId}'
                                  : (chat.title.isNotEmpty ? chat.title : chat.chatId),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          if (chat.isVerified) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.verified,
                              size: 16,
                              color: Color(0xFF168acd),
                            ),
                          ],
                          if (chat.isScam) ...[
                            const SizedBox(width: 4),
                            _TopBarWarningBadge(label: 'SCAM'),
                          ],
                          if (chat.isFake) ...[
                            const SizedBox(width: 4),
                            _TopBarWarningBadge(label: 'FAKE'),
                          ],
                          if (chat.isMuted) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.volume_off,
                              size: 16,
                              color: theme.textTheme.bodySmall?.color,
                            ),
                          ],
                        ],
                      ),
                      if (isTyping)
                        _TopBarTypingDots(
                          userName: typingUser!,
                          color: subtitleColor ?? theme.colorScheme.primary,
                        )
                      else if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 13, // dialogsTextFont = normalFont 13px
                            color: subtitleColor,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          // Spec §4.3: right-side buttons — shared 40×54 chrome.
          // Per spec order (left to right): Search, GroupCall, Call, Info, Menu.
          // Spec §4.3: Search button — top_bar_search icon, toggles inline search.
          _TopBarButton(
            icon: Icons.search,
            onPressed: onToggleSearch,
            isActive: isSearching,
          ),
          // Spec §4.3: Call button — 1:1 DMs only, phone icon.
          // Right-click opens audio/video call submenu.
          if (chat.type == ChatType.dm)
            Builder(
              builder: (btnCtx) => GestureDetector(
                onSecondaryTapUp: (details) {
                  _showCallMenu(btnCtx, details.globalPosition);
                },
                child: _TopBarButton(
                  icon: Icons.call,
                  onPressed: () {
                    showCallPanel(context, CallPanelInfo(
                      callerId: chat.chatId,
                      callerName: chat.title,
                      callerAvatarUrl: chat.avatarPath,
                      isVideo: false,
                      state: CallPanelState.connecting,
                    ));
                  },
                ),
              ),
            ),
          // Spec §4.3: Group call button — groups/channels when calls permitted.
          // icon: top_bar_group_call, iconPosition (4, 12).
          if (chat.type == ChatType.group || chat.type == ChatType.channel)
            _TopBarButton(
              icon: Icons.phone_in_talk,
              onPressed: () {
                // TODO: initiate group call via engine
              },
            ),
          if (onToggleInfo != null)
            _TopBarButton(
              icon: Icons.info_outline,
              onPressed: onToggleInfo,
              isActive: isInfoOpen,
            ),
          // Spec §4.3: topBarSkip = -5px — menu toggle pulled 5px tighter
          // against its left neighbour.  Allocate 39px (44 − 5) in the Row
          // while rendering the full 44px button; the 5px overflow extends
          // leftward into the previous button's space.
          SizedBox(
            width: 39, // 44 - topBarSkip(5)
            child: OverflowBox(
              maxWidth: 44,
              alignment: Alignment.centerRight,
              child: Builder(
                builder: (btnCtx) => _TopBarButton(
                  key: moreVertKey,
                  icon: Icons.more_vert,
                  width: 44,
                  iconPadding: const EdgeInsets.only(left: 8),
                  onPressed: () => _showTopBarMenu(btnCtx, chat, onToggleInfo: onToggleInfo),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduledTopBar(BuildContext context, ThemeData theme, bool isDark) {
    final topBarBg = isDark ? const Color(0xFF17212b) : Colors.white;
    final shadowFg = isDark ? const Color(0x5604080e) : const Color(0x18000000);
    final isSavedMessages = chat.title == 'Saved Messages';
    final titleText = isSavedMessages ? 'Reminders' : 'Scheduled messages';
    final dialogsNameFg = isDark ? const Color(0xFFf5f5f5) : const Color(0xFF222222);

    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: topBarBg,
        border: hideDivider ? null : Border(
          bottom: BorderSide(color: shadowFg, width: 1),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            height: 54,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, size: 20),
              onPressed: onExitScheduled,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              splashRadius: 20,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                titleText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: dialogsNameFg,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 39,
            child: OverflowBox(
              maxWidth: 44,
              alignment: Alignment.centerRight,
              child: Builder(
                builder: (btnCtx) => _TopBarButton(
                  icon: Icons.more_vert,
                  width: 44,
                  iconPadding: const EdgeInsets.only(left: 8),
                  onPressed: () => _showScheduledMenu(btnCtx, chat),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Spec §4.2: Animated typing indicator for the top bar subtitle.
/// Shows "UserName is typing" with three bouncing dots.
class _TopBarWarningBadge extends StatelessWidget {
  final String label;
  const _TopBarWarningBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFe53935);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
          height: 1.0,
        ),
      ),
    );
  }
}

class _TopBarTypingDots extends StatefulWidget {
  final String userName;
  final Color color;

  const _TopBarTypingDots({required this.userName, required this.color});

  @override
  State<_TopBarTypingDots> createState() => _TopBarTypingDotsState();
}

class _TopBarTypingDotsState extends State<_TopBarTypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontSize: 13, // dialogsTextFont = normalFont 13px
      color: widget.color,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            '${widget.userName} is typing',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        const SizedBox(width: 1),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final phase = (_controller.value + i / 3.0) * 2 * math.pi;
                final dy = -2.5 * math.max(0.0, math.sin(phase));
                return Padding(
                  padding: const EdgeInsets.only(left: 1),
                  child: Transform.translate(
                    offset: Offset(0, dy),
                    child: Text(
                      '.',
                      style: style?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ],
    );
  }
}

/// Scrollable message list. Newest at bottom, loads more at top.
class _MessageList extends StatelessWidget {
  final List<CachedMessage> messages;
  final bool loading;
  final bool isGroupChat;
  final ChatState? senderAvatars; // for looking up sender avatar b64 by ID
  final ScrollController scrollController;
  final ValueChanged<String> onReply;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggleSelect;
  final ValueChanged<String> onLongPress;
  final void Function(String msgId, Offset position, String selectedText) onContextMenu;
  final ValueChanged<String>? onSenderTap;
  final void Function(String senderId, Offset position)? onSenderContextMenu;
  final ValueChanged<String>? onReplyTap;
  /// Spec §4.3: ID of the currently highlighted search result message.
  final String? searchHighlightId;
  /// Spec §4.3: active search query for text highlighting within bubbles.
  final String searchQuery;
  /// Spec §5 / §49.4: unread count at time chat was opened (for unread bar).
  final int openedUnreadCount;
  final bool isScheduledView;

  const _MessageList({
    required this.messages,
    required this.loading,
    this.isGroupChat = false,
    this.senderAvatars,
    required this.scrollController,
    required this.onReply,
    required this.selectedIds,
    required this.onToggleSelect,
    required this.onLongPress,
    required this.onContextMenu,
    this.onSenderTap,
    this.onSenderContextMenu,
    this.onReplyTap,
    this.searchHighlightId,
    this.searchQuery = '',
    this.openedUnreadCount = 0,
    this.isScheduledView = false,
  });

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty && !loading) {
      if (isScheduledView) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final bgColor = isDark ? const Color(0xD5213040) : const Color(0x7F517c41);
        final scaffoldBg = isDark ? const Color(0xFF0e1621) : const Color(0xFFe6ebee);
        return Container(
          color: scaffoldBg,
          child: Center(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 3, 12, 4),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'No scheduled messages',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFFFFFFF),
                ),
              ),
            ),
          ),
        );
      }
      return Center(
        child: Text(
          'No messages yet',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    // Pre-compute display items: group consecutive album members.
    final displayItems = _buildDisplayItems(messages);

    return ListView.builder(
      controller: scrollController,
      reverse: true, // Newest at bottom.
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: displayItems.length + (loading ? 1 : 0),
      itemBuilder: (context, index) {
        if (loading && index == displayItems.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final item = displayItems[index];
        final msg = item.primary;
        final prevItem = index > 0 ? displayItems[index - 1] : null;
        final nextItem = index < displayItems.length - 1 ? displayItems[index + 1] : null;

        final showDate = nextItem == null ||
            _differentDay(msg.timestamp, nextItem.primary.timestamp);

        // Consecutive message grouping (spec §5):
        final isFirstInGroup = msg.isService || nextItem == null ||
            nextItem.primary.isService ||
            nextItem.primary.senderId != msg.senderId ||
            showDate ||
            (msg.timestamp - nextItem.primary.timestamp).abs() > 180000;
        final isLastInGroup = msg.isService || prevItem == null ||
            prevItem.primary.isService ||
            prevItem.primary.senderId != msg.senderId ||
            _differentDay(msg.timestamp, prevItem.primary.timestamp) ||
            (prevItem.primary.timestamp - msg.timestamp).abs() > 180000;

        final isSelected = selectedIds.contains(msg.msgId);
        final inSelectionMode = selectedIds.isNotEmpty;
        final isSearchHighlight = msg.msgId == searchHighlightId;

        final showUnreadBar = openedUnreadCount > 0 &&
            openedUnreadCount <= messages.length &&
            item.originalIndices.any((i) => i == openedUnreadCount - 1);

        if (msg.isService) {
          return Column(
            children: [
              if (showDate) _DateSeparator(timestamp: msg.timestamp, isScheduled: isScheduledView),
              if (showUnreadBar) _UnreadBar(count: openedUnreadCount),
              _ServiceMessage(text: msg.contentText),
            ],
          );
        }

        return Column(
          children: [
            if (showDate) _DateSeparator(timestamp: msg.timestamp, isScheduled: isScheduledView),
            if (showUnreadBar) _UnreadBar(count: openedUnreadCount),
            PlatformGestureDetector(
              behavior: inSelectionMode ? HitTestBehavior.opaque : HitTestBehavior.deferToChild,
              onLongPress: () => onLongPress(msg.msgId),
              onTap: inSelectionMode ? () => onToggleSelect(msg.msgId) : null,
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeInOut,
                padding: EdgeInsets.only(right: inSelectionMode ? 30.0 : 0.0),
                child: Container(
                  color: isSearchHighlight
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
                      : null,
                  child: IgnorePointer(
                    ignoring: inSelectionMode,
                    child: item.isAlbum
                        ? MessageBubble(
                            message: msg,
                            isFirstInGroup: isFirstInGroup,
                            isLastInGroup: isLastInGroup,
                            isGroupChat: isGroupChat,
                            isSelected: isSelected,
                            inSelectionMode: inSelectionMode,
                            isScheduledView: isScheduledView,
                            allMessages: messages,
                            albumItems: item.albumMessages,
                            senderAvatarB64: senderAvatars?.senderAvatar(msg.senderId),
                            onReply: () => onReply(msg.msgId),
                            onContextMenu: (pos, sel) => onContextMenu(msg.msgId, pos, sel),
                            onSenderTap: onSenderTap,
                            onSenderContextMenu: onSenderContextMenu,
                            onReplyTap: onReplyTap,
                          )
                        : MessageBubble(
                            message: msg,
                            isFirstInGroup: isFirstInGroup,
                            isLastInGroup: isLastInGroup,
                            isGroupChat: isGroupChat,
                            isSelected: isSelected,
                            inSelectionMode: inSelectionMode,
                            isScheduledView: isScheduledView,
                            allMessages: messages,
                            senderAvatarB64: senderAvatars?.senderAvatar(msg.senderId),
                            onReply: () => onReply(msg.msgId),
                            onContextMenu: (pos, sel) => onContextMenu(msg.msgId, pos, sel),
                            onSenderTap: onSenderTap,
                            onSenderContextMenu: onSenderContextMenu,
                            onReplyTap: onReplyTap,
                          ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static List<_DisplayItem> _buildDisplayItems(List<CachedMessage> messages) {
    final items = <_DisplayItem>[];
    // Sort messages with same groupedId to be consecutive before grouping.
    // The DB returns ORDER BY timestamp DESC which may interleave album items
    // with non-album messages at the same timestamp.
    final sorted = List<CachedMessage>.from(messages);
    sorted.sort((a, b) {
      final cmp = b.timestamp.compareTo(a.timestamp);
      if (cmp != 0) return cmp;
      // Same timestamp: group by groupedId so album items are consecutive.
      if (a.groupedId.isNotEmpty && b.groupedId.isNotEmpty) {
        final gCmp = a.groupedId.compareTo(b.groupedId);
        if (gCmp != 0) return gCmp;
      } else if (a.groupedId.isNotEmpty) {
        return -1;
      } else if (b.groupedId.isNotEmpty) {
        return 1;
      }
      return a.msgId.compareTo(b.msgId);
    });
    int i = 0;
    while (i < sorted.length) {
      final msg = sorted[i];
      if (msg.groupedId.isNotEmpty && msg.hasMedia) {
        // Collect all consecutive messages with this groupedId.
        final groupId = msg.groupedId;
        final albumMsgs = <CachedMessage>[msg];
        final indices = <int>[i];
        int j = i + 1;
        while (j < sorted.length &&
            sorted[j].groupedId == groupId &&
            sorted[j].hasMedia) {
          albumMsgs.add(sorted[j]);
          indices.add(j);
          j++;
        }
        if (albumMsgs.length >= 2) {
          final captionMsg = albumMsgs.firstWhere(
            (m) => m.contentText.isNotEmpty,
            orElse: () => albumMsgs.first,
          );
          items.add(_DisplayItem(
            primary: captionMsg,
            albumMessages: albumMsgs,
            originalIndices: indices,
          ));
          i = j;
          continue;
        }
      }
      items.add(_DisplayItem(primary: msg, originalIndices: [i]));
      i++;
    }
    return items;
  }

  bool _differentDay(int ts1, int ts2) {
    final d1 = DateTime.fromMillisecondsSinceEpoch(ts1);
    final d2 = DateTime.fromMillisecondsSinceEpoch(ts2);
    return d1.year != d2.year || d1.month != d2.month || d1.day != d2.day;
  }
}

class _DisplayItem {
  final CachedMessage primary;
  final List<CachedMessage> albumMessages;
  final List<int> originalIndices;
  const _DisplayItem({
    required this.primary,
    this.albumMessages = const [],
    this.originalIndices = const [],
  });
  bool get isAlbum => albumMessages.length >= 2;
}


/// Centered date separator pill.
class _DateSeparator extends StatelessWidget {
  final int timestamp;
  final bool isScheduled;

  const _DateSeparator({required this.timestamp, this.isScheduled = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final diff = now.difference(dt);

    String text;
    if (isScheduled) {
      text = 'Scheduled for ${_months[dt.month - 1]} ${dt.day}';
    } else if (diff.inDays == 0 && dt.day == now.day) {
      text = 'Today';
    } else if (diff.inDays == 1 || (diff.inDays == 0 && dt.day != now.day)) {
      text = 'Yesterday';
    } else {
      text = '${_months[dt.month - 1]} ${dt.day}, ${dt.year}';
    }

    // msgServiceBg: day #517c417f, night #213040d5
    final bgColor = isDark ? const Color(0xD5213040) : const Color(0x7F517c41);

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Center(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 3, 12, 4),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFFFFFFFF),
            ),
          ),
        ),
      ),
    );
  }

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
}

/// Spec §5 Service Messages: centered text in rounded pill.
/// msgServiceBg: day #517c417f, night #213040d5. msgServiceFg: #ffffff.
/// Padding: msgServicePadding 12/3/12/4. Margin: 10px above, 2px below.
/// Font: 13px semibold. Radius: fully rounded pill (radius = height/2).
class _ServiceMessage extends StatelessWidget {
  final String text;

  const _ServiceMessage({required this.text});

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // msgServiceBg: day #517c417f, night #213040d5
    final bgColor = isDark ? const Color(0xD5213040) : const Color(0x7F517c41);

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Center(
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85,
          ),
          padding: const EdgeInsets.fromLTRB(12, 3, 12, 4),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFFFFFFFF),
            ),
          ),
        ),
      ),
    );
  }
}

/// Spec §5 / §49.4: Full-width "N unread messages" divider band.
/// historyUnreadBarBg: day #FCFBFA / night #182433
/// historyUnreadBarFg: day #538BB4 / night #FFFFFF
class _UnreadBar extends StatelessWidget {
  final int count;
  const _UnreadBar({required this.count});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF182433) : const Color(0xFFFCFBFA);
    final fgColor = isDark ? const Color(0xFFFFFFFF) : const Color(0xFF538BB4);
    // 1px top/bottom borders — subtle separator lines
    final borderColor = isDark
        ? const Color(0xFF0E1621) // slightly darker than bg
        : const Color(0xFFE8E8E8); // light gray

    final label = count == 1 ? '1 unread message' : '$count unread messages';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 7),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.symmetric(
          horizontal: BorderSide(color: borderColor, width: 1),
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: fgColor,
        ),
      ),
    );
  }
}

/// Reply preview bar above compose — Telegram Desktop FieldHeader style.
/// 49px height, reply icon at (7,7), optional 32px thumbnail, cancel button.
class _ReplyBar extends StatelessWidget {
  final String replyId;
  final List<CachedMessage> messages;
  final VoidCallback onCancel;

  const _ReplyBar({
    required this.replyId,
    required this.messages,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final msg = messages.where((m) => m.msgId == replyId).firstOrNull;
    final hasThumb = msg != null && msg.mediaThumbB64.isNotEmpty;

    final titleColor = isDark ? const Color(0xFF429BDB) : theme.colorScheme.primary;
    final descColor = isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
    final cancelColor = isDark ? const Color(0xFF6C7883) : const Color(0xFFA0ACB6);

    return Container(
      height: 49,
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          // Reply icon at point(7,7), 22×22.
          Padding(
            padding: const EdgeInsets.only(left: 7, top: 7),
            child: Align(
              alignment: Alignment.topLeft,
              child: Icon(Icons.reply, size: 22, color: titleColor),
            ),
          ),
          // Spacer to reach historyReplySkip (53px) minus icon area.
          const SizedBox(width: 24),
          // 2px accent bar, 36px tall.
          Container(width: 2, height: 36, color: titleColor),
          const SizedBox(width: 10),
          // Optional 32×32 thumbnail.
          if (hasThumb) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 32,
                height: 32,
                child: _buildThumb(msg!),
              ),
            ),
            const SizedBox(width: 10),
          ],
          // Title + description text block.
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  msg?.senderName ?? 'Reply',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    color: titleColor,
                  ),
                ),
                Text(
                  _descriptionText(msg),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.25,
                    color: descColor.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          // Cancel (X) button — 49×49 hit area.
          SizedBox(
            width: 49,
            height: 49,
            child: IconButton(
              onPressed: onCancel,
              icon: Icon(Icons.close, size: 18, color: cancelColor),
              splashRadius: 20,
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumb(CachedMessage msg) {
    if (msg.mediaThumbB64.isNotEmpty) {
      try {
        final bytes = base64Decode(msg.mediaThumbB64);
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          width: 32,
          height: 32,
          gaplessPlayback: true,
        );
      } catch (_) {}
    }
    return Container(
      color: Colors.grey.withValues(alpha: 0.3),
      child: const Icon(Icons.image, size: 16, color: Colors.grey),
    );
  }

  String _descriptionText(CachedMessage? msg) {
    if (msg == null) return '';
    if (msg.contentText.isNotEmpty) return msg.contentText;
    switch (msg.mediaType) {
      case 1: return 'Photo';
      case 2: return 'Video';
      case 3: return 'Audio';
      case 4: return 'Voice message';
      case 5: return 'Video message';
      case 6: return 'Sticker';
      case 7: return 'GIF';
      case 8: return 'File';
      default: return '';
    }
  }
}

/// Edit bar shown above the compose area while editing an outgoing message.
/// Telegram Desktop-style: blue 2px side stripe, pencil icon, "Editing" header +
/// 1-line preview of the message being edited.
class _EditBar extends StatelessWidget {
  final String editingId;
  final List<CachedMessage> messages;
  final VoidCallback onCancel;

  const _EditBar({
    required this.editingId,
    required this.messages,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final msg = messages.where((m) => m.msgId == editingId).firstOrNull;

    return Container(
      height: 49,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.dividerColor, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(Icons.edit, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Container(width: 2, height: 28, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Editing',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                Text(
                  msg?.contentText ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onCancel,
            tooltip: 'Cancel edit',
          ),
        ],
      ),
    );
  }
}

class _ForwardBar extends StatelessWidget {
  final List<String> forwardingMsgIds;
  final List<CachedMessage> messages;
  final bool hideSender;
  final VoidCallback onToggleHideSender;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  const _ForwardBar({
    required this.forwardingMsgIds,
    required this.messages,
    required this.hideSender,
    required this.onToggleHideSender,
    required this.onSend,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final titleColor = isDark ? const Color(0xFF429BDB) : theme.colorScheme.primary;
    final descColor = isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
    final cancelColor = isDark ? const Color(0xFF6C7883) : const Color(0xFFA0ACB6);

    final firstMsg = messages.where((m) => forwardingMsgIds.contains(m.msgId)).firstOrNull;
    final count = forwardingMsgIds.length;
    final hasThumb = firstMsg != null && firstMsg.mediaThumbB64.isNotEmpty;

    final titleText = count == 1
        ? (firstMsg?.senderName ?? 'Forward')
        : '$count forwarded messages';

    return Container(
      height: 49,
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 7, top: 7),
            child: Align(
              alignment: Alignment.topLeft,
              child: Icon(Icons.shortcut, size: 22, color: titleColor),
            ),
          ),
          const SizedBox(width: 24),
          Container(width: 2, height: 36, color: titleColor),
          const SizedBox(width: 10),
          if (hasThumb) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 32,
                height: 32,
                child: _buildThumb(firstMsg!),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: GestureDetector(
              onTap: onSend,
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titleText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                      color: titleColor,
                    ),
                  ),
                  Text(
                    _descriptionText(firstMsg, count),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.25,
                      color: descColor.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 36,
            height: 36,
            child: IconButton(
              onPressed: onToggleHideSender,
              icon: Icon(
                hideSender ? Icons.person_off : Icons.person,
                size: 18,
                color: hideSender ? titleColor : cancelColor,
              ),
              splashRadius: 18,
              padding: EdgeInsets.zero,
              tooltip: hideSender ? 'Show sender name' : 'Hide sender name',
            ),
          ),
          SizedBox(
            width: 49,
            height: 49,
            child: IconButton(
              onPressed: onCancel,
              icon: Icon(Icons.close, size: 18, color: cancelColor),
              splashRadius: 20,
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumb(CachedMessage msg) {
    if (msg.mediaThumbB64.isNotEmpty) {
      try {
        final bytes = base64Decode(msg.mediaThumbB64);
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          width: 32,
          height: 32,
          gaplessPlayback: true,
        );
      } catch (_) {}
    }
    return Container(
      color: Colors.grey.withValues(alpha: 0.3),
      child: const Icon(Icons.image, size: 16, color: Colors.grey),
    );
  }

  String _descriptionText(CachedMessage? msg, int count) {
    if (count > 1) {
      return 'Tap to choose destination';
    }
    if (msg == null) return 'Tap to choose destination';
    if (msg.contentText.isNotEmpty) return msg.contentText;
    switch (msg.mediaType) {
      case 1: return 'Photo';
      case 2: return 'Video';
      case 3: return 'Audio';
      case 4: return 'Voice message';
      case 5: return 'Video message';
      case 6: return 'Sticker';
      case 7: return 'GIF';
      case 8: return 'File';
      default: return 'Tap to choose destination';
    }
  }
}

class _WebPreviewBar extends StatelessWidget {
  final WebPagePreview preview;
  final VoidCallback onCancel;

  const _WebPreviewBar({
    required this.preview,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final titleColor = isDark ? const Color(0xFF429BDB) : theme.colorScheme.primary;
    final descColor = isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
    final cancelColor = isDark ? const Color(0xFF6C7883) : const Color(0xFFA0ACB6);
    final hasThumb = preview.thumbB64.isNotEmpty;

    return Container(
      height: 49,
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 7, top: 7),
            child: Align(
              alignment: Alignment.topLeft,
              child: Icon(Icons.link, size: 22, color: titleColor),
            ),
          ),
          const SizedBox(width: 24),
          Container(width: 2, height: 36, color: titleColor),
          const SizedBox(width: 10),
          if (hasThumb) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 32,
                height: 32,
                child: Image.memory(
                  base64Decode(preview.thumbB64),
                  fit: BoxFit.cover,
                  width: 32,
                  height: 32,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.grey.withValues(alpha: 0.3),
                    child: const Icon(Icons.language, size: 16, color: Colors.grey),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  preview.title.isNotEmpty
                      ? preview.title
                      : (preview.siteName.isNotEmpty ? preview.siteName : preview.url),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    color: titleColor,
                  ),
                ),
                Text(
                  preview.description.isNotEmpty
                      ? preview.description
                      : preview.url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.25,
                    color: descColor.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 49,
            height: 49,
            child: IconButton(
              onPressed: onCancel,
              icon: Icon(Icons.close, size: 18, color: cancelColor),
              splashRadius: 20,
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}

/// Spec §7.5: Bot reply keyboard (sticky below compose field).
class _BotReplyKeyboard extends StatelessWidget {
  final ReplyKeyboardData keyboard;
  final ValueChanged<String> onButtonPressed;

  const _BotReplyKeyboard({
    required this.keyboard,
    required this.onButtonPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final composeBg = isDark
        ? AppColors.historyComposeAreaBgNight
        : AppColors.historyComposeAreaBg;

    final rowCount = keyboard.rows.length;
    final useTiny = !keyboard.resize && rowCount > 4;
    final buttonHeight = useTiny ? 25.0 : 38.0;
    final buttonMargin = useTiny ? 4.0 : 10.0;
    final buttonPadding = useTiny ? 3.0 : 10.0;
    final textTopPad = useTiny ? 2.0 : 9.0;

    final naturalHeight = keyboard.rows.fold<double>(0.0, (sum, row) {
      return sum + buttonHeight + buttonMargin;
    }) + buttonMargin;
    final maxHeight = keyboard.resize ? naturalHeight : 200.0;

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        color: composeBg,
        child: SingleChildScrollView(
          padding: EdgeInsets.all(buttonMargin / 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: keyboard.rows.map((row) {
              return Padding(
                padding: EdgeInsets.symmetric(vertical: buttonMargin / 2),
                child: Row(
                  children: row.map((btn) {
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: buttonMargin / 2),
                        child: _BotKeyboardButton(
                          text: btn.text,
                          height: buttonHeight,
                          padding: buttonPadding,
                          textTopPad: textTopPad,
                          isDark: isDark,
                          useTiny: useTiny,
                          onPressed: () => onButtonPressed(btn.text),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _BotKeyboardButton extends StatefulWidget {
  final String text;
  final double height;
  final double padding;
  final double textTopPad;
  final bool isDark;
  final bool useTiny;
  final VoidCallback onPressed;

  const _BotKeyboardButton({
    required this.text,
    required this.height,
    required this.padding,
    required this.textTopPad,
    required this.isDark,
    required this.useTiny,
    required this.onPressed,
  });

  @override
  State<_BotKeyboardButton> createState() => _BotKeyboardButtonState();
}

class _BotKeyboardButtonState extends State<_BotKeyboardButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final botKbBg = widget.isDark
        ? const Color(0xFF2b3945)
        : const Color(0xFFe4e7eb);
    final botKbDownBg = widget.isDark
        ? const Color(0xFF3a4957)
        : const Color(0xFFd0d4d9);
    final botKbColor = widget.isDark
        ? const Color(0xFFffffff)
        : const Color(0xFF000000);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onPressed();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        height: widget.height,
        decoration: BoxDecoration(
          color: _pressed ? botKbDownBg : botKbBg,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: EdgeInsets.symmetric(horizontal: widget.padding),
        alignment: Alignment.center,
        child: Text(
          widget.text,
          style: TextStyle(
            fontSize: widget.useTiny ? 13 : 15,
            fontWeight: FontWeight.w600,
            color: botKbColor,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// Spec §4.5: Contact Status / Action Bar.
/// Shows below the top bar for DMs with non-contacts (Add Contact + Block),
/// blocked users (Unblock), or bots (status label).
class _ContactStatusBar extends StatelessWidget {
  final ChatInfo chat;
  final ChatState chatState;

  const _ContactStatusBar({required this.chat, required this.chatState});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Spec: windowActiveTextFg — day #168acd, night #6ab3f3.
    final windowActiveTextFg = isDark
        ? const Color(0xFF6ab3f3)
        : const Color(0xFF168acd);
    // Spec: attentionButtonFg — red in both themes.
    const attentionButtonFg = Color(0xFFdf3f40);
    // Spec: historyComposeAreaBg — flat background matches compose area.
    final bgColor = isDark
        ? const Color(0xFF17212b)
        : const Color(0xFFffffff);
    // Spec: historyComposeButtonBg — hover background.
    final hoverColor = isDark
        ? const Color(0xFF202b36)
        : const Color(0xFFF1F1F1);

    if (chat.isBlocked) {
      // Blocked: single "Unblock" button, 46px height, attentionButtonFg red.
      return Container(
        color: bgColor,
        height: 46,
        child: _ContactStatusButton(
          label: 'Unblock',
          color: attentionButtonFg,
          hoverColor: hoverColor,
          height: 46,
          textTop: 14,
          onTap: () => chatState.unblockUser(chat.accountId, chat.chatId),
        ),
      );
    }

    if (chat.isBot) {
      // Bot: status label centered, minWidth 240, no buttons.
      return Container(
        color: bgColor,
        height: 49,
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 240),
          child: Text(
            'This is a bot',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
        ),
      );
    }

    // Non-contact: "Add Contact" (blue) + "Block" (red), side by side.
    return Container(
      color: bgColor,
      height: 49,
      child: Row(
        children: [
          Expanded(
            child: _ContactStatusButton(
              label: 'Add Contact',
              color: windowActiveTextFg,
              hoverColor: hoverColor,
              height: 49,
              textTop: 16,
              onTap: () => _showAddContactDialog(context),
            ),
          ),
          const SizedBox(width: 16), // Spec: historyContactStatusMinSkip 16px.
          Expanded(
            child: _ContactStatusButton(
              label: 'Block',
              color: attentionButtonFg,
              hoverColor: hoverColor,
              height: 49,
              textTop: 16,
              onTap: () => chatState.blockUser(chat.accountId, chat.chatId),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddContactDialog(BuildContext context) {
    final firstNameCtrl = TextEditingController(text: chat.title);
    final lastNameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: firstNameCtrl,
              decoration: const InputDecoration(labelText: 'First Name'),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: lastNameCtrl,
              decoration: const InputDecoration(labelText: 'Last Name'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              chatState.addContact(
                chat.accountId,
                '', // phone unknown from DM context
                firstNameCtrl.text.trim(),
                lastNameCtrl.text.trim(),
              );
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

/// Spec §4.5: A single full-width flat button for the contact status bar.
class _ContactStatusButton extends StatefulWidget {
  final String label;
  final Color color;
  final Color hoverColor;
  final double height;
  final double textTop;
  final VoidCallback onTap;

  const _ContactStatusButton({
    required this.label,
    required this.color,
    required this.hoverColor,
    required this.height,
    required this.textTop,
    required this.onTap,
  });

  @override
  State<_ContactStatusButton> createState() => _ContactStatusButtonState();
}

class _ContactStatusButtonState extends State<_ContactStatusButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: widget.height,
          color: _hovered ? widget.hoverColor : Colors.transparent,
          alignment: Alignment.topCenter,
          padding: EdgeInsets.only(top: widget.textTop),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: widget.color,
            ),
          ),
        ),
      ),
    );
  }
}

class _FallbackComposeButton extends StatefulWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  final double height;

  const _FallbackComposeButton({
    required this.label,
    required this.color,
    required this.onTap,
    this.height = 46,
  });

  @override
  State<_FallbackComposeButton> createState() => _FallbackComposeButtonState();
}

class _FallbackComposeButtonState extends State<_FallbackComposeButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212b) : const Color(0xFFffffff);
    final hoverColor = isDark ? const Color(0xFF202b36) : const Color(0xFFF1F1F1);
    return Container(
      color: _hovered ? hoverColor : bgColor,
      height: widget.height,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: widget.color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Spec §7.1: Channel compose bar with MUTE/UNMUTE + DISCUSS buttons.
/// Replaces the normal compose area for broadcast channels where users can't post.
class _ChannelComposeBar extends StatelessWidget {
  final ChatInfo chat;
  final ChatState chatState;
  final String linkedChatId;

  const _ChannelComposeBar({
    required this.chat,
    required this.chatState,
    required this.linkedChatId,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = isDark
        ? const Color(0xFF6ab3f3)
        : const Color(0xFF168acd);

    if (linkedChatId.isNotEmpty) {
      return Row(
        children: [
          Expanded(
            child: _FallbackComposeButton(
              label: chat.isMuted ? 'UNMUTE' : 'MUTE',
              color: accentColor,
              onTap: () => chatState.muteChat(
                  chat.accountId, chat.chatId, !chat.isMuted),
            ),
          ),
          Expanded(
            child: _FallbackComposeButton(
              label: 'DISCUSS',
              color: accentColor,
              onTap: () => chatState.openChatById(linkedChatId),
            ),
          ),
        ],
      );
    }
    return _FallbackComposeButton(
      label: chat.isMuted ? 'UNMUTE' : 'MUTE',
      color: accentColor,
      onTap: () =>
          chatState.muteChat(chat.accountId, chat.chatId, !chat.isMuted),
    );
  }
}

/// Selection action bar replacing the top bar during multi-select mode.
/// In scheduled view (spec §4.7), shows "SEND NOW" + "DELETE" + "CLEAR"
/// instead of the normal "FORWARD" + "COPY" + "DELETE" + "CLEAR".
class _SelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  final VoidCallback onCopy;
  final VoidCallback onForward;
  final VoidCallback? onDownloadFiles;

  final bool isScheduledView;
  final VoidCallback? onSendNow;

  final ForwardDragData? forwardDragData;
  final bool hideDivider;
  final bool hasDownloadableMedia;

  const _SelectionBar({
    required this.count,
    required this.onCancel,
    required this.onDelete,
    required this.onCopy,
    required this.onForward,
    this.onDownloadFiles,
    this.isScheduledView = false,
    this.onSendNow,
    this.forwardDragData,
    this.hideDivider = false,
    this.hasDownloadableMedia = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Spec §4.1: match top bar colors in selection mode.
    final topBarBg = isDark ? const Color(0xFF17212b) : Colors.white;
    final shadowFg = isDark ? const Color(0x5604080e) : const Color(0x18000000);

    // Spec §4.7: defaultActiveButton — blue pill RoundButton, white text.
    // Corner radii: 8px outer ends, 4px small inner ends (segmented pill).
    const largeR = Radius.circular(8);
    const smallR = Radius.circular(4);
    final basePillStyle = TextButton.styleFrom(
      backgroundColor: const Color(0xFF40A7E3), // activeButtonBg
      foregroundColor: Colors.white, // activeButtonFg
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
    // First button: large left corners, small right corners.
    final firstPillStyle = basePillStyle.copyWith(
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(
        borderRadius: const BorderRadius.only(
          topLeft: largeR, bottomLeft: largeR,
          topRight: smallR, bottomRight: smallR,
        ),
      )),
    );
    // Middle button: all small corners.
    final middlePillStyle = basePillStyle.copyWith(
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(
        borderRadius: BorderRadius.all(smallR),
      )),
    );
    // Last button: small left corners, large right corners.
    final lastPillStyle = basePillStyle.copyWith(
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(
        borderRadius: const BorderRadius.only(
          topLeft: smallR, bottomLeft: smallR,
          topRight: largeR, bottomRight: largeR,
        ),
      )),
    );

    // Spec §4.7: In scheduled view, show "SEND NOW" + "DELETE" only.
    final List<Widget> actionButtons;

    if (isScheduledView) {
      actionButtons = [
        Expanded(
          child: TextButton(
            onPressed: onSendNow,
            style: firstPillStyle,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Flexible(child: Text('SEND NOW', overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 4),
                _AnimatedCountBadge(count: count),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextButton(
            onPressed: onDelete,
            style: lastPillStyle,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Flexible(child: Text('DELETE', overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 4),
                _AnimatedCountBadge(count: count),
              ],
            ),
          ),
        ),
      ];
    } else {
      Widget forwardButton = TextButton(
        onPressed: onForward,
        style: firstPillStyle,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Flexible(child: Text('FORWARD', overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 4),
            _AnimatedCountBadge(count: count),
          ],
        ),
      );

      if (forwardDragData != null) {
        forwardButton = Draggable<ForwardDragData>(
          data: forwardDragData,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          feedback: Material(
            elevation: 4,
            borderRadius: const BorderRadius.only(
              topLeft: largeR, bottomLeft: largeR,
              topRight: smallR, bottomRight: smallR,
            ),
            color: isDark ? const Color(0xFF2b5278) : const Color(0xFF419fd9),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.forward, color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    '$count message${count > 1 ? 's' : ''}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ),
          child: forwardButton,
        );
      }

      actionButtons = [
        Expanded(child: forwardButton),
        const SizedBox(width: 10),
        Expanded(
          child: TextButton(
            onPressed: onDelete,
            style: lastPillStyle,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Flexible(child: Text('DELETE', overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 4),
                _AnimatedCountBadge(count: count),
              ],
            ),
          ),
        ),
      ];
    }

    return Container(
      height: 54, // topBarHeight per spec §4.1
      decoration: BoxDecoration(
        color: topBarBg,
        // Spec §4.1: divider hidden during one-column slide transitions.
        border: hideDivider ? null : Border(
          bottom: BorderSide(color: shadowFg, width: 1),
        ),
      ),
      padding: const EdgeInsets.only(left: 8, right: 10),
      child: Row(
        children: [
          const SizedBox(width: 8),
          ...actionButtons,
          const SizedBox(width: 6),
          _SelectionOverflowMenu(
            isDark: isDark,
            onCopy: onCopy,
            onDownloadFiles: hasDownloadableMedia ? onDownloadFiles : null,
          ),
          const Spacer(),
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: isDark
                  ? const Color(0xFF6AB2F2)
                  : const Color(0xFF168ACD),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              shape: const StadiumBorder(),
            ),
            child: const Text('CLEAR'),
          ),
        ],
      ),
    );
  }
}

/// Spec §4.7: Animated count badge for selection bar buttons.
/// Mimics tdesktop `setNumbersText` — count slides vertically when changing.
class _AnimatedCountBadge extends StatelessWidget {
  final int count;
  const _AnimatedCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 120),
      transitionBuilder: (child, animation) {
        return ClipRect(
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1.0),
              end: Offset.zero,
            ).animate(CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            )),
            child: child,
          ),
        );
      },
      child: Text(
        '$count',
        key: ValueKey<int>(count),
      ),
    );
  }
}

class _SelectionOverflowMenu extends StatelessWidget {
  final bool isDark;
  final VoidCallback onCopy;
  final VoidCallback? onDownloadFiles;

  const _SelectionOverflowMenu({
    required this.isDark,
    required this.onCopy,
    this.onDownloadFiles,
  });

  static void _showOverflowMenu(BuildContext btnCtx, {
    required VoidCallback onCopy,
    VoidCallback? onDownloadFiles,
  }) {
    final RenderBox button = btnCtx.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(btnCtx).overlay!.context.findRenderObject() as RenderBox;
    final Offset pos = button.localToGlobal(Offset.zero, ancestor: overlay);
    final items = <PopupMenuEntry<String>>[
      const PopupMenuItem(
        value: 'copy',
        child: Row(
          children: [
            Icon(Icons.copy, size: 20),
            SizedBox(width: 12),
            Text('Copy Selected Text'),
          ],
        ),
      ),
      if (onDownloadFiles != null)
        const PopupMenuItem(
          value: 'download',
          child: Row(
            children: [
              Icon(Icons.download, size: 20),
              SizedBox(width: 12),
              Text('Download Files'),
            ],
          ),
        ),
    ];
    showMenu<String>(
      context: btnCtx,
      position: RelativeRect.fromLTRB(
        pos.dx, pos.dy + button.size.height,
        pos.dx + button.size.width, pos.dy + button.size.height,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: items,
    ).then((value) {
      if (value == 'copy') onCopy();
      if (value == 'download') onDownloadFiles?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = isDark
        ? const Color(0xFF6AB2F2)
        : const Color(0xFF168ACD);
    final windowBgOver = isDark
        ? const Color(0xFF202b36)
        : const Color(0xFFf1f1f1);

    return SizedBox(
      width: 44,
      height: 54,
      child: Center(
        child: Builder(
          builder: (btnCtx) => IconButton(
            icon: Icon(Icons.more_vert, size: 20),
            onPressed: () => _showOverflowMenu(btnCtx,
              onCopy: onCopy,
              onDownloadFiles: onDownloadFiles,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            style: ButtonStyle(
              fixedSize: const WidgetStatePropertyAll(Size(40, 40)),
              minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
              maximumSize: const WidgetStatePropertyAll(Size(40, 40)),
              shape: const WidgetStatePropertyAll(CircleBorder()),
              iconColor: WidgetStatePropertyAll(iconColor),
              overlayColor: WidgetStatePropertyAll(windowBgOver),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupCallBar extends StatelessWidget {
  final GroupCallInfo groupCall;
  final VoidCallback? onJoin;

  const _GroupCallBar({
    required this.groupCall,
    this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final barBg = isDark ? const Color(0xFF1B2734) : const Color(0xFFFFFFFF);
    final shadowColor = isDark ? const Color(0x5604080E) : const Color(0x18000000);
    final textColor = isDark ? const Color(0xFFE1E3E6) : const Color(0xFF222222);
    final subtitleColor = isDark ? const Color(0xFF7E8B99) : const Color(0xFF999999);
    final accentGreen = const Color(0xFF4DC920);
    final joinBg = const Color(0xFF40A7E3);

    final participants = groupCall.participants;
    // Show up to 3 overlapping userpics.
    final visibleParticipants = participants.take(3).toList();

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: barBg,
        border: Border(bottom: BorderSide(color: shadowColor, width: 1)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13),
        child: Row(
          children: [
            // Overlapping participant userpics.
            if (visibleParticipants.isNotEmpty) ...[
              SizedBox(
                width: 28.0 + (visibleParticipants.length - 1) * 20.0,
                height: 28,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var i = 0; i < visibleParticipants.length; i++)
                      Positioned(
                        left: i * 20.0,
                        child: _GroupCallUserpic(
                          participant: visibleParticipants[i],
                          isSpeaking: visibleParticipants[i].isSpeaking,
                          accentGreen: accentGreen,
                          isDark: isDark,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
            ] else ...[
              // No participants yet — show a phone icon.
              Icon(Icons.phone_in_talk, size: 22, color: joinBg),
              const SizedBox(width: 10),
            ],
            // Title and participant count.
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    groupCall.title.isNotEmpty ? groupCall.title : 'Voice Chat',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    groupCall.participantsCount > 0
                        ? '${groupCall.participantsCount} participant${groupCall.participantsCount == 1 ? '' : 's'}'
                        : 'No participants',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12,
                      color: subtitleColor,
                    ),
                  ),
                ],
              ),
            ),
            // "Join" button.
            Material(
              color: joinBg,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onJoin,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  child: Text(
                    'Join',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Circular userpic for a group call participant with optional green speaking ring.
class _GroupCallUserpic extends StatelessWidget {
  final GroupCallParticipant participant;
  final bool isSpeaking;
  final Color accentGreen;
  final bool isDark;

  const _GroupCallUserpic({
    required this.participant,
    required this.isSpeaking,
    required this.accentGreen,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    const double size = 28;
    const double borderWidth = 2;
    // Color by userId hash for deterministic avatar bg.
    final hue = (participant.userId.hashCode % 360).abs().toDouble();
    final avatarBg = HSLColor.fromAHSL(1, hue, 0.5, 0.45).toColor();
    final initials = participant.displayName.isNotEmpty
        ? participant.displayName[0].toUpperCase()
        : '?';

    final avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: avatarBg,
        border: isSpeaking
            ? Border.all(color: accentGreen, width: borderWidth)
            : Border.all(
                color: isDark ? const Color(0xFF17212B) : Colors.white,
                width: borderWidth,
              ),
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );

    return avatar;
  }
}

/// Pinned message bar below the top bar.
/// Shows the most recent pinned message with a pin icon.
class _PinnedBar extends StatelessWidget {
  final CachedMessage pinned;
  final int pinnedCount;
  final int pinnedIndex;
  final VoidCallback? onTap;
  final VoidCallback? onClose;
  final VoidCallback? onShowAll;

  const _PinnedBar({
    required this.pinned,
    this.pinnedCount = 1,
    this.pinnedIndex = 0,
    this.onTap,
    this.onClose,
    this.onShowAll,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Spec §4.4: historyPinnedBg. Day=#ffffff, night=#1b2734.
    final pinnedBg = isDark ? const Color(0xFF1b2734) : Colors.white;
    // Spec §4.4: bottom divider same as top bar shadow.
    final shadowFg = isDark ? const Color(0x5604080e) : const Color(0x18000000);
    // Spec §4.4: left accent stripe in msgInReplyBarColor.
    // Day = activeLineFg (~#168acd). Night ≈ #429bdb.
    final accentColor = isDark ? const Color(0xFF429bdb) : const Color(0xFF168acd);
    // Spec §4.4: title color = windowActiveTextFg (blue accent).
    final titleColor = isDark ? const Color(0xFF6ab3f3) : const Color(0xFF168acd);
    // Spec §4.4: preview text = historyComposeAreaFg.
    final previewColor = isDark ? const Color(0xFFdcdcdc) : const Color(0xFF000000);

    return Container(
      height: 49, // historyReplyHeight
      decoration: BoxDecoration(
        color: pinnedBg,
        border: Border(
          bottom: BorderSide(color: shadowFg, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Content area — tapping navigates to pinned message.
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Row(
                children: [
                  const SizedBox(width: 1), // msgReplyBarPos offset x=1px
                  // Spec §4.4: left accent stripe — 2px wide, 36px tall.
                  Container(width: 2, height: 36, color: accentColor),
                  const SizedBox(width: 10), // msgReplyBarSkip
                  // Spec §4.4: content change animation 160ms.
                  // Wraps thumbnail + title/preview so entire content
                  // animates together when the pinned message changes.
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) {
                        final slideIn = Tween<Offset>(
                          begin: const Offset(0, 0.5),
                          end: Offset.zero,
                        ).animate(animation);
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: slideIn,
                            child: child,
                          ),
                        );
                      },
                      child: Row(
                        key: ValueKey(pinned.msgId),
                        children: [
                          if (pinned.mediaThumbB64.isNotEmpty) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: _buildPinnedThumb(),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _pinnedTitle(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: titleColor,
                                  ),
                                ),
                                Text(
                                  pinned.contentText.isNotEmpty
                                      ? pinned.contentText
                                      : (pinned.senderName.isNotEmpty
                                          ? '${pinned.senderName}: [media]'
                                          : '[media]'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: previewColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Spec §4.4: multi-pin "Show All" button — same size as close,
          // icon pinned_show_all, only shown when pinnedCount > 1.
          if (pinnedCount > 1)
            _PinnedBarShowAllButton(onShowAll: onShowAll),
          // Spec §4.4: close/unpin button — 49×49 hit-area, 40px ripple
          // at (4,4), box_button_close icon in historyReplyCancelFg.
          _PinnedBarCloseButton(onClose: onClose),
        ],
      ),
    );
  }

  String _pinnedTitle() {
    if (pinnedCount <= 1) return 'Pinned Message';
    if (pinnedCount == 2 && pinnedIndex > 0) {
      return 'Previous Pinned Message';
    }
    return 'Pinned Message #${pinnedCount - pinnedIndex}';
  }

  Widget _buildPinnedThumb() {
    try {
      final bytes = base64Decode(pinned.mediaThumbB64);
      return Image.memory(
        bytes,
        width: 32,
        height: 32,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _thumbPlaceholder(),
      );
    } catch (_) {
      return _thumbPlaceholder();
    }
  }

  Widget _thumbPlaceholder() {
    return Container(
      width: 32,
      height: 32,
      color: Colors.grey.shade300,
      child: const Icon(Icons.image, size: 16, color: Colors.grey),
    );
  }
}

/// Spec §4.4: historyPinnedShowAll — same 49×49 hit-area, 40px circular
/// ripple at (4,4), `pinned_show_all` icon. Same colors as close button.
/// Only shown when multiple pinned messages exist.
class _PinnedBarShowAllButton extends StatelessWidget {
  final VoidCallback? onShowAll;
  const _PinnedBarShowAllButton({this.onShowAll});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cancelFg = isDark ? const Color(0xFF6c7883) : const Color(0xFF999999);
    final cancelFgOver = isDark ? const Color(0xFFa8a8a8) : const Color(0xFF7c7c7c);

    return SizedBox(
      width: 49,
      height: 49,
      child: Stack(
        children: [
          Positioned(
            left: 4,
            top: 4,
            child: ClipOval(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onShowAll,
                  splashColor: (isDark
                      ? const Color(0xFF3a4654)
                      : const Color(0xFFf1f1f1)),
                  highlightColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: _HoverColorIcon(
                      icon: Icons.view_list,
                      size: 18,
                      color: cancelFg,
                      hoverColor: cancelFgOver,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Spec §4.4: historyReplyCancel — 49×49 hit-area, 40px circular ripple
/// at (4,4), `box_button_close` icon. Colors: historyReplyCancelFg resting,
/// historyReplyCancelFgOver on hover.
class _PinnedBarCloseButton extends StatelessWidget {
  final VoidCallback? onClose;
  const _PinnedBarCloseButton({this.onClose});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // historyReplyCancelFg: day #999999 (placeholderFg), night #6c7883.
    final cancelFg = isDark ? const Color(0xFF6c7883) : const Color(0xFF999999);
    // historyReplyCancelFgOver: day #7c7c7c, night #a8a8a8.
    final cancelFgOver = isDark ? const Color(0xFFa8a8a8) : const Color(0xFF7c7c7c);

    return SizedBox(
      width: 49,
      height: 49,
      child: Stack(
        children: [
          // Ripple circle: 40px at offset (4,4) inside the 49×49 area.
          Positioned(
            left: 4,
            top: 4,
            child: ClipOval(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onClose,
                  splashColor: (isDark
                      ? const Color(0xFF3a4654)
                      : const Color(0xFFf1f1f1)),
                  highlightColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: _HoverColorIcon(
                      icon: Icons.close,
                      size: 18,
                      color: cancelFg,
                      hoverColor: cancelFgOver,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Icon that changes color on hover (no surrounding InkWell needed —
/// used inside the ripple ClipOval above).
class _HoverColorIcon extends StatefulWidget {
  final IconData icon;
  final double size;
  final Color color;
  final Color hoverColor;
  const _HoverColorIcon({required this.icon, required this.size, required this.color, required this.hoverColor});
  @override
  State<_HoverColorIcon> createState() => _HoverColorIconState();
}

class _HoverColorIconState extends State<_HoverColorIcon> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Center(
        child: Icon(
          widget.icon,
          size: widget.size,
          color: _hovered ? widget.hoverColor : widget.color,
        ),
      ),
    );
  }
}

/// Scroll-to-bottom FAB (spec §5: JumpDownButton).
/// Spec §5: JumpDownButton — 52×62px hit-area, 42px visible disc,
/// two-layer icon (shadow disc + arrow), muted unread badge 4px above.
class _ScrollToBottomFab extends StatefulWidget {
  final int unreadCount;
  final VoidCallback onTap;

  const _ScrollToBottomFab({required this.unreadCount, required this.onTap});

  @override
  State<_ScrollToBottomFab> createState() => _ScrollToBottomFabState();
}

class _ScrollToBottomFabState extends State<_ScrollToBottomFab> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Spec colors.
    final discBg = isDark ? const Color(0xFF1D2B3A) : const Color(0xFFFFFFFF);
    final discBgOver = isDark ? const Color(0xFF243446) : const Color(0xFFF1F1F1);
    final arrowColor = isDark ? const Color(0xFFADB4BA) : const Color(0xFF999999);
    const shadowColor = Color(0x40000000); // #00000040 = 25% black
    // Badge: muted palette.
    final badgeBg = isDark ? const Color(0xFF3E546A) : const Color(0xFFBBBBBB);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 52,
          height: 62 + (widget.unreadCount > 0 ? 26 : 0), // badge adds 22+4 above
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Badge: 4px above the 62px button area.
              if (widget.unreadCount > 0)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        widget.unreadCount > 9999
                            ? '9999+'
                            : widget.unreadCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                ),
              // Button area: 52×62, disc at (5,15) within it.
              Positioned(
                bottom: 0,
                left: 0,
                child: SizedBox(
                  width: 52,
                  height: 62,
                  child: Stack(
                    children: [
                      // Shadow disc (slightly offset down for drop shadow).
                      Positioned(
                        left: 5,
                        top: 17, // 15 + 2px shadow offset
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: shadowColor,
                          ),
                        ),
                      ),
                      // Main disc.
                      Positioned(
                        left: 5,
                        top: 15,
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _hovered ? discBgOver : discBg,
                          ),
                        ),
                      ),
                      // Arrow icon centered on disc.
                      Positioned(
                        left: 5,
                        top: 15,
                        child: SizedBox(
                          width: 42,
                          height: 42,
                          child: Icon(
                            Icons.arrow_downward,
                            size: 20,
                            color: arrowColor,
                          ),
                        ),
                      ),
                    ],
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

/// Corner button for Mentions/Reactions/PollVotes (spec §5 / §49.17).
/// Same 52×62px hit-area and 42px visible disc as JumpDownButton, but
/// with a custom icon and count badge on the disc itself.
class _CornerButton extends StatefulWidget {
  final IconData icon;
  final int count;
  final VoidCallback onTap;

  const _CornerButton({
    required this.icon,
    required this.count,
    required this.onTap,
  });

  @override
  State<_CornerButton> createState() => _CornerButtonState();
}

class _CornerButtonState extends State<_CornerButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final discBg = isDark ? const Color(0xFF1D2B3A) : const Color(0xFFFFFFFF);
    final discBgOver = isDark ? const Color(0xFF243446) : const Color(0xFFF1F1F1);
    final iconColor = isDark ? const Color(0xFFADB4BA) : const Color(0xFF999999);
    const shadowColor = Color(0x40000000);
    // Badge uses the same muted palette as JumpDownButton.
    final badgeBg = isDark ? const Color(0xFF3E546A) : const Color(0xFFBBBBBB);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 52,
          height: 62 + (widget.count > 0 ? 26 : 0),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Badge: 4px above the 62px button area.
              if (widget.count > 0)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        widget.count > 9999
                            ? '9999+'
                            : widget.count.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                ),
              // Button area: 52×62, disc at (5,15).
              Positioned(
                bottom: 0,
                left: 0,
                child: SizedBox(
                  width: 52,
                  height: 62,
                  child: Stack(
                    children: [
                      // Shadow disc.
                      Positioned(
                        left: 5,
                        top: 17,
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: shadowColor,
                          ),
                        ),
                      ),
                      // Main disc.
                      Positioned(
                        left: 5,
                        top: 15,
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _hovered ? discBgOver : discBg,
                          ),
                        ),
                      ),
                      // Icon centered on disc.
                      Positioned(
                        left: 5,
                        top: 15,
                        child: SizedBox(
                          width: 42,
                          height: 42,
                          child: Icon(
                            widget.icon,
                            size: 20,
                            color: iconColor,
                          ),
                        ),
                      ),
                    ],
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

// ── Rich text editing controller (spec §7 / §41.4) ──

enum FormatType { bold, italic, underline, strike, code, spoiler, blockquote }

class ComposeEntity {
  int offset;
  int length;
  final FormatType type;

  ComposeEntity({required this.offset, required this.length, required this.type});

  Map<String, dynamic> toJson() {
    final typeStr = switch (type) {
      FormatType.bold => 'bold',
      FormatType.italic => 'italic',
      FormatType.underline => 'underline',
      FormatType.strike => 'strike',
      FormatType.code => 'code',
      FormatType.spoiler => 'spoiler',
      FormatType.blockquote => 'blockquote',
    };
    return {'type': typeStr, 'offset': offset, 'length': length};
  }
}

class RichTextEditingController extends TextEditingController {
  final List<ComposeEntity> entities = [];

  String _prevText = '';

  RichTextEditingController() {
    addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final newText = text;
    if (newText == _prevText) return;

    final oldLen = _prevText.length;
    final newLen = newText.length;

    if (newLen == 0) {
      entities.clear();
      _prevText = newText;
      return;
    }

    final minLen = oldLen < newLen ? oldLen : newLen;
    var commonPrefix = 0;
    while (commonPrefix < minLen &&
        _prevText.codeUnitAt(commonPrefix) == newText.codeUnitAt(commonPrefix)) {
      commonPrefix++;
    }
    final changePos = commonPrefix;
    final delta = newLen - oldLen;

    for (var i = entities.length - 1; i >= 0; i--) {
      final e = entities[i];
      final eEnd = e.offset + e.length;

      if (delta > 0) {
        if (changePos <= e.offset) {
          e.offset += delta;
        } else if (changePos < eEnd) {
          e.length += delta;
        }
      } else {
        final delStart = changePos;
        final delEnd = changePos - delta;

        if (delEnd <= e.offset) {
          e.offset += delta;
        } else if (delStart >= eEnd) {
          // no change
        } else if (delStart <= e.offset && delEnd >= eEnd) {
          entities.removeAt(i);
          continue;
        } else if (delStart <= e.offset) {
          final removed = delEnd - e.offset;
          e.offset = delStart;
          e.length -= removed;
        } else if (delEnd >= eEnd) {
          e.length = delStart - e.offset;
        } else {
          e.length += delta;
        }
      }

      if (i < entities.length && entities[i].length <= 0) {
        entities.removeAt(i);
      }
    }

    _prevText = newText;
  }

  void toggleFormat(FormatType type) {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) return;

    final start = sel.start;
    final end = sel.end;
    final length = end - start;

    final existing = entities.where((e) =>
      e.type == type && e.offset == start && e.length == length).toList();

    if (existing.isNotEmpty) {
      for (final e in existing) {
        entities.remove(e);
      }
    } else {
      entities.add(ComposeEntity(offset: start, length: length, type: type));
    }
    notifyListeners();
  }

  void clearFormatting() {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) return;
    final start = sel.start;
    final end = sel.end;
    entities.removeWhere((e) =>
      e.offset < end && e.offset + e.length > start);
    notifyListeners();
  }

  bool hasFormat(FormatType type) {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) return false;
    final start = sel.start;
    final end = sel.end;
    return entities.any((e) =>
      e.type == type && e.offset <= start && e.offset + e.length >= end);
  }

  String get entitiesJson {
    if (entities.isEmpty) return '';
    return jsonEncode(entities.map((e) => e.toJson()).toList());
  }

  @override
  void clear() {
    entities.clear();
    _prevText = '';
    super.clear();
  }

  @override
  set text(String newText) {
    entities.clear();
    _prevText = newText;
    super.text = newText;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (entities.isEmpty) {
      return super.buildTextSpan(
        context: context, style: style, withComposing: withComposing);
    }

    final t = text;
    final sorted = List<ComposeEntity>.from(entities)
      ..sort((a, b) => a.offset.compareTo(b.offset));

    final spans = <InlineSpan>[];
    var cursor = 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    for (final entity in sorted) {
      final eStart = entity.offset.clamp(0, t.length);
      final eEnd = (entity.offset + entity.length).clamp(0, t.length);
      if (eEnd <= eStart) continue;

      if (cursor < eStart) {
        spans.add(TextSpan(text: t.substring(cursor, eStart)));
      }

      final entityText = t.substring(eStart, eEnd);
      final entityStyle = switch (entity.type) {
        FormatType.bold => const TextStyle(fontWeight: FontWeight.bold),
        FormatType.italic => const TextStyle(fontStyle: FontStyle.italic),
        FormatType.underline => const TextStyle(decoration: TextDecoration.underline),
        FormatType.strike => const TextStyle(decoration: TextDecoration.lineThrough),
        FormatType.code => TextStyle(
          fontFamily: 'monospace',
          backgroundColor: isDark ? const Color(0xFF1E2A36) : const Color(0xFFF0F0F0),
        ),
        FormatType.spoiler => TextStyle(
          backgroundColor: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFD0D0D0),
        ),
        FormatType.blockquote => TextStyle(
          color: isDark ? const Color(0xFF65bdf3) : const Color(0xFF168acd),
          fontStyle: FontStyle.italic,
        ),
      };
      spans.add(TextSpan(text: entityText, style: entityStyle));
      cursor = eEnd;
    }

    if (cursor < t.length) {
      spans.add(TextSpan(text: t.substring(cursor)));
    }

    return TextSpan(style: style, children: spans);
  }
}

const _kEmoticons = <String, String>{
  '>:-(': '😠',
  '>:-)': '😈',
  'O:-)': '😇',
  ":'-(": '😢',
  ':-)': '😊',
  ':-(': '😞',
  ':-D': '😁',
  ':-P': '😛',
  ':-p': '😛',
  ';-P': '😜',
  ';-p': '😜',
  ':-O': '😮',
  ':-o': '😮',
  '8-)': '😎',
  'B-)': '😎',
  ':-*': '😘',
  ':-|': '😐',
  ';-)': '😉',
  '>:(': '😠',
  '>:)': '😈',
  'O:)': '😇',
  ":'(": '😢',
  ':)': '🙂',
  ':(': '😞',
  ':D': '😀',
  ':P': '😛',
  ':p': '😛',
  ';P': '😜',
  ';p': '😜',
  ':O': '😮',
  ':o': '😮',
  ':*': '😘',
  ':|': '😐',
  ';)': '😉',
  '(:': '🙃',
  '<3': '❤️',
};

final _kEmoticonsSorted = () {
  final list = _kEmoticons.entries.toList();
  list.sort((a, b) => b.key.length.compareTo(a.key.length));
  return list;
}();

/// Compose area at bottom. Spec §7 + §24.6.
enum SendButtonType { send, schedule, save, record, round, cancel, slowmode, editPrice }

enum AutocompleteType { mention, hashtag, command, emoji, stickerSuggestion }

class AutocompleteQuery {
  final AutocompleteType type;
  final String query;
  final int triggerOffset;
  const AutocompleteQuery(this.type, this.query, this.triggerOffset);
}

class _ComposeArea extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onSendSilent;
  final ValueChanged<DateTime>? onSendScheduled;
  final VoidCallback? onSendWhenOnline;
  final ValueChanged<String> onDraftChanged;
  final bool isEditing;
  final bool isForwarding;
  final ChatType chatType;
  final bool isSelfChat;
  /// Called when Up is pressed with empty field + no edit/reply active.
  /// Returns true if edit mode was entered (so the event is consumed).
  final bool Function()? onEditLast;
  /// Called on Ctrl+Up (direction=+1) / Ctrl+Down (direction=-1) to cycle
  /// the reply target (spec §24.6 lines 2982-2983). Returns true when the
  /// event was consumed.
  final bool Function(int direction)? onCycleReply;
  final ValueChanged<List<String>>? onLinksDetected;
  final ValueChanged<List<String>>? onFilesSelected;
  final bool voiceRestricted;
  final bool videoRestricted;
  final int slowmodeSeconds;
  final int slowmodeNextSendDate;
  final int starsToSend;
  final ValueChanged<AutocompleteQuery?>? onAutocompleteQuery;
  final bool autocompleteActive;
  final VoidCallback? onAutocompleteUp;
  final VoidCallback? onAutocompleteDown;
  final VoidCallback? onAutocompletePick;
  final List<SendAsPeerInfo> sendAsPeers;
  final String? selectedSendAsPeerId;
  final ValueChanged<String>? onSendAsChanged;
  final int scheduledCount;
  final VoidCallback? onScheduledPressed;
  final int ttlPeriod;
  final ValueChanged<int>? onTtlChanged;
  final bool isBot;
  final VoidCallback? onEmojiToggle;
  final bool emojiPanelVisible;
  final VoidCallback? onEscape;
  final ValueChanged<bool>? onScrollPage;
  final String sendBy;

  const _ComposeArea({
    required this.controller,
    required this.onSend,
    this.onSendSilent,
    this.onSendScheduled,
    this.onSendWhenOnline,
    required this.onDraftChanged,
    this.isEditing = false,
    this.isForwarding = false,
    this.chatType = ChatType.dm,
    this.isSelfChat = false,
    this.onEditLast,
    this.onCycleReply,
    this.onLinksDetected,
    this.onFilesSelected,
    this.voiceRestricted = false,
    this.videoRestricted = false,
    this.slowmodeSeconds = 0,
    this.slowmodeNextSendDate = 0,
    this.starsToSend = 0,
    this.onAutocompleteQuery,
    this.autocompleteActive = false,
    this.onAutocompleteUp,
    this.onAutocompleteDown,
    this.onAutocompletePick,
    this.sendAsPeers = const [],
    this.selectedSendAsPeerId,
    this.onSendAsChanged,
    this.scheduledCount = 0,
    this.onScheduledPressed,
    this.ttlPeriod = 0,
    this.onTtlChanged,
    this.isBot = false,
    this.onEmojiToggle,
    this.emojiPanelVisible = false,
    this.onEscape,
    this.onScrollPage,
    this.sendBy = 'enter',
  });

  @override
  State<_ComposeArea> createState() => _ComposeAreaState();
}

class _ComposeAreaState extends State<_ComposeArea>
    with TickerProviderStateMixin {
  static const int _kMaxMessageLength = 4096;

  static final _urlRegex = RegExp(
    r'(?:https?://|www\.)'
    r'[^\s<>\[\](){}"'
    "'"
    r']+',
    caseSensitive: false,
  );

  late final FocusNode _focusNode;
  late final ScrollController _scrollController;
  bool _showTopFade = false;
  bool _showBottomFade = false;
  Timer? _linkTimer;
  int _prevTextLength = 0;
  List<String> _detectedLinks = const [];
  bool _hasText = false;
  int _charRemaining = _kMaxMessageLength;
  int _consecutiveEnters = 0;
  Timer? _slowmodeTimer;
  int _slowmodeSecondsLeft = 0;
  bool _isRecording = false;
  bool _isVideoRound = false;
  DateTime? _recordingStart;
  Timer? _recordingTimer;
  Duration _recordingDuration = Duration.zero;
  bool _isRecordingLocked = false;
  double _lockDragStartY = 0;
  double _lockDragStartX = 0;
  int _trackingPointerId = -1;
  double _lockProgress = 0.0;
  double _slideLeftOffset = 0.0;
  bool _ttlArmed = false;
  bool _silentMode = false;
  late AnimationController _lockShowController;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(onKeyEvent: _onKey);
    _scrollController = ScrollController()..addListener(_updateFades);
    widget.controller.addListener(_scheduleUpdateFades);
    widget.controller.addListener(_onTextLengthChanged);
    _prevTextLength = widget.controller.text.length;
    _hasText = widget.controller.text.isNotEmpty;
    _charRemaining = _kMaxMessageLength - widget.controller.text.length;
    _startSlowmodeTimer();
    _lockShowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
  }

  @override
  void didUpdateWidget(covariant _ComposeArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slowmodeNextSendDate != widget.slowmodeNextSendDate ||
        oldWidget.slowmodeSeconds != widget.slowmodeSeconds) {
      _startSlowmodeTimer();
    }
  }

  void _startSlowmodeTimer() {
    _slowmodeTimer?.cancel();
    _slowmodeTimer = null;
    _slowmodeSecondsLeft = _computeSlowmodeLeft();
    if (_slowmodeSecondsLeft > 0) {
      _slowmodeTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        final left = _computeSlowmodeLeft();
        if (left != _slowmodeSecondsLeft) {
          setState(() => _slowmodeSecondsLeft = left);
        }
        if (left <= 0) {
          _slowmodeTimer?.cancel();
          _slowmodeTimer = null;
        }
      });
    }
  }

  int _computeSlowmodeLeft() {
    if (widget.slowmodeNextSendDate <= 0) return 0;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final left = widget.slowmodeNextSendDate - nowSec;
    return left > 0 ? left : 0;
  }

  @override
  void dispose() {
    _slowmodeTimer?.cancel();
    _linkTimer?.cancel();
    _recordingTimer?.cancel();
    _lockShowController.dispose();
    if (_trackingPointerId >= 0) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onGlobalPointerEvent);
    }
    widget.controller.removeListener(_onTextLengthChanged);
    widget.controller.removeListener(_scheduleUpdateFades);
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  static const double _lockThreshold = 80.0;
  static const double _slideCancelThreshold = 100.0;

  void _startRecording(double startY, int pointerId, {bool videoRound = false, double startX = 0}) {
    setState(() {
      _isRecording = true;
      _isVideoRound = videoRound;
      _isRecordingLocked = false;
      _recordingStart = DateTime.now();
      _recordingDuration = Duration.zero;
      _lockDragStartY = startY;
      _lockDragStartX = startX;
      _trackingPointerId = pointerId;
      _lockProgress = 0.0;
      _slideLeftOffset = 0.0;
    });
    _lockShowController.forward(from: 0.0);
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onGlobalPointerEvent);
    _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_recordingStart != null) {
        setState(() {
          _recordingDuration = DateTime.now().difference(_recordingStart!);
        });
      }
    });
  }

  void _onGlobalPointerEvent(PointerEvent event) {
    if (event.pointer != _trackingPointerId) return;
    if (_isRecordingLocked) return;
    if (event is PointerMoveEvent) {
      final dragUp = _lockDragStartY - event.position.dy;
      final progress = (dragUp / _lockThreshold).clamp(0.0, 1.0);
      final dragLeft = _lockDragStartX - event.position.dx;
      final slideOffset = dragLeft.clamp(0.0, double.infinity);
      if (slideOffset >= _slideCancelThreshold) {
        GestureBinding.instance.pointerRouter.removeGlobalRoute(_onGlobalPointerEvent);
        _trackingPointerId = -1;
        _cancelRecording();
        return;
      }
      setState(() {
        _lockProgress = progress;
        _slideLeftOffset = slideOffset;
      });
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onGlobalPointerEvent);
      _trackingPointerId = -1;
      if (_lockProgress >= 1.0) {
        setState(() => _isRecordingLocked = true);
      } else {
        _stopAndSendRecording();
      }
    }
  }

  void _stopAndSendRecording() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _lockShowController.reverse();
    setState(() {
      _isRecording = false;
      _isVideoRound = false;
      _isRecordingLocked = false;
      _recordingStart = null;
      _recordingDuration = Duration.zero;
      _lockProgress = 0.0;
      _slideLeftOffset = 0.0;
      _ttlArmed = false;
    });
  }

  void _cancelRecording() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    if (_trackingPointerId >= 0) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onGlobalPointerEvent);
      _trackingPointerId = -1;
    }
    _lockShowController.reverse();
    setState(() {
      _isRecording = false;
      _isVideoRound = false;
      _isRecordingLocked = false;
      _recordingStart = null;
      _recordingDuration = Duration.zero;
      _lockProgress = 0.0;
      _slideLeftOffset = 0.0;
      _ttlArmed = false;
    });
  }

  void _onTextLengthChanged() {
    final has = widget.controller.text.isNotEmpty;
    final remaining = _kMaxMessageLength - widget.controller.text.length;
    final counterChanged =
        (remaining <= 100 || _charRemaining <= 100) &&
        remaining != _charRemaining;
    if (has != _hasText || counterChanged) {
      setState(() {
        _hasText = has;
        _charRemaining = remaining;
      });
    } else {
      _charRemaining = remaining;
    }
  }

  SendButtonType _computeSendButtonType() {
    if (widget.isEditing) return SendButtonType.save;
    if (widget.isForwarding) return SendButtonType.send;
    if (_slowmodeSecondsLeft > 0) return SendButtonType.slowmode;
    if (!_hasText) {
      final appState = context.read<AppState>();
      return appState.recordVideoMessages
          ? SendButtonType.round
          : SendButtonType.record;
    }
    return SendButtonType.send;
  }

  static String _formatSlowmode(int seconds) {
    final clamped = seconds.clamp(0, 6000);
    final m = clamped ~/ 60;
    final s = clamped % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _scheduleUpdateFades() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateFades();
    });
  }

  void _updateFades() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final top = pos.pixels > 0.5;
    final bottom = pos.pixels < pos.maxScrollExtent - 0.5;
    if (top != _showTopFade || bottom != _showBottomFade) {
      setState(() {
        _showTopFade = top;
        _showBottomFade = bottom;
      });
    }
  }

  void _doSend() {
    if (_silentMode && widget.onSendSilent != null) {
      widget.onSendSilent!();
    } else {
      widget.onSend();
    }
  }

  void _showGiftSheet(BuildContext ctx) {
    final chatState = ctx.read<ChatState>();
    final chat = chatState.activeChat;
    if (chat == null) return;
    final engine = ctx.read<EngineService>();
    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _StarGiftSheet(
        accountId: chat.accountId,
        chatId: chat.chatId,
        peerName: chat.title,
        engine: engine,
      ),
    );
  }

  bool _shouldSubmit(LogicalKeyboardKey key, bool ctrl, bool shift) {
    if (key != LogicalKeyboardKey.enter) return false;
    if (ctrl && shift) return true;
    final mode = widget.sendBy;
    if (ctrl && mode != 'enter') return true;
    if (!ctrl && !shift && mode == 'enter') return true;
    return false;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isEnter = event.logicalKey == LogicalKeyboardKey.enter;
    if (!isEnter) _consecutiveEnters = 0;

    if (widget.autocompleteActive) {
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        widget.onAutocompleteUp?.call();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        widget.onAutocompleteDown?.call();
        return KeyEventResult.handled;
      }
      if (isEnter || event.logicalKey == LogicalKeyboardKey.tab) {
        widget.onAutocompletePick?.call();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _dismissAutocomplete();
        return KeyEventResult.handled;
      }
    }

    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final alt = HardwareKeyboard.instance.isAltPressed;
    final meta = HardwareKeyboard.instance.isMetaPressed;
    final richCtrl = widget.controller is RichTextEditingController
        ? widget.controller as RichTextEditingController
        : null;

    // Ctrl+Shift+N → clear formatting (spec §24.8)
    if (richCtrl != null && ctrl && shift &&
        event.logicalKey == LogicalKeyboardKey.keyN) {
      richCtrl.clearFormatting();
      return KeyEventResult.handled;
    }

    if (richCtrl != null && ctrl) {
      FormatType? fmt;
      if (!shift) {
        fmt = switch (event.logicalKey) {
          LogicalKeyboardKey.keyB => FormatType.bold,
          LogicalKeyboardKey.keyI => FormatType.italic,
          LogicalKeyboardKey.keyU => FormatType.underline,
          _ => null,
        };
      } else {
        fmt = switch (event.logicalKey) {
          LogicalKeyboardKey.keyX => FormatType.strike,
          LogicalKeyboardKey.keyM => FormatType.code,
          LogicalKeyboardKey.keyP => FormatType.spoiler,
          LogicalKeyboardKey.period => FormatType.blockquote,
          _ => null,
        };
      }
      if (fmt != null) {
        richCtrl.toggleFormat(fmt);
        return KeyEventResult.handled;
      }
    }

    // Ctrl+Shift+V → plain paste (spec §24.6)
    if (ctrl && shift && event.logicalKey == LogicalKeyboardKey.keyV) {
      _pastePlainText();
      return KeyEventResult.handled;
    }

    // Ctrl+O → file picker (spec §24.6)
    if (ctrl && !shift && !alt && event.logicalKey == LogicalKeyboardKey.keyO) {
      _pickFiles();
      return KeyEventResult.handled;
    }

    // Escape → cancel reply/edit/forward (spec §24.6)
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onEscape?.call();
      return KeyEventResult.handled;
    }

    // PageUp/PageDown → scroll chat history (spec §24.7)
    if (event.logicalKey == LogicalKeyboardKey.pageUp) {
      widget.onScrollPage?.call(true);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.pageDown) {
      widget.onScrollPage?.call(false);
      return KeyEventResult.handled;
    }

    // Tab → trigger autocomplete (spec §24.6)
    if (event.logicalKey == LogicalKeyboardKey.tab && !ctrl && !alt) {
      _checkAutocomplete();
      return KeyEventResult.handled;
    }

    // Submit logic (spec §24.6): respects sendBy mode
    if (_shouldSubmit(event.logicalKey, ctrl, shift)) {
      _doSend();
      return KeyEventResult.handled;
    }

    // Enter that doesn't submit inserts newline; track for triple-Enter
    // blockquote exit (spec §24.6)
    if (isEnter && richCtrl != null) {
      _consecutiveEnters++;
      if (_consecutiveEnters >= 3 && _isInBlockquote(richCtrl)) {
        _exitBlockquote(richCtrl);
        _consecutiveEnters = 0;
        return KeyEventResult.handled;
      }
    }

    // Up arrow → edit last outgoing (spec §24.7)
    if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
        widget.controller.text.isEmpty &&
        !shift && !ctrl && !alt && !meta) {
      final handled = widget.onEditLast?.call() ?? false;
      if (handled) return KeyEventResult.handled;
    }

    // Ctrl+Up / Ctrl+Down → cycle reply target (spec §24.6)
    if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
        ctrl && !shift && !alt && !meta) {
      final handled = widget.onCycleReply?.call(1) ?? false;
      if (handled) return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
        ctrl && !shift && !alt && !meta) {
      final handled = widget.onCycleReply?.call(-1) ?? false;
      if (handled) return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _pastePlainText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null || data!.text!.isEmpty) return;
    final sel = widget.controller.selection;
    final text = widget.controller.text;
    final newText = text.replaceRange(
      sel.start, sel.end, data.text!,
    );
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: sel.start + data.text!.length),
    );
  }

  bool _isInBlockquote(RichTextEditingController ctrl) {
    final cursor = ctrl.selection.baseOffset;
    for (final e in ctrl.entities) {
      if (e.type == FormatType.blockquote &&
          cursor >= e.offset && cursor <= e.offset + e.length) {
        return true;
      }
    }
    return false;
  }

  void _exitBlockquote(RichTextEditingController ctrl) {
    final cursor = ctrl.selection.baseOffset;
    for (var i = 0; i < ctrl.entities.length; i++) {
      final e = ctrl.entities[i];
      if (e.type == FormatType.blockquote &&
          cursor >= e.offset && cursor <= e.offset + e.length) {
        final text = ctrl.text;
        final removeFrom = text.lastIndexOf('\n', cursor - 1);
        final start = removeFrom >= e.offset ? removeFrom : cursor;
        final newText = text.substring(0, start) + text.substring(cursor);
        e.length -= (cursor - start);
        if (e.length <= 0) {
          ctrl.entities.removeAt(i);
        }
        ctrl.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: start),
        );
        break;
      }
    }
  }

  void _onTextChanged(String value) {
    _tryReplaceEmoticon();
    final text = widget.controller.text;
    widget.onDraftChanged(text);
    _scheduleLinkParse(text);
    _checkAutocomplete();
  }

  AutocompleteQuery? _lastAcQuery;

  static final _unicodeEmojiRe = RegExp(
    r'(?:[\u{1F600}-\u{1F64F}]|[\u{1F300}-\u{1F5FF}]|[\u{1F680}-\u{1F6FF}]|[\u{1F1E0}-\u{1F1FF}]|[\u{2600}-\u{26FF}]|[\u{2700}-\u{27BF}]|[\u{FE00}-\u{FE0F}]|[\u{1F900}-\u{1F9FF}]|[\u{1FA00}-\u{1FA6F}]|[\u{1FA70}-\u{1FAFF}]|[\u{200D}]|[\u{20E3}]|[\u{E0020}-\u{E007F}])+$',
    unicode: true,
  );

  void _checkAutocomplete() {
    final sel = widget.controller.selection;
    if (!sel.isValid || !sel.isCollapsed) {
      _dismissAutocomplete();
      return;
    }
    final text = widget.controller.text;
    final cursor = sel.baseOffset;
    if (cursor <= 0 || cursor > text.length) {
      _dismissAutocomplete();
      return;
    }
    final before = text.substring(0, cursor);

    final emojiMatch = RegExp(r'(?:^|(?<=\s)):(\w{2,})$').firstMatch(before);
    if (emojiMatch != null) {
      final query = emojiMatch.group(1)!;
      final triggerOffset = emojiMatch.start + emojiMatch.group(0)!.indexOf(':');
      final acQ = AutocompleteQuery(AutocompleteType.emoji, query, triggerOffset);
      if (_lastAcQuery?.type != acQ.type || _lastAcQuery?.query != acQ.query) {
        _lastAcQuery = acQ;
        widget.onAutocompleteQuery?.call(acQ);
      }
      return;
    }

    final match = RegExp(r'(?:^|(?<=\s))([@#/])(\S*)$').firstMatch(before);
    if (match != null) {
      final trigger = match.group(1)!;
      final query = match.group(2)!;
      final type = switch (trigger) {
        '@' => AutocompleteType.mention,
        '#' => AutocompleteType.hashtag,
        '/' => AutocompleteType.command,
        _ => null,
      };
      if (type != null) {
        final acQ = AutocompleteQuery(type, query, match.start + (match.group(0)!.indexOf(trigger)));
        if (_lastAcQuery?.type != acQ.type || _lastAcQuery?.query != acQ.query) {
          _lastAcQuery = acQ;
          widget.onAutocompleteQuery?.call(acQ);
        }
        return;
      }
    }

    final stickerMatch = _unicodeEmojiRe.firstMatch(before);
    if (stickerMatch != null) {
      final emoji = stickerMatch.group(0)!;
      final acQ = AutocompleteQuery(AutocompleteType.stickerSuggestion, emoji, stickerMatch.start);
      if (_lastAcQuery?.type != acQ.type || _lastAcQuery?.query != acQ.query) {
        _lastAcQuery = acQ;
        widget.onAutocompleteQuery?.call(acQ);
      }
      return;
    }

    _dismissAutocomplete();
  }

  void _dismissAutocomplete() {
    if (_lastAcQuery != null) {
      _lastAcQuery = null;
      widget.onAutocompleteQuery?.call(null);
    }
  }

  void _scheduleLinkParse(String text) {
    _linkTimer?.cancel();
    final delta = (text.length - _prevTextLength).abs();
    _prevTextLength = text.length;

    if (text.isEmpty || delta > 2 || text.endsWith(' ') || text.endsWith('\n')) {
      _parseLinks(text);
    } else {
      _linkTimer = Timer(const Duration(milliseconds: 500), () {
        _parseLinks(widget.controller.text);
      });
    }
  }

  void _parseLinks(String text) {
    final matches = _urlRegex.allMatches(text);
    final urls = matches.map((m) => m.group(0)!).toList();
    if (!_listEquals(urls, _detectedLinks)) {
      _detectedLinks = urls;
      widget.onLinksDetected?.call(urls);
    }
  }

  Future<void> _pickFiles() async {
    debugPrint('ATTACH: _pickFiles called');
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
      );
      debugPrint('ATTACH: result=$result');
      if (result == null || result.files.isEmpty) return;
      final paths = result.files
          .where((f) => f.path != null)
          .map((f) => f.path!)
          .toList();
      debugPrint('ATTACH: picked ${paths.length} files: $paths');
      if (paths.isNotEmpty) {
        widget.onFilesSelected?.call(paths);
      }
    } catch (e) {
      debugPrint('ATTACH: error=$e');
    }
  }

  List<AttachMenuBotInfo>? _cachedAttachBots;
  bool _attachBotsFetched = false;

  Future<void> _onAttachPressed() async {
    final engine = context.read<EngineService>();
    final accountId = context.read<AppState>().activeAccountId;

    if (!_attachBotsFetched) {
      _cachedAttachBots = await engine.getAttachMenuBots(accountId);
      _attachBotsFetched = true;
    }

    final bots = _cachedAttachBots;
    if (bots == null || bots.isEmpty) {
      _pickFiles();
      return;
    }

    if (!mounted) return;
    final button = _attachButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (button == null) {
      _pickFiles();
      return;
    }
    final buttonPos = button.localToGlobal(Offset(0, button.size.height));

    final selected = await showTelegramMenu<int>(
      context: context,
      position: buttonPos,
      items: [
        const TelegramMenuItem<int>(value: -1, label: 'Default'),
        ...bots.asMap().entries.map((e) => TelegramMenuItem<int>(
          value: e.key,
          label: e.value.shortName,
        )),
      ],
    );

    if (selected == null) return;
    if (selected == -1) {
      _pickFiles();
    } else {
      final bot = bots[selected];
      final chatState = context.read<ChatState>();
      chatState.openChatById(bot.botId.toString());
    }
  }

  final GlobalKey _attachButtonKey = GlobalKey();

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _tryReplaceEmoticon() {
    final ctrl = widget.controller;
    final text = ctrl.text;
    final sel = ctrl.selection;
    if (!sel.isValid || !sel.isCollapsed) return;
    final cursor = sel.baseOffset;
    if (cursor < 2) return;

    final trigger = text[cursor - 1];
    if (trigger != ' ' && trigger != '\n') return;

    final beforeTrigger = cursor - 1;

    for (final entry in _kEmoticonsSorted) {
      final emoticon = entry.key;
      final start = beforeTrigger - emoticon.length;
      if (start < 0) continue;
      if (text.substring(start, beforeTrigger) != emoticon) continue;
      if (start > 0) {
        final prev = text[start - 1];
        if (prev != ' ' && prev != '\n' && prev != '\t') continue;
      }

      final emoji = entry.value;
      final newText =
          text.substring(0, start) + emoji + text.substring(beforeTrigger);
      final newCursor = start + emoji.length + 1;
      ctrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newCursor),
      );
      break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final needsFade = _showTopFade || _showBottomFade;

    Widget field = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 36, maxHeight: 224),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        scrollController: _scrollController,
        onChanged: _onTextChanged,
        maxLines: null,
        textInputAction: TextInputAction.newline,
        style: theme.textTheme.bodyMedium,
        decoration: InputDecoration(
          hintText: widget.isEditing
              ? 'Edit message'
              : widget.chatType == ChatType.channel
                  ? 'Broadcast a message...'
                  : 'Write a message...',
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          isDense: true,
        ),
      ),
    );

    if (needsFade) {
      field = ShaderMask(
        shaderCallback: (bounds) {
          const fadeH = 6.0;
          final topStop = (fadeH / bounds.height).clamp(0.0, 0.45);
          final bottomStop = (1.0 - fadeH / bounds.height).clamp(0.55, 1.0);
          return LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _showTopFade ? Colors.transparent : Colors.white,
              Colors.white,
              Colors.white,
              _showBottomFade ? Colors.transparent : Colors.white,
            ],
            stops: [0.0, topStop, bottomStop, 1.0],
          ).createShader(bounds);
        },
        blendMode: BlendMode.dstIn,
        child: field,
      );
    }

    final isDark = theme.brightness == Brightness.dark;
    final composeBg = isDark
        ? AppColors.historyComposeAreaBgNight
        : AppColors.historyComposeAreaBg;
    final iconFg = isDark
        ? AppColors.historyComposeIconFgNight
        : AppColors.historyComposeIconFg;
    final iconFgOver = isDark
        ? AppColors.historyComposeIconFgOverNight
        : AppColors.historyComposeIconFgOver;

    if (_isRecording) {
      final recordBar = Container(
        decoration: BoxDecoration(
          color: composeBg,
          border: Border(
            top: BorderSide(color: theme.dividerColor, width: 1),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 9),
        child: SizedBox(
          height: 46,
          child: _VoiceRecordBar(
            duration: _recordingDuration,
            onCancel: _cancelRecording,
            isLocked: _isRecordingLocked,
            isVideoRound: _isVideoRound,
            onStop: _stopAndSendRecording,
            slideLeftOffset: _slideLeftOffset,
          ),
        ),
      );
      return Stack(
        clipBehavior: Clip.none,
        children: [
          recordBar,
          Positioned(
            right: 1,
            top: -22,
            child: _isRecordingLocked
                ? GestureDetector(
                    onTap: () => setState(() => _ttlArmed = !_ttlArmed),
                    child: AnimatedBuilder(
                      animation: _lockShowController,
                      builder: (context, child) {
                        if (_lockShowController.value == 0) return const SizedBox.shrink();
                        return Opacity(
                          opacity: _lockShowController.value,
                          child: child,
                        );
                      },
                      child: _RecordLockWidget(
                        progress: _lockProgress,
                        isLocked: _isRecordingLocked,
                        isVideoRound: _isVideoRound,
                        isDark: isDark,
                        ttlArmed: _ttlArmed,
                      ),
                    ),
                  )
                : IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _lockShowController,
                      builder: (context, child) {
                        if (_lockShowController.value == 0) return const SizedBox.shrink();
                        return Opacity(
                          opacity: _lockShowController.value,
                          child: Transform.translate(
                            offset: Offset(0, 133 * (1 - _lockShowController.value)),
                            child: child,
                          ),
                        );
                      },
                      child: _RecordLockWidget(
                        progress: _lockProgress,
                        isLocked: _isRecordingLocked,
                        isVideoRound: _isVideoRound,
                        isDark: isDark,
                        ttlArmed: false,
                      ),
                    ),
                  ),
          ),
        ],
      );
    }

    final isMobileWeb = kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
         defaultTargetPlatform == TargetPlatform.iOS);

    final richCtrl = widget.controller is RichTextEditingController
        ? widget.controller as RichTextEditingController
        : null;

    final composeRow = Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          KeyedSubtree(
            key: _attachButtonKey,
            child: _ComposeSlotButton(
            icon: Icons.attach_file,
            tooltip: 'Attach file',
            iconColor: iconFg,
            hoverColor: iconFgOver,
            onPressed: _onAttachPressed,
          ),
          ),
          if (widget.sendAsPeers.length > 1)
            _SendAsButton(
              peers: widget.sendAsPeers,
              selectedPeerId: widget.selectedSendAsPeerId,
              onChanged: widget.onSendAsChanged,
              isDark: isDark,
            ),
          Expanded(
            child: Stack(
              children: [
                field,
                if (_charRemaining <= 100)
                  Positioned(
                    right: 4,
                    top: 2,
                    child: IgnorePointer(
                      child: Text(
                        '$_charRemaining',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: _charRemaining < 0
                              ? const Color(0xFFE53935)
                              : isDark
                                  ? const Color(0xFF7e8b93)
                                  : const Color(0xFF999999),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          _TtlButton(
            ttlPeriod: widget.ttlPeriod,
            iconColor: iconFg,
            hoverColor: iconFgOver,
            accentColor: theme.colorScheme.primary,
            onChanged: widget.onTtlChanged,
          ),
          if (widget.scheduledCount > 0)
            _ScheduledToggleButton(
              iconColor: iconFg,
              hoverColor: iconFgOver,
              onPressed: widget.onScheduledPressed,
            ),
          if (widget.chatType == ChatType.channel)
            _ComposeSlotButton(
              icon: _silentMode ? Icons.notifications_off : Icons.notifications,
              tooltip: _silentMode ? 'Send with Sound' : 'Send without Sound',
              iconColor: _silentMode ? theme.colorScheme.primary : iconFg,
              hoverColor: _silentMode ? theme.colorScheme.primary : iconFgOver,
              onPressed: () => setState(() => _silentMode = !_silentMode),
            ),
          if (widget.isBot && widget.chatType == ChatType.dm)
            _BotCommandButton(
              iconColor: iconFg,
              hoverColor: iconFgOver,
              onPressed: () {
                final ctrl = widget.controller;
                if (ctrl.text.isEmpty || !ctrl.text.startsWith('/')) {
                  ctrl.text = '/${ctrl.text}';
                  ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
                }
              },
            ),
          if (!widget.isBot && widget.chatType == ChatType.dm && !widget.isSelfChat)
            _ComposeSlotButton(
              icon: Icons.card_giftcard,
              tooltip: 'Send a Gift',
              iconColor: iconFg,
              hoverColor: iconFgOver,
              onPressed: () => _showGiftSheet(context),
            ),
          _ComposeSlotButton(
            icon: Icons.emoji_emotions_outlined,
            tooltip: 'Emoji',
            iconColor: widget.emojiPanelVisible
                ? theme.colorScheme.primary
                : iconFg,
            hoverColor: iconFgOver,
            isEmojiToggle: true,
            onPressed: () => widget.onEmojiToggle?.call(),
          ),
          Builder(builder: (context) {
            final type = _computeSendButtonType();
            final forbidden = (type == SendButtonType.record && widget.voiceRestricted) ||
                (type == SendButtonType.round && widget.videoRestricted);
            return _SendButton(
              type: type,
              accentColor: theme.colorScheme.primary,
              iconFg: iconFg,
              onSend: _doSend,
              onSendSilent: widget.onSendSilent,
              onSendScheduled: widget.onSendScheduled,
              onSendWhenOnline: widget.onSendWhenOnline,
              chatType: widget.chatType,
              isSelfChat: widget.isSelfChat,
              forbidden: forbidden,
              slowmodeText: type == SendButtonType.slowmode
                  ? _formatSlowmode(_slowmodeSecondsLeft)
                  : null,
              starsToSend: widget.starsToSend,
              onToggleVoiceRound: () {
                final appState = context.read<AppState>();
                appState.recordVideoMessages = !appState.recordVideoMessages;
                setState(() {});
              },
              onRecordStart: _startRecording,
            );
          }),
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: composeBg,
        border: Border(
          top: BorderSide(color: theme.dividerColor, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isMobileWeb && richCtrl != null)
            _FormattingToolbar(
              controller: richCtrl,
              iconColor: iconFg,
              activeColor: theme.colorScheme.primary,
              isDark: isDark,
            ),
          composeRow,
        ],
      ),
    );
  }
}

/// Formatting toolbar for mobile-web — spec §13.5: keyboard shortcuts hidden,
/// compose-toolbar formatting buttons visible in place of Ctrl+B/I/U.
class _FormattingToolbar extends StatelessWidget {
  final RichTextEditingController controller;
  final Color iconColor;
  final Color activeColor;
  final bool isDark;

  const _FormattingToolbar({
    required this.controller,
    required this.iconColor,
    required this.activeColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Container(
          height: 36,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              for (final entry in _formatButtons)
                _FormatButton(
                  icon: entry.icon,
                  tooltip: entry.label,
                  isActive: controller.hasFormat(entry.type),
                  iconColor: iconColor,
                  activeColor: activeColor,
                  onTap: () => controller.toggleFormat(entry.type),
                ),
            ],
          ),
        );
      },
    );
  }

  static const _formatButtons = [
    (type: FormatType.bold, icon: Icons.format_bold, label: 'Bold'),
    (type: FormatType.italic, icon: Icons.format_italic, label: 'Italic'),
    (type: FormatType.underline, icon: Icons.format_underlined, label: 'Underline'),
    (type: FormatType.strike, icon: Icons.strikethrough_s, label: 'Strikethrough'),
    (type: FormatType.code, icon: Icons.code, label: 'Code'),
    (type: FormatType.spoiler, icon: Icons.visibility_off_outlined, label: 'Spoiler'),
    (type: FormatType.blockquote, icon: Icons.format_quote, label: 'Quote'),
  ];
}

class _FormatButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isActive;
  final Color iconColor;
  final Color activeColor;
  final VoidCallback onTap;

  const _FormatButton({
    required this.icon,
    required this.tooltip,
    required this.isActive,
    required this.iconColor,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            icon,
            size: 20,
            color: isActive ? activeColor : iconColor,
          ),
        ),
      ),
    );
  }
}

/// Compose strip slot button — spec §7.1 historyAttach: 44×46px, ripple 40×40.
/// [isEmojiToggle] renders a 20×20 circle ring instead of a filled icon.
class _ComposeSlotButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final Color iconColor;
  final Color hoverColor;
  final VoidCallback onPressed;
  final bool isEmojiToggle;

  const _ComposeSlotButton({
    required this.icon,
    required this.tooltip,
    required this.iconColor,
    required this.hoverColor,
    required this.onPressed,
    this.isEmojiToggle = false,
  });

  @override
  State<_ComposeSlotButton> createState() => _ComposeSlotButtonState();
}

class _ComposeSlotButtonState extends State<_ComposeSlotButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = _hovered ? widget.hoverColor : widget.iconColor;
    Widget iconWidget;
    if (widget.isEmojiToggle) {
      iconWidget = SizedBox(
        width: 20,
        height: 20,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 1.5),
          ),
          child: Center(
            child: Icon(widget.icon, size: 14, color: color),
          ),
        ),
      );
    } else {
      iconWidget = Icon(widget.icon, size: 22, color: color);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: widget.tooltip,
        child: InkResponse(
          onTap: widget.onPressed,
          radius: 20,
          child: SizedBox(
            width: 44,
            height: 46,
            child: Center(child: iconWidget),
          ),
        ),
      ),
    );
  }
}

class _BotCommandButton extends StatefulWidget {
  final Color iconColor;
  final Color hoverColor;
  final VoidCallback onPressed;

  const _BotCommandButton({
    required this.iconColor,
    required this.hoverColor,
    required this.onPressed,
  });

  @override
  State<_BotCommandButton> createState() => _BotCommandButtonState();
}

class _BotCommandButtonState extends State<_BotCommandButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = _hovered ? widget.hoverColor : widget.iconColor;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: 'Bot Commands',
        child: InkResponse(
          onTap: widget.onPressed,
          radius: 20,
          child: SizedBox(
            width: 44,
            height: 46,
            child: Center(
              child: Text(
                '/',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: color,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Spec §7: TTL/disappearing message timer button.
/// Shows auto-delete timer icon; tapping opens popup with period options.
class _TtlButton extends StatefulWidget {
  final int ttlPeriod;
  final Color iconColor;
  final Color hoverColor;
  final Color accentColor;
  final ValueChanged<int>? onChanged;

  const _TtlButton({
    required this.ttlPeriod,
    required this.iconColor,
    required this.hoverColor,
    required this.accentColor,
    this.onChanged,
  });

  @override
  State<_TtlButton> createState() => _TtlButtonState();
}

class _TtlButtonState extends State<_TtlButton> {
  bool _hovered = false;

  static String _formatTtl(int seconds) {
    if (seconds <= 0) return 'Off';
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}m';
    if (seconds < 86400) return '${seconds ~/ 3600}h';
    final days = seconds ~/ 86400;
    if (days < 31) return '${days}d';
    return '${days ~/ 30}mo';
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.ttlPeriod > 0;
    final color = active
        ? widget.accentColor
        : (_hovered ? widget.hoverColor : widget.iconColor);
    final label = active ? _formatTtl(widget.ttlPeriod) : null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: PopupMenuButton<int>(
        tooltip: active
            ? 'Auto-delete: ${_formatTtl(widget.ttlPeriod)}'
            : 'Auto-delete messages',
        onSelected: (value) {
          if (value != widget.ttlPeriod) {
            widget.onChanged?.call(value);
          }
        },
        itemBuilder: (_) => [
          for (final e in const <MapEntry<int, String>>[
            MapEntry(0, 'Off'),
            MapEntry(86400, '1 day'),
            MapEntry(604800, '7 days'),
            MapEntry(2678400, '1 month'),
          ])
            PopupMenuItem<int>(
              value: e.key,
              child: Row(
                children: [
                  Icon(
                    e.key == 0 ? Icons.timer_off_outlined : Icons.timer_outlined,
                    size: 20,
                    color: e.key == widget.ttlPeriod
                        ? widget.accentColor
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    e.value,
                    style: TextStyle(
                      fontWeight: e.key == widget.ttlPeriod
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: e.key == widget.ttlPeriod
                          ? widget.accentColor
                          : null,
                    ),
                  ),
                ],
              ),
            ),
        ],
        child: SizedBox(
          width: 44,
          height: 46,
          child: Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(Icons.timer_outlined, size: 22, color: color),
                if (label != null)
                  Positioned(
                    right: -6,
                    bottom: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: widget.accentColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFFFFFFF),
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

/// Spec §23.3: Scheduled messages toggle — clock icon with red attention dot.
/// Shown when scheduledMessages.count > 0. Click opens scheduled messages view.
class _ScheduledToggleButton extends StatefulWidget {
  final Color iconColor;
  final Color hoverColor;
  final VoidCallback? onPressed;

  const _ScheduledToggleButton({
    required this.iconColor,
    required this.hoverColor,
    this.onPressed,
  });

  @override
  State<_ScheduledToggleButton> createState() => _ScheduledToggleButtonState();
}

class _ScheduledToggleButtonState extends State<_ScheduledToggleButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = _hovered ? widget.hoverColor : widget.iconColor;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        message: 'Scheduled messages',
        child: InkResponse(
          onTap: widget.onPressed,
          radius: 20,
          child: SizedBox(
            width: 44,
            height: 46,
            child: Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(Icons.schedule, size: 22, color: color),
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFFdf3f40),
                        shape: BoxShape.circle,
                      ),
                    ),
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

/// Spec §7: Send As selector — shows current sender identity avatar,
/// click opens popup menu to switch between available sender peers.
class _SendAsButton extends StatelessWidget {
  final List<SendAsPeerInfo> peers;
  final String? selectedPeerId;
  final ValueChanged<String>? onChanged;
  final bool isDark;

  const _SendAsButton({
    required this.peers,
    this.selectedPeerId,
    this.onChanged,
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final selected = peers.firstWhere(
      (p) => p.peerId == selectedPeerId,
      orElse: () => peers.first,
    );

    return Tooltip(
      message: 'Send as ${selected.displayName}',
      child: InkResponse(
        onTap: () => _showMenu(context),
        radius: 20,
        child: SizedBox(
          width: 44,
          height: 46,
          child: Center(
            child: _SendAsAvatar(
              peer: selected,
              size: 28,
              isDark: isDark,
            ),
          ),
        ),
      ),
    );
  }

  void _showMenu(BuildContext context) {
    final button = context.findRenderObject() as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position,
      items: peers.map((peer) {
        final isSelected = peer.peerId == selectedPeerId;
        return PopupMenuItem<String>(
          value: peer.peerId,
          height: 44,
          child: Row(
            children: [
              _SendAsAvatar(peer: peer, size: 30, isDark: isDark),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  peer.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (isSelected)
                Icon(Icons.check, size: 18, color: Theme.of(context).colorScheme.primary),
            ],
          ),
        );
      }).toList(),
    ).then((value) {
      if (value != null && value != selectedPeerId) {
        onChanged?.call(value);
      }
    });
  }
}

class _SendAsAvatar extends StatelessWidget {
  final SendAsPeerInfo peer;
  final double size;
  final bool isDark;

  const _SendAsAvatar({
    required this.peer,
    required this.size,
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    if (peer.avatarPath.isNotEmpty) {
      return ClipOval(
        child: Image.file(
          File(peer.avatarPath),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(),
        ),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    final colors = [
      const Color(0xFFE17076),
      const Color(0xFF7BC862),
      const Color(0xFF65AADD),
      const Color(0xFFEE7AE6),
      const Color(0xFFE5AE43),
      const Color(0xFF6EC9CB),
      const Color(0xFFCDA0DE),
    ];
    final idx = peer.peerId.hashCode.abs() % colors.length;
    final initial = peer.displayName.isNotEmpty ? peer.displayName[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colors[idx],
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.45,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Spec §7.3: 8-state send button with selection logic.
class _SendButton extends StatefulWidget {
  final SendButtonType type;
  final Color accentColor;
  final Color iconFg;
  final VoidCallback onSend;
  final VoidCallback? onToggleVoiceRound;
  final void Function(double startY, int pointerId, {bool videoRound, double startX})? onRecordStart;
  final VoidCallback? onSendSilent;
  final ValueChanged<DateTime>? onSendScheduled;
  final VoidCallback? onSendWhenOnline;
  final ChatType chatType;
  final bool isSelfChat;
  final bool forbidden;
  final String? slowmodeText;
  final int starsToSend;

  const _SendButton({
    required this.type,
    required this.accentColor,
    required this.iconFg,
    required this.onSend,
    this.onToggleVoiceRound,
    this.onRecordStart,
    this.onSendSilent,
    this.onSendScheduled,
    this.onSendWhenOnline,
    this.chatType = ChatType.dm,
    this.isSelfChat = false,
    this.forbidden = false,
    this.slowmodeText,
    this.starsToSend = 0,
  });

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton>
    with TickerProviderStateMixin {
  bool _hovered = false;
  late AnimationController _morphController;
  late AnimationController _rollController;
  SendButtonType? _prevType;
  bool _isVoiceRoundTransition = false;
  Timer? _holdTimer;
  bool _holdFired = false;

  static const _kWideScale = 5.0;
  static const _morphDuration = Duration(milliseconds: 120);
  static const _rollDuration = Duration(milliseconds: 500);

  static bool _isVoiceRound(SendButtonType? a, SendButtonType? b) {
    if (a == null || b == null) return false;
    const vr = {SendButtonType.record, SendButtonType.round};
    return vr.contains(a) && vr.contains(b) && a != b;
  }

  @override
  void initState() {
    super.initState();
    _morphController = AnimationController(
      vsync: this,
      duration: _morphDuration,
    )..value = 1.0;
    _rollController = AnimationController(
      vsync: this,
      duration: _rollDuration,
    )..value = 1.0;
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _morphController.dispose();
    _rollController.dispose();
    super.dispose();
  }

  void _onRecordPointerDown(PointerDownEvent e) {
    if (e.buttons == kSecondaryMouseButton) {
      widget.onToggleVoiceRound?.call();
      return;
    }
    if (e.buttons != kPrimaryMouseButton) return;
    if (widget.forbidden && _isForbiddable(widget.type)) return;
    _holdFired = false;
    _holdTimer?.cancel();
    final globalY = e.position.dy;
    final pointerId = e.pointer;
    final isRound = widget.type == SendButtonType.round;
    final globalX = e.position.dx;
    _holdTimer = Timer(const Duration(milliseconds: 200), () {
      _holdFired = true;
      widget.onRecordStart?.call(globalY, pointerId, videoRound: isRound, startX: globalX);
    });
  }

  void _onRecordPointerUp(PointerUpEvent e) {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (!_holdFired) {
      final msg = widget.type == SendButtonType.round
          ? 'Hold to record video'
          : 'Hold to record';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 2),
        ),
      );
    }
    _holdFired = false;
  }

  void _onRecordPointerCancel(PointerCancelEvent e) {
    _holdTimer?.cancel();
    _holdTimer = null;
    _holdFired = false;
  }

  @override
  void didUpdateWidget(covariant _SendButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.type != widget.type) {
      _prevType = oldWidget.type;
      if (_isVoiceRound(oldWidget.type, widget.type)) {
        _isVoiceRoundTransition = true;
        _rollController.forward(from: 0.0);
      } else {
        _isVoiceRoundTransition = false;
        _morphController.forward(from: 0.0);
      }
    }
  }

  static IconData _iconFor(SendButtonType type) => switch (type) {
    SendButtonType.send => Icons.send,
    SendButtonType.schedule => Icons.schedule_send,
    SendButtonType.save => Icons.check,
    SendButtonType.record => Icons.mic,
    SendButtonType.round => Icons.videocam,
    SendButtonType.cancel => Icons.close,
    SendButtonType.slowmode => Icons.timer,
    SendButtonType.editPrice => Icons.star,
  };

  static String _tooltipFor(SendButtonType type) => switch (type) {
    SendButtonType.send => 'Send',
    SendButtonType.schedule => 'Schedule',
    SendButtonType.save => 'Save',
    SendButtonType.record => 'Voice message',
    SendButtonType.round => 'Video message',
    SendButtonType.cancel => 'Cancel',
    SendButtonType.slowmode => 'Slowmode active',
    SendButtonType.editPrice => 'Edit price',
  };

  void _onTap() {
    if (widget.forbidden && _isForbiddable(widget.type)) {
      final msg = widget.type == SendButtonType.round
          ? 'The admins of this group restricted you from sending video messages here.'
          : 'The admins of this group restricted you from sending voice messages here.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
      );
      return;
    }
    switch (widget.type) {
      case SendButtonType.send:
      case SendButtonType.save:
        widget.onSend();
      case SendButtonType.record:
      case SendButtonType.round:
        break;
      case SendButtonType.cancel:
        break;
      case SendButtonType.schedule:
        widget.onSend();
      case SendButtonType.slowmode:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Slow mode is enabled. Please wait before sending another message.'),
            duration: Duration(seconds: 3),
          ),
        );
      case SendButtonType.editPrice:
        break;
    }
  }

  bool get _canShowSendMenu {
    const sendLike = {SendButtonType.send, SendButtonType.schedule, SendButtonType.save};
    return sendLike.contains(widget.type) && !widget.forbidden;
  }

  void _showSendMenu() {
    final box = context.findRenderObject() as RenderBox;
    final pos = box.localToGlobal(Offset(0, -4));

    showTelegramMenu<String>(
      context: context,
      position: pos,
      items: [
        if (!widget.isSelfChat)
          const TelegramMenuItem(value: 'silent', icon: Icon(Icons.volume_off_outlined), label: 'Send without Sound'),
        TelegramMenuItem(value: 'schedule', icon: const Icon(Icons.schedule_outlined), label: widget.isSelfChat ? 'Set Reminder' : 'Schedule Message'),
        if (widget.chatType == ChatType.dm && !widget.isSelfChat)
          const TelegramMenuItem(value: 'when_online', icon: Icon(Icons.person_outline), label: 'Send When Online'),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'silent':
          widget.onSendSilent?.call();
        case 'schedule':
          _pickScheduleDate();
        case 'when_online':
          widget.onSendWhenOnline?.call();
      }
    });
  }

  Future<void> _pickScheduleDate() async {
    final result = await showChooseDateTimeBox(
      context,
      isSelfChat: widget.isSelfChat,
      isScheduledToUser: widget.chatType == ChatType.dm && !widget.isSelfChat,
    );
    if (result == null || !mounted) return;
    if (result.sendWhenOnline) {
      widget.onSendWhenOnline?.call();
    } else {
      widget.onSendScheduled?.call(result.dateTime);
    }
  }

  static bool _isForbiddable(SendButtonType type) =>
      type == SendButtonType.record || type == SendButtonType.round;

  Color _colorFor(SendButtonType type) {
    final isSendLike = type == SendButtonType.send ||
        type == SendButtonType.save ||
        type == SendButtonType.schedule;
    return isSendLike
        ? widget.accentColor
        : (_hovered ? widget.accentColor : widget.iconFg);
  }

  Widget _buildRollTransition() {
    return AnimatedBuilder(
      animation: _rollController,
      builder: (context, _) {
        final t = _rollController.value;
        final angle = t * math.pi;
        final showNew = t >= 0.5;
        final icon = showNew ? _iconFor(widget.type) : _iconFor(_prevType!);
        final color = showNew ? _colorFor(widget.type) : _colorFor(_prevType!);
        return Center(
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationZ(angle),
            child: Opacity(
              opacity: showNew ? ((t - 0.5) * 2.0) : (1.0 - t * 2.0).clamp(0.3, 1.0),
              child: Icon(icon, size: 22, color: color),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBloomTransition() {
    return AnimatedBuilder(
      animation: _morphController,
      builder: (context, _) {
        final t = _morphController.value;
        if (t >= 1.0 || _prevType == null) {
          return Center(
            child: Icon(
              _iconFor(widget.type),
              size: 22,
              color: _colorFor(widget.type),
            ),
          );
        }
        final outScale = 1.0 + (_kWideScale - 1.0) * t;
        final inScale = _kWideScale - (_kWideScale - 1.0) * t;
        return Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: 1.0 - t,
                child: Transform.scale(
                  scale: outScale,
                  child: Icon(
                    _iconFor(_prevType!),
                    size: 22,
                    color: _colorFor(_prevType!),
                  ),
                ),
              ),
              Opacity(
                opacity: t,
                child: Transform.scale(
                  scale: inScale,
                  child: Icon(
                    _iconFor(widget.type),
                    size: 22,
                    color: _colorFor(widget.type),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStarsPill(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: widget.accentColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star, size: 16, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            '${widget.starsToSend}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isRecordOrRound =
        widget.type == SendButtonType.record || widget.type == SendButtonType.round;
    final isForbidden = widget.forbidden && _isForbiddable(widget.type);
    final isSlowmode = widget.type == SendButtonType.slowmode;
    final showStars = widget.starsToSend > 0 && widget.type == SendButtonType.send;

    Widget content;
    if (showStars) {
      content = Center(child: _buildStarsPill(context));
    } else if (isSlowmode && widget.slowmodeText != null) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      content = Padding(
        padding: const EdgeInsets.only(right: 10),
        child: Center(
          child: Text(
            widget.slowmodeText!,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.normal,
              color: isDark
                  ? const Color(0xFF7e8e9f)
                  : const Color(0xFF999999),
            ),
          ),
        ),
      );
    } else {
      content = ClipRect(
        child: _isVoiceRoundTransition && _rollController.value < 1.0
            ? _buildRollTransition()
            : _buildBloomTransition(),
      );
      if (isForbidden) {
        content = Opacity(opacity: 0.5, child: content);
      }
    }

    final buttonWidth = showStars ? null : 44.0;

    return Listener(
      onPointerDown: isRecordOrRound
          ? _onRecordPointerDown
          : _canShowSendMenu
          ? (e) {
              if (e.buttons == kSecondaryMouseButton) {
                _showSendMenu();
              }
            }
          : null,
      onPointerUp: isRecordOrRound && !isForbidden
          ? _onRecordPointerUp
          : null,
      onPointerCancel: isRecordOrRound && !isForbidden
          ? _onRecordPointerCancel
          : null,
      child: MouseRegion(
        cursor: isSlowmode ? SystemMouseCursors.basic : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Tooltip(
          message: showStars ? 'Send for ${widget.starsToSend} stars' : _tooltipFor(widget.type),
          child: showStars
              ? Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: PlatformGestureDetector(
                    onTap: _onTap,
                    onLongPress: _canShowSendMenu ? _showSendMenu : null,
                    child: InkResponse(
                      onTap: _onTap,
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(height: 46, child: content),
                    ),
                  ),
                )
              : (isForbidden || isSlowmode)
              ? GestureDetector(
                  onTap: _onTap,
                  child: SizedBox(width: buttonWidth, height: 46, child: content),
                )
              : isRecordOrRound
              ? SizedBox(width: buttonWidth, height: 46, child: content)
              : PlatformGestureDetector(
                  onLongPress: _canShowSendMenu ? _showSendMenu : null,
                  child: InkResponse(
                    onTap: _onTap,
                    radius: 20,
                    child: SizedBox(width: buttonWidth, height: 46, child: content),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Spec §7.4: Voice-record bar — replaces compose input during recording.
/// Red pulsing blob (3-layer, audio-level-driven), timer with 1 decimal,
/// "Slide to cancel" hint (210px wide), cancel button (100px).
class _VoiceRecordBar extends StatefulWidget {
  final Duration duration;
  final VoidCallback onCancel;
  final bool isLocked;
  final bool isVideoRound;
  final VoidCallback? onStop;
  final double slideLeftOffset;

  const _VoiceRecordBar({
    required this.duration,
    required this.onCancel,
    this.isLocked = false,
    this.isVideoRound = false,
    this.onStop,
    this.slideLeftOffset = 0.0,
  });

  @override
  State<_VoiceRecordBar> createState() => _VoiceRecordBarState();
}

class _VoiceRecordBarState extends State<_VoiceRecordBar>
    with TickerProviderStateMixin {
  late AnimationController _blobController;
  late AnimationController _signalDotController;
  bool _cancelHovered = false;

  @override
  void initState() {
    super.initState();
    _blobController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _signalDotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blobController.dispose();
    _signalDotController.dispose();
    super.dispose();
  }

  void _confirmCancel(BuildContext context) {
    final msg = widget.isVideoRound
        ? 'Are you sure you want to stop recording and discard your video message?'
        : 'Are you sure you want to stop recording and discard your voice message?';
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel recording'),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Continue'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) widget.onCancel();
    });
  }

  String _formatDuration(Duration d) {
    final totalMs = d.inMilliseconds;
    final minutes = totalMs ~/ 60000;
    final seconds = (totalMs % 60000) ~/ 1000;
    final tenths = (totalMs % 1000) ~/ 100;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.$tenths';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textFg = isDark ? const Color(0xFFe0e3ea) : const Color(0xFF222222);
    final cancelFg = isDark ? const Color(0xFF6ab4f8) : const Color(0xFF168acd);
    final hintFg = isDark ? const Color(0xFF7e8e9f) : const Color(0xFF999999);

    final slideOpacity = widget.isLocked ? 1.0 : (1.0 - (widget.slideLeftOffset / 100.0).clamp(0.0, 0.6));

    final recordContent = Row(
      children: [
        const SizedBox(width: 12),
        SizedBox(
          width: 46,
          height: 46,
          child: AnimatedBuilder(
            animation: _blobController,
            builder: (context, _) {
              return CustomPaint(
                painter: _BlobPainter(
                  level: _blobController.value,
                  signalDotOpacity: _signalDotController.value,
                  isVideoRound: widget.isVideoRound,
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 60,
          child: Text(
            _formatDuration(widget.duration),
            style: TextStyle(
              fontSize: 13,
              color: textFg,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        if (widget.isLocked) ...[
          Expanded(
            child: Center(
              child: MouseRegion(
                onEnter: (_) => setState(() => _cancelHovered = true),
                onExit: (_) => setState(() => _cancelHovered = false),
                child: GestureDetector(
                  onTap: () => _confirmCancel(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: _cancelHovered
                          ? (isDark ? const Color(0xFF2b3640) : const Color(0xFFf1f1f1))
                          : Colors.transparent,
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontSize: 13,
                        color: cancelFg,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: widget.onStop,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: SizedBox(
                width: 44,
                height: 46,
                child: Center(
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: widget.isVideoRound
                          ? const Color(0xFF3f8ae0)
                          : const Color(0xFFe53935),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ] else ...[
          Expanded(
            child: Center(
              child: Opacity(
                opacity: slideOpacity,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chevron_left, size: 18, color: hintFg),
                    const SizedBox(width: 2),
                    Text(
                      'Slide to cancel',
                      style: TextStyle(fontSize: 13, color: hintFg),
                    ),
                  ],
                ),
              ),
            ),
          ),
          MouseRegion(
            onEnter: (_) => setState(() => _cancelHovered = true),
            onExit: (_) => setState(() => _cancelHovered = false),
            child: GestureDetector(
              onTap: widget.onCancel,
              child: SizedBox(
                width: 100,
                height: 46,
                child: Center(
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 13,
                      color: _cancelHovered
                          ? cancelFg.withValues(alpha: 0.7)
                          : cancelFg,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );

    if (!widget.isLocked && widget.slideLeftOffset > 0) {
      return Transform.translate(
        offset: Offset(-widget.slideLeftOffset * 0.5, 0),
        child: recordContent,
      );
    }
    return recordContent;
  }
}

class _BlobPainter extends CustomPainter {
  final double level;
  final double signalDotOpacity;
  final bool isVideoRound;

  _BlobPainter({required this.level, required this.signalDotOpacity, this.isVideoRound = false});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final center = Offset(cx, cy);

    final baseColor = isVideoRound ? const Color(0xFF3f8ae0) : const Color(0xFFe53935);

    final minorRadius = 40.0 + (47.0 - 40.0) * _wave(level, 0.3);
    final majorRadius = 43.0 + (50.0 - 43.0) * _wave(level, 0.6);
    final mainRadius = 23.0 + (37.0 - 23.0) * level;

    final scale = 0.45;

    final minorPaint = Paint()
      ..color = baseColor.withValues(alpha: 0.12);
    canvas.drawCircle(center, minorRadius * scale, minorPaint);

    final majorPaint = Paint()
      ..color = baseColor.withValues(alpha: 0.20);
    canvas.drawCircle(center, majorRadius * scale, majorPaint);

    final mainPaint = Paint()..color = baseColor;
    canvas.drawCircle(center, mainRadius * scale, mainPaint);

    if (isVideoRound) {
      _drawCameraIcon(canvas, center, scale);
    } else {
      final dotPaint = Paint()
        ..color = baseColor.withValues(alpha: signalDotOpacity);
      canvas.drawCircle(center, 5.0 * scale, dotPaint);
    }
  }

  void _drawCameraIcon(Canvas canvas, Offset center, double scale) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final bodyW = 12.0 * scale;
    final bodyH = 8.0 * scale;
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center.translate(-1.5 * scale, 0), width: bodyW, height: bodyH),
      Radius.circular(1.5 * scale),
    );
    canvas.drawRRect(bodyRect, paint);

    final lensPath = Path()
      ..moveTo(center.dx + bodyW / 2 - 1.5 * scale, center.dy - 2.5 * scale)
      ..lineTo(center.dx + bodyW / 2 + 2.5 * scale, center.dy)
      ..lineTo(center.dx + bodyW / 2 - 1.5 * scale, center.dy + 2.5 * scale)
      ..close();
    canvas.drawPath(lensPath, paint);
  }

  double _wave(double t, double offset) {
    return ((math.sin((t + offset) * math.pi * 2) + 1.0) / 2.0);
  }

  @override
  bool shouldRepaint(covariant _BlobPainter old) =>
      old.level != level || old.signalDotOpacity != signalDotOpacity || old.isVideoRound != isVideoRound;
}

class _RecordLockWidget extends StatelessWidget {
  final double progress;
  final bool isLocked;
  final bool isVideoRound;
  final bool isDark;
  final bool ttlArmed;

  const _RecordLockWidget({
    required this.progress,
    required this.isLocked,
    this.isVideoRound = false,
    required this.isDark,
    this.ttlArmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark ? const Color(0xFF1e2c3a) : const Color(0xFFffffff);
    final borderColor = isDark ? const Color(0xFF2b3e50) : const Color(0xFFe0e0e0);
    final iconColor = isDark ? const Color(0xFF7e8e9f) : const Color(0xFF999999);
    final lockAngle = isLocked ? 15.0 * math.pi / 180.0 : 0.0;
    final accentColor = isVideoRound ? const Color(0xFF3f8ae0) : const Color(0xFFe53935);

    return SizedBox(
      width: 75,
      height: 133,
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(37.5),
          border: Border.all(
            color: ttlArmed ? accentColor : borderColor,
            width: ttlArmed ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!isLocked)
              Icon(
                Icons.keyboard_arrow_up,
                size: 24,
                color: iconColor.withValues(alpha: 1.0 - progress),
              )
            else
              const SizedBox(height: 24),
            const SizedBox(height: 8),
            Transform.rotate(
              angle: lockAngle,
              child: Icon(
                isVideoRound
                    ? (isLocked ? Icons.videocam : Icons.videocam_outlined)
                    : (isLocked ? Icons.lock : Icons.lock_open),
                size: 28,
                color: isLocked ? accentColor : iconColor,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 4,
              width: 40,
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: borderColor,
                valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Forward dialog — shows a searchable chat list to pick a destination.
/// ShareBox — spec §9.4 forward dialog.
/// Grid of recipients (108px rows), multi-select with blue ring + avatar shrink,
/// search field, self-chat first, comment field slides in on selection.
class _ForwardSendOptions {
  final List<String> chatIds;
  final bool dropAuthor;
  final bool dropCaptions;
  final bool silent;
  final int scheduleDate;

  const _ForwardSendOptions({
    required this.chatIds,
    this.dropAuthor = false,
    this.dropCaptions = false,
    this.silent = false,
    this.scheduleDate = 0,
  });
}

class _ShareBox extends StatefulWidget {
  final List<ChatInfo> chats;
  final List<FolderInfo> folders;
  final ValueChanged<_ForwardSendOptions> onSend;
  final bool hasSenders;
  final bool hasCaptions;

  const _ShareBox({
    required this.chats,
    this.folders = const [],
    required this.onSend,
    this.hasSenders = true,
    this.hasCaptions = false,
  });

  @override
  State<_ShareBox> createState() => _ShareBoxState();
}

class _ShareBoxState extends State<_ShareBox> {
  static const _rowHeight = 108.0;
  static const _photoTop = 6.0;
  static const _nameTop = 6.0;
  static const _columnSkip = 6.0;
  static const _imageRadius = 28.0;
  static const _imageSmallRadius = 24.0;
  static const _activateDuration = Duration(milliseconds: 150);
  static const _commentHeightMin = 36.0;
  static const _commentHeightMax = 72.0;
  static const _commentPadding = EdgeInsets.all(5);

  static const _colorRemap = [0, 7, 4, 1, 6, 3, 5];
  static const _userpicPalette = [
    Color(0xFFe17076), Color(0xFF7bc862), Color(0xFFe5ca77), Color(0xFF65aadd),
    Color(0xFFa695e7), Color(0xFFee7aae), Color(0xFF6ec9cb), Color(0xFFe8a64e),
  ];

  String _query = '';
  String? _selectedFolderId;
  final Set<String> _selected = {};
  final _commentController = TextEditingController();
  bool _showSenderName = true;
  bool _showCaption = true;
  bool _silent = false;
  int _scheduleDate = 0;

  List<ChatInfo> get _sortedChats {
    final chats = List<ChatInfo>.from(widget.chats);
    final selfIdx = chats.indexWhere(
      (c) => c.title == 'Saved Messages' && c.type == ChatType.dm,
    );
    if (selfIdx > 0) {
      final self = chats.removeAt(selfIdx);
      chats.insert(0, self);
    }
    return chats;
  }

  bool _chatMatchesFolder(ChatInfo chat, FolderInfo folder) {
    if (folder.excludeChatIds.contains(chat.chatId)) return false;
    if (folder.chatIds.contains(chat.chatId)) return true;
    if (folder.contacts && chat.isContact && chat.type == ChatType.dm) return true;
    if (folder.nonContacts && !chat.isContact && chat.type == ChatType.dm && !chat.isBot) return true;
    if (folder.groups && chat.type == ChatType.group) return true;
    if (folder.channels && chat.type == ChatType.channel) return true;
    if (folder.bots && chat.isBot) return true;
    return false;
  }

  List<ChatInfo> get _filteredChats {
    var sorted = _sortedChats;
    if (_selectedFolderId != null) {
      final folder = widget.folders.where((f) => f.id == _selectedFolderId).firstOrNull;
      if (folder != null) {
        sorted = sorted.where((c) => _chatMatchesFolder(c, folder)).toList();
      }
    }
    if (_query.isEmpty) return sorted;
    final q = _query.toLowerCase();
    return sorted.where((c) => c.title.toLowerCase().contains(q)).toList();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final boxBg = isDark ? const Color(0xFF17212b) : Colors.white;
    final filtered = _filteredChats;
    final size = MediaQuery.of(context).size;
    final colCount = _columnsForWidth(size.width);
    final accentColor = isDark ? const Color(0xFF6ab3f3) : const Color(0xFF40a7e3);

    return Material(
      color: boxBg,
      child: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 54,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      'Forward to...',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (widget.hasSenders || widget.hasCaptions)
                    _buildMenuButton(context, theme, isDark),
                ],
              ),
            ),
            Container(
              height: 1,
              color: isDark ? const Color(0xFF0e1621) : const Color(0x18000000),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: isDark ? const Color(0xFF242f3d) : const Color(0xFFf1f1f1),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            if (widget.folders.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    _buildFolderTab(context, theme, isDark, null, 'All Chats'),
                    for (final folder in widget.folders)
                      _buildFolderTab(context, theme, isDark, folder.id, folder.name),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: colCount,
                  childAspectRatio: (_rowHeight - _photoTop) / _rowHeight,
                  mainAxisExtent: _rowHeight,
                  crossAxisSpacing: _columnSkip,
                ),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final chat = filtered[index];
                  final isSelected = _selected.contains(chat.chatId);
                  return _ShareBoxItem(
                    chat: chat,
                    isSelected: isSelected,
                    onTap: () => _toggleSelection(chat.chatId),
                  );
                },
              ),
            ),
            AnimatedSize(
              duration: _activateDuration,
              curve: Curves.easeOutCubic,
              child: _selected.isNotEmpty
                  ? Padding(
                      padding: _commentPadding,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: _commentHeightMin,
                          maxHeight: _commentHeightMax,
                        ),
                        child: TextField(
                          controller: _commentController,
                          maxLines: null,
                          decoration: InputDecoration(
                            hintText: 'Add a comment...',
                            isDense: true,
                            filled: true,
                            fillColor: isDark ? const Color(0xFF242f3d) : const Color(0xFFf1f1f1),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            Container(
              height: 1,
              color: isDark ? const Color(0xFF0e1621) : const Color(0x18000000),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancel', style: TextStyle(color: theme.hintColor)),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onSecondaryTapUp: _selected.isEmpty ? null : (details) {
                      _showSendMenu(context, theme, isDark, details.globalPosition);
                    },
                    child: FilledButton(
                      onPressed: _selected.isEmpty ? null : _doSend,
                      child: Text(
                        _selected.length <= 1
                            ? 'Send'
                            : 'Send (${_selected.length})',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFolderTab(BuildContext context, ThemeData theme, bool isDark, String? folderId, String label) {
    final isActive = _selectedFolderId == folderId;
    final accentColor = isDark ? const Color(0xFF6ab3f3) : const Color(0xFF40a7e3);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: isActive ? accentColor : (isDark ? const Color(0xFF242f3d) : const Color(0xFFf1f1f1)),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => _selectedFolderId = folderId),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isActive ? Colors.white : (isDark ? const Color(0xFFaaaaaa) : const Color(0xFF555555)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _toggleSelection(String chatId) {
    setState(() {
      if (_selected.contains(chatId)) {
        _selected.remove(chatId);
      } else {
        _selected.add(chatId);
      }
    });
  }

  void _doSend() {
    widget.onSend(_ForwardSendOptions(
      chatIds: _selected.toList(),
      dropAuthor: !_showSenderName,
      dropCaptions: !_showCaption,
      silent: _silent,
      scheduleDate: _scheduleDate,
    ));
  }

  Widget _buildMenuButton(BuildContext context, ThemeData theme, bool isDark) {
    final accentColor = isDark ? const Color(0xFF6ab3f3) : const Color(0xFF40a7e3);
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      position: PopupMenuPosition.over,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onSelected: (value) {
        switch (value) {
          case 'sender':
            setState(() => _showSenderName = !_showSenderName);
            break;
          case 'caption':
            setState(() => _showCaption = !_showCaption);
            break;
          case 'silent':
            setState(() => _silent = !_silent);
            break;
          case 'schedule':
            _showSchedulePicker(context);
            break;
        }
      },
      itemBuilder: (ctx) => [
        if (widget.hasSenders)
          PopupMenuItem<String>(
            value: 'sender',
            child: Row(
              children: [
                SizedBox(width: 24, child: _showSenderName ? Icon(Icons.check, size: 20, color: accentColor) : null),
                const SizedBox(width: 12),
                const Text("Show sender's name"),
              ],
            ),
          ),
        if (widget.hasCaptions)
          PopupMenuItem<String>(
            value: 'caption',
            child: Row(
              children: [
                SizedBox(width: 24, child: _showCaption ? Icon(Icons.check, size: 20, color: accentColor) : null),
                const SizedBox(width: 12),
                const Text('Show caption'),
              ],
            ),
          ),
        if (widget.hasSenders || widget.hasCaptions)
          const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'schedule',
          child: Row(
            children: [
              Icon(Icons.schedule, size: 20, color: theme.iconTheme.color),
              const SizedBox(width: 12),
              const Text('Schedule'),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'silent',
          child: Row(
            children: [
              Icon(
                _silent ? Icons.check : Icons.notifications_off_outlined,
                size: 20,
                color: _silent ? accentColor : theme.iconTheme.color,
              ),
              const SizedBox(width: 12),
              const Text('Send without sound'),
            ],
          ),
        ),
      ],
    );
  }

  void _showSendMenu(BuildContext context, ThemeData theme, bool isDark, Offset position) {
    final accentColor = isDark ? const Color(0xFF6ab3f3) : const Color(0xFF40a7e3);
    final screenSize = MediaQuery.of(context).size;
    final menuItems = <PopupMenuEntry<String>>[];

    if (widget.hasSenders) {
      menuItems.add(PopupMenuItem<String>(
        value: 'sender',
        child: Row(
          children: [
            SizedBox(width: 24, child: _showSenderName ? Icon(Icons.check, size: 20, color: accentColor) : null),
            const SizedBox(width: 12),
            const Text("Show sender's name"),
          ],
        ),
      ));
    }

    if (widget.hasCaptions) {
      menuItems.add(PopupMenuItem<String>(
        value: 'caption',
        child: Row(
          children: [
            SizedBox(width: 24, child: _showCaption ? Icon(Icons.check, size: 20, color: accentColor) : null),
            const SizedBox(width: 12),
            const Text('Show caption'),
          ],
        ),
      ));
    }

    if (widget.hasSenders || widget.hasCaptions) {
      menuItems.add(const PopupMenuDivider());
    }

    menuItems.addAll([
      PopupMenuItem<String>(
        value: 'schedule',
        child: Row(
          children: [
            Icon(Icons.schedule, size: 20, color: theme.iconTheme.color),
            const SizedBox(width: 12),
            const Text('Schedule'),
          ],
        ),
      ),
      PopupMenuItem<String>(
        value: 'silent',
        child: Row(
          children: [
            Icon(
              _silent ? Icons.check : Icons.notifications_off_outlined,
              size: 20,
              color: _silent ? accentColor : theme.iconTheme.color,
            ),
            const SizedBox(width: 12),
            const Text('Send without sound'),
          ],
        ),
      ),
    ]);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx - 220,
        0,
        screenSize.width - position.dx,
        screenSize.height - position.dy,
      ),
      items: menuItems,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'sender':
          setState(() => _showSenderName = !_showSenderName);
          break;
        case 'caption':
          setState(() => _showCaption = !_showCaption);
          break;
        case 'silent':
          setState(() => _silent = !_silent);
          break;
        case 'schedule':
          _showSchedulePicker(context);
          break;
      }
    });
  }

  void _showSchedulePicker(BuildContext context) async {
    final result = await showChooseDateTimeBox(context);
    if (result == null || !mounted) return;
    setState(() => _scheduleDate = result.dateTime.millisecondsSinceEpoch ~/ 1000);
    _doSend();
  }

  int _columnsForWidth(double screenWidth) {
    return (screenWidth / 90).floor().clamp(3, 10);
  }

  static Color avatarColor(String id) {
    final numId = int.tryParse(id) ?? id.hashCode.abs();
    return _userpicPalette[_colorRemap[numId.abs() % 7]];
  }
}

class _ShareBoxItem extends StatelessWidget {
  final ChatInfo chat;
  final bool isSelected;
  final VoidCallback onTap;

  const _ShareBoxItem({
    required this.chat,
    required this.isSelected,
    required this.onTap,
  });

  static const _imageRadius = 28.0;
  static const _imageSmallRadius = 24.0;
  static const _photoTop = 6.0;
  static const _nameTop = 6.0;

  bool get _isSavedMessages =>
      chat.title == 'Saved Messages' && chat.type == ChatType.dm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final radius = isSelected ? _imageSmallRadius : _imageRadius;
    final accentColor = isDark ? const Color(0xFF6ab3f3) : const Color(0xFF40a7e3);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: _photoTop),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: (isSelected ? _imageSmallRadius : _imageRadius) * 2 + (isSelected ? 4 : 0),
            height: (isSelected ? _imageSmallRadius : _imageRadius) * 2 + (isSelected ? 4 : 0),
            decoration: isSelected
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: accentColor, width: 2),
                  )
                : null,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: radius * 2,
                height: radius * 2,
                child: _buildAvatar(radius, isDark),
              ),
            ),
          ),
          SizedBox(height: _nameTop),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              _isSavedMessages ? 'Saved Messages' : chat.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? (isDark ? const Color(0xFF6ab3f3) : const Color(0xFF168acd)) : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(double radius, bool isDark) {
    if (_isSavedMessages) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: isDark ? const Color(0xFF5288c1) : const Color(0xFF40a7e3),
        child: Icon(Icons.bookmark, color: Colors.white, size: radius),
      );
    }
    if (chat.avatarPath.isNotEmpty) {
      return ClipOval(
        child: Image.file(
          File(chat.avatarPath),
          width: radius * 2,
          height: radius * 2,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallbackAvatar(radius),
        ),
      );
    }
    return _fallbackAvatar(radius);
  }

  Widget _fallbackAvatar(double radius) {
    final color = _ShareBoxState.avatarColor(chat.chatId);
    final initials = chat.title.isNotEmpty ? chat.title[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Text(
        initials,
        style: TextStyle(color: Colors.white, fontSize: radius * 0.65),
      ),
    );
  }
}

/// Format a last-seen descriptor per Telegram Desktop spec §4.2 / §14138.
/// Shared by the chat top bar and the info panel avatar header.
///
/// Time format matches Telegram Desktop: 12-hour AM/PM (via QLocale in
/// original source). kind variants: recently, within_week, within_month,
/// long_ago, exact (with lastSeenMs timestamp).
String formatChatLastSeen(({String kind, int lastSeenMs}) ls) {
  switch (ls.kind) {
    case 'recently':
      return 'last seen recently';
    case 'within_week':
      return 'last seen within a week';
    case 'within_month':
      return 'last seen within a month';
    case 'long_ago':
      return 'last seen a long time ago';
    case 'exact':
      if (ls.lastSeenMs <= 0) return '';
      final then = DateTime.fromMillisecondsSinceEpoch(ls.lastSeenMs);
      final now = DateTime.now();
      final diff = now.difference(then);
      if (diff.inSeconds < 60) return 'last seen just now';
      if (diff.inMinutes < 60) {
        final m = diff.inMinutes;
        return 'last seen $m ${m == 1 ? "minute" : "minutes"} ago';
      }
      final sameDay = then.year == now.year &&
          then.month == now.month &&
          then.day == now.day;
      final y = now.subtract(const Duration(days: 1));
      final yesterday = then.year == y.year &&
          then.month == y.month &&
          then.day == y.day;
      final time = _formatTime12h(then);
      if (sameDay) return 'last seen today at $time';
      if (yesterday) return 'last seen yesterday at $time';
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final date = '${months[then.month - 1]} ${then.day}';
      if (then.year != now.year) {
        return 'last seen $date, ${then.year} at $time';
      }
      return 'last seen $date at $time';
    default:
      return '';
  }
}

/// Format a [DateTime] as 12-hour time with AM/PM (e.g. "3:45 PM").
/// Matches Telegram Desktop QLocale English format per spec §14145.
String _formatTime12h(DateTime dt) {
  final h = dt.hour;
  final m = dt.minute.toString().padLeft(2, '0');
  if (h == 0) return '12:$m AM';
  if (h < 12) return '$h:$m AM';
  if (h == 12) return '12:$m PM';
  return '${h - 12}:$m PM';
}

class _DragOverlay extends StatelessWidget {
  final int hoveredCard;
  const _DragOverlay({required this.hoveredCard});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final boxBg = isDark ? const Color(0xFF17212B) : Colors.white;
    final shadowColor = isDark
        ? const Color(0x40000000)
        : const Color(0x26000000);
    final restColor = isDark
        ? const Color(0xFF7c99b2)
        : const Color(0xFF999999);
    final activeColor = isDark
        ? const Color(0xFF6ab3f3)
        : const Color(0xFF168acd);

    return Container(
      color: const Color(0x80000000),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        children: [
          Expanded(
            child: _DragCard(
              title: 'Drop files here',
              subtitle: 'to send them as files',
              icon: Icons.insert_drive_file_outlined,
              isHovered: hoveredCard == 1,
              boxBg: boxBg,
              shadowColor: shadowColor,
              restColor: restColor,
              activeColor: activeColor,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _DragCard(
              title: 'Drop photos here',
              subtitle: 'to send them quick',
              icon: Icons.image_outlined,
              isHovered: hoveredCard == 2,
              boxBg: boxBg,
              shadowColor: shadowColor,
              restColor: restColor,
              activeColor: activeColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _DragCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isHovered;
  final Color boxBg;
  final Color shadowColor;
  final Color restColor;
  final Color activeColor;

  const _DragCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isHovered,
    required this.boxBg,
    required this.shadowColor,
    required this.restColor,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isHovered ? activeColor : restColor;

    return Container(
      decoration: BoxDecoration(
        color: boxBg,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: textColor),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 27,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AutocompletePanel extends StatelessWidget {
  final List<MemberInfo> members;
  final int selectedIndex;
  final ValueChanged<int> onPick;
  final ValueChanged<int> onHover;

  const _AutocompletePanel({
    required this.members,
    required this.selectedIndex,
    required this.onPick,
    required this.onHover,
  });

  static const _colorRemap = [0, 7, 4, 1, 6, 3, 5];
  static const _userpicPalette = [
    Color(0xFFe17076), Color(0xFF7bc862), Color(0xFFe5ca77), Color(0xFF65aadd),
    Color(0xFFa695e7), Color(0xFFee7aae), Color(0xFF6ec9cb), Color(0xFFe8a64e),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212b) : Colors.white;
    final hoverColor = isDark ? const Color(0xFF202b36) : const Color(0xFFf1f1f1);
    final borderColor = theme.dividerColor;

    return TextFieldTapRegion(
      child: Container(
      constraints: const BoxConstraints(maxHeight: 180),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          top: BorderSide(color: borderColor, width: 1),
        ),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: members.length,
        itemBuilder: (context, index) {
          final m = members[index];
          final isSelected = index == selectedIndex;
          final numId = int.tryParse(m.userId) ?? m.userId.hashCode.abs();
          final avatarColor = _userpicPalette[_colorRemap[numId.abs() % 7]];
          return MouseRegion(
            onEnter: (_) => onHover(index),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onPick(index),
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                color: isSelected ? hoverColor : null,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16.5,
                      backgroundColor: m.avatarB64.isNotEmpty ? null : avatarColor,
                      backgroundImage: m.avatarB64.isNotEmpty
                          ? MemoryImage(base64Decode(m.avatarB64))
                          : null,
                      child: m.avatarB64.isEmpty
                          ? Text(
                              m.displayName.isNotEmpty ? m.displayName[0].toUpperCase() : '?',
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        m.displayName.isNotEmpty ? m.displayName : m.userId,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (m.username.isNotEmpty)
                      Text(
                        '@${m.username}',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? const Color(0xFF5b7a93) : const Color(0xFF999999),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      ),
    );
  }
}

class _CommandAutocompletePanel extends StatelessWidget {
  final List<BotCommandInfo> commands;
  final int selectedIndex;
  final ValueChanged<int> onPick;
  final ValueChanged<int> onHover;

  const _CommandAutocompletePanel({
    required this.commands,
    required this.selectedIndex,
    required this.onPick,
    required this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212b) : Colors.white;
    final hoverColor = isDark ? const Color(0xFF202b36) : const Color(0xFFf1f1f1);
    final borderColor = theme.dividerColor;
    final subtitleColor = isDark ? const Color(0xFF5b7a93) : const Color(0xFF999999);

    return TextFieldTapRegion(
      child: Container(
        constraints: const BoxConstraints(maxHeight: 180),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(
            top: BorderSide(color: borderColor, width: 1),
          ),
        ),
        child: ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: commands.length,
          itemBuilder: (context, index) {
            final cmd = commands[index];
            final isSelected = index == selectedIndex;
            return MouseRegion(
              onEnter: (_) => onHover(index),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onPick(index),
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 0),
                  color: isSelected ? hoverColor : null,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 33,
                        height: 33,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF3a5368) : const Color(0xFF5eaade),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Text(
                              '/',
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700, height: 1),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '/${cmd.command}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: theme.textTheme.bodyMedium?.color,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (cmd.description.isNotEmpty)
                              Text(
                                cmd.description,
                                style: TextStyle(fontSize: 12, color: subtitleColor),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      if (cmd.botUsername.isNotEmpty)
                        Text(
                          '@${cmd.botUsername}',
                          style: TextStyle(fontSize: 12, color: subtitleColor),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EmojiSuggestionPanel extends StatelessWidget {
  final List<EmojiEntry> emojis;
  final int selectedIndex;
  final ValueChanged<int> onPick;
  final ValueChanged<int> onHover;

  const _EmojiSuggestionPanel({
    required this.emojis,
    required this.selectedIndex,
    required this.onPick,
    required this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1e2c3a) : const Color(0xFFf7f7f7);
    final hoverColor = isDark ? const Color(0xFF2b3d4f) : const Color(0xFFe8e8e8);
    final borderColor = isDark ? const Color(0xFF101a23) : const Color(0xFFdadada);

    return TextFieldTapRegion(
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(
            top: BorderSide(color: borderColor, width: 1),
            bottom: BorderSide(color: borderColor, width: 1),
          ),
        ),
        child: ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: const [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
            stops: const [0.0, 0.03, 0.97, 1.0],
          ).createShader(bounds),
          blendMode: BlendMode.dstIn,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemCount: emojis.length,
            itemBuilder: (context, index) {
              final e = emojis[index];
              final isSelected = index == selectedIndex;
              return MouseRegion(
                onEnter: (_) => onHover(index),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onPick(index),
                  child: Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(
                      color: isSelected ? hoverColor : null,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(e.emoji, style: const TextStyle(fontSize: 24)),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _StickerSuggestionPanel extends StatelessWidget {
  final List<StickerInfoItem> stickers;
  final int selectedIndex;
  final ValueChanged<int> onPick;
  final ValueChanged<int> onHover;

  const _StickerSuggestionPanel({
    required this.stickers,
    required this.selectedIndex,
    required this.onPick,
    required this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212b) : Colors.white;
    final hoverColor = isDark ? const Color(0xFF202b36) : const Color(0xFFf1f1f1);
    final borderColor = isDark ? const Color(0xFF101a23) : const Color(0xFFdadada);
    const cellSize = 100.0;

    return TextFieldTapRegion(
      child: Container(
        height: cellSize + 8,
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(
            top: BorderSide(color: borderColor, width: 1),
          ),
        ),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          itemCount: stickers.length,
          itemBuilder: (context, index) {
            final s = stickers[index];
            final isSelected = index == selectedIndex;
            return MouseRegion(
              onEnter: (_) => onHover(index),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onPick(index),
                child: Container(
                  width: cellSize,
                  height: cellSize,
                  decoration: BoxDecoration(
                    color: isSelected ? hoverColor : null,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: s.thumbB64.isNotEmpty
                      ? Image.memory(
                          base64Decode(s.thumbB64),
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        )
                      : Center(
                          child: Text(s.emoji, style: const TextStyle(fontSize: 40)),
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InlineBotResultsPanel extends StatelessWidget {
  final InlineBotResults results;
  final bool gallery;
  final ValueChanged<InlineBotResult> onPick;
  final bool loading;
  final VoidCallback? onSwitchPM;

  const _InlineBotResultsPanel({
    required this.results,
    required this.gallery,
    required this.onPick,
    this.loading = false,
    this.onSwitchPM,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212b) : Colors.white;

    return SizedBox(
      height: 200,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(top: BorderSide(color: isDark ? const Color(0xFF1e2c3a) : const Color(0xFFe8e8e8))),
        ),
        child: gallery ? _buildGalleryGrid(isDark) : _buildListView(isDark),
      ),
    );
  }

  Widget _buildGalleryGrid(bool isDark) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availW = constraints.maxWidth - 6; // 3px padding each side
        final rows = _packMosaicRows(results.results, availW);
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
          itemCount: rows.length,
          itemBuilder: (context, rowIndex) {
            final row = rows[rowIndex];
            return Padding(
              padding: EdgeInsets.only(top: rowIndex > 0 ? 3 : 0),
              child: SizedBox(
                height: row.height,
                child: Row(
                  children: [
                    for (int i = 0; i < row.items.length; i++) ...[
                      if (i > 0) const SizedBox(width: 3),
                      SizedBox(
                        width: row.widths[i],
                        height: row.height,
                        child: _GalleryResultItem(
                          item: row.items[i],
                          onTap: () => onPick(row.items[i]),
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static const double _mosaicRowHeight = 96.0;
  static const double _mosaicSkip = 3.0;
  static const double _mosaicMinWidth = 48.0;

  List<_MosaicRow> _packMosaicRows(List<InlineBotResult> items, double availW) {
    final rows = <_MosaicRow>[];
    int i = 0;
    while (i < items.length) {
      final rowItems = <InlineBotResult>[];
      final intrinsicWidths = <double>[];
      double usedW = 0;
      while (i < items.length) {
        final item = items[i];
        double iw;
        if (item.thumbW > 0 && item.thumbH > 0) {
          iw = (item.thumbW / item.thumbH) * _mosaicRowHeight;
        } else {
          iw = _mosaicRowHeight;
        }
        if (iw < _mosaicMinWidth) iw = _mosaicMinWidth;
        final skipW = rowItems.isEmpty ? 0.0 : _mosaicSkip;
        if (rowItems.isNotEmpty && usedW + skipW + iw > availW) break;
        rowItems.add(item);
        intrinsicWidths.add(iw);
        usedW += skipW + iw;
        i++;
      }
      if (rowItems.isEmpty) break;
      final totalSkip = (rowItems.length - 1) * _mosaicSkip;
      final totalIntrinsic = intrinsicWidths.fold(0.0, (s, w) => s + w);
      final scale = (availW - totalSkip) / totalIntrinsic;
      final scaledWidths = <double>[];
      double remaining = availW - totalSkip;
      for (int j = 0; j < intrinsicWidths.length; j++) {
        if (j == intrinsicWidths.length - 1) {
          scaledWidths.add(remaining);
        } else {
          final sw = (intrinsicWidths[j] * scale).floorToDouble();
          scaledWidths.add(sw);
          remaining -= sw;
        }
      }
      final rowH = _mosaicRowHeight * scale;
      rows.add(_MosaicRow(items: rowItems, widths: scaledWidths, height: rowH.clamp(48.0, 200.0)));
    }
    return rows;
  }

  Widget _buildListView(bool isDark) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: results.results.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        thickness: 1,
        color: isDark ? const Color(0xFF1e2c3a) : const Color(0xFFe8e8e8),
      ),
      itemBuilder: (context, index) {
        final item = results.results[index];
        return _ListResultItem(item: item, onTap: () => onPick(item), isDark: isDark);
      },
    );
  }
}

class _MosaicRow {
  final List<InlineBotResult> items;
  final List<double> widths;
  final double height;
  const _MosaicRow({required this.items, required this.widths, required this.height});
}

class _SwitchPMButton extends StatefulWidget {
  final String text;
  final VoidCallback? onTap;
  final bool isDark;

  const _SwitchPMButton({required this.text, this.onTap, required this.isDark});

  @override
  State<_SwitchPMButton> createState() => _SwitchPMButtonState();
}

class _SwitchPMButtonState extends State<_SwitchPMButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accentColor = widget.isDark ? const Color(0xFF5288c1) : const Color(0xFF40a7e3);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          color: _hovered
              ? (widget.isDark ? const Color(0xFF202b36) : const Color(0xFFf1f1f1))
              : null,
          child: Row(
            children: [
              Icon(Icons.open_in_new, size: 18, color: accentColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.text,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: accentColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GalleryResultItem extends StatefulWidget {
  final InlineBotResult item;
  final VoidCallback onTap;
  final bool isDark;

  const _GalleryResultItem({required this.item, required this.onTap, required this.isDark});

  @override
  State<_GalleryResultItem> createState() => _GalleryResultItemState();
}

class _GalleryResultItemState extends State<_GalleryResultItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            color: widget.isDark ? const Color(0xFF1e2c3a) : const Color(0xFFf0f0f0),
            borderRadius: BorderRadius.circular(4),
            border: _hovered
                ? Border.all(color: widget.isDark ? const Color(0xFF5288c1) : const Color(0xFF40a7e3), width: 2)
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: _buildThumb(),
        ),
      ),
    );
  }

  Widget _buildThumb() {
    if (widget.item.thumbUrl.isNotEmpty) {
      return Image.network(widget.item.thumbUrl, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallbackContent());
    }
    if (widget.item.thumbB64.isNotEmpty) {
      try {
        final bytes = base64Decode(widget.item.thumbB64);
        return Image.memory(Uint8List.fromList(bytes), fit: BoxFit.cover, gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _fallbackContent());
      } catch (_) {}
    }
    return _fallbackContent();
  }

  Widget _fallbackContent() {
    if (widget.item.title.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Text(
            widget.item.title,
            style: TextStyle(
              fontSize: 11,
              color: widget.isDark ? const Color(0xFFaaaaaa) : const Color(0xFF666666),
            ),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    final iconColor = widget.isDark ? const Color(0xFF5b7a93) : const Color(0xFFbbbbbb);
    return Center(
      child: Icon(
        widget.item.type == 'gif' ? Icons.gif_box_outlined : Icons.image_outlined,
        size: 32,
        color: iconColor,
      ),
    );
  }
}

class _ListResultItem extends StatefulWidget {
  final InlineBotResult item;
  final VoidCallback onTap;
  final bool isDark;

  const _ListResultItem({required this.item, required this.onTap, required this.isDark});

  @override
  State<_ListResultItem> createState() => _ListResultItemState();
}

class _ListResultItemState extends State<_ListResultItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hoverColor = widget.isDark ? const Color(0xFF202b36) : const Color(0xFFf1f1f1);
    final thumbBg = widget.isDark ? const Color(0xFF1e2c3a) : const Color(0xFFf0f0f0);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          color: _hovered ? hoverColor : null,
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: thumbBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildListThumb(),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.item.title.isNotEmpty)
                      Text(
                        widget.item.title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.textTheme.bodyMedium?.color,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (widget.item.description.isNotEmpty)
                      Text(
                        widget.item.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: widget.isDark ? const Color(0xFF5b7a93) : const Color(0xFF999999),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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

  Widget _buildListThumb() {
    if (widget.item.thumbUrl.isNotEmpty) {
      return Image.network(widget.item.thumbUrl, fit: BoxFit.cover,
          width: 48, height: 48,
          errorBuilder: (_, __, ___) => Center(child: _thumbIcon()));
    }
    if (widget.item.thumbB64.isNotEmpty) {
      try {
        final bytes = base64Decode(widget.item.thumbB64);
        return Image.memory(bytes, fit: BoxFit.cover,
            width: 48, height: 48, gaplessPlayback: true,
            errorBuilder: (_, __, ___) => Center(child: _thumbIcon()));
      } catch (_) {}
    }
    return Center(child: _thumbIcon());
  }

  Widget _thumbIcon() {
    final iconColor = widget.isDark ? const Color(0xFF5b7a93) : const Color(0xFFbbbbbb);
    return switch (widget.item.type) {
      'photo' => Icon(Icons.photo, size: 24, color: iconColor),
      'gif' => Icon(Icons.gif_box_outlined, size: 24, color: iconColor),
      'video' => Icon(Icons.videocam_outlined, size: 24, color: iconColor),
      'audio' || 'voice' => Icon(Icons.audiotrack, size: 24, color: iconColor),
      'sticker' => Icon(Icons.emoji_emotions_outlined, size: 24, color: iconColor),
      'document' || 'file' => Icon(Icons.insert_drive_file_outlined, size: 24, color: iconColor),
      _ => Icon(Icons.article_outlined, size: 24, color: iconColor),
    };
  }
}

/// Star gift bottom sheet — fetches available gifts and displays in a grid.
class _StarGiftSheet extends StatefulWidget {
  final String accountId;
  final String chatId;
  final String peerName;
  final EngineService engine;

  const _StarGiftSheet({
    required this.accountId,
    required this.chatId,
    required this.peerName,
    required this.engine,
  });

  @override
  State<_StarGiftSheet> createState() => _StarGiftSheetState();
}

class _StarGiftSheetState extends State<_StarGiftSheet> {
  List<StarGiftItem>? _gifts;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadGifts();
  }

  Future<void> _loadGifts() async {
    final result = await widget.engine.getStarGifts(widget.accountId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result == null || result.gifts.isEmpty) {
        _error = 'No gifts available';
      } else {
        _gifts = result.gifts;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212b) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF3e546a) : const Color(0xFFcccccc),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: Text(
                  'Send a Gift to ${widget.peerName}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
              Expanded(child: _buildContent(scrollController, isDark, textColor)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContent(ScrollController controller, bool isDark, Color textColor) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, style: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 14)),
        ),
      );
    }
    final gifts = _gifts!;
    return GridView.builder(
      controller: controller,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.85,
      ),
      itemCount: gifts.length,
      itemBuilder: (context, index) {
        final gift = gifts[index];
        return _StarGiftCard(gift: gift, isDark: isDark);
      },
    );
  }
}

class _StarGiftCard extends StatelessWidget {
  final StarGiftItem gift;
  final bool isDark;

  const _StarGiftCard({required this.gift, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark ? const Color(0xFF1e2c3a) : const Color(0xFFF5F5F5);
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? const Color(0xFF7e8b93) : const Color(0xFF999999);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (gift.thumbB64.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                base64Decode(gift.thumbB64),
                width: 64,
                height: 64,
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            )
          else
            Icon(Icons.card_giftcard, size: 48, color: subColor),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star, size: 14, color: Color(0xFFFFAB00)),
              const SizedBox(width: 2),
              Text(
                '${gift.stars}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
              ),
            ],
          ),
          if (gift.limited)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${gift.remaining} left',
                style: TextStyle(fontSize: 10, color: subColor),
              ),
            ),
        ],
      ),
    );
  }
}

/// §23.8: Top-attached toast for video processing tip.
/// Shows title + body text, auto-dismisses after 4000ms.
class _VideoProcessingTipToast extends StatefulWidget {
  final VoidCallback onDismiss;
  const _VideoProcessingTipToast({required this.onDismiss});
  @override
  State<_VideoProcessingTipToast> createState() => _VideoProcessingTipToastState();
}

class _VideoProcessingTipToastState extends State<_VideoProcessingTipToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: FadeTransition(
        opacity: _anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic)),
          child: GestureDetector(
            onTap: widget.onDismiss,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              constraints: const BoxConstraints(maxWidth: 380),
              padding: const EdgeInsets.fromLTRB(19, 13, 19, 13),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xF0202C39) : const Color(0xF0FFFFFF),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Video is processing',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF222222),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'The video will be sent at the scheduled time once processing is complete.',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? const Color(0xFFAAAAAA) : const Color(0xFF777777),
                    ),
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

/// §23.8: Tooltip bubble for video processing, shown after the tip toast.
/// Max width 364px, transparent for mouse events, auto-hides.
class _VideoProcessingTooltip extends StatefulWidget {
  final double maxWidth;
  final VoidCallback onDismiss;
  const _VideoProcessingTooltip({required this.maxWidth, required this.onDismiss});
  @override
  State<_VideoProcessingTooltip> createState() => _VideoProcessingTooltipState();
}

class _VideoProcessingTooltipState extends State<_VideoProcessingTooltip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Positioned(
      left: 16,
      right: 16,
      top: 62,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _anim,
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              constraints: BoxConstraints(maxWidth: widget.maxWidth),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2B3A4A) : const Color(0xFF333333),
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'This video is still being processed and will be sent automatically when ready.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  CustomPaint(
                    size: const Size(12, 8),
                    painter: _TooltipArrowPainter(
                      color: isDark ? const Color(0xFF2B3A4A) : const Color(0xFF333333),
                    ),
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

class _TooltipArrowPainter extends CustomPainter {
  final Color color;
  const _TooltipArrowPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TooltipArrowPainter old) => old.color != color;
}

/// §23.8: Published video notification toast with thumbnail + "View" button.
/// Top-attached, 380px max width, 19/17/19/17px padding, 4000ms duration.
/// Right-click dismisses.
class _VideoPublishedToast extends StatefulWidget {
  final Uint8List? thumbnail;
  final VoidCallback onView;
  final VoidCallback onDismiss;
  const _VideoPublishedToast({
    this.thumbnail,
    required this.onView,
    required this.onDismiss,
  });
  @override
  State<_VideoPublishedToast> createState() => _VideoPublishedToastState();
}

class _VideoPublishedToastState extends State<_VideoPublishedToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final thumbSize = 28.0; // font->height * 2 ≈ 28px
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: FadeTransition(
        opacity: _anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic)),
          child: Center(
            child: GestureDetector(
              onSecondaryTap: widget.onDismiss,
              child: Container(
                constraints: const BoxConstraints(minWidth: 32, maxWidth: 380),
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                padding: const EdgeInsets.fromLTRB(19, 17, 19, 17),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xF0202C39) : const Color(0xF0FFFFFF),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: widget.thumbnail != null
                          ? Image.memory(
                              widget.thumbnail!,
                              width: thumbSize,
                              height: thumbSize,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              width: thumbSize,
                              height: thumbSize,
                              color: isDark ? const Color(0xFF3A4A5A) : const Color(0xFFDDDDDD),
                              child: Icon(
                                Icons.videocam,
                                size: 16,
                                color: isDark ? const Color(0xFF8899AA) : const Color(0xFF999999),
                              ),
                            ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Scheduled video published',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : const Color(0xFF222222),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: widget.onView,
                      child: Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        alignment: Alignment.center,
                        child: Text(
                          'View',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: isDark ? const Color(0xFF71BFFF) : const Color(0xFF168ACD),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _showChatPreviewPopup(BuildContext ctx, ChatInfo chat, ChatState chatState) {
  final theme = Theme.of(ctx);
  final isDark = theme.brightness == Brightness.dark;
  final bgColor = isDark ? const Color(0xFF17212b) : Colors.white;
  final textColor = isDark ? Colors.white : const Color(0xFF222222);
  final subtitleColor = isDark ? const Color(0xFF5b7a93) : const Color(0xFF999999);
  final msgs = chatState.messages.take(5).toList();

  showDialog(
    context: ctx,
    barrierColor: Colors.black38,
    builder: (dialogCtx) => GestureDetector(
      onTap: () => Navigator.of(dialogCtx).pop(),
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: GestureDetector(
          onTap: () {},
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(10),
            color: bgColor,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360, maxHeight: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                    child: Row(
                      children: [
                        _previewAvatar(chat, 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                chat.title,
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                _previewSubtitle(chat),
                                style: TextStyle(color: subtitleColor, fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: theme.dividerColor),
                  if (msgs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No messages',
                        style: TextStyle(color: subtitleColor, fontSize: 13),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                        itemCount: msgs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 4),
                        itemBuilder: (_, i) {
                          final m = msgs[i];
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (m.senderName.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Text(
                                    '${m.senderName}:',
                                    style: TextStyle(
                                      color: isDark
                                          ? const Color(0xFF71BFFF)
                                          : const Color(0xFF168ACD),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  m.contentText.isNotEmpty
                                      ? m.contentText
                                      : (m.hasMedia ? '[Media]' : ''),
                                  style: TextStyle(color: textColor, fontSize: 13),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _previewAvatar(ChatInfo chat, double radius) {
  if (chat.avatarPath.isNotEmpty) {
    final file = File(chat.avatarPath);
    if (file.existsSync()) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: FileImage(file),
      );
    }
  }
  const colorRemap = [0, 7, 4, 1, 6, 3, 5];
  const palette = [
    Color(0xFFe17076), Color(0xFF7bc862), Color(0xFFe5ca77), Color(0xFF65aadd),
    Color(0xFFa695e7), Color(0xFFee7aae), Color(0xFF6ec9cb), Color(0xFFe8a64e),
  ];
  final numId = int.tryParse(chat.chatId) ?? chat.chatId.hashCode.abs();
  final idx = colorRemap[numId.abs() % 7];
  return CircleAvatar(
    radius: radius,
    backgroundColor: palette[idx],
    child: Text(
      chat.title.isNotEmpty ? chat.title[0].toUpperCase() : '?',
      style: TextStyle(color: Colors.white, fontSize: radius * 0.7, fontWeight: FontWeight.w600),
    ),
  );
}

String _previewSubtitle(ChatInfo chat) {
  if (chat.memberCount > 0) {
    final label = chat.type == ChatType.channel ? 'subscribers' : 'members';
    return '${chat.memberCount} $label';
  }
  return chat.type == ChatType.dm ? 'Private chat' : '';
}

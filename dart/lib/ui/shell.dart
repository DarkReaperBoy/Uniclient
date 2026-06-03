import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';
import '../state/app_state.dart';
import '../state/auth_state.dart';
import '../state/chat_state.dart';
import 'auth_screen.dart';
import 'chat_export.dart';
import 'chat_list_panel.dart';
import 'chat_view.dart';
import 'filter_column.dart';
import 'hamburger_drawer.dart';
import 'advanced_settings_screen.dart';
import 'call_screen.dart';
import 'chat_switch_overlay.dart';
import 'info_panel.dart';
import 'keyboard_shortcuts.dart';
import 'music_player_bar.dart';
import '../theme/theme.dart';

/// Layout modes matching Telegram Desktop's responsive breakpoints.
enum LayoutMode { oneColumn, twoColumn, threeColumn }

/// Main app shell: responsive column layout with chat list, chat view, and info panel.
class UniClientShell extends StatefulWidget {
  const UniClientShell({super.key});

  static VoidCallback? toggleInfoRequest;
  static VoidCallback? openInfoRequest;
  static void Function({bool reverse})? showChatSwitchRequest;
  static VoidCallback? hideChatSwitchRequest;

  @override
  State<UniClientShell> createState() => _UniClientShellState();
}

class _UniClientShellState extends State<UniClientShell>
    with SingleTickerProviderStateMixin {
  // Dialogs column width ratio (0.0-1.0 of body width), persisted to layout.json.
  double _dialogsWidthRatio = 0.33;
  bool _infoOpen = false;
  // Third column width, persisted within [_thirdMin, _thirdMax].
  double _thirdColumnWidth = 360.0;
  bool _layoutLoaded = false;
  bool? _lastVerticalFilters;
  Set<String>? _lastForumViewPrefs;
  bool _isDragging = false;
  bool _chatSwitchActive = false;
  // One-column section transition direction tracking (spec §1: horizontal slide + crossfade).
  bool _navForward = true;
  bool _hadActiveChat = false;
  // Spec §4.1: top-bar divider hidden during one-column slide transitions.
  bool _oneColumnAnimating = false;
  Timer? _oneColumnTimer;
  // Spec §1: third column open/close animation. Shadow stays until dismissed.
  late final AnimationController _thirdColumnAnim;
  late final Animation<double> _thirdColumnCurved;

  // Spec §1 column constants (window.style:20-24).
  static const _dialogsMin = 260.0;
  static const _chatMin = 380.0;
  static const _thirdMin = 292.0;
  static const _thirdMax = 392.0;
  static const _filtersWidth = 72.0;

  // Spec §1: Wide chat mode triggers at 880px chat width.
  static const _wideChatThreshold = 880.0;

  // OneColumn: < 640, ThreeColumn: >= 932
  static const _oneColumnBreak = 640.0;
  static const _threeColumnBreak = 932.0;

  String _configDir = '';

  String get _layoutFilePath =>
      _configDir.isEmpty ? '' : '$_configDir/layout.json';

  void _loadLayoutPrefs() {
    final path = _layoutFilePath;
    if (path.isEmpty) return;
    try {
      final file = File(path);
      if (!file.existsSync()) return;
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      _dialogsWidthRatio = (data['dialogsWidthRatio'] as num?)?.toDouble() ?? _dialogsWidthRatio;
      _thirdColumnWidth = (data['thirdColumnWidth'] as num?)?.toDouble() ?? _thirdColumnWidth;
      final chatState = context.read<ChatState>();
      chatState.useVerticalFilters = (data['useVerticalFilters'] as bool?) ?? true;
      final forumPrefs = data['forumViewAsMessages'];
      if (forumPrefs is List) {
        chatState.loadForumViewPrefs(forumPrefs.cast<String>().toSet());
      }
    } catch (_) {
      // Ignore corrupt/missing file.
    }
  }

  void _saveLayoutPrefs() {
    final path = _layoutFilePath;
    if (path.isEmpty) return;
    try {
      final chatState = context.read<ChatState>();
      File(path).writeAsStringSync(jsonEncode({
        'dialogsWidthRatio': _dialogsWidthRatio,
        'thirdColumnWidth': _thirdColumnWidth,
        'useVerticalFilters': chatState.useVerticalFilters,
        'forumViewAsMessages': chatState.forumViewAsMessagesKeys.toList(),
      }));
    } catch (_) {
      // Best-effort persistence.
    }
  }

  @override
  void initState() {
    super.initState();
    _thirdColumnAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    )..addStatusListener((status) {
        if (status == AnimationStatus.dismissed) {
          setState(() {}); // Remove third column widgets from tree.
        }
      });
    _thirdColumnCurved = CurvedAnimation(
      parent: _thirdColumnAnim,
      curve: Curves.easeOutCirc,
    );
    UniClientShell.toggleInfoRequest = _toggleInfo;
    UniClientShell.openInfoRequest = _openInfo;
    UniClientShell.showChatSwitchRequest = _showChatSwitch;
    UniClientShell.hideChatSwitchRequest = _hideChatSwitch;
  }

  @override
  void dispose() {
    if (UniClientShell.toggleInfoRequest == _toggleInfo) {
      UniClientShell.toggleInfoRequest = null;
    }
    if (UniClientShell.openInfoRequest == _openInfo) {
      UniClientShell.openInfoRequest = null;
    }
    if (UniClientShell.showChatSwitchRequest == _showChatSwitch) {
      UniClientShell.showChatSwitchRequest = null;
    }
    if (UniClientShell.hideChatSwitchRequest == _hideChatSwitch) {
      UniClientShell.hideChatSwitchRequest = null;
    }
    _thirdColumnAnim.dispose();
    _oneColumnTimer?.cancel();
    super.dispose();
  }

  void _toggleInfo() {
    setState(() {
      _infoOpen = !_infoOpen;
      _navForward = _infoOpen;
      if (_infoOpen) {
        _thirdColumnAnim.forward();
      } else {
        _thirdColumnAnim.reverse();
      }
    });
  }

  void _openInfo() {
    if (_infoOpen) return;
    setState(() {
      _infoOpen = true;
      _navForward = true;
      _thirdColumnAnim.forward();
    });
  }

  void _closeInfo() {
    if (!_infoOpen) return;
    setState(() {
      _infoOpen = false;
      _navForward = false;
      _thirdColumnAnim.reverse();
    });
  }

  bool _chatSwitchReverse = false;

  void _showChatSwitch({bool reverse = false}) {
    if (_chatSwitchActive) return;
    ShortcutSystem.instance.pause();
    setState(() {
      _chatSwitchReverse = reverse;
      _chatSwitchActive = true;
    });
  }

  void _hideChatSwitch() {
    if (!_chatSwitchActive) return;
    ShortcutSystem.instance.resume();
    setState(() => _chatSwitchActive = false);
  }

  LayoutMode _layoutMode(double bodyWidth) {
    if (bodyWidth < _oneColumnBreak) return LayoutMode.oneColumn;
    if (bodyWidth >= _threeColumnBreak && (_infoOpen || !_thirdColumnAnim.isDismissed)) return LayoutMode.threeColumn;
    return LayoutMode.twoColumn;
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final authState = context.watch<AuthState>();
    final chatState = context.watch<ChatState>();

    // Track navigation direction for one-column section transitions.
    final hasChat = chatState.activeChat != null;
    if (hasChat != _hadActiveChat) {
      _navForward = hasChat;
      _hadActiveChat = hasChat;
      // Spec §4.1: hide top-bar divider during one-column slide transition.
      _oneColumnAnimating = true;
      _oneColumnTimer?.cancel();
      _oneColumnTimer = Timer(const Duration(milliseconds: 200), () {
        if (mounted) setState(() => _oneColumnAnimating = false);
      });
    }

    // Load layout prefs once configDir becomes available.
    if (!_layoutLoaded && appState.configDir.isNotEmpty) {
      _layoutLoaded = true;
      _configDir = appState.configDir;
      _loadLayoutPrefs();
      _lastVerticalFilters = chatState.useVerticalFilters;
    }

    // Persist when filter tab mode changes (§18.12).
    chatState.onPersistLayout ??= () {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _saveLayoutPrefs();
      });
    };
    if (_layoutLoaded && _lastVerticalFilters != chatState.useVerticalFilters) {
      _lastVerticalFilters = chatState.useVerticalFilters;
      WidgetsBinding.instance.addPostFrameCallback((_) => _saveLayoutPrefs());
    }

    // Persist when forum view-as-messages preference changes (§22.10).
    final currentForumPrefs = chatState.forumViewAsMessagesKeys;
    if (_layoutLoaded && _lastForumViewPrefs != null &&
        !setEquals(_lastForumViewPrefs!, currentForumPrefs)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _saveLayoutPrefs());
    }
    _lastForumViewPrefs = currentForumPrefs;

    // Show loading while engine initializes.
    if (!appState.initialized) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: appState.initError != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
                    const SizedBox(height: 16),
                    Text('Failed to initialize engine',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Text(appState.initError!,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                )
              : const CircularProgressIndicator(),
        ),
      );
    }

    // Show auth screen if there's an active auth flow.
    if (authState.hasActiveFlow && !authState.isReady) {
      return const AuthScreen();
    }

    // Show add-account prompt if no accounts exist.
    if (appState.accounts.isEmpty) {
      return _NoAccountsScreen(
        onAdd: (platform) {
          final id = appState.addAccount(platform);
          authState.startAuth(id);
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final windowWidth = constraints.maxWidth;
        // Show vertical filters sidebar when folders exist, preference is sidebar
        // mode, and window is wide enough (spec §18.12: ≥452px for sidebar to fit,
        // but we also need room for dialogs column).
        final showFilters = chatState.hasFolders &&
            chatState.useVerticalFilters &&
            windowWidth > _oneColumnBreak + _filtersWidth;
        final bodyWidth = windowWidth - (showFilters ? _filtersWidth : 0.0);
        final mode = _layoutMode(bodyWidth);

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: Stack(
            children: [
              _buildLayout(context, mode, bodyWidth, windowWidth, showFilters, chatState),
              Positioned(
                left: 0,
                bottom: 0,
                child: _ConnectionStateWidget(accountId: appState.activeAccountId),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLayout(BuildContext context, LayoutMode mode, double bodyWidth,
      double windowWidth, bool showFilters, ChatState chatState) {
    Widget layout;
    switch (mode) {
      case LayoutMode.oneColumn:
        layout = _buildOneColumn(context, chatState);
      case LayoutMode.twoColumn:
        layout = _buildTwoColumn(context, bodyWidth, showFilters, chatState);
      case LayoutMode.threeColumn:
        layout = _buildThreeColumn(context, bodyWidth, showFilters, chatState);
    }

    // Now-playing media player bar (AyuGram Media::Player::Widget) — sits at the
    // top of the content area whenever a voice/music track is loaded. The bar
    // collapses itself to zero height when nothing is playing, so wrapping
    // unconditionally is safe. Call / export top bars stack above it.
    layout = Column(
      children: [
        const MusicPlayerBar(),
        Expanded(child: layout),
      ],
    );

    final groupCall = chatState.activeGroupCall;
    final personalCall = chatState.activePersonalCall;
    final hasActiveCall = (groupCall != null && groupCall.active) || personalCall != null;

    if (hasActiveCall) {
      final Widget callBar;
      final accountId = chatState.activeChat?.accountId
          ?? context.read<AppState>().activeAccountId;
      if (personalCall != null) {
        callBar = MinimisedCallBar(
          isPersonalCall: true,
          peerName: personalCall.peerName,
          peerFirstName: personalCall.peerFirstName,
          isSelfMuted: personalCall.isMuted,
          isConnecting: personalCall.isConnecting,
          signalQuality: personalCall.signalQuality,
          callStartTime: personalCall.startTime,
          onHangup: () {
            if (accountId.isNotEmpty && personalCall.callId.isNotEmpty) {
              context.read<EngineService>().endCall(accountId, personalCall.callId);
            }
            chatState.setActivePersonalCall(null);
          },
          onToggleMute: () {
            if (accountId.isNotEmpty && personalCall.callId.isNotEmpty) {
              context.read<EngineService>().setCallMuted(
                accountId, personalCall.callId, !personalCall.isMuted);
            }
            chatState.setActivePersonalCall(
              personalCall.copyWith(isMuted: !personalCall.isMuted),
            );
          },
        );
      } else {
        final selfUserId = context.read<AppState>().activeAccount?.selfUserId ?? '';
        GroupCallParticipant? selfP;
        for (final p in groupCall!.participants) {
          if (p.userId == selfUserId) {
            selfP = p;
            break;
          }
        }
        final selfMuted = selfP?.isMuted ?? false;
        // muted + can't self-unmute → admin force-muted (RaisedHand if hand up).
        final forceMuted = selfP != null &&
            selfP.isMuted && !selfP.canSelfUnmute && selfP.raisedHandRating == 0;
        final raisedHand = selfP != null &&
            selfP.isMuted && !selfP.canSelfUnmute && selfP.raisedHandRating > 0;
        // Not yet in the participant list = the call instance is still joining.
        final isConnecting = selfP == null;
        final isCanManage = chatState.activeChat?.isAdmin ?? false;
        // Loudest participant drives the bar's audio-level blobs.
        double audioLevel = 0.0;
        for (final p in groupCall.participants) {
          if (p.audioLevel > audioLevel) audioLevel = p.audioLevel;
        }
        // Duration since the local user joined (selfP.date is a unix timestamp).
        final callStartTime = (selfP != null && selfP.date > 0)
            ? DateTime.fromMillisecondsSinceEpoch(selfP.date * 1000)
            : null;
        callBar = MinimisedCallBar(
          peerName: groupCall.title.isNotEmpty
              ? groupCall.title
              : chatState.activeChat?.title ?? 'Group Call',
          participants: groupCall.participants,
          isSelfMuted: selfMuted,
          isForceMuted: forceMuted,
          isRaisedHand: raisedHand,
          isConnecting: isConnecting,
          isCanManage: isCanManage,
          audioLevel: audioLevel,
          callStartTime: callStartTime,
          callId: groupCall.callId,
          onTap: () {
            // Reopen the full call panel (AyuGram top bar → showInfoPanel).
            showGroupCallPanel(
              context,
              groupCall!,
              chatTitle: chatState.activeChat?.title ?? '',
              isCanManage: isCanManage,
              isSelfMuted: selfMuted,
              isForceMuted: forceMuted,
              isRaisedHand: raisedHand,
              callStartTime: callStartTime,
            );
          },
          onHangup: () {
            // _CallBarHangupButton leaves/ends the call itself via callId +
            // isCanManage; just clear local state so the bar disappears.
            chatState.setActiveGroupCall(null);
          },
          onToggleMute: () {
            if (accountId.isNotEmpty && groupCall.callId.isNotEmpty) {
              context.read<EngineService>().setCallMuted(
                accountId, groupCall.callId, !selfMuted);
            }
            final updatedParticipants = groupCall!.participants.map((p) {
              if (p.userId == selfUserId) {
                return GroupCallParticipant(
                  userId: p.userId, displayName: p.displayName,
                  isMuted: !p.isMuted, mutedByMe: p.mutedByMe,
                  isSpeaking: p.isSpeaking, sounding: p.sounding,
                  hasVideo: p.hasVideo, avatarPath: p.avatarPath,
                  canSelfUnmute: p.canSelfUnmute,
                  raisedHandRating: p.raisedHandRating,
                  volume: p.volume, audioLevel: p.audioLevel,
                  ssrc: p.ssrc,
                  additionalSounding: p.additionalSounding,
                  additionalSpeaking: p.additionalSpeaking,
                  lastActive: p.lastActive, date: p.date,
                );
              }
              return p;
            }).toList();
            chatState.setActiveGroupCall(GroupCallInfo(
              callId: groupCall.callId, chatId: groupCall.chatId,
              title: groupCall.title,
              participantsCount: groupCall.participantsCount,
              participants: updatedParticipants,
              active: groupCall.active, isRtmp: groupCall.isRtmp,
              scheduleDate: groupCall.scheduleDate, origin: groupCall.origin,
            ));
          },
        );
      }
      layout = Column(
        children: [
          _SlideWrapCallBar(visible: true, child: callBar),
          Expanded(child: layout),
        ],
      );
    }

    if (chatState.exportActive) {
      layout = Column(
        children: [
          const ExportTopBar(),
          Expanded(child: layout),
        ],
      );
    }

    if (_chatSwitchActive) {
      final history = chatState.collectChatOpenHistory();
      if (history.length < 2) {
        ShortcutSystem.instance.resume();
        _chatSwitchActive = false;
        return layout;
      }
      return Stack(
        children: [
          layout,
          Positioned.fill(
            child: ChatSwitchOverlay(
              chats: history,
              initialIndex: _chatSwitchReverse ? history.length - 1 : 0,
              onChosen: (chat) {
                ShortcutSystem.instance.resume();
                setState(() => _chatSwitchActive = false);
                chatState.openChat(chat);
              },
              onRemove: (chat) {
                chatState.removeChatFromOpenHistory(chat.chatId);
              },
              onCancel: () {
                ShortcutSystem.instance.resume();
                setState(() => _chatSwitchActive = false);
              },
            ),
          ),
        ],
      );
    }

    return layout;
  }

  /// Single panel: show either chat list or chat view, with section transition
  /// animation (spec §1: horizontal slide with content snapshot crossfade).
  Widget _buildOneColumn(BuildContext context, ChatState chatState) {
    final showForumTopics = chatState.isViewingForum && chatState.activeTopicId == null;
    final showChat = chatState.activeChat != null && !showForumTopics;
    final showInfo = _infoOpen && showChat;
    final forward = _navForward;

    final String currentKey = showInfo ? 'info' : (showChat ? 'chat' : (showForumTopics ? 'forumtopics' : 'chatlist'));

    return ClipRect(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        layoutBuilder: (currentChild, previousChildren) {
          return Stack(
            fit: StackFit.expand,
            children: [
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          );
        },
        transitionBuilder: (child, animation) {
          final isIncoming = child.key == ValueKey(currentKey);
          final beginOffset = isIncoming
              ? Offset(forward ? 1.0 : -1.0, 0)
              : Offset(forward ? -0.3 : 0.3, 0);
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCirc,
          );
          return SlideTransition(
            position: Tween<Offset>(begin: beginOffset, end: Offset.zero)
                .animate(curved),
            child: FadeTransition(
              opacity: curved,
              child: child,
            ),
          );
        },
        child: showInfo
            ? InfoPanel(
                key: const ValueKey('info'),
                onClose: _closeInfo,
                wrapMode: InfoWrapMode.narrow,
              )
            : showChat
                ? ChatView(
                    key: const ValueKey('chat'),
                    onBack: () {
                      if (chatState.forumParentChat != null && chatState.activeTopicId != null) {
                        chatState.goBackFromTopic();
                      } else {
                        chatState.closeChat();
                      }
                    },
                    showBackButton: true,
                    hideTopBarDivider: _oneColumnAnimating,
                    onToggleInfo: _toggleInfo,
                    isInfoOpen: _infoOpen,
                  )
                : ChatListPanel(
                    key: const ValueKey('chatlist'),
                    onOpenDrawer: () => _openDrawer(context),
                    showHamburger: true,
                  ),
      ),
    );
  }

  Widget _buildTwoColumn(BuildContext context, double bodyWidth,
      bool showFilters, ChatState chatState) {
    final maxDialogs = bodyWidth - _chatMin;
    final dialogsWidth = (bodyWidth * _dialogsWidthRatio).clamp(_dialogsMin, maxDialogs);

    final columns = Row(
      children: [
        if (showFilters)
          FilterColumn(
            onOpenDrawer: () => _openDrawer(context),
          ),
        if (showFilters) _ColumnShadow(),
        AnimatedContainer(
          duration: _isDragging ? Duration.zero : const Duration(milliseconds: 180),
          curve: Curves.easeOutCirc,
          width: dialogsWidth,
          child: ChatListPanel(
            showHamburger: !showFilters,
            onOpenDrawer: showFilters ? null : () => _openDrawer(context),
            filterSidebarVisible: showFilters,
          ),
        ),
        _ColumnShadow(),
        _ResizeHandle(
          onDragStart: () => setState(() => _isDragging = true),
          onDragEnd: () {
            setState(() => _isDragging = false);
            _saveLayoutPrefs();
          },
          onDrag: (dx) {
            setState(() {
              final raw = (bodyWidth * _dialogsWidthRatio + dx);
              final newWidth = raw.clamp(_dialogsMin, maxDialogs);
              _dialogsWidthRatio = newWidth / bodyWidth;
            });
          },
        ),
        Expanded(
          child: Stack(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final wideChat = constraints.maxWidth >= _wideChatThreshold;
                  return chatState.activeChat != null
                      ? ChatView(
                          showBackButton: false,
                          onToggleInfo: _toggleInfo,
                          isInfoOpen: _infoOpen,
                          wideChatMode: wideChat,
                        )
                      : _EmptyChatPlaceholder();
                },
              ),
              if (_infoOpen && chatState.activeChat != null)
                _InfoLayerOverlay(onClose: _closeInfo),
            ],
          ),
        ),
      ],
    );

    return columns;
  }

  /// Three columns: dialogs + chat + info panel.
  /// Implements the Telegram Desktop three-column shrink algorithm (spec §1
  /// SessionController::shrinkDialogsAndThirdColumns).
  Widget _buildThreeColumn(BuildContext context, double bodyWidth,
      bool showFilters, ChatState chatState) {
    var dw = (bodyWidth * _dialogsWidthRatio).clamp(_dialogsMin, bodyWidth);
    var tw = _thirdColumnWidth.clamp(_thirdMin, _thirdMax);

    if (dw + tw + _chatMin > bodyWidth) {
      // Pin chat to 380px minimum, divide the rest proportionally.
      final available = bodyWidth - _chatMin;
      final total = dw + tw;
      if (total > 0) {
        tw = available * tw / total;
        dw = available * dw / total;
      }
      // Step 3: Clamp — ensure both columns meet minimums.
      if (tw < _thirdMin) {
        tw = _thirdMin;
        dw = bodyWidth - _thirdMin - _chatMin;
      } else if (dw < _dialogsMin) {
        dw = _dialogsMin;
        tw = bodyWidth - _dialogsMin - _chatMin;
      }
      tw = tw.clamp(_thirdMin, _thirdMax);
      dw = dw.clamp(_dialogsMin, bodyWidth);
    }

    return Row(
      children: [
        // Filters sidebar (when folders exist).
        if (showFilters)
          FilterColumn(
            onOpenDrawer: () => _openDrawer(context),
          ),
        if (showFilters) _ColumnShadow(),
        // Dialogs column.
        AnimatedContainer(
          duration: _isDragging ? Duration.zero : const Duration(milliseconds: 180),
          curve: Curves.easeOutCirc,
          width: dw,
          child: ChatListPanel(
            showHamburger: !showFilters,
            onOpenDrawer: showFilters ? null : () => _openDrawer(context),
            filterSidebarVisible: showFilters,
          ),
        ),
        // Dialogs-chat shadow separator + resize handle.
        _ColumnShadow(),
        _ResizeHandle(
          onDragStart: () => setState(() => _isDragging = true),
          onDragEnd: () {
            setState(() => _isDragging = false);
            _saveLayoutPrefs();
          },
          onDrag: (dx) {
            setState(() {
              final raw = dw + dx;
              final maxDw = bodyWidth - _chatMin - tw;
              _dialogsWidthRatio = raw.clamp(_dialogsMin, maxDw) / bodyWidth;
            });
          },
        ),
        // Chat column (Expanded absorbs remaining space, avoiding overflow
        // from shadow/handle pixels and enabling smooth column animations).
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wideChat = constraints.maxWidth >= _wideChatThreshold;
              return chatState.activeChat != null
                  ? ChatView(
                      showBackButton: false,
                      onToggleInfo: _toggleInfo,
                      isInfoOpen: _infoOpen,
                      wideChatMode: wideChat,
                    )
                  : _EmptyChatPlaceholder();
            },
          ),
        ),
        // Chat-info shadow separator. Stays visible during close animation,
        // removed when animation reaches dismissed state (spec §1 _thirdShadow).
        if (!_thirdColumnAnim.isDismissed && chatState.activeChat != null) ...[
          _ColumnShadow(),
          // Resize handle only while info is open (not during close animation).
          if (_infoOpen)
            _ResizeHandle(
              onDragStart: () => setState(() => _isDragging = true),
              onDragEnd: () {
                setState(() => _isDragging = false);
                _saveLayoutPrefs();
              },
              onDrag: (dx) {
                setState(() {
                  _thirdColumnWidth = (tw - dx).clamp(_thirdMin, _thirdMax);
                });
              },
            ),
          AnimatedBuilder(
            animation: _thirdColumnCurved,
            builder: (context, child) {
              return ClipRect(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: _thirdColumnCurved.value,
                  child: child,
                ),
              );
            },
            child: SizedBox(
              width: tw,
              child: InfoPanel(onClose: _closeInfo),
            ),
          ),
        ],
      ],
    );
  }

  void _openDrawer(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: context.palette.layerBg,
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final slide = Tween<Offset>(
          begin: const Offset(-1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ));
        return SlideTransition(position: slide, child: child);
      },
      pageBuilder: (_, __, ___) => Align(
        alignment: Alignment.centerLeft,
        child: Material(
          elevation: 0,
          color: Colors.transparent,
          child: SizedBox(
            width: 274,
            height: height,
            child: const HamburgerDrawer(),
          ),
        ),
      ),
    );
  }
}

/// Spec §1 column shadow separator. 1px fillRect with shadowFg color.
/// Light theme: #00000018 (black at 9.4% opacity).
/// Dark theme: #04080e56 (near-black at 33.7% opacity).
/// No animation — static paint, toggled by show/hide.
class _InfoLayerOverlay extends StatelessWidget {
  final VoidCallback onClose;

  const _InfoLayerOverlay({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onClose,
      child: Container(
        color: context.palette.layerBg,
        alignment: Alignment.topCenter,
        padding: const EdgeInsets.only(left: 48, right: 48, top: 20),
        child: GestureDetector(
          onTap: () {},
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 392),
            child: InfoPanel(
              onClose: onClose,
              wrapMode: InfoWrapMode.layer,
            ),
          ),
        ),
      ),
    );
  }
}

class _SlideWrapCallBar extends StatefulWidget {
  final bool visible;
  final Widget child;

  const _SlideWrapCallBar({required this.visible, required this.child});

  @override
  State<_SlideWrapCallBar> createState() => _SlideWrapCallBarState();
}

class _SlideWrapCallBarState extends State<_SlideWrapCallBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: widget.visible ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(_SlideWrapCallBar old) {
    super.didUpdateWidget(old);
    if (widget.visible != old.visible) {
      if (widget.visible) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
      axisAlignment: -1.0,
      child: widget.child,
    );
  }
}

class _ColumnShadow extends StatelessWidget {
  const _ColumnShadow();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      color: context.palette.shadowFg,
    );
  }
}

/// Drag handle between columns (invisible 4px hit target, no visual).
class _ResizeHandle extends StatelessWidget {
  final void Function(double dx) onDrag;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  const _ResizeHandle({required this.onDrag, this.onDragStart, this.onDragEnd});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: onDragStart != null ? (_) => onDragStart!() : null,
      onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
      onHorizontalDragEnd: onDragEnd != null ? (_) => onDragEnd!() : null,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: const SizedBox(width: 4, height: double.infinity),
      ),
    );
  }
}

/// Placeholder shown when no chat is selected — spec §35.6.
/// Service-message style bubble, centred in the chat pane.
class _EmptyChatPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      color: palette.windowBg,
      child: Center(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 3, 12, 4),
          decoration: BoxDecoration(
            color: palette.msgServiceBg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            'Select a chat to start messaging',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: palette.msgServiceFg,
            ),
          ),
        ),
      ),
    );
  }
}

/// Screen shown when no accounts exist.
class _NoAccountsScreen extends StatelessWidget {
  final void Function(String platform) onAdd;

  const _NoAccountsScreen({required this.onAdd});

  static const _platforms = [
    ('telegram', 'Telegram', Icons.send),
    ('matrix', 'Matrix', Icons.grid_view),
    ('xmpp', 'XMPP', Icons.message),
    ('irc', 'IRC', Icons.tag),
    ('bale', 'Bale', Icons.chat),
    ('rubika', 'Rubika', Icons.radio_button_checked),
    ('deltachat', 'Delta Chat', Icons.email),
    ('mumble', 'Mumble', Icons.headset_mic),
    ('teamspeak', 'TeamSpeak', Icons.headset),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Welcome to UniClient',
                            style: theme.textTheme.headlineMedium),
                        const SizedBox(height: 8),
                        Text('Add an account to get started',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.textTheme.bodySmall?.color,
                            )),
                        const SizedBox(height: 32),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          alignment: WrapAlignment.center,
                          children: _platforms.map((p) => _PlatformButton(
                            label: p.$2,
                            icon: p.$3,
                            onTap: () => onAdd(p.$1),
                          )).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ConnectionStateWidget extends StatefulWidget {
  final String accountId;
  const _ConnectionStateWidget({required this.accountId});

  @override
  State<_ConnectionStateWidget> createState() => _ConnectionStateWidgetState();
}

class _ConnectionStateWidgetState extends State<_ConnectionStateWidget>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const _kConnectingStateDelay = Duration(milliseconds: 1000);
  static const _kIgnoreStartConnectingFor = Duration(milliseconds: 3000);
  static const _animDuration = Duration(milliseconds: 150);
  static const _minWaitDuration = Duration(milliseconds: 4000);

  late final AnimationController _visibilityAnim;
  late final AnimationController _slideAnim;
  late final AnimationController _contentWidthAnim;
  Timer? _showTimer;
  Timer? _waitTimer;
  Timer? _countdownTimer;
  bool _shouldShow = false;
  bool _isHovered = false;
  bool _isWaiting = false;
  int _reconnectCountdown = 0;
  ConnState? _lastState;
  DateTime? _connectingStartedAt;
  final DateTime _appStartTime = DateTime.now();
  bool _appExposed = true;
  String _retainedText = '';
  bool _textExpanded = false;

  @override
  void initState() {
    super.initState();
    _visibilityAnim = AnimationController(vsync: this, duration: _animDuration);
    _slideAnim = AnimationController(vsync: this, duration: _animDuration);
    _contentWidthAnim = AnimationController(vsync: this, duration: _animDuration);
    _contentWidthAnim.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) {
        setState(() => _retainedText = '');
      }
    });
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _showTimer?.cancel();
    _waitTimer?.cancel();
    _countdownTimer?.cancel();
    _visibilityAnim.dispose();
    _slideAnim.dispose();
    _contentWidthAnim.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final exposed = state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    if (_appExposed != exposed) {
      _appExposed = exposed;
      if (mounted) setState(() {});
    }
  }

  void _startWaitCountdown(int waitSeconds) {
    _isWaiting = true;
    _reconnectCountdown = waitSeconds;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _reconnectCountdown--;
        if (_reconnectCountdown <= 0) {
          _tryReconnect();
        }
      });
    });
  }

  void _cancelWait() {
    _waitTimer?.cancel();
    _waitTimer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _isWaiting = false;
    _reconnectCountdown = 0;
  }

  void _tryReconnect() {
    _cancelWait();
    showProxiesDialog(context);
  }

  void _syncVisibility(ConnState state, int engineWaitSeconds) {
    if (state == _lastState) return;
    final oldState = _lastState;
    _lastState = state;

    final proxyEnabled = context.read<AppState>().proxyMode > 0;
    final wantVisible = _appExposed &&
        (proxyEnabled ||
            state == ConnState.connecting ||
            state == ConnState.disconnected ||
            state == ConnState.unstable);

    if (state == ConnState.connecting &&
        (oldState == null || oldState == ConnState.connected)) {
      final now = DateTime.now();
      if (_connectingStartedAt == null) {
        _connectingStartedAt = now;
        _showTimer?.cancel();
        _showTimer = Timer(_kConnectingStateDelay, () {
          _showTimer = null;
          if (!mounted) return;
          _lastState = null;
          setState(() {});
        });
        return;
      }
      final applyAt = _connectingStartedAt!.add(_kConnectingStateDelay);
      final ignoreUntil = _appStartTime.add(_kIgnoreStartConnectingFor);
      final earliest = applyAt.isAfter(ignoreUntil) ? applyAt : ignoreUntil;
      if (now.isBefore(earliest)) {
        _showTimer?.cancel();
        _showTimer = Timer(earliest.difference(now), () {
          _showTimer = null;
          if (!mounted) return;
          _lastState = null;
          setState(() {});
        });
        return;
      }
    }

    if (state == ConnState.connected) {
      _connectingStartedAt = null;
    }

    if (wantVisible && !_shouldShow && _showTimer == null) {
      _shouldShow = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _visibilityAnim.forward();
        _slideAnim.forward();
      });
    } else if (!wantVisible) {
      _showTimer?.cancel();
      _showTimer = null;
      _cancelWait();
      _connectingStartedAt = null;
      if (_shouldShow) {
        _shouldShow = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _visibilityAnim.reverse();
          _slideAnim.reverse();
        });
      }
    }

    if ((state == ConnState.disconnected || state == ConnState.unstable) &&
        oldState != ConnState.disconnected &&
        oldState != ConnState.unstable) {
      _cancelWait();
      _waitTimer = Timer(_minWaitDuration, () {
        _waitTimer = null;
        if (!mounted) return;
        if (_lastState == ConnState.disconnected ||
            _lastState == ConnState.unstable) {
          setState(() {
            final wait = engineWaitSeconds > 0 ? engineWaitSeconds : 5;
            _startWaitCountdown(wait);
          });
        }
      });
    } else if (state == ConnState.connected) {
      _cancelWait();
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final state = appState.connStateFor(widget.accountId);
    final p = context.palette;
    final proxyEnabled = appState.proxyMode > 0;

    final engineWaitSeconds = appState.connWaitSecondsFor(widget.accountId);
    _syncVisibility(state, engineWaitSeconds);

    if (!_shouldShow && !_visibilityAnim.isAnimating) {
      return const SizedBox.shrink();
    }

    if (!_appExposed) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: Listenable.merge([_visibilityAnim, _slideAnim]),
      builder: (context, child) {
        final slideOffset = (1.0 - _slideAnim.value) * 30.0;
        return Transform.translate(
          offset: Offset(0, slideOffset),
          child: Opacity(
            opacity: _visibilityAnim.value,
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            onTap: _tryReconnect,
            behavior: HitTestBehavior.opaque,
            child: _buildPill(state, p, proxyEnabled),
          ),
        ),
      ),
    );
  }

  Widget _buildPill(ConnState state, TelegramPalette p, bool proxyEnabled) {
    final showProgress = state != ConnState.connected;
    final wantText = showProgress && (_isHovered || _isWaiting);

    final String text;
    if (_isWaiting && _reconnectCountdown > 0) {
      text = 'Reconnect in $_reconnectCountdown s...';
    } else {
      text = 'Connecting...';
    }

    if (wantText && !_textExpanded) {
      _textExpanded = true;
      _retainedText = text;
      _contentWidthAnim.forward();
    } else if (!wantText && _textExpanded) {
      _textExpanded = false;
      _contentWidthAnim.reverse();
    } else if (wantText) {
      _retainedText = text;
    }

    final displayText = _retainedText;
    final hasText = displayText.isNotEmpty;

    return AnimatedBuilder(
      animation: _contentWidthAnim,
      builder: (context, _) {
        final t = _contentWidthAnim.value;
        final hPad = 5.0 + (13.0 * t);

        return CustomPaint(
          painter: _ConnectingPillPainter(
            bgColor: p.windowBg,
            shadowColor: p.windowShadowFg,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showProgress)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: p.menuIconFg,
                    ),
                  ),
                if (hasText) ...[
                  SizedBox(width: 8 * t),
                  ClipRect(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      widthFactor: t,
                      child: Opacity(
                        opacity: t,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              displayText,
                              style: TextStyle(fontSize: 13, color: p.menuIconFg),
                            ),
                            if (_isWaiting)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: GestureDetector(
                                  onTap: _tryReconnect,
                                  child: Text(
                                    'Try now',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: p.windowBgActive,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                if (proxyEnabled) ...[
                  if (showProgress || hasText) SizedBox(width: 4 * (hasText ? t : 1.0)),
                  Icon(
                    Icons.shield_outlined,
                    size: 16,
                    color: p.windowBgActive,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ConnectingPillPainter extends CustomPainter {
  final Color bgColor;
  final Color shadowColor;

  _ConnectingPillPainter({required this.bgColor, required this.shadowColor});

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height / 2;
    final body = RRect.fromLTRBR(0, 0, size.width, size.height, Radius.circular(r));

    final shadowPaint = Paint()
      ..color = shadowColor
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
    canvas.drawRRect(body.shift(const Offset(0, 1)), shadowPaint);

    final bgPaint = Paint()..color = bgColor;
    canvas.drawRRect(body, bgPaint);
  }

  @override
  bool shouldRepaint(_ConnectingPillPainter old) =>
      old.bgColor != bgColor || old.shadowColor != shadowColor;
}

class _PlatformButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _PlatformButton({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.cardColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 120,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 32, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              Text(label, style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/foundation.dart';

import '../bridge/engine_service.dart';
import '../l10n/strings.dart';
import '../models/engine_models.dart';

enum ForwardMethod { native, resendAsOwn }

enum AyuForwardPhase { preparing, downloading, sending, finished }

class ForwardChunk {
  final ForwardMethod method;
  final List<CachedMessage> messages;
  const ForwardChunk(this.method, this.messages);
}

class AyuForwardStrings {
  static String statusPreparing() => TrStrings.lngAyuForwardStatusPreparing();
  static String statusForwarding() => TrStrings.lngAyuForwardStatusForwarding();
  static String statusLoadingMedia() => TrStrings.lngAyuForwardStatusLoadingMedia();
  static String statusFinished() => TrStrings.lngAyuForwardStatusFinished();
  static String sentCount(int sent, int total) => TrStrings.lngAyuForwardStatusSentCount(sent, total);
  static String chunkCount(int chunk, int total) => TrStrings.lngAyuForwardStatusChunkCount(chunk, total);
}

class ForwardProgress extends ChangeNotifier {
  AyuForwardPhase _phase = AyuForwardPhase.preparing;
  int _sentCount = 0;
  int _totalCount = 0;
  int _chunkIndex = 0;
  int _totalChunks = 0;
  bool _cancelled = false;
  bool _isDisposed = false;

  AyuForwardPhase get phase => _phase;
  int get sentCount => _sentCount;
  int get totalCount => _totalCount;
  int get chunkIndex => _chunkIndex;
  int get totalChunks => _totalChunks;
  bool get isCancelled => _cancelled;
  bool get isDisposed => _isDisposed;

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_isDisposed) return;
    super.notifyListeners();
  }

  String get statusText {
    switch (_phase) {
      case AyuForwardPhase.preparing:
        return AyuForwardStrings.statusPreparing();
      case AyuForwardPhase.sending:
        return AyuForwardStrings.statusForwarding();
      case AyuForwardPhase.downloading:
        return AyuForwardStrings.statusLoadingMedia();
      case AyuForwardPhase.finished:
        return AyuForwardStrings.statusFinished();
    }
  }

  String get detailText {
    if (_phase == AyuForwardPhase.downloading) return '';
    if (_totalCount == 0) return '';
    final msg = AyuForwardStrings.sentCount(_sentCount, _totalCount);
    if (_totalChunks > 1) {
      return '$msg • ${AyuForwardStrings.chunkCount(_chunkIndex, _totalChunks)}';
    }
    return msg;
  }

  void cancel() {
    _cancelled = true;
    _phase = AyuForwardPhase.finished;
    notifyListeners();
  }

  void update({
    AyuForwardPhase? phase,
    int? sent,
    int? total,
    int? chunk,
    int? chunks,
  }) {
    if (phase != null) _phase = phase;
    if (sent != null) _sentCount = sent;
    if (total != null) _totalCount = total;
    if (chunk != null) _chunkIndex = chunk;
    if (chunks != null) _totalChunks = chunks;
    notifyListeners();
  }
}

class AyuForward {
  static final Map<String, ForwardProgress> _activeForwards = {};

  static ForwardProgress? getProgress(String peerId) => _activeForwards[peerId];
  static bool isForwarding(String peerId) {
    final p = _activeForwards[peerId];
    if (p == null) return false;
    // totalCount is now reset per-chunk (0 during the brief preparing window
    // before the first chunk seeds it), so detect an active forward by the
    // chunk count instead of the per-chunk message count.
    return p.phase != AyuForwardPhase.finished
        && p.chunkIndex <= p.totalChunks
        && !p.isCancelled
        && (p.totalChunks > 0 || p.phase == AyuForwardPhase.downloading);
  }

  static void _scheduleCleanup(String toChatId) {
    Future.delayed(const Duration(seconds: 2), () {
      final p = _activeForwards.remove(toChatId);
      if (p == null || p.isDisposed) return;
      if (!p.hasListeners) {
        p.dispose();
      }
    });
  }

  static void startNativeForward(String toChatId, ForwardProgress progress, int total) {
    _activeForwards[toChatId] = progress;
    progress.update(
      phase: AyuForwardPhase.sending,
      total: total,
      chunks: 1,
      chunk: 1,
    );
  }

  static void finishNativeForward(String toChatId, ForwardProgress progress, int sent) {
    progress.update(phase: AyuForwardPhase.finished, sent: sent);
    _scheduleCleanup(toChatId);
  }

  static bool isMessageRestricted(CachedMessage msg) {
    if (msg.isDeleted) return true;
    if (msg.unsupportedTTL) return true;
    if (msg.ttlSeconds > 0) return true;
    if (msg.noForwards) return true;
    return false;
  }

  static bool isChatRestricted(ChatInfo chat) => chat.noForwards;

  /// Polymorphic AyuNoForwards check: returns true if forwarding is restricted
  /// at the chat level (channel/group noForwards flag) or message level
  /// (per-message noForwards flag set when server indicated restriction).
  static bool isAyuNoForwards({
    ChatInfo? chat,
    CachedMessage? message,
  }) {
    if (chat != null && chat.noForwards) return true;
    if (message != null && message.noForwards) return true;
    return false;
  }

  /// Mirrors C++ `isFullAyuForwardNeeded(item)` (ayu_forward.cpp:233-235):
  ///   `item->from()->isAyuNoForwards() || item->history()->peer->isAyuNoForwards()`
  /// True when the message's SENDER has the no-forwards flag, or the source
  /// chat has it. AyuGram always evaluates this on a SINGLE message — the FIRST
  /// forwarded message (`draft.items.front()`) — never the whole batch, so this
  /// takes one message, not a list. Used to decide whether the ENTIRE batch is
  /// re-sent as own (full AyuForward) vs. routed through per-chunk handling.
  static bool isFullAyuForwardNeeded(CachedMessage message, ChatInfo sourceChat) {
    return message.senderNoForwards || isChatRestricted(sourceChat);
  }

  static List<ForwardChunk> buildChunks(
    List<CachedMessage> messages,
    ChatInfo sourceChat,
  ) {
    // Full AyuForward: the ENTIRE batch is re-sent as own ONLY when
    // `isFullAyuForwardNeeded(items.front())` holds — the source chat has
    // no-forwards, OR the FIRST forwarded message's sender has it. AyuGram keys
    // this whole-batch decision off `draft.items.front()` ONLY
    // (apiwrap.cpp:3487, share_box.cpp:1757, context_menu.cpp:842), never a
    // per-message scan. In a multi-sender forward through an unrestricted chat
    // where a LATER message's sender is restricted but the first isn't, AyuGram
    // still forwards natively (per-chunk path below), preserving the "Forwarded
    // from" attribution — using `.any` here would wrongly strip attribution and
    // re-upload every message. Mirrors C++ isFullAyuForwardNeeded =
    // item->from()->isAyuNoForwards() || item->history()->peer->isAyuNoForwards()
    // (ayu_forward.cpp:233-235), consistent with needsIntelligentForward.
    final fullResendNeeded = messages.isNotEmpty
        ? isFullAyuForwardNeeded(messages.first, sourceChat)
        : isChatRestricted(sourceChat);
    if (fullResendNeeded) {
      return [ForwardChunk(ForwardMethod.resendAsOwn, messages)];
    }

    final chunks = <ForwardChunk>[];
    ForwardMethod? currentMethod;
    var currentMsgs = <CachedMessage>[];

    for (final msg in messages) {
      final method = isMessageRestricted(msg)
          ? ForwardMethod.resendAsOwn
          : ForwardMethod.native;
      if (method != currentMethod && currentMsgs.isNotEmpty) {
        chunks.add(ForwardChunk(currentMethod!, currentMsgs));
        currentMsgs = [];
      }
      currentMethod = method;
      currentMsgs.add(msg);
    }
    if (currentMsgs.isNotEmpty) {
      chunks.add(ForwardChunk(currentMethod!, currentMsgs));
    }
    return chunks;
  }

  /// Groups messages by their groupedId (album membership). Messages with the
  /// same non-empty groupedId are batched together at the position of the first
  /// occurrence. Non-album messages get their own single-element group.
  /// Preserves chronological order (matches C++ prepareMedia).
  static List<List<CachedMessage>> _groupByAlbum(List<CachedMessage> messages) {
    final groups = <List<CachedMessage>>[];
    final albumMap = <String, List<CachedMessage>>{};
    final seenAlbums = <String>{};

    for (final msg in messages) {
      if (msg.groupedId.isNotEmpty) {
        albumMap.putIfAbsent(msg.groupedId, () => []).add(msg);
        if (seenAlbums.add(msg.groupedId)) {
          groups.add(albumMap[msg.groupedId]!);
        }
      } else {
        groups.add([msg]);
      }
    }
    return groups;
  }

  static Future<void> intelligentForward({
    required EngineService engine,
    required String accountId,
    required String sourceChatId,
    required List<CachedMessage> messages,
    required String toChatId,
    required ChatInfo sourceChat,
    bool dropAuthor = false,
    bool dropCaptions = false,
    bool silent = false,
    int scheduleDate = 0,
    ForwardProgress? progress,
  }) async {
    final chunks = buildChunks(messages, sourceChat);

    if (progress != null) {
      _activeForwards[toChatId] = progress;
      // Per-chunk progress: do NOT seed a global total here. AyuGram resets
      // state->totalMessages / state->sentMessages for every chunk inside the
      // loop (ayu_forward.cpp:291-306), so each chunk shows its own "N/N"
      // rather than a cumulative count across the whole batch.
      progress.update(
        phase: AyuForwardPhase.preparing,
        chunks: chunks.length,
      );
    }

    try {
      for (int i = 0; i < chunks.length; i++) {
        if (progress?.isCancelled == true) break;
        final chunk = chunks[i];

        final phase = chunk.method == ForwardMethod.resendAsOwn
            ? AyuForwardPhase.downloading
            : AyuForwardPhase.sending;
        // Reset progress for this chunk: total = this chunk's size, sent = 0
        // (mirrors state->totalMessages = chunk.items.size(); sentMessages = 0).
        progress?.update(
          phase: phase,
          chunk: i + 1,
          total: chunk.messages.length,
          sent: 0,
        );

        switch (chunk.method) {
          case ForwardMethod.native:
            progress?.update(phase: AyuForwardPhase.sending);
            final msgIds = chunk.messages.map((m) => m.msgId).toList();
            await engine.forwardMessages(
              accountId, sourceChatId, msgIds, toChatId,
              dropAuthor: dropAuthor,
              dropCaptions: dropCaptions,
              silent: silent,
              scheduleDate: scheduleDate,
            );
            // Chunk finished: sent = total (state->sentMessages = totalMessages).
            progress?.update(sent: chunk.messages.length);
          case ForwardMethod.resendAsOwn:
            final albumGroups = _groupByAlbum(chunk.messages);
            int sentInChunk = 0;
            for (final group in albumGroups) {
              if (progress?.isCancelled == true) break;
              progress?.update(phase: AyuForwardPhase.downloading);

              if (group.length > 1) {
                await engine.resendAlbumAsOwn(
                  accountId,
                  sourceChatId,
                  group.map((m) => m.msgId).toList(),
                  toChatId,
                  silent: silent,
                  scheduleDate: scheduleDate,
                  dropCaptions: dropCaptions,
                );
                sentInChunk += group.length;
              } else {
                await engine.resendAsOwn(
                  accountId, sourceChatId, group.first.msgId, toChatId,
                  silent: silent,
                  scheduleDate: scheduleDate,
                  dropCaptions: dropCaptions,
                );
                sentInChunk++;
              }
              progress?.update(
                phase: AyuForwardPhase.sending,
                sent: sentInChunk,
              );
            }
        }
      }
    } finally {
      progress?.update(phase: AyuForwardPhase.finished);
      _scheduleCleanup(toChatId);
    }
  }

  static bool needsIntelligentForward(
    List<CachedMessage> messages,
    ChatInfo sourceChat,
  ) {
    // AyuGram's caller gate (apiwrap.cpp:3487-3501, window_peer_menu.cpp:3248):
    //   isFullAyuForwardNeeded(items.front()) || isAyuForwardNeeded(items)
    // The first disjunct is FIRST-ITEM-ONLY (the front message's sender, or the
    // source chat); the second is any-message message-level restriction
    // (deleted / unsupportedTTL / ttlSeconds / per-message noForwards ==
    // isMessageRestricted). A LATER message's restricted SENDER must NOT force
    // the special path on its own — only the FRONT message's sender does, so we
    // do not `.any(senderNoForwards)`.
    if (messages.isEmpty) return isChatRestricted(sourceChat);
    if (isFullAyuForwardNeeded(messages.first, sourceChat)) return true;
    return messages.any(isMessageRestricted);
  }
}

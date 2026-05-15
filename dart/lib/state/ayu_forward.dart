import 'package:flutter/foundation.dart';

import '../bridge/engine_service.dart';
import '../models/engine_models.dart';

enum ForwardMethod { native, resendAsOwn }

enum AyuForwardPhase { preparing, downloading, sending, finished }

class ForwardChunk {
  final ForwardMethod method;
  final List<CachedMessage> messages;
  const ForwardChunk(this.method, this.messages);
}

class AyuForwardStrings {
  static String statusPreparing() => 'Preparing...';
  static String statusForwarding() => 'Forwarding messages';
  static String statusLoadingMedia() => 'Loading media';
  static String statusFinished() => 'Done';
  static String sentCount(int sent, int total) => 'sent $sent of $total';
  static String chunkCount(int chunk, int total) => 'chunk $chunk of $total';
}

class ForwardProgress extends ChangeNotifier {
  AyuForwardPhase _phase = AyuForwardPhase.preparing;
  int _sentCount = 0;
  int _totalCount = 0;
  int _chunkIndex = 0;
  int _totalChunks = 0;
  bool _cancelled = false;

  AyuForwardPhase get phase => _phase;
  int get sentCount => _sentCount;
  int get totalCount => _totalCount;
  int get chunkIndex => _chunkIndex;
  int get totalChunks => _totalChunks;
  bool get isCancelled => _cancelled;

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
    return p.phase != AyuForwardPhase.finished
        && p.chunkIndex < p.totalChunks
        && !p.isCancelled
        && ((p.totalChunks > 0 && p.totalCount > 0) || p.phase == AyuForwardPhase.downloading);
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
    Future.delayed(const Duration(seconds: 2), () {
      _activeForwards.remove(toChatId);
      progress.dispose();
    });
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

  static List<ForwardChunk> buildChunks(
    List<CachedMessage> messages,
    ChatInfo sourceChat,
  ) {
    if (isChatRestricted(sourceChat)) {
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
      progress.update(
        phase: AyuForwardPhase.preparing,
        total: messages.length,
        chunks: chunks.length,
      );
    }

    int sentSoFar = 0;
    try {
      for (int i = 0; i < chunks.length; i++) {
        if (progress?.isCancelled == true) break;
        final chunk = chunks[i];

        final phase = chunk.method == ForwardMethod.resendAsOwn
            ? AyuForwardPhase.downloading
            : AyuForwardPhase.sending;
        progress?.update(phase: phase, chunk: i + 1);

        switch (chunk.method) {
          case ForwardMethod.native:
            progress?.update(phase: AyuForwardPhase.sending);
            for (final msg in chunk.messages) {
              if (progress?.isCancelled == true) break;
              await engine.forwardMessage(
                accountId, sourceChatId, msg.msgId, toChatId,
                dropAuthor: dropAuthor,
                dropCaptions: dropCaptions,
                silent: silent,
                scheduleDate: scheduleDate,
              );
              sentSoFar++;
              progress?.update(sent: sentSoFar);
            }
          case ForwardMethod.resendAsOwn:
            final albumGroups = _groupByAlbum(chunk.messages);
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
                sentSoFar += group.length;
              } else {
                await engine.resendAsOwn(
                  accountId, sourceChatId, group.first.msgId, toChatId,
                  silent: silent,
                  scheduleDate: scheduleDate,
                  dropCaptions: dropCaptions,
                );
                sentSoFar++;
              }
              progress?.update(
                phase: AyuForwardPhase.sending,
                sent: sentSoFar,
              );
            }
        }
      }
    } finally {
      progress?.update(phase: AyuForwardPhase.finished, sent: sentSoFar);
      Future.delayed(const Duration(seconds: 2), () {
        _activeForwards.remove(toChatId);
        progress?.dispose();
      });
    }
  }

  static bool needsIntelligentForward(
    List<CachedMessage> messages,
    ChatInfo sourceChat,
  ) {
    if (isChatRestricted(sourceChat)) return true;
    if (messages.any((m) => m.senderNoForwards)) return true;
    return messages.any(isMessageRestricted);
  }
}

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
      case AyuForwardPhase.sending:
        return 'Forwarding messages';
      case AyuForwardPhase.downloading:
        return 'Loading media';
      case AyuForwardPhase.finished:
        return 'Done';
    }
  }

  String get detailText {
    if (_phase == AyuForwardPhase.downloading) return '';
    if (_totalCount == 0) return '';
    final msg = 'sent $_sentCount of $_totalCount';
    if (_totalChunks > 1) {
      return '$msg · chunk $_chunkIndex of $_totalChunks';
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
  static bool isForwarding(String peerId) => _activeForwards.containsKey(peerId);

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
    if (msg.ttlSeconds > 0) return true;
    return false;
  }

  static bool isChatRestricted(ChatInfo chat) => chat.noForwards;

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
            for (final msg in chunk.messages) {
              if (progress?.isCancelled == true) break;
              progress?.update(phase: AyuForwardPhase.downloading);
              await engine.resendAsOwn(
                accountId, sourceChatId, msg.msgId, toChatId,
                silent: silent,
                scheduleDate: scheduleDate,
              );
              sentSoFar++;
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
    return messages.any(isMessageRestricted);
  }
}

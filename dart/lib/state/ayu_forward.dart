import '../bridge/engine_service.dart';
import '../models/engine_models.dart';

enum ForwardMethod { native, resendAsOwn }

class ForwardChunk {
  final ForwardMethod method;
  final List<CachedMessage> messages;
  const ForwardChunk(this.method, this.messages);
}

class AyuForward {
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
  }) async {
    final chunks = buildChunks(messages, sourceChat);

    for (final chunk in chunks) {
      switch (chunk.method) {
        case ForwardMethod.native:
          for (final msg in chunk.messages) {
            await engine.forwardMessage(
              accountId, sourceChatId, msg.msgId, toChatId,
              dropAuthor: dropAuthor,
              dropCaptions: dropCaptions,
              silent: silent,
              scheduleDate: scheduleDate,
            );
          }
        case ForwardMethod.resendAsOwn:
          for (final msg in chunk.messages) {
            await engine.resendAsOwn(
              accountId, sourceChatId, msg.msgId, toChatId,
              silent: silent,
              scheduleDate: scheduleDate,
            );
          }
      }
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

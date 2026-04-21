import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../bridge/engine_service.dart';
import '../state/app_state.dart';
import '../state/chat_state.dart';

/// §21: Create Channel wizard — Step 1: GroupInfoBox (name/description/photo).
/// Width 364px (boxWideWidth). Title bar 48px, 16px semibold.
/// Userpic 72×72px at (24, 10). Title input at left 99px, max 128 chars.
/// Description field max 255 chars, max height 116px.
/// Buttons: "Create" + "Cancel".
class CreateChannelScreen extends StatefulWidget {
  const CreateChannelScreen({super.key});

  @override
  State<CreateChannelScreen> createState() => _CreateChannelScreenState();
}

class _CreateChannelScreenState extends State<CreateChannelScreen> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _nameFocus = FocusNode();
  bool _creating = false;
  String? _error;

  // §21.7: kMaxGroupChannelTitle = 128, kMaxChannelDescription = 255.
  static const _maxTitleLength = 128;
  static const _maxDescLength = 255;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nameFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _createChannel() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      // §21.2: Empty title → focus + shake.
      _nameFocus.requestFocus();
      setState(() => _error = 'Please enter a channel name');
      return;
    }

    setState(() {
      _creating = true;
      _error = null;
    });

    try {
      final appState = context.read<AppState>();
      final engine = context.read<EngineService>();
      final chatState = context.read<ChatState>();
      final accountId = appState.activeAccountId;

      if (accountId.isEmpty) {
        setState(() {
          _creating = false;
          _error = 'No active account';
        });
        return;
      }

      final chatInfo = await engine.createChannel(
        accountId,
        name,
        _descController.text.trim(),
      );

      if (!mounted) return;

      // Navigate to the new channel by opening it.
      final chats = chatState.chats;
      final newChat = chats.where((c) => c.chatId == chatInfo.chatId).firstOrNull;
      if (newChat != null) {
        chatState.openChat(newChat);
      }

      Navigator.of(context).pop(true);
    } on EngineException catch (e) {
      if (!mounted) return;
      String msg = e.message;
      // §21.2 errors: NO_CHAT_TITLE, CHANNELS_TOO_MUCH, etc.
      if (msg.contains('NO_CHAT_TITLE')) {
        msg = 'Please enter a channel name';
      } else if (msg.contains('CHANNELS_TOO_MUCH')) {
        msg = 'You have created too many channels';
      } else if (msg.contains('USERS_TOO_FEW')) {
        msg = 'Unable to create channel';
      }
      setState(() {
        _creating = false;
        _error = msg;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final bgColor = isDark ? const Color(0xFF17212B) : const Color(0xFFFFFFFF);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF000000);
    final subtextColor = isDark ? const Color(0xFF6C7883) : const Color(0xFF999999);
    final fieldBgColor = isDark ? const Color(0xFF242F3D) : const Color(0xFFF1F1F1);
    // §21.2.1: Default userpic gradient pair 1 (historyPeer1UserpicBg).
    const userpicGrad1 = Color(0xFFFC5C51);
    const userpicGrad2 = Color(0xFFE44234);

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
        // §21.2: Title bar 48px, 16px semibold.
        toolbarHeight: 48,
        title: Text(
          'New Channel',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        actions: [
          // "Create" button in the app bar (like Telegram Desktop).
          TextButton(
            onPressed: _creating ? null : _createChannel,
            child: _creating
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  )
                : Text(
                    'Create',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // §21.2: Userpic button (72×72) + title input side by side.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // §21.2: 72×72px userpic at (24, 10).
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [userpicGrad1, userpicGrad2],
                    ),
                  ),
                  child: Center(
                    child: _nameController.text.trim().isNotEmpty
                        ? Text(
                            _nameController.text.trim()[0].toUpperCase(),
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w500,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            Icons.add_a_photo_outlined,
                            size: 28,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                  ),
                ),
                const SizedBox(width: 27),
                // §21.2: Title input at left 99px (72+27), top 5px.
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: TextField(
                      controller: _nameController,
                      focusNode: _nameFocus,
                      maxLength: _maxTitleLength,
                      style: TextStyle(
                        fontSize: 14,
                        color: textColor,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Channel Name',
                        hintStyle: TextStyle(color: subtextColor),
                        counterText: '',
                        filled: true,
                        fillColor: fieldBgColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      onChanged: (_) => setState(() => _error = null),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            // §21.2: Description (channels only): MultiLine, max 255 chars.
            TextField(
              controller: _descController,
              maxLength: _maxDescLength,
              maxLines: null,
              minLines: 3,
              style: TextStyle(
                fontSize: 14,
                color: textColor,
              ),
              decoration: InputDecoration(
                hintText: 'Description (optional)',
                hintStyle: TextStyle(color: subtextColor),
                counterText: '',
                filled: true,
                fillColor: fieldBgColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // §21.2: Informational text below description.
            Text(
              'You can provide an optional description for your channel.',
              style: TextStyle(
                fontSize: 13,
                color: subtextColor,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFFDD4B39),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

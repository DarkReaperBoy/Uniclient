import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'telegram_palette.dart';

/// Full-size theme preview image (903×584) matching Telegram Desktop's
/// window_theme_preview.cpp. Renders a miniature dialogs panel (left) with
/// 9 sample rows, and a chat history area (right) with sample bubbles.
class ThemePreviewImage extends StatelessWidget {
  final TelegramPalette palette;
  final double width;
  final double height;

  const ThemePreviewImage({
    super.key,
    required this.palette,
    this.width = 903,
    this.height = 584,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _ThemePreviewPainter(palette: palette),
    );
  }
}

class _ThemePreviewPainter extends CustomPainter {
  final TelegramPalette palette;

  _ThemePreviewPainter({required this.palette});

  static const double _dialogsWidth = 260;
  static const double _topBarHeight = 54;
  static const double _composeHeight = 49;
  static const double _rowHeight = 62;
  static const double _avatarSize = 46;
  static const double _avatarLeft = 10;
  static const double _textLeft = 68;

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / 903;
    final scaleY = size.height / 584;
    canvas.save();
    canvas.scale(scaleX, scaleY);

    _drawDialogsPanel(canvas);
    _drawChatPanel(canvas);

    canvas.restore();
  }

  void _drawDialogsPanel(Canvas canvas) {
    // Background
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _dialogsWidth, 584),
      Paint()..color = palette.dialogsBg,
    );

    // Search bar area
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _dialogsWidth, 44),
      Paint()..color = palette.dialogsBg,
    );
    final searchRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(7, 7, 246, 30),
      const Radius.circular(15),
    );
    canvas.drawRRect(
      searchRect,
      Paint()..color = palette.windowBgOver,
    );
    _drawText(canvas, 'Search', 28, 14, 12,
        palette.windowSubTextFg, FontWeight.normal);

    // 9 dialog rows
    const names = [
      'Paul',
      'Saved Messages',
      'Design Team',
      'Alice Cooper',
      'Travel Chat',
      'John Smith',
      'Work Group',
      'Mary Jane',
      'Tech News',
    ];
    const previews = [
      'Hey, are you free tomorrow?',
      'Photo saved to gallery',
      'Let\'s discuss the new mockup...',
      'Sure, I\'ll send it over!',
      'Booked the hotel for next week',
      'Can you review this PR?',
      'Meeting at 3pm confirmed',
      'Happy birthday! 🎉',
      'New article about Flutter 4.0',
    ];
    const times = [
      '12:45',
      '12:30',
      '12:15',
      '11:50',
      '11:30',
      'Tue',
      'Mon',
      'Mon',
      'Sun',
    ];
    const unreadCounts = [0, 0, 3, 0, 0, 1, 0, 0, 5];
    const pinnedFlags = [false, true, false, false, false, false, false, false, false];
    const activeIndex = 2;

    final double startY = 44;

    for (int i = 0; i < 9; i++) {
      final y = startY + i * _rowHeight;
      if (y + _rowHeight > 584) break;

      final isActive = i == activeIndex;

      // Row background
      canvas.drawRect(
        Rect.fromLTWH(0, y, _dialogsWidth, _rowHeight),
        Paint()..color = isActive ? palette.dialogsBgActive : palette.dialogsBg,
      );

      // Avatar circle
      final avatarCx = _avatarLeft + _avatarSize / 2;
      final avatarCy = y + 8 + _avatarSize / 2;
      final avatarColors = [
        palette.historyPeer1UserpicBg,
        palette.historyPeer2UserpicBg,
        palette.historyPeer3UserpicBg,
        palette.historyPeer4UserpicBg,
        palette.historyPeer5UserpicBg,
        palette.historyPeer6UserpicBg,
        palette.historyPeer7UserpicBg,
        palette.historyPeer8UserpicBg,
      ];
      canvas.drawCircle(
        Offset(avatarCx, avatarCy),
        _avatarSize / 2,
        Paint()..color = avatarColors[i % 8],
      );
      // Avatar initial letter
      _drawText(
        canvas,
        names[i].substring(0, 1),
        avatarCx - 6,
        avatarCy - 8,
        16,
        Colors.white,
        FontWeight.w500,
      );

      // Name
      final nameFg = isActive ? palette.dialogsNameFgActive : palette.dialogsNameFg;
      _drawText(canvas, names[i], _textLeft, y + 10, 13, nameFg, FontWeight.w600,
          maxWidth: 140);

      // Timestamp
      final dateFg = isActive ? palette.dialogsTextFgActive : palette.dialogsDateFg;
      _drawTextRight(canvas, times[i], _dialogsWidth - 10, y + 12, 12, dateFg);

      // Preview
      final previewFg = isActive ? palette.dialogsTextFgActive : palette.dialogsTextFg;
      _drawText(canvas, previews[i], _textLeft, y + 34, 13, previewFg,
          FontWeight.normal,
          maxWidth: 170);

      // Unread badge
      if (unreadCounts[i] > 0) {
        final badgeText = '${unreadCounts[i]}';
        final badgeW = math.max(20.0, 12.0 + badgeText.length * 7.0);
        final badgeX = _dialogsWidth - 10 - badgeW;
        final badgeY = y + 36;
        final badgeBg = isActive ? palette.dialogsUnreadBgActive : palette.dialogsUnreadBg;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(badgeX, badgeY, badgeW, 20),
            const Radius.circular(10),
          ),
          Paint()..color = badgeBg,
        );
        final badgeFg = isActive ? palette.dialogsUnreadFgActive : palette.dialogsUnreadFg;
        _drawText(canvas, badgeText, badgeX + (badgeW - badgeText.length * 7) / 2,
            badgeY + 3, 11, badgeFg, FontWeight.bold);
      }

      // Pin icon
      if (pinnedFlags[i] && unreadCounts[i] == 0) {
        final pinX = _dialogsWidth - 22.0;
        final pinY = y + 38;
        final pinColor = isActive ? palette.dialogsTextFgActive : palette.dialogsDateFg;
        _drawPinIcon(canvas, pinX, pinY, pinColor);
      }
    }

    // Separator shadow
    canvas.drawRect(
      const Rect.fromLTWH(_dialogsWidth - 1, 0, 1, 584),
      Paint()..color = palette.shadowFg,
    );
  }

  void _drawChatPanel(Canvas canvas) {
    final left = _dialogsWidth;
    final chatWidth = 903 - _dialogsWidth;

    // Chat background (windowBg)
    canvas.drawRect(
      Rect.fromLTWH(left, 0, chatWidth.toDouble(), 584),
      Paint()..color = palette.windowBg,
    );

    // Top bar
    canvas.drawRect(
      Rect.fromLTWH(left, 0, chatWidth.toDouble(), _topBarHeight),
      Paint()..color = palette.topBarBg,
    );
    canvas.drawRect(
      Rect.fromLTWH(left, _topBarHeight - 1, chatWidth.toDouble(), 1),
      Paint()..color = palette.shadowFg,
    );

    // Top bar avatar
    final topAvatarCx = left + 16 + 18;
    const topAvatarCy = 27.0;
    canvas.drawCircle(
      Offset(topAvatarCx, topAvatarCy),
      18,
      Paint()..color = palette.historyPeer3UserpicBg,
    );
    _drawText(canvas, 'D', topAvatarCx - 6, topAvatarCy - 8, 16, Colors.white,
        FontWeight.w500);

    // Top bar title and subtitle
    _drawText(canvas, 'Design Team', left + 56, 12, 15,
        palette.windowBoldFg, FontWeight.w600);
    _drawText(canvas, '5 members, 2 online', left + 56, 32, 13,
        palette.windowSubTextFg, FontWeight.normal);

    // Message area
    _drawMessageArea(canvas, left, chatWidth.toDouble());

    // Compose area
    _drawComposeArea(canvas, left, chatWidth.toDouble());
  }

  void _drawMessageArea(Canvas canvas, double left, double chatWidth) {
    final areaTop = _topBarHeight;
    final areaBottom = 584 - _composeHeight;

    // Date separator
    final dateY = areaTop + 14;
    final dateText = 'April 28';
    final datePillW = 90.0;
    final datePillX = left + (chatWidth - datePillW) / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(datePillX, dateY, datePillW, 24),
        const Radius.circular(12),
      ),
      Paint()..color = palette.msgServiceBg,
    );
    _drawText(canvas, dateText, datePillX + 16, dateY + 5, 13,
        palette.msgServiceFg, FontWeight.w500);

    // Sample messages
    final messages = <_SampleMessage>[
      _SampleMessage(
        text: 'Has anyone seen the new mockup for\nthe settings page?',
        isOut: false,
        senderName: 'Alice Cooper',
        senderColor: palette.historyPeer4NameFg,
        time: '12:06',
        y: dateY + 38,
      ),
      _SampleMessage(
        text: 'Yes! The layout looks great 👍',
        isOut: false,
        senderName: 'Paul',
        senderColor: palette.historyPeer1NameFg,
        time: '12:08',
        y: dateY + 108,
        attachTop: false,
      ),
      _SampleMessage(
        text: 'I think we should adjust the\nspacing on the header section',
        isOut: true,
        time: '12:10',
        y: dateY + 162,
        showCheck: true,
      ),
      _SampleMessage(
        text: 'Good point, I\'ll update it',
        isOut: false,
        senderName: 'Alice Cooper',
        senderColor: palette.historyPeer4NameFg,
        time: '12:12',
        y: dateY + 238,
      ),
      _SampleMessage(
        text: 'Also, the font size should match\nthe spec — 14px for body text',
        isOut: true,
        time: '12:15',
        y: dateY + 298,
        showCheck: true,
        doubleCheck: true,
      ),
      _SampleMessage(
        isOut: false,
        senderName: 'Paul',
        senderColor: palette.historyPeer1NameFg,
        time: '12:16',
        y: dateY + 378,
        isReply: true,
        replyName: 'You',
        replyText: 'I think we should adjust the...',
        text: 'Agreed, let me check the values',
      ),
    ];

    for (final msg in messages) {
      if (msg.y + 80 > areaBottom) continue;
      _drawBubble(canvas, msg, left, chatWidth);
    }
  }

  void _drawBubble(
      Canvas canvas, _SampleMessage msg, double panelLeft, double chatWidth) {
    final maxBubbleW = 340.0;
    final padding = 11.0;

    // Estimate text width
    double textW = _estimateTextWidth(msg.text, 13) + padding * 2;
    if (msg.senderName != null) {
      textW = math.max(textW, _estimateTextWidth(msg.senderName!, 13) + padding * 2);
    }
    if (msg.isReply) {
      textW = math.max(textW, _estimateTextWidth(msg.replyText ?? '', 12) + padding * 2 + 10);
    }
    final bubbleW = math.min(textW + 50, maxBubbleW);

    final lines = msg.text.split('\n').length;
    double contentH = 6.0; // top padding
    if (msg.senderName != null) contentH += 18;
    if (msg.isReply) contentH += 34;
    contentH += lines * 18 + 6; // text + bottom padding
    contentH += 16; // timestamp row

    final bubbleBg = msg.isOut ? palette.msgOutBg : palette.msgInBg;
    final textFg = msg.isOut ? palette.historyTextOutFg : palette.historyTextInFg;
    final dateFg = msg.isOut ? palette.msgOutDateFg : palette.msgInDateFg;

    // Position
    double bubbleX;
    if (msg.isOut) {
      bubbleX = panelLeft + chatWidth - bubbleW - 20;
    } else {
      bubbleX = panelLeft + 52; // after avatar space
    }

    // Avatar for incoming
    if (!msg.isOut) {
      final avCx = panelLeft + 16 + 16.5;
      final avCy = msg.y + contentH - 16.5;
      canvas.drawCircle(
        Offset(avCx, avCy),
        16.5,
        Paint()..color = msg.senderColor ?? palette.historyPeer1UserpicBg,
      );
      _drawText(canvas, (msg.senderName ?? 'U').substring(0, 1),
          avCx - 5, avCy - 7, 14, Colors.white, FontWeight.w500);
    }

    // Bubble shape with tail
    final bubbleRect = Rect.fromLTWH(bubbleX, msg.y, bubbleW, contentH);
    final rrect = RRect.fromRectAndCorners(
      bubbleRect,
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: msg.isOut ? const Radius.circular(16) : const Radius.circular(6),
      bottomRight: msg.isOut ? const Radius.circular(6) : const Radius.circular(16),
    );
    canvas.drawRRect(rrect, Paint()..color = bubbleBg);

    double cy = msg.y + 6;

    // Sender name
    if (msg.senderName != null) {
      _drawText(canvas, msg.senderName!, bubbleX + padding, cy, 13,
          msg.senderColor ?? palette.historyPeer1NameFg, FontWeight.w600);
      cy += 18;
    }

    // Reply block
    if (msg.isReply) {
      final replyBarColor = msg.isOut
          ? palette.msgOutReplyBarColor
          : palette.msgInReplyBarColor;
      canvas.drawRect(
        Rect.fromLTWH(bubbleX + padding, cy, 2, 30),
        Paint()..color = replyBarColor,
      );
      _drawText(canvas, msg.replyName ?? '', bubbleX + padding + 8, cy + 1,
          12, replyBarColor, FontWeight.w600);
      _drawText(canvas, msg.replyText ?? '', bubbleX + padding + 8, cy + 16,
          12, textFg.withValues(alpha: 0.7), FontWeight.normal);
      cy += 34;
    }

    // Message text
    for (final line in msg.text.split('\n')) {
      _drawText(canvas, line, bubbleX + padding, cy, 13, textFg,
          FontWeight.normal);
      cy += 18;
    }

    // Timestamp + checks
    final timeX = bubbleX + bubbleW - padding - _estimateTextWidth(msg.time, 11) - (msg.showCheck ? 22 : 0);
    final timeY = msg.y + contentH - 18;
    _drawText(canvas, msg.time, timeX, timeY, 11, dateFg, FontWeight.normal);

    if (msg.showCheck) {
      final checkX = timeX + _estimateTextWidth(msg.time, 11) + 4;
      final checkY = timeY + 2;
      final checkColor = palette.historyOutIconFg;
      _drawCheck(canvas, checkX, checkY, checkColor, msg.doubleCheck);
    }
  }

  void _drawComposeArea(Canvas canvas, double left, double chatWidth) {
    final composeY = 584 - _composeHeight;

    // Background
    canvas.drawRect(
      Rect.fromLTWH(left, composeY.toDouble(), chatWidth, _composeHeight.toDouble()),
      Paint()..color = palette.historyComposeAreaBg,
    );

    // Top border
    canvas.drawRect(
      Rect.fromLTWH(left, composeY.toDouble(), chatWidth, 1),
      Paint()..color = palette.shadowFg,
    );

    // Attach icon placeholder
    final iconColor = palette.historyComposeIconFg;
    _drawAttachIcon(canvas, left + 12, composeY + 14, iconColor);

    // Text field placeholder
    _drawText(canvas, 'Write a message...', left + 52, composeY + 16, 13,
        palette.historyComposeAreaFg.withValues(alpha: 0.5), FontWeight.normal);

    // Send button area
    final sendX = left + chatWidth - 44;
    final sendY = composeY + 6;
    canvas.drawCircle(
      Offset(sendX + 18, sendY + 18),
      18,
      Paint()..color = palette.historyComposeButtonBg,
    );
    _drawSendArrow(canvas, sendX + 10, sendY + 10, palette.historySendIconFg);
  }

  // ── Drawing Helpers ──

  void _drawText(Canvas canvas, String text, double x, double y, double fontSize,
      Color color, FontWeight weight, {double? maxWidth}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: weight,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    );
    tp.layout(maxWidth: maxWidth ?? 400);
    tp.paint(canvas, Offset(x, y));
  }

  void _drawTextRight(
      Canvas canvas, String text, double rightX, double y, double fontSize, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, color: color),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(rightX - tp.width, y));
  }

  double _estimateTextWidth(String text, double fontSize) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    return tp.width;
  }

  void _drawPinIcon(Canvas canvas, double x, double y, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(x + 4, y)
      ..lineTo(x + 12, y)
      ..moveTo(x + 8, y)
      ..lineTo(x + 8, y + 10)
      ..moveTo(x + 3, y + 10)
      ..lineTo(x + 13, y + 10)
      ..moveTo(x + 8, y + 10)
      ..lineTo(x + 8, y + 16);
    canvas.drawPath(path, paint);
  }

  void _drawCheck(Canvas canvas, double x, double y, Color color, bool double_) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (double_) {
      final path1 = Path()
        ..moveTo(x, y + 5)
        ..lineTo(x + 4, y + 9)
        ..lineTo(x + 11, y + 2);
      canvas.drawPath(path1, paint);
      final path2 = Path()
        ..moveTo(x + 4, y + 5)
        ..lineTo(x + 8, y + 9)
        ..lineTo(x + 15, y + 2);
      canvas.drawPath(path2, paint);
    } else {
      final path = Path()
        ..moveTo(x + 1, y + 5)
        ..lineTo(x + 5, y + 9)
        ..lineTo(x + 12, y + 2);
      canvas.drawPath(path, paint);
    }
  }

  void _drawAttachIcon(Canvas canvas, double x, double y, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(x + 10, y + 2)
      ..lineTo(x + 10, y + 14)
      ..moveTo(x + 4, y + 8)
      ..lineTo(x + 16, y + 8);
    canvas.drawPath(path, paint);
  }

  void _drawSendArrow(Canvas canvas, double x, double y, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(x + 4, y + 2)
      ..lineTo(x + 16, y + 8)
      ..lineTo(x + 4, y + 14)
      ..lineTo(x + 7, y + 8)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ThemePreviewPainter old) =>
      !identical(old.palette, palette);
}

class _SampleMessage {
  final String text;
  final bool isOut;
  final String? senderName;
  final Color? senderColor;
  final String time;
  final double y;
  final bool showCheck;
  final bool doubleCheck;
  final bool attachTop;
  final bool isReply;
  final String? replyName;
  final String? replyText;

  const _SampleMessage({
    required this.text,
    required this.isOut,
    this.senderName,
    this.senderColor,
    required this.time,
    required this.y,
    this.showCheck = false,
    this.doubleCheck = false,
    this.attachTop = false,
    this.isReply = false,
    this.replyName,
    this.replyText,
  });
}

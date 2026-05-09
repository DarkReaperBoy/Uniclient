import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'telegram_palette.dart';

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

  static const double _dialogsWidth = 312;
  static const double _topBarHeight = 54;
  static const double _composeHeight = 46;
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
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _dialogsWidth, 584),
      Paint()..color = palette.dialogsBg,
    );

    // Hamburger menu icon (3 lines)
    final menuIconColor = palette.dialogsMenuIconFg;
    final menuPaint = Paint()
      ..color = menuIconColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    const menuX = 7.0 + 12.0;
    const menuCY = 27.0;
    canvas.drawLine(
        const Offset(menuX, menuCY - 7), const Offset(menuX + 18, menuCY - 7), menuPaint);
    canvas.drawLine(
        const Offset(menuX, menuCY), const Offset(menuX + 18, menuCY), menuPaint);
    canvas.drawLine(
        const Offset(menuX, menuCY + 7), const Offset(menuX + 18, menuCY + 7), menuPaint);

    // Search filter field
    const filterLeft = 58.0;
    const filterTop = 11.0;
    const filterHeight = 32.0;
    const filterWidth = _dialogsWidth - filterLeft - 14.0;
    final filterRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(filterLeft, filterTop, filterWidth, filterHeight),
      const Radius.circular(16),
    );
    canvas.drawRRect(filterRect, Paint()..color = palette.windowBgOver);
    _drawText(canvas, 'Search', filterLeft + 14, filterTop + 8, 13,
        palette.windowSubTextFg, FontWeight.normal);

    // 8 dialog rows (AyuGram has 8 named + 1 empty)
    const names = [
      'Eva Summer',
      'Alexandra Smith',
      'Mike Apple',
      'Evening Club',
      'Old Pirates',
      'Max Bright',
      'Natalie Parker',
      'Davy Jones',
    ];
    const previews = [
      'We are too smart for this world. \u{1f923}\u{1f602}',
      'This is amazing!',
      '\u{1f4ce} Sticker',
      'Eva: Photo',
      'Max: Yo-ho-ho!',
      'How about some coffee?',
      'OK, great)',
      'Keynote.pdf',
    ];
    const times = ['11:00', '10:00', '9:00', '8:00', '7:00', '6:00', '5:00', '4:00'];
    const unreadCounts = [0, 2, 2, 0, 0, 0, 0, 0];
    const mutedFlags = [false, false, true, false, false, false, false, false];
    const pinnedFlags = [true, false, false, false, false, false, false, false];
    const statusFlags = [0, 0, 0, 0, 0, 2, 2, 0]; // 0=none, 2=received
    const activeIndex = 0;
    const isGroup = [false, false, false, true, true, false, false, false];

    const double startY = 54;

    for (int i = 0; i < 8; i++) {
      final y = startY + i * _rowHeight;
      if (y + _rowHeight > 584) break;

      final isActive = i == activeIndex;

      canvas.drawRect(
        Rect.fromLTWH(0, y, _dialogsWidth, _rowHeight),
        Paint()..color = isActive ? palette.dialogsBgActive : palette.dialogsBg,
      );

      // Avatar circle
      final avatarCx = _avatarLeft + _avatarSize / 2;
      final avatarCy = y + 8 + _avatarSize / 2;
      final avatarColors = [
        palette.historyPeer1UserpicBg,
        palette.historyPeer8UserpicBg,
        palette.historyPeer3UserpicBg,
        palette.historyPeer2UserpicBg,
        palette.historyPeer7UserpicBg,
        palette.historyPeer4UserpicBg,
        palette.historyPeer5UserpicBg,
        palette.historyPeer6UserpicBg,
      ];
      canvas.drawCircle(
        Offset(avatarCx, avatarCy),
        _avatarSize / 2,
        Paint()..color = avatarColors[i],
      );
      _drawText(
        canvas,
        _initials(names[i]),
        avatarCx - 8,
        avatarCy - 8,
        14,
        Colors.white,
        FontWeight.w500,
      );

      // Name
      final nameFg = isActive ? palette.dialogsNameFgActive : palette.dialogsNameFg;
      _drawText(canvas, names[i], _textLeft, y + 10, 13, nameFg, FontWeight.w600,
          maxWidth: 155);

      // Sent status icon before date
      if (statusFlags[i] > 0) {
        final checkFg = isActive ? palette.dialogsTextFgActive : palette.dialogsSentIconFg;
        final checkX = _dialogsWidth - 10 - _estimateTextWidth(times[i], 12) - 20;
        _drawCheck(canvas, checkX, y + 12, checkFg, statusFlags[i] == 2);
      }

      // Timestamp
      final dateFg = isActive ? palette.dialogsDateFgActive : palette.dialogsDateFg;
      _drawTextRight(canvas, times[i], _dialogsWidth - 10, y + 12, 12, dateFg);

      // Preview text
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
        final badgeBg = isActive
            ? palette.dialogsUnreadBgActive
            : (mutedFlags[i] ? palette.dialogsUnreadBgMuted : palette.dialogsUnreadBg);
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
    const left = _dialogsWidth;
    const chatWidth = 903.0 - _dialogsWidth;

    // Chat background
    canvas.drawRect(
      const Rect.fromLTWH(left, 0, chatWidth, 584),
      Paint()..color = palette.windowBg,
    );

    // Top bar
    canvas.drawRect(
      const Rect.fromLTWH(left, 0, chatWidth, _topBarHeight),
      Paint()..color = palette.topBarBg,
    );
    canvas.drawRect(
      const Rect.fromLTWH(left, _topBarHeight - 1, chatWidth, 1),
      Paint()..color = palette.shadowFg,
    );

    // Top bar: name and status (no avatar in AyuGram preview)
    _drawText(canvas, 'Eva Summer', left + 17, 8, 15,
        palette.dialogsNameFg, FontWeight.w600);
    _drawText(canvas, 'online', left + 17, 32, 13,
        palette.contactsStatusFgOnline, FontWeight.normal);

    // Top bar: right-aligned icons (search, call, menu)
    final iconFg = palette.dialogsMenuIconFg;
    final iconPaint = Paint()
      ..color = iconFg
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Menu toggle (rightmost, 44px zone)
    const menuRight = 903.0;
    _drawMenuDotsIcon(canvas, menuRight - 28, 19, iconPaint);

    // Call icon (next, 40px zone with 4px skip)
    const callRight = menuRight - 44 - 4;
    _drawCallIcon(canvas, callRight - 28, 17, iconPaint);

    // Search icon (next, 40px zone)
    const searchRight = callRight - 40;
    _drawSearchIcon(canvas, searchRight - 26, 18, iconPaint);

    // Message area
    _drawMessageArea(canvas, left, chatWidth);

    // Compose area
    _drawComposeArea(canvas, left, chatWidth);
  }

  void _drawMessageArea(Canvas canvas, double left, double chatWidth) {
    final areaBottom = 584.0 - _composeHeight;

    // Paint bottom-up like AyuGram does
    var historyBottom = areaBottom - 8.0;

    // Bubble 6 (bottom): incoming with reply
    // "We are too smart for this world. 🤣😂" at 11:00
    // Reply: "Alex Cassio" → "Mark Twain said that ☝️"
    historyBottom = _drawTextBubbleBottomUp(
      canvas, left, chatWidth, historyBottom,
      text: 'We are too smart for this world. \u{1f923}\u{1f602}',
      isOut: false,
      time: '11:00',
      senderName: null,
      senderColor: palette.historyPeer1NameFg,
      replyName: 'Alex Cassio',
      replyText: 'Mark Twain said that \u{261d}\u{fe0f}',
      tail: true,
    );
    historyBottom -= 6;

    // Bubble 5: outgoing, attached top, tail
    // "Mark Twain said that ☝️" at 10:00
    historyBottom = _drawTextBubbleBottomUp(
      canvas, left, chatWidth, historyBottom,
      text: 'Mark Twain said that \u{261d}\u{fe0f}',
      isOut: true,
      time: '10:00',
      showCheck: true,
      doubleCheck: true,
      attachToTop: true,
      tail: true,
    );
    historyBottom -= 2;

    // Bubble 4: outgoing, no tail, attached bottom
    // "Twenty years from now..." at 10:00
    historyBottom = _drawTextBubbleBottomUp(
      canvas, left, chatWidth, historyBottom,
      text: 'Twenty years from now you will be more\ndisappointed by the things that you didn\'t\ndo than by the ones you did do. \u{1f9d0}',
      isOut: true,
      time: '10:00',
      showCheck: true,
      doubleCheck: true,
      attachToBottom: true,
      tail: false,
    );
    historyBottom -= 12;

    // Service bubble: "December 26"
    historyBottom = _drawServiceBubble(canvas, left, chatWidth, historyBottom, 'December 26');
    historyBottom -= 12;

    // Bubble 2: audio waveform (outgoing, received)
    historyBottom = _drawAudioBubbleBottomUp(canvas, left, chatWidth, historyBottom);
    historyBottom -= 6;

    // Bubble 1: photo bubble (incoming)
    // "To reach a port, we must sail. 🥸" at 7:00
    _drawPhotoBubbleBottomUp(canvas, left, chatWidth, historyBottom);
  }

  double _drawTextBubbleBottomUp(
    Canvas canvas,
    double panelLeft,
    double chatWidth,
    double bottom, {
    required String text,
    required bool isOut,
    required String time,
    String? senderName,
    Color? senderColor,
    String? replyName,
    String? replyText,
    bool showCheck = false,
    bool doubleCheck = false,
    bool attachToTop = false,
    bool attachToBottom = false,
    bool tail = true,
  }) {
    final maxBubbleW = math.min(chatWidth * 0.72, 430.0);
    const padding = 11.0;

    double textW = _estimateTextWidth(
        text.split('\n').fold<String>('', (a, b) => a.length > b.length ? a : b), 13) + padding * 2;
    if (senderName != null) {
      textW = math.max(textW, _estimateTextWidth(senderName, 13) + padding * 2);
    }
    if (replyName != null) {
      textW = math.max(textW, _estimateTextWidth(replyText ?? '', 12) + padding * 2 + 16);
    }
    final bubbleW = math.min(textW + 50, maxBubbleW);

    final lines = text.split('\n').length;
    double contentH = 8.0;
    if (senderName != null) contentH += 18;
    if (replyName != null) contentH += 38;
    contentH += lines * 18 + 4;
    contentH += 16;

    final bubbleBg = isOut ? palette.msgOutBg : palette.msgInBg;
    final textFg = isOut ? palette.historyTextOutFg : palette.historyTextInFg;
    final dateFg = isOut ? palette.msgOutDateFg : palette.msgInDateFg;

    final y = bottom - contentH;

    double bubbleX;
    if (isOut) {
      bubbleX = panelLeft + chatWidth - bubbleW - 16;
    } else {
      bubbleX = panelLeft + 16;
    }

    // Bubble shape
    final bubbleRect = Rect.fromLTWH(bubbleX, y, bubbleW, contentH);
    final topL = attachToTop && !isOut ? const Radius.circular(4) : const Radius.circular(16);
    final topR = attachToTop && isOut ? const Radius.circular(4) : const Radius.circular(16);
    final botL = !isOut && !attachToBottom && tail
        ? const Radius.circular(4)
        : (attachToBottom && !isOut ? const Radius.circular(4) : const Radius.circular(16));
    final botR = isOut && !attachToBottom && tail
        ? const Radius.circular(4)
        : (attachToBottom && isOut ? const Radius.circular(4) : const Radius.circular(16));
    final rrect = RRect.fromRectAndCorners(
      bubbleRect, topLeft: topL, topRight: topR, bottomLeft: botL, bottomRight: botR,
    );
    canvas.drawRRect(rrect, Paint()..color = bubbleBg);

    double cy = y + 8;

    // Sender name
    if (senderName != null) {
      _drawText(canvas, senderName, bubbleX + padding, cy, 13,
          senderColor ?? palette.historyPeer1NameFg, FontWeight.w600);
      cy += 18;
    }

    // Reply block
    if (replyName != null) {
      final replyBarColor = isOut ? palette.msgOutReplyBarColor : palette.msgInReplyBarColor;
      final replyBgPaint = Paint()..color = replyBarColor.withValues(alpha: 0.1);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(bubbleX + padding, cy, bubbleW - padding * 2, 34),
          const Radius.circular(4),
        ),
        replyBgPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(bubbleX + padding, cy, 3, 34),
          const Radius.circular(1.5),
        ),
        Paint()..color = replyBarColor,
      );
      _drawText(canvas, replyName, bubbleX + padding + 10, cy + 3,
          12, replyBarColor, FontWeight.w600);
      _drawText(canvas, replyText ?? '', bubbleX + padding + 10, cy + 18,
          12, textFg.withValues(alpha: 0.7), FontWeight.normal);
      cy += 38;
    }

    // Message text
    for (final line in text.split('\n')) {
      _drawText(canvas, line, bubbleX + padding, cy, 13, textFg, FontWeight.normal);
      cy += 18;
    }

    // Timestamp + checks
    final timeWidth = _estimateTextWidth(time, 11);
    final timeX = bubbleX + bubbleW - padding - timeWidth - (showCheck ? 22 : 0);
    final timeY = y + contentH - 18;
    _drawText(canvas, time, timeX, timeY, 11, dateFg, FontWeight.normal);

    if (showCheck) {
      final checkX = timeX + timeWidth + 4;
      final checkY = timeY + 2;
      _drawCheck(canvas, checkX, checkY, palette.historyOutIconFg, doubleCheck);
    }

    final margin = attachToTop ? 2.0 : 6.0;
    return y - margin;
  }

  double _drawServiceBubble(Canvas canvas, double panelLeft, double chatWidth,
      double bottom, String text) {
    const vPad = 5.0;
    const hPad = 12.0;
    final textWidth = _estimateTextWidth(text, 13);
    final bubbleW = textWidth + hPad * 2;
    final bubbleH = 13.0 + vPad * 2;
    final bubbleX = panelLeft + (chatWidth - bubbleW) / 2;
    final bubbleY = bottom - bubbleH;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(bubbleX, bubbleY, bubbleW, bubbleH),
        Radius.circular(bubbleH / 2),
      ),
      Paint()..color = palette.msgServiceBg,
    );
    _drawText(canvas, text, bubbleX + hPad, bubbleY + vPad, 13,
        palette.msgServiceFg, FontWeight.w500);
    return bubbleY - 8;
  }

  double _drawAudioBubbleBottomUp(Canvas canvas, double panelLeft,
      double chatWidth, double bottom) {
    const bubbleW = 260.0;
    const bubbleH = 52.0;
    const thumbSize = 33.0;
    const thumbLeft = 8.0;
    const thumbTop = 9.0;

    final bubbleX = panelLeft + chatWidth - bubbleW - 16;
    final y = bottom - bubbleH;

    // Bubble background
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(bubbleX, y, bubbleW, bubbleH),
        topLeft: const Radius.circular(16),
        topRight: const Radius.circular(16),
        bottomLeft: const Radius.circular(16),
        bottomRight: const Radius.circular(4),
      ),
      Paint()..color = palette.msgOutBg,
    );

    // Play button circle
    final circleCx = bubbleX + thumbLeft + thumbSize / 2;
    final circleCy = y + thumbTop + thumbSize / 2;
    canvas.drawCircle(
      Offset(circleCx, circleCy),
      thumbSize / 2,
      Paint()..color = palette.msgFileOutBg,
    );
    // Play triangle
    final playPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final playPath = Path()
      ..moveTo(circleCx - 4, circleCy - 7)
      ..lineTo(circleCx + 7, circleCy)
      ..lineTo(circleCx - 4, circleCy + 7)
      ..close();
    canvas.drawPath(playPath, playPaint);

    // Waveform bars
    const wavedata = [
      0, 0, 0, 0, 27, 31, 4, 1, 0, 0, 23, 30, 18, 9, 7, 19, 4, 2, 2, 2,
      0, 0, 15, 15, 15, 15, 3, 15, 19, 3, 2, 0, 0, 0, 0, 0, 3, 12, 16, 6,
      4, 6, 14, 12, 2, 12, 12, 11, 3, 0, 7, 5, 7, 4, 7, 5, 2, 4, 0, 9,
      5, 7, 6, 2, 2, 0, 0
    ];
    const waveActive = 33;
    const barWidth = 2.0;
    const barSpacing = 2.0;
    const maxBarHeight = 16.0;
    const minBarHeight = 2.0;
    const normValue = 31;
    final waveLeft = bubbleX + thumbLeft + thumbSize + 10;
    final waveBottom = y + thumbTop + thumbSize / 2 + maxBarHeight / 2;
    final waveRight = bubbleX + bubbleW - 50;
    final availW = waveRight - waveLeft;
    final barCount = math.min((availW / (barWidth + barSpacing)).floor(), wavedata.length);

    for (int i = 0; i < barCount; i++) {
      final dataIdx = (i * wavedata.length / barCount).floor();
      final value = wavedata[math.min(dataIdx, wavedata.length - 1)];
      final barH = minBarHeight + (value / normValue) * (maxBarHeight - minBarHeight);
      final barX = waveLeft + i * (barWidth + barSpacing);
      final barColor = i < waveActive
          ? palette.msgWaveformOutActive
          : palette.msgWaveformOutInactive;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(barX, waveBottom - barH, barWidth, barH + minBarHeight),
          const Radius.circular(1),
        ),
        Paint()..color = barColor,
      );
    }

    // Duration text
    _drawText(canvas, '0:07', waveLeft, y + thumbTop + thumbSize - 4, 11,
        palette.mediaOutFg, FontWeight.normal);

    // Timestamp + check
    final timeX = bubbleX + bubbleW - 11 - _estimateTextWidth('8:00', 11) - 22;
    final timeY = y + bubbleH - 18;
    _drawText(canvas, '8:00', timeX, timeY, 11, palette.msgOutDateFg, FontWeight.normal);
    _drawCheck(canvas, timeX + _estimateTextWidth('8:00', 11) + 4, timeY + 2,
        palette.historyOutIconFg, true);

    return y - 6;
  }

  double _drawPhotoBubbleBottomUp(Canvas canvas, double panelLeft,
      double chatWidth, double bottom) {
    const photoW = 200.0;
    const photoH = 150.0;
    const captionH = 28.0;
    const totalH = photoH + captionH;
    const bubbleW = photoW;

    final bubbleX = panelLeft + 16;
    final y = bottom - totalH;

    // Bubble background
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(bubbleX, y, bubbleW, totalH),
        topLeft: const Radius.circular(16),
        topRight: const Radius.circular(16),
        bottomLeft: const Radius.circular(4),
        bottomRight: const Radius.circular(16),
      ),
      Paint()..color = palette.msgInBg,
    );

    // Photo placeholder (gradient to simulate an image)
    final photoRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(bubbleX, y, photoW, photoH),
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
    );
    canvas.drawRRect(
      photoRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF6BA3D6), Color(0xFF3D7AB5), Color(0xFF2B5E8C)],
        ).createShader(Rect.fromLTWH(bubbleX, y, photoW, photoH)),
    );

    // Caption
    _drawText(canvas, 'To reach a port, we must sail. \u{1f978}',
        bubbleX + 11, y + photoH + 5, 13, palette.historyTextInFg, FontWeight.normal);

    // Time in photo area
    final timeW = _estimateTextWidth('7:00', 11);
    final timeBgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(bubbleX + bubbleW - timeW - 18, y + photoH - 22, timeW + 12, 18),
      const Radius.circular(9),
    );
    canvas.drawRRect(timeBgRect, Paint()..color = const Color(0x80000000));
    _drawText(canvas, '7:00',
        bubbleX + bubbleW - timeW - 12, y + photoH - 20, 11, Colors.white, FontWeight.normal);

    return y - 6;
  }

  void _drawComposeArea(Canvas canvas, double left, double chatWidth) {
    final composeY = 584.0 - _composeHeight;

    // Background
    canvas.drawRect(
      Rect.fromLTWH(left, composeY, chatWidth, _composeHeight),
      Paint()..color = palette.historyReplyBg,
    );

    // Top border
    canvas.drawRect(
      Rect.fromLTWH(left, composeY, chatWidth, 1),
      Paint()..color = palette.shadowFg,
    );

    // Attach icon (left side, 44px zone)
    final iconColor = palette.historyComposeIconFg;
    _drawAttachIcon(canvas, left + 12, composeY + 14, iconColor);

    // Text input field background
    const fieldLeft = 44.0;
    const fieldRight = 88.0;
    final fieldRect = Rect.fromLTWH(
        left + fieldLeft, composeY + 7, chatWidth - fieldLeft - fieldRight, 32);
    canvas.drawRRect(
      RRect.fromRectAndRadius(fieldRect, const Radius.circular(16)),
      Paint()..color = palette.historyComposeAreaBg,
    );

    // Placeholder text
    _drawText(canvas, 'Write a message...', left + fieldLeft + 12, composeY + 14, 13,
        palette.historyComposeAreaFg.withValues(alpha: 0.5), FontWeight.normal);

    // Emoji button (right of field, before record button)
    // AyuGram: fills emoji area with historyComposeAreaBg, draws icon, then circle outline
    final emojiX = left + chatWidth - 88;
    final emojiCY = composeY + _composeHeight / 2;
    canvas.drawRect(
      Rect.fromLTWH(emojiX, composeY, 44, _composeHeight),
      Paint()..color = palette.historyComposeAreaBg,
    );
    final emojiPaint = Paint()
      ..color = palette.historyComposeIconFg
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset(emojiX + 11, emojiCY), 9, emojiPaint);
    canvas.drawCircle(Offset(emojiX + 7.5, emojiCY - 2.5), 1.2, Paint()..color = palette.historyComposeIconFg);
    canvas.drawCircle(Offset(emojiX + 14.5, emojiCY - 2.5), 1.2, Paint()..color = palette.historyComposeIconFg);
    final smilePath = Path()
      ..addArc(Rect.fromCenter(center: Offset(emojiX + 11, emojiCY - 0.5), width: 10, height: 10),
          0.3, math.pi * 0.4);
    canvas.drawPath(smilePath, emojiPaint..strokeWidth = 1.2);
    // Circle outline around emoji icon (AyuGram: historyEmojiCircleFg + drawEllipse)
    final circlePaint = Paint()
      ..color = palette.historyComposeIconFg.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(emojiX + 11, emojiCY), width: 23, height: 23),
      circlePaint,
    );

    // Record button (microphone icon, rightmost 44px zone)
    final micX = left + chatWidth - 34;
    final micY = composeY + 14;
    final micPaint = Paint()
      ..color = palette.historyComposeIconFg
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    // Mic body
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(micX + 2, micY - 2, 8, 12),
        const Radius.circular(4),
      ),
      micPaint,
    );
    // Mic base arc
    final basePath = Path()
      ..addArc(Rect.fromLTWH(micX - 1, micY, 14, 14), 0, math.pi);
    canvas.drawPath(basePath, micPaint);
    // Mic stand
    canvas.drawLine(Offset(micX + 6, micY + 14), Offset(micX + 6, micY + 18), micPaint);
    canvas.drawLine(Offset(micX + 2, micY + 18), Offset(micX + 10, micY + 18), micPaint);
  }

  // ── Icon Drawing Helpers ──

  void _drawMenuDotsIcon(Canvas canvas, double x, double y, Paint paint) {
    final dotPaint = Paint()..color = paint.color;
    for (int i = 0; i < 3; i++) {
      canvas.drawCircle(Offset(x + 8, y + i * 6), 2, dotPaint);
    }
  }

  void _drawCallIcon(Canvas canvas, double x, double y, Paint paint) {
    final path = Path()
      ..moveTo(x + 3, y + 2)
      ..cubicTo(x + 5, y + 2, x + 6, y + 4, x + 6, y + 7)
      ..cubicTo(x + 7, y + 10, x + 10, y + 13, x + 13, y + 14)
      ..cubicTo(x + 16, y + 14, x + 18, y + 13, x + 18, y + 15)
      ..lineTo(x + 18, y + 18)
      ..cubicTo(x + 18, y + 19, x + 17, y + 20, x + 16, y + 20)
      ..cubicTo(x + 8, y + 20, x + 1, y + 13, x + 1, y + 5)
      ..cubicTo(x + 1, y + 3, x + 2, y + 2, x + 3, y + 2)
      ..close();
    canvas.drawPath(path, paint..style = PaintingStyle.stroke);
  }

  void _drawSearchIcon(Canvas canvas, double x, double y, Paint paint) {
    canvas.drawCircle(Offset(x + 9, y + 9), 7, paint..style = PaintingStyle.stroke);
    canvas.drawLine(Offset(x + 14, y + 14), Offset(x + 19, y + 19),
        paint..strokeWidth = 2.0);
  }

  // ── Text Helpers ──

  String _initials(String name) {
    final parts = name.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}';
    return name.substring(0, 1);
  }

  void _drawText(Canvas canvas, String text, double x, double y, double fontSize,
      Color color, FontWeight weight, {double? maxWidth}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, fontWeight: weight, color: color),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    );
    tp.layout(maxWidth: maxWidth ?? 500);
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

  @override
  bool shouldRepaint(_ThemePreviewPainter old) =>
      !identical(old.palette, palette);
}

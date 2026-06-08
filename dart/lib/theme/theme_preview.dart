import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'telegram_palette.dart';
import 'wallpaper.dart';

class ThemePreviewImage extends StatefulWidget {
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
  State<ThemePreviewImage> createState() => _ThemePreviewImageState();
}

class _ThemePreviewImageState extends State<ThemePreviewImage> {
  ui.Image? _photoImage;
  ui.Image? _wallpaperImage;

  @override
  void initState() {
    super.initState();
    _loadThemeImage();
    _generateWallpaper();
  }

  Future<void> _loadThemeImage() async {
    try {
      final data = await rootBundle.load('assets/images/themeimage.jpg');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() => _photoImage = frame.image);
      }
    } catch (_) {
      // Fallback to gradient if image can't be loaded
    }
  }

  // The default chat wallpaper (AyuGram paints it over the history region when
  // the theme has no embedded background — window_theme_preview.cpp:462-485).
  // For the theme wallpaper it overlays the Telegram doodle pattern
  // (`:/gui/art/background.tgv`) on the fixed 4-colour default gradient via
  // PreparePatternImage at intensity 50 (cpp:468-480). The result is
  // palette-independent, so it is generated once.
  Future<void> _generateWallpaper() async {
    ui.Image? image;
    try {
      final tgv = await rootBundle.load('assets/images/background.tgv');
      image = await prepareDefaultPatternImage(tgv.buffer.asUint8List());
    } catch (_) {
      image = null;
    }
    // Fall back to the plain default gradient (no doodle) if the pattern asset
    // can't be loaded or decoded, so the chat area never shows a flat windowBg.
    if (image == null) {
      const size = 256;
      try {
        image = await decodeRgbaPixels(
            defaultWallpaperGradientPixels(size: size), size, size);
      } catch (_) {
        image = null;
      }
    }
    if (!mounted) {
      image?.dispose();
      return;
    }
    setState(() {
      _wallpaperImage?.dispose();
      _wallpaperImage = image;
    });
  }

  @override
  void dispose() {
    _photoImage?.dispose();
    _wallpaperImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(widget.width, widget.height),
      painter: _ThemePreviewPainter(
        palette: widget.palette,
        photoImage: _photoImage,
        wallpaperImage: _wallpaperImage,
      ),
    );
  }
}

class _ThemePreviewPainter extends CustomPainter {
  final TelegramPalette palette;
  final ui.Image? photoImage;
  final ui.Image? wallpaperImage;

  _ThemePreviewPainter({
    required this.palette,
    this.photoImage,
    this.wallpaperImage,
  });

  static const double _canvasWidth = 903;
  static const double _canvasHeight = 584;
  static const double _dialogsWidth = 312;
  static const double _topBarHeight = 54;
  static const double _composeHeight = 46;
  static const double _rowHeight = 62;
  static const double _avatarSize = 46;
  static const double _avatarLeft = 10;
  static const double _textLeft = 68;

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / _canvasWidth;
    final scaleY = size.height / _canvasHeight;
    canvas.save();
    canvas.scale(scaleX, scaleY);

    _drawDialogsPanel(canvas);
    _drawChatPanel(canvas);

    canvas.restore();
  }

  void _drawDialogsPanel(Canvas canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _dialogsWidth, _canvasHeight),
      Paint()..color = palette.dialogsBg,
    );

    // Hamburger menu icon
    _drawMaterialIcon(canvas, Icons.menu, 12, 15, 24, palette.dialogsMenuIconFg);

    // Search filter field
    const filterLeft = 58.0;
    const filterTop = 11.0;
    const filterHeight = 32.0;
    const filterWidth = _dialogsWidth - filterLeft - 14.0;
    final filterRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(filterLeft, filterTop, filterWidth, filterHeight),
      const Radius.circular(16),
    );
    // AyuGram fills the filter field with dialogsFilter.textBg = filterInputInactiveBg.
    canvas.drawRRect(filterRect, Paint()..color = palette.filterInputInactiveBg);
    _drawText(canvas, 'Search', filterLeft + 14, filterTop + 8, 13,
        palette.windowSubTextFg, FontWeight.normal);

    // 8 dialog rows
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
    const statusFlags = [0, 0, 0, 0, 0, 2, 2, 0];
    // AyuGram peer color index per row (the addRow() 2nd arg in generateData).
    const peerIndices = [0, 7, 2, 1, 6, 3, 4, 5];
    // Row::Type::Group rows (Evening Club, Old Pirates) get a chat-type icon.
    const groupFlags = [false, false, false, true, true, false, false, false];
    // Ui::Text::Colorized previews: 0=plain, -1=whole accent, n>0=first n chars.
    const previewColorized = [0, 0, -1, -1, 4, 0, 0, -1];
    // ColorIndexToPaletteIndex map (chat_style.cpp): colorIndex -> palette slot.
    const colorIndexToPalette = [0, 7, 4, 1, 6, 3, 5];
    const activeIndex = 0;

    const double startY = 54;

    for (int i = 0; i < 8; i++) {
      final y = startY + i * _rowHeight;
      if (y + _rowHeight > _canvasHeight) break;

      final isActive = i == activeIndex;

      canvas.drawRect(
        Rect.fromLTWH(0, y, _dialogsWidth, _rowHeight),
        Paint()..color = isActive ? palette.dialogsBgActive : palette.dialogsBg,
      );

      // Avatar circle — AyuGram empty userpic: vertical gradient color1(top)→
      // color2(bottom); color slot = ColorIndexToPaletteIndex(peerIndex % 7).
      final avatarCx = _avatarLeft + _avatarSize / 2;
      final avatarCy = y + 8 + _avatarSize / 2;
      final paletteSlot = colorIndexToPalette[peerIndices[i] % 7];
      canvas.drawCircle(
        Offset(avatarCx, avatarCy),
        _avatarSize / 2,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(avatarCx, avatarCy - _avatarSize / 2),
            Offset(avatarCx, avatarCy + _avatarSize / 2),
            [
              palette.peerUserpicBg(paletteSlot),
              palette.peerUserpicBg2(paletteSlot),
            ],
          ),
      );
      // Initials, centered. AyuGram font = (size * 13) / 33 → 18px for a 46px avatar.
      final initials = _initials(names[i]);
      const initialsSize = 18.0;
      final initialsW = _estimateTextWidth(initials, initialsSize);
      _drawText(
        canvas,
        initials,
        avatarCx - initialsW / 2,
        avatarCy - initialsSize / 2 - 1,
        initialsSize,
        Colors.white,
        FontWeight.w500,
      );

      // Chat-type icon (Group): AyuGram dialogsChatIcon before the name, then
      // shift the name right by icon.width()(16) + dialogsChatTypeSkip(3) = 19.
      double nameLeft = _textLeft;
      if (groupFlags[i]) {
        _drawGroupIcon(canvas, _textLeft, y + 13,
            isActive ? palette.dialogsChatIconFgActive : palette.dialogsChatIconFg);
        nameLeft += 19;
      }

      // Name
      final nameFg = isActive ? palette.dialogsNameFgActive : palette.dialogsNameFg;
      _drawText(canvas, names[i], nameLeft, y + 10, 13, nameFg, FontWeight.w600,
          maxWidth: 155 - (nameLeft - _textLeft));

      // Sent status icon before date
      if (statusFlags[i] > 0) {
        final checkFg = isActive ? palette.dialogsTextFgActive : palette.dialogsSentIconFg;
        final checkX = _dialogsWidth - 10 - _estimateTextWidth(times[i], 12) - 20;
        _drawCheckIcon(canvas, checkX, y + 10, checkFg, statusFlags[i] == 2);
      }

      // Timestamp
      final dateFg = isActive ? palette.dialogsDateFgActive : palette.dialogsDateFg;
      _drawTextRight(canvas, times[i], _dialogsWidth - 10, y + 12, 12, dateFg);

      // Preview text — AyuGram wraps some previews in Ui::Text::Colorized, which
      // renders in the dialogs text palette's linkFg = dialogsTextFgService accent.
      final previewFg = isActive ? palette.dialogsTextFgActive : palette.dialogsTextFg;
      final previewLinkFg =
          isActive ? palette.dialogsTextFgActive : palette.dialogsTextFgService;
      final clen = previewColorized[i];
      final List<TextSpan> previewSpans;
      if (isActive || clen == 0) {
        previewSpans = [
          TextSpan(
              text: previews[i],
              style: TextStyle(fontSize: 13, color: previewFg)),
        ];
      } else if (clen < 0) {
        previewSpans = [
          TextSpan(
              text: previews[i],
              style: TextStyle(fontSize: 13, color: previewLinkFg)),
        ];
      } else {
        previewSpans = [
          TextSpan(
              text: previews[i].substring(0, clen),
              style: TextStyle(fontSize: 13, color: previewLinkFg)),
          TextSpan(
              text: previews[i].substring(clen),
              style: TextStyle(fontSize: 13, color: previewFg)),
        ];
      }
      final previewTp = TextPainter(
        text: TextSpan(children: previewSpans),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      );
      previewTp.layout(maxWidth: 170);
      previewTp.paint(canvas, Offset(_textLeft, y + 34));

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
        final pinColor = isActive ? palette.dialogsTextFgActive : palette.dialogsDateFg;
        _drawMaterialIcon(canvas, Icons.push_pin, _dialogsWidth - 26, y + 34, 16, pinColor);
      }
    }

    // Separator shadow
    canvas.drawRect(
      const Rect.fromLTWH(_dialogsWidth - 1, 0, 1, _canvasHeight),
      Paint()..color = palette.shadowFg,
    );
  }

  void _drawChatPanel(Canvas canvas) {
    const left = _dialogsWidth;
    const chatWidth = _canvasWidth - _dialogsWidth;

    // Chat background
    canvas.drawRect(
      const Rect.fromLTWH(left, 0, chatWidth, _canvasHeight),
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

    // Top bar: name and status. The "online" status is active
    // (_topBarStatusActive = true, generateData), so AyuGram paints it with
    // historyStatusFgActive (window_theme_preview.cpp:550) — which the palette
    // binds to windowActiveTextFg (chat.style:460), NOT contactsStatusFgOnline
    // (the two diverge in night/macOS and custom/cloud themes).
    _drawText(canvas, 'Eva Summer', left + 17, 8, 15,
        palette.dialogsNameFg, FontWeight.w600);
    _drawText(canvas, 'online', left + 17, 32, 13,
        palette.windowActiveTextFg, FontWeight.normal);

    // Top bar: right-aligned icons using AyuGram button widths
    // topBarMenuToggle.width=44, topBarSkip=-5, topBarCall.width=40, topBarSearch.width=40
    // right accumulates: menu=44, call=44+(-5)+40=79, search=79+40=119
    // Icon centers at rightEdge - (buttonRight - buttonWidth/2), icon x = center - 12
    final iconFg = palette.dialogsMenuIconFg;
    final rightEdge = left + chatWidth;

    _drawDotsVertIcon(canvas, rightEdge - 34, 15, 24, iconFg);
    _drawPhoneCallIcon(canvas, rightEdge - 71, 15, 24, iconFg);
    _drawSearchIcon(canvas, rightEdge - 111, 15, 24, iconFg);

    // Message area
    _drawMessageArea(canvas, left, chatWidth);

    // Compose area
    _drawComposeArea(canvas, left, chatWidth);
  }

  // Port of Ui::ComputeChatBackgroundRects (chat_theme.cpp:833-878): cover-fit
  // [image] into [fill], returning the source crop ([from]) and destination
  // ([to]) rects. The axis where the image is relatively smaller is filled and
  // the other centre-cropped, with the crop extent parity-matched to the image.
  // C++ `int(...)` truncates toward zero, so the centring offset (which can be
  // negative) uses truncateToDouble, not floor.
  ({Rect from, Rect to}) _computeChatBackgroundRects(Size fill, Size image) {
    final iw = image.width.toInt();
    final ih = image.height.toInt();
    final fw = fill.width;
    final fh = fill.height;
    if (iw * fh > ih * fw) {
      final pxsize = fh / ih;
      var takewidth = (fw / pxsize).ceil();
      if (takewidth > iw) {
        takewidth = iw;
      } else if ((iw % 2) != (takewidth % 2)) {
        takewidth++;
      }
      return (
        from: Rect.fromLTWH(
            ((iw - takewidth) ~/ 2).toDouble(), 0, takewidth.toDouble(),
            ih.toDouble()),
        to: Rect.fromLTWH(
            ((fw - takewidth * pxsize) / 2).truncateToDouble(), 0,
            (takewidth * pxsize).ceilToDouble(), fh),
      );
    } else {
      final pxsize = fw / iw;
      var takeheight = (fh / pxsize).ceil();
      if (takeheight > ih) {
        takeheight = ih;
      } else if ((ih % 2) != (takeheight % 2)) {
        takeheight++;
      }
      return (
        from: Rect.fromLTWH(
            0, ((ih - takeheight) ~/ 2).toDouble(), iw.toDouble(),
            takeheight.toDouble()),
        to: Rect.fromLTWH(
            0, ((fh - takeheight * pxsize) / 2).truncateToDouble(),
            fw, (takeheight * pxsize).ceilToDouble()),
      );
    }
  }

  void _drawMessageArea(Canvas canvas, double left, double chatWidth) {
    final areaBottom = _canvasHeight - _composeHeight;

    // Clip to the history region so the oldest (topmost) bubble is cut cleanly at
    // the top-bar edge instead of overlapping the top bar (matches AyuGram, where
    // the first photo message is scrolled partly under the header).
    final historyRect =
        Rect.fromLTWH(left, _topBarHeight, chatWidth, areaBottom - _topBarHeight);
    canvas.save();
    canvas.clipRect(historyRect);

    // Chat background wallpaper. AyuGram's paintHistoryBackground() paints the
    // default wallpaper (the 4-colour gradient + doodle pattern) over the
    // history region, on top of the base windowBg fill, before drawing any
    // bubbles (window_theme_preview.cpp:444-485). It is cover-fit into a
    // `chatWidth × _canvasHeight` box via ComputeChatBackgroundRects and anchored
    // to the body top (shifted up by topBarHeight, `fromy`), so the history shows
    // the centre band rather than the whole image squashed flat (cpp:519-530).
    // Until it decodes, fall back to the gradient's average tone so the chat area
    // never shows a flat windowBg.
    final wp = wallpaperImage;
    if (wp != null) {
      const fromy = -_topBarHeight;
      final rects = _computeChatBackgroundRects(
        Size(chatWidth, _canvasHeight),
        Size(wp.width.toDouble(), wp.height.toDouble()),
      );
      // to.moveTop(+fromy) then to.moveTopLeft(+_history.topLeft()=(left,topBar)).
      final dst = rects.to.translate(left, _topBarHeight + fromy);
      canvas.drawImageRect(
        wp,
        rects.from,
        dst,
        Paint()..filterQuality = FilterQuality.high,
      );
    } else {
      canvas.drawRect(historyRect, Paint()..color = const Color(0xFFA9C595));
    }

    var historyBottom = areaBottom - 8.0;

    // Bubble 6 (bottom): incoming with reply
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
    _drawPhotoBubbleBottomUp(canvas, left, chatWidth, historyBottom);

    canvas.restore();
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

    // Bubble shape — BubbleRounding (message_bubble.cpp:835-859): every corner
    // starts Large(16); attachToTop/Bottom downgrades a corner to Small(4); a
    // tail downgrades the bottom corner on the message's own side to a Tail,
    // which Ui::PaintBubble renders as a SHARP corner (radius 0) plus a drawn
    // tail pointer (message_bubble.cpp:59-64, 153-158).
    final bubbleRect = Rect.fromLTWH(bubbleX, y, bubbleW, contentH);
    const large = Radius.circular(16);
    const small = Radius.circular(4);
    var topL = large, topR = large, botL = large, botR = large;
    var tailLeft = false, tailRight = false;
    if (isOut) {
      if (attachToTop) topR = small;
      if (attachToBottom) {
        botR = small;
      } else if (tail) {
        botR = Radius.zero;
        tailRight = true;
      }
    } else {
      if (attachToTop) topL = small;
      if (attachToBottom) {
        botL = small;
      } else if (tail) {
        botL = Radius.zero;
        tailLeft = true;
      }
    }
    final rrect = RRect.fromRectAndCorners(
      bubbleRect, topLeft: topL, topRight: topR, bottomLeft: botL, bottomRight: botR,
    );
    canvas.drawRRect(rrect, Paint()..color = bubbleBg);
    if (tailLeft) {
      _drawBubbleTail(canvas, bubbleX, y + contentH, bubbleBg, right: false);
    }
    if (tailRight) {
      _drawBubbleTail(canvas, bubbleX + bubbleW, y + contentH, bubbleBg, right: true);
    }

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
      // Reply sender name → msgInServiceFg/msgOutServiceFg (= windowActiveTextFg
      // accent), NOT the reply-bar colour; reply text → full-opacity
      // historyTextInFg/historyTextOutFg (window_theme_preview.cpp:907-911).
      final replyNameFg = isOut ? palette.msgOutServiceFg : palette.msgInServiceFg;
      _drawText(canvas, replyName, bubbleX + padding + 10, cy + 3,
          12, replyNameFg, FontWeight.w600);
      _drawText(canvas, replyText ?? '', bubbleX + padding + 10, cy + 18,
          12, textFg, FontWeight.normal);
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
      _drawCheckIcon(canvas, timeX + timeWidth + 4, timeY, palette.historyOutIconFg, doubleCheck);
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
    // AyuGram msgFileLayout: padding(12,8,10,8), thumbSize 44 → height 8+44+8=60.
    const bubbleH = 60.0;
    const thumbSize = 44.0;
    const thumbLeft = 12.0;
    const thumbTop = 8.0;

    final bubbleX = panelLeft + chatWidth - bubbleW - 16;
    final y = bottom - bubbleH;

    // Bubble background — outgoing, standalone: bottom-right is a Tail, drawn as
    // a sharp corner plus a tail pointer (message_bubble.cpp:847-849, 153-158).
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(bubbleX, y, bubbleW, bubbleH),
        topLeft: const Radius.circular(16),
        topRight: const Radius.circular(16),
        bottomLeft: const Radius.circular(16),
        bottomRight: Radius.zero,
      ),
      Paint()..color = palette.msgOutBg,
    );
    _drawBubbleTail(canvas, bubbleX + bubbleW, y + bubbleH, palette.msgOutBg,
        right: true);

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
      ..moveTo(circleCx - 5, circleCy - 9)
      ..lineTo(circleCx + 9, circleCy)
      ..lineTo(circleCx - 5, circleCy + 9)
      ..close();
    canvas.drawPath(playPath, playPaint);

    // Waveform bars
    const wavedata = [
      0, 0, 0, 0, 27, 31, 4, 1, 0, 0, 23, 30, 18, 9, 7, 19, 4, 2, 2, 2,
      0, 0, 15, 15, 15, 15, 3, 15, 19, 3, 2, 0, 0, 0, 0, 0, 3, 12, 16, 6,
      4, 6, 14, 12, 2, 12, 12, 11, 3, 0, 7, 5, 7, 4, 7, 5, 2, 4, 0, 9,
      5, 7, 6, 2, 2, 0, 0
    ];
    // waveActive indexes the 67-element wavedata array (the DATA index up to
    // which the message has been "played"), NOT the downsampled bar index.
    const waveActive = 33;
    const barWidth = 2.0; // msgWaveformBar (chat.style:557)
    // msgWaveformSkip = 1px (chat.style:558) → 3px pitch with the 2px bar.
    const barSpacing = 1.0;
    // AyuGram waveform amplitude range (chat.style:559-560): each bar is bottom-
    // anchored at waveBottom + msgWaveformMin and grows upward by bar_value in
    // [0, msgWaveformMax - msgWaveformMin] (window_theme_preview.cpp:947,961-963).
    const msgWaveformMin = 3.0;
    const msgWaveformMax = 17.0;
    const maxDelta = msgWaveformMax - msgWaveformMin;
    const normValue = 31;
    // statusTop (chat.style:511) — duration text top within the file layout.
    const statusTop = 34.0;
    final waveLeft = bubbleX + thumbLeft + thumbSize + 11;
    // wave_bottom = y + padding.top + msgWaveformMax (window_theme_preview.cpp:948),
    // so bars occupy the upper "name" row, not the play-button centre line.
    final waveBottom = y + thumbTop + msgWaveformMax;
    final waveRight = bubbleX + bubbleW - 50;
    final availW = waveRight - waveLeft;
    final barCount = math.min((availW / (barWidth + barSpacing)).floor(), wavedata.length);

    for (int i = 0; i < barCount; i++) {
      final dataIdx = (i * wavedata.length / barCount).floor();
      final value = wavedata[math.min(dataIdx, wavedata.length - 1)];
      // bar_value ∈ [0, maxDelta]; rect top = wave_bottom - bar_value, height =
      // msgWaveformMin + bar_value (window_theme_preview.cpp:961-963).
      final barValue = (value / normValue) * maxDelta;
      final barX = waveLeft + i * (barWidth + barSpacing);
      // AyuGram colors a bar "played" by the DATA index it samples, not the bar
      // index (window_theme_preview.cpp:960 `if (i >= bubble.waveactive)`, where
      // `i` iterates the 67 samples). Comparing the bar index `i` against 33
      // would paint ~94% of the ~35 bars active; comparing dataIdx gives ~half.
      final barColor = dataIdx < waveActive
          ? palette.msgWaveformOutActive
          : palette.msgWaveformOutInactive;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(barX, waveBottom - barValue, barWidth, msgWaveformMin + barValue),
          const Radius.circular(1),
        ),
        Paint()..color = barColor,
      );
    }

    // Duration text ("0:07") at (nameleft, statusTop) = (waveLeft, y+34) —
    // above the timestamp, not at the bubble's bottom edge (cpp:925,982).
    _drawText(canvas, '0:07', waveLeft, y + statusTop, 11,
        palette.mediaOutFg, FontWeight.normal);

    // Timestamp + check
    final timeX = bubbleX + bubbleW - 11 - _estimateTextWidth('8:00', 11) - 22;
    final timeY = y + bubbleH - 18;
    _drawText(canvas, '8:00', timeX, timeY, 11, palette.msgOutDateFg, FontWeight.normal);
    _drawCheckIcon(canvas, timeX + _estimateTextWidth('8:00', 11) + 4, timeY,
        palette.historyOutIconFg, true);

    return y - 6;
  }

  double _drawPhotoBubbleBottomUp(Canvas canvas, double panelLeft,
      double chatWidth, double bottom) {
    // AyuGram: photoWidth/Height = ConvertScale(image/2), width clamped to the
    // history width and msgMaxWidth(430). themeimage.jpg is 654x395 → 327x197.
    double photoW = 327;
    double photoH = 197;
    if (photoImage != null) {
      photoW = (photoImage!.width / 2).floorToDouble();
      photoH = (photoImage!.height / 2).floorToDouble();
    }
    final maxPhotoW = math.min(chatWidth - 16 - 56, 430.0);
    if (photoW > maxPhotoW) {
      photoH = photoH * (maxPhotoW / photoW);
      photoW = maxPhotoW;
    }
    const captionH = 28.0;
    final totalH = photoH + captionH;
    final bubbleW = photoW;

    final bubbleX = panelLeft + 16;
    final y = bottom - totalH;

    // Bubble background — incoming, standalone: bottom-left is a Tail, drawn as
    // a sharp corner plus a tail pointer (message_bubble.cpp:856-857, 153-158).
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(bubbleX, y, bubbleW, totalH),
        topLeft: const Radius.circular(16),
        topRight: const Radius.circular(16),
        bottomLeft: Radius.zero,
        bottomRight: const Radius.circular(16),
      ),
      Paint()..color = palette.msgInBg,
    );
    _drawBubbleTail(canvas, bubbleX, y + totalH, palette.msgInBg, right: false);

    // Caption and time drawn BEFORE photo (AyuGram draws photo last, on top)
    _drawText(canvas, 'To reach a port, we must sail. \u{1f978}',
        bubbleX + 11, y + photoH + 5, 13, palette.historyTextInFg, FontWeight.normal);

    final timeW = _estimateTextWidth('7:00', 11);
    _drawText(canvas, '7:00',
        bubbleX + bubbleW - timeW - 12, y + totalH - 16, 11,
        palette.msgInDateFg, FontWeight.normal);

    // Photo area drawn last (matches AyuGram rendering order)
    final photoRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(bubbleX, y, photoW, photoH),
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
    );
    canvas.save();
    canvas.clipRRect(photoRect);
    if (photoImage != null) {
      final src = Rect.fromLTWH(
        0, 0,
        photoImage!.width.toDouble(),
        photoImage!.height.toDouble(),
      );
      final dst = Rect.fromLTWH(bubbleX, y, photoW, photoH);
      canvas.drawImageRect(photoImage!, src, dst, Paint());
    } else {
      canvas.drawRect(
        Rect.fromLTWH(bubbleX, y, photoW, photoH),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6BA3D6), Color(0xFF3D7AB5), Color(0xFF2B5E8C)],
          ).createShader(Rect.fromLTWH(bubbleX, y, photoW, photoH)),
      );
    }
    canvas.restore();

    return y - 6;
  }

  void _drawComposeArea(Canvas canvas, double left, double chatWidth) {
    final composeY = _canvasHeight - _composeHeight;
    // AyuGram: historyAttach.width=44, historySendSize=44x46, historySendRight=2,
    // historyAttachEmoji.inner.width=44, historySendPadding=9
    const attachWidth = 44.0;
    const emojiWidth = 44.0;
    const sendWidth = 44.0;
    const sendRight = 2.0;

    canvas.drawRect(
      Rect.fromLTWH(left, composeY, chatWidth, _composeHeight),
      Paint()..color = palette.historyReplyBg,
    );

    canvas.drawRect(
      Rect.fromLTWH(left, composeY, chatWidth, 1),
      Paint()..color = palette.shadowFg,
    );

    // Attach button icon centered in 44px button (iconPosition auto-centered)
    _drawPaperclipIcon(canvas, left + 10, composeY + 11, 24, palette.historyComposeIconFg);

    // Mic/record icon: AyuGram paints in historySendSize area offset by historySendRight
    final sendAreaLeft = left + chatWidth - sendRight - sendWidth;
    _drawMicrophoneIcon(
      canvas, sendAreaLeft + 10, composeY + 11, 24,
      palette.historyComposeIconFg,
    );

    // Emoji button positioned from right using AyuGram's accumulation:
    // right = historySendRight(2) + sendWidth(44) + emojiWidth(44) = 90
    final emojiLeft = left + chatWidth - sendRight - sendWidth - emojiWidth;
    canvas.drawRect(
      Rect.fromLTWH(emojiLeft, composeY, emojiWidth, _composeHeight),
      Paint()..color = palette.historyComposeAreaBg,
    );
    const emojiIconSize = 22.0;
    final emojiIconX = emojiLeft + (emojiWidth - emojiIconSize) / 2;
    final emojiIconY = composeY + (_composeHeight - emojiIconSize) / 2;
    _drawEmojiSmileyIcon(canvas, emojiIconX, emojiIconY, emojiIconSize, palette.historyComposeIconFg);

    // Field area: between attach button and emoji button
    final fieldRect = Rect.fromLTWH(
        left + attachWidth, composeY + 7,
        chatWidth - attachWidth - emojiWidth - sendWidth - sendRight, 32);
    canvas.drawRRect(
      RRect.fromRectAndRadius(fieldRect, const Radius.circular(16)),
      Paint()..color = palette.historyComposeAreaBg,
    );

    // AyuGram: lng_message_ph = "Message" (localized placeholder). Colour =
    // historyComposeField.placeholderFg = placeholderFg = windowSubTextFg
    // (colors.palette:73, window_theme_preview.cpp:616) — the same token used by
    // the dialogs search placeholder above, NOT windowFg@50%.
    _drawText(canvas, 'Message', left + attachWidth + 12, composeY + 14, 13,
        palette.windowSubTextFg, FontWeight.normal);
  }

  // ── Icon Drawing Helpers ──

  // AyuGram message-bubble tail (chat.style:439-446 `bubble_tail` icon, colorized
  // with msgInBg/msgOutBg; message_bubble.cpp:153-158). A Corner::Tail bottom
  // corner is drawn sharp and this 6×10 pointer is painted just outside it, in
  // the bubble's own bg colour. Mask shape (Resources/icons/bubble_tail.png) is a
  // right triangle whose right angle sits at the bubble's bottom corner, tapering
  // ~6px outward and ~8px up. [right]=true mirrors it for outgoing bubbles.
  void _drawBubbleTail(Canvas canvas, double x, double bottom, Color color,
      {required bool right}) {
    final path = Path()
      ..moveTo(x, bottom - 8)
      ..lineTo(x, bottom)
      ..lineTo(x + (right ? 6 : -6), bottom)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
  }

  // AyuGram dialogsChatIcon (Row::Type::Group) — a compact two-person glyph
  // (~16x10) painted before group-row names in the dialogs list.
  void _drawGroupIcon(Canvas canvas, double x, double y, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    // Back person (left, slightly smaller).
    canvas.drawCircle(Offset(x + 4.5, y + 2.6), 2.3, paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x + 0.8, y + 4.9, 7.4, 5.1),
        const Radius.circular(2.5),
      ),
      paint,
    );
    // Front person (right), drawn over the back one to read as a group.
    canvas.drawCircle(Offset(x + 10.8, y + 3.0), 2.8, paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x + 6.6, y + 5.5, 8.6, 4.5),
        const Radius.circular(2.6),
      ),
      paint,
    );
  }

  void _drawMaterialIcon(Canvas canvas, IconData icon, double x, double y,
      double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: size,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, Offset(x, y));
  }

  void _drawDotsVertIcon(Canvas canvas, double x, double y, double size, Color color) {
    final paint = Paint()..color = color;
    final cx = x + size / 2;
    final r = size * 0.1;
    for (final f in [0.24, 0.5, 0.76]) {
      canvas.drawCircle(Offset(cx, y + size * f), r, paint);
    }
  }

  void _drawSearchIcon(Canvas canvas, double x, double y, double size, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size * 0.09
      ..strokeCap = StrokeCap.round;
    final r = size * 0.28;
    final cx = x + size * 0.42;
    final cy = y + size * 0.42;
    canvas.drawCircle(Offset(cx, cy), r, paint);
    canvas.drawLine(
      Offset(cx + r * 0.71, cy + r * 0.71),
      Offset(x + size * 0.82, y + size * 0.82),
      paint,
    );
  }

  void _drawPhoneCallIcon(Canvas canvas, double x, double y, double size, Color color) {
    final s = size / 24;
    final path = Path()
      ..moveTo(x + 6.6 * s, y + 10.8 * s)
      ..cubicTo(x + 8.1 * s, y + 13.6 * s, x + 10.4 * s, y + 15.9 * s,
          x + 13.2 * s, y + 17.4 * s)
      ..lineTo(x + 14.5 * s, y + 16.1 * s)
      ..cubicTo(x + 14.8 * s, y + 15.8 * s, x + 15.3 * s, y + 15.7 * s,
          x + 15.7 * s, y + 15.8 * s)
      ..cubicTo(x + 17.1 * s, y + 16.4 * s, x + 18.7 * s, y + 16.7 * s,
          x + 20.3 * s, y + 16.7 * s)
      ..cubicTo(x + 21.0 * s, y + 16.7 * s, x + 21.6 * s, y + 17.3 * s,
          x + 21.6 * s, y + 18.0 * s)
      ..lineTo(x + 21.6 * s, y + 20.0 * s)
      ..cubicTo(x + 21.6 * s, y + 20.6 * s, x + 21.0 * s, y + 21.0 * s,
          x + 20.5 * s, y + 21.0 * s)
      ..cubicTo(x + 11.3 * s, y + 21.0 * s, x + 3.0 * s, y + 13.3 * s,
          x + 3.0 * s, y + 4.0 * s)
      ..cubicTo(x + 3.0 * s, y + 3.4 * s, x + 3.4 * s, y + 3.0 * s,
          x + 4.0 * s, y + 3.0 * s)
      ..lineTo(x + 7.0 * s, y + 3.0 * s)
      ..cubicTo(x + 7.6 * s, y + 3.0 * s, x + 8.0 * s, y + 3.4 * s,
          x + 8.0 * s, y + 4.0 * s)
      ..cubicTo(x + 8.0 * s, y + 5.6 * s, x + 8.3 * s, y + 7.1 * s,
          x + 8.8 * s, y + 8.5 * s)
      ..cubicTo(x + 8.9 * s, y + 8.9 * s, x + 8.8 * s, y + 9.3 * s,
          x + 8.5 * s, y + 9.6 * s)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _drawMicrophoneIcon(Canvas canvas, double x, double y, double size, Color color) {
    final s = size / 24;
    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * s
      ..strokeCap = StrokeCap.round;
    final cx = x + size / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - 3.5 * s, y + 3 * s, 7 * s, 10 * s),
        Radius.circular(3.5 * s),
      ),
      fill,
    );
    canvas.drawArc(
      Rect.fromLTWH(cx - 5.5 * s, y + 7 * s, 11 * s, 11 * s),
      0, math.pi, false, stroke,
    );
    canvas.drawLine(
      Offset(cx, y + 18 * s), Offset(cx, y + 21 * s), stroke,
    );
  }

  void _drawEmojiSmileyIcon(Canvas canvas, double x, double y, double size, Color color) {
    // AyuGram: historyEmojiCircleLine = 1.5px stroke width
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = color;
    final cx = x + size / 2;
    final cy = y + size / 2;
    final r = size * 0.42;
    canvas.drawCircle(Offset(cx, cy), r, stroke);
    final eyeR = size * 0.05;
    final eyeY = cy - r * 0.2;
    canvas.drawCircle(Offset(cx - r * 0.35, eyeY), eyeR, fill);
    canvas.drawCircle(Offset(cx + r * 0.35, eyeY), eyeR, fill);
    final smileR = r * 0.5;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy + r * 0.05), radius: smileR),
      0.2, math.pi - 0.4, false, stroke,
    );
  }

  void _drawPaperclipIcon(Canvas canvas, double x, double y, double size, Color color) {
    final s = size / 24;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * s
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(x + 18 * s, y + 7 * s)
      ..lineTo(x + 18 * s, y + 17.5 * s)
      ..arcToPoint(
        Offset(x + 7 * s, y + 17.5 * s),
        radius: Radius.circular(5.5 * s),
        clockwise: false,
      )
      ..lineTo(x + 7 * s, y + 5 * s)
      ..arcToPoint(
        Offset(x + 15 * s, y + 5 * s),
        radius: Radius.circular(4 * s),
        clockwise: false,
      )
      ..lineTo(x + 15 * s, y + 15.5 * s)
      ..arcToPoint(
        Offset(x + 10 * s, y + 15.5 * s),
        radius: Radius.circular(2.5 * s),
        clockwise: false,
      )
      ..lineTo(x + 10 * s, y + 7 * s);
    canvas.drawPath(path, paint);
  }

  void _drawCheckIcon(Canvas canvas, double x, double y, Color color, bool isDouble) {
    if (isDouble) {
      _drawMaterialIcon(canvas, Icons.done_all, x, y, 14, color);
    } else {
      _drawMaterialIcon(canvas, Icons.check, x, y, 14, color);
    }
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

  @override
  bool shouldRepaint(_ThemePreviewPainter old) =>
      !identical(old.palette, palette) ||
      !identical(old.photoImage, photoImage) ||
      !identical(old.wallpaperImage, wallpaperImage);
}

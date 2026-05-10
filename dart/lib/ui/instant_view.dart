import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../bridge/engine_service.dart';

void openInstantView(BuildContext context, String accountId, String url, {String? siteName}) {
  Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      builder: (_) => InstantViewPage(accountId: accountId, url: url, siteName: siteName ?? ''),
    ),
  );
}

class InstantViewPage extends StatefulWidget {
  final String accountId;
  final String url;
  final String siteName;

  const InstantViewPage({
    super.key,
    required this.accountId,
    required this.url,
    this.siteName = '',
  });

  @override
  State<InstantViewPage> createState() => _InstantViewPageState();
}

class _InstantViewPageState extends State<InstantViewPage> {
  Map<String, dynamic>? _pageData;
  bool _loading = true;
  String? _error;
  double _zoomFactor = 1.0;

  final List<_IvHistoryEntry> _history = [];
  int _historyIndex = -1;

  @override
  void initState() {
    super.initState();
    _navigateTo(widget.url, push: false);
  }

  String get _currentUrl {
    if (_historyIndex >= 0 && _historyIndex < _history.length) {
      return _history[_historyIndex].url;
    }
    return widget.url;
  }

  bool get _canGoBack => _historyIndex > 0;
  bool get _canGoForward => _historyIndex < _history.length - 1;

  Future<void> _navigateTo(String url, {bool push = true}) async {
    setState(() { _loading = true; _error = null; });
    final engine = context.read<EngineService>();
    try {
      final data = await engine.getInstantViewPage(widget.accountId, url);
      if (!mounted) return;
      if (data == null) {
        _openExternal(url);
        if (push) return;
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _loading = false;
        _pageData = data;
        if (push) {
          if (_historyIndex < _history.length - 1) {
            _history.removeRange(_historyIndex + 1, _history.length);
          }
          _history.add(_IvHistoryEntry(url: url, data: data));
          _historyIndex = _history.length - 1;
        } else {
          _history.add(_IvHistoryEntry(url: url, data: data));
          _historyIndex = 0;
        }
      });
    } catch (e) {
      if (!mounted) return;
      _openExternal(url);
      if (!push) Navigator.of(context).pop();
    }
  }

  void _goBack() {
    if (!_canGoBack) return;
    setState(() {
      _historyIndex--;
      _pageData = _history[_historyIndex].data;
    });
  }

  void _goForward() {
    if (!_canGoForward) return;
    setState(() {
      _historyIndex++;
      _pageData = _history[_historyIndex].data;
    });
  }

  void _openExternal(String url) {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  void _zoomIn() => setState(() => _zoomFactor = (_zoomFactor + 0.1).clamp(0.5, 3.0));
  void _zoomOut() => setState(() => _zoomFactor = (_zoomFactor - 0.1).clamp(0.5, 3.0));
  void _zoomReset() => setState(() => _zoomFactor = 1.0);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212b) : Colors.white;
    final fgColor = isDark ? Colors.white : Colors.black87;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.equal, control: true): _zoomIn,
        const SingleActivator(LogicalKeyboardKey.minus, control: true): _zoomOut,
        const SingleActivator(LogicalKeyboardKey.digit0, control: true): _zoomReset,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: bgColor,
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: AppBar(
              backgroundColor: bgColor,
              foregroundColor: fgColor,
              elevation: 0,
              toolbarHeight: 48,
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: Text(
                widget.siteName.isNotEmpty ? widget.siteName : 'INSTANT VIEW',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: fgColor),
              ),
              actions: [
                if (_canGoBack)
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 20),
                    tooltip: 'Back',
                    onPressed: _goBack,
                  ),
                if (_canGoForward)
                  IconButton(
                    icon: const Icon(Icons.arrow_forward, size: 20),
                    tooltip: 'Forward',
                    onPressed: _goForward,
                  ),
                _buildZoomButton(fgColor),
                IconButton(
                  icon: const Icon(Icons.share, size: 20),
                  tooltip: 'Share',
                  onPressed: () => Share.share(_currentUrl),
                ),
                IconButton(
                  icon: const Icon(Icons.open_in_browser, size: 22),
                  tooltip: 'Open in browser',
                  onPressed: () => _openExternal(_currentUrl),
                ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(height: 1, color: isDark ? const Color(0xFF0e1621) : const Color(0xFFe0e0e0)),
              ),
            ),
          ),
          body: _loading
              ? Center(child: CircularProgressIndicator(color: isDark ? const Color(0xFF71baf7) : const Color(0xFF168acd)))
              : _error != null
                  ? _buildError(fgColor)
                  : _buildContent(isDark, fgColor),
        ),
      ),
    );
  }

  Widget _buildZoomButton(Color fgColor) {
    if (_zoomFactor == 1.0) {
      return IconButton(
        icon: const Icon(Icons.zoom_in, size: 20),
        tooltip: 'Zoom (Ctrl+/Ctrl-)',
        onPressed: _zoomIn,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 26, height: 26,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.remove, size: 16),
              onPressed: _zoomOut,
            ),
          ),
          GestureDetector(
            onTap: _zoomReset,
            child: Text('${(_zoomFactor * 100).round()}%', style: TextStyle(fontSize: 12, color: fgColor)),
          ),
          SizedBox(
            width: 26, height: 26,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.add, size: 16),
              onPressed: _zoomIn,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(Color fgColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: fgColor.withAlpha(100)),
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: fgColor.withAlpha(150), fontSize: 14), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => _openExternal(_currentUrl),
              child: const Text('Open in browser'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(bool isDark, Color fgColor) {
    final blocks = _pageData!['blocks'] as List<dynamic>? ?? [];
    final rtl = _pageData!['rtl'] == true;

    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(_zoomFactor)),
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          itemCount: blocks.length,
          itemBuilder: (context, i) {
            final block = blocks[i] as Map<String, dynamic>;
            return _IvBlock(
              block: block,
              isDark: isDark,
              accountId: widget.accountId,
              onNavigateIV: (url) => _navigateTo(url),
            );
          },
        ),
      ),
    );
  }
}

class _IvHistoryEntry {
  final String url;
  final Map<String, dynamic> data;
  const _IvHistoryEntry({required this.url, required this.data});
}

class _IvBlock extends StatelessWidget {
  final Map<String, dynamic> block;
  final bool isDark;
  final String accountId;
  final void Function(String url)? onNavigateIV;

  const _IvBlock({required this.block, required this.isDark, this.accountId = '', this.onNavigateIV});

  Color get _accentColor => isDark ? const Color(0xFF71baf7) : const Color(0xFF168acd);
  Color get _textColor => isDark ? const Color(0xFFe0e4e8) : const Color(0xFF222222);
  Color get _subtleColor => isDark ? const Color(0xFF8a9bab) : const Color(0xFF777777);

  @override
  Widget build(BuildContext context) {
    final type = block['type'] as String? ?? '';
    switch (type) {
      case 'title':
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _richText(context, block['text'], TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: _textColor, height: 1.3)),
        );
      case 'subtitle':
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _richText(context, block['text'], TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: _subtleColor, height: 1.3)),
        );
      case 'kicker':
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: _richText(context, block['text'], TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _accentColor, letterSpacing: 0.5)),
        );
      case 'author_date':
        return _buildAuthorDate(context);
      case 'header':
        return Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: _richText(context, block['text'], TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _textColor, height: 1.3)),
        );
      case 'subheader':
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6),
          child: _richText(context, block['text'], TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: _textColor, height: 1.3)),
        );
      case 'paragraph':
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _richText(context, block['text'], TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: _textColor, height: 1.6)),
        );
      case 'preformatted':
        return _buildPreformatted(context);
      case 'footer':
        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: _richText(context, block['text'], TextStyle(fontSize: 13, color: _subtleColor, height: 1.4)),
        );
      case 'divider':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(child: Container(width: 48, height: 2, color: _subtleColor.withAlpha(80))),
        );
      case 'anchor':
        return const SizedBox.shrink();
      case 'photo':
        return _buildPhoto(context);
      case 'cover':
        final coverBlock = block['cover'] as Map<String, dynamic>?;
        if (coverBlock == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _IvBlock(block: coverBlock, isDark: isDark, accountId: accountId, onNavigateIV: onNavigateIV),
        );
      case 'blockquote':
        return _buildBlockquote(context);
      case 'pullquote':
        return _buildPullquote(context);
      case 'list':
        return _buildList(context);
      case 'ordered_list':
        return _buildOrderedList(context);
      case 'details':
        return _buildDetails(context);
      case 'table':
        return _buildTable(context);
      case 'embed':
        return _buildEmbed(context);
      case 'embed_post':
        return _buildEmbedPost(context);
      case 'related':
        return _buildRelated(context);
      case 'video':
        return _buildVideo(context);
      case 'collage':
        return _buildCollage(context);
      case 'slideshow':
        return _buildSlideshow(context);
      case 'channel':
        return _buildChannel(context);
      case 'audio':
        return _buildAudio(context);
      case 'map':
        return _buildMap(context);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildAuthorDate(BuildContext context) {
    final dateTs = block['date'] as num?;
    String dateStr = '';
    if (dateTs != null && dateTs > 0) {
      final dt = DateTime.fromMillisecondsSinceEpoch(dateTs.toInt() * 1000);
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      dateStr = '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    }
    final authorWidget = _richText(context, block['author'], TextStyle(fontSize: 14, color: _subtleColor));
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Wrap(
        children: [
          if (authorWidget != null) authorWidget,
          if (authorWidget != null && dateStr.isNotEmpty) Text(' · ', style: TextStyle(fontSize: 14, color: _subtleColor)),
          if (dateStr.isNotEmpty) Text(dateStr, style: TextStyle(fontSize: 14, color: _subtleColor)),
        ],
      ),
    );
  }

  Widget _buildPreformatted(BuildContext context) {
    final bgColor = isDark ? const Color(0xFF1e2c3a) : const Color(0xFFf4f4f5);
    final lang = block['lang'] as String? ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (lang.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(lang, style: TextStyle(fontSize: 11, color: _subtleColor, fontWeight: FontWeight.w600)),
              ),
            _buildHighlightedCode(context, lang) ??
                _richText(
                  context,
                  block['text'],
                  TextStyle(fontSize: 14, fontFamily: 'monospace', color: _textColor, height: 1.5),
                ) ??
                const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }

  Widget? _buildHighlightedCode(BuildContext context, String lang) {
    if (lang.isEmpty) return null;
    final plainText = _extractPlainText(block['text']);
    if (plainText.isEmpty) return null;

    final keywords = _getKeywords(lang);
    if (keywords.isEmpty) return null;

    final spans = _highlightSyntax(plainText, keywords, lang);
    return SelectableText.rich(
      TextSpan(children: spans),
      style: TextStyle(fontSize: 14, fontFamily: 'monospace', color: _textColor, height: 1.5),
    );
  }

  Set<String> _getKeywords(String lang) {
    final l = lang.toLowerCase();
    if (l == 'javascript' || l == 'js' || l == 'typescript' || l == 'ts') {
      return {'const', 'let', 'var', 'function', 'return', 'if', 'else', 'for', 'while', 'class', 'new', 'this', 'import', 'export', 'from', 'async', 'await', 'try', 'catch', 'throw', 'switch', 'case', 'break', 'default', 'true', 'false', 'null', 'undefined', 'typeof', 'instanceof'};
    }
    if (l == 'python' || l == 'py') {
      return {'def', 'class', 'return', 'if', 'elif', 'else', 'for', 'while', 'import', 'from', 'as', 'try', 'except', 'finally', 'raise', 'with', 'yield', 'lambda', 'True', 'False', 'None', 'and', 'or', 'not', 'in', 'is', 'pass', 'break', 'continue', 'global', 'nonlocal', 'async', 'await'};
    }
    if (l == 'java' || l == 'kotlin' || l == 'kt') {
      return {'class', 'public', 'private', 'protected', 'static', 'final', 'void', 'int', 'boolean', 'String', 'return', 'if', 'else', 'for', 'while', 'new', 'this', 'super', 'import', 'package', 'try', 'catch', 'throw', 'throws', 'true', 'false', 'null', 'extends', 'implements', 'interface', 'abstract', 'switch', 'case', 'break', 'default', 'val', 'var', 'fun', 'when', 'object', 'companion', 'override', 'data'};
    }
    if (l == 'c' || l == 'cpp' || l == 'c++' || l == 'h' || l == 'hpp') {
      return {'int', 'char', 'float', 'double', 'void', 'bool', 'if', 'else', 'for', 'while', 'return', 'class', 'struct', 'enum', 'const', 'static', 'virtual', 'override', 'public', 'private', 'protected', 'namespace', 'using', 'include', 'define', 'typedef', 'template', 'typename', 'auto', 'true', 'false', 'nullptr', 'new', 'delete', 'this', 'switch', 'case', 'break', 'default', 'try', 'catch', 'throw'};
    }
    if (l == 'go' || l == 'golang') {
      return {'func', 'return', 'if', 'else', 'for', 'range', 'switch', 'case', 'default', 'break', 'continue', 'var', 'const', 'type', 'struct', 'interface', 'map', 'chan', 'go', 'defer', 'select', 'package', 'import', 'true', 'false', 'nil', 'make', 'new', 'append', 'len', 'cap', 'error'};
    }
    if (l == 'rust' || l == 'rs') {
      return {'fn', 'let', 'mut', 'const', 'if', 'else', 'for', 'while', 'loop', 'match', 'return', 'struct', 'enum', 'impl', 'trait', 'pub', 'use', 'mod', 'self', 'super', 'true', 'false', 'Some', 'None', 'Ok', 'Err', 'async', 'await', 'move', 'where', 'type', 'unsafe'};
    }
    if (l == 'dart') {
      return {'class', 'extends', 'implements', 'with', 'void', 'var', 'final', 'const', 'int', 'double', 'String', 'bool', 'if', 'else', 'for', 'while', 'return', 'new', 'this', 'super', 'import', 'export', 'true', 'false', 'null', 'async', 'await', 'try', 'catch', 'throw', 'switch', 'case', 'break', 'default', 'late', 'required', 'abstract', 'static', 'override', 'Future', 'Stream', 'dynamic'};
    }
    if (l == 'html' || l == 'xml') {
      return {'html', 'head', 'body', 'div', 'span', 'p', 'a', 'img', 'script', 'style', 'link', 'meta', 'title', 'class', 'id', 'href', 'src', 'type'};
    }
    if (l == 'css' || l == 'scss') {
      return {'color', 'background', 'margin', 'padding', 'border', 'display', 'flex', 'grid', 'width', 'height', 'font', 'text', 'position', 'top', 'left', 'right', 'bottom', 'overflow', 'z-index', 'opacity', 'transform', 'transition', 'animation'};
    }
    if (l == 'sql') {
      return {'SELECT', 'FROM', 'WHERE', 'INSERT', 'INTO', 'UPDATE', 'DELETE', 'CREATE', 'TABLE', 'ALTER', 'DROP', 'INDEX', 'JOIN', 'LEFT', 'RIGHT', 'INNER', 'OUTER', 'ON', 'AND', 'OR', 'NOT', 'NULL', 'IS', 'IN', 'AS', 'ORDER', 'BY', 'GROUP', 'HAVING', 'LIMIT', 'OFFSET', 'UNION', 'VALUES', 'SET', 'DISTINCT', 'COUNT', 'SUM', 'AVG', 'MAX', 'MIN', 'LIKE', 'BETWEEN', 'EXISTS', 'PRIMARY', 'KEY', 'FOREIGN', 'REFERENCES', 'CASCADE'};
    }
    if (l == 'shell' || l == 'bash' || l == 'sh' || l == 'zsh') {
      return {'if', 'then', 'else', 'elif', 'fi', 'for', 'while', 'do', 'done', 'case', 'esac', 'function', 'return', 'exit', 'echo', 'export', 'source', 'local', 'readonly', 'set', 'unset', 'shift', 'eval', 'exec', 'trap', 'cd', 'pwd', 'test', 'true', 'false'};
    }
    return {};
  }

  List<TextSpan> _highlightSyntax(String code, Set<String> keywords, String lang) {
    final spans = <TextSpan>[];
    final kwColor = isDark ? const Color(0xFFc678dd) : const Color(0xFF7B3A9E);
    final strColor = isDark ? const Color(0xFF98c379) : const Color(0xFF50A14F);
    final commentColor = isDark ? const Color(0xFF5c6370) : const Color(0xFFA0A1A7);
    final numColor = isDark ? const Color(0xFFd19a66) : const Color(0xFF986801);

    final pattern = RegExp(
      r'(//[^\n]*|/\*[\s\S]*?\*/|#[^\n]*)'
      r'''|("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\]|\\.)*`)'''
      r'|(\b\d+\.?\d*\b)'
      r'|(\b[a-zA-Z_]\w*\b)',
    );

    int lastEnd = 0;
    for (final match in pattern.allMatches(code)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: code.substring(lastEnd, match.start)));
      }
      final text = match.group(0)!;
      if (match.group(1) != null) {
        spans.add(TextSpan(text: text, style: TextStyle(color: commentColor, fontStyle: FontStyle.italic)));
      } else if (match.group(2) != null) {
        spans.add(TextSpan(text: text, style: TextStyle(color: strColor)));
      } else if (match.group(3) != null) {
        spans.add(TextSpan(text: text, style: TextStyle(color: numColor)));
      } else if (keywords.contains(text)) {
        spans.add(TextSpan(text: text, style: TextStyle(color: kwColor, fontWeight: FontWeight.w600)));
      } else {
        spans.add(TextSpan(text: text));
      }
      lastEnd = match.end;
    }
    if (lastEnd < code.length) {
      spans.add(TextSpan(text: code.substring(lastEnd)));
    }
    return spans;
  }

  Widget _buildPhoto(BuildContext context) {
    final thumbB64 = block['thumb'] as String?;
    final caption = block['caption'];
    final photoId = block['photo_id'] as num?;
    final extra = block['extra'] as String?;
    final photoW = block['w'] as num? ?? 0;
    final photoH = block['h'] as num? ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (photoId != null && extra != null && extra.isNotEmpty)
            _IvFullPhoto(
              accountId: accountId,
              photoId: photoId.toInt(),
              extra: extra,
              thumbB64: thumbB64,
              photoWidth: photoW.toInt(),
              photoHeight: photoH.toInt(),
            )
          else if (thumbB64 != null && thumbB64.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.memory(
                base64Decode(thumbB64),
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (_, __, ___) => const SizedBox(height: 100),
              ),
            ),
          if (caption != null) _buildCaption(context, caption),
        ],
      ),
    );
  }

  Widget _buildCaption(BuildContext context, dynamic caption) {
    if (caption is! Map<String, dynamic>) return const SizedBox.shrink();
    final textWidget = _richText(context, caption['text'], TextStyle(fontSize: 13, color: _subtleColor, height: 1.4));
    final creditWidget = _richText(context, caption['credit'], TextStyle(fontSize: 12, color: _subtleColor.withAlpha(180), height: 1.4));
    if (textWidget == null && creditWidget == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (textWidget != null) textWidget,
          if (creditWidget != null) creditWidget,
        ],
      ),
    );
  }

  Widget _buildBlockquote(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: _accentColor, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _richText(context, block['text'], TextStyle(fontSize: 16, fontStyle: FontStyle.italic, color: _textColor, height: 1.5)) ?? const SizedBox.shrink(),
            if (block['caption'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _richText(context, block['caption'], TextStyle(fontSize: 13, color: _subtleColor)) ?? const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPullquote(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      child: Column(
        children: [
          _richText(
            context,
            block['text'],
            TextStyle(fontSize: 20, fontStyle: FontStyle.italic, fontWeight: FontWeight.w500, color: _textColor, height: 1.4),
          ) ?? const SizedBox.shrink(),
          if (block['caption'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _richText(context, block['caption'], TextStyle(fontSize: 14, color: _subtleColor)) ?? const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final items = block['items'] as List<dynamic>? ?? [];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items.map((item) {
          final itemMap = item as Map<String, dynamic>;
          if (itemMap.containsKey('text')) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 8, right: 8),
                    child: Container(width: 5, height: 5, decoration: BoxDecoration(color: _subtleColor, shape: BoxShape.circle)),
                  ),
                  Expanded(child: _richText(context, itemMap['text'], TextStyle(fontSize: 16, color: _textColor, height: 1.6)) ?? const SizedBox.shrink()),
                ],
              ),
            );
          }
          final blocks = itemMap['blocks'] as List<dynamic>? ?? [];
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: 8),
                  child: Container(width: 5, height: 5, decoration: BoxDecoration(color: _subtleColor, shape: BoxShape.circle)),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: blocks.map((b) => _IvBlock(block: b as Map<String, dynamic>, isDark: isDark, accountId: accountId, onNavigateIV: onNavigateIV)).toList(),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildOrderedList(BuildContext context) {
    final items = block['items'] as List<dynamic>? ?? [];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items.asMap().entries.map((entry) {
          final itemMap = entry.value as Map<String, dynamic>;
          final num = itemMap['num'] as String? ?? '${entry.key + 1}.';
          if (itemMap.containsKey('text')) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 28, child: Text('$num.', style: TextStyle(fontSize: 16, color: _subtleColor, height: 1.6))),
                  Expanded(child: _richText(context, itemMap['text'], TextStyle(fontSize: 16, color: _textColor, height: 1.6)) ?? const SizedBox.shrink()),
                ],
              ),
            );
          }
          final blocks = itemMap['blocks'] as List<dynamic>? ?? [];
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 28, child: Text('$num.', style: TextStyle(fontSize: 16, color: _subtleColor, height: 1.6))),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: blocks.map((b) => _IvBlock(block: b as Map<String, dynamic>, isDark: isDark, accountId: accountId, onNavigateIV: onNavigateIV)).toList(),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDetails(BuildContext context) {
    final blocks = block['blocks'] as List<dynamic>? ?? [];
    final open = block['open'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _IvDetails(
        title: _richText(context, block['title'], TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _textColor)),
        blocks: blocks,
        isDark: isDark,
        initiallyOpen: open,
        accountId: accountId,
        onNavigateIV: onNavigateIV,
      ),
    );
  }

  Widget _buildTable(BuildContext context) {
    final rows = block['rows'] as List<dynamic>? ?? [];
    final bordered = block['bordered'] == true;
    final borderColor = isDark ? const Color(0xFF2a3a4a) : const Color(0xFFe0e0e0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Table(
        border: bordered ? TableBorder.all(color: borderColor, width: 1) : null,
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        children: rows.map((row) {
          final cells = row as List<dynamic>? ?? [];
          return TableRow(
            children: cells.map((cell) {
              final cellMap = cell as Map<String, dynamic>;
              final isHeader = cellMap['header'] == true;
              return Padding(
                padding: const EdgeInsets.all(8),
                child: _richText(
                  context,
                  cellMap['text'],
                  TextStyle(
                    fontSize: 14,
                    fontWeight: isHeader ? FontWeight.w600 : FontWeight.w400,
                    color: _textColor,
                    height: 1.4,
                  ),
                ) ?? const SizedBox.shrink(),
              );
            }).toList(),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmbed(BuildContext context) {
    final embedUrl = block['url'] as String?;
    final embedHtml = block['html'] as String?;
    final w = (block['w'] as num?)?.toDouble() ?? 0;
    final h = (block['h'] as num?)?.toDouble() ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1e2c3a) : const Color(0xFFf4f4f5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (embedHtml != null && embedHtml.isNotEmpty) ...[
              Container(
                width: double.infinity,
                constraints: BoxConstraints(maxHeight: h > 0 ? h : 300),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0e1621) : Colors.white,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _stripHtml(embedHtml),
                    style: TextStyle(fontSize: 13, color: _textColor, height: 1.4),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (embedUrl != null && embedUrl.isNotEmpty)
              GestureDetector(
                onTap: () => launchUrl(Uri.parse(embedUrl), mode: LaunchMode.externalApplication),
                child: Row(
                  children: [
                    Icon(Icons.open_in_new, size: 14, color: _accentColor),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(embedUrl, style: TextStyle(fontSize: 13, color: _accentColor, decoration: TextDecoration.underline), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            if (block['caption'] != null) _buildCaption(context, block['caption']),
          ],
        ),
      ),
    );
  }

  String _stripHtml(String html) {
    return html.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&#39;', "'").trim();
  }

  Widget _buildEmbedPost(BuildContext context) {
    final author = block['author'] as String? ?? '';
    final blocks = block['blocks'] as List<dynamic>? ?? [];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: _accentColor.withAlpha(100), width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (author.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(author, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _accentColor)),
              ),
            ...blocks.map((b) => _IvBlock(block: b as Map<String, dynamic>, isDark: isDark, accountId: accountId, onNavigateIV: onNavigateIV)),
            if (block['caption'] != null) _buildCaption(context, block['caption']),
          ],
        ),
      ),
    );
  }

  Widget _buildRelated(BuildContext context) {
    final articles = block['articles'] as List<dynamic>? ?? [];
    if (articles.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _richText(context, block['title'], TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _textColor)) ??
              Text('Related', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _textColor)),
          const SizedBox(height: 8),
          ...articles.map((a) {
            final am = a as Map<String, dynamic>;
            final title = am['title'] as String? ?? am['url'] as String? ?? '';
            final desc = am['desc'] as String? ?? '';
            final articleUrl = am['url'] as String? ?? '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () {
                  if (articleUrl.isNotEmpty) {
                    if (onNavigateIV != null) {
                      onNavigateIV!(articleUrl);
                    } else {
                      launchUrl(Uri.parse(articleUrl), mode: LaunchMode.externalApplication);
                    }
                  }
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: _accentColor), maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (desc.isNotEmpty) Text(desc, style: TextStyle(fontSize: 13, color: _subtleColor), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildVideo(BuildContext context) {
    final caption = block['caption'];
    final autoplay = block['autoplay'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            height: 200,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0e1621) : const Color(0xFFe8e8e8),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_circle_outline, size: 48, color: _accentColor),
                  const SizedBox(height: 8),
                  Text(autoplay ? 'Video (autoplay)' : 'Video', style: TextStyle(fontSize: 13, color: _subtleColor)),
                ],
              ),
            ),
          ),
          if (caption != null) _buildCaption(context, caption),
        ],
      ),
    );
  }

  Widget _buildCollage(BuildContext context) {
    final items = block['items'] as List<dynamic>? ?? [];
    final caption = block['caption'];
    if (items.isEmpty) return const SizedBox.shrink();

    final crossCount = items.length <= 2 ? items.length : (items.length <= 4 ? 2 : 3);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GridView.count(
            crossAxisCount: crossCount,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
            children: items.map((item) {
              return _IvBlock(block: item as Map<String, dynamic>, isDark: isDark, accountId: accountId, onNavigateIV: onNavigateIV);
            }).toList(),
          ),
          if (caption != null) _buildCaption(context, caption),
        ],
      ),
    );
  }

  Widget _buildSlideshow(BuildContext context) {
    final items = block['items'] as List<dynamic>? ?? [];
    final caption = block['caption'];
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 300,
            child: PageView.builder(
              itemCount: items.length,
              itemBuilder: (ctx, i) {
                return _IvBlock(block: items[i] as Map<String, dynamic>, isDark: isDark, accountId: accountId, onNavigateIV: onNavigateIV);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Center(child: Text('${items.length} items', style: TextStyle(fontSize: 12, color: _subtleColor))),
          ),
          if (caption != null) _buildCaption(context, caption),
        ],
      ),
    );
  }

  Widget _buildChannel(BuildContext context) {
    final title = block['title'] as String? ?? 'Channel';
    final username = block['username'] as String?;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1e2c3a) : const Color(0xFFf4f4f5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: _accentColor.withAlpha(40),
              child: Icon(Icons.campaign, color: _accentColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _textColor)),
                  if (username != null) Text('@$username', style: TextStyle(fontSize: 13, color: _subtleColor)),
                ],
              ),
            ),
            TextButton(
              onPressed: () {
                if (username != null) {
                  launchUrl(Uri.parse('https://t.me/$username'), mode: LaunchMode.externalApplication);
                }
              },
              child: Text('Join', style: TextStyle(color: _accentColor, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudio(BuildContext context) {
    final caption = block['caption'];
    final audioTitle = block['title'] as String?;
    final performer = block['performer'] as String?;
    final duration = block['duration'] as num?;

    String durationStr = '';
    if (duration != null && duration > 0) {
      final mins = duration.toInt() ~/ 60;
      final secs = duration.toInt() % 60;
      durationStr = '$mins:${secs.toString().padLeft(2, '0')}';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1e2c3a) : const Color(0xFFf4f4f5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _accentColor),
                  child: const Icon(Icons.play_arrow, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(audioTitle ?? performer ?? 'Audio', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _textColor), maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (performer != null && audioTitle != null)
                        Text(performer, style: TextStyle(fontSize: 12, color: _subtleColor), maxLines: 1),
                      if (durationStr.isNotEmpty) Text(durationStr, style: TextStyle(fontSize: 12, color: _subtleColor)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (caption != null) _buildCaption(context, caption),
        ],
      ),
    );
  }

  Widget _buildMap(BuildContext context) {
    final lat = block['lat'] as num?;
    final lng = block['lng'] as num?;
    final caption = block['caption'];

    if (lat == null || lng == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=15/$lat/$lng'), mode: LaunchMode.externalApplication),
            child: Container(
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1e2c3a) : const Color(0xFFe8eaed),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.place, size: 40, color: _accentColor),
                    const SizedBox(height: 6),
                    Text('${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}', style: TextStyle(fontSize: 13, color: _subtleColor)),
                    const SizedBox(height: 4),
                    Text('Open in maps', style: TextStyle(fontSize: 12, color: _accentColor, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ),
          if (caption != null) _buildCaption(context, caption),
        ],
      ),
    );
  }

  String _extractPlainText(dynamic rtData) {
    if (rtData == null) return '';
    if (rtData is! Map<String, dynamic>) return '';
    final t = rtData['t'] as String? ?? '';
    if (t == 'plain') return rtData['v'] as String? ?? '';
    if (t == 'concat') {
      final parts = rtData['parts'] as List<dynamic>? ?? [];
      return parts.map(_extractPlainText).join();
    }
    return _extractPlainText(rtData['c']);
  }

  Widget? _richText(BuildContext context, dynamic rtData, TextStyle baseStyle) {
    if (rtData == null) return null;
    final span = _richTextToSpan(context, rtData, baseStyle);
    if (span == null) return null;
    return SelectableText.rich(TextSpan(children: [span]), style: baseStyle);
  }

  InlineSpan? _richTextToSpan(BuildContext context, dynamic rtData, TextStyle baseStyle) {
    if (rtData == null) return null;
    if (rtData is! Map<String, dynamic>) return null;
    final t = rtData['t'] as String? ?? '';
    switch (t) {
      case 'plain':
        final text = rtData['v'] as String? ?? '';
        if (text.isEmpty) return null;
        return TextSpan(text: text);
      case 'bold':
        final child = _richTextToSpan(context, rtData['c'], baseStyle.copyWith(fontWeight: FontWeight.w700));
        if (child == null) return null;
        return TextSpan(style: const TextStyle(fontWeight: FontWeight.w700), children: [child]);
      case 'italic':
        final child = _richTextToSpan(context, rtData['c'], baseStyle.copyWith(fontStyle: FontStyle.italic));
        if (child == null) return null;
        return TextSpan(style: const TextStyle(fontStyle: FontStyle.italic), children: [child]);
      case 'underline':
        final child = _richTextToSpan(context, rtData['c'], baseStyle.copyWith(decoration: TextDecoration.underline));
        if (child == null) return null;
        return TextSpan(style: const TextStyle(decoration: TextDecoration.underline), children: [child]);
      case 'strike':
        final child = _richTextToSpan(context, rtData['c'], baseStyle.copyWith(decoration: TextDecoration.lineThrough));
        if (child == null) return null;
        return TextSpan(style: const TextStyle(decoration: TextDecoration.lineThrough), children: [child]);
      case 'fixed':
        final child = _richTextToSpan(context, rtData['c'], baseStyle.copyWith(fontFamily: 'monospace'));
        if (child == null) return null;
        return TextSpan(style: TextStyle(fontFamily: 'monospace', fontSize: baseStyle.fontSize != null ? baseStyle.fontSize! - 1 : 14, backgroundColor: isDark ? const Color(0xFF1e2c3a) : const Color(0xFFf0f0f0)), children: [child]);
      case 'url':
        final href = rtData['href'] as String? ?? '';
        final child = _richTextToSpan(context, rtData['c'], baseStyle.copyWith(color: _accentColor));
        if (child == null) return null;
        return TextSpan(
          style: TextStyle(color: _accentColor, decoration: TextDecoration.underline, decorationColor: _accentColor.withAlpha(100)),
          recognizer: TapGestureRecognizer()..onTap = () {
            if (href.isNotEmpty) {
              if (onNavigateIV != null && _looksLikeIvUrl(href)) {
                onNavigateIV!(href);
              } else {
                launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
              }
            }
          },
          children: [child],
        );
      case 'email':
        final addr = rtData['addr'] as String? ?? '';
        final child = _richTextToSpan(context, rtData['c'], baseStyle.copyWith(color: _accentColor));
        if (child == null) return null;
        return TextSpan(
          style: TextStyle(color: _accentColor),
          recognizer: TapGestureRecognizer()..onTap = () {
            if (addr.isNotEmpty) {
              launchUrl(Uri.parse('mailto:$addr'));
            }
          },
          children: [child],
        );
      case 'concat':
        final parts = rtData['parts'] as List<dynamic>? ?? [];
        final spans = <InlineSpan>[];
        for (final p in parts) {
          final s = _richTextToSpan(context, p, baseStyle);
          if (s != null) spans.add(s);
        }
        if (spans.isEmpty) return null;
        return TextSpan(children: spans);
      case 'sub':
        final child = _richTextToSpan(context, rtData['c'], baseStyle);
        if (child == null) return null;
        return TextSpan(style: TextStyle(fontSize: (baseStyle.fontSize ?? 16) * 0.75, fontFeatures: const [FontFeature.subscripts()]), children: [child]);
      case 'sup':
        final child = _richTextToSpan(context, rtData['c'], baseStyle);
        if (child == null) return null;
        return TextSpan(style: TextStyle(fontSize: (baseStyle.fontSize ?? 16) * 0.75, fontFeatures: const [FontFeature.superscripts()]), children: [child]);
      case 'marked':
        final child = _richTextToSpan(context, rtData['c'], baseStyle);
        if (child == null) return null;
        return TextSpan(style: TextStyle(backgroundColor: isDark ? const Color(0xFF3a4a2a) : const Color(0xFFfff9c4)), children: [child]);
      case 'phone':
        final phone = rtData['phone'] as String? ?? '';
        final child = _richTextToSpan(context, rtData['c'], baseStyle.copyWith(color: _accentColor));
        if (child == null) return null;
        return TextSpan(
          style: TextStyle(color: _accentColor),
          recognizer: TapGestureRecognizer()..onTap = () {
            if (phone.isNotEmpty) {
              launchUrl(Uri.parse('tel:$phone'));
            }
          },
          children: [child],
        );
      case 'anchor':
        return _richTextToSpan(context, rtData['c'], baseStyle);
      case 'image':
        return null;
      default:
        return null;
    }
  }

  bool _looksLikeIvUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      return host == 'telegra.ph' || host == 'graph.org' || host.endsWith('.telegra.ph') || host.endsWith('.graph.org');
    } catch (_) {
      return false;
    }
  }
}

class _IvFullPhoto extends StatefulWidget {
  final String accountId;
  final int photoId;
  final String extra;
  final String? thumbB64;
  final int photoWidth;
  final int photoHeight;

  const _IvFullPhoto({
    required this.accountId,
    required this.photoId,
    required this.extra,
    this.thumbB64,
    this.photoWidth = 0,
    this.photoHeight = 0,
  });

  @override
  State<_IvFullPhoto> createState() => _IvFullPhotoState();
}

class _IvFullPhotoState extends State<_IvFullPhoto> {
  String? _localPath;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _downloadPhoto();
  }

  Future<void> _downloadPhoto() async {
    final engine = context.read<EngineService>();
    final path = await engine.downloadIVPhoto(widget.accountId, widget.photoId, widget.extra);
    if (!mounted) return;
    setState(() {
      _localPath = path;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final aspectRatio = widget.photoWidth > 0 && widget.photoHeight > 0
        ? widget.photoWidth / widget.photoHeight
        : 16.0 / 9.0;

    if (_localPath != null) {
      final file = File(_localPath!);
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.file(
            file,
            fit: BoxFit.cover,
            width: double.infinity,
            errorBuilder: (_, __, ___) => _buildThumb(aspectRatio),
          ),
        );
      }
    }

    if (_loading) {
      return Stack(
        children: [
          _buildThumb(aspectRatio),
          Positioned.fill(
            child: Center(
              child: SizedBox(
                width: 24, height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white.withAlpha(180)),
              ),
            ),
          ),
        ],
      );
    }

    return _buildThumb(aspectRatio);
  }

  Widget _buildThumb(double aspectRatio) {
    if (widget.thumbB64 != null && widget.thumbB64!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.memory(
          base64Decode(widget.thumbB64!),
          fit: BoxFit.cover,
          width: double.infinity,
          errorBuilder: (_, __, ___) => AspectRatio(
            aspectRatio: aspectRatio,
            child: Container(color: Colors.grey.withAlpha(50)),
          ),
        ),
      );
    }
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey.withAlpha(50),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

class _IvDetails extends StatefulWidget {
  final Widget? title;
  final List<dynamic> blocks;
  final bool isDark;
  final bool initiallyOpen;
  final String accountId;
  final void Function(String url)? onNavigateIV;

  const _IvDetails({required this.title, required this.blocks, required this.isDark, required this.initiallyOpen, this.accountId = '', this.onNavigateIV});

  @override
  State<_IvDetails> createState() => _IvDetailsState();
}

class _IvDetailsState extends State<_IvDetails> {
  late bool _open;

  @override
  void initState() {
    super.initState();
    _open = widget.initiallyOpen;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _open = !_open),
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              Icon(_open ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right, size: 20, color: widget.isDark ? Colors.white70 : Colors.black54),
              const SizedBox(width: 4),
              Expanded(child: widget.title ?? const SizedBox.shrink()),
            ],
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(left: 24, top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widget.blocks.map((b) => _IvBlock(block: b as Map<String, dynamic>, isDark: widget.isDark, accountId: widget.accountId, onNavigateIV: widget.onNavigateIV)).toList(),
            ),
          ),
      ],
    );
  }
}

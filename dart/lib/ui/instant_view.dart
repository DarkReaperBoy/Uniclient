import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../bridge/engine_service.dart';
import '../state/app_state.dart';

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
  late double _zoomFactor;
  int _zoomLevel = 100;
  final ScrollController _scrollController = ScrollController();
  bool _showScrollToTop = false;

  final List<_IvHistoryEntry> _history = [];
  int _historyIndex = -1;

  @override
  void initState() {
    super.initState();
    final storedZoom = context.read<AppState>().ivZoom;
    _zoomLevel = (storedZoom * 100).round().clamp(100, 300);
    _zoomFactor = _zoomLevel / 100.0;
    _scrollController.addListener(_onScroll);
    _navigateTo(widget.url, push: false);
  }

  void _onScroll() {
    final show = _scrollController.offset > 300;
    if (show != _showScrollToTop) {
      setState(() => _showScrollToTop = show);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
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
      final fragment = Uri.tryParse(url)?.fragment;
      if (fragment != null && fragment.isNotEmpty) {
        _scrollToAnchor(fragment);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
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

  void _scrollToAnchor(String name) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final targetKey = ValueKey('anchor_$name');
      bool found = false;
      void visit(Element element) {
        if (found) return;
        if (element.widget.key == targetKey) {
          Scrollable.ensureVisible(element, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
          found = true;
          return;
        }
        element.visitChildren(visit);
      }
      context.visitChildElements(visit);
    });
  }

  int _getZoomStep() {
    if (HardwareKeyboard.instance.isAltPressed) return 1;
    if (HardwareKeyboard.instance.isControlPressed) return 5;
    return 10;
  }

  void _zoomIn() => _setZoomLevel((_zoomLevel + _getZoomStep()).clamp(100, 300));
  void _zoomOut() => _setZoomLevel((_zoomLevel - _getZoomStep()).clamp(100, 300));
  void _zoomReset() => _setZoomLevel(100);

  void _setZoomLevel(int level) {
    setState(() {
      _zoomLevel = level;
      _zoomFactor = level / 100.0;
    });
    context.read<AppState>().setIvZoom(_zoomFactor);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212b) : Colors.white;
    final fgColor = isDark ? Colors.white : Colors.black87;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.equal, control: true): _zoomIn,
        const SingleActivator(LogicalKeyboardKey.equal, control: true, alt: true): _zoomIn,
        const SingleActivator(LogicalKeyboardKey.minus, control: true): _zoomOut,
        const SingleActivator(LogicalKeyboardKey.minus, control: true, alt: true): _zoomOut,
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
          floatingActionButton: _showScrollToTop && !_loading
              ? FloatingActionButton.small(
                  backgroundColor: isDark ? const Color(0xFF2b3a4a) : const Color(0xFFf0f0f0),
                  onPressed: () => _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut),
                  child: Icon(Icons.keyboard_arrow_up, color: fgColor),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildZoomButton(Color fgColor) {
    if (_zoomLevel == 100) {
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
            child: Text('$_zoomLevel%', style: TextStyle(fontSize: 12, color: fgColor)),
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
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              sliver: SliverList.builder(
                itemCount: blocks.length,
                itemBuilder: (context, index) {
                  final block = blocks[index] as Map<String, dynamic>;
                  return _IvBlock(
                    block: block,
                    isDark: isDark,
                    accountId: widget.accountId,
                    onNavigateIV: (url) => _navigateTo(url),
                  );
                },
              ),
            ),
          ],
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

class _IvBlock extends StatefulWidget {
  final Map<String, dynamic> block;
  final bool isDark;
  final String accountId;
  final void Function(String url)? onNavigateIV;

  const _IvBlock({required this.block, required this.isDark, this.accountId = '', this.onNavigateIV});

  @override
  State<_IvBlock> createState() => _IvBlockState();
}

class _IvBlockState extends State<_IvBlock> {
  final _recognizers = <TapGestureRecognizer>[];
  String? _cachedCodeKey;
  Widget? _cachedCodeWidget;

  Map<String, dynamic> get block => widget.block;
  bool get isDark => widget.isDark;
  String get accountId => widget.accountId;
  void Function(String url)? get onNavigateIV => widget.onNavigateIV;

  Color get _accentColor => isDark ? const Color(0xFF71baf7) : const Color(0xFF168acd);
  Color get _textColor => isDark ? const Color(0xFFe0e4e8) : const Color(0xFF222222);
  Color get _subtleColor => isDark ? const Color(0xFF8a9bab) : const Color(0xFF777777);

  TapGestureRecognizer _makeTapRecognizer(VoidCallback onTap) {
    final r = TapGestureRecognizer()..onTap = onTap;
    _recognizers.add(r);
    return r;
  }

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
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
          child: _richText(context, block['text'], TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _subtleColor, height: 1.3)),
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
        final anchorName = block['name'] as String? ?? '';
        if (anchorName.isEmpty) return const SizedBox.shrink();
        return SizedBox.shrink(key: ValueKey('anchor_$anchorName'));
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

    final cacheKey = '$lang\n$plainText';
    if (_cachedCodeKey == cacheKey && _cachedCodeWidget != null) {
      return _cachedCodeWidget;
    }

    final keywords = _getKeywords(lang);
    if (keywords.isEmpty) return null;

    final spans = _highlightSyntax(plainText, keywords, lang);
    _cachedCodeKey = cacheKey;
    _cachedCodeWidget = SelectableText.rich(
      TextSpan(children: spans),
      style: TextStyle(fontSize: 14, fontFamily: 'monospace', color: _textColor, height: 1.5),
    );
    return _cachedCodeWidget;
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
    final photoUrl = block['url'] as String?;

    Widget imageWidget;
    if (photoId != null && extra != null && extra.isNotEmpty) {
      imageWidget = _IvFullPhoto(
        accountId: accountId,
        photoId: photoId.toInt(),
        extra: extra,
        thumbB64: thumbB64,
        photoWidth: photoW.toInt(),
        photoHeight: photoH.toInt(),
        onTap: () => _openPhotoViewer(context, accountId, photoId.toInt(), extra, thumbB64),
      );
    } else if (thumbB64 != null && thumbB64.isNotEmpty) {
      imageWidget = GestureDetector(
        onTap: () => _openPhotoViewer(context, accountId, null, null, thumbB64),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.memory(
            base64Decode(thumbB64),
            fit: BoxFit.cover,
            width: double.infinity,
            errorBuilder: (_, __, ___) => const SizedBox(height: 100),
          ),
        ),
      );
    } else {
      imageWidget = const SizedBox.shrink();
    }

    if (photoUrl != null && photoUrl.isNotEmpty && onNavigateIV != null && _looksLikeIvUrl(photoUrl)) {
      imageWidget = GestureDetector(
        onTap: () => onNavigateIV!(photoUrl),
        child: imageWidget,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          imageWidget,
          if (caption != null) _buildCaption(context, caption),
        ],
      ),
    );
  }

  static void _openPhotoViewer(BuildContext context, String accountId, int? photoId, String? extra, String? thumbB64) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => _IvPhotoViewer(
        accountId: accountId,
        photoId: photoId,
        extra: extra,
        thumbB64: thumbB64,
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
          final rawNum = itemMap['num'] as String? ?? '';
          final cleanNum = rawNum.endsWith('.') ? rawNum.substring(0, rawNum.length - 1) : rawNum;
          final numLabel = cleanNum.isNotEmpty ? '$cleanNum.' : '${entry.key + 1}.';
          if (itemMap.containsKey('text')) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 28, child: Text(numLabel, style: TextStyle(fontSize: 16, color: _subtleColor, height: 1.6))),
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
                SizedBox(width: 28, child: Text(numLabel, style: TextStyle(fontSize: 16, color: _subtleColor, height: 1.6))),
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
    final striped = block['striped'] == true;
    final borderColor = isDark ? const Color(0xFF2a3a4a) : const Color(0xFFe0e0e0);
    final stripeColor = isDark ? const Color(0xFF1a2634) : const Color(0xFFF7F7F8);

    int maxCols = 0;
    for (final row in rows) {
      final cells = row as List<dynamic>? ?? [];
      int cols = 0;
      for (final cell in cells) {
        final cm = cell as Map<String, dynamic>;
        cols += (cm['colspan'] as num?)?.toInt() ?? 1;
      }
      if (cols > maxCols) maxCols = cols;
    }
    if (maxCols == 0) maxCols = 1;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Table(
        border: bordered ? TableBorder.all(color: borderColor, width: 1) : null,
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        columnWidths: {for (int i = 0; i < maxCols; i++) i: const FlexColumnWidth()},
        children: rows.asMap().entries.map((rowEntry) {
          final rowIndex = rowEntry.key;
          final cells = rowEntry.value as List<dynamic>? ?? [];
          final isStriped = striped && rowIndex.isOdd;

          final rowCells = <Widget>[];
          for (final cell in cells) {
            final cellMap = cell as Map<String, dynamic>;
            final isHeader = cellMap['header'] == true;
            final colSpan = (cellMap['colspan'] as num?)?.toInt() ?? 1;
            Alignment cellAlignment = Alignment.topLeft;
            if (cellMap['align_center'] == true) {
              cellAlignment = cellMap['valign_middle'] == true ? Alignment.center
                  : cellMap['valign_bottom'] == true ? Alignment.bottomCenter
                  : Alignment.topCenter;
            } else if (cellMap['align_right'] == true) {
              cellAlignment = cellMap['valign_middle'] == true ? Alignment.centerRight
                  : cellMap['valign_bottom'] == true ? Alignment.bottomRight
                  : Alignment.topRight;
            } else {
              cellAlignment = cellMap['valign_middle'] == true ? Alignment.centerLeft
                  : cellMap['valign_bottom'] == true ? Alignment.bottomLeft
                  : Alignment.topLeft;
            }
            final cellWidget = Container(
              color: isStriped ? stripeColor : null,
              padding: const EdgeInsets.all(8),
              alignment: cellAlignment,
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
            if (colSpan > 1) {
              rowCells.add(TableCell(
                child: cellWidget,
              ));
              for (int s = 1; s < colSpan && rowCells.length < maxCols; s++) {
                rowCells.add(const TableCell(child: SizedBox.shrink()));
              }
            } else {
              rowCells.add(cellWidget);
            }
          }
          while (rowCells.length < maxCols) {
            rowCells.add(const TableCell(child: SizedBox.shrink()));
          }

          return TableRow(
            decoration: isStriped ? BoxDecoration(color: stripeColor) : null,
            children: rowCells,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmbed(BuildContext context) {
    final caption = block['caption'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IvEmbedBlock(
            block: block,
            isDark: isDark,
            accountId: accountId,
          ),
          if (caption != null) ...[
            const SizedBox(height: 8),
            _buildCaption(context, caption),
          ],
        ],
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
    final videoId = block['video_id'] as num?;
    final extra = block['extra'] as String?;
    final mime = block['mime'] as String? ?? 'video/mp4';
    final thumbB64 = block['thumb'] as String?;
    final videoW = (block['w'] as num?)?.toDouble() ?? 0;
    final videoH = (block['h'] as num?)?.toDouble() ?? 0;
    final duration = block['duration'] as num?;

    String durationStr = '';
    if (duration != null && duration > 0) {
      final mins = duration.toInt() ~/ 60;
      final secs = duration.toInt() % 60;
      durationStr = '$mins:${secs.toString().padLeft(2, '0')}';
    }

    final aspectRatio = videoW > 0 && videoH > 0 ? videoW / videoH : 16.0 / 9.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IvVideoBlock(
            accountId: accountId,
            videoId: videoId?.toInt() ?? 0,
            extra: extra ?? '',
            mime: mime,
            thumbB64: thumbB64,
            aspectRatio: aspectRatio,
            durationStr: durationStr,
            isDark: isDark,
            accentColor: _accentColor,
            subtleColor: _subtleColor,
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (ctx, constraints) {
              final totalWidth = constraints.maxWidth;
              return _buildCollageLayout(items, totalWidth);
            },
          ),
          if (caption != null) _buildCaption(context, caption),
        ],
      ),
    );
  }

  Widget _buildCollageLayout(List<dynamic> items, double totalWidth) {
    final count = items.length;
    const gap = 2.0;
    final maxH = totalWidth.toDouble();
    final minW = totalWidth * 0.1;

    Widget buildItem(dynamic item) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: _IvBlock(block: item as Map<String, dynamic>, isDark: isDark, accountId: accountId, onNavigateIV: onNavigateIV),
      );
    }

    List<double> ratios = items.map((item) {
      final m = item as Map<String, dynamic>;
      final w = (m['w'] as num?)?.toDouble() ?? 100;
      final h = (m['h'] as num?)?.toDouble() ?? 100;
      return w / h;
    }).toList();

    String proportions = ratios.map((r) => r > 1.2 ? 'w' : r < 0.8 ? 'n' : 'q').join();
    double avgRatio = ratios.fold(0.0, (a, b) => a + b) / count;

    int _round(double v) => v.round();

    if (count == 1) {
      final h = _round(totalWidth / ratios[0]).toDouble().clamp(50.0, maxH);
      return SizedBox(height: h, child: buildItem(items[0]));
    }

    if (count == 2) {
      if (proportions == 'ww' && avgRatio > 1.4 && (ratios[1] - ratios[0]).abs() < 0.2) {
        final h = _round((totalWidth / ratios[0]).clamp(50, (maxH - gap) / 2)).toDouble();
        return Column(children: [
          SizedBox(height: h, child: buildItem(items[0])),
          const SizedBox(height: gap),
          SizedBox(height: h, child: buildItem(items[1])),
        ]);
      } else if (proportions == 'ww' || proportions == 'qq') {
        final w = (totalWidth - gap) / 2;
        final h = _round((w / ratios[0]).clamp(50, maxH).toDouble().clamp(50, (w / ratios[1]).clamp(50, maxH))).toDouble();
        return SizedBox(
          height: h,
          child: Row(children: [
            SizedBox(width: w, child: buildItem(items[0])),
            const SizedBox(width: gap),
            SizedBox(width: w, child: buildItem(items[1])),
          ]),
        );
      } else {
        final secondW = ((0.4 * (totalWidth - gap)).clamp(
            minW,
            ((totalWidth - gap) / ratios[0] / (1 / ratios[0] + 1 / ratios[1])).clamp(minW, totalWidth - gap - minW),
        )).clamp(minW, totalWidth - gap - minW);
        final firstW = totalWidth - secondW - gap;
        final h = _round((firstW / ratios[0]).clamp(50, maxH).toDouble().clamp(50, (secondW / ratios[1]).clamp(50, maxH))).toDouble();
        return SizedBox(
          height: h,
          child: Row(children: [
            SizedBox(width: firstW, child: buildItem(items[0])),
            const SizedBox(width: gap),
            SizedBox(width: secondW, child: buildItem(items[1])),
          ]),
        );
      }
    }

    if (count == 3) {
      if (proportions[0] == 'n') {
        final firstH = maxH;
        final thirdH = _round(((maxH - gap) / 2).clamp(50, (ratios[1] * (totalWidth - gap) / (ratios[2] + ratios[1])).clamp(50, (maxH - gap) / 2))).toDouble();
        final secondH = firstH - thirdH - gap;
        final rightW = _round((((totalWidth - gap) / 2).clamp(minW, (thirdH * ratios[2]).clamp(minW, (secondH * ratios[1]).clamp(minW, (totalWidth - gap) / 2)))).clamp(minW, totalWidth - gap - minW)).toDouble();
        final leftW = (totalWidth - gap - rightW).clamp(minW, _round(firstH * ratios[0]).toDouble());
        return SizedBox(
          height: firstH,
          child: Row(children: [
            SizedBox(width: leftW, child: buildItem(items[0])),
            const SizedBox(width: gap),
            SizedBox(
              width: rightW,
              child: Column(children: [
                SizedBox(height: secondH, child: buildItem(items[1])),
                const SizedBox(height: gap),
                SizedBox(height: thirdH, child: buildItem(items[2])),
              ]),
            ),
          ]),
        );
      } else {
        final firstH = _round((totalWidth / ratios[0]).clamp(50, (maxH - gap) * 0.66)).toDouble();
        final secondW = (totalWidth - gap) / 2;
        final secondH = _round((secondW / ratios[1]).clamp(50, (secondW / ratios[2]).clamp(50, maxH - firstH - gap))).toDouble().clamp(50.0, maxH - firstH - gap);
        final thirdW = totalWidth - secondW - gap;
        return Column(children: [
          SizedBox(height: firstH, child: buildItem(items[0])),
          const SizedBox(height: gap),
          SizedBox(
            height: secondH,
            child: Row(children: [
              SizedBox(width: secondW, child: buildItem(items[1])),
              const SizedBox(width: gap),
              SizedBox(width: thirdW, child: buildItem(items[2])),
            ]),
          ),
        ]);
      }
    }

    if (count == 4) {
      if (proportions[0] == 'w') {
        final h0 = _round((totalWidth / ratios[0]).clamp(50, (maxH - gap) * 0.66)).toDouble();
        final h = _round((totalWidth - 2 * gap) / (ratios[1] + ratios[2] + ratios[3])).toDouble();
        final w0 = ((totalWidth - 2 * gap) * 0.4).clamp(minW, (h * ratios[1]).clamp(minW, (totalWidth - 2 * gap) * 0.4));
        final w2 = ((totalWidth - 2 * gap) * 0.33).clamp(minW, (h * ratios[3]).clamp(minW, (totalWidth - 2 * gap) * 0.33));
        final w1 = totalWidth - w0 - w2 - 2 * gap;
        final h1 = h.clamp(50.0, maxH - h0 - gap);
        return Column(children: [
          SizedBox(height: h0, child: buildItem(items[0])),
          const SizedBox(height: gap),
          SizedBox(
            height: h1,
            child: Row(children: [
              SizedBox(width: w0, child: buildItem(items[1])),
              const SizedBox(width: gap),
              SizedBox(width: w1, child: buildItem(items[2])),
              const SizedBox(width: gap),
              SizedBox(width: w2, child: buildItem(items[3])),
            ]),
          ),
        ]);
      } else {
        final h = maxH;
        final w0 = _round((h * ratios[0]).clamp(minW, (totalWidth - gap) * 0.6)).toDouble();
        final w = _round((h - 2 * gap) / (1 / ratios[1] + 1 / ratios[2] + 1 / ratios[3])).toDouble();
        final h0 = _round(w / ratios[1]).toDouble();
        final h1 = _round(w / ratios[2]).toDouble();
        final h2 = h - h0 - h1 - 2 * gap;
        final w1 = w.clamp(minW, totalWidth - w0 - gap);
        return SizedBox(
          height: h,
          child: Row(children: [
            SizedBox(width: w0, child: buildItem(items[0])),
            const SizedBox(width: gap),
            SizedBox(
              width: w1,
              child: Column(children: [
                SizedBox(height: h0, child: buildItem(items[1])),
                const SizedBox(height: gap),
                SizedBox(height: h1, child: buildItem(items[2])),
                const SizedBox(height: gap),
                SizedBox(height: h2, child: buildItem(items[3])),
              ]),
            ),
          ]),
        );
      }
    }

    final croppedRatios = ratios.map((r) {
      const maxR = 2.75;
      const minR = 0.6667;
      return avgRatio > 1.1 ? r.clamp(1.0, maxR) : r.clamp(minR, 1.0);
    }).toList();
    final complexMaxH = totalWidth * 4 / 3;

    double multiHeight(int offset, int lineCount) {
      double sum = 0;
      for (int i = offset; i < offset + lineCount; i++) sum += croppedRatios[i];
      return (totalWidth - (lineCount - 1) * gap) / sum;
    }

    List<List<int>> attempts = [];
    List<List<double>> attemptHeights = [];
    void pushAttempt(List<int> lineCounts) {
      final heights = <double>[];
      int offset = 0;
      for (final c in lineCounts) { heights.add(multiHeight(offset, c)); offset += c; }
      attempts.add(lineCounts);
      attemptHeights.add(heights);
    }
    for (int f = 1; f < count; f++) {
      final s = count - f;
      if (f <= 3 && s <= 3) pushAttempt([f, s]);
    }
    for (int f = 1; f < count - 1; f++) {
      for (int s = 1; s < count - f; s++) {
        final t = count - f - s;
        if (f <= 3 && s <= (avgRatio < 0.85 ? 4 : 3) && t <= 3) pushAttempt([f, s, t]);
      }
    }

    int bestIdx = 0;
    double bestDiff = double.infinity;
    for (int i = 0; i < attempts.length; i++) {
      final heights = attemptHeights[i];
      final total = heights.fold(0.0, (a, b) => a + b) + gap * (heights.length - 1);
      final minH = heights.reduce((a, b) => a < b ? a : b);
      final bad1 = minH < minW ? 1.5 : 1.0;
      bool descending = false;
      for (int j = 1; j < attempts[i].length; j++) {
        if (attempts[i][j - 1] > attempts[i][j]) { descending = true; break; }
      }
      final bad2 = descending ? 1.5 : 1.0;
      final diff = (total - complexMaxH).abs() * bad1 * bad2;
      if (diff < bestDiff) { bestDiff = diff; bestIdx = i; }
    }

    final optCounts = attempts[bestIdx];
    final optHeights = attemptHeights[bestIdx];
    int idx = 0;
    final rows = <Widget>[];
    for (int row = 0; row < optCounts.length; row++) {
      final colCount = optCounts[row];
      final h = optHeights[row].round().toDouble();
      final rowItems = <Widget>[];
      for (int col = 0; col < colCount; col++) {
        if (col > 0) rowItems.add(const SizedBox(width: gap));
        final w = (h * croppedRatios[idx]).round().toDouble().clamp(minW, totalWidth);
        rowItems.add(SizedBox(width: w, height: h, child: buildItem(items[idx])));
        idx++;
      }
      if (rows.isNotEmpty) rows.add(const SizedBox(height: gap));
      rows.add(Row(children: rowItems));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  Widget _buildSlideshow(BuildContext context) {
    final items = block['items'] as List<dynamic>? ?? [];
    final caption = block['caption'];
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _IvSlideshowBlock(
        items: items,
        isDark: isDark,
        accountId: accountId,
        onNavigateIV: onNavigateIV,
        accentColor: _accentColor,
        subtleColor: _subtleColor,
        caption: caption,
        captionBuilder: (ctx, cap) => _buildCaption(ctx, cap),
      ),
    );
  }

  Widget _buildChannel(BuildContext context) {
    final title = block['title'] as String? ?? 'Channel';
    final username = block['username'] as String?;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _IvChannelBlock(
        title: title,
        username: username,
        accountId: accountId,
        isDark: isDark,
        accentColor: _accentColor,
        textColor: _textColor,
        subtleColor: _subtleColor,
      ),
    );
  }

  Widget _buildAudio(BuildContext context) {
    final caption = block['caption'];
    final audioId = block['audio_id'] as num?;
    final extra = block['extra'] as String?;
    final mime = block['mime'] as String? ?? 'audio/mpeg';
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
          _IvAudioBlock(
            accountId: accountId,
            audioId: audioId?.toInt() ?? 0,
            extra: extra ?? '',
            mime: mime,
            title: audioTitle,
            performer: performer,
            durationStr: durationStr,
            isDark: isDark,
            accentColor: _accentColor,
            textColor: _textColor,
            subtleColor: _subtleColor,
          ),
          if (caption != null) _buildCaption(context, caption),
        ],
      ),
    );
  }

  Widget _buildMap(BuildContext context) {
    final lat = block['lat'] as num?;
    final lng = block['lng'] as num?;
    final zoom = (block['zoom'] as num?)?.toInt() ?? 15;
    final mapW = (block['w'] as num?)?.toInt() ?? 650;
    final mapH = (block['h'] as num?)?.toInt() ?? 200;
    final caption = block['caption'];
    final geoAccess = block['access'] as num?;

    if (lat == null || lng == null) return const SizedBox.shrink();

    final latD = lat.toDouble();
    final lngD = lng.toDouble();
    final displayW = mapW.toDouble().clamp(200.0, 800.0);
    final displayH = mapH.toDouble().clamp(100.0, 400.0);

    if (geoAccess == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/?mlat=$latD&mlon=$lngD#map=$zoom/$latD/$lngD'), mode: LaunchMode.externalApplication),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  width: displayW,
                  height: displayH,
                  color: isDark ? const Color(0xFF1e2c3a) : const Color(0xFFe8eaed),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.location_pin, color: Colors.red.shade700, size: 36),
                      const SizedBox(height: 8),
                      Text(
                        '${latD.toStringAsFixed(4)}, ${lngD.toStringAsFixed(4)}',
                        style: TextStyle(fontSize: 13, color: _subtleColor, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap to open map',
                        style: TextStyle(fontSize: 12, color: _accentColor),
                      ),
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

    final n = 1 << zoom;
    final latRad = latD * math.pi / 180.0;
    final worldPixelX = ((lngD + 180.0) / 360.0) * n * 256;
    final worldPixelY = ((1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) / 2.0) * n * 256;

    final viewLeftPixel = worldPixelX - displayW / 2;
    final viewTopPixel = worldPixelY - displayH / 2;

    final tileXStart = (viewLeftPixel / 256).floor();
    final tileYStart = (viewTopPixel / 256).floor();
    final tileXEnd = ((viewLeftPixel + displayW) / 256).floor();
    final tileYEnd = ((viewTopPixel + displayH) / 256).floor();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/?mlat=$latD&mlon=$lngD#map=$zoom/$latD/$lngD'), mode: LaunchMode.externalApplication),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: displayW,
                height: displayH,
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    for (int ty = tileYStart; ty <= tileYEnd; ty++)
                      for (int tx = tileXStart; tx <= tileXEnd; tx++)
                        Positioned(
                          left: tx * 256.0 - viewLeftPixel,
                          top: ty * 256.0 - viewTopPixel,
                          width: 256,
                          height: 256,
                          child: Image.network(
                            'https://tile.openstreetmap.org/$zoom/${((tx % n) + n) % n}/${ty.clamp(0, n - 1)}.png',
                            fit: BoxFit.fill,
                            headers: const {'User-Agent': 'UniClient/1.0'},
                            errorBuilder: (_, __, ___) => Container(
                              color: isDark ? const Color(0xFF1e2c3a) : const Color(0xFFe8eaed),
                            ),
                          ),
                        ),
                    Positioned(
                      left: displayW / 2 - 14,
                      top: displayH / 2 - 36,
                      child: Icon(Icons.location_pin, color: Colors.red.shade700, size: 36),
                    ),
                    Positioned(
                      left: 0, right: 0, bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        color: Colors.black45,
                        child: Text(
                          '${latD.toStringAsFixed(4)}, ${lngD.toStringAsFixed(4)}',
                          style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
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
          recognizer: _makeTapRecognizer(() {
            if (href.isNotEmpty) {
              if (onNavigateIV != null && _looksLikeIvUrl(href)) {
                onNavigateIV!(href);
              } else {
                launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
              }
            }
          }),
          children: [child],
        );
      case 'email':
        final addr = rtData['addr'] as String? ?? '';
        final child = _richTextToSpan(context, rtData['c'], baseStyle.copyWith(color: _accentColor));
        if (child == null) return null;
        return TextSpan(
          style: TextStyle(color: _accentColor),
          recognizer: _makeTapRecognizer(() {
            if (addr.isNotEmpty) {
              launchUrl(Uri.parse('mailto:$addr'));
            }
          }),
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
          recognizer: _makeTapRecognizer(() {
            if (phone.isNotEmpty) {
              launchUrl(Uri.parse('tel:$phone'));
            }
          }),
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
  final VoidCallback? onTap;

  const _IvFullPhoto({
    required this.accountId,
    required this.photoId,
    required this.extra,
    this.thumbB64,
    this.photoWidth = 0,
    this.photoHeight = 0,
    this.onTap,
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
        return GestureDetector(
          onTap: widget.onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.file(
              file,
              fit: BoxFit.cover,
              width: double.infinity,
              errorBuilder: (_, __, ___) => _buildThumb(aspectRatio),
            ),
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

class _IvPhotoViewer extends StatefulWidget {
  final String accountId;
  final int? photoId;
  final String? extra;
  final String? thumbB64;

  const _IvPhotoViewer({required this.accountId, this.photoId, this.extra, this.thumbB64});

  @override
  State<_IvPhotoViewer> createState() => _IvPhotoViewerState();
}

class _IvPhotoViewerState extends State<_IvPhotoViewer> {
  String? _fullPath;

  @override
  void initState() {
    super.initState();
    if (widget.photoId != null && widget.extra != null) {
      _loadFullImage();
    }
  }

  Future<void> _loadFullImage() async {
    final engine = context.read<EngineService>();
    final path = await engine.downloadIVPhoto(widget.accountId, widget.photoId!, widget.extra!);
    if (mounted) setState(() => _fullPath = path);
  }

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;
    if (_fullPath != null && File(_fullPath!).existsSync()) {
      imageWidget = InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Image.file(File(_fullPath!), fit: BoxFit.contain),
      );
    } else if (widget.thumbB64 != null && widget.thumbB64!.isNotEmpty) {
      imageWidget = Image.memory(base64Decode(widget.thumbB64!), fit: BoxFit.contain);
    } else {
      imageWidget = const Center(child: CircularProgressIndicator(color: Colors.white));
    }

    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: imageWidget),
          Positioned(
            top: 16, right: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

class _IvVideoBlock extends StatefulWidget {
  final String accountId;
  final int videoId;
  final String extra;
  final String mime;
  final String? thumbB64;
  final double aspectRatio;
  final String durationStr;
  final bool isDark;
  final Color accentColor;
  final Color subtleColor;

  const _IvVideoBlock({
    required this.accountId,
    required this.videoId,
    required this.extra,
    required this.mime,
    this.thumbB64,
    this.aspectRatio = 16 / 9,
    this.durationStr = '',
    required this.isDark,
    required this.accentColor,
    required this.subtleColor,
  });

  @override
  State<_IvVideoBlock> createState() => _IvVideoBlockState();
}

class _IvVideoBlockState extends State<_IvVideoBlock> {
  Player? _player;
  VideoController? _videoController;
  bool _downloading = false;
  bool _playing = false;
  String? _error;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _playVideo() async {
    if (widget.videoId == 0 || widget.extra.isEmpty) {
      setState(() => _error = 'No video data available');
      return;
    }
    setState(() { _downloading = true; _error = null; });
    final engine = context.read<EngineService>();
    final path = await engine.downloadIVDocument(widget.accountId, widget.videoId, widget.extra, widget.mime);
    if (!mounted) return;
    if (path == null || path.isEmpty) {
      setState(() { _downloading = false; _error = 'Failed to download video'; });
      return;
    }
    final player = Player();
    if (AppState.noHwAccelVideo) {
      (player.platform as NativePlayer).setProperty('hwdec', 'no');
    }
    final controller = VideoController(player);
    setState(() {
      _player = player;
      _videoController = controller;
      _downloading = false;
      _playing = true;
    });
    await player.open(Media(path));
  }

  @override
  Widget build(BuildContext context) {
    if (_playing && _videoController != null) {
      return AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Video(controller: _videoController!),
              Positioned(
                top: 8, right: 8,
                child: GestureDetector(
                  onTap: () {
                    _player?.dispose();
                    setState(() { _player = null; _videoController = null; _playing = false; });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget thumb;
    if (widget.thumbB64 != null && widget.thumbB64!.isNotEmpty) {
      thumb = Image.memory(
        base64Decode(widget.thumbB64!),
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, __, ___) => Container(color: widget.isDark ? const Color(0xFF0e1621) : const Color(0xFFe8e8e8)),
      );
    } else {
      thumb = Container(color: widget.isDark ? const Color(0xFF0e1621) : const Color(0xFFe8e8e8));
    }

    return GestureDetector(
      onTap: _downloading ? null : _playVideo,
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            fit: StackFit.expand,
            children: [
              thumb,
              Container(color: Colors.black26),
              Center(
                child: _downloading
                    ? const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                    : _error != null
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline, color: Colors.white70, size: 40),
                              const SizedBox(height: 4),
                              Text(_error!, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            ],
                          )
                        : Container(
                            width: 56, height: 56,
                            decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            child: const Icon(Icons.play_arrow, color: Colors.white, size: 32),
                          ),
              ),
              if (widget.durationStr.isNotEmpty)
                Positioned(
                  bottom: 8, right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                    child: Text(widget.durationStr, style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IvAudioBlock extends StatefulWidget {
  final String accountId;
  final int audioId;
  final String extra;
  final String mime;
  final String? title;
  final String? performer;
  final String durationStr;
  final bool isDark;
  final Color accentColor;
  final Color textColor;
  final Color subtleColor;

  const _IvAudioBlock({
    required this.accountId,
    required this.audioId,
    required this.extra,
    required this.mime,
    this.title,
    this.performer,
    this.durationStr = '',
    required this.isDark,
    required this.accentColor,
    required this.textColor,
    required this.subtleColor,
  });

  @override
  State<_IvAudioBlock> createState() => _IvAudioBlockState();
}

class _IvAudioBlockState extends State<_IvAudioBlock> {
  Player? _player;
  bool _downloading = false;
  bool _playing = false;
  bool _paused = false;
  String? _error;
  final _positionNotifier = ValueNotifier<Duration>(Duration.zero);
  final _durationNotifier = ValueNotifier<Duration>(Duration.zero);
  final List<StreamSubscription> _subs = [];

  @override
  void dispose() {
    for (final s in _subs) { s.cancel(); }
    _player?.dispose();
    _positionNotifier.dispose();
    _durationNotifier.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_player != null) {
      if (_playing && !_paused) {
        _player!.pause();
      } else {
        _player!.play();
      }
      return;
    }

    if (widget.audioId == 0 || widget.extra.isEmpty) {
      setState(() => _error = 'No audio data available');
      return;
    }
    setState(() { _downloading = true; _error = null; });
    final engine = context.read<EngineService>();
    String? path;
    try {
      path = await engine.downloadIVDocument(widget.accountId, widget.audioId, widget.extra, widget.mime);
    } on Exception {
      if (!mounted) return;
      setState(() { _downloading = false; _error = 'Failed to download audio'; });
      return;
    }
    if (!mounted) return;
    if (path == null || path.isEmpty) {
      setState(() { _downloading = false; _error = 'Failed to download audio'; });
      return;
    }
    final player = Player();
    _player = player;
    _subs.add(player.stream.playing.listen((v) {
      if (mounted) setState(() { _playing = v; _paused = !v; });
    }));
    _subs.add(player.stream.position.listen((v) {
      if (mounted) _positionNotifier.value = v;
    }));
    _subs.add(player.stream.duration.listen((v) {
      if (mounted) _durationNotifier.value = v;
    }));
    _subs.add(player.stream.completed.listen((v) {
      if (v && mounted) setState(() { _playing = false; _paused = false; });
    }));
    setState(() { _downloading = false; _playing = true; });
    await player.open(Media(path));
  }

  String _formatDuration(Duration d) {
    final mins = d.inMinutes;
    final secs = d.inSeconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: widget.isDark ? const Color(0xFF1e2c3a) : const Color(0xFFf4f4f5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: (_downloading || _error != null) ? null : _togglePlayback,
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: _error != null ? Colors.grey : widget.accentColor),
                  child: _downloading
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(_error != null ? Icons.error_outline : (_playing && !_paused ? Icons.pause : Icons.play_arrow), color: Colors.white, size: 22),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title ?? widget.performer ?? 'Audio',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: widget.textColor),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.performer != null && widget.title != null)
                      Text(widget.performer!, style: TextStyle(fontSize: 12, color: widget.subtleColor), maxLines: 1),
                    if (_error != null)
                      Text(_error!, style: TextStyle(fontSize: 12, color: widget.subtleColor.withAlpha(180)))
                    else
                      ValueListenableBuilder<Duration>(
                        valueListenable: _positionNotifier,
                        builder: (_, pos, __) => ValueListenableBuilder<Duration>(
                          valueListenable: _durationNotifier,
                          builder: (_, dur, __) => Text(
                            _playing || _paused
                                ? '${_formatDuration(pos)} / ${_formatDuration(dur)}'
                                : widget.durationStr.isNotEmpty ? widget.durationStr : '',
                            style: TextStyle(fontSize: 12, color: widget.subtleColor),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (_playing || _paused) ...[
            const SizedBox(height: 6),
            ValueListenableBuilder<Duration>(
              valueListenable: _positionNotifier,
              builder: (_, pos, __) {
                final dur = _durationNotifier.value;
                final progress = dur.inMilliseconds > 0
                    ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                    : 0.0;
                return LinearProgressIndicator(
                  value: progress,
                  backgroundColor: widget.isDark ? const Color(0xFF2a3a4a) : const Color(0xFFe0e0e0),
                  valueColor: AlwaysStoppedAnimation(widget.accentColor),
                  minHeight: 3,
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _IvEmbedBlock extends StatefulWidget {
  final Map<String, dynamic> block;
  final bool isDark;
  final String accountId;

  const _IvEmbedBlock({required this.block, required this.isDark, required this.accountId});

  @override
  State<_IvEmbedBlock> createState() => _IvEmbedBlockState();
}

class _IvEmbedBlockState extends State<_IvEmbedBlock> {
  Player? _player;
  VideoController? _videoController;
  bool _playing = false;
  bool _loading = false;

  Color get _accentColor => widget.isDark ? const Color(0xFF71baf7) : const Color(0xFF168acd);
  Color get _textColor => widget.isDark ? const Color(0xFFe0e4e8) : const Color(0xFF222222);
  Color get _subtleColor => widget.isDark ? const Color(0xFF8a9bab) : const Color(0xFF777777);

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  static String? _extractYouTubeId(String url) {
    for (final p in [
      RegExp(r'youtube\.com/watch\?v=([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtu\.be/([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtube\.com/embed/([a-zA-Z0-9_-]{11})'),
    ]) {
      final m = p.firstMatch(url);
      if (m != null) return m.group(1);
    }
    return null;
  }

  static String? _extractVimeoId(String url) {
    final m = RegExp(r'vimeo\.com/(\d+)').firstMatch(url);
    return m?.group(1);
  }

  Future<void> _playVideo(String url) async {
    setState(() => _loading = true);
    try {
      final player = Player();
      if (AppState.noHwAccelVideo) {
        (player.platform as NativePlayer).setProperty('hwdec', 'no');
      }
      final controller = VideoController(player);
      setState(() {
        _player = player;
        _videoController = controller;
        _playing = true;
        _loading = false;
      });
      await player.open(Media(url));
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    }
  }

  void _stopVideo() {
    _player?.dispose();
    setState(() { _player = null; _videoController = null; _playing = false; });
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&mdash;', '—')
        .replaceAll('&ndash;', '–')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final embedUrl = widget.block['url'] as String?;
    final embedHtml = widget.block['html'] as String?;
    final w = (widget.block['w'] as num?)?.toDouble() ?? 0;
    final h = (widget.block['h'] as num?)?.toDouble() ?? 0;

    String? youtubeId;
    String? vimeoId;
    if (embedUrl != null) {
      youtubeId = _extractYouTubeId(embedUrl);
      vimeoId ??= _extractVimeoId(embedUrl);
    }
    if (youtubeId == null && embedHtml != null) {
      final srcMatch = RegExp(r"""src=["']([^"']+youtube[^"']+)["']""").firstMatch(embedHtml);
      if (srcMatch != null) youtubeId = _extractYouTubeId(srcMatch.group(1)!);
    }

    if (_playing && _videoController != null) {
      return AspectRatio(
        aspectRatio: w > 0 && h > 0 ? w / h : 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Video(controller: _videoController!),
              Positioned(
                top: 8, right: 8,
                child: GestureDetector(
                  onTap: _stopVideo,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (youtubeId != null) {
      return _buildVideoEmbed(
        thumbnailUrl: 'https://img.youtube.com/vi/$youtubeId/hqdefault.jpg',
        playUrl: 'https://www.youtube.com/watch?v=$youtubeId',
        label: 'YouTube',
        aspectRatio: w > 0 && h > 0 ? w / h : 16 / 9,
      );
    }

    if (vimeoId != null) {
      return _buildVideoEmbed(
        thumbnailUrl: null,
        playUrl: 'https://vimeo.com/$vimeoId',
        label: 'Vimeo',
        aspectRatio: w > 0 && h > 0 ? w / h : 16 / 9,
      );
    }

    final isTwitter = embedUrl != null && (embedUrl.contains('twitter.com') || embedUrl.contains('x.com'));
    if (isTwitter && embedHtml != null) {
      return _buildTwitterCard(embedHtml, embedUrl);
    }

    final isSoundCloud = embedUrl != null && embedUrl.contains('soundcloud.com');
    if (isSoundCloud) {
      return _buildSoundCloudCard(embedUrl, embedHtml);
    }

    return _buildGenericEmbed(embedUrl, embedHtml, w, h);
  }

  Widget _buildVideoEmbed({
    required String? thumbnailUrl,
    required String playUrl,
    required String label,
    required double aspectRatio,
  }) {
    return GestureDetector(
      onTap: _loading ? null : () => _playVideo(playUrl),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (thumbnailUrl != null)
                Image.network(
                  thumbnailUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: widget.isDark ? const Color(0xFF0e1621) : const Color(0xFFe8e8e8),
                    child: Center(child: Icon(Icons.play_circle_outline, size: 48, color: _subtleColor)),
                  ),
                )
              else
                Container(
                  color: widget.isDark ? const Color(0xFF0e1621) : const Color(0xFFe8e8e8),
                  child: Center(child: Icon(Icons.play_circle_outline, size: 48, color: _subtleColor)),
                ),
              Center(
                child: _loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Container(
                        width: 64, height: 64,
                        decoration: BoxDecoration(
                          color: label == 'YouTube' ? Colors.red.shade600 : Colors.blue.shade600,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.play_arrow, color: Colors.white, size: 40),
                      ),
              ),
              Positioned(
                left: 8, top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                  child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTwitterCard(String html, String? url) {
    final text = _stripHtml(html);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.isDark ? const Color(0xFF1e2c3a) : const Color(0xFFf4f4f5),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: const Color(0xFF1DA1F2), width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.alternate_email, size: 18, color: const Color(0xFF1DA1F2)),
              const SizedBox(width: 8),
              Text('Post', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _textColor)),
            ],
          ),
          const SizedBox(height: 8),
          Text(text, style: TextStyle(fontSize: 15, color: _textColor, height: 1.5)),
          if (url != null) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
              child: Text('View original', style: TextStyle(fontSize: 13, color: _accentColor, decoration: TextDecoration.underline)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSoundCloudCard(String url, String? html) {
    String? srcUrl;
    if (html != null) {
      final m = RegExp(r"""src=["']([^"']+soundcloud[^"']+)["']""").firstMatch(html);
      srcUrl = m?.group(1);
    }
    final playTarget = srcUrl ?? url;

    return GestureDetector(
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: widget.isDark ? const Color(0xFF1e2c3a) : const Color(0xFFf4f4f5),
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: const Color(0xFFFF5500), width: 3)),
        ),
        child: Row(
          children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(color: const Color(0xFFFF5500), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.music_note, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SoundCloud', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _textColor)),
                  const SizedBox(height: 2),
                  Text(Uri.tryParse(playTarget)?.pathSegments.lastOrNull ?? 'Audio', style: TextStyle(fontSize: 13, color: _subtleColor), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Icon(Icons.open_in_new, size: 16, color: _subtleColor),
          ],
        ),
      ),
    );
  }

  Widget _buildGenericEmbed(String? url, String? html, double w, double h) {
    String? displayUrl = url;
    if (displayUrl == null && html != null) {
      final srcMatch = RegExp(r'''src=["']([^"']+)["']''').firstMatch(html);
      if (srcMatch != null) displayUrl = srcMatch.group(1);
    }

    String? contentText;
    if (html != null) {
      contentText = _stripHtml(html);
      if (contentText.isEmpty) contentText = null;
    }

    return GestureDetector(
      onTap: displayUrl != null
          ? () => launchUrl(Uri.parse(displayUrl!), mode: LaunchMode.externalApplication)
          : null,
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(minHeight: h > 0 ? h.clamp(60, 400) : 80),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: widget.isDark ? const Color(0xFF1e2c3a) : const Color(0xFFf4f4f5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: widget.isDark ? const Color(0xFF2a3a4a) : const Color(0xFFe0e0e0)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (contentText != null) ...[
              Text(contentText, style: TextStyle(fontSize: 15, color: _textColor, height: 1.5), maxLines: 10, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 8),
            ],
            if (displayUrl != null)
              Row(
                children: [
                  Icon(Icons.web, size: 18, color: _subtleColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      displayUrl,
                      style: TextStyle(fontSize: 13, color: _accentColor, decoration: TextDecoration.underline),
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.open_in_new, size: 16, color: _subtleColor),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _IvChannelBlock extends StatefulWidget {
  final String title;
  final String? username;
  final String accountId;
  final bool isDark;
  final Color accentColor;
  final Color textColor;
  final Color subtleColor;

  const _IvChannelBlock({
    required this.title,
    this.username,
    required this.accountId,
    required this.isDark,
    required this.accentColor,
    required this.textColor,
    required this.subtleColor,
  });

  @override
  State<_IvChannelBlock> createState() => _IvChannelBlockState();
}

class _IvChannelBlockState extends State<_IvChannelBlock> {
  bool _joined = false;
  bool _joining = false;

  Future<void> _joinChannel() async {
    final username = widget.username;
    if (username == null || username.isEmpty) return;
    setState(() => _joining = true);
    try {
      final engine = context.read<EngineService>();
      await engine.joinChat(widget.accountId, username);
      if (mounted) setState(() { _joined = true; _joining = false; });
    } catch (e) {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: widget.isDark ? const Color(0xFF1e2c3a) : const Color(0xFFf4f4f5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: widget.accentColor.withAlpha(40),
            child: Icon(Icons.campaign, color: widget.accentColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: widget.textColor)),
                if (widget.username != null) Text('@${widget.username}', style: TextStyle(fontSize: 13, color: widget.subtleColor)),
              ],
            ),
          ),
          if (_joined)
            Text('Joined', style: TextStyle(color: widget.subtleColor, fontSize: 14))
          else
            TextButton(
              onPressed: _joining ? null : _joinChannel,
              child: _joining
                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: widget.accentColor))
                  : Text('Join', style: TextStyle(color: widget.accentColor, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

class _IvSlideshowBlock extends StatefulWidget {
  final List<dynamic> items;
  final bool isDark;
  final String accountId;
  final void Function(String url)? onNavigateIV;
  final Color accentColor;
  final Color subtleColor;
  final dynamic caption;
  final Widget Function(BuildContext, dynamic) captionBuilder;

  const _IvSlideshowBlock({
    required this.items,
    required this.isDark,
    required this.accountId,
    this.onNavigateIV,
    required this.accentColor,
    required this.subtleColor,
    this.caption,
    required this.captionBuilder,
  });

  @override
  State<_IvSlideshowBlock> createState() => _IvSlideshowBlockState();
}

class _IvSlideshowBlockState extends State<_IvSlideshowBlock> {
  late final PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    if (page < 0 || page >= widget.items.length) return;
    _pageController.animateToPage(page, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = (w * 0.625).clamp(200.0, 500.0);
            return SizedBox(
              height: h,
              child: Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                itemCount: widget.items.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (ctx, i) {
                  return _IvBlock(
                    block: widget.items[i] as Map<String, dynamic>,
                    isDark: widget.isDark,
                    accountId: widget.accountId,
                    onNavigateIV: widget.onNavigateIV,
                  );
                },
              ),
              if (_currentPage > 0)
                Positioned(
                  left: 8, top: 0, bottom: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: () => _goTo(_currentPage - 1),
                      child: Container(
                        width: 36, height: 36,
                        decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                        child: const Icon(Icons.chevron_left, color: Colors.white, size: 24),
                      ),
                    ),
                  ),
                ),
              if (_currentPage < widget.items.length - 1)
                Positioned(
                  right: 8, top: 0, bottom: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: () => _goTo(_currentPage + 1),
                      child: Container(
                        width: 36, height: 36,
                        decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                        child: const Icon(Icons.chevron_right, color: Colors.white, size: 24),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
          },
        ),
        const SizedBox(height: 8),
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(widget.items.length, (i) {
              final isActive = i == _currentPage;
              return GestureDetector(
                onTap: () => _goTo(i),
                child: Container(
                  width: isActive ? 8 : 6,
                  height: isActive ? 8 : 6,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive ? widget.accentColor : widget.subtleColor.withAlpha(100),
                  ),
                ),
              );
            }),
          ),
        ),
        if (widget.caption != null) widget.captionBuilder(context, widget.caption),
      ],
    );
  }
}

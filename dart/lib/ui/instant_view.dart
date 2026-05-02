import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

  @override
  void initState() {
    super.initState();
    _fetchPage();
  }

  Future<void> _fetchPage() async {
    final engine = context.read<EngineService>();
    try {
      final data = await engine.getInstantViewPage(widget.accountId, widget.url);
      if (!mounted) return;
      if (data == null) {
        _fallbackToBrowser();
        return;
      }
      setState(() { _loading = false; _pageData = data; });
    } catch (e) {
      if (!mounted) return;
      _fallbackToBrowser();
    }
  }

  void _fallbackToBrowser() {
    Process.run('xdg-open', [widget.url]);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF17212b) : Colors.white;
    final fgColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        foregroundColor: fgColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.siteName.isNotEmpty ? widget.siteName : 'INSTANT VIEW',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: fgColor),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser, size: 22),
            tooltip: 'Open in browser',
            onPressed: () => Process.run('xdg-open', [widget.url]),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: isDark ? const Color(0xFF0e1621) : const Color(0xFFe0e0e0)),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: isDark ? const Color(0xFF71baf7) : const Color(0xFF168acd)))
          : _error != null
              ? _buildError(fgColor)
              : _buildContent(isDark, fgColor),
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
              onPressed: () => Process.run('xdg-open', [widget.url]),
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
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        itemCount: blocks.length,
        itemBuilder: (context, i) {
          final block = blocks[i] as Map<String, dynamic>;
          return _IvBlock(block: block, isDark: isDark);
        },
      ),
    );
  }
}

class _IvBlock extends StatelessWidget {
  final Map<String, dynamic> block;
  final bool isDark;

  const _IvBlock({required this.block, required this.isDark});

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
          child: _richText(block['text'], TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: _textColor, height: 1.3)),
        );
      case 'subtitle':
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _richText(block['text'], TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: _subtleColor, height: 1.3)),
        );
      case 'kicker':
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: _richText(block['text'], TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _accentColor, letterSpacing: 0.5)),
        );
      case 'author_date':
        return _buildAuthorDate();
      case 'header':
        return Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 8),
          child: _richText(block['text'], TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _textColor, height: 1.3)),
        );
      case 'subheader':
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6),
          child: _richText(block['text'], TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: _textColor, height: 1.3)),
        );
      case 'paragraph':
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _richText(block['text'], TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: _textColor, height: 1.6)),
        );
      case 'preformatted':
        return _buildPreformatted();
      case 'footer':
        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: _richText(block['text'], TextStyle(fontSize: 13, color: _subtleColor, height: 1.4)),
        );
      case 'divider':
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(child: Container(width: 48, height: 2, color: _subtleColor.withAlpha(80))),
        );
      case 'anchor':
        return const SizedBox.shrink();
      case 'photo':
        return _buildPhoto();
      case 'cover':
        final coverBlock = block['cover'] as Map<String, dynamic>?;
        if (coverBlock == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _IvBlock(block: coverBlock, isDark: isDark),
        );
      case 'blockquote':
        return _buildBlockquote();
      case 'pullquote':
        return _buildPullquote();
      case 'list':
        return _buildList();
      case 'ordered_list':
        return _buildOrderedList();
      case 'details':
        return _buildDetails();
      case 'table':
        return _buildTable();
      case 'embed':
        return _buildEmbed();
      case 'embed_post':
        return _buildEmbedPost();
      case 'related':
        return _buildRelated();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildAuthorDate() {
    final dateTs = block['date'] as num?;
    String dateStr = '';
    if (dateTs != null && dateTs > 0) {
      final dt = DateTime.fromMillisecondsSinceEpoch(dateTs.toInt() * 1000);
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      dateStr = '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    }
    final authorWidget = _richText(block['author'], TextStyle(fontSize: 14, color: _subtleColor));
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

  Widget _buildPreformatted() {
    final bgColor = isDark ? const Color(0xFF1e2c3a) : const Color(0xFFf4f4f5);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(4),
        ),
        child: _richText(
          block['text'],
          TextStyle(fontSize: 14, fontFamily: 'monospace', color: _textColor, height: 1.5),
        ) ?? const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildPhoto() {
    final thumbB64 = block['thumb'] as String?;
    final caption = block['caption'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (thumbB64 != null && thumbB64.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.memory(
                base64Decode(thumbB64),
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (_, __, ___) => const SizedBox(height: 100),
              ),
            ),
          if (caption != null) _buildCaption(caption),
        ],
      ),
    );
  }

  Widget _buildCaption(dynamic caption) {
    if (caption is! Map<String, dynamic>) return const SizedBox.shrink();
    final textWidget = _richText(caption['text'], TextStyle(fontSize: 13, color: _subtleColor, height: 1.4));
    final creditWidget = _richText(caption['credit'], TextStyle(fontSize: 12, color: _subtleColor.withAlpha(180), height: 1.4));
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

  Widget _buildBlockquote() {
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
            _richText(block['text'], TextStyle(fontSize: 16, fontStyle: FontStyle.italic, color: _textColor, height: 1.5)) ?? const SizedBox.shrink(),
            if (block['caption'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _richText(block['caption'], TextStyle(fontSize: 13, color: _subtleColor)) ?? const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPullquote() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      child: Column(
        children: [
          _richText(
            block['text'],
            TextStyle(fontSize: 20, fontStyle: FontStyle.italic, fontWeight: FontWeight.w500, color: _textColor, height: 1.4),
          ) ?? const SizedBox.shrink(),
          if (block['caption'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _richText(block['caption'], TextStyle(fontSize: 14, color: _subtleColor)) ?? const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }

  Widget _buildList() {
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
                  Expanded(child: _richText(itemMap['text'], TextStyle(fontSize: 16, color: _textColor, height: 1.6)) ?? const SizedBox.shrink()),
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
                    children: blocks.map((b) => _IvBlock(block: b as Map<String, dynamic>, isDark: isDark)).toList(),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildOrderedList() {
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
                  Expanded(child: _richText(itemMap['text'], TextStyle(fontSize: 16, color: _textColor, height: 1.6)) ?? const SizedBox.shrink()),
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
                    children: blocks.map((b) => _IvBlock(block: b as Map<String, dynamic>, isDark: isDark)).toList(),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDetails() {
    final blocks = block['blocks'] as List<dynamic>? ?? [];
    final open = block['open'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _IvDetails(
        title: _richText(block['title'], TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _textColor)),
        blocks: blocks,
        isDark: isDark,
        initiallyOpen: open,
      ),
    );
  }

  Widget _buildTable() {
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

  Widget _buildEmbed() {
    final embedUrl = block['url'] as String?;
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
            if (embedUrl != null && embedUrl.isNotEmpty)
              GestureDetector(
                onTap: () => Process.run('xdg-open', [embedUrl]),
                child: Text(embedUrl, style: TextStyle(fontSize: 13, color: _accentColor, decoration: TextDecoration.underline)),
              ),
            if (block['caption'] != null) _buildCaption(block['caption']),
          ],
        ),
      ),
    );
  }

  Widget _buildEmbedPost() {
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
            ...blocks.map((b) => _IvBlock(block: b as Map<String, dynamic>, isDark: isDark)),
            if (block['caption'] != null) _buildCaption(block['caption']),
          ],
        ),
      ),
    );
  }

  Widget _buildRelated() {
    final articles = block['articles'] as List<dynamic>? ?? [];
    if (articles.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _richText(block['title'], TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _textColor)) ??
              Text('Related', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _textColor)),
          const SizedBox(height: 8),
          ...articles.map((a) {
            final am = a as Map<String, dynamic>;
            final title = am['title'] as String? ?? am['url'] as String? ?? '';
            final desc = am['desc'] as String? ?? '';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () {
                  final url = am['url'] as String?;
                  if (url != null) Process.run('xdg-open', [url]);
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

  Widget? _richText(dynamic rtData, TextStyle baseStyle) {
    if (rtData == null) return null;
    final span = _richTextToSpan(rtData, baseStyle);
    if (span == null) return null;
    return SelectableText.rich(TextSpan(children: [span]), style: baseStyle);
  }

  InlineSpan? _richTextToSpan(dynamic rtData, TextStyle baseStyle) {
    if (rtData == null) return null;
    if (rtData is! Map<String, dynamic>) return null;
    final t = rtData['t'] as String? ?? '';
    switch (t) {
      case 'plain':
        final text = rtData['v'] as String? ?? '';
        if (text.isEmpty) return null;
        return TextSpan(text: text);
      case 'bold':
        final child = _richTextToSpan(rtData['c'], baseStyle.copyWith(fontWeight: FontWeight.w700));
        if (child == null) return null;
        return TextSpan(style: const TextStyle(fontWeight: FontWeight.w700), children: [child]);
      case 'italic':
        final child = _richTextToSpan(rtData['c'], baseStyle.copyWith(fontStyle: FontStyle.italic));
        if (child == null) return null;
        return TextSpan(style: const TextStyle(fontStyle: FontStyle.italic), children: [child]);
      case 'underline':
        final child = _richTextToSpan(rtData['c'], baseStyle.copyWith(decoration: TextDecoration.underline));
        if (child == null) return null;
        return TextSpan(style: const TextStyle(decoration: TextDecoration.underline), children: [child]);
      case 'strike':
        final child = _richTextToSpan(rtData['c'], baseStyle.copyWith(decoration: TextDecoration.lineThrough));
        if (child == null) return null;
        return TextSpan(style: const TextStyle(decoration: TextDecoration.lineThrough), children: [child]);
      case 'fixed':
        final child = _richTextToSpan(rtData['c'], baseStyle.copyWith(fontFamily: 'monospace'));
        if (child == null) return null;
        return TextSpan(style: TextStyle(fontFamily: 'monospace', fontSize: baseStyle.fontSize != null ? baseStyle.fontSize! - 1 : 14, backgroundColor: isDark ? const Color(0xFF1e2c3a) : const Color(0xFFf0f0f0)), children: [child]);
      case 'url':
        final href = rtData['href'] as String? ?? '';
        final child = _richTextToSpan(rtData['c'], baseStyle.copyWith(color: _accentColor));
        if (child == null) return null;
        return TextSpan(
          style: TextStyle(color: _accentColor, decoration: TextDecoration.underline, decorationColor: _accentColor.withAlpha(100)),
          children: [child],
        );
      case 'email':
        final child = _richTextToSpan(rtData['c'], baseStyle.copyWith(color: _accentColor));
        if (child == null) return null;
        return TextSpan(style: TextStyle(color: _accentColor), children: [child]);
      case 'concat':
        final parts = rtData['parts'] as List<dynamic>? ?? [];
        final spans = <InlineSpan>[];
        for (final p in parts) {
          final s = _richTextToSpan(p, baseStyle);
          if (s != null) spans.add(s);
        }
        if (spans.isEmpty) return null;
        return TextSpan(children: spans);
      case 'sub':
        final child = _richTextToSpan(rtData['c'], baseStyle);
        if (child == null) return null;
        return TextSpan(style: TextStyle(fontSize: (baseStyle.fontSize ?? 16) * 0.75, fontFeatures: const [FontFeature.subscripts()]), children: [child]);
      case 'sup':
        final child = _richTextToSpan(rtData['c'], baseStyle);
        if (child == null) return null;
        return TextSpan(style: TextStyle(fontSize: (baseStyle.fontSize ?? 16) * 0.75, fontFeatures: const [FontFeature.superscripts()]), children: [child]);
      case 'marked':
        final child = _richTextToSpan(rtData['c'], baseStyle);
        if (child == null) return null;
        return TextSpan(style: TextStyle(backgroundColor: isDark ? const Color(0xFF3a4a2a) : const Color(0xFFfff9c4)), children: [child]);
      case 'phone':
        final child = _richTextToSpan(rtData['c'], baseStyle.copyWith(color: _accentColor));
        if (child == null) return null;
        return TextSpan(style: TextStyle(color: _accentColor), children: [child]);
      case 'anchor':
        return _richTextToSpan(rtData['c'], baseStyle);
      case 'image':
        return null;
      default:
        return null;
    }
  }
}

class _IvDetails extends StatefulWidget {
  final Widget? title;
  final List<dynamic> blocks;
  final bool isDark;
  final bool initiallyOpen;

  const _IvDetails({required this.title, required this.blocks, required this.isDark, required this.initiallyOpen});

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
              children: widget.blocks.map((b) => _IvBlock(block: b as Map<String, dynamic>, isDark: widget.isDark)).toList(),
            ),
          ),
      ],
    );
  }
}

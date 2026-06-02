import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../bridge/engine_service.dart';
import 'debug.dart';

/// Client-side translation backends for AyuGram's "Translation Provider" setting.
///
/// AyuGram selects the actual translation backend from `translationProvider()`
/// (lang/translate_provider.cpp:33-67): Telegram uses the MTProto
/// `messages.translateText` API, while Google and Yandex are plain client-side
/// HTTP calls (ayu/features/translator/implementations/{google,yandex}.cpp). The
/// Native provider is OS-level and unavailable on our pure-Dart desktop build, so
/// it falls back to Telegram — matching `ResolveTranslateProvider`'s
/// `!IsTranslateProviderAvailable()` branch.
///
/// uniclient's engine translate path (Go `messages.translateText`) is the Telegram
/// backend; Google/Yandex are handled here so the provider choice takes effect
/// without round-tripping HTTP-only providers through the Telegram core.

// Provider ids (match AppState._translationProvider / ayu_general_page choose-button).
const int kProviderTelegram = 0;
const int kProviderGoogle = 1;
const int kProviderYandex = 2;
const int kProviderNative = 3;

const String _kDesktopUserAgent =
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

/// Routes a translation request to the configured [provider].
///
/// Google/Yandex translate [sourceText] over HTTP (and fall back to the engine on
/// any failure). Telegram/Native go through the engine: by [msgId] when provided
/// (server-side message translation) or as free text otherwise.
Future<String?> translateWithProvider(
  EngineService engine, {
  required int provider,
  required String accountId,
  String chatId = '',
  String msgId = '',
  required String toLang,
  String sourceText = '',
}) async {
  if ((provider == kProviderGoogle || provider == kProviderYandex) &&
      sourceText.isNotEmpty) {
    try {
      final r = provider == kProviderGoogle
          ? await _googleTranslate(sourceText, toLang)
          : await _yandexTranslate(sourceText, toLang);
      if (r != null && r.isNotEmpty) return r;
    } catch (e) {
      Debug.error('TRANSLATE', 'provider $provider failed', e);
    }
    // fall through to the engine (Telegram) backend on failure
  }
  if (msgId.isNotEmpty) {
    return engine.translateText(accountId, chatId, msgId, toLang);
  }
  if (sourceText.isNotEmpty) {
    return engine.translateFreeText(accountId, sourceText, toLang);
  }
  return null;
}

// ── Google ── (port of implementations/google.cpp)

Future<String?> _googleTranslate(String text, String toLang) async {
  final to = toLang.trim();
  if (text.isEmpty || to.isEmpty) return null;
  // Body shape: [[["<text>"],"auto","<to>"],"wt_lib"]; newlines → <br>.
  final body = jsonEncode([
    [
      [text.replaceAll('\n', '<br>')],
      'auto',
      to,
    ],
    'wt_lib',
  ]);
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  try {
    final req = await client.postUrl(
        Uri.parse('https://translate-pa.googleapis.com/v1/translateHtml'));
    req.headers.set(HttpHeaders.contentTypeHeader, 'application/json+protobuf');
    req.headers.set('X-Goog-Api-Key',
        'AIzaSyATBXajvzQLTDHEQbcpq0Ihe0vWDHmO520');
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    req.headers.set(HttpHeaders.userAgentHeader, _kDesktopUserAgent);
    req.add(utf8.encode(body));
    final resp = await req.close().timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) return null;
    final respBody = await resp.transform(utf8.decoder).join();
    final decoded = jsonDecode(respBody);
    if (decoded is! List || decoded.isEmpty) return null;
    final combined = _collectStrings(decoded[0]).join(' ').trim();
    if (combined.isEmpty) return null;
    return _decodeHtml(combined);
  } finally {
    client.close(force: true);
  }
}

// Mirror of google.cpp collectStrings(): recursively gather translation strings.
List<String> _collectStrings(dynamic value) {
  final out = <String>[];
  if (value is String) {
    out.add(value);
  } else if (value is List) {
    for (final item in value) {
      out.addAll(_collectStrings(item));
    }
  } else if (value is Map) {
    if (value.containsKey('text')) out.addAll(_collectStrings(value['text']));
    if (value.containsKey('trans')) out.addAll(_collectStrings(value['trans']));
  }
  return out;
}

// ── Yandex ── (port of implementations/yandex.cpp)

Future<String?> _yandexTranslate(String text, String toLang) async {
  final to = toLang.trim();
  if (text.isEmpty || to.isEmpty) return null;
  final url = Uri.parse(
      'https://translate.yandex.net/api/v1/tr.json/translate'
      '?srv=android&id=${_randomUuid()}-0-0');
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  try {
    final req = await client.postUrl(url);
    req.headers.set(HttpHeaders.userAgentHeader,
        'ru.yandex.translate/21.15.4.21402814 (Xiaomi Redmi K20 Pro; Android 11)');
    req.headers
        .set(HttpHeaders.contentTypeHeader, 'application/x-www-form-urlencoded');
    final form = 'lang=${Uri.encodeQueryComponent(to)}'
        '&text=${Uri.encodeQueryComponent(text)}';
    req.add(utf8.encode(form));
    final resp = await req.close().timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) return null;
    final respBody = await resp.transform(utf8.decoder).join();
    final decoded = jsonDecode(respBody);
    if (decoded is! Map) return null;
    final textArr = decoded['text'];
    if (textArr is! List || textArr.isEmpty) return null;
    final combined = textArr.whereType<String>().join('\n').trim();
    return combined.isEmpty ? null : combined;
  } finally {
    client.close(force: true);
  }
}

// 32 random hex chars, mirroring QUuid::createUuid() with braces/dashes stripped.
String _randomUuid() {
  final rnd = Random();
  final sb = StringBuffer();
  for (var i = 0; i < 32; i++) {
    sb.write(rnd.nextInt(16).toRadixString(16));
  }
  return sb.toString();
}

// Equivalent of google.cpp decodeHtmlEntities (QTextDocument::toPlainText):
// <br> → newline, then unescape the common HTML entities.
String _decodeHtml(String s) {
  var r = s.replaceAll(RegExp(r'<br\s*/?>'), '\n');
  r = r
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ');
  r = r.replaceAllMapped(
      RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)));
  r = r.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'),
      (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)));
  // &amp; last so "&amp;lt;" decodes to "&lt;", not "<".
  r = r.replaceAll('&amp;', '&');
  return r;
}

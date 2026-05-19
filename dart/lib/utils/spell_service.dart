import 'dart:io';
import 'dart:ui';

import 'package:flutter/services.dart';

class UniSpellCheckService implements SpellCheckService {
  static final UniSpellCheckService instance = UniSpellCheckService._();
  UniSpellCheckService._();

  final Map<String, Set<String>> _dictionaries = {};
  bool _loaded = false;

  static String get dictsDir {
    if (Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? '/tmp';
      return '$home/.local/share/uniclient/dicts';
    }
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '/tmp';
      return '$home/Library/Application Support/uniclient/dicts';
    }
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'] ?? '';
      return '$appData\\uniclient\\dicts';
    }
    return '/tmp/uniclient_dicts';
  }

  Future<void> loadDictionaries(Set<String> enabledCodes) async {
    _dictionaries.clear();
    _loaded = false;

    final systemDirs = <String>[
      if (Platform.isLinux) ...['/usr/share/hunspell', '/usr/share/myspell/dicts'],
    ];

    final allDirs = [...systemDirs, dictsDir];

    for (final dirPath in allDirs) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;
      for (final f in dir.listSync()) {
        if (!f.path.endsWith('.dic')) continue;
        final code = f.path.split('/').last.replaceAll('.dic', '');
        if (enabledCodes.isNotEmpty && !enabledCodes.contains(code)) continue;
        if (_dictionaries.containsKey(code)) continue;
        try {
          final words = <String>{};
          final lines = await File(f.path).readAsLines();
          var skipFirst = true;
          for (final line in lines) {
            if (skipFirst) { skipFirst = false; continue; }
            if (line.isEmpty) continue;
            final slashIdx = line.indexOf('/');
            final word = slashIdx > 0 ? line.substring(0, slashIdx) : line;
            words.add(word.toLowerCase());
          }
          if (words.isNotEmpty) _dictionaries[code] = words;
        } catch (_) {}
      }
    }
    _loaded = true;
  }

  bool isWordCorrect(String word) {
    if (!_loaded || _dictionaries.isEmpty) return true;
    final lower = word.toLowerCase();
    for (final dict in _dictionaries.values) {
      if (dict.contains(lower)) return true;
    }
    return false;
  }

  @override
  Future<List<SuggestionSpan>?> fetchSpellCheckSuggestions(
      Locale locale, String text) async {
    if (!_loaded || _dictionaries.isEmpty) return null;

    final spans = <SuggestionSpan>[];
    final wordPattern = RegExp(r"[a-zA-ZÀ-ÿЀ-ӿ']+");

    for (final match in wordPattern.allMatches(text)) {
      final word = match.group(0)!;
      if (word.length < 2) continue;
      if (!isWordCorrect(word)) {
        spans.add(SuggestionSpan(
          TextRange(start: match.start, end: match.end),
          const [],
        ));
      }
    }
    return spans;
  }

  List<String> getLoadedDictCodes() => _dictionaries.keys.toList();

  static const downloadManifest = <String, DictDownload>{
    'en_US': DictDownload('English (US)', 'en', 'en_US'),
    'en_GB': DictDownload('English (UK)', 'en', 'en_GB'),
    'de_DE': DictDownload('German', 'de', 'de_DE_frami'),
    'fr_FR': DictDownload('French', 'fr_FR', 'fr'),
    'es_ES': DictDownload('Spanish', 'es', 'es_ES'),
    'it_IT': DictDownload('Italian', 'it_IT', 'it_IT'),
    'pt_BR': DictDownload('Portuguese (Brazil)', 'pt_BR', 'pt_BR'),
    'pt_PT': DictDownload('Portuguese', 'pt_PT', 'pt_PT'),
    'ru_RU': DictDownload('Russian', 'ru_RU', 'ru_RU'),
    'uk_UA': DictDownload('Ukrainian', 'uk_UA', 'uk_UA'),
    'pl_PL': DictDownload('Polish', 'pl_PL', 'pl_PL'),
    'nl_NL': DictDownload('Dutch', 'nl_NL', 'nl_NL'),
    'cs_CZ': DictDownload('Czech', 'cs_CZ', 'cs_CZ'),
    'sv_SE': DictDownload('Swedish', 'sv_SE', 'sv_SE'),
    'da_DK': DictDownload('Danish', 'da_DK', 'da_DK'),
    'nb_NO': DictDownload('Norwegian', 'no', 'nb_NO'),
    'hu_HU': DictDownload('Hungarian', 'hu_HU', 'hu_HU'),
    'ro_RO': DictDownload('Romanian', 'ro', 'ro_RO'),
    'tr_TR': DictDownload('Turkish', 'tr_TR', 'tr_TR'),
    'hr_HR': DictDownload('Croatian', 'hr_HR', 'hr_HR'),
    'sl_SI': DictDownload('Slovenian', 'sl_SI', 'sl_SI'),
    'sk_SK': DictDownload('Slovak', 'sk_SK', 'sk_SK'),
    'bg_BG': DictDownload('Bulgarian', 'bg_BG', 'bg_BG'),
    'el_GR': DictDownload('Greek', 'el_GR', 'el_GR'),
    'ca_ES': DictDownload('Catalan', 'ca', 'ca_ES'),
    'he_IL': DictDownload('Hebrew', 'he_IL', 'he_IL'),
    'ar': DictDownload('Arabic', 'ar', 'ar'),
    'vi_VN': DictDownload('Vietnamese', 'vi', 'vi_VN'),
    'id_ID': DictDownload('Indonesian', 'id', 'id_ID'),
  };

  static Future<bool> downloadDictionary(String code) async {
    final entry = downloadManifest[code];
    if (entry == null) return false;

    final dir = Directory(dictsDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    const baseUrl = 'https://raw.githubusercontent.com/LibreOffice/dictionaries/master';
    final dicUrl = '$baseUrl/${entry.repoDir}/${entry.fileName}.dic';
    final affUrl = '$baseUrl/${entry.repoDir}/${entry.fileName}.aff';

    final client = HttpClient();
    try {
      for (final (url, ext) in [(dicUrl, '.dic'), (affUrl, '.aff')]) {
        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close();
        if (response.statusCode != 200) {
          if (ext == '.dic') return false;
          continue;
        }
        final bytes = await response.fold<List<int>>(
          <int>[],
          (prev, chunk) => prev..addAll(chunk),
        );
        await File('${dir.path}/$code$ext').writeAsBytes(bytes);
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  static Future<bool> deleteDictionary(String code) async {
    final dir = dictsDir;
    var deleted = false;
    for (final ext in ['.dic', '.aff']) {
      final f = File('$dir/$code$ext');
      if (await f.exists()) {
        await f.delete();
        deleted = true;
      }
    }
    return deleted;
  }

  static bool isDictionaryDownloaded(String code) {
    return File('$dictsDir/$code.dic').existsSync();
  }

  static List<String> listDownloadedDictCodes() {
    final dir = Directory(dictsDir);
    if (!dir.existsSync()) return [];
    return dir
        .listSync()
        .where((f) => f.path.endsWith('.dic'))
        .map((f) => f.path.split('/').last.replaceAll('.dic', ''))
        .toList();
  }
}

class DictDownload {
  final String label;
  final String repoDir;
  final String fileName;
  const DictDownload(this.label, this.repoDir, this.fileName);
}

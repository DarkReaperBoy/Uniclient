import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../utils/debug.dart';

/// A single support-template question entry.
/// Port of `Support::details::TemplatesQuestion` (support_templates.h:21-26).
class TemplatesQuestion {
  final String question;
  final List<String> originalKeys;
  final List<String> normalizedKeys;
  final String value;

  const TemplatesQuestion({
    required this.question,
    required this.originalKeys,
    required this.normalizedKeys,
    required this.value,
  });
}

/// One parsed `tl_*.txt` template file.
/// Port of `Support::details::TemplatesFile` (support_templates.h:28-31).
class TemplatesFile {
  final String url;

  /// Keyed by normalized question text (== AyuGram's `std::map<QString, …>`).
  final Map<String, TemplatesQuestion> questions;

  const TemplatesFile({required this.url, required this.questions});
}

/// Result of a key lookup. Port of `Templates::QuestionByKey`
/// (support_templates.h:60-63).
class TemplatesMatch {
  final TemplatesQuestion question;
  final String key;

  const TemplatesMatch(this.question, this.key);
}

/// Faithful Dart port of AyuGram / Telegram Desktop `Support::Templates`
/// (`support/support_templates.{h,cpp}`).
///
/// Reads `tl_*.txt` files from the `TEMPLATES` sub-folder of the app working
/// directory, parses the `{QUESTION}` / `{KEYS}` / `{VALUE}` / `{URL}` format
/// (port of `ReadByLine` + `ReadFromBlob`, support_templates.cpp:69-176) and
/// exposes key-match lookups (`matchExact` / `matchFromEnd`,
/// support_templates.cpp:613-659).
///
/// [reload] re-reads every file from disk and returns the list of parse / IO
/// errors (empty == success) — the engine for the `SupportReloadTemplates`
/// shortcut (port of `Templates::reload()`, support_templates.cpp:464). The
/// caller surfaces the result as a toast, exactly like `Ui::Toast::Show`.
class SupportTemplates {
  SupportTemplates._();
  static final SupportTemplates instance = SupportTemplates._();

  /// App working directory (== AyuGram `cWorkingDir()`). The template folder is
  /// `<workingDir>/TEMPLATES`. Set once at startup from `main.dart`.
  String _workingDir = '';

  /// path (file name) -> parsed file. Port of `TemplatesData::files`.
  final Map<String, TemplatesFile> _files = {};

  int _maxKeyLength = 0;

  /// Guards against overlapping reloads (== `_reading` binary guard +
  /// `_reloadAfterRead`, support_templates.cpp:475-481).
  bool _reading = false;
  bool _reloadAfterRead = false;

  void setWorkingDir(String dir) => _workingDir = dir;

  int get maxKeyLength => _maxKeyLength;
  int get fileCount => _files.length;
  int get questionCount =>
      _files.values.fold(0, (sum, f) => sum + f.questions.length);

  static final RegExp _tokenRe = RegExp(r'^\{([A-Z_]+)\}$');
  static final RegExp _letterOrNumber = RegExp(r'^[\p{L}\p{N}]$', unicode: true);

  /// Re-read all template files from disk and return the parse / IO errors
  /// (empty == success). Port of `Templates::reload()` + `Templates::load()`
  /// (support_templates.cpp:464-502). If a load is already running, defers and
  /// re-runs afterwards (mirrors `_reloadAfterRead`).
  Future<List<String>> reload() async {
    if (_reading) {
      _reloadAfterRead = true;
      return const [];
    }
    _reading = true;
    try {
      List<String> errors;
      do {
        _reloadAfterRead = false;
        errors = await _load();
      } while (_reloadAfterRead);
      return errors;
    } finally {
      _reading = false;
    }
  }

  Future<List<String>> _load() async {
    if (kIsWeb || _workingDir.isEmpty) return const [];

    final dir = Directory('$_workingDir/TEMPLATES');
    final errors = <String>[];
    final files = <String, TemplatesFile>{};

    if (!await dir.exists()) {
      // No TEMPLATES folder == nothing to load (not an error — matches
      // `ReadFiles` returning an empty result for a missing directory).
      _files.clear();
      _maxKeyLength = 0;
      return errors;
    }

    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        if (!_isTemplatesFile(name)) continue;
        try {
          final blob = await entity.readAsBytes();
          final result = _readFromBlob(blob);
          files[name] = result.file;
          errors.addAll(result.errors);
        } catch (_) {
          // == "Couldn't open '%1' for reading!" (support_templates.cpp:182).
          errors.add("Couldn't open '$name' for reading!");
        }
      }
    } catch (e) {
      Debug.log('support_templates', 'failed to list $dir: $e');
      errors.add("Couldn't read templates folder: $e");
    }

    _files
      ..clear()
      ..addAll(files);
    _maxKeyLength = _countMaxKeyLength();
    return errors;
  }

  /// Exact key match. Port of `Templates::matchExact`
  /// (support_templates.cpp:613-631).
  TemplatesMatch? matchExact(String query) {
    if (query.isEmpty || query.length > _maxKeyLength) return null;
    final normalized = _normalizeKey(query);
    for (final file in _files.values) {
      for (final question in file.questions.values) {
        for (final key in question.normalizedKeys) {
          if (key == normalized) return TemplatesMatch(question, key);
        }
      }
    }
    return null;
  }

  /// Longest key that matches the end of [query]. Port of
  /// `Templates::matchFromEnd` (support_templates.cpp:633-659).
  TemplatesMatch? matchFromEnd(String query) {
    if (query.length > _maxKeyLength) {
      query = query.substring(query.length - _maxKeyLength);
    }
    final size = query.length;
    // queries[i] == NormalizeKey of the last (i+1) characters of `query`.
    final queries = <String>[];
    for (var i = 0; i != size; ++i) {
      queries.add(_normalizeKey(query.substring(size - i - 1)));
    }

    TemplatesMatch? result;
    for (final file in _files.values) {
      for (final question in file.questions.values) {
        for (final key in question.normalizedKeys) {
          if (key.isNotEmpty &&
              key.length <= queries.length &&
              queries[key.length - 1] == key &&
              (result == null || result.key.length <= key.length)) {
            result = TemplatesMatch(question, key);
          }
        }
      }
    }
    return result;
  }

  // ── parsing (support_templates.cpp:69-176) ──────────────────────────────

  bool _isTemplatesFile(String file) {
    final lower = file.toLowerCase();
    return lower.startsWith('tl_') && lower.endsWith('.txt');
  }

  /// Strip everything but letters/numbers, lower-cased. Port of
  /// `NormalizeQuestion` (support_templates.cpp:41-50).
  String _normalizeQuestion(String question) {
    final sb = StringBuffer();
    for (final rune in question.runes) {
      final ch = String.fromCharCode(rune);
      if (_letterOrNumber.hasMatch(ch)) sb.write(ch.toLowerCase());
    }
    return sb.toString();
  }

  /// Trim + lower-case a key. Port of `NormalizeKey`
  /// (support_templates.cpp:52-54); `RemoveAccents` is approximated by
  /// lower-casing (sufficient for the ASCII keys templates use in practice).
  String _normalizeKey(String query) => query.trim().toLowerCase();

  int _countMaxKeyLength() {
    var result = 0;
    for (final file in _files.values) {
      for (final question in file.questions.values) {
        for (final key in question.normalizedKeys) {
          if (key.length > result) result = key.length;
        }
      }
    }
    return result;
  }

  _FileResult _readFromBlob(List<int> blob) {
    final questions = <String, TemplatesQuestion>{};
    final errors = <String>[];
    var url = '';

    // Accumulator for the question currently being read.
    var qQuestion = '';
    final qOriginalKeys = <String>[];
    final qNormalizedKeys = <String>[];
    var qValue = '';

    void emit() {
      // Chop trailing newlines off the value (support_templates.cpp:123-125).
      while (qValue.endsWith('\n')) {
        qValue = qValue.substring(0, qValue.length - 1);
      }
      final normalized = _normalizeQuestion(qQuestion);
      if (normalized.isNotEmpty) {
        // `emplace` (support_templates.cpp:172) keeps the first entry on a
        // duplicate normalized question, so insert only if absent.
        questions.putIfAbsent(
          normalized,
          () => TemplatesQuestion(
            question: qQuestion,
            originalKeys: List.of(qOriginalKeys),
            normalizedKeys: List.of(qNormalizedKeys),
            value: qValue,
          ),
        );
      }
      // base::take — reset the accumulator for the next entry.
      qQuestion = '';
      qOriginalKeys.clear();
      qNormalizedKeys.clear();
      qValue = '';
    }

    var state = _ReadState.none;
    var hadKeys = false;
    var hadValue = false;

    final text = const Utf8Decoder(allowMalformed: true).convert(blob);
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      final match = _tokenRe.firstMatch(line);
      if (match != null) {
        final token = match.group(1)!;
        // Reset the had-flags when leaving a value section, BEFORE computing
        // the next state (support_templates.cpp:85-87).
        if (state == _ReadState.value) {
          hadKeys = hadValue = false;
        }
        final newState = switch (token) {
          'VALUE' => hadValue ? _ReadState.none : _ReadState.value,
          'KEYS' => hadKeys ? _ReadState.none : _ReadState.keys,
          'QUESTION' => _ReadState.question,
          'URL' => _ReadState.url,
          _ => _ReadState.none,
        };
        // stateChange(was, now): emit the finished question when leaving Value
        // (ReadByLineGetUrl, support_templates.cpp:128-131).
        if (state == _ReadState.value) emit();
        state = newState;
        // The marker line itself is never accumulated (stateChangeLine).
      } else {
        if (line.isNotEmpty) {
          if (state == _ReadState.value) {
            hadValue = true;
          } else if (state == _ReadState.keys) {
            hadKeys = true;
          }
        }
        switch (state) {
          case _ReadState.keys:
            if (line.isNotEmpty) {
              qOriginalKeys.add(line);
              final norm = _normalizeKey(line);
              if (norm.isNotEmpty) qNormalizedKeys.add(norm);
            }
            break;
          case _ReadState.value:
            if (qValue.isNotEmpty) qValue += '\n';
            qValue += line;
            break;
          case _ReadState.question:
            if (qQuestion.isEmpty) qQuestion = line;
            break;
          case _ReadState.url:
            if (url.isEmpty) url = line;
            break;
          case _ReadState.none:
            break;
        }
      }
    }
    emit(); // final call() (support_templates.cpp:163).

    return _FileResult(TemplatesFile(url: url, questions: questions), errors);
  }
}

/// Parser state. Port of `Support::details::ReadState`
/// (support_templates.cpp:61-67).
enum _ReadState { none, question, keys, value, url }

class _FileResult {
  final TemplatesFile file;
  final List<String> errors;
  const _FileResult(this.file, this.errors);
}

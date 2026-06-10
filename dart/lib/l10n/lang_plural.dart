// CLDR plural-rule selection for the cloud language pack.
//
// 1:1 port of AyuGram/Telegram Desktop `lang/lang_tag.cpp` (the `ChoosePlural*`
// rule functions + `GeneratePluralRulesMap()` + `UpdatePluralRules()` lookup).
// Telegram's cloud pack ships one value per CLDR plural category
// (zero/one/two/few/many/other); `trCount` uses [pluralForm] to pick the right
// category for a given count in the active language, exactly as AyuGram resolves
// `tr::lng_days(lt_count, n)` via `Lang::Plural()` → `ChoosePlural`.
//
// Reference: http://www.unicode.org/cldr/charts/latest/supplemental/language_plural_rules.html
//
// `n` absolute value of the source number (integer and decimals).
// `i` integer digits of n.
// `v` number of visible fraction digits in n, with trailing zeros.
// `w` number of visible fraction digits in n, without trailing zeros.
// `f` visible fractional digits in n, with trailing zeros.
// `t` visible fractional digits in n, without trailing zeros.
//
// `n` is -1 for non-integer numbers and n == i for integer numbers; it is fine
// while the rules only compare n to integers. [pluralForm] is integer-only (the
// callers pass an `int count`), so n == i and v == w == f == t == 0 — the
// fractional branches are ported verbatim but never trigger here.
library;

// Plural-category shifts, matching lang_tag.cpp kShift* (the index into the
// per-category cloud values).
const int _shiftZero = 0;
const int _shiftOne = 1;
const int _shiftTwo = 2;
const int _shiftFew = 3;
const int _shiftMany = 4;
const int _shiftOther = 5;

/// Category name for each shift, indexed by the `_shift*` constants. Mirrors the
/// `key#form` suffix the Go bridge emits for `langPackStringPluralized`.
const List<String> _formForShift = [
  'zero',
  'one',
  'two',
  'few',
  'many',
  'other',
];

typedef _ChoosePlural = int Function(int n, int i, int v, int w, int f, int t);

// --- ChoosePlural* rule functions (lang_tag.cpp:48-495) ----------------------

int _choosePlural1(int n, int i, int v, int w, int f, int t) {
  return _shiftOther;
}

int _choosePlural2fil(int n, int i, int v, int w, int f, int t) {
  if (v == 0) {
    final mod10 = i % 10;
    if (i == 1 || i == 2 || i == 3) {
      return _shiftOne;
    } else if (mod10 != 4 && mod10 != 6 && mod10 != 9) {
      return _shiftOne;
    }
    return _shiftOther;
  }
  final mod10 = f % 10;
  if (mod10 != 4 && mod10 != 6 && mod10 != 9) {
    return _shiftOne;
  }
  return _shiftOther;
}

int _choosePlural2tzm(int n, int i, int v, int w, int f, int t) {
  if (n == 0 || n == 1) {
    return _shiftOne;
  } else if (n >= 11 && n <= 99) {
    return _shiftOne;
  }
  return _shiftOther;
}

int _choosePlural2is(int n, int i, int v, int w, int f, int t) {
  if (t == 0) {
    final mod10 = i % 10;
    final mod100 = i % 100;
    if (mod10 == 1 && mod100 != 11) {
      return _shiftOne;
    }
    return _shiftOther;
  }
  return _shiftOne;
}

int _choosePlural2mk(int n, int i, int v, int w, int f, int t) {
  if (v == 0) {
    final mod10 = i % 10;
    final mod100 = i % 100;
    if (mod10 == 1 && mod100 != 11) {
      return _shiftOne;
    }
  }
  final mod10 = f % 10;
  final mod100 = f % 100;
  if (mod10 == 1 && mod100 != 11) {
    return _shiftOne;
  }
  return _shiftOther;
}

int _choosePlural2ak(int n, int i, int v, int w, int f, int t) {
  if (n == 0 || n == 1) {
    return _shiftOne;
  }
  return _shiftOther;
}

int _choosePlural2am(int n, int i, int v, int w, int f, int t) {
  if (i == 0 || n == 1) {
    return _shiftOne;
  }
  return _shiftOther;
}

int _choosePlural2hy(int n, int i, int v, int w, int f, int t) {
  if (i == 0 || i == 1) {
    return _shiftOne;
  }
  return _shiftOther;
}

int _choosePlural2si(int n, int i, int v, int w, int f, int t) {
  if (n == 0 || n == 1) {
    return _shiftOne;
  } else if (i == 0 && f == 1) {
    return _shiftOne;
  }
  return _shiftOther;
}

int _choosePlural2bh(int n, int i, int v, int w, int f, int t) {
  // not documented
  if (n == 0 || n == 1) {
    return _shiftOne;
  }
  return _shiftOther;
}

int _choosePlural2af(int n, int i, int v, int w, int f, int t) {
  if (n == 1) {
    return _shiftOne;
  }
  return _shiftOther;
}

int _choosePlural2ast(int n, int i, int v, int w, int f, int t) {
  if (i == 1 && v == 0) {
    return _shiftOne;
  }
  return _shiftOther;
}

int _choosePlural2da(int n, int i, int v, int w, int f, int t) {
  if (n == 1) {
    return _shiftOne;
  } else if (t != 0 && (i == 0 || i == 1)) {
    return _shiftOne;
  }
  return _shiftOther;
}

int _choosePlural3lv(int n, int i, int v, int w, int f, int t) {
  final nmod10 = n % 10;
  final nmod100 = n % 100;
  final fmod10 = f % 10;
  final fmod100 = f % 100;
  if (nmod10 == 0) {
    return _shiftZero;
  } else if (nmod100 >= 11 && nmod100 <= 19) {
    return _shiftZero;
  } else if (v == 2 && fmod100 >= 11 && fmod100 <= 19) {
    return _shiftZero;
  } else if (nmod10 == 1 && nmod100 != 11) {
    return _shiftOne;
  } else if (v == 2 && fmod10 == 1 && fmod100 != 11) {
    return _shiftOne;
  } else if (v != 2 && fmod10 == 1) {
    return _shiftOne;
  }
  return _shiftOther;
}

int _choosePlural3ksh(int n, int i, int v, int w, int f, int t) {
  if (n == 0) {
    return _shiftZero;
  } else if (n == 1) {
    return _shiftOne;
  }
  return _shiftOther;
}

int _choosePlural3lag(int n, int i, int v, int w, int f, int t) {
  if (n == 0) {
    return _shiftZero;
  } else if (n != 0 && (i == 0 || i == 1)) {
    return _shiftOne;
  }
  return _shiftOther;
}

int _choosePlural3kw(int n, int i, int v, int w, int f, int t) {
  if (n == 1) {
    return _shiftOne;
  } else if (n == 2) {
    return _shiftTwo;
  }
  return _shiftOther;
}

int _choosePlural3bs(int n, int i, int v, int w, int f, int t) {
  if (v == 0) {
    final mod10 = i % 10;
    final mod100 = i % 100;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return _shiftFew;
    } else if (mod10 == 1 && mod100 != 11) {
      return _shiftOne;
    }
    return _shiftOther;
  }
  final mod10 = f % 10;
  final mod100 = f % 100;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return _shiftFew;
  } else if (mod10 == 1 && mod100 != 11) {
    return _shiftOne;
  }
  return _shiftOther;
}

int _choosePlural3shi(int n, int i, int v, int w, int f, int t) {
  if (i == 0 || n == 1) {
    return _shiftOne;
  } else if (n >= 2 && n <= 10) {
    return _shiftFew;
  }
  return _shiftOther;
}

int _choosePlural3mo(int n, int i, int v, int w, int f, int t) {
  if (v == 0) {
    final mod100 = n % 100;
    if (i == 1) {
      return _shiftOne;
    } else if (n == 0) {
      return _shiftFew;
    } else if (n != 1 && mod100 >= 1 && mod100 <= 19) {
      return _shiftFew;
    }
    return _shiftOther;
  }
  return _shiftFew;
}

int _choosePlural4be(int n, int i, int v, int w, int f, int t) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    return _shiftFew;
  } else if (mod10 == 1 && mod100 != 11) {
    return _shiftOne;
  } else if (mod10 == 0) {
    return _shiftMany;
  } else if (mod10 >= 5 && mod10 <= 9) {
    return _shiftMany;
  } else if (mod100 >= 11 && mod100 <= 14) {
    return _shiftMany;
  }
  return _shiftOther;
}

int _choosePlural4ru(int n, int i, int v, int w, int f, int t) {
  if (v == 0) {
    final mod10 = i % 10;
    final mod100 = i % 100;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return _shiftFew;
    } else if (mod10 == 1 && mod100 != 11) {
      return _shiftOne;
    }
    return _shiftMany;
  }
  return _shiftOther;
}

int _choosePlural4pl(int n, int i, int v, int w, int f, int t) {
  if (v == 0) {
    if (i == 1) {
      return _shiftOne;
    }
    final mod10 = i % 10;
    final mod100 = i % 100;
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return _shiftFew;
    } else {
      return _shiftMany;
    }
  }
  return _shiftOther;
}

int _choosePlural4lt(int n, int i, int v, int w, int f, int t) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 >= 2 && mod10 <= 9 && (mod100 < 11 || mod100 > 19)) {
    return _shiftFew;
  } else if (mod10 == 1 && mod100 != 11) {
    return _shiftOne;
  } else if (f != 0) {
    return _shiftMany;
  }
  return _shiftOther;
}

int _choosePlural4cs(int n, int i, int v, int w, int f, int t) {
  if (v == 0) {
    if (i == 1) {
      return _shiftOne;
    } else if (i >= 2 && i <= 4) {
      return _shiftFew;
    }
    return _shiftOther;
  }
  return _shiftMany;
}

int _choosePlural4gd(int n, int i, int v, int w, int f, int t) {
  if (n == 1 || n == 11) {
    return _shiftOne;
  } else if (n == 2 || n == 12) {
    return _shiftTwo;
  } else if (n >= 3 && n <= 10) {
    return _shiftFew;
  } else if (n >= 13 && n <= 19) {
    return _shiftFew;
  }
  return _shiftOther;
}

int _choosePlural4dsb(int n, int i, int v, int w, int f, int t) {
  if (v == 0) {
    final imod100 = i % 100;
    if (imod100 == 1) {
      return _shiftOne;
    } else if (imod100 == 2) {
      return _shiftTwo;
    } else if (imod100 == 3 || imod100 == 4) {
      return _shiftFew;
    }
  }
  final fmod100 = f % 100;
  if (fmod100 == 1) {
    return _shiftOne;
  } else if (fmod100 == 2) {
    return _shiftTwo;
  } else if (fmod100 == 3 || fmod100 == 4) {
    return _shiftFew;
  }
  return _shiftOther;
}

int _choosePlural4sl(int n, int i, int v, int w, int f, int t) {
  if (v == 0) {
    final imod100 = i % 100;
    if (imod100 == 3 || imod100 == 4) {
      return _shiftFew;
    } else if (imod100 == 1) {
      return _shiftOne;
    } else if (imod100 == 2) {
      return _shiftTwo;
    }
    return _shiftOther;
  }
  return _shiftFew;
}

int _choosePlural4he(int n, int i, int v, int w, int f, int t) {
  if (v == 0) {
    if (i == 1) {
      return _shiftOne;
    } else if (i == 2) {
      return _shiftTwo;
    } else if (n != 0 && n != 10 && (n % 10) == 0) {
      return _shiftMany;
    }
    return _shiftOther;
  }
  return _shiftOther;
}

int _choosePlural4mt(int n, int i, int v, int w, int f, int t) {
  final mod100 = n % 100;
  if (n == 1) {
    return _shiftOne;
  } else if (n == 0) {
    return _shiftFew;
  } else if (mod100 >= 2 && mod100 <= 10) {
    return _shiftFew;
  } else if (mod100 >= 11 && mod100 <= 19) {
    return _shiftMany;
  }
  return _shiftOther;
}

int _choosePlural5gv(int n, int i, int v, int w, int f, int t) {
  if (v == 0) {
    final mod10 = i % 10;
    final mod20 = i % 20;
    if (mod10 == 1) {
      return _shiftOne;
    } else if (mod10 == 2) {
      return _shiftTwo;
    } else if (mod20 == 0) {
      return _shiftFew;
    }
    return _shiftOther;
  }
  return _shiftMany;
}

int _choosePlural5br(int n, int i, int v, int w, int f, int t) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11 && mod100 != 71 && mod100 != 91) {
    return _shiftOne;
  } else if (mod10 == 2 && mod100 != 12 && mod100 != 72 && mod100 != 92) {
    return _shiftTwo;
  } else if ((mod10 == 3 || mod10 == 4 || mod10 == 9) &&
      (mod100 < 10 || mod100 > 19) &&
      (mod100 < 70 || mod100 > 79) &&
      (mod100 < 90 || mod100 > 99)) {
    return _shiftFew;
  } else if (n != 0 && (n % 1000000) == 0) {
    return _shiftMany;
  }
  return _shiftOther;
}

int _choosePlural5ga(int n, int i, int v, int w, int f, int t) {
  if (n == 1) {
    return _shiftOne;
  } else if (n == 2) {
    return _shiftTwo;
  } else if (n >= 3 && n <= 6) {
    return _shiftFew;
  } else if (n >= 7 && n <= 10) {
    return _shiftMany;
  }
  return _shiftOther;
}

int _choosePlural6ar(int n, int i, int v, int w, int f, int t) {
  if (n == 0) {
    return _shiftZero;
  } else if (n == 1) {
    return _shiftOne;
  } else if (n == 2) {
    return _shiftTwo;
  } else if (n < 0) {
    return _shiftOther;
  }
  final mod100 = n % 100;
  if (mod100 >= 3 && mod100 <= 10) {
    return _shiftFew;
  } else if (mod100 >= 11 && mod100 <= 99) {
    return _shiftMany;
  }
  return _shiftOther;
}

int _choosePlural6cy(int n, int i, int v, int w, int f, int t) {
  if (n == 0) {
    return _shiftZero;
  } else if (n == 1) {
    return _shiftOne;
  } else if (n == 2) {
    return _shiftTwo;
  } else if (n == 3) {
    return _shiftFew;
  } else if (n == 6) {
    return _shiftMany;
  }
  return _shiftOther;
}

// --- Language → rule map (lang_tag.cpp:521-734) ------------------------------
//
// Keys are normalized (lowercase, `_`→`-`) to match AyuGram's `PluralsKey`
// (ConvertKeyChar). Languages not listed (bm/my/yue/zh/dz/ig/id/ja/jv/ko/th/
// vi/… — the commented-out `ChoosePlural1` block) fall through to the
// other-only [_choosePlural1] default in [_lookupRule].
final Map<String, _ChoosePlural> _pluralRules = {
  'fil': _choosePlural2fil,
  'tl': _choosePlural2fil,
  'tzm': _choosePlural2tzm,
  'is': _choosePlural2is,
  'mk': _choosePlural2mk,
  'ak': _choosePlural2ak,
  'guw': _choosePlural2ak,
  'ln': _choosePlural2ak,
  'mg': _choosePlural2ak,
  'nso': _choosePlural2ak,
  'pa': _choosePlural2ak,
  'ti': _choosePlural2ak,
  'wa': _choosePlural2ak,
  'am': _choosePlural2am,
  'as': _choosePlural2am,
  'bn': _choosePlural2am,
  'gu': _choosePlural2am,
  'hi': _choosePlural2am,
  'kn': _choosePlural2am,
  'mr': _choosePlural2am,
  'fa': _choosePlural2am,
  'zu': _choosePlural2am,
  'hy': _choosePlural2hy,
  'fr': _choosePlural2hy,
  'ff': _choosePlural2hy,
  'kab': _choosePlural2hy,
  'pt': _choosePlural2hy,
  'si': _choosePlural2si,
  'bh': _choosePlural2bh,
  'bho': _choosePlural2bh,
  'af': _choosePlural2af,
  'sq': _choosePlural2af,
  'asa': _choosePlural2af,
  'az': _choosePlural2af,
  'eu': _choosePlural2af,
  'bem': _choosePlural2af,
  'bez': _choosePlural2af,
  'brx': _choosePlural2af,
  'bg': _choosePlural2af,
  'ckb': _choosePlural2af,
  'ce': _choosePlural2af,
  'chr': _choosePlural2af,
  'cgg': _choosePlural2af,
  'dv': _choosePlural2af,
  'eo': _choosePlural2af,
  'ee': _choosePlural2af,
  'fo': _choosePlural2af,
  'fur': _choosePlural2af,
  'ka': _choosePlural2af,
  'el': _choosePlural2af,
  'ha': _choosePlural2af,
  'haw': _choosePlural2af,
  'hu': _choosePlural2af,
  'kaj': _choosePlural2af,
  'kkj': _choosePlural2af,
  'kl': _choosePlural2af,
  'ks': _choosePlural2af,
  'kk': _choosePlural2af,
  'ku': _choosePlural2af,
  'ky': _choosePlural2af,
  'lb': _choosePlural2af,
  'jmc': _choosePlural2af,
  'ml': _choosePlural2af,
  'mas': _choosePlural2af,
  'mgo': _choosePlural2af,
  'mn': _choosePlural2af,
  'nah': _choosePlural2af,
  'ne': _choosePlural2af,
  'nnh': _choosePlural2af,
  'jgo': _choosePlural2af,
  'nd': _choosePlural2af,
  'no': _choosePlural2af,
  'nb': _choosePlural2af,
  'nn': _choosePlural2af,
  'ny': _choosePlural2af,
  'nyn': _choosePlural2af,
  'or': _choosePlural2af,
  'om': _choosePlural2af,
  'os': _choosePlural2af,
  'pap': _choosePlural2af,
  'ps': _choosePlural2af,
  'rm': _choosePlural2af,
  'rof': _choosePlural2af,
  'rwk': _choosePlural2af,
  'ssy': _choosePlural2af,
  'saq': _choosePlural2af,
  'seh': _choosePlural2af,
  'ksb': _choosePlural2af,
  'sn': _choosePlural2af,
  'sd': _choosePlural2af,
  'xog': _choosePlural2af,
  'so': _choosePlural2af,
  'nr': _choosePlural2af,
  'sdh': _choosePlural2af,
  'st': _choosePlural2af,
  'es': _choosePlural2af,
  'ss': _choosePlural2af,
  'gsw': _choosePlural2af,
  'syr': _choosePlural2af,
  'ta': _choosePlural2af,
  'te': _choosePlural2af,
  'teo': _choosePlural2af,
  'tig': _choosePlural2af,
  'ts': _choosePlural2af,
  'tn': _choosePlural2af,
  'tr': _choosePlural2af,
  'tk': _choosePlural2af,
  'kcg': _choosePlural2af,
  'ug': _choosePlural2af,
  'uz': _choosePlural2af,
  've': _choosePlural2af,
  'vo': _choosePlural2af,
  'vun': _choosePlural2af,
  'wae': _choosePlural2af,
  'xh': _choosePlural2af,
  '': _choosePlural2ast,
  'ast': _choosePlural2ast,
  'ca': _choosePlural2ast,
  'nl': _choosePlural2ast,
  'en': _choosePlural2ast,
  'et': _choosePlural2ast,
  'pt-pt': _choosePlural2ast,
  'fi': _choosePlural2ast,
  'gl': _choosePlural2ast,
  'lg': _choosePlural2ast,
  'de': _choosePlural2ast,
  'io': _choosePlural2ast,
  'ia': _choosePlural2ast,
  'it': _choosePlural2ast,
  'sc': _choosePlural2ast,
  'scn': _choosePlural2ast,
  'sw': _choosePlural2ast,
  'sv': _choosePlural2ast,
  'ur': _choosePlural2ast,
  'fy': _choosePlural2ast,
  'ji': _choosePlural2ast,
  'yi': _choosePlural2ast,
  'da': _choosePlural2da,
  'lv': _choosePlural3lv,
  'prg': _choosePlural3lv,
  'ksh': _choosePlural3ksh,
  'lag': _choosePlural3lag,
  'kw': _choosePlural3kw,
  'smn': _choosePlural3kw,
  'iu': _choosePlural3kw,
  'smj': _choosePlural3kw,
  'naq': _choosePlural3kw,
  'se': _choosePlural3kw,
  'smi': _choosePlural3kw,
  'sms': _choosePlural3kw,
  'sma': _choosePlural3kw,
  'bs': _choosePlural3bs,
  'hr': _choosePlural3bs,
  'sr': _choosePlural3bs,
  'sh': _choosePlural3bs,
  'sr-latn': _choosePlural3bs,
  'shi': _choosePlural3shi,
  'mo': _choosePlural3mo,
  'ro-md': _choosePlural3mo,
  'ro': _choosePlural3mo,
  'be': _choosePlural4be,
  'ru': _choosePlural4ru,
  'uk': _choosePlural4ru,
  'pl': _choosePlural4pl,
  'lt': _choosePlural4lt,
  'cs': _choosePlural4cs,
  'sk': _choosePlural4cs,
  'gd': _choosePlural4gd,
  'dsb': _choosePlural4dsb,
  'hsb': _choosePlural4dsb,
  'sl': _choosePlural4sl,
  'he': _choosePlural4he,
  'iw': _choosePlural4he,
  'mt': _choosePlural4mt,
  'gv': _choosePlural5gv,
  'br': _choosePlural5br,
  'ga': _choosePlural5ga,
  'ar': _choosePlural6ar,
  'ars': _choosePlural6ar,
  'cy': _choosePlural6cy,
};

/// Resolve the rule for [langCode], mirroring AyuGram `UpdatePluralRules`:
/// try the full normalized code, then the parent (the part before the first
/// `-`), then fall back to the other-only [_choosePlural1].
_ChoosePlural _lookupRule(String langCode) {
  final key = langCode.toLowerCase().replaceAll('_', '-');
  final dash = key.indexOf('-');
  final parent = dash > 0 ? key.substring(0, dash) : '';
  final full = _pluralRules[key];
  if (full != null || parent.isEmpty) {
    return full ?? _choosePlural1;
  }
  return _pluralRules[parent] ?? _choosePlural1;
}

/// The CLDR plural category ('zero'/'one'/'two'/'few'/'many'/'other') for
/// [count] in [langCode]. Integer-only entry point (n == i == count, no
/// fraction), matching the cloud-value path of AyuGram `Lang::Plural()` for an
/// integer `lt_count` argument.
String pluralForm(String langCode, int count) {
  final n = count.abs();
  final shift = _lookupRule(langCode)(n, n, 0, 0, 0, 0);
  return _formForShift[shift];
}

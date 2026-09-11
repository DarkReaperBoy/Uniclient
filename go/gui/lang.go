package gui

// Localization core (slice 140): pack-keyed string lookup with an
// embedded English fallback — tdesktop semantics (missing keys fall back
// to the base language, never blanks). The override map is loaded from
// the account's cloud lang pack (engine.GetLangStrings over
// langpack.getStrings, tdesktop keys verified against the upstream
// lang.strings 2026-09-11) and replaced wholesale on language change
// (copy-on-write: the frame snapshot may keep the old reference).

import (
	"strings"

	"uniclient/engine"
)

// langTr returns the string for a tdesktop lang key: the loaded override
// when present and non-empty, else the embedded English fallback. Pure.
func langTr(override map[string]string, key, fallback string) string {
	if v, ok := override[key]; ok && v != "" {
		return v
	}
	return fallback
}

// langKeysForSettings is the fixed key set this GUI surface consumes —
// the exact keys requested from the cloud pack. Keys verified against
// telegramdesktop/tdesktop Telegram/Resources/langs/lang.strings.
func langKeysForSettings() []string {
	return []string{
		// settings rail + sections
		"lng_settings_section_info",
		"lng_settings_section_notify",
		"lng_settings_section_privacy",
		"lng_settings_data_storage",
		"lng_settings_calls",
		"lng_settings_language",
		"lng_menu_about",
		"lng_settings_section_filters",
		// language box
		"lng_languages",
		"lng_languages_none",
		"lng_language_name",
		// common controls
		"lng_cancel",
		"lng_close",
		"lng_box_ok",
		"lng_box_done",
		"lng_continue",
		// settings rows
		"lng_settings_add_account_about",
		"lng_menu_add_account",
		"lng_settings_information",
	}
}

// settingsRailLabels renders the settings rail labels through the pack.
// Indices match settingsSections. Pure.
func settingsRailLabels(override map[string]string) []string {
	keys := [...]int{
		setSectionMain, setSectionNotifications, setSectionPrivacy, setSectionData,
		setSectionAppearance, setSectionCalls, setSectionLanguage, setSectionAyu,
		setSectionAbout,
	}
	out := make([]string, len(settingsSections))
	for i, sec := range keys {
		out[i] = settingsRailLabel(override, sec)
	}
	return out
}

// settingsRailLabel renders one rail label through the pack. Pure.
func settingsRailLabel(override map[string]string, sec int) string {
	switch sec {
	case setSectionMain:
		return langTr(override, "lng_settings_section_info", "Main")
	case setSectionNotifications:
		return langTr(override, "lng_settings_section_notify", "Notifications")
	case setSectionPrivacy:
		return langTr(override, "lng_settings_section_privacy", "Privacy & Security")
	case setSectionData:
		return langTr(override, "lng_settings_data_storage", "Data & Storage")
	case setSectionAppearance:
		return "Appearance" // no dedicated upstream key; base label
	case setSectionCalls:
		return langTr(override, "lng_settings_calls", "Calls")
	case setSectionLanguage:
		return langTr(override, "lng_settings_language", "Language")
	case setSectionAyu:
		return "Ayu" // AyuGram-specific; base label
	case setSectionAbout:
		return langTr(override, "lng_menu_about", "About")
	}
	return ""
}

// languageRowLabel renders one language row: native name leads (tdesktop
// behavior), the English name + code as the sub line. Pure.
func languageRowLabel(l engine.LanguageInfo) (title, sub string) {
	title = l.NativeName
	if title == "" {
		title = l.Name
	}
	sub = l.Name
	if l.LangCode != "" {
		if sub != "" {
			sub += " · " + l.LangCode
		} else {
			sub = l.LangCode
		}
	}
	return title, sub
}

// languageBadges lists the row's badges in display order. Pure.
func languageBadges(l engine.LanguageInfo) []string {
	var badges []string
	if l.Official {
		badges = append(badges, "official")
	}
	if l.Beta {
		badges = append(badges, "beta")
	}
	if l.Rtl {
		badges = append(badges, "RTL")
	}
	return badges
}

// filterLanguages filters by English name, native name or code
// (case-insensitive, trimmed). Pure.
func filterLanguages(langs []engine.LanguageInfo, q string) []engine.LanguageInfo {
	q = strings.ToLower(strings.TrimSpace(q))
	if q == "" {
		return langs
	}
	var out []engine.LanguageInfo
	for _, l := range langs {
		if strings.Contains(strings.ToLower(l.Name), q) ||
			strings.Contains(strings.ToLower(l.NativeName), q) ||
			strings.Contains(strings.ToLower(l.LangCode), q) {
			out = append(out, l)
		}
	}
	return out
}

// languageNameFor renders the current-language card line: the language's
// name when known, the code itself otherwise, English when unset. Pure.
func languageNameFor(langs []engine.LanguageInfo, code string) string {
	if code == "" {
		return "English"
	}
	for _, l := range langs {
		if l.LangCode == code {
			if l.NativeName != "" {
				return l.NativeName
			}
			if l.Name != "" {
				return l.Name
			}
			return l.LangCode
		}
	}
	return code
}

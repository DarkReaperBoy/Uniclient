package gui

import (
	"strings"

	"uniclient/engine"
)

func langTr(override map[string]string, key, fallback string) string {
	if v, ok := override[key]; ok && v != "" {
		return v
	}
	return fallback
}

func langKeysForSettings() []string {
	return []string{
		"lng_settings_section_info",
		"lng_settings_section_notify",
		"lng_settings_section_privacy",
		"lng_settings_data_storage",
		"lng_settings_calls",
		"lng_settings_language",
		"lng_menu_about",
		"lng_settings_section_filters",
		"lng_languages",
		"lng_languages_none",
		"lng_language_name",
		"lng_cancel",
		"lng_close",
		"lng_box_ok",
		"lng_box_done",
		"lng_continue",
		"lng_settings_add_account_about",
		"lng_menu_add_account",
		"lng_settings_information",
	}
}

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
		return "Appearance"
	case setSectionCalls:
		return langTr(override, "lng_settings_calls", "Calls")
	case setSectionLanguage:
		return langTr(override, "lng_settings_language", "Language")
	case setSectionAyu:
		return "Ayu"
	case setSectionAbout:
		return langTr(override, "lng_menu_about", "About")
	}
	return ""
}

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

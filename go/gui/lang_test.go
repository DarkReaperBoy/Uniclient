package gui

// Language switch (slice 140): the localization core — pack-keyed string
// lookup with embedded English fallback (tdesktop semantics: missing keys
// fall back to the base language), the fixed settings-surface key set,
// language row labels/badges and search filter.

import (
	"testing"

	"uniclient/engine"
)

func TestLangTrFallback(t *testing.T) {
	if got := langTr(nil, "lng_cancel", "Cancel"); got != "Cancel" {
		t.Fatalf("nil override = %q, want fallback", got)
	}
	if got := langTr(map[string]string{}, "lng_cancel", "Cancel"); got != "Cancel" {
		t.Fatalf("empty override = %q, want fallback", got)
	}
	// empty pack value falls back (GetLangStrings never emits those, but
	// be robust)
	if got := langTr(map[string]string{"lng_cancel": ""}, "lng_cancel", "Cancel"); got != "Cancel" {
		t.Fatalf("empty value = %q, want fallback", got)
	}
}

func TestLangTrOverride(t *testing.T) {
	ov := map[string]string{
		"lng_cancel":            "Abbrechen",
		"lng_settings_calls":    "Anrufe",
		"lng_settings_language": "Sprache",
	}
	if got := langTr(ov, "lng_cancel", "Cancel"); got != "Abbrechen" {
		t.Fatalf("override = %q", got)
	}
	if got := langTr(ov, "lng_settings_language", "Language"); got != "Sprache" {
		t.Fatalf("override = %q", got)
	}
	// unknown key: fallback untouched
	if got := langTr(ov, "lng_unknown_key", "About"); got != "About" {
		t.Fatalf("unknown key = %q", got)
	}
}

// langKeysForSettings pins the key set requested from the cloud pack —
// the keys this GUI surface actually consumes.
func TestLangKeysForSettings(t *testing.T) {
	keys := langKeysForSettings()
	if len(keys) == 0 {
		t.Fatal("empty key set")
	}
	seen := map[string]bool{}
	for _, k := range keys {
		if k == "" || seen[k] {
			t.Fatalf("bad/duplicate key %q", k)
		}
		seen[k] = true
	}
	// the core settings keys are all present
	for _, want := range []string{
		"lng_settings_section_notify",
		"lng_settings_section_privacy",
		"lng_settings_data_storage",
		"lng_settings_calls",
		"lng_settings_language",
		"lng_menu_about",
		"lng_cancel",
		"lng_close",
		"lng_languages_none",
	} {
		if !seen[want] {
			t.Errorf("key %q missing from the set", want)
		}
	}
}

// settingsRailLabels renders the rail through the pack (fallback English).
func TestSettingsRailLabels(t *testing.T) {
	base := settingsRailLabels(nil)
	if base[setSectionNotifications] != "Notifications" {
		t.Fatalf("fallback notifications = %q", base[setSectionNotifications])
	}
	if base[setSectionLanguage] != "Language" {
		t.Fatalf("fallback language = %q", base[setSectionLanguage])
	}
	ov := map[string]string{
		"lng_settings_section_notify": "Benachrichtigungen",
		"lng_settings_language":       "Sprache",
		"lng_menu_about":              "Über",
	}
	de := settingsRailLabels(ov)
	if de[setSectionNotifications] != "Benachrichtigungen" {
		t.Fatalf("de notifications = %q", de[setSectionNotifications])
	}
	if de[setSectionLanguage] != "Sprache" {
		t.Fatalf("de language = %q", de[setSectionLanguage])
	}
	if de[setSectionAbout] != "Über" {
		t.Fatalf("de about = %q", de[setSectionAbout])
	}
	// no key: stays English
	if de[setSectionMain] != "Main" {
		t.Fatalf("main drifted: %q", de[setSectionMain])
	}
	if len(de) != len(settingsSections) {
		t.Fatalf("label count = %d, want %d", len(de), len(settingsSections))
	}
}

func TestLanguageRowLabel(t *testing.T) {
	l := engine.LanguageInfo{
		LangCode:   "de",
		Name:       "German",
		NativeName: "Deutsch",
	}
	if title, sub := languageRowLabel(l); title != "Deutsch" || sub != "German · de" {
		t.Fatalf("row = %q/%q", title, sub)
	}
	// no native name: name leads
	l.NativeName = ""
	if title, _ := languageRowLabel(l); title != "German" {
		t.Fatalf("no-native title = %q", title)
	}
}

func TestLanguageBadges(t *testing.T) {
	cases := []struct {
		in   engine.LanguageInfo
		want []string
	}{
		{engine.LanguageInfo{}, nil},
		{engine.LanguageInfo{Official: true}, []string{"official"}},
		{engine.LanguageInfo{Beta: true}, []string{"beta"}},
		{engine.LanguageInfo{Rtl: true}, []string{"RTL"}},
		{engine.LanguageInfo{Official: true, Rtl: true}, []string{"official", "RTL"}},
		{engine.LanguageInfo{Official: true, Beta: true, Rtl: true}, []string{"official", "beta", "RTL"}},
	}
	for _, c := range cases {
		got := languageBadges(c.in)
		if len(got) != len(c.want) {
			t.Fatalf("badges(%+v) = %v, want %v", c.in, got, c.want)
		}
		for i := range got {
			if got[i] != c.want[i] {
				t.Fatalf("badges(%+v) = %v, want %v", c.in, got, c.want)
			}
		}
	}
}

func TestFilterLanguages(t *testing.T) {
	langs := []engine.LanguageInfo{
		{LangCode: "de", Name: "German", NativeName: "Deutsch"},
		{LangCode: "fa", Name: "Persian", NativeName: "فارسی"},
		{LangCode: "pt-br", Name: "Portuguese (Brazil)", NativeName: "Português (Brasil)"},
	}
	if got := filterLanguages(langs, "deut"); len(got) != 1 || got[0].LangCode != "de" {
		t.Fatalf("native filter = %+v", got)
	}
	if got := filterLanguages(langs, "PERS"); len(got) != 1 || got[0].LangCode != "fa" {
		t.Fatalf("name filter = %+v", got)
	}
	if got := filterLanguages(langs, "PT-BR"); len(got) != 1 || got[0].LangCode != "pt-br" {
		t.Fatalf("code filter = %+v", got)
	}
	if got := filterLanguages(langs, "  "); len(got) != 3 {
		t.Fatal("blank query filtered")
	}
	if got := filterLanguages(langs, "zzz"); len(got) != 0 {
		t.Fatalf("no-hit filter = %+v", got)
	}
}

// languageNameFor renders the current-language card line.
func TestLanguageNameFor(t *testing.T) {
	langs := []engine.LanguageInfo{{LangCode: "en", Name: "English", NativeName: "English"}}
	if got := languageNameFor(langs, "en"); got != "English" {
		t.Fatalf("en = %q", got)
	}
	if got := languageNameFor(langs, "de"); got != "de" {
		t.Fatalf("unknown = %q, want the code itself", got)
	}
	if got := languageNameFor(nil, ""); got != "English" {
		t.Fatalf("empty = %q", got)
	}
}

package cores

import (
	"testing"

	"github.com/gotd/td/tg"
)

func TestApplyBotInfoFields(t *testing.T) {
	bi := &tg.BotInfo{}
	bi.SetDescription("I translate messages. Just send me text!")
	bi.SetPrivacyPolicyURL("https://example.com/privacy")
	bi.SetMenuButton(&tg.BotMenuButton{Text: "Open app", URL: "https://example.com/app"})
	u := &User{}
	applyBotInfoFields(u, bi)
	if u.BotDescription != "I translate messages. Just send me text!" {
		t.Errorf("BotDescription = %q", u.BotDescription)
	}
	if u.BotPrivacyURL != "https://example.com/privacy" {
		t.Errorf("BotPrivacyURL = %q", u.BotPrivacyURL)
	}
	if u.BotMenuText != "Open app" {
		t.Errorf("BotMenuText = %q", u.BotMenuText)
	}

	u2 := &User{BotDescription: "kept"}
	applyBotInfoFields(u2, &tg.BotInfo{})
	if u2.BotDescription != "kept" {
		t.Errorf("empty info overwrote description: %q", u2.BotDescription)
	}
	if u2.BotPrivacyURL != "" || u2.BotMenuText != "" {
		t.Errorf("empty info invented fields: %+v", u2)
	}

	u3 := &User{}
	applyBotInfoFields(u3, nil)
	if u3.BotDescription != "" || u3.BotPrivacyURL != "" || u3.BotMenuText != "" {
		t.Errorf("nil info invented fields: %+v", u3)
	}

	u4 := &User{}
	bi4 := &tg.BotInfo{}
	bi4.SetMenuButton(&tg.BotMenuButtonDefault{})
	applyBotInfoFields(u4, bi4)
	if u4.BotMenuText != "" {
		t.Errorf("default menu button leaked text: %q", u4.BotMenuText)
	}
}

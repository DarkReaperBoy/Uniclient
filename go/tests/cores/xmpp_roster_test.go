package tests

import (
	"testing"
	. "uniclient/cores"
)

func TestXMPPParseRoster(t *testing.T) {
	inner := "<query xmlns='jabber:iq:roster'>" +
		"<ver>42-abc</ver>" +
		"<item jid='alice@example.org' name='Alice' subscription='both'/>" +
		"<item jid='bob@example.org' subscription='to'><group>Friends</group></item>" +
		"</query>"

	items, ver, err := XmppParseRoster(inner)
	if err != nil {
		t.Fatalf("parse errored — the old ,attr tag rejected the whole document (B-11): %v", err)
	}
	if ver != "42-abc" {
		t.Errorf("ver = %q, want %q (XEP-0237 roster version must round-trip)", ver, "42-abc")
	}
	if len(items) != 2 {
		t.Fatalf("items = %d (%+v), want 2", len(items), items)
	}
	byJID := map[string]XmppRosterItem{}
	for _, it := range items {
		byJID[it.JID] = it
	}
	a := byJID["alice@example.org"]
	if a.Name != "Alice" || a.Subscription != "both" {
		t.Errorf("alice = %+v, want Name=Alice Subscription=both", a)
	}
	b := byJID["bob@example.org"]
	if b.Subscription != "to" || len(b.Groups) != 1 || b.Groups[0] != "Friends" {
		t.Errorf("bob = %+v, want Subscription=to Groups=[Friends]", b)
	}

	items, _, err = XmppParseRoster("<query xmlns='jabber:iq:roster'>" +
		"<item jid='gone@example.org' subscription='remove'/></query>")
	if err != nil || len(items) != 1 || items[0].Subscription != "remove" {
		t.Errorf("remove payload: items=%+v err=%v, want one remove item", items, err)
	}

	if _, _, err := XmppParseRoster("<query xmlns='jabber:iq:roster'><item jid='x'"); err == nil {
		t.Error("malformed payload parsed without error — silent fabrication")
	}
}

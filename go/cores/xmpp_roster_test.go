package cores

// tests-first for BUGS.md B-11 — the roster <query/> parser.
//
// The old struct tag (`xml:"jabber:iq:roster query>ver,attr"`) was
// structurally invalid: encoding/xml rejects `,attr` on a chained
// path, so Unmarshal errored on EVERY input and both call sites
// dropped the roster silently — the XMPP contact list never loaded
// (requestRoster ignored the error; handleRosterPush returned on it).
// The slice-235 audit proved it with a standalone probe BEFORE this
// test existed; the test keeps the proof permanent.

import "testing"

func TestXMPPParseRoster(t *testing.T) {
	inner := "<query xmlns='jabber:iq:roster'>" +
		"<ver>42-abc</ver>" +
		"<item jid='alice@example.org' name='Alice' subscription='both'/>" +
		"<item jid='bob@example.org' subscription='to'><group>Friends</group></item>" +
		"</query>"

	items, ver, err := xmppParseRoster(inner)
	if err != nil {
		t.Fatalf("parse errored — the old ,attr tag rejected the whole document (B-11): %v", err)
	}
	if ver != "42-abc" {
		t.Errorf("ver = %q, want %q (XEP-0237 roster version must round-trip)", ver, "42-abc")
	}
	if len(items) != 2 {
		t.Fatalf("items = %d (%+v), want 2", len(items), items)
	}
	byJID := map[string]xmppRosterItem{}
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

	// A remove payload must decode too (subscription='remove' is how
	// XEP-0237 deletes a contact).
	items, _, err = xmppParseRoster("<query xmlns='jabber:iq:roster'>" +
		"<item jid='gone@example.org' subscription='remove'/></query>")
	if err != nil || len(items) != 1 || items[0].Subscription != "remove" {
		t.Errorf("remove payload: items=%+v err=%v, want one remove item", items, err)
	}

	// Genuinely malformed XML must ERROR, not fabricate a roster
	// (§1.10). Note: plain text is *valid* XML once wrapped in <r> —
	// the wrapper is why this uses an unclosed tag, not prose
	// (first draft of this oracle was wrong in exactly that way).
	if _, _, err := xmppParseRoster("<query xmlns='jabber:iq:roster'><item jid='x'"); err == nil {
		t.Error("malformed payload parsed without error — silent fabrication")
	}
}

package cores

import (
	"strings"
	"testing"
)

// XEP-0077 in-band registration: stanza construction + response parsing.

func TestXMPPRegisterIQStanza(t *testing.T) {
	stanza := buildIBRStanza("reg42", "alice", "s3cret!pass")
	want := `<iq type='set' id='reg42'><query xmlns='jabber:iq:register'><username>alice</username><password>s3cret!pass</password></query></iq>`
	if stanza != want {
		t.Fatalf("IBR stanza mismatch:\n got %s\nwant %s", stanza, want)
	}

	// XML-escaping must apply to both fields (xml.EscapeText emits
	// numeric character references for quotes: &#34; and &#39;).
	stanza = buildIBRStanza("r2", `a&"b"`, `p<'>'`)
	if !strings.Contains(stanza, `<username>a&amp;&#34;b&#34;</username>`) {
		t.Fatalf("username not escaped: %s", stanza)
	}
	if !strings.Contains(stanza, `<password>p&lt;&#39;&gt;&#39;</password>`) {
		t.Fatalf("password not escaped: %s", stanza)
	}
}

func TestXMPPParseIBRResponse(t *testing.T) {
	// Success.
	err := parseIBRResponse(`<iq id='reg42' type='result'><query xmlns='jabber:iq:register'/></iq>`)
	if err != nil {
		t.Fatalf("success response returned error: %v", err)
	}

	// Username taken (conflict) — the classic case for retries.
	err = parseIBRResponse(`<iq id='reg42' type='error'><error type='cancel'><conflict xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/><text xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'>Username already exists</text></error></iq>`)
	if err == nil || !strings.Contains(err.Error(), "conflict") || !strings.Contains(err.Error(), "Username already exists") {
		t.Fatalf("conflict not surfaced: %v", err)
	}

	// Server forbids IBR.
	err = parseIBRResponse(`<iq id='reg42' type='error'><error type='cancel'><not-allowed xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/></error></iq>`)
	if err == nil || !strings.Contains(err.Error(), "not-allowed") {
		t.Fatalf("not-allowed not surfaced: %v", err)
	}

	// Web redirect (OOB) — server wants registration on a website.
	err = parseIBRResponse(`<iq id='reg42' type='result'><query xmlns='jabber:iq:register'><x xmlns='jabber:x:oob'><url>https://xmpp.is/account/</url></x></query></iq>`)
	if err == nil || !strings.Contains(err.Error(), "https://xmpp.is/account/") {
		t.Fatalf("OOB redirect not surfaced: %v", err)
	}

	// Empty/timeout-ish garbage must not parse as success.
	err = parseIBRResponse(``)
	if err == nil {
		t.Fatal("empty response must be an error")
	}
}

func TestXMPPFeaturesAdvertiseIBR(t *testing.T) {
	c := &XMPPCore{}
	featXML := `<stream:features><mechanisms xmlns='urn:ietf:params:xml:ns:xmpp-sasl'><mechanism>SCRAM-SHA-256</mechanism></mechanisms><register xmlns='http://jabber.org/features/iq-register'/></stream:features>`
	if err := c.parseStreamFeatures(featXML); err != nil {
		t.Fatalf("parse: %v", err)
	}
	if c.features.IBR == nil {
		t.Fatal("IBR not detected in features (http://jabber.org/features/iq-register)")
	}

	// Absent → nil.
	c2 := &XMPPCore{}
	featXML2 := `<stream:features><mechanisms xmlns='urn:ietf:params:xml:ns:xmpp-sasl'><mechanism>PLAIN</mechanism></mechanisms></stream:features>`
	if err := c2.parseStreamFeatures(featXML2); err != nil {
		t.Fatalf("parse: %v", err)
	}
	if c2.features.IBR != nil {
		t.Fatal("IBR must be nil when not advertised")
	}
}

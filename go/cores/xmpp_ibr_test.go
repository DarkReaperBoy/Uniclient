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

// ── data-form registration (XEP-0077 §4 with jabber:x:data) ───────────────
// Modern servers (ejabberd/MongooseIM with form-based IBR, e.g. sure.im)
// reject the legacy <username/><password/> payload with "Use proper
// DataForm registration" and answer the form GET with an x:data form.

func TestXMPPParseIBRForm(t *testing.T) {
	// Data-form GET response.
	raw := `<iq id='f1' type='result'><query xmlns='jabber:iq:register'>` +
		`<x xmlns='jabber:x:data' type='form'>` +
		`<field var='FORM_TYPE' type='hidden'><value>urn:xmpp:ibr-token:0</value></field>` +
		`<field var='username' type='text-single' label='Username'><required/></field>` +
		`<field var='password' type='text-private' label='Password'><required/></field>` +
		`</x></query></iq>`
	fields, ok := parseIBRForm(raw)
	if !ok || len(fields) != 3 {
		t.Fatalf("parseIBRForm = %+v ok=%v, want 3 fields", fields, ok)
	}
	if fields[0].Var != "FORM_TYPE" || fields[0].Type != "hidden" || fields[0].Value != "urn:xmpp:ibr-token:0" {
		t.Errorf("FORM_TYPE field wrong: %+v", fields[0])
	}
	if !fields[1].Required || fields[1].Var != "username" {
		t.Errorf("username field wrong: %+v", fields[1])
	}
	if fields[2].Var != "password" || fields[2].Type != "text-private" {
		t.Errorf("password field wrong: %+v", fields[2])
	}

	// Legacy form → ok=false.
	legacy := `<iq id='f2' type='result'><query xmlns='jabber:iq:register'><instructions>Choose a username.</instructions><username/><password/></query></iq>`
	if _, ok := parseIBRForm(legacy); ok {
		t.Error("legacy form parsed as data form")
	}
	// Error response → not a form.
	if _, ok := parseIBRForm(`<iq id='f3' type='error'><error type='cancel'><not-allowed xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/></error></iq>`); ok {
		t.Error("error response parsed as data form")
	}
}

func TestXMPPBuildIBRDataFormSubmit(t *testing.T) {
	fields := []ibrFormField{
		{Var: "FORM_TYPE", Type: "hidden", Value: "urn:xmpp:ibr-token:0"},
		{Var: "username", Type: "text-single", Required: true},
		{Var: "password", Type: "text-private", Required: true},
		{Var: "email", Type: "text-single"}, // unknown → omitted
	}
	stanza := buildIBRDataFormSubmit("s7", fields, "alice", "s3cret")
	if !strings.Contains(stanza, `<iq type='set' id='s7'><query xmlns='jabber:iq:register'>`) {
		t.Errorf("envelope wrong: %s", stanza)
	}
	if !strings.Contains(stanza, `<x xmlns='jabber:x:data' type='submit'>`) {
		t.Errorf("submit form missing: %s", stanza)
	}
	if !strings.Contains(stanza, `<field var='FORM_TYPE' type='hidden'><value>urn:xmpp:ibr-token:0</value></field>`) {
		t.Errorf("FORM_TYPE not passed through: %s", stanza)
	}
	if !strings.Contains(stanza, `<field var='username'><value>alice</value></field>`) {
		t.Errorf("username not filled: %s", stanza)
	}
	if !strings.Contains(stanza, `<field var='password'><value>s3cret</value></field>`) {
		t.Errorf("password not filled: %s", stanza)
	}
	if strings.Contains(stanza, "email") {
		t.Errorf("unanswerable field must be omitted: %s", stanza)
	}
	// Values are XML-escaped.
	stanza = buildIBRDataFormSubmit("s8", fields, `a&b`, `p<"'>`)
	if !strings.Contains(stanza, `<value>a&amp;b</value>`) {
		t.Errorf("username not escaped: %s", stanza)
	}
	if !strings.Contains(stanza, `<value>p&lt;&#34;&#39;&gt;</value>`) {
		t.Errorf("password not escaped: %s", stanza)
	}
}

func TestXMPPBuildIBRGetStanza(t *testing.T) {
	stanza := buildIBRGetStanza("g1")
	want := `<iq type='get' id='g1'><query xmlns='jabber:iq:register'/></iq>`
	if stanza != want {
		t.Fatalf("GET stanza mismatch:\n got %s\nwant %s", stanza, want)
	}
}

func TestSASLElementMatch(t *testing.T) {
	// The wire format real servers use: self-closing WITH the xmlns
	// attribute — the old code only matched the literal <success/> and
	// would time out on every real successful login.
	cases := []struct {
		data    string
		name    string
		content string
	}{
		{`<success xmlns='urn:ietf:params:xml:ns:xmpp-sasl'/>`, "success", ""},
		{`<success/>`, "success", ""},
		{`<success xmlns="urn:ietf:params:xml:ns:xmpp-sasl"></success>`, "success", ""},
		{`<challenge xmlns='urn:ietf:params:xml:ns:xmpp-sasl'>Y2hhbGxlbmdl</challenge>`, "challenge", "Y2hhbGxlbmdl"},
		{`<failure xmlns='urn:ietf:params:xml:ns:xmpp-sasl'><not-authorized/></failure>`, "failure", "<not-authorized/>"},
	}
	for _, c := range cases {
		name, content, ok := saslElementMatch(c.data)
		if !ok || name != c.name || content != c.content {
			t.Errorf("saslElementMatch(%q) = %q,%q,%v want %q,%q", c.data, name, content, ok, c.name, c.content)
		}
	}
	// Incomplete buffers must not match.
	if _, _, ok := saslElementMatch(`<success xml`); ok {
		t.Error("partial element matched")
	}
	if _, _, ok := saslElementMatch(`<stream:features>`); ok {
		t.Error("non-SASL element matched")
	}
}

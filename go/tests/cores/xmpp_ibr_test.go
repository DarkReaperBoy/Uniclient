package tests

import (
	"strings"
	"testing"
	. "uniclient/cores"
)

func TestXMPPRegisterIQStanza(t *testing.T) {
	stanza := BuildIBRStanza("reg42", "alice", "s3cret!pass")
	want := `<iq type='set' id='reg42'><query xmlns='jabber:iq:register'><username>alice</username><password>s3cret!pass</password></query></iq>`
	if stanza != want {
		t.Fatalf("IBR stanza mismatch:\n got %s\nwant %s", stanza, want)
	}

	stanza = BuildIBRStanza("r2", `a&"b"`, `p<'>'`)
	if !strings.Contains(stanza, `<username>a&amp;&#34;b&#34;</username>`) {
		t.Fatalf("username not escaped: %s", stanza)
	}
	if !strings.Contains(stanza, `<password>p&lt;&#39;&gt;&#39;</password>`) {
		t.Fatalf("password not escaped: %s", stanza)
	}
}

func TestXMPPParseIBRResponse(t *testing.T) {
	err := ParseIBRResponse(`<iq id='reg42' type='result'><query xmlns='jabber:iq:register'/></iq>`)
	if err != nil {
		t.Fatalf("success response returned error: %v", err)
	}

	err = ParseIBRResponse(`<iq id='reg42' type='error'><error type='cancel'><conflict xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/><text xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'>Username already exists</text></error></iq>`)
	if err == nil || !strings.Contains(err.Error(), "conflict") || !strings.Contains(err.Error(), "Username already exists") {
		t.Fatalf("conflict not surfaced: %v", err)
	}

	err = ParseIBRResponse(`<iq id='reg42' type='error'><error type='cancel'><not-allowed xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/></error></iq>`)
	if err == nil || !strings.Contains(err.Error(), "not-allowed") {
		t.Fatalf("not-allowed not surfaced: %v", err)
	}

	err = ParseIBRResponse(`<iq id='reg42' type='result'><query xmlns='jabber:iq:register'><x xmlns='jabber:x:oob'><url>https://xmpp.is/account/</url></x></query></iq>`)
	if err == nil || !strings.Contains(err.Error(), "https://xmpp.is/account/") {
		t.Fatalf("OOB redirect not surfaced: %v", err)
	}

	err = ParseIBRResponse(``)
	if err == nil {
		t.Fatal("empty response must be an error")
	}
}

func TestXMPPParseIBRForm(t *testing.T) {
	raw := `<iq id='f1' type='result'><query xmlns='jabber:iq:register'>` +
		`<x xmlns='jabber:x:data' type='form'>` +
		`<field var='FORM_TYPE' type='hidden'><value>urn:xmpp:ibr-token:0</value></field>` +
		`<field var='username' type='text-single' label='Username'><required/></field>` +
		`<field var='password' type='text-private' label='Password'><required/></field>` +
		`</x></query></iq>`
	fields, ok := ParseIBRForm(raw)
	if !ok || len(fields) != 3 {
		t.Fatalf("ParseIBRForm = %+v ok=%v, want 3 fields", fields, ok)
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

	legacy := `<iq id='f2' type='result'><query xmlns='jabber:iq:register'><instructions>Choose a username.</instructions><username/><password/></query></iq>`
	if _, ok := ParseIBRForm(legacy); ok {
		t.Error("legacy form parsed as data form")
	}
	if _, ok := ParseIBRForm(`<iq id='f3' type='error'><error type='cancel'><not-allowed xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/></error></iq>`); ok {
		t.Error("error response parsed as data form")
	}
}

func TestXMPPBuildIBRDataFormSubmit(t *testing.T) {
	fields := []IbrFormField{
		{Var: "FORM_TYPE", Type: "hidden", Value: "urn:xmpp:ibr-token:0"},
		{Var: "username", Type: "text-single", Required: true},
		{Var: "password", Type: "text-private", Required: true},
		{Var: "email", Type: "text-single"},
	}
	stanza := BuildIBRDataFormSubmit("s7", fields, "alice", "s3cret")
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
	stanza = BuildIBRDataFormSubmit("s8", fields, `a&b`, `p<"'>`)
	if !strings.Contains(stanza, `<value>a&amp;b</value>`) {
		t.Errorf("username not escaped: %s", stanza)
	}
	if !strings.Contains(stanza, `<value>p&lt;&#34;&#39;&gt;</value>`) {
		t.Errorf("password not escaped: %s", stanza)
	}
}

func TestXMPPBuildIBRGetStanza(t *testing.T) {
	stanza := BuildIBRGetStanza("g1")
	want := `<iq type='get' id='g1'><query xmlns='jabber:iq:register'/></iq>`
	if stanza != want {
		t.Fatalf("GET stanza mismatch:\n got %s\nwant %s", stanza, want)
	}
}

func TestSASLElementMatch(t *testing.T) {
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
		name, content, ok := SaslElementMatch(c.data)
		if !ok || name != c.name || content != c.content {
			t.Errorf("saslElementMatch(%q) = %q,%q,%v want %q,%q", c.data, name, content, ok, c.name, c.content)
		}
	}
	if _, _, ok := SaslElementMatch(`<success xml`); ok {
		t.Error("partial element matched")
	}
	if _, _, ok := SaslElementMatch(`<stream:features>`); ok {
		t.Error("non-SASL element matched")
	}
}

package tests

import (
	"testing"
	. "uniclient/engine"
)

func TestAuthFlowsArePerEngine(t *testing.T) {
	e1 := newAuthEngine(t)
	e2 := newAuthEngine(t)
	if err := e1.AttachAccount("acct", "xmpp", nil); err != nil {
		t.Fatalf("attach e1: %v", err)
	}
	if err := e2.AttachAccount("acct", "xmpp", nil); err != nil {
		t.Fatalf("attach e2: %v", err)
	}
	if _, err := e1.StartAuth("acct"); err != nil {
		t.Fatalf("start e1: %v", err)
	}
	if _, err := e2.StartAuth("acct"); err != nil {
		t.Fatalf("start e2: %v", err)
	}

	e2.CancelAuth("acct")

	st, err := e1.SubmitAuthInput("acct", "x@invalid.example")
	if err != nil {
		t.Fatalf("e1 lost its auth flow after e2 cancelled its own: %v", err)
	}
	if st == nil || st.State != AuthStateInput || st.FieldType != "password" {
		t.Fatalf("e1 flow corrupted by e2: %+v", st)
	}
}

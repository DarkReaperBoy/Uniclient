package cores

import "testing"

// TestStubCoreIsHonest: the stub never pretends to work — unsupported
// operations must surface ErrNotSupported, never fake success
// (AGENTS.md §1.10).
func TestStubCoreIsHonest(t *testing.T) {
	var c Core = StubCore{}

	if c.Name() != "stub" {
		t.Errorf("Name() = %q, want stub", c.Name())
	}
	if caps := c.Capabilities(); caps != nil {
		t.Errorf("Capabilities() = %v, want nil (stub supports nothing)", caps)
	}
	if err := c.Authenticate(AuthConfig{}); err != ErrNotSupported {
		t.Errorf("Authenticate() = %v, want ErrNotSupported", err)
	}
	if err := c.Logout(); err != ErrNotSupported {
		t.Errorf("Logout() = %v, want ErrNotSupported", err)
	}
	if _, err := c.GetDialogs(PaginationOpts{}); err != ErrNotSupported {
		t.Errorf("GetDialogs() = %v, want ErrNotSupported", err)
	}
	if _, err := c.GetFolders(); err != ErrNotSupported {
		t.Errorf("GetFolders() = %v, want ErrNotSupported", err)
	}
	if _, err := c.SendMessage("chat", OutgoingMessage{Text: "x"}); err != ErrNotSupported {
		t.Errorf("SendMessage() = %v, want ErrNotSupported", err)
	}
	if _, err := c.GetMessages("chat", PaginationOpts{}); err != ErrNotSupported {
		t.Errorf("GetMessages() = %v, want ErrNotSupported", err)
	}
	if err := c.MarkAsRead("chat", "msg"); err != ErrNotSupported {
		t.Errorf("MarkAsRead() = %v, want ErrNotSupported", err)
	}
	if _, err := c.StartCall("chat", false); err != ErrNotSupported {
		t.Errorf("StartCall() = %v, want ErrNotSupported", err)
	}
	if _, err := c.JoinGroupCall("chat"); err != ErrNotSupported {
		t.Errorf("JoinGroupCall() = %v, want ErrNotSupported", err)
	}
}

package gui

import "testing"

// TestBizQuickReplyEditSlotIsSingle pins R36: the quick-reply manager's
// inline forms used to be two independent slots sharing one name editor
// and one cancel button — the new-shortcut form and a rename row could be
// open at the same time (opening a rename clobbered the form's text via
// SetText), and the shared Cancel button only cleared the new-form flag,
// so a started rename could NOT be cancelled at all. There is now exactly
// one inline edit slot: opening either side closes the other, and cancel
// closes whichever is open.
func TestBizQuickReplyEditSlotIsSingle(t *testing.T) {
	a := &App{}
	a.businessPage = &businessPageState{accountID: "acc", loaded: true, editor: "replies"}

	// Open the new-shortcut form.
	a.bizQRNewClicked()
	head := a.businessPage
	if !head.qrNewOpen || head.qrRenameID != 0 {
		t.Fatalf("new form must open with no rename row: qrNewOpen=%v qrRenameID=%d",
			head.qrNewOpen, head.qrRenameID)
	}
	if bizQRNameEd.Text() != "" || bizQRTextEd.Text() != "" {
		t.Fatal("opening the new form must clear the editors")
	}

	// A rename row opening must close the new form (one slot).
	a.bizQRRenameRowClicked(42, "thanks")
	head = a.businessPage
	if head.qrRenameID != 42 {
		t.Fatalf("rename row must open for id 42, got %d", head.qrRenameID)
	}
	if head.qrNewOpen {
		t.Fatal("opening a rename row must close the new-shortcut form")
	}
	if bizQRNameEd.Text() != "thanks" {
		t.Fatalf("rename row must seed the name editor, got %q", bizQRNameEd.Text())
	}

	// Cancel must close the rename row (the dead-cancel half of R36:
	// this exact path used to leave qrRenameID set).
	a.bizQRCancelClicked()
	head = a.businessPage
	if head.qrNewOpen || head.qrRenameID != 0 {
		t.Fatalf("cancel must close the inline edit slot: qrNewOpen=%v qrRenameID=%d",
			head.qrNewOpen, head.qrRenameID)
	}

	// Reopening the new form must clear any rename row.
	a.bizQRRenameRowClicked(7, "hello")
	a.bizQRNewClicked()
	head = a.businessPage
	if !head.qrNewOpen || head.qrRenameID != 0 {
		t.Fatalf("opening the new form must close a rename row: qrNewOpen=%v qrRenameID=%d",
			head.qrNewOpen, head.qrRenameID)
	}

	// Toggling the new form closed leaves no slot open.
	a.bizQRNewClicked()
	head = a.businessPage
	if head.qrNewOpen {
		t.Fatal("second click must close the new form")
	}
}

// TestBizQREditSlotOnClosedPage pins the nil-safety of the extracted
// click handlers: a closed page (or a race where the page closed between
// the frame and the click) must be a silent no-op, not a panic.
func TestBizQREditSlotOnClosedPage(t *testing.T) {
	a := &App{} // no business page at all
	a.bizQRNewClicked()
	a.bizQRCancelClicked()
	a.bizQRRenameRowClicked(1, "x")
	if a.businessPage != nil {
		t.Fatal("handlers on a closed page must not open one")
	}
}

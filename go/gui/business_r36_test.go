package gui

import "testing"

func TestBizQuickReplyEditSlotIsSingle(t *testing.T) {
	a := &App{}
	a.businessPage = &businessPageState{accountID: "acc", loaded: true, editor: "replies"}

	a.bizQRNewClicked()
	head := a.businessPage
	if !head.qrNewOpen || head.qrRenameID != 0 {
		t.Fatalf("new form must open with no rename row: qrNewOpen=%v qrRenameID=%d",
			head.qrNewOpen, head.qrRenameID)
	}
	if bizQRNameEd.Text() != "" || bizQRTextEd.Text() != "" {
		t.Fatal("opening the new form must clear the editors")
	}

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

	a.bizQRCancelClicked()
	head = a.businessPage
	if head.qrNewOpen || head.qrRenameID != 0 {
		t.Fatalf("cancel must close the inline edit slot: qrNewOpen=%v qrRenameID=%d",
			head.qrNewOpen, head.qrRenameID)
	}

	a.bizQRRenameRowClicked(7, "hello")
	a.bizQRNewClicked()
	head = a.businessPage
	if !head.qrNewOpen || head.qrRenameID != 0 {
		t.Fatalf("opening the new form must close a rename row: qrNewOpen=%v qrRenameID=%d",
			head.qrNewOpen, head.qrRenameID)
	}

	a.bizQRNewClicked()
	head = a.businessPage
	if head.qrNewOpen {
		t.Fatal("second click must close the new form")
	}
}

func TestBizQREditSlotOnClosedPage(t *testing.T) {
	a := &App{}
	a.bizQRNewClicked()
	a.bizQRCancelClicked()
	a.bizQRRenameRowClicked(1, "x")
	if a.businessPage != nil {
		t.Fatal("handlers on a closed page must not open one")
	}
}

package gui

import (
	"gioui.org/widget"

	"golang.org/x/exp/shiny/materialdesign/icons"
)

// App icons (Material Design icon set shipped with gio).
var (
	iconContentAdd         = mustIcon(icons.ContentAdd)
	iconNavigationBack     = mustIcon(icons.NavigationArrowBack)
	iconContentSend        = mustIcon(icons.ContentSend)
	iconCommunicationChat  = mustIcon(icons.CommunicationChat)
	iconCommunicationForum = mustIcon(icons.CommunicationForum)
	iconHardwareHeadset    = mustIcon(icons.HardwareHeadset)
	iconActionSearch       = mustIcon(icons.ActionSearch)
	iconActionSettings     = mustIcon(icons.ActionSettings)
	iconActionAccount      = mustIcon(icons.ActionAccountCircle)
	iconActionDelete       = mustIcon(icons.ActionDelete)
	iconActionDone         = mustIcon(icons.ActionDone)
	iconContentClear       = mustIcon(icons.ContentClear)
	iconContentCreate      = mustIcon(icons.ContentCreate)
	iconContentReply       = mustIcon(icons.ContentReply)
	iconNavigationCheck    = mustIcon(icons.NavigationCheck)
	iconSocialPerson       = mustIcon(icons.SocialPerson)
	iconCommunicationCall  = mustIcon(icons.CommunicationCall)
)

func mustIcon(data []byte) *widget.Icon {
	ic, err := widget.NewIcon(data)
	if err != nil {
		panic("gui: icon decode failed: " + err.Error())
	}
	return ic
}

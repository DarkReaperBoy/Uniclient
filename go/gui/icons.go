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
	iconAVNote             = mustIcon(icons.AVNote)
	iconAVMic              = mustIcon(icons.AVMic)
	iconFileAttach         = mustIcon(icons.FileAttachment)
	iconFileDownload       = mustIcon(icons.FileFileDownload)
	iconAVPlayCircle       = mustIcon(icons.AVPlayCircleFilled)
	iconAVStop             = mustIcon(icons.AVStop)
	iconSocialNotif        = mustIcon(icons.SocialNotificationsNone)
	iconActionLock         = mustIcon(icons.ActionLock)
	iconActionBackup       = mustIcon(icons.ActionBackup)
	iconImagePalette       = mustIcon(icons.ImagePalette)
	iconActionGhost        = mustIcon(icons.ActionVisibilityOff)
	iconActionInfo         = mustIcon(icons.ActionInfoOutline)
	iconImagePhoto         = mustIcon(icons.ImagePhoto)
	iconNavChevronLeft     = mustIcon(icons.NavigationChevronLeft)
	iconNavChevronRight    = mustIcon(icons.NavigationChevronRight)
	iconSocialShare        = mustIcon(icons.SocialShare)
)

func mustIcon(data []byte) *widget.Icon {
	ic, err := widget.NewIcon(data)
	if err != nil {
		panic("gui: icon decode failed: " + err.Error())
	}
	return ic
}

package gui

import (
	"gioui.org/widget"

	"golang.org/x/exp/shiny/materialdesign/icons"
)

// App icons (Material Design icon set shipped with gio).
var (
	iconContentAdd            = mustIcon(icons.ContentAdd)
	iconNavigationBack        = mustIcon(icons.NavigationArrowBack)
	iconContentSend           = mustIcon(icons.ContentSend)
	iconCommunicationChat     = mustIcon(icons.CommunicationChat)
	iconCommunicationForum    = mustIcon(icons.CommunicationForum)
	iconHardwareHeadset       = mustIcon(icons.HardwareHeadset)
	iconActionSearch          = mustIcon(icons.ActionSearch)
	iconActionSettings        = mustIcon(icons.ActionSettings)
	iconActionAccount         = mustIcon(icons.ActionAccountCircle)
	iconActionDelete          = mustIcon(icons.ActionDelete)
	iconActionDone            = mustIcon(icons.ActionDone)
	iconContentClear          = mustIcon(icons.ContentClear)
	iconContentCreate         = mustIcon(icons.ContentCreate)
	iconContentReply          = mustIcon(icons.ContentReply)
	iconNavigationCheck       = mustIcon(icons.NavigationCheck)
	iconSocialPerson          = mustIcon(icons.SocialPerson)
	iconCommunicationCall     = mustIcon(icons.CommunicationCall)
	iconAVNote                = mustIcon(icons.AVNote)
	iconAVMic                 = mustIcon(icons.AVMic)
	iconAVMicOff              = mustIcon(icons.AVMicOff)
	iconAVVideocamOff         = mustIcon(icons.AVVideocamOff)
	iconCommunicationCallEnd  = mustIcon(icons.CommunicationCallEnd)
	iconFileAttach            = mustIcon(icons.FileAttachment)
	iconFileDownload          = mustIcon(icons.FileFileDownload)
	iconFileFolder            = mustIcon(icons.FileFolder)
	iconAVPlayCircle          = mustIcon(icons.AVPlayCircleFilled)
	iconAVStop                = mustIcon(icons.AVStop)
	iconAVVideocam            = mustIcon(icons.AVVideocam)
	iconSocialNotif           = mustIcon(icons.SocialNotificationsNone)
	iconSocialNotifOff        = mustIcon(icons.SocialNotificationsOff)
	iconContentMarkUnread     = mustIcon(icons.ContentMarkUnread)
	iconActionLock            = mustIcon(icons.ActionLock)
	iconActionBackup          = mustIcon(icons.ActionBackup)
	iconImagePalette          = mustIcon(icons.ImagePalette)
	iconActionGhost           = mustIcon(icons.ActionVisibilityOff)
	iconActionInfo            = mustIcon(icons.ActionInfoOutline)
	iconImagePhoto            = mustIcon(icons.ImagePhoto)
	iconNavChevronLeft        = mustIcon(icons.NavigationChevronLeft)
	iconNavChevronRight       = mustIcon(icons.NavigationChevronRight)
	iconSocialShare           = mustIcon(icons.SocialShare)
	iconEmojiSmile            = mustIcon(icons.EditorInsertEmoticon)
	iconContentBackspace      = mustIcon(icons.ContentBackspace)
	iconActionOfflinePin      = mustIcon(icons.ActionOfflinePin)
	iconNavMoreVert           = mustIcon(icons.NavigationMoreVert)
	iconNavMenu               = mustIcon(icons.NavigationMenu)
	iconCommunicationContacts = mustIcon(icons.CommunicationContacts)
	iconSocialGroup           = mustIcon(icons.SocialGroup)
	iconActionSchedule        = mustIcon(icons.ActionSchedule)
	iconActionCheckCircle     = mustIcon(icons.ActionCheckCircle)
	iconToggleStar            = mustIcon(icons.ToggleStar)
	iconAlertWarning          = mustIcon(icons.AlertWarning)
	iconAVVolumeOff           = mustIcon(icons.AVVolumeOff)
	iconNavArrowDown          = mustIcon(icons.NavigationArrowDownward)
	iconSocialPoll            = mustIcon(icons.SocialPoll)
	iconMapsPlace             = mustIcon(icons.MapsPlace)

	// Custom IconVG glyph: Material "pin" pushpin (see scripts/gen_pin_icon.go).
	iconCustomPin = mustIcon([]byte{0x89, 0x49, 0x56, 0x47, 0x04, 0x0a, 0x00, 0x80, 0x80, 0xb0, 0xb0, 0x84, 0x02, 0x3f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x80, 0x7c, 0xc0, 0xa0, 0x98, 0xe8, 0x88, 0xe6, 0xa2, 0xe8, 0x84, 0xe6, 0x8e, 0xe8, 0x88, 0xe6, 0x90, 0xe8, 0x98, 0x00, 0x8c, 0x9c, 0xe8, 0xa0, 0xe6, 0x35, 0x8b, 0xe8, 0xac, 0xe6, 0xcd, 0x8c, 0xe8, 0xa0, 0xe6, 0xa4, 0xe8, 0x9c, 0x00, 0xa0, 0x98, 0xe1})
)

func mustIcon(data []byte) *widget.Icon {
	ic, err := widget.NewIcon(data)
	if err != nil {
		panic("gui: icon decode failed: " + err.Error())
	}
	return ic
}

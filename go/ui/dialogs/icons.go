package dialogs

import "uniclient/ui/icons"

func ChatTypeIcon(t ChatType) icons.Icon {
	switch t {
	case ChatBot:
		return icons.DialogsBot
	case ChatChannel:
		return icons.DialogsChannel
	case ChatForum:
		return icons.DialogsForum
	}
	return icons.Icon{}
}

func BadgeIcon(kind BadgeKind) icons.Icon {
	switch kind {
	case BadgePinned:
		return icons.DialogsPinned
	case BadgeMention:
		return icons.DialogsMention
	case BadgeReaction:
		return icons.DialogsReaction
	case BadgePoll:
		return icons.DialogsPoll
	}
	return icons.Icon{}
}

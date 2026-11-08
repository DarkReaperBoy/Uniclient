package dialogs

import "uniclient/ui/icons"

func SendStateIcon(state SendState) icons.Icon {
	switch state {
	case SendSending:
		return icons.DialogsSending
	case SendSent:
		return icons.DialogsSent
	case SendReceived:
		return icons.DialogsReceived
	}
	return icons.Icon{}
}

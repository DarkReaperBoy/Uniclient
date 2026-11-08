package history

import (
	"uniclient/ui/dialogs"
)

func absInt(v int) int {
	if v < 0 {
		return -v
	}
	return v
}

func (Item) consumesHorizontalScroll() bool {
	return false
}

func (l List) ConsumeScrollAction(dx, dy int, classicWheel bool, y int) bool {
	horizontal := absInt(dx) > absInt(dy)
	if classicWheel && !horizontal {
		return false
	}
	i := l.RowAt(y)
	return i >= 0 && l.Items[i].consumesHorizontalScroll()
}

func ChatBottomRequest(top, delta, max int) bool {
	if delta <= 0 {
		return false
	}
	target := top + delta
	return dialogs.WillScrollTo(top, target, max) < target
}

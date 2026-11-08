package history

import "uniclient/ui/tokens"

func (l List) firstUnreadRow() int {
	for i := range l.Items {
		if l.Items[i].UnreadBar != "" {
			return i
		}
	}
	return -1
}

func (l List) DownShown(v Viewport) bool {
	if len(l.Items) == 0 || v.Height <= 0 {
		return false
	}
	if v.Top+tokens.HistoryToDownShownAfter < l.MaxOffset(v) {
		return true
	}
	row := l.firstUnreadRow()
	if row < 0 {
		return false
	}
	return l.rowTop(row) >= v.Top+v.Height
}

func (l List) DownJumpTop(v Viewport) int {
	max := l.MaxOffset(v)
	row := l.firstUnreadRow()
	if row < 0 {
		return max
	}
	top := l.rowTop(row)
	if top < 0 {
		return 0
	}
	if top > max {
		return max
	}
	return top
}

func DownButtonGeometry(paneWidth, paneHeight int, progress float32) Geometry {
	if progress < 0 {
		progress = 0
	}
	if progress > 1 {
		progress = 1
	}
	travel := float32(tokens.HistoryToDownHeight + tokens.HistoryToDownPositionY)
	return Geometry{
		Left:   paneWidth - tokens.HistoryToDownPositionX - tokens.HistoryToDownWidth,
		Top:    paneHeight - int(travel*progress),
		Width:  tokens.HistoryToDownWidth,
		Height: tokens.HistoryToDownHeight,
	}
}

func DownButtonHit(paneWidth, paneHeight int, progress float32, x, y int) bool {
	g := DownButtonGeometry(paneWidth, paneHeight, progress)
	return x >= g.Left && x < g.Left+g.Width && y >= g.Top && y < g.Top+g.Height
}

func (l List) firstUnreadMentionRow() int {
	for i := range l.Items {
		if l.Items[i].UnreadMention {
			return i
		}
	}
	return -1
}

func (l List) MentionsShown() bool {
	return l.firstUnreadMentionRow() >= 0
}

func (l List) MentionsJumpTop(v Viewport) int {
	row := l.firstUnreadMentionRow()
	if row < 0 {
		return -1
	}
	max := l.MaxOffset(v)
	top := l.rowTop(row)
	if top < 0 {
		return 0
	}
	if top > max {
		return max
	}
	return top
}

func MentionsButtonGeometry(paneWidth, paneHeight int, progress, downProgress float32) Geometry {
	if progress < 0 {
		progress = 0
	}
	if progress > 1 {
		progress = 1
	}
	if downProgress < 0 {
		downProgress = 0
	}
	if downProgress > 1 {
		downProgress = 1
	}
	travel := float32(tokens.HistoryToDownPositionX + tokens.HistoryToDownWidth)
	shift := float32(tokens.HistoryToDownHeight+tokens.HistoryUnreadThingsSkip) * downProgress
	return Geometry{
		Left:   paneWidth - int(travel*progress),
		Top:    paneHeight - tokens.HistoryToDownHeight - tokens.HistoryToDownPositionY - int(shift),
		Width:  tokens.HistoryToDownWidth,
		Height: tokens.HistoryToDownHeight,
	}
}

func MentionsButtonHit(paneWidth, paneHeight int, progress, downProgress float32, x, y int) bool {
	g := MentionsButtonGeometry(paneWidth, paneHeight, progress, downProgress)
	return x >= g.Left && x < g.Left+g.Width && y >= g.Top && y < g.Top+g.Height
}

func (l List) firstUnreadReactionRow() int {
	for i := range l.Items {
		if l.Items[i].UnreadReaction {
			return i
		}
	}
	return -1
}

func (l List) ReactionsShown() bool {
	return l.firstUnreadReactionRow() >= 0
}

func (l List) ReactionsJumpTop(v Viewport) int {
	row := l.firstUnreadReactionRow()
	if row < 0 {
		return -1
	}
	max := l.MaxOffset(v)
	top := l.rowTop(row)
	if top < 0 {
		return 0
	}
	if top > max {
		return max
	}
	return top
}

func ReactionsButtonGeometry(paneWidth, paneHeight int, progress, downProgress, mentionsProgress float32) Geometry {
	if progress < 0 {
		progress = 0
	}
	if progress > 1 {
		progress = 1
	}
	if downProgress < 0 {
		downProgress = 0
	}
	if downProgress > 1 {
		downProgress = 1
	}
	if mentionsProgress < 0 {
		mentionsProgress = 0
	}
	if mentionsProgress > 1 {
		mentionsProgress = 1
	}
	travel := float32(tokens.HistoryToDownPositionX + tokens.HistoryToDownWidth)
	step := float32(tokens.HistoryToDownHeight + tokens.HistoryUnreadThingsSkip)
	shift := step*downProgress + step*mentionsProgress
	return Geometry{
		Left:   paneWidth - int(travel*progress),
		Top:    paneHeight - tokens.HistoryToDownHeight - tokens.HistoryToDownPositionY - int(shift),
		Width:  tokens.HistoryToDownWidth,
		Height: tokens.HistoryToDownHeight,
	}
}

func ReactionsButtonHit(paneWidth, paneHeight int, progress, downProgress, mentionsProgress float32, x, y int) bool {
	g := ReactionsButtonGeometry(paneWidth, paneHeight, progress, downProgress, mentionsProgress)
	return x >= g.Left && x < g.Left+g.Width && y >= g.Top && y < g.Top+g.Height
}

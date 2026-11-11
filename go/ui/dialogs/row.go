package dialogs

import (
	"image"

	"uniclient/ui/icons"
	"uniclient/ui/tokens"
)

type ChatType uint8

const (
	ChatPlain ChatType = iota
	ChatBot
	ChatChannel
	ChatForum
)

type SendState uint8

const (
	SendHidden SendState = iota
	SendSending
	SendSent
	SendReceived
)

type BadgeKind uint8

const (
	BadgeCounter BadgeKind = iota
	BadgeMark
	BadgePinned
	BadgeMention
	BadgeReaction
	BadgePoll
)

type Entry struct {
	Name        string
	Username    string
	Preview     string
	Date        string
	Photo       image.Image
	Unread      int
	ReadInbox   int
	UnreadMark  bool
	UnreadMuted bool
	Mention     bool
	Reaction    bool
	Poll        bool
	Pinned      bool
	SortTime    int64
	Online      bool
	TTL         bool
	TTLSec      int
	ChatType    ChatType
	SendState   SendState
	Tagged      bool
	Forum       bool
	Tags        []string
	Account     string
	ChatID      string
	Group       bool
}

type Metrics struct {
	SemiboldHeight int
	NormalDescent  int
	TextAscent     int
	TextHeight     int
	UnreadAscent   int
	UnreadHeight   int
	NameWidth      int
	DateWidth      int
	CounterWidth   int
	ChatTypeIconW  int
}

type Rect struct {
	X, Y, W, H int
}

type Badge struct {
	Kind         BadgeKind
	Cell         Rect
	Dot          Rect
	TextBaseline int
	Muted        bool
}

type RowLayout struct {
	Narrow        bool
	Height        int
	Photo         Rect
	Online        Rect
	TTL           Rect
	Name          Rect
	DateX         int
	DateBaseline  int
	Preview       Rect
	ChatTypeIcon  Rect
	SendStateIcon Rect
	TagTop        int
	Badges        []Badge
}

func CounterText(e Entry, narrow bool) string {
	return tokens.FormatUnreadCounter(e.Unread, e.Mention || e.Reaction, narrow)
}

func Layout(e Entry, width int, m Metrics) RowLayout {
	var l RowLayout
	l.Narrow = width < tokens.ColumnMinWidthLeft/2
	l.Height = rowHeight(e, l.Narrow)
	l.Photo = Rect{
		X: tokens.DialogsRowPadLeft,
		Y: tokens.DialogsRowPadTop,
		W: tokens.DialogsRowPhotoSize,
		H: tokens.DialogsRowPhotoSize,
	}
	if e.Online {
		x, y := tokens.DialogsOnlineBadgePos(tokens.DialogsRowPhotoSize, tokens.DialogsOnlineBadgeSize, tokens.DialogsOnlineBadgeStroke)
		l.Online = Rect{
			X: tokens.DialogsRowPadLeft + x,
			Y: tokens.DialogsRowPadTop + y,
			W: tokens.DialogsOnlineBadgeSize,
			H: tokens.DialogsOnlineBadgeSize,
		}
	}
	if e.TTL {
		x, y := tokens.DialogsOnlineBadgePos(tokens.DialogsRowPhotoSize, tokens.DialogsTTLBadgeSize, 0)
		l.TTL = Rect{
			X: tokens.DialogsRowPadLeft + x,
			Y: tokens.DialogsRowPadTop + y,
			W: tokens.DialogsTTLBadgeSize,
			H: tokens.DialogsTTLBadgeSize,
		}
	}
	if l.Narrow {
		l.Badges = narrowBadges(e, m)
		return l
	}

	textTop := textTopFor(e)
	if e.Tagged {
		if e.Forum {
			l.TagTop = tokens.DialogsRowTaggedForumTagTop
		} else {
			l.TagTop = tokens.DialogsRowTaggedTagTop
		}
	}

	namewidth := width - tokens.DialogsRowNameLeft - tokens.DialogsRowPadRight
	nameW := namewidth
	if e.Date != "" && m.DateWidth > 0 {
		l.DateX = width - tokens.DialogsRowPadRight - m.DateWidth
		l.DateBaseline = tokens.DialogsRowNameTop + m.SemiboldHeight - m.NormalDescent
		nameW -= m.DateWidth + tokens.DialogsDateSkip
	}
	nameX := tokens.DialogsRowNameLeft
	if e.ChatType != ChatPlain && m.ChatTypeIconW > 0 {
		l.ChatTypeIcon = Rect{
			X: nameX,
			Y: tokens.DialogsRowNameTop,
			W: m.ChatTypeIconW,
			H: tokens.DialogsIconSize,
		}
		nameX += m.ChatTypeIconW + tokens.DialogsChatTypeSkip
		nameW -= m.ChatTypeIconW + tokens.DialogsChatTypeSkip
	}
	if e.SendState != SendHidden {
		nameW -= tokens.DialogsSendStateSkip
		l.SendStateIcon = Rect{
			X: nameX + nameW,
			Y: tokens.DialogsRowNameTop,
			W: tokens.DialogsIconSize,
			H: tokens.DialogsIconSize,
		}
	}
	l.Name = Rect{X: nameX, Y: tokens.DialogsRowNameTop, W: nameW, H: m.SemiboldHeight}

	badges, used := wideBadges(e, width, textTop, m)
	l.Badges = badges
	l.Preview = Rect{
		X: tokens.DialogsRowTextLeft,
		Y: textTop,
		W: namewidth - used,
		H: m.TextHeight,
	}
	return l
}

func textTopFor(e Entry) int {
	switch {
	case e.Forum:
		return tokens.DialogsRowForumTextTop
	case e.Tagged:
		return tokens.DialogsRowTaggedTextTop
	default:
		return tokens.DialogsRowTextTop
	}
}

func rowHeight(e Entry, narrow bool) int {
	if narrow {
		return tokens.DialogsRowHeight
	}
	switch {
	case e.Forum && e.Tagged:
		return tokens.DialogsRowTaggedForumHeight
	case e.Forum:
		return tokens.DialogsRowForumHeight
	case e.Tagged:
		return tokens.DialogsRowTaggedHeight
	default:
		return tokens.DialogsRowHeight
	}
}

func badgeTop(textTop int, m Metrics) int {
	return textTop + m.TextAscent - m.UnreadAscent - (tokens.DialogsUnreadHeight-m.UnreadHeight)/2
}

func wideBadges(e Entry, width, textTop int, m Metrics) ([]Badge, int) {
	top := badgeTop(textTop, m)
	right := width - tokens.DialogsRowPadRight
	var badges []Badge
	switch {
	case e.UnreadMark:
		cell := Rect{X: right - tokens.DialogsUnreadHeight, Y: top, W: tokens.DialogsUnreadHeight, H: tokens.DialogsUnreadHeight}
		off := (tokens.DialogsUnreadHeight - tokens.DialogsUnreadMarkDiameter) / 2
		badges = append(badges, Badge{
			Kind: BadgeMark,
			Cell: cell,
			Dot:  Rect{X: cell.X + off, Y: top + off, W: tokens.DialogsUnreadMarkDiameter, H: tokens.DialogsUnreadMarkDiameter},
		})
		right -= tokens.DialogsUnreadHeight + tokens.DialogsUnreadPadding
	case e.Unread > 0:
		pillW := tokens.DialogsBadgeWidth(m.CounterWidth)
		badges = append(badges, Badge{
			Kind:         BadgeCounter,
			Cell:         Rect{X: right - pillW, Y: top, W: pillW, H: tokens.DialogsUnreadHeight},
			TextBaseline: top + (tokens.DialogsUnreadHeight-m.UnreadHeight)/2 + m.UnreadAscent,
			Muted:        e.UnreadMuted,
		})
		right -= pillW + tokens.DialogsUnreadPadding
	case e.Pinned:
		pinned := icons.DialogsPinned.Cell.W
		badges = append(badges, Badge{
			Kind: BadgePinned,
			Cell: Rect{X: right - pinned, Y: textTop, W: pinned, H: pinned},
		})
		right -= pinned + tokens.DialogsUnreadPadding
	}
	if e.Mention || e.Reaction {
		kind := BadgeReaction
		if e.Mention {
			kind = BadgeMention
		}
		badges = append(badges, Badge{
			Kind: kind,
			Cell: Rect{X: right - tokens.DialogsIconSize, Y: top, W: tokens.DialogsIconSize, H: tokens.DialogsIconSize},
		})
		right -= tokens.DialogsIconSize + tokens.DialogsUnreadPadding
	}
	if e.Poll {
		badges = append(badges, Badge{
			Kind: BadgePoll,
			Cell: Rect{X: right - tokens.DialogsIconSize, Y: top, W: tokens.DialogsIconSize, H: tokens.DialogsIconSize},
		})
		right -= tokens.DialogsIconSize + tokens.DialogsUnreadPadding
	}
	used := (width - tokens.DialogsRowPadRight) - right
	return badges, used
}

func narrowBadges(e Entry, m Metrics) []Badge {
	if e.Unread <= 0 && !e.UnreadMark && !e.Mention && !e.Reaction && !e.Poll {
		return nil
	}
	top := tokens.DialogsNarrowBadgeTop()
	right := tokens.DialogsRowPadLeft + tokens.DialogsRowPhotoSize
	var badges []Badge
	painted := 0
	switch {
	case e.UnreadMark:
		cell := Rect{X: right - tokens.DialogsUnreadHeight, Y: top, W: tokens.DialogsUnreadHeight, H: tokens.DialogsUnreadHeight}
		off := (tokens.DialogsUnreadHeight - tokens.DialogsUnreadMarkDiameter) / 2
		badges = append(badges, Badge{
			Kind: BadgeMark,
			Cell: cell,
			Dot:  Rect{X: cell.X + off, Y: top + off, W: tokens.DialogsUnreadMarkDiameter, H: tokens.DialogsUnreadMarkDiameter},
		})
		right -= tokens.DialogsUnreadHeight + tokens.DialogsUnreadPadding
		painted++
	case e.Unread > 0:
		pillW := tokens.DialogsBadgeWidth(m.CounterWidth)
		badges = append(badges, Badge{
			Kind:         BadgeCounter,
			Cell:         Rect{X: right - pillW, Y: top, W: pillW, H: tokens.DialogsUnreadHeight},
			TextBaseline: top + (tokens.DialogsUnreadHeight-m.UnreadHeight)/2 + m.UnreadAscent,
			Muted:        e.UnreadMuted,
		})
		right -= pillW + tokens.DialogsUnreadPadding
		painted++
	}
	if painted < 2 && (e.Mention || e.Reaction) {
		kind := BadgeReaction
		if e.Mention {
			kind = BadgeMention
		}
		badges = append(badges, Badge{
			Kind: kind,
			Cell: Rect{X: right - tokens.DialogsUnreadHeight, Y: top, W: tokens.DialogsUnreadHeight, H: tokens.DialogsUnreadHeight},
		})
		right -= tokens.DialogsUnreadHeight + tokens.DialogsUnreadPadding
		painted++
	}
	if painted < 2 && e.Poll {
		badges = append(badges, Badge{
			Kind: BadgePoll,
			Cell: Rect{X: right - tokens.DialogsUnreadHeight, Y: top, W: tokens.DialogsUnreadHeight, H: tokens.DialogsUnreadHeight},
		})
	}
	return badges
}

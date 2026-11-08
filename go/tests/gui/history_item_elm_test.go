package tests

import (
	"reflect"
	"testing"

	. "uniclient/ui/app"
	"uniclient/ui/history"
)

func chatItemModel(t *testing.T, rows int) Model {
	t.Helper()
	items := make([]history.Item, rows)
	heights := make([]int, rows)
	hits := make([]history.HitBox, rows)
	for i := range items {
		items[i] = history.Item{Kind: history.ItemMessage, Text: "m", TimeText: "10:00"}
		heights[i] = 60
		top := i * 60
		hits[i] = history.HitBox{
			Item: history.Geometry{Left: 20, Top: top + 5, Width: 200, Height: 50},
			Time: history.Geometry{Left: 181, Top: top + 39, Width: 30, Height: 13},
		}
	}
	m, _ := Update(InitialModel(), Resized{Width: 800, Height: 120})
	m, _ = Update(m, ChatLoaded{Items: items})
	m, _ = Update(m, ChatMeasured{Heights: heights, Hits: hits})
	return m
}

func selectionOf(rows ...int) history.Selection {
	if len(rows) == 0 {
		return nil
	}
	s := make(history.Selection, len(rows))
	for _, r := range rows {
		s[r] = true
	}
	return s
}

func TestChatMousePressRecordsItemState(t *testing.T) {
	m := chatItemModel(t, 3)
	m, _ = Update(m, ChatPressed{X: 100, Y: 30})
	p := m.ChatPress
	if p.Row != 0 || p.X != 100 || p.Y != 30 || !p.Inside || p.Time {
		t.Fatalf("press state = %+v, want row 0 inside body", p)
	}
	if p.Action != ChatPressSelecting {
		t.Fatalf("body press action = %d, want Selecting (text anchor)", p.Action)
	}
	m, _ = Update(m, ChatPressed{X: 100, Y: 58})
	p = m.ChatPress
	if p.Row != 0 || p.Inside {
		t.Fatalf("margin press = %+v, want row 0 outside the bubble", p)
	}
	if p.Action != ChatPressPrepareSelect {
		t.Fatalf("margin press action = %d, want PrepareSelect", p.Action)
	}
}

func TestChatMousePressOnTimePreparesDrag(t *testing.T) {
	m := chatItemModel(t, 3)
	m, _ = Update(m, ChatPressed{X: 190, Y: 45})
	p := m.ChatPress
	if p.Row != 0 || !p.Inside || !p.Time {
		t.Fatalf("time press = %+v, want row 0 over the time rect", p)
	}
	if p.Action != ChatPressPrepareDrag {
		t.Fatalf("time press action = %d, want PrepareDrag (requiredToStartDragging)", p.Action)
	}
}

func TestChatMouseTapBodyNoSelection(t *testing.T) {
	m := chatItemModel(t, 3)
	m, _ = Update(m, ChatPressed{X: 100, Y: 30})
	m, _ = Update(m, ChatReleased{X: 100, Y: 30})
	if m.ChatSelection.HasSelectedItems() {
		t.Fatalf("bare body tap selected = %v, want none", m.ChatSelection)
	}
	if m.ChatPress.Row != -1 {
		t.Fatalf("release must clear the press: %+v", m.ChatPress)
	}
}

func TestChatMouseTapTimeSelects(t *testing.T) {
	m := chatItemModel(t, 3)
	m, _ = Update(m, ChatPressed{X: 190, Y: 45})
	m, _ = Update(m, ChatReleased{X: 190, Y: 45})
	if !reflect.DeepEqual(m.ChatSelection, selectionOf(0)) {
		t.Fatalf("time tap selection = %v, want row 0", m.ChatSelection)
	}
}

func TestChatTapWhileSelectedInverts(t *testing.T) {
	m := chatItemModel(t, 3)
	m.ChatSelection = selectionOf(0)

	m, _ = Update(m, ChatPressed{X: 100, Y: 90})
	if p := m.ChatPress; p.Row != 1 || p.Action != ChatPressPrepareSelect {
		t.Fatalf("press on unselected row = %+v, want row 1 PrepareSelect", p)
	}
	m, _ = Update(m, ChatReleased{X: 100, Y: 90})
	if !reflect.DeepEqual(m.ChatSelection, selectionOf(0, 1)) {
		t.Fatalf("tap in selection mode = %v, want rows 0 and 1", m.ChatSelection)
	}

	m, _ = Update(m, ChatPressed{X: 100, Y: 90})
	m, _ = Update(m, ChatReleased{X: 100, Y: 90})
	if !reflect.DeepEqual(m.ChatSelection, selectionOf(0)) {
		t.Fatalf("second tap = %v, want row 0 only (invert back)", m.ChatSelection)
	}

	m, _ = Update(m, ChatPressed{X: 100, Y: 30})
	if p := m.ChatPress; p.Action != ChatPressPrepareDrag {
		t.Fatalf("press on selected row = %+v, want PrepareDrag (overSelectedItems)", p)
	}
	m, _ = Update(m, ChatReleased{X: 100, Y: 30})
	if m.ChatSelection.HasSelectedItems() {
		t.Fatalf("tap on the selected row = %v, want empty", m.ChatSelection)
	}
}

func TestChatTapServiceIgnored(t *testing.T) {
	items := []history.Item{
		{Kind: history.ItemMessage, Text: "m", TimeText: "10:00"},
		{Kind: history.ItemService, Text: "today"},
		{Kind: history.ItemMessage, Text: "m2", TimeText: "10:01"},
	}
	hits := []history.HitBox{
		{Item: history.Geometry{Left: 20, Top: 5, Width: 200, Height: 50},
			Time: history.Geometry{Left: 181, Top: 39, Width: 30, Height: 13}},
		{Item: history.Geometry{Left: 12, Top: 65, Width: 776, Height: 50}},
		{Item: history.Geometry{Left: 20, Top: 125, Width: 200, Height: 50},
			Time: history.Geometry{Left: 181, Top: 159, Width: 30, Height: 13}},
	}
	m, _ := Update(InitialModel(), Resized{Width: 800, Height: 120})
	m, _ = Update(m, ChatLoaded{Items: items})
	m, _ = Update(m, ChatMeasured{Heights: []int{60, 60, 60}, Hits: hits})
	m.ChatSelection = selectionOf(0)

	m, _ = Update(m, ChatPressed{X: 100, Y: 90})
	if p := m.ChatPress; p.Row != 1 || !p.Inside || p.Action != ChatPressPrepareSelect {
		t.Fatalf("service press = %+v, want row 1 inside PrepareSelect", p)
	}
	m, _ = Update(m, ChatReleased{X: 100, Y: 90})
	if !reflect.DeepEqual(m.ChatSelection, selectionOf(0)) {
		t.Fatalf("service tap = %v, want unchanged (canBeSelected false)", m.ChatSelection)
	}

	m, _ = Update(m, ChatPressed{X: 400, Y: 100})
	m, _ = Update(m, ChatReleased{X: 400, Y: 100})
	if !reflect.DeepEqual(m.ChatSelection, selectionOf(0)) {
		t.Fatalf("service time tap = %v, want unchanged", m.ChatSelection)
	}
}

func TestChatMarginPressTimeReleaseSelects(t *testing.T) {
	m := chatItemModel(t, 3)
	m, _ = Update(m, ChatPressed{X: 100, Y: 58})
	m, _ = Update(m, ChatReleased{X: 190, Y: 45})
	if !reflect.DeepEqual(m.ChatSelection, selectionOf(0)) {
		t.Fatalf("margin press + time release = %v, want row 0", m.ChatSelection)
	}
}

func TestChatMouseDragDegradesPrepareDrag(t *testing.T) {
	m := chatItemModel(t, 3)
	m, _ = Update(m, ChatPressed{X: 190, Y: 45})
	m, _ = Update(m, ChatDragged{X: 190, Y: 60})
	if p := m.ChatPress; p.Action != ChatPressDragging {
		t.Fatalf("dragged press action = %d, want Dragging", p.Action)
	}
	m, _ = Update(m, ChatReleased{X: 190, Y: 60})
	if m.ChatSelection.HasSelectedItems() {
		t.Fatalf("degraded release selected = %v, want none", m.ChatSelection)
	}
}

func TestChatMouseDragDegradesPrepareSelect(t *testing.T) {
	m := chatItemModel(t, 3)
	m.ChatSelection = selectionOf(0)
	m, _ = Update(m, ChatPressed{X: 100, Y: 58})
	if p := m.ChatPress; p.Action != ChatPressPrepareSelect {
		t.Fatalf("setup action = %d, want PrepareSelect", p.Action)
	}
	m, _ = Update(m, ChatDragged{X: 100, Y: 70})
	if p := m.ChatPress; p.Action != ChatPressSelecting {
		t.Fatalf("dragged press action = %d, want Selecting", p.Action)
	}
	m, _ = Update(m, ChatReleased{X: 100, Y: 70})
	if !reflect.DeepEqual(m.ChatSelection, selectionOf(0)) {
		t.Fatalf("degraded release = %v, want unchanged", m.ChatSelection)
	}
}

func TestChatMouseRowChangeDegrades(t *testing.T) {
	m := chatItemModel(t, 3)
	m, _ = Update(m, ChatPressed{X: 100, Y: 56})
	if p := m.ChatPress; p.Action != ChatPressPrepareSelect {
		t.Fatalf("setup action = %d, want PrepareSelect", p.Action)
	}
	m, _ = Update(m, ChatDragged{X: 100, Y: 60})
	if p := m.ChatPress; p.Action != ChatPressSelecting {
		t.Fatalf("row change action = %d, want Selecting", p.Action)
	}
}

func TestChatTouchTapOnTimeSelects(t *testing.T) {
	m := chatItemModel(t, 3)
	m, _ = Update(m, ChatPressed{X: 190, Y: 45, Touch: true, Now: 1000})
	if m.ChatPress.Row != -1 {
		t.Fatalf("touch press must not record an item press: %+v", m.ChatPress)
	}
	m, _ = Update(m, ChatDragged{X: 190, Y: 46, Now: 1010})
	m, _ = Update(m, ChatReleased{X: 190, Y: 46, Now: 1030})
	if !reflect.DeepEqual(m.ChatSelection, selectionOf(0)) {
		t.Fatalf("touch tap on time = %v, want row 0", m.ChatSelection)
	}
	if m.ChatTouch.Active {
		t.Fatal("tap must reset the touch drag")
	}
}

func TestChatTouchTapOnBodyNoSelection(t *testing.T) {
	m := chatItemModel(t, 3)
	m, _ = Update(m, ChatPressed{X: 100, Y: 30, Touch: true, Now: 1000})
	m, _ = Update(m, ChatReleased{X: 100, Y: 30, Now: 1030})
	if m.ChatSelection.HasSelectedItems() {
		t.Fatalf("touch body tap = %v, want none", m.ChatSelection)
	}
}

func TestChatTouchScrollDoesNotSelect(t *testing.T) {
	m := chatItemModel(t, 3)
	m, _ = Update(m, ChatPressed{X: 400, Y: 100, Touch: true, Now: 1000})
	m, _ = Update(m, ChatDragged{X: 400, Y: 80, Now: 1010})
	m, _ = Update(m, ChatReleased{X: 400, Y: 80, Now: 1030})
	if m.ChatSelection.HasSelectedItems() {
		t.Fatalf("touch scroll selected = %v, want none", m.ChatSelection)
	}
	if m.ChatPress.Row != -1 {
		t.Fatalf("touch press leaked an item press: %+v", m.ChatPress)
	}
}

func TestChatPressBelowItemsNoState(t *testing.T) {
	items := []history.Item{
		{Kind: history.ItemMessage, Text: "m", TimeText: "10:00"},
		{Kind: history.ItemMessage, Text: "m2", TimeText: "10:01"},
	}
	hits := []history.HitBox{
		{Item: history.Geometry{Left: 20, Top: 5, Width: 200, Height: 30},
			Time: history.Geometry{Left: 191, Top: 25, Width: 30, Height: 13}},
		{Item: history.Geometry{Left: 20, Top: 45, Width: 200, Height: 30},
			Time: history.Geometry{Left: 191, Top: 65, Width: 30, Height: 13}},
	}
	m, _ := Update(InitialModel(), Resized{Width: 800, Height: 120})
	m, _ = Update(m, ChatLoaded{Items: items})
	m, _ = Update(m, ChatMeasured{Heights: []int{40, 40}, Hits: hits})
	m, _ = Update(m, ChatPressed{X: 100, Y: 90})
	if m.ChatPress.Row != -1 {
		t.Fatalf("press below all rows = %+v, want no row", m.ChatPress)
	}
	m, _ = Update(m, ChatReleased{X: 100, Y: 90})
	if m.ChatSelection.HasSelectedItems() {
		t.Fatal("release without a press must select nothing")
	}
}

func TestChatPressCancelClearsPress(t *testing.T) {
	m := chatItemModel(t, 3)
	m, _ = Update(m, ChatPressed{X: 190, Y: 45})
	m, _ = Update(m, ChatPressCanceled{})
	if m.ChatPress.Row != -1 {
		t.Fatalf("cancel must clear the press: %+v", m.ChatPress)
	}
	m, _ = Update(m, ChatReleased{X: 190, Y: 45})
	if m.ChatSelection.HasSelectedItems() {
		t.Fatal("release after cancel must select nothing")
	}
}

func TestChatBarPressLeavesNoItemPress(t *testing.T) {
	m := chatItemModel(t, 3)
	chatW := m.Columns().Chat
	m, _ = Update(m, ChatPressed{X: chatW - 5, Y: 60})
	if !m.ChatBar.Dragging {
		t.Fatal("setup: press on the strip with a visible thumb must drag the bar")
	}
	if m.ChatPress.Row != -1 {
		t.Fatalf("bar press recorded an item press: %+v", m.ChatPress)
	}
	m, _ = Update(m, ChatReleased{X: chatW - 5, Y: 60})
	if m.ChatSelection.HasSelectedItems() {
		t.Fatal("bar release must select nothing")
	}
}

func TestChatHiddenThumbPressFallsToItem(t *testing.T) {
	m := chatModel(t, 800, 300, make([]history.Item, 1), []int{100})
	chatW := m.Columns().Chat
	m, _ = Update(m, ChatPressed{X: chatW - 5, Y: 50})
	if m.ChatBar.Dragging {
		t.Fatal("hidden thumb must not drag the bar")
	}
	if m.ChatPress.Row != 0 {
		t.Fatalf("hidden-thumb strip press = %+v, want the item press (pass-through)", m.ChatPress)
	}
}

func TestChatMeasuredStoresHits(t *testing.T) {
	m, _ := Update(InitialModel(), Resized{Width: 800, Height: 120})
	m, _ = Update(m, ChatLoaded{Items: make([]history.Item, 1)})
	if m.Chat.Hits != nil {
		t.Fatalf("hits not invalidated on reload: %+v", m.Chat.Hits)
	}
	hits := []history.HitBox{{Item: history.Geometry{Left: 20, Top: 5, Width: 200, Height: 50}}}
	m, _ = Update(m, ChatMeasured{Heights: []int{60}, Hits: hits})
	if len(m.Chat.Hits) != 1 || m.Chat.Hits[0] != hits[0] {
		t.Fatalf("hits not stored: %+v", m.Chat.Hits)
	}
}

func TestChatNoHitBoxesNoTimeCursor(t *testing.T) {
	m := chatModel(t, 800, 120, make([]history.Item, 3), []int{60, 60, 60})
	m, _ = Update(m, ChatPressed{X: 190, Y: 45})
	p := m.ChatPress
	if p.Row != 0 || p.Inside || p.Time {
		t.Fatalf("press without hit boxes = %+v, want row 0 outside with no cursor", p)
	}
	m, _ = Update(m, ChatReleased{X: 190, Y: 45})
	if m.ChatSelection.HasSelectedItems() {
		t.Fatal("release without hit boxes must select nothing")
	}
}

func TestChatSelectionClearedOnReload(t *testing.T) {
	m := chatItemModel(t, 3)
	m.ChatSelection = selectionOf(0)
	m, _ = Update(m, ChatLoaded{Items: make([]history.Item, 3)})
	if m.ChatSelection.HasSelectedItems() {
		t.Fatalf("reload kept the selection = %v, want cleared", m.ChatSelection)
	}
}

package cores

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/gotd/td/tg"
)

func businessRecipientsFromWire(r tg.BusinessRecipients) map[string]interface{} {
	return map[string]interface{}{
		"existing_chats":   r.ExistingChats,
		"new_chats":        r.NewChats,
		"contacts":         r.Contacts,
		"non_contacts":     r.NonContacts,
		"exclude_selected": r.ExcludeSelected,
	}
}

func quickRepliesFromWire(res *tg.MessagesQuickReplies) []QuickReplyInfo {
	if res == nil {
		return nil
	}
	texts := make(map[int]string, len(res.Messages))
	for _, m := range res.Messages {
		if msg, ok := m.(*tg.Message); ok {
			texts[msg.ID] = msg.Message
		}
	}
	out := make([]QuickReplyInfo, 0, len(res.QuickReplies))
	for _, q := range res.QuickReplies {
		out = append(out, QuickReplyInfo{
			ID:         q.ShortcutID,
			Name:       q.Shortcut,
			Count:      q.Count,
			TopMessage: texts[q.TopMessage],
		})
	}
	return out
}

func timezonesFromWire(res *tg.HelpTimezonesList) []TimezoneInfo {
	if res == nil {
		return nil
	}
	out := make([]TimezoneInfo, 0, len(res.Timezones))
	for _, tz := range res.Timezones {
		out = append(out, TimezoneInfo{ID: tz.ID, Name: tz.Name, UtcOffset: tz.UtcOffset})
	}
	return out
}

func businessInfoFromWire(full *tg.UserFull, self *tg.User, replies []QuickReplyInfo) map[string]interface{} {
	out := map[string]interface{}{}
	if self != nil {
		out["premium"] = self.Premium
	}
	if wh, ok := full.GetBusinessWorkHours(); ok {
		intervals := make([]map[string]interface{}, 0, len(wh.WeeklyOpen))
		for _, wo := range wh.WeeklyOpen {
			intervals = append(intervals, map[string]interface{}{
				"start": wo.StartMinute,
				"end":   wo.EndMinute,
			})
		}
		out["work_hours"] = map[string]interface{}{
			"timezone_id": wh.TimezoneID,
			"open_now":    wh.OpenNow,
			"weekly_open": intervals,
		}
	}
	if loc, ok := full.GetBusinessLocation(); ok {
		m := map[string]interface{}{"address": loc.Address}
		if gp, ok := loc.GetGeoPoint(); ok {
			if pt, ok := gp.(*tg.GeoPoint); ok {
				m["lat"], m["lon"] = pt.Lat, pt.Long
			}
		}
		out["location"] = m
	}
	byID := make(map[int]QuickReplyInfo, len(replies))
	for _, q := range replies {
		byID[q.ID] = q
	}
	if g, ok := full.GetBusinessGreetingMessage(); ok {
		m := businessRecipientsFromWire(g.Recipients)
		m["shortcut_id"] = g.ShortcutID
		m["no_activity_days"] = g.NoActivityDays
		m["message"] = byID[g.ShortcutID].TopMessage
		out["greeting"] = m
	}
	if aw, ok := full.GetBusinessAwayMessage(); ok {
		m := businessRecipientsFromWire(aw.Recipients)
		m["shortcut_id"] = aw.ShortcutID
		m["offline_only"] = aw.OfflineOnly
		switch sch := aw.Schedule.(type) {
		case *tg.BusinessAwayMessageScheduleAlways:
			m["schedule"] = "always"
		case *tg.BusinessAwayMessageScheduleOutsideWorkHours:
			m["schedule"] = "outside_work_hours"
		case *tg.BusinessAwayMessageScheduleCustom:
			m["schedule"] = "custom"
			m["start_date"] = sch.StartDate
			m["end_date"] = sch.EndDate
		}
		m["message"] = byID[aw.ShortcutID].TopMessage
		out["away"] = m
	}
	if intro, ok := full.GetBusinessIntro(); ok {
		out["intro"] = map[string]interface{}{
			"title":       intro.Title,
			"description": intro.Description,
		}
	}
	return out
}

func buildBusinessRecipients(data map[string]interface{}) (tg.InputBusinessRecipients, error) {
	r := tg.InputBusinessRecipients{
		ExistingChats:   dataBool(data, "existing_chats"),
		NewChats:        dataBool(data, "new_chats"),
		Contacts:        dataBool(data, "contacts"),
		NonContacts:     dataBool(data, "non_contacts"),
		ExcludeSelected: dataBool(data, "exclude_selected"),
	}
	if !r.ExistingChats && !r.NewChats && !r.Contacts && !r.NonContacts {
		return r, fmt.Errorf("select at least one recipient group")
	}
	return r, nil
}

func buildWorkHours(data map[string]interface{}) (*tg.BusinessWorkHours, error) {
	raw, _ := data["weekly_open"].([]interface{})
	if len(raw) == 0 {
		return nil, nil
	}
	wh := &tg.BusinessWorkHours{
		TimezoneID: dataStr(data, "timezone_id"),
		WeeklyOpen: make([]tg.BusinessWeeklyOpen, 0, len(raw)),
	}
	for _, it := range raw {
		iv, ok := it.(map[string]interface{})
		if !ok {
			continue
		}
		s, e := dataInt(iv, "start"), dataInt(iv, "end")
		if s < 0 || e <= s || e > 8*24*60 {
			return nil, fmt.Errorf("invalid weekly interval %d..%d", s, e)
		}
		wh.WeeklyOpen = append(wh.WeeklyOpen, tg.BusinessWeeklyOpen{StartMinute: s, EndMinute: e})
	}
	if len(wh.WeeklyOpen) == 0 {
		return nil, nil
	}
	return wh, nil
}

func buildLocation(data map[string]interface{}) (address string, geo *tg.InputGeoPoint, err error) {
	address = strings.TrimSpace(dataStr(data, "address"))
	lat, hasLat := dataFloat(data, "lat")
	lon, hasLon := dataFloat(data, "lon")
	if address == "" && !hasLat && !hasLon {
		return "", nil, nil
	}
	if address == "" {
		return "", nil, fmt.Errorf("address is required")
	}
	if len(address) > 96*4 {
		return "", nil, fmt.Errorf("address too long (max 96 chars)")
	}
	if hasLat || hasLon {
		geo = &tg.InputGeoPoint{Lat: lat, Long: lon}
	}
	return address, geo, nil
}

func buildGreeting(data map[string]interface{}) (*tg.InputBusinessGreetingMessage, error) {
	if len(data) == 0 {
		return nil, nil
	}
	recipients, err := buildBusinessRecipients(data)
	if err != nil {
		return nil, err
	}
	days := dataInt(data, "no_activity_days")
	switch days {
	case 0:
		days = 7
	case 7, 14, 21, 28:
	default:
		return nil, fmt.Errorf("inactivity days must be 7, 14, 21 or 28")
	}
	return &tg.InputBusinessGreetingMessage{
		ShortcutID:     dataInt(data, "shortcut_id"),
		Recipients:     recipients,
		NoActivityDays: days,
	}, nil
}

func buildAway(data map[string]interface{}) (*tg.InputBusinessAwayMessage, error) {
	if len(data) == 0 {
		return nil, nil
	}
	recipients, err := buildBusinessRecipients(data)
	if err != nil {
		return nil, err
	}
	msg := &tg.InputBusinessAwayMessage{
		OfflineOnly: dataBool(data, "offline_only"),
		ShortcutID:  dataInt(data, "shortcut_id"),
		Recipients:  recipients,
	}
	switch dataStr(data, "schedule") {
	case "", "always":
		msg.Schedule = &tg.BusinessAwayMessageScheduleAlways{}
	case "outside_work_hours":
		msg.Schedule = &tg.BusinessAwayMessageScheduleOutsideWorkHours{}
	case "custom":
		s, e := dataInt(data, "start_date"), dataInt(data, "end_date")
		if s <= 0 || e <= s {
			return nil, fmt.Errorf("custom schedule needs a valid date range")
		}
		msg.Schedule = &tg.BusinessAwayMessageScheduleCustom{StartDate: s, EndDate: e}
	default:
		return nil, fmt.Errorf("unknown schedule %q", dataStr(data, "schedule"))
	}
	return msg, nil
}

func buildIntro(data map[string]interface{}) (*tg.InputBusinessIntro, error) {
	if len(data) == 0 {
		return nil, nil
	}
	title := strings.TrimSpace(dataStr(data, "title"))
	if title == "" {
		return nil, nil
	}
	desc := strings.TrimSpace(dataStr(data, "description"))
	if desc == "" {
		return nil, fmt.Errorf("description is required")
	}
	if len(title) > 32*4 || len(desc) > 128*4 {
		return nil, fmt.Errorf("intro text too long (title 32, description 128 chars)")
	}
	return &tg.InputBusinessIntro{Title: title, Description: desc}, nil
}

func sanitizeShortcutName(name, fallback string) string {
	var b strings.Builder
	for _, r := range strings.TrimSpace(name) {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r >= '0' && r <= '9', r == '_', r == '-':
			b.WriteRune(r)
		}
		if b.Len() >= 12 {
			break
		}
	}
	if b.Len() == 0 {
		return fallback
	}
	return b.String()
}

func dataBool(m map[string]interface{}, k string) bool {
	switch v := m[k].(type) {
	case bool:
		return v
	case string:
		return v == "true" || v == "1"
	case float64:
		return v != 0
	case int:
		return v != 0
	}
	return false
}

func dataStr(m map[string]interface{}, k string) string {
	if m == nil {
		return ""
	}
	switch v := m[k].(type) {
	case string:
		return v
	case fmt.Stringer:
		return v.String()
	}
	return ""
}

func dataInt(m map[string]interface{}, k string) int {
	switch v := m[k].(type) {
	case int:
		return v
	case int64:
		return int(v)
	case float64:
		return int(v)
	case string:
		var n int
		fmt.Sscanf(v, "%d", &n)
		return n
	}
	return 0
}

func dataFloat(m map[string]interface{}, k string) (float64, bool) {
	switch v := m[k].(type) {
	case float64:
		return v, true
	case float32:
		return float64(v), true
	case int:
		return float64(v), true
	case int64:
		return float64(v), true
	case string:
		var f float64
		if _, err := fmt.Sscanf(strings.TrimSpace(v), "%g", &f); err == nil {
			return f, true
		}
	}
	return 0, false
}

func (t *TelegramCore) GetTimezones() ([]TimezoneInfo, error) {
	api, ctx, err := t.withAPI()
	if err != nil {
		return nil, err
	}
	res, err := api.HelpGetTimezonesList(ctx, 0)
	if err != nil {
		return nil, fmt.Errorf("get timezones: %w", err)
	}
	list, ok := res.(*tg.HelpTimezonesList)
	if !ok {
		return nil, nil
	}
	return timezonesFromWire(list), nil
}

func (t *TelegramCore) GetQuickReplies() ([]QuickReplyInfo, error) {
	api, ctx, err := t.withAPI()
	if err != nil {
		return nil, err
	}
	res, err := api.MessagesGetQuickReplies(ctx, 0)
	if err != nil {
		return nil, fmt.Errorf("get quick replies: %w", err)
	}
	list, ok := res.(*tg.MessagesQuickReplies)
	if !ok {
		return nil, nil
	}
	t.cacheEntities(list.Users, list.Chats)
	return quickRepliesFromWire(list), nil
}

func (t *TelegramCore) GetBusinessInfo() (map[string]interface{}, error) {
	api, ctx, err := t.withAPI()
	if err != nil {
		return nil, err
	}
	res, err := api.UsersGetFullUser(ctx, &tg.InputUserSelf{})
	if err != nil {
		return nil, fmt.Errorf("get business info: %w", err)
	}
	t.cacheEntities(res.Users, nil)
	var self *tg.User
	for _, u := range res.Users {
		if user, ok := u.(*tg.User); ok && user.Self {
			self = user
			break
		}
	}
	var replies []QuickReplyInfo
	if qr, err := api.MessagesGetQuickReplies(ctx, 0); err == nil {
		if list, ok := qr.(*tg.MessagesQuickReplies); ok {
			t.cacheEntities(list.Users, list.Chats)
			replies = quickRepliesFromWire(list)
		}
	}
	return businessInfoFromWire(&res.FullUser, self, replies), nil
}

func (t *TelegramCore) SetBusinessFeature(feature string, data map[string]interface{}) error {
	api, ctx, err := t.withAPI()
	if err != nil {
		return err
	}
	switch feature {
	case "work_hours":
		req := &tg.AccountUpdateBusinessWorkHoursRequest{}
		wh, err := buildWorkHours(data)
		if err != nil {
			return err
		}
		if wh != nil {
			req.SetBusinessWorkHours(*wh)
		}
		if _, err := api.AccountUpdateBusinessWorkHours(ctx, req); err != nil {
			return fmt.Errorf("update work hours: %w", err)
		}
		return nil
	case "location":
		req := &tg.AccountUpdateBusinessLocationRequest{}
		address, geo, err := buildLocation(data)
		if err != nil {
			return err
		}
		if address != "" {
			req.SetAddress(address)
		}
		if geo != nil {
			req.SetGeoPoint(geo)
		}
		if _, err := api.AccountUpdateBusinessLocation(ctx, req); err != nil {
			return fmt.Errorf("update business location: %w", err)
		}
		return nil
	case "greeting":
		if len(data) == 0 {
			_, err := api.AccountUpdateBusinessGreetingMessage(ctx, &tg.AccountUpdateBusinessGreetingMessageRequest{})
			return err
		}
		msg, err := buildGreeting(data)
		if err != nil {
			return err
		}
		if msg == nil {
			_, err := api.AccountUpdateBusinessGreetingMessage(ctx, &tg.AccountUpdateBusinessGreetingMessageRequest{})
			return err
		}
		id, err := t.ensureShortcutMessage(api, ctx, msg.ShortcutID, dataStr(data, "message"),
			sanitizeShortcutName(dataStr(data, "shortcut_name"), "greeting"))
		if err != nil {
			return err
		}
		msg.ShortcutID = id
		req := &tg.AccountUpdateBusinessGreetingMessageRequest{}
		req.SetMessage(*msg)
		if _, err := api.AccountUpdateBusinessGreetingMessage(ctx, req); err != nil {
			return fmt.Errorf("update greeting message: %w", err)
		}
		return nil
	case "away":
		if len(data) == 0 {
			_, err := api.AccountUpdateBusinessAwayMessage(ctx, &tg.AccountUpdateBusinessAwayMessageRequest{})
			return err
		}
		msg, err := buildAway(data)
		if err != nil {
			return err
		}
		if msg == nil {
			_, err := api.AccountUpdateBusinessAwayMessage(ctx, &tg.AccountUpdateBusinessAwayMessageRequest{})
			return err
		}
		id, err := t.ensureShortcutMessage(api, ctx, msg.ShortcutID, dataStr(data, "message"),
			sanitizeShortcutName(dataStr(data, "shortcut_name"), "away"))
		if err != nil {
			return err
		}
		msg.ShortcutID = id
		req := &tg.AccountUpdateBusinessAwayMessageRequest{}
		req.SetMessage(*msg)
		if _, err := api.AccountUpdateBusinessAwayMessage(ctx, req); err != nil {
			return fmt.Errorf("update away message: %w", err)
		}
		return nil
	case "intro":
		req := &tg.AccountUpdateBusinessIntroRequest{}
		intro, err := buildIntro(data)
		if err != nil {
			return err
		}
		if intro != nil {
			req.SetIntro(*intro)
		}
		if _, err := api.AccountUpdateBusinessIntro(ctx, req); err != nil {
			return fmt.Errorf("update intro: %w", err)
		}
		return nil
	default:
		return fmt.Errorf("unknown business feature %q", feature)
	}
}

func (t *TelegramCore) ensureShortcutMessage(api *tg.Client, ctx context.Context, shortcutID int, text, name string) (int, error) {
	if text = strings.TrimSpace(text); text == "" {
		return 0, fmt.Errorf("message text is required")
	}
	if shortcutID > 0 {
		if res, err := api.MessagesGetQuickReplyMessages(ctx, &tg.MessagesGetQuickReplyMessagesRequest{
			ShortcutID: shortcutID,
		}); err == nil {
			if msgs, ok := res.(*tg.MessagesMessages); ok {
				ids := make([]int, 0, len(msgs.Messages))
				for _, m := range msgs.Messages {
					if msg, ok := m.(*tg.Message); ok {
						ids = append(ids, msg.ID)
					}
				}
				if len(ids) > 0 {
					_, _ = api.MessagesDeleteQuickReplyMessages(ctx, &tg.MessagesDeleteQuickReplyMessagesRequest{
						ShortcutID: shortcutID, ID: ids,
					})
				}
			}
		}
		if _, err := api.MessagesSendMessage(ctx, &tg.MessagesSendMessageRequest{
			Peer:               &tg.InputPeerSelf{},
			Message:            text,
			RandomID:           time.Now().UnixNano(),
			QuickReplyShortcut: &tg.InputQuickReplyShortcutID{ShortcutID: shortcutID},
		}); err != nil {
			return 0, fmt.Errorf("save quick reply message: %w", err)
		}
		return shortcutID, nil
	}
	if _, err := api.MessagesSendMessage(ctx, &tg.MessagesSendMessageRequest{
		Peer:               &tg.InputPeerSelf{},
		Message:            text,
		RandomID:           time.Now().UnixNano(),
		QuickReplyShortcut: &tg.InputQuickReplyShortcut{Shortcut: name},
	}); err != nil {
		return 0, fmt.Errorf("create quick reply: %w", err)
	}
	qr, err := api.MessagesGetQuickReplies(ctx, 0)
	if err != nil {
		return 0, fmt.Errorf("resolve new shortcut: %w", err)
	}
	list, ok := qr.(*tg.MessagesQuickReplies)
	if !ok {
		return 0, fmt.Errorf("resolve new shortcut: empty list")
	}
	for _, q := range list.QuickReplies {
		if q.Shortcut == name {
			return q.ShortcutID, nil
		}
	}
	return 0, fmt.Errorf("created shortcut %q not found", name)
}

func (t *TelegramCore) CreateQuickReply(name, text string) (int, error) {
	api, ctx, err := t.withAPI()
	if err != nil {
		return 0, err
	}
	name = sanitizeShortcutName(name, "")
	if name == "" {
		return 0, fmt.Errorf("shortcut name is required")
	}
	if strings.TrimSpace(text) == "" {
		return 0, fmt.Errorf("message text is required")
	}
	if _, err := api.MessagesSendMessage(ctx, &tg.MessagesSendMessageRequest{
		Peer:               &tg.InputPeerSelf{},
		Message:            text,
		RandomID:           time.Now().UnixNano(),
		QuickReplyShortcut: &tg.InputQuickReplyShortcut{Shortcut: name},
	}); err != nil {
		return 0, fmt.Errorf("create quick reply: %w", err)
	}
	res, err := api.MessagesGetQuickReplies(ctx, 0)
	if err != nil {
		return 0, fmt.Errorf("resolve shortcut: %w", err)
	}
	if list, ok := res.(*tg.MessagesQuickReplies); ok {
		for _, q := range list.QuickReplies {
			if q.Shortcut == name {
				return q.ShortcutID, nil
			}
		}
	}
	return 0, nil
}

func (t *TelegramCore) RenameQuickReply(id int, name string) error {
	api, ctx, err := t.withAPI()
	if err != nil {
		return err
	}
	name = sanitizeShortcutName(name, "")
	if name == "" {
		return fmt.Errorf("shortcut name is required")
	}
	if _, err := api.MessagesEditQuickReplyShortcut(ctx, &tg.MessagesEditQuickReplyShortcutRequest{
		ShortcutID: id,
		Shortcut:   name,
	}); err != nil {
		return fmt.Errorf("rename quick reply: %w", err)
	}
	return nil
}

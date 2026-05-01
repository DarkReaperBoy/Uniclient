// Bridge converters — hand-written because Go↔Proto field mappings have
// time.Time, string-enums, *bool, and other non-trivial conversions.
package bridge

import (
	"encoding/json"
	"time"

	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"

	pb "uniclient/proto"
	"uniclient/cores"
)

// ═══════════════════════════════════════════════════════════════════
// Enum converters (string ↔ proto int)
// ═══════════════════════════════════════════════════════════════════

var chatTypeToProto = map[cores.ChatType]pb.ChatType{
	cores.ChatTypeDM:      pb.ChatType_CHAT_TYPE_DM,
	cores.ChatTypeGroup:   pb.ChatType_CHAT_TYPE_GROUP,
	cores.ChatTypeChannel: pb.ChatType_CHAT_TYPE_CHANNEL,
	cores.ChatTypeTopic:   pb.ChatType_CHAT_TYPE_TOPIC,
}

var protoChatType = map[pb.ChatType]cores.ChatType{
	pb.ChatType_CHAT_TYPE_DM:      cores.ChatTypeDM,
	pb.ChatType_CHAT_TYPE_GROUP:   cores.ChatTypeGroup,
	pb.ChatType_CHAT_TYPE_CHANNEL: cores.ChatTypeChannel,
	pb.ChatType_CHAT_TYPE_TOPIC:   cores.ChatTypeTopic,
}

var msgStatusToProto = map[cores.MessageStatus]pb.MessageStatus{
	cores.MessageStatusSending:   pb.MessageStatus_MESSAGE_STATUS_SENDING,
	cores.MessageStatusSent:      pb.MessageStatus_MESSAGE_STATUS_SENT,
	cores.MessageStatusDelivered: pb.MessageStatus_MESSAGE_STATUS_DELIVERED,
	cores.MessageStatusRead:      pb.MessageStatus_MESSAGE_STATUS_READ,
	cores.MessageStatusFailed:    pb.MessageStatus_MESSAGE_STATUS_FAILED,
}

var callStateToProto = map[cores.CallState]pb.CallState{
	cores.CallStateRinging:    pb.CallState_CALL_STATE_RINGING,
	cores.CallStateConnecting: pb.CallState_CALL_STATE_CONNECTING,
	cores.CallStateActive:     pb.CallState_CALL_STATE_ACTIVE,
	cores.CallStateEnded:      pb.CallState_CALL_STATE_ENDED,
}

var authModeToProto = map[cores.AuthMode]pb.AuthMode{
	cores.AuthModeBot:  pb.AuthMode_AUTH_MODE_BOT,
	cores.AuthModeUser: pb.AuthMode_AUTH_MODE_USER,
}

var protoAuthMode = map[pb.AuthMode]cores.AuthMode{
	pb.AuthMode_AUTH_MODE_BOT:  cores.AuthModeBot,
	pb.AuthMode_AUTH_MODE_USER: cores.AuthModeUser,
}

var updateTypeToProto = map[cores.UpdateType]pb.UpdateType{
	cores.UpdateNewMessage:    pb.UpdateType_UPDATE_TYPE_NEW_MESSAGE,
	cores.UpdateEditMessage:   pb.UpdateType_UPDATE_TYPE_EDIT_MESSAGE,
	cores.UpdateDeleteMessage: pb.UpdateType_UPDATE_TYPE_DELETE_MESSAGE,
	cores.UpdateReadState:     pb.UpdateType_UPDATE_TYPE_READ_STATE,
	cores.UpdateUserStatus:    pb.UpdateType_UPDATE_TYPE_USER_STATUS,
	cores.UpdateTyping:        pb.UpdateType_UPDATE_TYPE_TYPING,
	cores.UpdateCallState:     pb.UpdateType_UPDATE_TYPE_CALL_STATE,
	cores.UpdateGroupMembers:  pb.UpdateType_UPDATE_TYPE_GROUP_MEMBERS,
	cores.UpdateVerification:  pb.UpdateType_UPDATE_TYPE_VERIFICATION,
	cores.UpdateConnectivity:  pb.UpdateType_UPDATE_TYPE_CONNECTIVITY,
}

// ═══════════════════════════════════════════════════════════════════
// Time helpers
// ═══════════════════════════════════════════════════════════════════

func timeToMS(t time.Time) int64 {
	if t.IsZero() {
		return 0
	}
	return t.UnixMilli()
}

func timePtrToMS(t *time.Time) int64 {
	if t == nil {
		return 0
	}
	return t.UnixMilli()
}

func msToTime(ms int64) time.Time {
	if ms == 0 {
		return time.Time{}
	}
	return time.UnixMilli(ms)
}

func msToTimePtr(ms int64) *time.Time {
	if ms == 0 {
		return nil
	}
	t := time.UnixMilli(ms)
	return &t
}

// ═══════════════════════════════════════════════════════════════════
// JSON helpers (for map[string]interface{} ↔ bytes)
// ═══════════════════════════════════════════════════════════════════

func mapToBytes(m map[string]interface{}) []byte {
	if m == nil {
		return nil
	}
	b, _ := json.Marshal(m)
	return b
}

func bytesToMap(data []byte) map[string]interface{} {
	if len(data) == 0 {
		return nil
	}
	var m map[string]interface{}
	_ = json.Unmarshal(data, &m)
	return m
}

func mapStringToBytes(m map[string]string) []byte {
	if m == nil {
		return nil
	}
	b, _ := json.Marshal(m)
	return b
}

func bytesToMapString(data []byte) map[string]string {
	if len(data) == 0 {
		return nil
	}
	var m map[string]string
	_ = json.Unmarshal(data, &m)
	return m
}

func sliceMapToBytes(ms []map[string]interface{}) []byte {
	if ms == nil {
		return nil
	}
	b, _ := json.Marshal(ms)
	return b
}

func anyToBytes(v interface{}) []byte {
	if v == nil {
		return nil
	}
	b, _ := json.Marshal(v)
	return b
}

func bytesToSliceMapString(data []byte) []map[string]string {
	if len(data) == 0 {
		return nil
	}
	var ms []map[string]string
	_ = json.Unmarshal(data, &ms)
	return ms
}

func bytesToSliceMap(data []byte) []map[string]interface{} {
	if len(data) == 0 {
		return nil
	}
	var ms []map[string]interface{}
	_ = json.Unmarshal(data, &ms)
	return ms
}

func bytesToNestedSliceMapString(data []byte) [][]map[string]string {
	if len(data) == 0 {
		return nil
	}
	var ms [][]map[string]string
	_ = json.Unmarshal(data, &ms)
	return ms
}

func bytesToMapStringMapStringString(data []byte) map[string]map[string]string {
	if len(data) == 0 {
		return nil
	}
	var m map[string]map[string]string
	_ = json.Unmarshal(data, &m)
	return m
}

func bytesToMapIntString(data []byte) map[int]string {
	if len(data) == 0 {
		return nil
	}
	var m map[int]string
	_ = json.Unmarshal(data, &m)
	return m
}

func intsToInt64s(is []int) []int64 {
	out := make([]int64, len(is))
	for i, v := range is {
		out[i] = int64(v)
	}
	return out
}

func int64sToInts(is []int64) []int {
	out := make([]int, len(is))
	for i, v := range is {
		out[i] = int(v)
	}
	return out
}

func anyFromBytes(data []byte) interface{} {
	if len(data) == 0 {
		return nil
	}
	var v interface{}
	_ = json.Unmarshal(data, &v)
	return v
}

func bytesToSliceInterface(data []byte) []interface{} {
	if len(data) == 0 {
		return nil
	}
	var v []interface{}
	_ = json.Unmarshal(data, &v)
	return v
}

func int16SliceToBytes(s []int16) []byte {
	b, _ := json.Marshal(s)
	return b
}

func uint16SliceToBytes(s []uint16) []byte {
	b, _ := json.Marshal(s)
	return b
}

func bytesToInt16Slice(data []byte) []int16 {
	if len(data) == 0 {
		return nil
	}
	var s []int16
	_ = json.Unmarshal(data, &s)
	return s
}

func bytesToUint16Slice(data []byte) []uint16 {
	if len(data) == 0 {
		return nil
	}
	var s []uint16
	_ = json.Unmarshal(data, &s)
	return s
}

func float32SliceTo3(s []float32) [3]float32 {
	var out [3]float32
	for i := 0; i < 3 && i < len(s); i++ {
		out[i] = s[i]
	}
	return out
}

func bytesToMapStringMapStringMapStringInterface(data []byte) map[string]map[string]map[string]interface{} {
	if len(data) == 0 {
		return nil
	}
	var m map[string]map[string]map[string]interface{}
	_ = json.Unmarshal(data, &m)
	return m
}

// ═══════════════════════════════════════════════════════════════════
// Shared type converters
// ═══════════════════════════════════════════════════════════════════

// --- AuthConfig ---

func ProtoToAuthConfig(a *pb.AuthConfig) cores.AuthConfig {
	if a == nil {
		return cores.AuthConfig{}
	}
	return cores.AuthConfig{
		Mode:       protoAuthMode[a.Mode],
		BotToken:   a.BotToken,
		Phone:      a.Phone,
		OTP:        a.Otp,
		Password2F: a.Password_2F,
		Extra:      a.Extra,
	}
}

// --- PaginationOpts ---

func ProtoToPaginationOpts(p *pb.PaginationOpts) cores.PaginationOpts {
	if p == nil {
		return cores.PaginationOpts{}
	}
	return cores.PaginationOpts{Limit: int(p.Limit), Offset: p.Offset}
}

// --- User ---

func UserToProto(u *cores.User) *pb.User {
	if u == nil {
		return nil
	}
	return &pb.User{
		Id: u.ID, Username: u.Username, DisplayName: u.DisplayName,
		Phone: u.Phone, AvatarUrl: u.AvatarURL, AvatarB64: u.AvatarB64,
		IsBot: u.IsBot, IsOnline: u.IsOnline,
		LastSeenMs: timePtrToMS(u.LastSeen),
		Platform:   u.Platform,
	}
}

func ProtoToUser(u *pb.User) *cores.User {
	if u == nil {
		return nil
	}
	return &cores.User{
		ID: u.Id, Username: u.Username, DisplayName: u.DisplayName,
		Phone: u.Phone, AvatarURL: u.AvatarUrl, AvatarB64: u.AvatarB64,
		IsBot: u.IsBot, IsOnline: u.IsOnline,
		LastSeen: msToTimePtr(u.LastSeenMs),
		Platform: u.Platform,
	}
}

func UsersToProto(us []cores.User) []*pb.User {
	out := make([]*pb.User, len(us))
	for i := range us {
		out[i] = UserToProto(&us[i])
	}
	return out
}

// --- FileRef ---

func FileRefToProto(f *cores.FileRef) *pb.FileRef {
	if f == nil {
		return nil
	}
	return &pb.FileRef{
		Id: f.ID, Name: f.Name, MimeType: f.MimeType,
		Size: f.Size, Url: f.URL, ThumbB64: f.ThumbB64, Extra: f.Extra,
	}
}

func ProtoToFileRef(f *pb.FileRef) *cores.FileRef {
	if f == nil {
		return nil
	}
	return &cores.FileRef{
		ID: f.Id, Name: f.Name, MimeType: f.MimeType,
		Size: f.Size, URL: f.Url, ThumbB64: f.ThumbB64, Extra: f.Extra,
	}
}

func FileRefsToProto(fs []cores.FileRef) []*pb.FileRef {
	out := make([]*pb.FileRef, len(fs))
	for i := range fs {
		out[i] = FileRefToProto(&fs[i])
	}
	return out
}

func ProtoToFileRefs(fs []*pb.FileRef) []cores.FileRef {
	out := make([]cores.FileRef, len(fs))
	for i := range fs {
		if fs[i] != nil {
			out[i] = *ProtoToFileRef(fs[i])
		}
	}
	return out
}

// --- Reaction ---

func ReactionToProto(r *cores.Reaction) *pb.Reaction {
	if r == nil {
		return nil
	}
	return &pb.Reaction{Emoji: r.Emoji, Count: int32(r.Count), ByMe: r.ByMe, PeerId: r.PeerID, PeerName: r.PeerName}
}

func ReactionsToProto(rs []cores.Reaction) []*pb.Reaction {
	out := make([]*pb.Reaction, len(rs))
	for i := range rs {
		out[i] = ReactionToProto(&rs[i])
	}
	return out
}

// --- Message ---

func MessageToProto(m *cores.Message) *pb.Message {
	if m == nil {
		return nil
	}
	extra, _ := json.Marshal(m.Extra)
	return &pb.Message{
		Id: m.ID, ChatId: m.ChatID, SenderId: m.SenderID,
		SenderName: m.SenderName, Text: m.Text,
		TimestampMs: timeToMS(m.Timestamp),
		EditedAtMs:  timePtrToMS(m.EditedAt),
		Status:      msgStatusToProto[m.Status],
		ReplyToId:   m.ReplyToID, ReplyPreview: m.ReplyPreview,
		ForwardFrom: m.ForwardFrom, IsEncrypted: m.IsEncrypted,
		DecryptFailed: m.DecryptFailed,
		Attachments:   FileRefsToProto(m.Attachments),
		Reactions:     ReactionsToProto(m.Reactions),
		IsPinned:      m.IsPinned, Platform: m.Platform,
		ExtraJson: extra,
	}
}

func ProtoToMessage(m *pb.Message) *cores.Message {
	if m == nil {
		return nil
	}
	msg := &cores.Message{
		ID: m.Id, ChatID: m.ChatId, SenderID: m.SenderId,
		SenderName: m.SenderName, Text: m.Text,
		Timestamp: msToTime(m.TimestampMs),
		EditedAt:  msToTimePtr(m.EditedAtMs),
		Status:    cores.MessageStatus(m.Status),
		ReplyToID: m.ReplyToId, ReplyPreview: m.ReplyPreview,
		ForwardFrom: m.ForwardFrom, IsEncrypted: m.IsEncrypted,
		DecryptFailed: m.DecryptFailed,
		Attachments:   ProtoToFileRefs(m.Attachments),
		IsPinned:      m.IsPinned, Platform: m.Platform,
	}
	if len(m.ExtraJson) > 0 {
		_ = json.Unmarshal(m.ExtraJson, &msg.Extra)
	}
	return msg
}

func MessagesToProto(ms []cores.Message) []*pb.Message {
	out := make([]*pb.Message, len(ms))
	for i := range ms {
		out[i] = MessageToProto(&ms[i])
	}
	return out
}

func PtrMessagesToProto(ms []*cores.Message) []*pb.Message {
	out := make([]*pb.Message, len(ms))
	for i := range ms {
		out[i] = MessageToProto(ms[i])
	}
	return out
}

// --- OutgoingMessage ---

func OutgoingMessageToProto(m *cores.OutgoingMessage) *pb.OutgoingMessage {
	if m == nil {
		return nil
	}
	extra, _ := json.Marshal(m.Extra)
	return &pb.OutgoingMessage{
		Text:        m.Text,
		ReplyToId:   m.ReplyToID,
		Attachments: FileRefsToProto(m.Attachments),
		ExtraJson:   extra,
	}
}

func ProtoToOutgoingMessage(m *pb.OutgoingMessage) *cores.OutgoingMessage {
	if m == nil {
		return nil
	}
	om := &cores.OutgoingMessage{
		Text:        m.Text,
		ReplyToID:   m.ReplyToId,
		Attachments: ProtoToFileRefs(m.Attachments),
	}
	if len(m.ExtraJson) > 0 {
		_ = json.Unmarshal(m.ExtraJson, &om.Extra)
	}
	return om
}

// --- Dialog ---

func DialogToProto(d *cores.Dialog) *pb.Dialog {
	if d == nil {
		return nil
	}
	return &pb.Dialog{
		Id: d.ID, Type: chatTypeToProto[d.Type], Title: d.Title,
		AvatarUrl: d.AvatarURL, AvatarB64: d.AvatarB64,
		LastMessage: MessageToProto(d.LastMessage),
		UnreadCount: int32(d.UnreadCount), IsMuted: d.IsMuted,
		IsPinned: d.IsPinned, IsArchived: d.IsArchived,
		MemberCount: int32(d.MemberCount), ParentId: d.ParentID,
		Platform: d.Platform,
	}
}

func DialogsToProto(ds []cores.Dialog) []*pb.Dialog {
	out := make([]*pb.Dialog, len(ds))
	for i := range ds {
		out[i] = DialogToProto(&ds[i])
	}
	return out
}

func ForumTopicsToDialogProtos(fts []cores.ForumTopic) []*pb.Dialog {
	out := make([]*pb.Dialog, len(fts))
	for i := range fts {
		out[i] = &pb.Dialog{
			Id: fts[i].ID, Title: fts[i].Title,
			Type: pb.ChatType_CHAT_TYPE_TOPIC,
			UnreadCount: int32(fts[i].UnreadCount),
			IsPinned: fts[i].IsPinned,
			ParentId: fts[i].ParentID,
		}
	}
	return out
}

// --- Folder ---

func FolderToProto(f *cores.Folder) *pb.Folder {
	if f == nil {
		return nil
	}
	return &pb.Folder{Id: f.ID, Name: f.Name, ChatIds: f.ChatIDs}
}

func FoldersToProto(fs []cores.Folder) []*pb.Folder {
	out := make([]*pb.Folder, len(fs))
	for i := range fs {
		out[i] = FolderToProto(&fs[i])
	}
	return out
}

func ProtoToFolder(f *pb.Folder) *cores.Folder {
	if f == nil {
		return nil
	}
	return &cores.Folder{ID: f.Id, Name: f.Name, ChatIDs: f.ChatIds}
}

// --- Session ---

func SessionToProto(s *cores.Session) *pb.Session {
	if s == nil {
		return nil
	}
	return &pb.Session{
		Id: s.ID, Device: s.Device, Platform: s.Platform,
		AppName: s.AppName, AppVersion: s.AppVersion,
		Ip: s.IP, Location: s.Location,
		LastActiveMs: timeToMS(s.LastActive),
		IsCurrent:    s.IsCurrent,
	}
}

func SessionsToProto(ss []cores.Session) []*pb.Session {
	out := make([]*pb.Session, len(ss))
	for i := range ss {
		out[i] = SessionToProto(&ss[i])
	}
	return out
}

// --- CallSession ---

func CallSessionToProto(c *cores.CallSession) *pb.CallSession {
	if c == nil {
		return nil
	}
	parts := make([]*pb.CallParticipant, len(c.Participants))
	for i, p := range c.Participants {
		parts[i] = &pb.CallParticipant{
			UserId: p.UserID, DisplayName: p.DisplayName,
			IsMuted: p.IsMuted, IsSpeaking: p.IsSpeaking, HasVideo: p.HasVideo,
		}
	}
	return &pb.CallSession{
		Id: c.ID, ChatId: c.ChatID, IsVideo: c.IsVideo, IsGroup: c.IsGroup,
		Participants: parts, State: callStateToProto[c.State], Meta: c.Meta,
	}
}

// --- ReadState ---

func ReadStateToProto(r *cores.ReadState) *pb.ReadState {
	if r == nil {
		return nil
	}
	return &pb.ReadState{MyLastRead: r.MyLastRead, PeerLastRead: r.PeerLastRead}
}

// --- VerificationInfo ---

func VerificationInfoToProto(v *cores.VerificationInfo) *pb.VerificationInfo {
	if v == nil {
		return nil
	}
	decimals := make([]int32, len(v.Decimals))
	for i, d := range v.Decimals {
		decimals[i] = int32(d)
	}
	return &pb.VerificationInfo{
		TransactionId: v.TransactionID, State: v.State,
		FromUser: v.FromUser, FromDevice: v.FromDevice,
		Emojis: v.Emojis, EmojiSymbols: v.EmojiSymbols,
		Decimals: decimals,
		CancelCode: v.CancelCode, CancelReason: v.CancelReason,
	}
}

// --- Update ---

func UpdateToProto(u *cores.Update) *pb.Update {
	if u == nil {
		return nil
	}
	out := &pb.Update{
		Type:         updateTypeToProto[u.Type],
		ChatId:       u.ChatID,
		Message:      MessageToProto(u.Message),
		MessageId:    u.MessageID,
		UserId:       u.UserID,
		ReadState:    ReadStateToProto(u.ReadState),
		Call:         CallSessionToProto(u.Call),
		Verification: VerificationInfoToProto(u.Verification),
		ConnState:    u.ConnState,
		Platform:     u.Platform,
	}
	if u.IsOnline != nil {
		out.HasIsOnline = true
		out.IsOnline = *u.IsOnline
	}
	return out
}

// ═══════════════════════════════════════════════════════════════════
// Generic core-specific struct converters (via JSON round-trip)
// ═══════════════════════════════════════════════════════════════════

// goToProtoJSON converts a Go struct to a proto message using JSON as intermediary.
// Works because Go JSON tags and proto field names are both snake_case.
func goToProtoJSON(goVal interface{}, dst proto.Message) error {
	data, err := json.Marshal(goVal)
	if err != nil {
		return err
	}
	return protojson.Unmarshal(data, dst)
}

// protoToGoJSON converts a proto message to a Go struct using JSON as intermediary.
func protoToGoJSON(src proto.Message, dst interface{}) error {
	data, err := protojson.Marshal(src)
	if err != nil {
		return err
	}
	return json.Unmarshal(data, dst)
}

func boolPtr(b bool) *bool { return &b }
func intPtr(i int) *int     { return &i }
func stringPtr(s string) *string { return &s }

// Suppress unused import warning.
var _ = proto.Marshal

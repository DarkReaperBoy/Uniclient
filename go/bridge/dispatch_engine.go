package bridge

import (
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/gotd/td/tg"
	"google.golang.org/protobuf/proto"

	"uniclient/cores"
	"uniclient/engine"
	pb "uniclient/proto"
)

// sanitizeUTF8 replaces invalid UTF-8 bytes with the Unicode replacement character.
// Protobuf string fields require valid UTF-8.
func sanitizeUTF8(s string) string {
	if utf8.ValidString(s) {
		return s
	}
	var b strings.Builder
	b.Grow(len(s))
	for i := 0; i < len(s); {
		r, size := utf8.DecodeRuneInString(s[i:])
		if r == utf8.RuneError && size == 1 {
			b.WriteRune('\uFFFD')
		} else {
			b.WriteRune(r)
		}
		i += size
	}
	return b.String()
}

// engineInstance is the global engine, set during Init.
var engineInstance *engine.Engine

// SetEngine sets the global engine instance for bridge dispatch.
func SetEngine(e *engine.Engine) {
	engineInstance = e
}

// dispatchEngine routes __engine method calls to the Engine.
func dispatchEngine(method string, payload []byte) ([]byte, error) {
	// Init is special — it creates the engine, so handle before nil check.
	if method == "Init" {
		var req pb.EngineInitRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		if err := InitEngine(req.ConfigDir, req.CacheDir, req.DownloadDir, req.VaultPassword); err != nil {
			return proto.Marshal(&pb.EngineInitResponse{Ok: false, Error: err.Error()})
		}
		return proto.Marshal(&pb.EngineInitResponse{Ok: true})
	}

	e := engineInstance
	if e == nil {
		return nil, fmt.Errorf("engine not initialized")
	}

	switch method {

	// ── Account management ──

	case "ListAccounts":
		accounts := e.ListAccounts()
		resp := &pb.EngineListAccountsResponse{}
		for _, a := range accounts {
			resp.Accounts = append(resp.Accounts, &pb.AccountInfo{
				Id:          a.ID,
				Platform:    a.Platform,
				DisplayName: a.DisplayName,
				Phone:       a.Phone,
				Username:    a.Username,
				AvatarPath:  a.AvatarPath,
				SortOrder:   int32(a.SortOrder),
				ConnState:   int32(a.ConnState),
				IsVerified:  a.IsVerified,
				IsPremium:   a.IsPremium,
			})
		}
		return proto.Marshal(resp)

	case "AddAccount":
		var req pb.EngineAddAccountRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		id, err := e.AddAccount(req.Platform)
		if err != nil {
			return nil, err
		}
		return proto.Marshal(&pb.EngineAddAccountResponse{AccountId: id})

	case "RemoveAccount":
		var req pb.EngineRemoveAccountRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.RemoveAccount(req.AccountId)

	case "ReorderAccounts":
		var req pb.EngineReorderAccountsRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.ReorderAccounts(req.AccountIds)

	case "ConnectAccount":
		var req pb.EngineConnectAccountRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.ConnectAccount(req.AccountId)

	case "ConnectAllAccounts":
		e.ConnectAllAccounts()
		return nil, nil

	case "DisconnectAccount":
		var req pb.EngineDisconnectAccountRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.DisconnectAccount(req.AccountId)

	// ── Auth flow ──

	case "StartAuth":
		var req pb.EngineStartAuthRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		state, err := e.StartAuth(req.AccountId)
		if err != nil {
			return nil, err
		}
		return proto.Marshal(&pb.EngineStartAuthResponse{
			State: authStateToProto(state),
		})

	case "SubmitAuthInput":
		var req pb.EngineSubmitAuthInputRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		state, err := e.SubmitAuthInput(req.AccountId, req.Input)
		if err != nil {
			return nil, err
		}
		return proto.Marshal(&pb.EngineSubmitAuthInputResponse{
			State: authStateToProto(state),
		})

	case "CancelAuth":
		var req pb.EngineCancelAuthRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		e.CancelAuth(req.AccountId)
		return nil, nil

	// ── Chat list ──

	case "GetChatList":
		var req pb.EngineGetChatListRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		var chats []engine.ChatInfo
		var err error
		if req.AccountId == "" {
			chats, err = e.GetUnifiedChatList(int(req.Limit), int(req.Offset))
		} else {
			chats, err = e.GetChatList(req.AccountId, req.Archived, int(req.Limit), int(req.Offset))
		}
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetChatListResponse{}
		for _, c := range chats {
			resp.Chats = append(resp.Chats, chatInfoToProto(&c))
		}
		return proto.Marshal(resp)

	case "SaveDraft":
		var req pb.EngineSaveDraftRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.SaveDraft(req.AccountId, req.ChatId, req.Text)

	case "MuteChat":
		var req pb.EngineMuteChatRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.MuteChat(req.AccountId, req.ChatId, req.Muted, req.DurationSeconds)

	case "PinChat":
		var req pb.EnginePinChatRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.PinChat(req.AccountId, req.ChatId, req.Pinned)

	case "SetHistoryTTL":
		var req pb.EngineSetHistoryTTLRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.SetHistoryTTL(req.AccountId, req.ChatId, int(req.Period))

	case "ArchiveChat":
		var req pb.EngineArchiveChatRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.ArchiveChat(req.AccountId, req.ChatId, req.Archived)

	case "BlockUser":
		var req pb.EngineBlockUserRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.BlockUser(req.AccountId, req.UserId)

	case "UnblockUser":
		var req pb.EngineUnblockUserRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.UnblockUser(req.AccountId, req.UserId)

	case "BanMember":
		var req pb.EngineBanMemberRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.BanMember(req.AccountId, req.ChatId, req.UserId)

	case "RemoveMember":
		var req pb.EngineRemoveMemberRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.RemoveMember(req.AccountId, req.ChatId, req.UserId)

	case "DemoteAdmin":
		var req pb.EngineDemoteAdminRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.DemoteAdmin(req.AccountId, req.ChatId, req.UserId)

	case "PromoteAdmin":
		var req pb.EnginePromoteAdminRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.PromoteAdmin(req.AccountId, req.ChatId, req.UserId)

	case "RestrictMember":
		var req pb.EngineRestrictMemberRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.RestrictMember(req.AccountId, req.ChatId, req.UserId)

	case "ReportSpam":
		var req pb.EngineLeaveChatRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.ReportSpam(req.AccountId, req.ChatId)

	case "GetLinkedChatId":
		var req pb.EngineLeaveChatRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		id, err := e.GetLinkedChatId(req.AccountId, req.ChatId)
		if err != nil {
			return nil, err
		}
		return []byte(id), nil

	case "AddContact":
		var req pb.EngineAddContactRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.AddContact(req.AccountId, req.Phone, req.FirstName, req.LastName)

	case "DeleteContact":
		var req pb.EngineBlockUserRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.DeleteContact(req.AccountId, req.UserId)

	case "MarkChatRead":
		var req pb.EngineMarkChatReadRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.MarkChatRead(req.AccountId, req.ChatId, req.UpToMsgId)

	case "GetForumTopics":
		var req pb.EngineGetForumTopicsRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		topics, err := e.GetForumTopics(req.AccountId, req.ChatId)
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetForumTopicsResponse{}
		for _, c := range topics {
			resp.Chats = append(resp.Chats, chatInfoToProto(&c))
		}
		return proto.Marshal(resp)

	// ── Messages ──

	case "GetMessages":
		var req pb.EngineGetMessagesRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		msgs, err := e.GetMessages(req.AccountId, req.ChatId, req.BeforeMs, int(req.Limit))
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetMessagesResponse{}
		for _, m := range msgs {
			resp.Messages = append(resp.Messages, cachedMsgToProto(&m))
		}
		return proto.Marshal(resp)

	case "GetPinnedMessages":
		var req pb.EngineGetPinnedMessagesRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		msgs, err := e.GetPinnedMessages(req.AccountId, req.ChatId)
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetPinnedMessagesResponse{}
		for _, m := range msgs {
			resp.Messages = append(resp.Messages, cachedMsgToProto(&m))
		}
		return proto.Marshal(resp)

	case "FetchLiveMessages":
		var req pb.EngineGetMessagesRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		msgs, err := e.FetchLiveMessages(req.AccountId, req.ChatId, int(req.Limit))
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetMessagesResponse{}
		for _, m := range msgs {
			resp.Messages = append(resp.Messages, cachedMsgToProto(&m))
		}
		return proto.Marshal(resp)

	case "SendMessage":
		var req pb.EngineSendMessageRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		localID, err := e.SendMessage(req.AccountId, req.ChatId, req.Text, req.ReplyToId, req.Silent)
		if err != nil {
			return nil, err
		}
		return proto.Marshal(&pb.EngineSendMessageResponse{LocalId: localID})

	case "EditMessage":
		var req pb.EngineEditMessageRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.EditMessage(req.AccountId, req.ChatId, req.MsgId, req.NewText)

	case "DeleteMessage":
		var req pb.EngineDeleteMessageRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.DeleteMessage(req.AccountId, req.ChatId, req.MsgId)

	case "JoinChat":
		var req pb.EngineJoinChatRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.JoinChat(req.AccountId, req.ChannelName)

	case "LeaveChat":
		var req pb.EngineLeaveChatRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.LeaveChat(req.AccountId, req.ChatId)

	case "EditChatTitle":
		var req pb.EngineSaveDraftRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.EditChatTitle(req.AccountId, req.ChatId, req.Text)

	case "EditChatDescription":
		var req pb.EngineSaveDraftRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.EditChatDescription(req.AccountId, req.ChatId, req.Text)

	case "ClearHistory":
		var req pb.EngineLeaveChatRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.ClearHistory(req.AccountId, req.ChatId)

	case "DeleteChat":
		var req pb.EngineLeaveChatRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.DeleteChat(req.AccountId, req.ChatId)

	case "ForwardMessage":
		var req pb.EngineForwardMessageRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.ForwardMessage(req.AccountId, req.ChatId, req.MsgId, req.ToChatId, req.DropAuthor, req.DropCaptions, req.Silent, req.ScheduleDate)

	case "SendScheduledNow":
		var req pb.EngineSendScheduledNowRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.SendScheduledNow(req.AccountId, req.ChatId, req.MsgIds)

	case "ReactToMessage":
		var req pb.EngineReactToMessageRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.ReactToMessage(req.AccountId, req.ChatId, req.MsgId, req.Emoji)

	case "PinMessage":
		var req pb.EnginePinMessageRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.PinMessage(req.AccountId, req.ChatId, req.MsgId, req.Pinned)

	case "UploadFile":
		var req pb.EngineUploadFileRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		msgID, err := e.UploadFile(req.AccountId, req.ChatId, req.FilePath, req.Caption)
		if err != nil {
			return nil, err
		}
		return proto.Marshal(&pb.EngineUploadFileResponse{MsgId: msgID})

	case "RetryPending":
		var req pb.EngineRetryPendingRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.RetryPending(req.LocalId)

	case "GetMessageRaw":
		var req pb.EngineGetMessageRawRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		raw, err := e.GetMessageRaw(req.AccountId, req.ChatId, req.MsgId)
		if err != nil {
			return nil, err
		}
		return proto.Marshal(&pb.EngineGetMessageRawResponse{ContentRaw: raw})

	// ── Members ──

	case "GetChatMembers":
		var req pb.EngineGetChatMembersRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		members, err := e.GetChatMembers(req.AccountId, req.ChatId, int(req.Limit), int(req.Offset))
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetChatMembersResponse{}
		for _, m := range members {
			resp.Members = append(resp.Members, &pb.EngineMemberInfo{
				UserId:      m.UserID,
				Username:    sanitizeUTF8(m.Username),
				DisplayName: sanitizeUTF8(m.DisplayName),
				AvatarB64:   m.AvatarB64,
				IsBot:       m.IsBot,
				IsOnline:    m.IsOnline,
				Role:        m.Role,
			})
		}
		return proto.Marshal(resp)

	// ── Similar channels ──

	case "GetSimilarChannels":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		channels, err := e.GetSimilarChannels(params.AccountID, params.ChatID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(channels)

	case "GetChatBotCommands":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		cmds, err := e.GetChatBotCommands(params.AccountID, params.ChatID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(cmds)

	// ── Active chat ──

	case "SetActiveChat":
		var req pb.EngineSetActiveChatRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		e.SetActiveChat(req.AccountId, req.ChatId)
		return nil, nil

	case "ClearActiveChat":
		e.ClearActiveChat()
		return nil, nil

	// ── Search ──

	case "SearchMessages":
		var req pb.EngineSearchMessagesRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		results, err := e.SearchMessages(req.Query, req.AccountId, int(req.Limit))
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineSearchMessagesResponse{}
		for _, r := range results {
			resp.Results = append(resp.Results, &pb.EngineSearchResult{
				AccountId:  r.AccountID,
				ChatId:     r.ChatID,
				MsgId:      r.MsgID,
				SenderName: sanitizeUTF8(r.SenderName),
				Text:       sanitizeUTF8(r.Text),
				Timestamp:  r.Timestamp,
				ChatTitle:  sanitizeUTF8(r.ChatTitle),
			})
		}
		return proto.Marshal(resp)

	case "SearchChats":
		var req pb.EngineSearchChatsRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		chats, err := e.SearchChats(req.Query, int(req.Limit))
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineSearchChatsResponse{}
		for _, c := range chats {
			resp.Chats = append(resp.Chats, chatInfoToProto(&c))
		}
		return proto.Marshal(resp)

	// ── Media ──

	case "RequestDownload":
		var req pb.EngineRequestDownloadRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.RequestDownload(req.AccountId, req.ChatId, req.MsgId, int(req.Seq), int(req.Priority))

	case "CancelDownload":
		var req pb.EngineCancelDownloadRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		e.CancelDownload(req.AccountId, req.ChatId, req.MsgId, int(req.Seq))
		return nil, nil

	case "GetSharedMedia":
		var req pb.EngineGetSharedMediaRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		items, err := e.GetSharedMedia(req.AccountId, req.ChatId, req.MediaType, int(req.Limit), int(req.Offset))
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetSharedMediaResponse{}
		for _, item := range items {
			resp.Items = append(resp.Items, &pb.EngineSharedMediaItem{
				MsgId:     item.MsgID,
				Timestamp: item.Timestamp,
				MediaType: int32(item.MediaType),
				FileName:  sanitizeUTF8(item.FileName),
				MimeType:  item.MimeType,
				FileSize:  item.FileSize,
				ThumbB64:  item.ThumbB64,
				LocalPath: item.LocalPath,
				Width:     int32(item.Width),
				Height:    int32(item.Height),
				Duration:  int32(item.Duration),
			})
		}
		return proto.Marshal(resp)

	case "GetSharedMediaCounts":
		var req pb.EngineGetSharedMediaCountsRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		counts, err := e.GetSharedMediaCounts(req.AccountId, req.ChatId)
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetSharedMediaCountsResponse{}
		for _, c := range counts {
			resp.Counts = append(resp.Counts, &pb.EngineSharedMediaCount{
				MediaType: c.MediaType,
				Count:     int32(c.Count),
			})
		}
		return proto.Marshal(resp)

	case "GetCacheSize":
		size, err := e.GetCacheSize()
		if err != nil {
			return nil, err
		}
		return proto.Marshal(&pb.EngineGetCacheSizeResponse{SizeBytes: size})

	case "ClearCache":
		var req pb.EngineClearCacheRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.ClearCache(req.AccountId)

	// ── Folders ──

	case "GetFolders":
		var req pb.EngineGetFoldersRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		folders, err := e.GetFolders(req.AccountId)
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetFoldersResponse{}
		for _, f := range folders {
			resp.Folders = append(resp.Folders, &pb.EngineFolderInfo{
				Id:              f.ID,
				Name:            f.Name,
				ChatIds:         f.ChatIDs,
				ExcludeChatIds:  f.ExcludeChatIDs,
				PinnedChatIds:   f.PinnedChatIDs,
				Contacts:        f.Contacts,
				NonContacts:     f.NonContacts,
				Groups:          f.Groups,
				Channels:        f.Channels,
				Bots:            f.Bots,
				ExcludeMuted:    f.ExcludeMuted,
				ExcludeRead:     f.ExcludeRead,
				ExcludeArchived: f.ExcludeArchived,
			})
		}
		return proto.Marshal(resp)

	case "DeleteFolder":
		var req pb.EngineDeleteFolderRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		if err := e.DeleteFolder(req.AccountId, req.FolderId); err != nil {
			return nil, err
		}
		return nil, nil

	// ── Config ──

	case "GetConfig":
		cfg := e.GetConfig()
		resp := &pb.EngineGetConfigResponse{
			Theme:              cfg.Theme,
			AccentColor:        cfg.AccentColor,
			FontScale:          cfg.FontScale,
			Language:           cfg.Language,
			DownloadDir:        cfg.DownloadDir,
			MaxCacheSize:       cfg.MaxCacheSize,
			SendReadReceipts:   cfg.SendReadReceipts,
			SendTyping:         cfg.SendTyping,
			NotifyDms:          cfg.NotifyDMs,
			NotifyGroups:       cfg.NotifyGroups,
			NotifyMentionsOnly: cfg.NotifyMentionsOnly,
		}
		return proto.Marshal(resp)

	case "UpdateConfig":
		var req pb.EngineUpdateConfigRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		changes := &engine.ConfigChanges{
			Theme:        req.Theme,
			AccentColor:  req.AccentColor,
			FontScale:    req.FontScale,
			Language:     req.Language,
			MaxCacheSize: req.MaxCacheSize,
		}
		if req.HasSendReadReceipts {
			v := req.SendReadReceipts
			changes.SendReadReceipts = &v
		}
		if req.HasSendTyping {
			v := req.SendTyping
			changes.SendTyping = &v
		}
		if req.HasNotifyDms {
			v := req.NotifyDms
			changes.NotifyDMs = &v
		}
		if req.HasNotifyGroups {
			v := req.NotifyGroups
			changes.NotifyGroups = &v
		}
		if req.HasNotifyMentionsOnly {
			v := req.NotifyMentionsOnly
			changes.NotifyMentionsOnly = &v
		}
		return nil, e.UpdateConfigFromBridge(changes)

	// ── Create Channel ──

	case "CreateChannel":
		var req pb.EngineCreateChannelRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		chat, err := e.CreateChannel(req.AccountId, req.Name, req.Description)
		if err != nil {
			return nil, err
		}
		return proto.Marshal(&pb.EngineCreateChannelResponse{Chat: chatInfoToProto(chat)})

	// ── Contacts ──

	case "GetContacts":
		var req pb.EngineGetContactsRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		contacts, err := e.GetContacts(req.AccountId)
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetContactsResponse{}
		for _, c := range contacts {
			resp.Contacts = append(resp.Contacts, &pb.EngineContactInfo{
				UserId:      c.UserID,
				Username:    sanitizeUTF8(c.Username),
				DisplayName: sanitizeUTF8(c.DisplayName),
				Phone:       c.Phone,
				AvatarB64:   c.AvatarB64,
				IsBot:       c.IsBot,
				IsOnline:    c.IsOnline,
			})
		}
		return proto.Marshal(resp)

	// ��─ Shutdown ──

	// ── Online count ──

	case "GetOnlineCount":
		var req pb.EngineGetOnlineCountRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		count, err := e.GetOnlineCount(req.AccountId, req.ChatId)
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetOnlineCountResponse{
			OnlineCount: int32(count),
		}
		return proto.Marshal(resp)

	case "GetGroupCall":
		var req pb.EngineGetGroupCallRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		info, err := e.GetGroupCall(req.AccountId, req.ChatId)
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetGroupCallResponse{}
		if info != nil {
			gc := &pb.EngineGroupCallInfo{
				CallId:            info.CallID,
				ChatId:            info.ChatID,
				Title:             info.Title,
				ParticipantsCount: int32(info.ParticipantsCount),
				Active:            info.Active,
			}
			for _, p := range info.Participants {
				gc.Participants = append(gc.Participants, &pb.EngineGroupCallParticipant{
					UserId:      p.UserID,
					DisplayName: p.DisplayName,
					IsMuted:     p.IsMuted,
					IsSpeaking:  p.IsSpeaking,
					HasVideo:    p.HasVideo,
					AvatarPath:  p.AvatarPath,
				})
			}
			resp.GroupCall = gc
		}
		return proto.Marshal(resp)

	case "JoinGroupCall":
		var req pb.EngineJoinGroupCallRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		callID, err := e.JoinGroupCall(req.AccountId, req.ChatId)
		if err != nil {
			return nil, err
		}
		return proto.Marshal(&pb.EngineJoinGroupCallResponse{CallId: callID})

	case "Shutdown":
		return nil, e.Shutdown()

	// ── Peer Colors ──

	case "GetPeerColors":
		var req pb.EngineGetPeerColorsRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		colors, err := e.GetPeerColors(req.AccountId)
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetPeerColorsResponse{}
		for _, c := range colors {
			entry := &pb.EnginePeerColorEntry{
				ColorId: int32(c.ColorID),
				Hidden:  c.Hidden,
			}
			for _, v := range c.DayColors {
				entry.DayColors = append(entry.DayColors, int32(v))
			}
			for _, v := range c.NightColors {
				entry.NightColors = append(entry.NightColors, int32(v))
			}
			resp.Colors = append(resp.Colors, entry)
		}
		return proto.Marshal(resp)

	case "GetStickerSetInfo":
		var req pb.EngineGetStickerSetInfoRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		info, err := e.GetStickerSetInfo(req.AccountId, req.ShortName, req.SetId, req.AccessHash)
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetStickerSetInfoResponse{
			Title:     info.Title,
			ShortName: info.ShortName,
			Count:     int32(info.Count),
			Installed: info.Installed,
			Archived:  info.Archived,
			Animated:  info.Animated,
			Video:     info.Video,
		}
		for _, s := range info.Stickers {
			resp.Stickers = append(resp.Stickers, &pb.EngineStickerInfo{
				Emoji:    s.Emoji,
				ThumbB64: s.ThumbB64,
				Width:    int32(s.Width),
				Height:   int32(s.Height),
				MimeType: s.MimeType,
				FileId:   s.FileID,
			})
		}
		return proto.Marshal(resp)

	case "GetStickerSuggestions":
		var req pb.EngineGetStickerSuggestionsRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		stickers, err := e.GetStickerSuggestions(req.AccountId, req.Emoji)
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetStickerSuggestionsResponse{}
		for _, s := range stickers {
			resp.Stickers = append(resp.Stickers, &pb.EngineStickerInfo{
				Emoji:    s.Emoji,
				ThumbB64: s.ThumbB64,
				Width:    int32(s.Width),
				Height:   int32(s.Height),
				MimeType: s.MimeType,
				FileId:   s.FileID,
			})
		}
		return proto.Marshal(resp)

	case "GetInstalledEmojiSets":
		var req pb.EngineGetInstalledEmojiSetsRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		sets, err := e.GetInstalledEmojiSets(req.AccountId)
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetInstalledEmojiSetsResponse{}
		for _, s := range sets {
			summary := &pb.EngineEmojiSetSummary{
				SetId:      s.SetID,
				AccessHash: s.AccessHash,
				Title:      s.Title,
				ShortName:  s.ShortName,
				Count:      int32(s.Count),
				Installed:  s.Installed,
				Premium:    s.Premium,
			}
			for _, st := range s.Stickers {
				summary.Stickers = append(summary.Stickers, &pb.EngineStickerInfo{
					Emoji:    st.Emoji,
					ThumbB64: st.ThumbB64,
					Width:    int32(st.Width),
					Height:   int32(st.Height),
					MimeType: st.MimeType,
					FileId:   st.FileID,
				})
			}
			resp.Sets = append(resp.Sets, summary)
		}
		return proto.Marshal(resp)

	case "TranscribeAudio":
		var req pb.EngineTranscribeAudioRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		pending, transcriptionID, text, err := e.TranscribeAudio(req.AccountId, req.ChatId, req.MsgId)
		if err != nil {
			return nil, err
		}
		return proto.Marshal(&pb.EngineTranscribeAudioResponse{
			Pending:         pending,
			TranscriptionId: transcriptionID,
			Text:            text,
		})

	case "FaveSticker":
		var req pb.EngineFaveStickerRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		if err := e.FaveSticker(req.AccountId, req.FileId, req.Extra, req.Unfave); err != nil {
			return nil, err
		}
		return []byte{}, nil

	case "GetInstalledStickerPacks":
		var req pb.EngineGetInstalledStickerPacksRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		packs, err := e.GetInstalledStickerPacks(req.AccountId)
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetInstalledStickerPacksResponse{}
		for _, p := range packs {
			summary := &pb.EngineStickerPackSummary{
				SetId:      p.SetID,
				AccessHash: p.AccessHash,
				Title:      p.Title,
				ShortName:  p.ShortName,
				Count:      int32(p.Count),
				Animated:   p.Animated,
				Video:      p.Video,
				ThumbB64:   p.ThumbB64,
			}
			for _, st := range p.Stickers {
				summary.Stickers = append(summary.Stickers, &pb.EngineStickerInfo{
					Emoji:    st.Emoji,
					ThumbB64: st.ThumbB64,
					Width:    int32(st.Width),
					Height:   int32(st.Height),
					MimeType: st.MimeType,
					FileId:   st.FileID,
				})
			}
			resp.Packs = append(resp.Packs, summary)
		}
		return proto.Marshal(resp)

	case "GetRecentStickers":
		var req pb.EngineGetRecentStickersRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		stickers, err := e.GetRecentStickers(req.AccountId)
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetRecentStickersResponse{}
		for _, s := range stickers {
			resp.Stickers = append(resp.Stickers, &pb.EngineStickerInfo{
				Emoji:    s.Emoji,
				ThumbB64: s.ThumbB64,
				Width:    int32(s.Width),
				Height:   int32(s.Height),
				MimeType: s.MimeType,
				FileId:   s.FileID,
			})
		}
		return proto.Marshal(resp)

	case "GetFeaturedStickerPacks":
		var req pb.EngineGetFeaturedStickerPacksRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		packs, err := e.GetFeaturedStickerPacks(req.AccountId)
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetFeaturedStickerPacksResponse{}
		for _, p := range packs {
			summary := &pb.EngineStickerPackSummary{
				SetId:      p.SetID,
				AccessHash: p.AccessHash,
				Title:      p.Title,
				ShortName:  p.ShortName,
				Count:      int32(p.Count),
				Animated:   p.Animated,
				Video:      p.Video,
				ThumbB64:   p.ThumbB64,
				Installed:  p.Installed,
			}
			for _, st := range p.Stickers {
				summary.Stickers = append(summary.Stickers, &pb.EngineStickerInfo{
					Emoji:    st.Emoji,
					ThumbB64: st.ThumbB64,
					Width:    int32(st.Width),
					Height:   int32(st.Height),
					MimeType: st.MimeType,
					FileId:   st.FileID,
				})
			}
			resp.Packs = append(resp.Packs, summary)
		}
		return proto.Marshal(resp)

	case "SearchStickerSets":
		var req pb.EngineSearchStickerSetsRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		packs, err := e.SearchStickerSets(req.AccountId, req.Query)
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineSearchStickerSetsResponse{}
		for _, p := range packs {
			summary := &pb.EngineStickerPackSummary{
				SetId:      p.SetID,
				AccessHash: p.AccessHash,
				Title:      p.Title,
				ShortName:  p.ShortName,
				Count:      int32(p.Count),
				Animated:   p.Animated,
				Video:      p.Video,
				ThumbB64:   p.ThumbB64,
				Installed:  p.Installed,
			}
			for _, st := range p.Stickers {
				summary.Stickers = append(summary.Stickers, &pb.EngineStickerInfo{
					Emoji:    st.Emoji,
					ThumbB64: st.ThumbB64,
					Width:    int32(st.Width),
					Height:   int32(st.Height),
					MimeType: st.MimeType,
					FileId:   st.FileID,
				})
			}
			resp.Packs = append(resp.Packs, summary)
		}
		return proto.Marshal(resp)

	case "InstallStickerSet":
		var req pb.EngineInstallStickerSetRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		if err := e.InstallStickerSet(req.AccountId, req.SetId, req.AccessHash); err != nil {
			return nil, err
		}
		return []byte{}, nil

	case "SaveGif":
		var req pb.EngineSaveGifRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		if err := e.SaveGif(req.AccountId, req.FileId, req.Extra, req.Unsave); err != nil {
			return nil, err
		}
		return []byte{}, nil

	case "GetSavedGifs":
		var req pb.EngineGetSavedGifsRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		gifs, err := e.GetSavedGifs(req.AccountId)
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetSavedGifsResponse{}
		for _, g := range gifs {
			resp.Gifs = append(resp.Gifs, &pb.EngineGifInfo{
				ThumbB64: g.ThumbB64,
				Width:    int32(g.Width),
				Height:   int32(g.Height),
				MimeType: g.MimeType,
				FileId:   g.FileID,
			})
		}
		return proto.Marshal(resp)

	case "TranslateText":
		var req pb.EngineTranslateTextRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		text, err := e.TranslateText(req.AccountId, req.ChatId, req.MsgId, req.ToLang)
		if err != nil {
			return nil, err
		}
		return proto.Marshal(&pb.EngineTranslateTextResponse{
			TranslatedText: text,
		})

	case "ReportMessage":
		var req pb.EngineReportMessageRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		msgIDs := make([]int, len(req.MsgIds))
		for i, id := range req.MsgIds {
			msgIDs[i] = int(id)
		}
		result, err := e.ReportMessage(req.AccountId, req.ChatId, msgIDs, req.Option, req.Message)
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineReportMessageResponse{
			ResultType:      result.Type,
			Title:           result.Title,
			CommentOptional: result.CommentOptional,
			CommentOption:   result.CommentOption,
		}
		for _, o := range result.Options {
			resp.Options = append(resp.Options, &pb.ReportOption{
				Text:   o.Text,
				Option: o.Option,
			})
		}
		return proto.Marshal(resp)

	case "GetAttachMenuBots":
		var req pb.EngineGetAttachMenuBotsRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		bots, err := e.GetAttachMenuBots(req.AccountId)
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetAttachMenuBotsResponse{}
		for _, b := range bots {
			resp.Bots = append(resp.Bots, &pb.EngineAttachMenuBotInfo{
				BotId:     b.BotID,
				ShortName: b.ShortName,
				Inactive:  b.Inactive,
			})
		}
		return proto.Marshal(resp)

	case "GetWebPagePreview":
		var req pb.EngineGetWebPagePreviewRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		result, err := e.GetWebPagePreview(req.AccountId, req.Url)
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetWebPagePreviewResponse{}
		if result != nil {
			resp.Url = result.URL
			resp.SiteName = result.SiteName
			resp.Title = result.Title
			resp.Description = result.Description
			resp.ThumbB64 = result.ThumbB64
		}
		return proto.Marshal(resp)

	case "BotCallback":
		var req pb.EngineBotCallbackRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		msg, err := e.BotCallback(req.AccountId, req.ChatId, req.MsgId, req.Data)
		if err != nil {
			return nil, err
		}
		return proto.Marshal(&pb.EngineBotCallbackResponse{Message: msg})

	case "GetInlineBotResults":
		var params struct {
			AccountID string `json:"account_id"`
			BotID     string `json:"bot_id"`
			Query     string `json:"query"`
			Offset    string `json:"offset"`
			ChatID    string `json:"chat_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		results, err := e.GetInlineBotResultsFull(params.AccountID, params.BotID, params.Query, params.Offset, params.ChatID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(results)

	case "ResolveUsername":
		var params struct {
			AccountID string `json:"account_id"`
			Username  string `json:"username"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		userID, err := e.ResolveUsername(params.AccountID, params.Username)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]string{"user_id": userID})

	case "GetUserProfile":
		var params struct {
			AccountID string `json:"account_id"`
			UserID    string `json:"user_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		user, err := e.GetUserProfile(params.AccountID, params.UserID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(user)

	case "GetSelfBio":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		bio, err := e.GetSelfBio(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]string{"bio": bio})

	case "UpdateBio":
		var params struct {
			AccountID string `json:"account_id"`
			Bio       string `json:"bio"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.UpdateBio(params.AccountID, params.Bio)

	case "GetSelfBirthday":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		day, month, year, err := e.GetSelfBirthday(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]int{"day": day, "month": month, "year": year})

	case "UpdateBirthday":
		var params struct {
			AccountID string `json:"account_id"`
			Day       int    `json:"day"`
			Month     int    `json:"month"`
			Year      int    `json:"year"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.UpdateBirthday(params.AccountID, params.Day, params.Month, params.Year)

	case "GetSelfColorAndChannel":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		colorID, channelName, err := e.GetSelfColorAndChannel(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]interface{}{
			"color_id":     colorID,
			"channel_name": channelName,
		})

	case "UpdateNameColor":
		var params struct {
			AccountID string `json:"account_id"`
			ColorID   int    `json:"color_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.UpdateNameColor(params.AccountID, params.ColorID)

	case "GetContentSettings":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		enabled, canChange, err := e.GetContentSettings(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]interface{}{
			"sensitive_enabled":    enabled,
			"sensitive_can_change": canChange,
		})

	case "SetContentSettings":
		var params struct {
			AccountID        string `json:"account_id"`
			SensitiveEnabled bool   `json:"sensitive_enabled"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.SetContentSettings(params.AccountID, params.SensitiveEnabled)

	case "GetArchiveSettings":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		archiveAndMute, keepUnmuted, keepFolders, err := e.GetArchiveSettings(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]interface{}{
			"archive_and_mute":      archiveAndMute,
			"keep_archived_unmuted": keepUnmuted,
			"keep_archived_folders": keepFolders,
		})

	case "SetArchiveSettings":
		var params struct {
			AccountID          string `json:"account_id"`
			ArchiveAndMute     bool   `json:"archive_and_mute"`
			KeepArchivedUnmuted bool  `json:"keep_archived_unmuted"`
			KeepArchivedFolders bool  `json:"keep_archived_folders"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.SetArchiveSettings(params.AccountID, params.ArchiveAndMute, params.KeepArchivedUnmuted, params.KeepArchivedFolders)

	case "GetCloudThemes":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		themes, err := e.GetCloudThemes(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(themes)

	case "UploadProfilePhoto":
		var params struct {
			AccountID string `json:"account_id"`
			FilePath  string `json:"file_path"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.UploadProfilePhoto(params.AccountID, params.FilePath)

	case "SendInlineBotResult":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			QueryID   int64  `json:"query_id"`
			ResultID  string `json:"result_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		msgID, err := e.SendInlineBotResult(params.AccountID, params.ChatID, params.QueryID, params.ResultID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]int{"msg_id": msgID})

	case "SendSticker":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			StickerID string `json:"sticker_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		if err := e.SendSticker(params.AccountID, params.ChatID, params.StickerID); err != nil {
			return nil, err
		}
		return nil, nil

	// ── Send As ──

	case "GetSendAs":
		var req pb.EngineGetSendAsRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		peers, err := e.GetSendAs(req.AccountId, req.ChatId)
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetSendAsResponse{}
		for _, p := range peers {
			resp.Peers = append(resp.Peers, &pb.EngineSendAsPeerInfo{
				PeerId:      p.PeerID,
				DisplayName: sanitizeUTF8(p.DisplayName),
				AvatarPath:  p.AvatarPath,
				IsChannel:   p.IsChannel,
			})
		}
		return proto.Marshal(resp)

	case "SaveDefaultSendAs":
		var req pb.EngineSaveDefaultSendAsRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		err := e.SaveDefaultSendAs(req.AccountId, req.ChatId, req.PeerId)
		if err != nil {
			return nil, err
		}
		return proto.Marshal(&pb.EngineSaveDefaultSendAsResponse{Ok: true})

	case "GetScheduledCount":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		count, err := e.GetScheduledCount(params.AccountID, params.ChatID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]int{"count": count})

	case "GetScheduledMessages":
		var req pb.EngineGetMessagesRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		msgs, err := e.GetScheduledMessages(req.AccountId, req.ChatId)
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetMessagesResponse{}
		for _, m := range msgs {
			resp.Messages = append(resp.Messages, cachedMsgToProto(&m))
		}
		return proto.Marshal(resp)

	case "GetStarGifts":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		result, err := e.GetStarGifts(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(result)

	case "GetPinnedStarGifts":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		result, err := e.GetPinnedStarGifts(params.AccountID, params.ChatID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(result)

	case "VotePoll":
		var req pb.EngineVotePollRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		if err := e.VotePoll(req.AccountId, req.ChatId, req.MsgId, int(req.OptionIndex)); err != nil {
			return nil, err
		}
		return []byte{}, nil

	case "RetractPollVote":
		var req pb.EngineRetractPollVoteRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		if err := e.RetractPollVote(req.AccountId, req.ChatId, req.MsgId); err != nil {
			return nil, err
		}
		return []byte{}, nil

	case "StopPoll":
		var req pb.EngineStopPollRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		if err := e.StopPoll(req.AccountId, req.ChatId, req.MsgId); err != nil {
			return nil, err
		}
		return []byte{}, nil

	case "SendCallRating":
		var req pb.EngineSendCallRatingRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		if err := e.SendCallRating(req.AccountId, req.CallId, int(req.Rating), req.Comment); err != nil {
			return nil, err
		}
		return []byte{}, nil

	case "GetDefaultHistoryTTL":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		ttl, err := e.GetDefaultHistoryTTL(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]int{"period": ttl})

	case "SetDefaultHistoryTTL":
		var params struct {
			AccountID string `json:"account_id"`
			Period    int    `json:"period"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.SetDefaultHistoryTTL(params.AccountID, params.Period)

	case "GetCloudPasswordState":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		state, err := e.GetCloudPasswordState(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(state)

	case "CheckCloudPassword":
		var params struct {
			AccountID string `json:"account_id"`
			Password  string `json:"password"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.CheckCloudPassword(params.AccountID, params.Password)

	case "SetCloudPassword":
		var params struct {
			AccountID       string `json:"account_id"`
			CurrentPassword string `json:"current_password"`
			NewPassword     string `json:"new_password"`
			Hint            string `json:"hint"`
			Email           string `json:"email"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.SetCloudPassword(params.AccountID, params.CurrentPassword, params.NewPassword, params.Hint, params.Email)

	case "RemoveCloudPassword":
		var params struct {
			AccountID string `json:"account_id"`
			Password  string `json:"password"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.RemoveCloudPassword(params.AccountID, params.Password)

	case "GetPasskeyList":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		list, err := e.GetPasskeyList(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(list)

	case "GetBlockedUsers":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		users, err := e.GetBlockedUsers(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(users)

	case "GetSessions":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		sessions, err := e.GetSessions(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(sessions)

	case "GetPrivacySetting":
		var params struct {
			AccountID string `json:"account_id"`
			Key       string `json:"key"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return getPrivacySetting(e, params.AccountID, params.Key)

	case "SetPrivacySetting":
		var params struct {
			AccountID string `json:"account_id"`
			Key       string `json:"key"`
			Option    string `json:"option"`
			AlwaysIDs []string `json:"always_ids"`
			NeverIDs  []string `json:"never_ids"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, setPrivacySetting(e, params.AccountID, params.Key, params.Option, params.AlwaysIDs, params.NeverIDs)

	case "GetAllPrivacySettings":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return getAllPrivacySettings(e, params.AccountID)

	default:
		return nil, fmt.Errorf("unknown engine method: %s", method)
	}
}

var privacyKeyMap = map[string]tg.InputPrivacyKeyClass{
	"phone_number":    &tg.InputPrivacyKeyPhoneNumber{},
	"last_seen":       &tg.InputPrivacyKeyStatusTimestamp{},
	"profile_photo":   &tg.InputPrivacyKeyProfilePhoto{},
	"forwards":        &tg.InputPrivacyKeyForwards{},
	"calls":           &tg.InputPrivacyKeyPhoneCall{},
	"calls_p2p":       &tg.InputPrivacyKeyPhoneP2P{},
	"voice_messages":  &tg.InputPrivacyKeyVoiceMessages{},
	"chat_invite":     &tg.InputPrivacyKeyChatInvite{},
	"birthday":        &tg.InputPrivacyKeyBirthday{},
	"gifts":           &tg.InputPrivacyKeyStarGiftsAutoSave{},
	"about":           &tg.InputPrivacyKeyAbout{},
	"added_by_phone":  &tg.InputPrivacyKeyAddedByPhone{},
	"saved_music":     &tg.InputPrivacyKeySavedMusic{},
}

type privacyResult struct {
	Option       string   `json:"option"`
	AlwaysUsers  []string `json:"always_users"`
	NeverUsers   []string `json:"never_users"`
	AlwaysChats  []string `json:"always_chats"`
	NeverChats   []string `json:"never_chats"`
	AllowPremium bool     `json:"allow_premium"`
}

func parsePrivacyRules(rules []tg.PrivacyRuleClass) *privacyResult {
	res := &privacyResult{Option: "everyone"}
	for _, r := range rules {
		switch v := r.(type) {
		case *tg.PrivacyValueAllowAll:
			res.Option = "everyone"
		case *tg.PrivacyValueAllowContacts:
			res.Option = "contacts"
		case *tg.PrivacyValueAllowCloseFriends:
			res.Option = "close_friends"
		case *tg.PrivacyValueDisallowAll:
			res.Option = "nobody"
		case *tg.PrivacyValueAllowUsers:
			for _, id := range v.Users {
				res.AlwaysUsers = append(res.AlwaysUsers, strconv.FormatInt(id, 10))
			}
		case *tg.PrivacyValueDisallowUsers:
			for _, id := range v.Users {
				res.NeverUsers = append(res.NeverUsers, strconv.FormatInt(id, 10))
			}
		case *tg.PrivacyValueAllowChatParticipants:
			for _, id := range v.Chats {
				res.AlwaysChats = append(res.AlwaysChats, strconv.FormatInt(id, 10))
			}
		case *tg.PrivacyValueDisallowChatParticipants:
			for _, id := range v.Chats {
				res.NeverChats = append(res.NeverChats, strconv.FormatInt(id, 10))
			}
		case *tg.PrivacyValueAllowPremium:
			res.AllowPremium = true
		}
	}
	if res.AlwaysUsers == nil { res.AlwaysUsers = []string{} }
	if res.NeverUsers == nil { res.NeverUsers = []string{} }
	if res.AlwaysChats == nil { res.AlwaysChats = []string{} }
	if res.NeverChats == nil { res.NeverChats = []string{} }
	return res
}

func getPrivacySetting(e *engine.Engine, accountID, key string) ([]byte, error) {
	acc := e.GetAccountCore(accountID)
	if acc == nil {
		return nil, fmt.Errorf("account not found")
	}
	tgCore, ok := acc.(*cores.TelegramCore)
	if !ok {
		return json.Marshal(&privacyResult{Option: "everyone", AlwaysUsers: []string{}, NeverUsers: []string{}, AlwaysChats: []string{}, NeverChats: []string{}})
	}
	inputKey, ok := privacyKeyMap[key]
	if !ok {
		return nil, fmt.Errorf("unknown privacy key: %s", key)
	}
	rules, err := tgCore.GetPrivacy(inputKey)
	if err != nil {
		return nil, err
	}
	return json.Marshal(parsePrivacyRules(rules))
}

func setPrivacySetting(e *engine.Engine, accountID, key, option string, alwaysIDs, neverIDs []string) error {
	acc := e.GetAccountCore(accountID)
	if acc == nil {
		return fmt.Errorf("account not found")
	}
	tgCore, ok := acc.(*cores.TelegramCore)
	if !ok {
		return fmt.Errorf("privacy settings not supported for this platform")
	}
	inputKey, ok := privacyKeyMap[key]
	if !ok {
		return fmt.Errorf("unknown privacy key: %s", key)
	}
	var rules []tg.InputPrivacyRuleClass
	switch option {
	case "everyone":
		rules = append(rules, &tg.InputPrivacyValueAllowAll{})
	case "contacts":
		rules = append(rules, &tg.InputPrivacyValueAllowContacts{})
	case "close_friends":
		rules = append(rules, &tg.InputPrivacyValueAllowCloseFriends{})
	case "nobody":
		rules = append(rules, &tg.InputPrivacyValueDisallowAll{})
	}
	if len(alwaysIDs) > 0 {
		var users []tg.InputUserClass
		for _, idStr := range alwaysIDs {
			id, err := strconv.ParseInt(idStr, 10, 64)
			if err != nil { continue }
			users = append(users, &tg.InputUser{UserID: id})
		}
		if len(users) > 0 {
			rules = append(rules, &tg.InputPrivacyValueAllowUsers{Users: users})
		}
	}
	if len(neverIDs) > 0 {
		var users []tg.InputUserClass
		for _, idStr := range neverIDs {
			id, err := strconv.ParseInt(idStr, 10, 64)
			if err != nil { continue }
			users = append(users, &tg.InputUser{UserID: id})
		}
		if len(users) > 0 {
			rules = append(rules, &tg.InputPrivacyValueDisallowUsers{Users: users})
		}
	}
	return tgCore.SetPrivacy(inputKey, rules)
}

func getAllPrivacySettings(e *engine.Engine, accountID string) ([]byte, error) {
	keys := []string{"phone_number", "last_seen", "profile_photo", "forwards", "calls", "voice_messages", "chat_invite", "birthday", "gifts", "about", "saved_music"}
	result := make(map[string]*privacyResult)
	acc := e.GetAccountCore(accountID)
	if acc == nil {
		return nil, fmt.Errorf("account not found")
	}
	tgCore, ok := acc.(*cores.TelegramCore)
	if !ok {
		for _, k := range keys {
			result[k] = &privacyResult{Option: "everyone", AlwaysUsers: []string{}, NeverUsers: []string{}, AlwaysChats: []string{}, NeverChats: []string{}}
		}
		return json.Marshal(result)
	}
	for _, k := range keys {
		inputKey, ok := privacyKeyMap[k]
		if !ok { continue }
		rules, err := tgCore.GetPrivacy(inputKey)
		if err != nil {
			result[k] = &privacyResult{Option: "everyone", AlwaysUsers: []string{}, NeverUsers: []string{}, AlwaysChats: []string{}, NeverChats: []string{}}
			continue
		}
		result[k] = parsePrivacyRules(rules)
	}
	return json.Marshal(result)
}

// --- Proto converters ---

func authStateToProto(s *engine.AuthState) *pb.EngineAuthState {
	if s == nil {
		return nil
	}
	p := &pb.EngineAuthState{
		AccountId:   s.AccountID,
		Platform:    s.Platform,
		State:       s.State,
		FieldType:   s.FieldType,
		Label:       s.Label,
		Hint:        s.Hint,
		Error:       s.Error,
		CodeLength:  int32(s.CodeLength),
		SentTo:      s.SentTo,
		TimeoutSecs: int32(s.TimeoutSecs),
		CanResend:   s.CanResend,
		HasRecovery: s.HasRecovery,
		QrData:      s.QRData,
		QrExpiresIn: int32(s.QRExpiresIn),
		DisplayName: s.DisplayName,
		AvatarB64:   s.AvatarB64,
		Message:     s.Message,
		Recoverable: s.Recoverable,
	}
	for _, o := range s.Options {
		p.Options = append(p.Options, &pb.AuthOption{Id: o.ID, Label: o.Label})
	}
	return p
}

func chatInfoToProto(c *engine.ChatInfo) *pb.EngineChatInfo {
	return &pb.EngineChatInfo{
		AccountId:    c.AccountID,
		ChatId:       c.ChatID,
		Type:         int32(c.Type),
		Title:        sanitizeUTF8(c.Title),
		AvatarPath:   c.AvatarPath,
		LastMsgId:    c.LastMsgID,
		LastMsgText:  sanitizeUTF8(c.LastMsgText),
		LastMsgTime:  c.LastMsgTime,
		LastMsgSender:     sanitizeUTF8(c.LastMsgSender),
		LastMsgIsOutgoing: c.LastMsgIsOutgoing,
		LastMsgStatus:     int32(c.LastMsgStatus),
		UnreadCount:       int32(c.UnreadCount),
		IsMuted:      c.IsMuted,
		IsPinned:     c.IsPinned,
		IsArchived:   c.IsArchived,
		DraftText:    sanitizeUTF8(c.DraftText),
		MemberCount:  int32(c.MemberCount),
		ParentId:     c.ParentID,
		IsBot:        c.IsBot,
		IsContact:    c.IsContact,
		IsBlocked:    c.IsBlocked,
		SlowmodeSeconds:       int32(c.SlowmodeSeconds),
		SlowmodeNextSendDate:  c.SlowmodeNextSendDate,
		StarsToSend:           int32(c.StarsToSend),
		TtlPeriod:             int32(c.TtlPeriod),
		EmojiStatusId:         c.EmojiStatusID,
	}
}

func cachedMsgToProto(m *engine.CachedMessage) *pb.EngineCachedMessage {
	return &pb.EngineCachedMessage{
		AccountId:          m.AccountID,
		ChatId:             m.ChatID,
		MsgId:              m.MsgID,
		LocalId:            m.LocalID,
		SenderId:           m.SenderID,
		SenderName:         sanitizeUTF8(m.SenderName),
		SenderRank:         m.SenderRank,
		SenderColorId:      int32(m.SenderColorID),
		ContentText:        sanitizeUTF8(m.ContentText),
		ContentRaw:         m.ContentRaw,
		ContentRich:        m.ContentRich,
		Timestamp:          m.Timestamp,
		EditedAt:           m.EditedAt,
		Status:             int32(m.Status),
		ReplyToId:          m.ReplyToID,
		ReplyPreview:       sanitizeUTF8(m.ReplyPreview),
		ForwardFrom:        sanitizeUTF8(m.ForwardFrom),
		IsPinned:           m.IsPinned,
		IsOutgoing:         m.IsOutgoing,
		IsService:          m.IsService,
		HasMedia:           m.HasMedia,
		MediaType:          int32(m.MediaType),
		MediaFileName:      sanitizeUTF8(m.MediaFileName),
		MediaMimeType:      m.MediaMimeType,
		MediaFileSize:      m.MediaFileSize,
		MediaThumbB64:      m.MediaThumbB64,
		MediaLocalPath:     m.MediaLocalPath,
		MediaWidth:         int32(m.MediaWidth),
		MediaHeight:        int32(m.MediaHeight),
		MediaDuration:      int32(m.MediaDuration),
		MediaDownloadState: int32(m.MediaDownloadState),
		GroupedId:          m.GroupedID,
		MediaRemoteRef:     m.MediaRemoteRef,
		MediaExtra:         m.MediaExtra,
	}
}

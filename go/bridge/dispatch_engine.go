package bridge

import (
	"fmt"
	"strings"
	"unicode/utf8"

	"google.golang.org/protobuf/proto"

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
				AvatarPath:  a.AvatarPath,
				SortOrder:   int32(a.SortOrder),
				ConnState:   int32(a.ConnState),
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
		return nil, e.MuteChat(req.AccountId, req.ChatId, req.Muted)

	case "PinChat":
		var req pb.EnginePinChatRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.PinChat(req.AccountId, req.ChatId, req.Pinned)

	case "ArchiveChat":
		var req pb.EngineArchiveChatRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.ArchiveChat(req.AccountId, req.ChatId, req.Archived)

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
		localID, err := e.SendMessage(req.AccountId, req.ChatId, req.Text, req.ReplyToId)
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

	case "ForwardMessage":
		var req pb.EngineForwardMessageRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.ForwardMessage(req.AccountId, req.ChatId, req.MsgId, req.ToChatId)

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
				Id:      f.ID,
				Name:    f.Name,
				ChatIds: f.ChatIDs,
			})
		}
		return proto.Marshal(resp)

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

	// ── Shutdown ──

	case "Shutdown":
		return nil, e.Shutdown()

	default:
		return nil, fmt.Errorf("unknown engine method: %s", method)
	}
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
		LastMsgSender: sanitizeUTF8(c.LastMsgSender),
		UnreadCount:  int32(c.UnreadCount),
		IsMuted:      c.IsMuted,
		IsPinned:     c.IsPinned,
		IsArchived:   c.IsArchived,
		DraftText:    sanitizeUTF8(c.DraftText),
		MemberCount:  int32(c.MemberCount),
		ParentId:     c.ParentID,
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
	}
}

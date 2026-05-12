package bridge

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"strings"
	"unicode/utf8"

	"github.com/gotd/td/tg"
	"google.golang.org/protobuf/encoding/protowire"
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
				SelfUserId:  a.SelfUserID,
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

	case "UnbanMember":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			UserID    string `json:"user_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.UnbanMember(params.AccountID, params.ChatID, params.UserID)

	case "DemoteAdmin":
		var req pb.EngineDemoteAdminRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.DemoteAdmin(req.AccountId, req.ChatId, req.UserId)

	case "TransferChannelOwnership":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			UserID    string `json:"user_id"`
			Password  string `json:"password"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.TransferChannelOwnership(params.AccountID, params.ChatID, params.UserID, params.Password)

	case "PromoteAdmin":
		var req pb.EnginePromoteAdminRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.PromoteAdmin(req.AccountId, req.ChatId, req.UserId)

	case "PromoteAdminWithRights":
		var params struct {
			AccountID      string `json:"account_id"`
			ChatID         string `json:"chat_id"`
			UserID         string `json:"user_id"`
			ChangeInfo     bool   `json:"change_info"`
			DeleteMessages bool   `json:"delete_messages"`
			BanUsers       bool   `json:"ban_users"`
			InviteUsers    bool   `json:"invite_users"`
			PinMessages    bool   `json:"pin_messages"`
			ManageTopics   bool   `json:"manage_topics"`
			PostMessages   bool   `json:"post_messages"`
			EditMessages   bool   `json:"edit_messages"`
			PostStories    bool   `json:"post_stories"`
			EditStories    bool   `json:"edit_stories"`
			DeleteStories  bool   `json:"delete_stories"`
			ManageCall     bool   `json:"manage_call"`
			ManageRanks    bool   `json:"manage_ranks"`
			Anonymous      bool   `json:"anonymous"`
			AddAdmins      bool   `json:"add_admins"`
			ManageDirect   bool   `json:"manage_direct"`
			Rank           string `json:"rank"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		rights := &engine.AdminRights{
			ChangeInfo:     params.ChangeInfo,
			DeleteMessages: params.DeleteMessages,
			BanUsers:       params.BanUsers,
			InviteUsers:    params.InviteUsers,
			PinMessages:    params.PinMessages,
			ManageTopics:   params.ManageTopics,
			PostMessages:   params.PostMessages,
			EditMessages:   params.EditMessages,
			PostStories:    params.PostStories,
			EditStories:    params.EditStories,
			DeleteStories:  params.DeleteStories,
			ManageCall:     params.ManageCall,
			ManageRanks:    params.ManageRanks,
			Anonymous:      params.Anonymous,
			AddAdmins:      params.AddAdmins,
			ManageDirect:   params.ManageDirect,
		}
		return nil, e.PromoteAdminWithRights(params.AccountID, params.ChatID, params.UserID, rights, params.Rank)

	case "RestrictMember":
		var req pb.EngineRestrictMemberRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.RestrictMember(req.AccountId, req.ChatId, req.UserId)

	case "RestrictMemberWithRights":
		var params struct {
			AccountID       string `json:"account_id"`
			ChatID          string `json:"chat_id"`
			UserID          string `json:"user_id"`
			SendPlain       bool   `json:"send_plain"`
			SendPhotos      bool   `json:"send_photos"`
			SendVideos      bool   `json:"send_videos"`
			SendRoundvideos bool   `json:"send_roundvideos"`
			SendAudios      bool   `json:"send_audios"`
			SendVoices      bool   `json:"send_voices"`
			SendDocs        bool   `json:"send_docs"`
			SendStickers    bool   `json:"send_stickers"`
			EmbedLinks      bool   `json:"embed_links"`
			SendPolls       bool   `json:"send_polls"`
			InviteUsers     bool   `json:"invite_users"`
			ManageTopics    bool   `json:"manage_topics"`
			PinMessages     bool   `json:"pin_messages"`
			EditRank        bool   `json:"edit_rank"`
			ChangeInfo      bool   `json:"change_info"`
			UntilDate       int    `json:"until_date"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		rights := &engine.DefaultBannedRights{
			SendPlain:       params.SendPlain,
			SendPhotos:      params.SendPhotos,
			SendVideos:      params.SendVideos,
			SendRoundvideos: params.SendRoundvideos,
			SendAudios:      params.SendAudios,
			SendVoices:      params.SendVoices,
			SendDocs:        params.SendDocs,
			SendStickers:    params.SendStickers,
			EmbedLinks:      params.EmbedLinks,
			SendPolls:       params.SendPolls,
			InviteUsers:     params.InviteUsers,
			ManageTopics:    params.ManageTopics,
			PinMessages:     params.PinMessages,
			EditRank:        params.EditRank,
			ChangeInfo:      params.ChangeInfo,
		}
		return nil, e.RestrictMemberWithRights(params.AccountID, params.ChatID, params.UserID, rights, params.UntilDate)

	case "ReportSpam":
		var req pb.EngineReportSpamRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.ReportSpam(req.AccountId, req.ChatId)

	case "GetLinkedChatId":
		var req pb.EngineGetLinkedChatIdRequest
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
		return nil, e.AddContact(req.AccountId, req.Phone, req.FirstName, req.LastName, req.GetNote())

	case "SuggestContactPhoto":
		var params struct {
			AccountID string `json:"account_id"`
			UserID    string `json:"user_id"`
			PhotoData []byte `json:"photo_data"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.SuggestContactPhoto(params.AccountID, params.UserID, params.PhotoData)

	case "SetPersonalContactPhoto":
		var params struct {
			AccountID string `json:"account_id"`
			UserID    string `json:"user_id"`
			PhotoData []byte `json:"photo_data"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.SetPersonalContactPhoto(params.AccountID, params.UserID, params.PhotoData)

	case "ClearPersonalContactPhoto":
		var params struct {
			AccountID string `json:"account_id"`
			UserID    string `json:"user_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.ClearPersonalContactPhoto(params.AccountID, params.UserID)

	case "DeleteContact":
		var req pb.EngineDeleteContactRequest
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

	case "ReadMessageContents":
		var req pb.EngineReadMessageContentsRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.ReadMessageContents(req.AccountId, req.ChatId, req.MsgId)

	case "ReportMusicListen":
		var req pb.EngineReportMusicListenRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.ReportMusicListen(req.AccountId, req.DocId, req.AccessHash, req.FileRef, int(req.DurationSec))

	case "SetUserNoForwardsFlags":
		var req pb.EngineSetUserNoForwardsFlagsRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.SetUserNoForwardsFlags(req.AccountId, req.UserId, req.MyEnabled, req.PeerEnabled)

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
		for i := range topics {
			resp.Topics = append(resp.Topics, forumTopicToProto(&topics[i]))
		}
		return proto.Marshal(resp)

	case "CreateForumTopic":
		var req pb.EngineCreateForumTopicRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		topicId, err := e.CreateForumTopic(req.AccountId, req.ChatId, req.Title, int(req.ColorId), req.IconEmojiId)
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineCreateForumTopicResponse{TopicId: int64(topicId)}
		return proto.Marshal(resp)

	case "EditForumTopic":
		var req pb.EngineEditForumTopicRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.EditForumTopic(req.AccountId, req.ChatId, int(req.TopicId), req.Title, req.IconEmojiId)

	case "PinForumTopic":
		var req pb.EnginePinForumTopicRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.PinForumTopic(req.AccountId, req.ChatId, int(req.TopicId), req.Pinned)

	case "ToggleForumTopicClosed":
		var req pb.EngineToggleForumTopicClosedRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.ToggleForumTopicClosed(req.AccountId, req.ChatId, int(req.TopicId), req.Closed)

	case "ToggleGeneralTopicHidden":
		var req pb.EngineToggleGeneralTopicHiddenRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.ToggleGeneralTopicHidden(req.AccountId, req.ChatId, req.Hidden)

	case "DeleteForumTopicHistory":
		var req pb.EngineEditForumTopicRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.DeleteForumTopicHistory(req.AccountId, req.ChatId, int(req.TopicId))

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
		var entities []cores.TextEntity
		if req.EntitiesJson != "" {
			json.Unmarshal([]byte(req.EntitiesJson), &entities)
		}
		webPageUrl := ""
		forceLargeMedia := false
		forceSmallMedia := false
		invertMedia := false
		webPageOptional := false
		unknown := req.ProtoReflect().GetUnknown()
		for len(unknown) > 0 {
			num, wtype, n := protowire.ConsumeTag(unknown)
			if n < 0 {
				break
			}
			unknown = unknown[n:]
			switch wtype {
			case protowire.VarintType:
				v, vn := protowire.ConsumeVarint(unknown)
				if vn < 0 {
					break
				}
				if num == 10 {
					forceLargeMedia = v != 0
				} else if num == 11 {
					forceSmallMedia = v != 0
				} else if num == 12 {
					invertMedia = v != 0
				} else if num == 13 {
					webPageOptional = v != 0
				}
				unknown = unknown[vn:]
			case protowire.BytesType:
				v, vn := protowire.ConsumeBytes(unknown)
				if vn < 0 {
					break
				}
				if num == 9 {
					webPageUrl = string(v)
				}
				unknown = unknown[vn:]
			case protowire.Fixed32Type:
				_, vn := protowire.ConsumeFixed32(unknown)
				if vn < 0 {
					break
				}
				unknown = unknown[vn:]
			case protowire.Fixed64Type:
				_, vn := protowire.ConsumeFixed64(unknown)
				if vn < 0 {
					break
				}
				unknown = unknown[vn:]
			}
		}
		localID, err := e.SendMessage(req.AccountId, req.ChatId, req.Text, req.ReplyToId, entities, req.Silent, req.ScheduleDate, req.TopicRootId, webPageUrl, forceLargeMedia, forceSmallMedia, invertMedia, webPageOptional)
		if err != nil {
			return nil, err
		}
		return proto.Marshal(&pb.EngineSendMessageResponse{LocalId: localID})

	case "SendContact":
		var req pb.EngineSendContactRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		msgID, err := e.SendContact(req.AccountId, req.ToChatId, req.Phone, req.FirstName, req.LastName, req.UserId)
		if err != nil {
			return nil, err
		}
		return proto.Marshal(&pb.EngineSendContactResponse{LocalId: msgID})

	case "EditMessage":
		var req pb.EngineEditMessageRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.EditMessage(req.AccountId, req.ChatId, req.MsgId, req.NewText, req.EntitiesJson)

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

	case "JoinChannel":
		var req pb.EngineJoinChannelRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.JoinChannel(req.AccountId, req.ChatId)

	case "LeaveChat":
		var req pb.EngineLeaveChatRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.LeaveChat(req.AccountId, req.ChatId)

	case "EditChatTitle":
		var req pb.EngineEditChatTitleRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.EditChatTitle(req.AccountId, req.ChatId, req.Title)

	case "EditChatDescription":
		var req pb.EngineEditChatDescriptionRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.EditChatDescription(req.AccountId, req.ChatId, req.Description)

	case "ToggleForum":
		var req pb.EngineToggleForumRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.ToggleForum(req.AccountId, req.ChatId, req.Enabled)

	case "ClearHistory":
		var req pb.EngineClearHistoryRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.ClearHistory(req.AccountId, req.ChatId)

	case "DeleteChat":
		var req pb.EngineDeleteChatRequest
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

	case "ResendAsOwn":
		var req pb.EngineResendAsOwnRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.ResendAsOwn(req.AccountId, req.SourceChatId, req.MsgId, req.ToChatId, req.Silent, req.ScheduleDate, req.DropCaptions)

	case "ResendAlbumAsOwn":
		var req pb.EngineResendAlbumAsOwnRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.ResendAlbumAsOwn(req.AccountId, req.SourceChatId, req.MsgIds, req.ToChatId, req.Silent, req.ScheduleDate, req.DropCaptions)

	case "SendScheduledNow":
		var req pb.EngineSendScheduledNowRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.SendScheduledNow(req.AccountId, req.ChatId, req.MsgIds)

	case "RescheduleMessage":
		var req pb.EngineRescheduleMessageRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.RescheduleMessage(req.AccountId, req.ChatId, req.MsgId, req.ScheduleDate)

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
		msgID, err := e.UploadFileEx(req.AccountId, req.ChatId, req.FilePath, cores.UploadOptions{
			Caption:         req.Caption,
			CaptionEntities: req.CaptionEntities,
			Silent:          req.Silent,
			ScheduleDate:    int64(req.ScheduleDate),
			Spoiler:         req.Spoiler,
			SendAsDocument:  req.SendAsDocument,
			CaptionAbove:    req.CaptionAbove,
			VideoCoverPath:  req.VideoCoverPath,
		})
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

	case "GetChatMembersByRole":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			Role      string `json:"role"`
			Query     string `json:"query"`
			Limit     int    `json:"limit"`
			Offset    int    `json:"offset"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		result, err := e.GetChatMembersByRole(params.AccountID, params.ChatID, params.Role, params.Query, params.Limit, params.Offset)
		if err != nil {
			return nil, err
		}
		return json.Marshal(result)

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

	case "SetAntiRecallSettings":
		var params struct {
			SaveDeletedMessages bool `json:"save_deleted_messages"`
			SaveMessagesHistory bool `json:"save_messages_history"`
			SaveForBots         bool `json:"save_for_bots"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		e.SetAntiRecallSettings(params.SaveDeletedMessages, params.SaveMessagesHistory, params.SaveForBots)
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
				Waveform:  item.Waveform,
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
				IsChatList:      f.IsChatList,
				Emoticon:        f.Emoticon,
			})
		}
		return proto.Marshal(resp)

	case "CreateFolder":
		var params struct {
			AccountID   string   `json:"account_id"`
			Name        string   `json:"name"`
			ChatIDs     []string `json:"chat_ids"`
			Contacts    bool     `json:"contacts"`
			NonContacts bool     `json:"non_contacts"`
			Groups      bool     `json:"groups"`
			Channels    bool     `json:"channels"`
			Bots        bool     `json:"bots"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		opts := &engine.CreateFolderOpts{
			Contacts:    params.Contacts,
			NonContacts: params.NonContacts,
			Groups:      params.Groups,
			Channels:    params.Channels,
			Bots:        params.Bots,
		}
		fi, err := e.CreateFolder(params.AccountID, params.Name, params.ChatIDs, opts)
		if err != nil {
			return nil, err
		}
		return json.Marshal(fi)

	case "DeleteFolder":
		var req pb.EngineDeleteFolderRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		if err := e.DeleteFolder(req.AccountId, req.FolderId); err != nil {
			return nil, err
		}
		return nil, nil

	case "GetSuggestedFolders":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		suggestions, err := e.GetSuggestedFolders(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(suggestions)

	// ── Folder Invite Links ──

	case "GetFolderInviteLinks":
		var params struct {
			AccountID string `json:"account_id"`
			FolderID  int    `json:"folder_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		links, err := e.GetFolderInviteLinks(params.AccountID, params.FolderID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(links)

	case "CreateFolderInviteLink":
		var params struct {
			AccountID string   `json:"account_id"`
			FolderID  int      `json:"folder_id"`
			Title     string   `json:"title"`
			PeerIDs   []string `json:"peer_ids"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		url, err := e.CreateFolderInviteLink(params.AccountID, params.FolderID, params.Title, params.PeerIDs)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]string{"url": url})

	case "EditFolderInviteLink":
		var params struct {
			AccountID string   `json:"account_id"`
			FolderID  int      `json:"folder_id"`
			Slug      string   `json:"slug"`
			PeerIDs   []string `json:"peer_ids"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		link, err := e.EditFolderInviteLink(params.AccountID, params.FolderID, params.Slug, params.PeerIDs)
		if err != nil {
			return nil, err
		}
		return json.Marshal(link)

	case "DeleteFolderInviteLink":
		var params struct {
			AccountID string `json:"account_id"`
			FolderID  int    `json:"folder_id"`
			Slug      string `json:"slug"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		if err := e.DeleteFolderInviteLink(params.AccountID, params.FolderID, params.Slug); err != nil {
			return nil, err
		}
		return nil, nil

	case "GetLeaveChatlistSuggestions":
		var params struct {
			AccountID string `json:"account_id"`
			FolderID  int    `json:"folder_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		ids, err := e.GetLeaveChatlistSuggestions(params.AccountID, params.FolderID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(ids)

	case "LeaveChatlistFolder":
		var params struct {
			AccountID string   `json:"account_id"`
			FolderID  int      `json:"folder_id"`
			PeerIDs   []string `json:"peer_ids"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		if err := e.LeaveChatlistFolder(params.AccountID, params.FolderID, params.PeerIDs); err != nil {
			return nil, err
		}
		return nil, nil

	// ── Config ──

	case "GetConfig":
		cfg := e.GetConfig()
		resp := &pb.EngineGetConfigResponse{
			Theme:                  cfg.Theme,
			AccentColor:            cfg.AccentColor,
			FontScale:              cfg.FontScale,
			Language:               cfg.Language,
			DownloadDir:            cfg.DownloadDir,
			MaxCacheSize:           cfg.MaxCacheSize,
			SendReadReceipts:       cfg.SendReadReceipts,
			SendTyping:             cfg.SendTyping,
			NotifyDms:              cfg.NotifyDMs,
			NotifyGroups:           cfg.NotifyGroups,
			NotifyMentionsOnly:     cfg.NotifyMentionsOnly,
			SendReadStories:        cfg.SendReadStories,
			SendOnlinePackets:      cfg.SendOnlinePackets,
			SendOfflineAfterOnline: cfg.SendOfflineAfterOnline,
			MarkReadAfterAction:    cfg.MarkReadAfterAction,
			UseScheduledMessages:   cfg.UseScheduledMessages,
			SendWithoutSound:       cfg.SendWithoutSound,
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
		if req.HasSendUploadProgress {
			v := req.SendUploadProgress
			changes.SendUploadProgress = &v
		}
		if req.HasSendReadStories {
			v := req.SendReadStories
			changes.SendReadStories = &v
		}
		if req.HasSendOnlinePackets {
			v := req.SendOnlinePackets
			changes.SendOnlinePackets = &v
		}
		if req.HasSendOfflineAfterOnline {
			v := req.SendOfflineAfterOnline
			changes.SendOfflineAfterOnline = &v
		}
		if req.HasMarkReadAfterAction {
			v := req.MarkReadAfterAction
			changes.MarkReadAfterAction = &v
		}
		if req.HasUseScheduledMessages {
			v := req.UseScheduledMessages
			changes.UseScheduledMessages = &v
		}
		if req.HasSendWithoutSound {
			v := req.SendWithoutSound
			changes.SendWithoutSound = &v
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

	case "MarkAsOnline":
		type statusUpdater interface {
			UpdateStatus(online bool) error
		}
		mu.RLock()
		entries := make([]coreEntry, 0, len(registry))
		for _, entry := range registry {
			entries = append(entries, entry)
		}
		mu.RUnlock()
		for _, entry := range entries {
			if su, ok := entry.instance.(statusUpdater); ok {
				su.UpdateStatus(true)
			}
		}
		return nil, nil

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

	case "GetInviteLink":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		link, err := e.GetInviteLink(params.AccountID, params.ChatID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]string{"link": link})

	case "GetExportedChatInvites":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			Revoked   bool   `json:"revoked"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		links, err := e.GetExportedChatInvites(params.AccountID, params.ChatID, params.Revoked)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]interface{}{"links": links})

	case "CreateChatInviteLink":
		var params struct {
			AccountID       string `json:"account_id"`
			ChatID          string `json:"chat_id"`
			Label           string `json:"label"`
			ExpireDate      int    `json:"expire_date"`
			UsageLimit      int    `json:"usage_limit"`
			RequestApproval bool   `json:"request_approval"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		link, err := e.CreateChatInviteLink(params.AccountID, params.ChatID, params.Label, params.ExpireDate, params.UsageLimit, params.RequestApproval)
		if err != nil {
			return nil, err
		}
		return json.Marshal(link)

	case "EditChatInviteLink":
		var params struct {
			AccountID       string `json:"account_id"`
			ChatID          string `json:"chat_id"`
			Link            string `json:"link"`
			Label           string `json:"label"`
			ExpireDate      int    `json:"expire_date"`
			UsageLimit      int    `json:"usage_limit"`
			RequestApproval bool   `json:"request_approval"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		link, err := e.EditChatInviteLink(params.AccountID, params.ChatID, params.Link, params.Label, params.ExpireDate, params.UsageLimit, params.RequestApproval)
		if err != nil {
			return nil, err
		}
		return json.Marshal(link)

	case "RevokeChatInviteLink":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			Link      string `json:"link"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		link, err := e.RevokeChatInviteLink(params.AccountID, params.ChatID, params.Link)
		if err != nil {
			return nil, err
		}
		return json.Marshal(link)

	case "DeleteRevokedChatInviteLink":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			Link      string `json:"link"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		if err := e.DeleteRevokedChatInviteLink(params.AccountID, params.ChatID, params.Link); err != nil {
			return nil, err
		}
		return nil, nil

	case "DeleteAllRevokedChatInvites":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		if err := e.DeleteAllRevokedChatInvites(params.AccountID, params.ChatID); err != nil {
			return nil, err
		}
		return nil, nil

	case "GetAdminsWithInvites":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		admins, err := e.GetAdminsWithInvites(params.AccountID, params.ChatID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]interface{}{"admins": admins})

	case "GetChatUsername":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		username, err := e.GetChatUsername(params.AccountID, params.ChatID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]string{"username": username})

	case "CheckChannelUsername":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			Username  string `json:"username"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		ok, err := e.CheckChannelUsername(params.AccountID, params.ChatID, params.Username)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]bool{"available": ok})

	case "UpdateChannelUsername":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			Username  string `json:"username"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		if err := e.UpdateChannelUsername(params.AccountID, params.ChatID, params.Username); err != nil {
			return nil, err
		}
		return nil, nil

	case "GetPublicLinksLimits":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		free, premium, err := e.GetPublicLinksLimits(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]int{"free_limit": free, "premium_limit": premium})

	case "GetForumTopicDefaultIcons":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		icons, err := e.GetForumTopicDefaultIcons(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]interface{}{"icons": icons})

	case "GetAccountUsernames":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		usernames, err := e.GetAccountUsernames(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]interface{}{"usernames": usernames})

	case "ToggleAccountUsername":
		var params struct {
			AccountID string `json:"account_id"`
			Username  string `json:"username"`
			Active    bool   `json:"active"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		ok, err := e.ToggleAccountUsername(params.AccountID, params.Username, params.Active)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]bool{"ok": ok})

	case "ReorderAccountUsernames":
		var params struct {
			AccountID string `json:"account_id"`
			Order     []string `json:"order"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		ok, err := e.ReorderAccountUsernames(params.AccountID, params.Order)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]bool{"ok": ok})

	case "GetChannelUsernames":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		usernames, err := e.GetChannelUsernames(params.AccountID, params.ChatID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]interface{}{"usernames": usernames})

	case "ToggleChannelUsername":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			Username  string `json:"username"`
			Active    bool   `json:"active"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		ok, err := e.ToggleChannelUsername(params.AccountID, params.ChatID, params.Username, params.Active)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]bool{"ok": ok})

	case "ReorderChannelUsernames":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			Order     []string `json:"order"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		ok, err := e.ReorderChannelUsernames(params.AccountID, params.ChatID, params.Order)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]bool{"ok": ok})

	case "CheckAccountUsername":
		var params struct {
			AccountID string `json:"account_id"`
			Username  string `json:"username"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		ok, err := e.CheckAccountUsername(params.AccountID, params.Username)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]bool{"available": ok})

	case "UpdateAccountUsername":
		var params struct {
			AccountID string `json:"account_id"`
			Username  string `json:"username"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		if err := e.UpdateAccountUsername(params.AccountID, params.Username); err != nil {
			return nil, err
		}
		return nil, nil

	case "CreatePoll":
		var params struct {
			AccountID      string   `json:"account_id"`
			ChatID         string   `json:"chat_id"`
			Question       string   `json:"question"`
			Options        []string `json:"options"`
			MultipleChoice bool     `json:"multiple_choice"`
			Anonymous      *bool    `json:"anonymous"`
			Quiz           bool     `json:"quiz"`
			CorrectOption  int      `json:"correct_option"`
			Solution       string   `json:"solution"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		anon := true
		if params.Anonymous != nil {
			anon = *params.Anonymous
		}
		msgID, err := e.CreatePollEx(params.AccountID, params.ChatID, params.Question, params.Options, engine.PollOptions{
			MultipleChoice: params.MultipleChoice,
			Anonymous:      anon,
			Quiz:           params.Quiz,
			CorrectOption:  params.CorrectOption,
			Solution:       params.Solution,
		})
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]string{"msg_id": msgID})

	case "GetAdminedPublicChannels":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		channels, err := e.GetAdminedPublicChannels(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(channels)

	case "GetDefaultBannedRights":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		rights, err := e.GetDefaultBannedRights(params.AccountID, params.ChatID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(rights)

	case "GetAdminLogEvents":
		var params struct {
			AccountID string          `json:"account_id"`
			ChatID    string          `json:"chat_id"`
			Limit     int             `json:"limit"`
			Query     string          `json:"query"`
			MaxID     int64           `json:"max_id"`
			Filters   map[string]bool `json:"filters"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		events, err := e.GetAdminLogEvents(params.AccountID, params.ChatID, params.Limit, params.Query, params.MaxID, params.Filters)
		if err != nil {
			return nil, err
		}
		return json.Marshal(events)

	case "SetDefaultBannedRights":
		var params struct {
			AccountID       string `json:"account_id"`
			ChatID          string `json:"chat_id"`
			SendPlain       bool   `json:"send_plain"`
			SendPhotos      bool   `json:"send_photos"`
			SendVideos      bool   `json:"send_videos"`
			SendRoundvideos bool   `json:"send_roundvideos"`
			SendAudios      bool   `json:"send_audios"`
			SendVoices      bool   `json:"send_voices"`
			SendDocs        bool   `json:"send_docs"`
			SendStickers    bool   `json:"send_stickers"`
			EmbedLinks      bool   `json:"embed_links"`
			SendPolls       bool   `json:"send_polls"`
			InviteUsers     bool   `json:"invite_users"`
			ManageTopics    bool   `json:"manage_topics"`
			PinMessages     bool   `json:"pin_messages"`
			EditRank        bool   `json:"edit_rank"`
			ChangeInfo      bool   `json:"change_info"`
			SlowmodeSeconds int    `json:"slowmode_seconds"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		rights := &engine.DefaultBannedRights{
			SendPlain:       params.SendPlain,
			SendPhotos:      params.SendPhotos,
			SendVideos:      params.SendVideos,
			SendRoundvideos: params.SendRoundvideos,
			SendAudios:      params.SendAudios,
			SendVoices:      params.SendVoices,
			SendDocs:        params.SendDocs,
			SendStickers:    params.SendStickers,
			EmbedLinks:      params.EmbedLinks,
			SendPolls:       params.SendPolls,
			InviteUsers:     params.InviteUsers,
			ManageTopics:    params.ManageTopics,
			PinMessages:     params.PinMessages,
			EditRank:        params.EditRank,
			ChangeInfo:      params.ChangeInfo,
			SlowmodeSeconds: params.SlowmodeSeconds,
		}
		if err := e.SetDefaultBannedRights(params.AccountID, params.ChatID, rights); err != nil {
			return nil, err
		}
		return nil, nil

	case "GetChatPermissionFlags":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		flags, err := e.GetChatPermissionFlags(params.AccountID, params.ChatID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(flags)

	case "SetSlowMode":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			Seconds   int    `json:"seconds"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		if err := e.SetSlowMode(params.AccountID, params.ChatID, params.Seconds); err != nil {
			return nil, err
		}
		return nil, nil

	case "ToggleJoinToSend":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			Enabled   bool   `json:"enabled"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		if err := e.ToggleJoinToSend(params.AccountID, params.ChatID, params.Enabled); err != nil {
			return nil, err
		}
		return nil, nil

	case "ToggleNoForwards":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			Enabled   bool   `json:"enabled"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		if err := e.ToggleNoForwards(params.AccountID, params.ChatID, params.Enabled); err != nil {
			return nil, err
		}
		return nil, nil

	case "ToggleJoinRequest":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			Enabled   bool   `json:"enabled"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		if err := e.ToggleJoinRequest(params.AccountID, params.ChatID, params.Enabled); err != nil {
			return nil, err
		}
		return nil, nil

	case "ToggleAntiSpam":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			Enabled   bool   `json:"enabled"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		if err := e.ToggleAntiSpam(params.AccountID, params.ChatID, params.Enabled); err != nil {
			return nil, err
		}
		return nil, nil

	case "TogglePreHistoryHidden":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			Hidden    bool   `json:"hidden"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.TogglePreHistoryHidden(params.AccountID, params.ChatID, params.Hidden)

	case "ToggleSignatures":
		var params struct {
			AccountID       string `json:"account_id"`
			ChatID          string `json:"chat_id"`
			Enabled         bool   `json:"enabled"`
			ProfilesEnabled *bool  `json:"profiles_enabled,omitempty"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		if params.ProfilesEnabled != nil {
			return nil, e.ToggleSignatures(params.AccountID, params.ChatID, params.Enabled, *params.ProfilesEnabled)
		}
		return nil, e.ToggleSignatures(params.AccountID, params.ChatID, params.Enabled)

	case "TogglePeerTranslations":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			Disabled  bool   `json:"disabled"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.TogglePeerTranslations(params.AccountID, params.ChatID, params.Disabled)

	case "SetChatReactionsMode":
		var params struct {
			AccountID string   `json:"account_id"`
			ChatID    string   `json:"chat_id"`
			Mode      string   `json:"mode"`
			Emojis    []string `json:"emojis"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.SetChatReactionsMode(params.AccountID, params.ChatID, params.Mode, params.Emojis)

	case "UpdateChannelColor":
		var params struct {
			AccountID  string `json:"account_id"`
			ChatID     string `json:"chat_id"`
			ColorIndex int    `json:"color_index"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.UpdateChannelColor(params.AccountID, params.ChatID, params.ColorIndex)

	case "UpdatePaidMessagesPrice":
		var params struct {
			AccountID        string `json:"account_id"`
			ChatID           string `json:"chat_id"`
			Stars            int64  `json:"stars"`
			BroadcastEnabled bool   `json:"broadcast_enabled"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.UpdatePaidMessagesPrice(params.AccountID, params.ChatID, params.Stars, params.BroadcastEnabled)

	case "GetFullChatInfo":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		dialog, err := e.GetFullChat(params.AccountID, params.ChatID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(dialog)

	case "GetParticipantInfo":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			UserID    string `json:"user_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		user, err := e.GetParticipantInfo(params.AccountID, params.ChatID, params.UserID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(user)

	case "EditChannelPhoto":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			FilePath  string `json:"file_path"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		var photoData []byte
		if params.FilePath != "" {
			var readErr error
			photoData, readErr = os.ReadFile(params.FilePath)
			if readErr != nil {
				return nil, readErr
			}
		}
		return nil, e.EditChannelPhoto(params.AccountID, params.ChatID, photoData)

	case "DeleteChannelPhoto":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.DeleteChannelPhoto(params.AccountID, params.ChatID)

	case "SetGroupStickerSet":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			ShortName string `json:"short_name"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.SetGroupStickerSet(params.AccountID, params.ChatID, params.ShortName)

	case "SetDiscussionGroup":
		var params struct {
			AccountID   string `json:"account_id"`
			BroadcastID string `json:"broadcast_id"`
			GroupID     string `json:"group_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.SetDiscussionGroup(params.AccountID, params.BroadcastID, params.GroupID)

	case "GetDiscussionGroups":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		groups, err := e.GetDiscussionGroups(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(groups)

	// ── Create Group ──

	case "CreateGroup":
		var params struct {
			AccountID string   `json:"account_id"`
			Name      string   `json:"name"`
			Members   []string `json:"members"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		chat, err := e.CreateGroup(params.AccountID, params.Name, params.Members)
		if err != nil {
			return nil, err
		}
		return json.Marshal(chat)

	// ── Add Members ──

	case "AddMembers":
		var params struct {
			AccountID string   `json:"account_id"`
			ChatID    string   `json:"chat_id"`
			UserIDs   []string `json:"user_ids"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.AddMembers(params.AccountID, params.ChatID, params.UserIDs)

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
				UserId:         c.UserID,
				Username:       sanitizeUTF8(c.Username),
				DisplayName:    sanitizeUTF8(c.DisplayName),
				Phone:          c.Phone,
				AvatarB64:      c.AvatarB64,
				IsBot:          c.IsBot,
				IsOnline:       c.IsOnline,
				StoryCount:     c.StoryCount,
				HasUnreadStory: c.HasUnreadStory,
				IsVerified:     c.IsVerified,
				IsPremium:      c.IsPremium,
				IsScam:         c.IsScam,
				IsFake:         c.IsFake,
				LastSeenKind:   c.LastSeenKind,
				LastSeenTs:     c.LastSeenTs,
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
			Masks:     info.Masks,
			Emojis:    info.Emojis,
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

	case "GetEmojiKeywords":
		var params struct {
			AccountID string `json:"account_id"`
			LangCode  string `json:"lang_code"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		result, err := e.GetEmojiKeywords(params.AccountID, params.LangCode)
		if err != nil {
			return nil, err
		}
		return json.Marshal(result)

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

	case "GetCustomEmojiThumbs":
		var req pb.EngineGetCustomEmojiThumbsRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		thumbs, err := e.GetCustomEmojiThumbs(req.AccountId, req.DocumentIds)
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetCustomEmojiThumbsResponse{}
		for _, t := range thumbs {
			resp.Thumbs = append(resp.Thumbs, &pb.EngineCustomEmojiThumb{
				DocumentId: t.DocumentID,
				ThumbB64:   t.ThumbB64,
				PathB64:    t.PathB64,
			})
		}
		return proto.Marshal(resp)

	case "GetCustomEmojiFiles":
		var req pb.EngineGetCustomEmojiFilesRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		files, err := e.GetCustomEmojiFiles(req.AccountId, req.DocumentIds)
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetCustomEmojiFilesResponse{}
		for _, f := range files {
			resp.Files = append(resp.Files, &pb.EngineCustomEmojiFile{
				DocumentId: f.DocumentID,
				MimeType:   f.MimeType,
				FileData:   f.FileData,
			})
		}
		return proto.Marshal(resp)

	case "GetCustomEmojiSetInfo":
		var req pb.EngineGetCustomEmojiSetInfoRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		setID, accessHash, title, shortName, count, found, err := e.GetCustomEmojiSetInfo(req.AccountId, req.DocumentId)
		if err != nil {
			return nil, err
		}
		return proto.Marshal(&pb.EngineGetCustomEmojiSetInfoResponse{
			SetId:      setID,
			AccessHash: accessHash,
			Title:      title,
			ShortName:  shortName,
			Count:      count,
			Found:      found,
		})

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

	case "UninstallStickerSet":
		var params struct {
			AccountID  string `json:"account_id"`
			SetID      int64  `json:"set_id"`
			AccessHash int64  `json:"access_hash"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		if err := e.UninstallStickerSet(params.AccountID, params.SetID, params.AccessHash); err != nil {
			return nil, err
		}
		return nil, nil

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
		text, err := e.TranslateText(req.AccountId, req.ChatId, req.MsgId, req.ToLang, req.Text)
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
		data, err := proto.Marshal(resp)
		if err != nil {
			return nil, err
		}
		if result != nil {
			if result.Type != "" {
				data = protowire.AppendTag(data, 6, protowire.BytesType)
				data = protowire.AppendString(data, result.Type)
			}
			if result.HasLargeMedia {
				data = protowire.AppendTag(data, 7, protowire.VarintType)
				data = protowire.AppendVarint(data, 1)
			}
			if result.PendingTill > 0 {
				data = protowire.AppendTag(data, 8, protowire.VarintType)
				data = protowire.AppendVarint(data, uint64(result.PendingTill))
			}
		}
		return data, nil

	case "GetInstantViewPage":
		var params struct {
			AccountID string `json:"account_id"`
			URL       string `json:"url"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return e.GetInstantViewPage(params.AccountID, params.URL)

	case "DownloadIVPhoto":
		var params struct {
			AccountID string `json:"account_id"`
			PhotoID   int64  `json:"photo_id"`
			Extra     string `json:"extra"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return e.DownloadIVPhoto(params.AccountID, params.PhotoID, params.Extra)

	case "BotCallback":
		var req pb.EngineBotCallbackRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		isGame := req.Data == "__game"
		data := req.Data
		if isGame {
			data = ""
		}
		result, err := e.BotCallback(req.AccountId, req.ChatId, req.MsgId, data, isGame)
		if err != nil {
			return nil, err
		}
		return proto.Marshal(&pb.EngineBotCallbackResponse{
			Message:   result.Message,
			Url:       result.URL,
			ShowAlert: result.ShowAlert,
		})

	case "RequestBotWebView":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			BotID     string `json:"bot_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		url, err := e.RequestBotWebView(params.AccountID, params.ChatID, params.BotID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]string{"url": url})

	case "RequestURLAuth":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			MsgID     string `json:"msg_id"`
			ButtonID  int    `json:"button_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		result, err := e.RequestURLAuth(params.AccountID, params.ChatID, params.MsgID, params.ButtonID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(result)

	case "AcceptURLAuth":
		var params struct {
			AccountID    string `json:"account_id"`
			ChatID       string `json:"chat_id"`
			MsgID        string `json:"msg_id"`
			ButtonID     int    `json:"button_id"`
			WriteAllowed bool   `json:"write_allowed"`
			SharePhone   bool   `json:"share_phone"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		url, err := e.AcceptURLAuth(params.AccountID, params.ChatID, params.MsgID, params.ButtonID, params.WriteAllowed, params.SharePhone)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]string{"url": url})

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

	case "DownloadSingleAvatar":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		path, err := e.DownloadSingleAvatar(params.AccountID, params.ChatID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]string{"path": path})

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

	case "ClearPaymentInfo":
		var params struct {
			AccountID        string `json:"account_id"`
			ClearCredentials bool   `json:"clear_credentials"`
			ClearShipping    bool   `json:"clear_shipping"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.ClearPaymentInfo(params.AccountID, params.ClearCredentials, params.ClearShipping)

	case "GetPaymentForm":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			MsgID     string `json:"msg_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		form, err := e.GetPaymentForm(params.AccountID, params.ChatID, params.MsgID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(form)

	case "SendPaymentForm":
		var params struct {
			AccountID string                 `json:"account_id"`
			ChatID    string                 `json:"chat_id"`
			MsgID     string                 `json:"msg_id"`
			FormData  map[string]interface{} `json:"form_data"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.SendPaymentForm(params.AccountID, params.ChatID, params.MsgID, params.FormData)

	case "GetPaymentReceipt":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			MsgID     string `json:"msg_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		receipt, err := e.GetPaymentReceipt(params.AccountID, params.ChatID, params.MsgID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(receipt)

	case "GetHideReadMarks":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		hide, err := e.GetHideReadMarks(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]interface{}{
			"hide_read_marks": hide,
		})

	case "SetHideReadMarks":
		var params struct {
			AccountID     string `json:"account_id"`
			HideReadMarks bool   `json:"hide_read_marks"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.SetHideReadMarks(params.AccountID, params.HideReadMarks)

	case "GetMessagesPrivacy":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		option, chargeStars, err := e.GetMessagesPrivacy(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]interface{}{
			"option":       option,
			"charge_stars": chargeStars,
		})

	case "SetMessagesPrivacy":
		var params struct {
			AccountID   string `json:"account_id"`
			Option      string `json:"option"`
			ChargeStars int64  `json:"charge_stars"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.SetMessagesPrivacy(params.AccountID, params.Option, params.ChargeStars)

	case "GetConfcallSizeLimit":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		limit, err := e.GetConfcallSizeLimit(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]interface{}{
			"limit": limit,
		})

	case "GetPaidMessagesConfig":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		maxStars, commissionPermille, withdrawRate, err := e.GetPaidMessagesConfig(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]interface{}{
			"max_stars":              maxStars,
			"commission_permille":    commissionPermille,
			"withdraw_rate":          withdrawRate,
		})

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

	case "GetWallpapers":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		wallpapers, err := e.GetWallpapers(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(wallpapers)

	case "DeleteCloudTheme":
		var params struct {
			AccountID string `json:"account_id"`
			ThemeID   int64  `json:"theme_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		if err := e.DeleteCloudTheme(params.AccountID, params.ThemeID); err != nil {
			return nil, err
		}
		return json.Marshal(map[string]bool{"ok": true})

	case "CreateCloudTheme":
		var params struct {
			AccountID string `json:"account_id"`
			Title     string `json:"title"`
			Slug      string `json:"slug"`
			ThemeData string `json:"theme_data"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		themeBytes, err := base64.StdEncoding.DecodeString(params.ThemeData)
		if err != nil {
			return nil, fmt.Errorf("decode theme data: %w", err)
		}
		info, err := e.CreateCloudTheme(params.AccountID, params.Title, params.Slug, themeBytes)
		if err != nil {
			return nil, err
		}
		return json.Marshal(info)

	case "GetChatThemes":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		themes, err := e.GetChatThemes(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(themes)

	case "SetChatTheme":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			Emoticon  string `json:"emoticon"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		if err := e.SetChatTheme(params.AccountID, params.ChatID, params.Emoticon); err != nil {
			return nil, err
		}
		return json.Marshal(map[string]bool{"ok": true})

	case "UploadProfilePhoto":
		var params struct {
			AccountID string `json:"account_id"`
			FilePath  string `json:"file_path"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.UploadProfilePhoto(params.AccountID, params.FilePath)

	case "UploadFallbackPhoto":
		var params struct {
			AccountID string `json:"account_id"`
			FilePath  string `json:"file_path"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.UploadFallbackPhoto(params.AccountID, params.FilePath)

	case "DeleteFallbackPhoto":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.DeleteFallbackPhoto(params.AccountID)

	case "HasFallbackPhoto":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		has, err := e.HasFallbackPhoto(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]bool{"has": has})

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

	case "SendStoryWithPhoto":
		var params struct {
			AccountID          string   `json:"account_id"`
			Caption            string   `json:"caption"`
			PhotoData          []byte   `json:"photo_data"`
			Privacy            string   `json:"privacy"`
			DurationHours      int      `json:"duration_hours"`
			SaveToProfile      bool     `json:"save_to_profile"`
			AllowSharing       bool     `json:"allow_sharing"`
			SelectedContactIDs []string `json:"selected_contact_ids"`
			TrimStart          float64  `json:"trim_start"`
			TrimEnd            float64  `json:"trim_end"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		opts := cores.StoryPostOptions{
			Privacy:            params.Privacy,
			DurationHours:      params.DurationHours,
			SaveToProfile:      params.SaveToProfile,
			AllowSharing:       params.AllowSharing,
			SelectedContactIDs: params.SelectedContactIDs,
			TrimStart:          params.TrimStart,
			TrimEnd:            params.TrimEnd,
		}
		storyID, err := e.SendStoryWithPhoto(params.AccountID, params.Caption, params.PhotoData, opts)
		if err != nil {
			return nil, err
		}
		resp := map[string]int{"story_id": storyID}
		return json.Marshal(resp)

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

	case "GetMessageReactorsList":
		var params struct {
			AccountID      string `json:"account_id"`
			ChatID         string `json:"chat_id"`
			MsgID          int    `json:"msg_id"`
			Limit          int    `json:"limit"`
			Offset         string `json:"offset"`
			ReactionFilter string `json:"reaction_filter"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		reactors, nextOffset, err := e.GetMessageReactorsList(params.AccountID, params.ChatID, params.MsgID, params.Limit, params.Offset, params.ReactionFilter)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]interface{}{
			"reactors":    reactors,
			"next_offset": nextOffset,
		})

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

	case "GetUnreadMentions":
		var req pb.EngineGetMessagesRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		msgs, err := e.GetUnreadMentions(req.AccountId, req.ChatId, 1)
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetMessagesResponse{}
		for _, m := range msgs {
			resp.Messages = append(resp.Messages, cachedMsgToProto(&m))
		}
		return proto.Marshal(resp)

	case "GetUnreadReactions":
		var req pb.EngineGetMessagesRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		msgs, err := e.GetUnreadReactions(req.AccountId, req.ChatId, 1)
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

	case "VotePollMulti":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			MsgID     string `json:"msg_id"`
			Options   []int  `json:"options"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		if err := e.VotePollMulti(params.AccountID, params.ChatID, params.MsgID, params.Options); err != nil {
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

	case "FetchPeerStories":
		var req pb.EngineFetchPeerStoriesRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		storiesJSON, err := e.FetchPeerStories(req.AccountId, req.PeerId)
		if err != nil {
			return nil, err
		}
		return proto.Marshal(&pb.EngineFetchPeerStoriesResponse{
			StoriesJson: storiesJSON,
		})

	case "GetStoryAlbums":
		var req pb.EngineGetStoryAlbumsRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		albums, err := e.GetStoryAlbums(req.AccountId)
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetStoryAlbumsResponse{}
		for _, a := range albums {
			resp.Albums = append(resp.Albums, &pb.EngineStoryAlbum{
				Id:    a.ID,
				Title: a.Title,
				Count: int32(a.Count),
			})
		}
		return proto.Marshal(resp)

	case "GetAlbumStories":
		var req pb.EngineGetAlbumStoriesRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		storiesJSON, totalCount, err := e.GetAlbumStories(req.AccountId, int64(req.AlbumId), int(req.Offset), int(req.Limit))
		if err != nil {
			return nil, err
		}
		return proto.Marshal(&pb.EngineGetAlbumStoriesResponse{
			StoriesJson: storiesJSON,
			TotalCount:  int32(totalCount),
		})

	case "CreateStoryAlbum":
		var req pb.EngineCreateStoryAlbumRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		albumID, title, err := e.CreateStoryAlbum(req.AccountId, req.Title)
		if err != nil {
			return nil, err
		}
		return proto.Marshal(&pb.EngineCreateStoryAlbumResponse{
			AlbumId: albumID,
			Title:   title,
		})

	case "ReorderStoryAlbums":
		var req pb.EngineReorderStoryAlbumsRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		if err := e.ReorderStoryAlbums(req.AccountId, req.AlbumIds); err != nil {
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

	case "GetAccountTTL":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		days, err := e.GetAccountTTL(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]int{"days": days})

	case "SetAccountTTL":
		var params struct {
			AccountID string `json:"account_id"`
			Days      int    `json:"days"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.SetAccountTTL(params.AccountID, params.Days)

	case "SetCustomDeviceModel":
		var params struct {
			AccountID string `json:"account_id"`
			Model     string `json:"model"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.SetCustomDeviceModel(params.AccountID, params.Model)

	case "GetTopPeersEnabled":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		enabled, err := e.GetTopPeersEnabled(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]bool{"enabled": enabled})

	case "ToggleTopPeers":
		var params struct {
			AccountID string `json:"account_id"`
			Enabled   bool   `json:"enabled"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.ToggleTopPeers(params.AccountID, params.Enabled)

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

	case "ConfirmPasswordEmail":
		var params struct {
			AccountID string `json:"account_id"`
			Code      string `json:"code"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.ConfirmPasswordEmail(params.AccountID, params.Code)

	case "ResendPasswordEmail":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.ResendPasswordEmail(params.AccountID)

	case "CancelPasswordEmail":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.CancelPasswordEmail(params.AccountID)

	case "RequestPasswordRecovery":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		emailPattern, err := e.RequestPasswordRecovery(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]string{"emailPattern": emailPattern})

	case "ResetPassword":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		result, err := e.ResetPassword(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(result)

	case "CancelResetPassword":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.CancelResetPassword(params.AccountID)

	case "SetCloudPasswordEmail":
		var params struct {
			AccountID       string `json:"account_id"`
			CurrentPassword string `json:"current_password"`
			Email           string `json:"email"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.SetCloudPasswordEmail(params.AccountID, params.CurrentPassword, params.Email)

	case "CheckRecoveryPassword":
		var params struct {
			AccountID string `json:"account_id"`
			Code      string `json:"code"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.CheckRecoveryPassword(params.AccountID, params.Code)

	case "RecoverPasswordWithCode":
		var params struct {
			AccountID   string `json:"account_id"`
			Code        string `json:"code"`
			NewPassword string `json:"new_password"`
			Hint        string `json:"hint"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.RecoverPasswordWithCode(params.AccountID, params.Code, params.NewPassword, params.Hint)

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
			Offset    int    `json:"offset"`
			Limit     int    `json:"limit"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		if params.Limit > 0 {
			users, total, err := e.GetBlockedUsersPaged(params.AccountID, params.Offset, params.Limit)
			if err != nil {
				return nil, err
			}
			return json.Marshal(map[string]interface{}{
				"users": users,
				"total": total,
			})
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

	case "TerminateSession":
		var params struct {
			AccountID string `json:"account_id"`
			SessionID string `json:"session_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.TerminateSession(params.AccountID, params.SessionID)

	case "TerminateAllOtherSessions":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.TerminateAllOtherSessions(params.AccountID)

	case "GetSessionAutoTerminateDays":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		days, err := e.GetSessionAutoTerminateDays(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]int{"days": days})

	case "SetSessionAutoTerminateDays":
		var params struct {
			AccountID string `json:"account_id"`
			Days      int    `json:"days"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.SetSessionAutoTerminateDays(params.AccountID, params.Days)

	case "GetLanguages":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		langs, err := e.GetLanguages(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(langs)

	case "SaveLanguagePrefs":
		var params struct {
			AccountID string          `json:"account_id"`
			Prefs     json.RawMessage `json:"prefs"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		if err := e.SaveLanguagePrefs(params.AccountID, params.Prefs); err != nil {
			return nil, err
		}
		return json.Marshal(map[string]bool{"ok": true})

	case "LoadLanguagePrefs":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		data, err := e.LoadLanguagePrefs(params.AccountID)
		if err != nil {
			return nil, err
		}
		return data, nil

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
			AccountID    string   `json:"account_id"`
			Key          string   `json:"key"`
			Option       string   `json:"option"`
			AlwaysIDs    []string `json:"always_ids"`
			NeverIDs     []string `json:"never_ids"`
			AllowPremium bool     `json:"allow_premium"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, setPrivacySetting(e, params.AccountID, params.Key, params.Option, params.AlwaysIDs, params.NeverIDs, params.AllowPremium)

	case "GetAllPrivacySettings":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return getAllPrivacySettings(e, params.AccountID)

	case "GetConnectedBots":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		bots, err := e.GetConnectedBots(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(bots)

	case "ToggleConnectedBotPaused":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			Paused    bool   `json:"paused"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.ToggleConnectedBotPaused(params.AccountID, params.ChatID, params.Paused)

	case "DisablePeerConnectedBot":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.DisablePeerConnectedBot(params.AccountID, params.ChatID)

	case "GetSavedSublists":
		var req pb.EngineGetSavedSublistsRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		sublists, total, err := e.GetSavedSublists(req.AccountId, int(req.Limit), int(req.OffsetDate), int(req.OffsetId), req.ExcludePinned)
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetSavedSublistsResponse{TotalCount: int32(total)}
		for _, s := range sublists {
			resp.Sublists = append(resp.Sublists, &pb.EngineSavedSublist{
				PeerId:      s.PeerID,
				PeerName:    sanitizeUTF8(s.PeerName),
				AvatarPath:  s.AvatarPath,
				Type:        int32(s.Type),
				IsPinned:    s.IsPinned,
				TopMessage:  int32(s.TopMessage),
				LastMsgText: sanitizeUTF8(s.LastMsgText),
				LastMsgTime: s.LastMsgTime,
				IsSelf:      s.IsSelf,
				UnreadCount: int32(s.UnreadCount),
			})
		}
		return proto.Marshal(resp)

	case "GetPinnedSavedSublists":
		var req pb.EngineGetSavedSublistsRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		sublists, total, err := e.GetPinnedSavedSublists(req.AccountId)
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetSavedSublistsResponse{TotalCount: int32(total)}
		for _, s := range sublists {
			resp.Sublists = append(resp.Sublists, &pb.EngineSavedSublist{
				PeerId:      s.PeerID,
				PeerName:    sanitizeUTF8(s.PeerName),
				AvatarPath:  s.AvatarPath,
				Type:        int32(s.Type),
				IsPinned:    s.IsPinned,
				TopMessage:  int32(s.TopMessage),
				LastMsgText: sanitizeUTF8(s.LastMsgText),
				LastMsgTime: s.LastMsgTime,
				IsSelf:      s.IsSelf,
				UnreadCount: int32(s.UnreadCount),
			})
		}
		return proto.Marshal(resp)

	case "GetSavedReactionTags":
		var req pb.EngineGetSavedReactionTagsRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		tags, err := e.GetSavedReactionTags(req.AccountId, req.SublistPeerId)
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetSavedReactionTagsResponse{}
		for _, t := range tags {
			resp.Tags = append(resp.Tags, &pb.EngineSavedReactionTag{
				Emoji:    sanitizeUTF8(t.Emoji),
				CustomId: t.CustomID,
				Title:    sanitizeUTF8(t.Title),
				Count:    int32(t.Count),
			})
		}
		return proto.Marshal(resp)

	case "RenameSavedReactionTag":
		var req pb.EngineRenameSavedReactionTagRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		if err := e.RenameSavedReactionTag(req.AccountId, req.Emoji, req.CustomId, req.Title); err != nil {
			return nil, err
		}
		return nil, nil

	case "AcceptCall":
		var params struct {
			AccountID string `json:"account_id"`
			CallID    string `json:"call_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		callID, err := e.AcceptCall(params.AccountID, params.CallID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]string{"call_id": callID})

	case "DeclineCall":
		var params struct {
			AccountID string `json:"account_id"`
			CallID    string `json:"call_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		if err := e.DeclineCall(params.AccountID, params.CallID); err != nil {
			return nil, err
		}
		return nil, nil

	case "EndCall":
		var params struct {
			AccountID string `json:"account_id"`
			CallID    string `json:"call_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		if err := e.EndCall(params.AccountID, params.CallID); err != nil {
			return nil, err
		}
		return nil, nil

	case "SetCallMuted":
		var params struct {
			AccountID string `json:"account_id"`
			CallID    string `json:"call_id"`
			Muted     bool   `json:"muted"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		if err := e.SetCallMuted(params.AccountID, params.CallID, params.Muted); err != nil {
			return nil, err
		}
		return nil, nil

	case "ToggleCamera":
		var params struct {
			AccountID string `json:"account_id"`
			CallID    string `json:"call_id"`
			Enabled   bool   `json:"enabled"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		if err := e.ToggleCamera(params.AccountID, params.CallID, params.Enabled); err != nil {
			return nil, err
		}
		return nil, nil

	case "ToggleScreenSharing":
		var params struct {
			AccountID string `json:"account_id"`
			CallID    string `json:"call_id"`
			Enabled   bool   `json:"enabled"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		if err := e.ToggleScreenSharing(params.AccountID, params.CallID, params.Enabled); err != nil {
			return nil, err
		}
		return nil, nil

	case "StartCall":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			Video     bool   `json:"video"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		callID, err := e.StartCall(params.AccountID, params.ChatID, params.Video)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]string{"call_id": callID})

	case "CreateConferenceCall":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		callID, inviteLink, err := e.CreateConferenceCall(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]string{"call_id": callID, "invite_link": inviteLink})

	case "ClearCallHistory":
		var req pb.EngineClearCallHistoryRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		if err := e.ClearCallHistory(req.AccountId, req.Revoke); err != nil {
			return nil, err
		}
		return nil, nil

	case "GetCallHistory":
		var params struct {
			AccountID string `json:"account_id"`
			OffsetID  int    `json:"offset_id"`
			Limit     int    `json:"limit"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		entries, err := e.GetCallHistory(params.AccountID, params.OffsetID, params.Limit)
		if err != nil {
			return nil, err
		}
		if entries == nil {
			entries = []engine.CallHistoryEntry{}
		}
		return json.Marshal(entries)

	case "GetOutboxReadDate":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			MsgID     string `json:"msg_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		date, err := e.GetOutboxReadDate(params.AccountID, params.ChatID, params.MsgID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]interface{}{
			"date": date,
		})

	case "GetMessageReadParticipants":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			MsgID     string `json:"msg_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		userIDs, err := e.GetMessageReadParticipants(params.AccountID, params.ChatID, params.MsgID)
		if err != nil {
			return nil, err
		}
		if userIDs == nil {
			userIDs = []int64{}
		}
		return json.Marshal(map[string]interface{}{
			"user_ids": userIDs,
		})

	case "GetMessageReadParticipantsDetailed":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			MsgID     string `json:"msg_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		participants, err := e.GetMessageReadParticipantsDetailed(params.AccountID, params.ChatID, params.MsgID)
		if err != nil {
			if errMsg := err.Error(); strings.HasPrefix(errMsg, "privacy:") {
				return json.Marshal(map[string]interface{}{
					"participants":  []map[string]interface{}{},
					"privacy_state": strings.TrimPrefix(errMsg, "privacy:"),
				})
			}
			return nil, err
		}
		if participants == nil {
			participants = []map[string]interface{}{}
		}
		return json.Marshal(map[string]interface{}{
			"participants": participants,
		})

	case "GetEditRevisions":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			MsgID     string `json:"msg_id"`
			Offset    int    `json:"offset"`
			Limit     int    `json:"limit"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		if params.Limit <= 0 {
			params.Limit = 20
		}
		revisions, err := e.GetEditRevisions(params.AccountID, params.ChatID, params.MsgID, params.Offset, params.Limit)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]interface{}{"revisions": revisions})

	case "HasEditRevisions":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			MsgID     string `json:"msg_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		has, err := e.HasEditRevisions(params.AccountID, params.ChatID, params.MsgID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]interface{}{"has_revisions": has})

	case "GetDeletedMessages":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			Search    string `json:"search"`
			Offset    int    `json:"offset"`
			Limit     int    `json:"limit"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		if params.Limit <= 0 {
			params.Limit = 20
		}
		msgs, err := e.GetDeletedMessages(params.AccountID, params.ChatID, params.Search, params.Offset, params.Limit)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]interface{}{"messages": msgs})

	case "GetBroadcastStatsEngine":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		stats, err := e.GetBroadcastStats(params.AccountID, params.ChatID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(stats)

	case "GetMegagroupStatsEngine":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		stats, err := e.GetMegagroupStats(params.AccountID, params.ChatID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(stats)

	case "GetMessageStatsEngine":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			MsgID     int    `json:"msg_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		stats, err := e.GetMessageStats(params.AccountID, params.ChatID, params.MsgID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(stats)

	case "GetMorePublicForwardsEngine":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			MsgID     int    `json:"msg_id"`
			Offset    string `json:"offset"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		result, err := e.GetMorePublicForwards(params.AccountID, params.ChatID, params.MsgID, params.Offset)
		if err != nil {
			return nil, err
		}
		return json.Marshal(result)

	case "LoadStatsGraphEngine":
		var params struct {
			AccountID string `json:"account_id"`
			Token     string `json:"token"`
			X         int64  `json:"x"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		graph, err := e.LoadStatsGraph(params.AccountID, params.Token, params.X)
		if err != nil {
			return nil, err
		}
		return json.Marshal(graph)

	// ── Saved Sublists ──

	case "ToggleSavedDialogPin":
		var req pb.EnginePinChatRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.ToggleSavedDialogPin(req.AccountId, req.ChatId, req.Pinned)

	case "MarkSavedSublistRead":
		var req pb.EngineMarkSavedSublistReadRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.MarkSavedSublistRead(req.AccountId, req.PeerId)

	case "DeleteSavedSublistHistory":
		var req pb.EngineDeleteSavedSublistHistoryRequest
		if err := proto.Unmarshal(payload, &req); err != nil {
			return nil, err
		}
		return nil, e.DeleteSavedSublistHistory(req.AccountId, req.PeerId)

	// ── Reorder ──

	case "ReorderPinnedDialogs":
		var params struct {
			AccountID string   `json:"account_id"`
			ChatIDs   []string `json:"chat_ids"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.ReorderPinnedDialogs(params.AccountID, params.ChatIDs)

	case "ReorderDialogFilters":
		var params struct {
			AccountID string `json:"account_id"`
			FilterIDs []int  `json:"filter_ids"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.ReorderDialogFilters(params.AccountID, params.FilterIDs)

	case "ToggleDialogFilterTags":
		var params struct {
			AccountID string `json:"account_id"`
			Enabled   bool   `json:"enabled"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		ok, err := e.ToggleDialogFilterTags(params.AccountID, params.Enabled)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]bool{"ok": ok})

	// ── Forum Topics with Offset ──

	case "GetForumTopicsWithOffset":
		var params struct {
			AccountID   string `json:"account_id"`
			ChatID      string `json:"chat_id"`
			OffsetDate  int    `json:"offset_date"`
			OffsetID    int    `json:"offset_id"`
			OffsetTopic int    `json:"offset_topic"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		topics, err := e.GetForumTopicsWithOffset(params.AccountID, params.ChatID, params.OffsetDate, params.OffsetID, params.OffsetTopic)
		if err != nil {
			return nil, err
		}
		resp := &pb.EngineGetForumTopicsResponse{}
		for i := range topics {
			resp.Topics = append(resp.Topics, forumTopicToProto(&topics[i]))
		}
		return proto.Marshal(resp)

	// ── Data Export ──

	case "StartExport":
		var params engine.ExportSettings
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		if err := e.StartExport(params.AccountID, params); err != nil {
			return nil, err
		}
		return json.Marshal(map[string]bool{"ok": true})

	case "SkipExportFile":
		var params struct {
			AccountID string `json:"account_id"`
			RandomID  uint64 `json:"random_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		e.SkipExportFile(params.AccountID, params.RandomID)
		return json.Marshal(map[string]bool{"ok": true})

	case "CancelExport":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		e.CancelExport(params.AccountID)
		return json.Marshal(map[string]bool{"ok": true})

	case "SaveExportSettings":
		var params struct {
			AccountID string          `json:"account_id"`
			Settings  json.RawMessage `json:"settings"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		if err := e.SaveExportSettings(params.AccountID, params.Settings); err != nil {
			return nil, err
		}
		return json.Marshal(map[string]bool{"ok": true})

	case "LoadExportSettings":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		data, err := e.LoadExportSettings(params.AccountID)
		if err != nil {
			return nil, err
		}
		return data, nil

	case "MarkChatUnread":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.MarkChatUnread(params.AccountID, params.ChatID)

	case "AddChatToFolder":
		var params struct {
			AccountID string `json:"account_id"`
			ChatID    string `json:"chat_id"`
			FolderID  string `json:"folder_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.AddChatToFolder(params.AccountID, params.ChatID, params.FolderID)

	case "GetTopPeers":
		var params struct {
			AccountID string `json:"account_id"`
			Limit     int    `json:"limit"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		peers, err := e.GetTopPeers(params.AccountID, params.Limit)
		if err != nil {
			return nil, err
		}
		if peers == nil {
			peers = []engine.ChatInfo{}
		}
		return json.Marshal(peers)

	case "RemoveSavedReactionTag":
		var params struct {
			AccountID string `json:"account_id"`
			Emoji     string `json:"emoji"`
			CustomID  int64  `json:"custom_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.RemoveSavedReactionTag(params.AccountID, params.Emoji, params.CustomID)

	case "SearchGlobalChats":
		var params struct {
			AccountID string `json:"account_id"`
			Query     string `json:"query"`
			Limit     int    `json:"limit"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		chats, err := e.SearchGlobalChats(params.AccountID, params.Query, params.Limit)
		if err != nil {
			return nil, err
		}
		return json.Marshal(chats)

	case "GetContactSignUpNotification":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		enabled, err := e.GetContactSignUpNotification(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(map[string]bool{"enabled": enabled})

	case "SetContactSignUpNotification":
		var params struct {
			AccountID string `json:"account_id"`
			Silent    bool   `json:"silent"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.SetContactSignUpNotification(params.AccountID, params.Silent)

	case "SetCallsDisabledHere":
		var params struct {
			AccountID string `json:"account_id"`
			Disabled  bool   `json:"disabled"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.SetCallsDisabledHere(params.AccountID, params.Disabled)

	case "UpdateDefaultNotifySettings":
		var params struct {
			AccountID    string `json:"account_id"`
			PeerType     string `json:"peer_type"`
			Enabled      bool   `json:"enabled"`
			SoundEnabled *bool  `json:"sound_enabled,omitempty"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		var silent *bool
		if params.SoundEnabled != nil {
			s := !*params.SoundEnabled
			silent = &s
		}
		return nil, e.UpdateDefaultNotifySettings(params.AccountID, params.PeerType, params.Enabled, silent)

	case "GetDefaultNotifySettings":
		var params struct {
			AccountID string `json:"account_id"`
			PeerType  string `json:"peer_type"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		settings, err := e.GetDefaultNotifySettings(params.AccountID, params.PeerType)
		if err != nil {
			return nil, err
		}
		return json.Marshal(settings)

	case "GetReactionsNotifySettings":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		settings, err := e.GetReactionsNotifySettings(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(settings)

	case "SetReactionsNotifySettings":
		var params struct {
			AccountID        string `json:"account_id"`
			ReactionsEnabled bool   `json:"reactions_enabled"`
			ReactionsFrom    string `json:"reactions_from"`
			PollVotesEnabled bool   `json:"poll_votes_enabled"`
			PollVotesFrom    string `json:"poll_votes_from"`
			ShowSenderName   bool   `json:"show_sender_name"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		return nil, e.SetReactionsNotifySettings(params.AccountID, params.ReactionsEnabled, params.ReactionsFrom, params.PollVotesEnabled, params.PollVotesFrom, params.ShowSenderName)

	case "GetSavedRingtones":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		tones, err := e.GetSavedRingtones(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(tones)

	case "GetMutedChatsByType":
		var params struct {
			AccountID string `json:"account_id"`
		}
		if err := json.Unmarshal(payload, &params); err != nil {
			return nil, err
		}
		counts, err := e.GetMutedChatsByType(params.AccountID)
		if err != nil {
			return nil, err
		}
		return json.Marshal(counts)

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

func setPrivacySetting(e *engine.Engine, accountID, key, option string, alwaysIDs, neverIDs []string, allowPremium bool) error {
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
	if allowPremium {
		rules = append(rules, &tg.InputPrivacyValueAllowPremium{})
	}
	return tgCore.SetPrivacy(inputKey, rules)
}

func getAllPrivacySettings(e *engine.Engine, accountID string) ([]byte, error) {
	keys := []string{"phone_number", "last_seen", "profile_photo", "forwards", "calls", "voice_messages", "chat_invite", "birthday", "gifts", "about", "saved_music", "added_by_phone"}
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
		IsForum:               c.IsForum,
		WriteRestrictionType:  int32(c.WriteRestrictionType),
		WriteRestrictionText:  c.WriteRestrictionText,
		NotJoined:            c.NotJoined,
		JoinRequest:          c.JoinRequest,
		CanPost:              c.CanPost,
		NoForwards:           c.NoForwards,
		IsSelf:               c.IsSelf,
	}
}

func forumTopicToProto(ft *cores.ForumTopic) *pb.EngineForumTopic {
	return &pb.EngineForumTopic{
		Id:              ft.ID,
		Title:           sanitizeUTF8(ft.Title),
		ColorId:         int32(ft.ColorID),
		IconEmojiId:     ft.IconEmojiID,
		CreatorId:       ft.CreatorID,
		CreationDate:    ft.CreationDate,
		IsClosed:        ft.IsClosed,
		IsHidden:        ft.IsHidden,
		IsMy:            ft.IsMy,
		IsPinned:        ft.IsPinned,
		UnreadCount:     int32(ft.UnreadCount),
		UnreadMentions:  int32(ft.UnreadMentions),
		UnreadReactions: int32(ft.UnreadReactions),
		TopMessageId:    ft.TopMessageID,
		ReadInboxMaxId:  int32(ft.ReadInboxMaxID),
		ReadOutboxMaxId: int32(ft.ReadOutboxMaxID),
		ParentId:        ft.ParentID,
		CanEdit:         ft.CanEdit,
		CanDelete:       ft.CanDelete,
		CanToggleClosed: ft.CanToggleClosed,
		CanTogglePinned: ft.CanTogglePinned,
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
		SenderNoForwards:   m.SenderNoForwards,
	}
}

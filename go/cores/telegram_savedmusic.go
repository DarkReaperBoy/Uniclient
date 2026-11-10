//go:build !js

package cores

import (
	"encoding/base64"
	"fmt"
	"strconv"
	"time"

	"github.com/gotd/td/tg"
)

func NormalizeMusicDoc(d *tg.Document) (MusicTrackInfo, bool) {
	var tr MusicTrackInfo
	var audio *tg.DocumentAttributeAudio
	for _, a := range d.Attributes {
		switch at := a.(type) {
		case *tg.DocumentAttributeAudio:
			audio = at
		case *tg.DocumentAttributeFilename:
			tr.FileName = at.FileName
		}
	}
	if audio == nil || audio.Voice {
		return tr, false
	}
	tr.DocID = strconv.FormatInt(d.ID, 10)
	tr.AccessHash = d.AccessHash
	tr.FileRefB64 = base64.StdEncoding.EncodeToString(d.FileReference)
	if t, ok := audio.GetTitle(); ok {
		tr.Title = t
	}
	if p, ok := audio.GetPerformer(); ok {
		tr.Performer = p
	}
	tr.Duration = audio.Duration
	tr.Size = d.Size
	tr.MimeType = d.MimeType
	return tr, true
}

func ProfileMusicSaveRequest(track, after MusicTrackInfo, unsave bool) *tg.AccountSaveMusicRequest {
	req := &tg.AccountSaveMusicRequest{
		ID: &tg.InputDocument{
			ID:            mustInt64(track.DocID),
			AccessHash:    track.AccessHash,
			FileReference: fileRefBytes(track.FileRefB64),
		},
	}
	if unsave {
		req.SetUnsave(true)
	}
	if after.DocID != "" {
		req.SetAfterID(&tg.InputDocument{
			ID:            mustInt64(after.DocID),
			AccessHash:    after.AccessHash,
			FileReference: fileRefBytes(after.FileRefB64),
		})
	}
	return req
}

func mustInt64(s string) int64 {
	n, _ := strconv.ParseInt(s, 10, 64)
	return n
}

func fileRefBytes(b64 string) []byte {
	if b64 == "" {
		return nil
	}
	raw, err := base64.StdEncoding.DecodeString(b64)
	if err != nil {
		return nil
	}
	return raw
}

func (t *TelegramCore) GetProfileMusic(peerID string) ([]MusicTrackInfo, int, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, 0, err
	}
	inputPeer, unlock, perr := t.withPeer(peerID)
	if perr != nil {
		return nil, 0, fmt.Errorf("resolve peer: %w", perr)
	}
	user, ok := inputPeer.(*tg.InputPeerUser)
	unlock()
	if !ok {
		return nil, 0, fmt.Errorf("%w: profile music needs a user peer", ErrNotSupported)
	}

	res, err := api.UsersGetSavedMusic(ctx, &tg.UsersGetSavedMusicRequest{
		ID:     &tg.InputUser{UserID: user.UserID, AccessHash: user.AccessHash},
		Offset: 0,
		Limit:  100,
		Hash:   0,
	})
	if err != nil {
		return nil, 0, err
	}
	switch r := res.(type) {
	case *tg.UsersSavedMusic:
		tracks := make([]MusicTrackInfo, 0, len(r.Documents))
		for _, dc := range r.Documents {
			if d, ok := dc.(*tg.Document); ok {
				if tr, is := NormalizeMusicDoc(d); is {
					tracks = append(tracks, tr)
				}
			}
		}
		return tracks, r.Count, nil
	case *tg.UsersSavedMusicNotModified:
		return nil, r.Count, nil
	default:
		return nil, 0, fmt.Errorf("unexpected users.getSavedMusic result %T", res)
	}
}

func (t *TelegramCore) SaveProfileMusicDoc(track, after MusicTrackInfo, unsave bool) error {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return err
	}
	_, err = api.AccountSaveMusic(ctx, ProfileMusicSaveRequest(track, after, unsave))
	return err
}

func (t *TelegramCore) GetOwnSavedMusicIDs(hash int64) ([]string, bool, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, false, err
	}
	res, err := api.AccountGetSavedMusicIDs(ctx, hash)
	if err != nil {
		return nil, false, err
	}
	switch r := res.(type) {
	case *tg.AccountSavedMusicIDs:
		ids := make([]string, len(r.IDs))
		for i, id := range r.IDs {
			ids[i] = strconv.FormatInt(id, 10)
		}
		return ids, true, nil
	case *tg.AccountSavedMusicIDsNotModified:
		return nil, false, nil
	default:
		return nil, false, fmt.Errorf("unexpected account.getSavedMusicIDs result %T", res)
	}
}

func AudioSendMediaRequest(track MusicTrackInfo, caption string, silent bool, scheduleDate int, randomID int64) *tg.MessagesSendMediaRequest {
	req := &tg.MessagesSendMediaRequest{
		RandomID: randomID,
		Media: &tg.InputMediaDocument{ID: &tg.InputDocument{
			ID:            mustInt64(track.DocID),
			AccessHash:    track.AccessHash,
			FileReference: fileRefBytes(track.FileRefB64),
		}},
		Message: caption,
		Silent:  silent,
	}
	if scheduleDate > 0 {
		req.SetScheduleDate(scheduleDate)
	}
	return req
}

func (t *TelegramCore) SendAudioDocument(chatID string, track MusicTrackInfo, caption string, silent bool, scheduleDate int) (*Message, error) {
	api, ctx, err := t.WithAPI()
	if err != nil {
		return nil, err
	}
	inputPeer, unlock, perr := t.withPeer(chatID)
	if perr != nil {
		return nil, fmt.Errorf("resolve peer: %w", perr)
	}
	defer unlock()
	req := AudioSendMediaRequest(track, caption, silent, scheduleDate, time.Now().UnixNano())
	req.Peer = inputPeer
	result, err := api.MessagesSendMedia(ctx, req)
	if err != nil {
		return nil, err
	}
	return t.extractMessageFromUpdates(result, chatID), nil
}

package engine

import (
	"database/sql"
	"fmt"
	"time"

	"uniclient/cores"
)

// Voice-message transcription (slice 115, Telegram messages.transcribeAudio
// + updateTranscribedAudio parity): the user taps the "A→A" glyph on a voice
// bubble, the engine calls the core's TranscribeAudio, and the result —
// immediately when final, or via the pushed update when the server needs
// time — is stored per message and hydrated into CachedMessage rows so the
// bubble renders the text block. Transcriptions only exist for messages the
// user explicitly asked about (matching Telegram Desktop's behavior).

// TranscriptionSupported reports whether the account's core can transcribe
// voice messages (VoiceTranscriber).
func (e *Engine) TranscriptionSupported(accountID string) bool {
	e.accountsMu.RLock()
	acc := e.accounts[accountID]
	e.accountsMu.RUnlock()
	if acc == nil || acc.Core == nil {
		return false
	}
	_, ok := acc.Core.(VoiceTranscriber)
	return ok
}

// TranscribeVoiceNote requests a transcription for one voice message.
// Returns the text and whether the server is still working (pending results
// arrive later via UpdateTranscription; the engine stores them and emits
// EventMsgTranscribed). Errors are passed through verbatim so the GUI can
// surface the server's own reasons (premium-required, forbidden, ...).
func (e *Engine) TranscribeVoiceNote(accountID, chatID, msgID string) (text string, pending bool, err error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return "", false, fmt.Errorf("account not found: %s", accountID)
	}
	if acc.Core == nil {
		return "", false, fmt.Errorf("account not connected: %s", accountID)
	}
	transcriber, ok := acc.Core.(VoiceTranscriber)
	if !ok {
		return "", false, fmt.Errorf("platform does not support voice transcription")
	}
	pend, tid, txt, err := transcriber.TranscribeAudio(chatID, msgID)
	if err != nil {
		return "", false, err
	}
	if _, serr := e.storeTranscription(accountID, chatID, msgID, tid, txt, pend); serr != nil {
		// The transcription worked server-side; a local store failure must
		// not turn into a user-facing error — still return the text.
		return txt, pend, nil
	}
	return txt, pend, nil
}

// GetCachedTranscription returns the stored transcription for one message
// ("" / false when none exists).
func (e *Engine) GetCachedTranscription(accountID, chatID, msgID string) (text string, pending bool) {
	var txt string
	var pend int
	err := e.db.QueryRow(
		`SELECT text, pending FROM message_transcriptions
                 WHERE account_id = ? AND chat_id = ? AND msg_id = ? LIMIT 1`,
		accountID, chatID, msgID).Scan(&txt, &pend)
	if err != nil {
		return "", false
	}
	return txt, pend != 0
}

// storeTranscription upserts one transcription row (latest write wins —
// the server can refine the text across pushes).
func (e *Engine) storeTranscription(accountID, chatID, msgID string, transcriptionID int64, text string, pending bool) (sql.Result, error) {
	return e.db.Exec(
		`INSERT INTO message_transcriptions (account_id, chat_id, msg_id, transcription_id, pending, text, created_at)
                 VALUES (?, ?, ?, ?, ?, ?, ?)
                 ON CONFLICT(account_id, chat_id, msg_id) DO UPDATE SET
                   transcription_id = excluded.transcription_id,
                   pending = excluded.pending,
                   text = excluded.text`,
		accountID, chatID, msgID, transcriptionID, boolToInt(pending), text, time.Now().UnixMilli())
}

// populateTranscriptions hydrates the transcription fields of a chat's
// cached messages in one query (only rows that have one).
func (e *Engine) populateTranscriptions(accountID, chatID string, msgs []CachedMessage) {
	if len(msgs) == 0 {
		return
	}
	rows, err := e.db.Query(
		`SELECT msg_id, text, pending FROM message_transcriptions
                 WHERE account_id = ? AND chat_id = ?`,
		accountID, chatID)
	if err != nil {
		return
	}
	defer rows.Close()
	for rows.Next() {
		var msgID, text string
		var pend int
		if err := rows.Scan(&msgID, &text, &pend); err != nil {
			return
		}
		for i := range msgs {
			if msgs[i].MsgID == msgID && !msgs[i].IsService {
				msgs[i].TranscriptionText = text
				msgs[i].TranscriptionPending = pend != 0
			}
		}
	}
}

// handleTranscriptionUpdate applies a pushed transcription (cores.
// UpdateTranscription → tg.updateTranscribedAudio). Only messages that
// already have a row (the user asked for them) are updated — unsolicited
// transcriptions stay invisible, matching Telegram Desktop.
func (e *Engine) handleTranscriptionUpdate(accountID, chatID string, tr *cores.TranscriptionUpdate) {
	if tr == nil || tr.MessageID == "" {
		return
	}
	res, err := e.db.Exec(
		`UPDATE message_transcriptions
                 SET transcription_id = ?, pending = ?, text = ?
                 WHERE account_id = ? AND chat_id = ? AND msg_id = ?`,
		tr.TranscriptionID, boolToInt(tr.Pending), tr.Text,
		accountID, chatID, tr.MessageID)
	if err != nil {
		return
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return // nobody asked for this message's transcription
	}
	e.emitEvent(EventMsgTranscribed, accountID, MsgTranscribedEvent{
		ChatID:  chatID,
		MsgID:   tr.MessageID,
		Text:    tr.Text,
		Pending: tr.Pending,
	})
}

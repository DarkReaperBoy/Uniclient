package engine

import (
	"database/sql"
	"fmt"
	"time"

	"uniclient/cores"
)

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
	if _, serr := e.StoreTranscription(accountID, chatID, msgID, tid, txt, pend); serr != nil {
		return txt, pend, nil
	}
	return txt, pend, nil
}

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

func (e *Engine) StoreTranscription(accountID, chatID, msgID string, transcriptionID int64, text string, pending bool) (sql.Result, error) {
	return e.db.Exec(
		`INSERT INTO message_transcriptions (account_id, chat_id, msg_id, transcription_id, pending, text, created_at)
                 VALUES (?, ?, ?, ?, ?, ?, ?)
                 ON CONFLICT(account_id, chat_id, msg_id) DO UPDATE SET
                   transcription_id = excluded.transcription_id,
                   pending = excluded.pending,
                   text = excluded.text`,
		accountID, chatID, msgID, transcriptionID, boolToInt(pending), text, time.Now().UnixMilli())
}

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
		return
	}
	e.emitEvent(EventMsgTranscribed, accountID, MsgTranscribedEvent{
		ChatID:  chatID,
		MsgID:   tr.MessageID,
		Text:    tr.Text,
		Pending: tr.Pending,
	})
}

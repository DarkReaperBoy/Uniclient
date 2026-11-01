package engine

import (
	"database/sql"
	"log"
)

type viewsProvider interface {
	GetMessagesViewsBatch(chatID string, msgIDs []string) (views, forwards map[string]int, err error)
}

const viewsRefreshCap = 60

func (e *Engine) RefreshMessageViews(accountID, chatID string) (int, error) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return 0, nil
	}
	p, ok := acc.Core.(viewsProvider)
	if !ok {
		return 0, nil
	}

	var chatType int
	err := e.db.QueryRow(
		`SELECT type FROM chats WHERE account_id = ? AND chat_id = ?`, accountID, chatID).Scan(&chatType)
	if err != nil || chatType != ChatTypeChanVal {
		return 0, nil
	}

	rows, err := e.db.Query(
		`SELECT msg_id FROM messages
                 WHERE account_id = ? AND chat_id = ? AND is_service = 0 AND is_deleted = 0
                 ORDER BY timestamp DESC LIMIT ?`,
		accountID, chatID, viewsRefreshCap)
	if err != nil {
		return 0, err
	}
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return 0, err
		}
		ids = append(ids, id)
	}
	rows.Close()
	if len(ids) == 0 {
		return 0, nil
	}

	views, forwards, err := p.GetMessagesViewsBatch(chatID, ids)
	if err != nil {
		log.Printf("[engine] RefreshMessageViews(%s, %s): %v", accountID, chatID, err)
		return 0, nil
	}

	changed := 0
	tx, err := e.db.Begin()
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	stmt, err := tx.Prepare(
		`UPDATE messages SET views = ?, forwards = ? WHERE account_id = ? AND chat_id = ? AND msg_id = ?`)
	if err != nil {
		return 0, err
	}
	defer stmt.Close()
	for _, id := range ids {
		v := views[id]
		f := forwards[id]
		var oldV, oldF int
		qerr := tx.QueryRow(
			`SELECT views, forwards FROM messages WHERE account_id = ? AND chat_id = ? AND msg_id = ?`,
			accountID, chatID, id).Scan(&oldV, &oldF)
		if qerr == sql.ErrNoRows {
			continue
		}
		if qerr != nil {
			return changed, qerr
		}
		if v == oldV && f == oldF {
			continue
		}
		if _, uerr := stmt.Exec(v, f, accountID, chatID, id); uerr != nil {
			return changed, uerr
		}
		changed++
	}
	if err := tx.Commit(); err != nil {
		return changed, err
	}
	if changed > 0 {
		e.emitChatUpdate(accountID, chatID)
	}
	return changed, nil
}

const ViewsRefreshInterval = 30

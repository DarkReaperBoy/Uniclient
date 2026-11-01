package engine

import (
	"database/sql"
	"fmt"
	"regexp"
	"strings"
	"time"
)

type AyuFilter struct {
	ID        int64  `json:"id"`
	Pattern   string `json:"pattern"`
	Enabled   bool   `json:"enabled"`
	CreatedAt int64  `json:"created_at"`
}

func (e *Engine) AddAyuFilter(pattern string) (AyuFilter, error) {
	pattern = strings.TrimSpace(pattern)
	if pattern == "" {
		return AyuFilter{}, fmt.Errorf("empty pattern")
	}
	if _, err := regexp.Compile(pattern); err != nil {
		return AyuFilter{}, fmt.Errorf("invalid regex: %w", err)
	}
	f := AyuFilter{Pattern: pattern, Enabled: true, CreatedAt: time.Now().UnixMilli()}
	res, err := e.db.Exec(
		`INSERT INTO ayu_filters (pattern, enabled, created_at) VALUES (?, 1, ?)`,
		f.Pattern, f.CreatedAt)
	if err != nil {
		return AyuFilter{}, err
	}
	f.ID, _ = res.LastInsertId()
	return f, nil
}

func (e *Engine) ListAyuFilters() []AyuFilter {
	rows, err := e.db.Query(`SELECT id, pattern, enabled, created_at FROM ayu_filters ORDER BY id DESC`)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var out []AyuFilter
	for rows.Next() {
		var f AyuFilter
		var en int
		if err := rows.Scan(&f.ID, &f.Pattern, &en, &f.CreatedAt); err != nil {
			continue
		}
		f.Enabled = en != 0
		out = append(out, f)
	}
	return out
}

func (e *Engine) SetAyuFilterEnabled(id int64, enabled bool) error {
	v := 0
	if enabled {
		v = 1
	}
	_, err := e.db.Exec(`UPDATE ayu_filters SET enabled = ? WHERE id = ?`, v, id)
	return err
}

func (e *Engine) RemoveAyuFilter(id int64) error {
	_, err := e.db.Exec(`DELETE FROM ayu_filters WHERE id = ?`, id)
	return err
}

func (e *Engine) enabledAyuRegexes() []*regexp.Regexp {
	var regs []*regexp.Regexp
	for _, f := range e.ListAyuFilters() {
		if !f.Enabled {
			continue
		}
		if re, err := regexp.Compile(f.Pattern); err == nil {
			regs = append(regs, re)
		}
	}
	return regs
}

func FilterMessagesByRegexes(msgs []CachedMessage, regs []*regexp.Regexp) []CachedMessage {
	if len(regs) == 0 || len(msgs) == 0 {
		return msgs
	}
	out := msgs[:0:0]
	for _, m := range msgs {
		hide := false
		if m.ContentText != "" {
			for _, re := range regs {
				if re.MatchString(m.ContentText) {
					hide = true
					break
				}
			}
		}
		if !hide {
			out = append(out, m)
		}
	}
	return out
}

func (e *Engine) ayuFiltersTableExists() bool {
	var name string
	err := e.db.QueryRow(`SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'ayu_filters'`).Scan(&name)
	return err == nil
}

func (e *Engine) applyAyuFilters(msgs []CachedMessage) []CachedMessage {
	if !e.ayuFiltersTableExists() {
		return msgs
	}
	return FilterMessagesByRegexes(msgs, e.enabledAyuRegexes())
}

var _ = sql.ErrNoRows

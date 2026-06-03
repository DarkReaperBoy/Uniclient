package engine

import (
	"context"
	"encoding/json"
	"fmt"
	"math/rand"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"uniclient/cores"
)

type ExportSettings struct {
	AccountID       string `json:"account_id"`
	PersonalInfo    bool   `json:"personal_info"`
	Contacts        bool   `json:"contacts"`
	Stories         bool   `json:"stories"`
	ProfileMusic    bool   `json:"profile_music"`
	PersonalChats   bool   `json:"personal_chats"`
	BotChats        bool   `json:"bot_chats"`
	PrivateGroups   bool   `json:"private_groups"`
	PrivateChannels bool   `json:"private_channels"`
	PublicGroups    bool   `json:"public_groups"`
	PublicChannels  bool   `json:"public_channels"`
	MediaPhotos     bool   `json:"media_photos"`
	MediaVideo      bool   `json:"media_video"`
	MediaVoice      bool   `json:"media_voice"`
	MediaVideoMsg   bool   `json:"media_video_message"`
	MediaSticker    bool   `json:"media_sticker"`
	MediaGif        bool   `json:"media_gif"`
	MediaFile       bool   `json:"media_file"`
	SizeLimitMB     int    `json:"size_limit_mb"`
	Format          string `json:"format"`
	ExportLocation  string `json:"export_location"`
	ChatID          string `json:"chat_id,omitempty"`
	TopicRootID     int    `json:"topic_root_id,omitempty"`
	Sessions        bool   `json:"sessions"`
	OtherData       bool   `json:"other_data"`
}

type ExportProgressEvent struct {
	Step         string  `json:"step"`
	StepIndex    int     `json:"step_index"`
	TotalSteps   int     `json:"total_steps"`
	Progress     float64 `json:"progress"`
	Info         string  `json:"info"`
	TotalFiles   int     `json:"total_files"`
	TotalSize    int64   `json:"total_size_bytes"`
	FileRandomID uint64  `json:"file_random_id,omitempty"`
	FileName     string  `json:"file_name,omitempty"`
}

type ExportErrorEvent struct {
	ErrorType      string `json:"error_type"`
	Code           int    `json:"code,omitempty"`
	ErrorName      string `json:"error_name,omitempty"`
	Description    string `json:"description,omitempty"`
	Path           string `json:"path,omitempty"`
	HoursRemaining int    `json:"hours_remaining,omitempty"`
	AvailableAtMS  int64  `json:"available_at_ms,omitempty"`
}

type ExportCompleteEvent struct {
	ExportPath string `json:"export_path"`
	TotalFiles int    `json:"total_files"`
	TotalSize  int64  `json:"total_size_bytes"`
}

// ExportSuggestEvent is emitted when a previously-delayed takeout export becomes
// available and the user should be re-prompted to start it (AyuGram's "Data
// export ready" box, Export::View::SuggestStart).
type ExportSuggestEvent struct {
	AvailableAtMS int64 `json:"available_at_ms"`
}

type exportState struct {
	mu           sync.Mutex
	cancel       context.CancelFunc
	skipFileCh   chan uint64
	running      bool
	totalFiles   int
	totalSize    int64
	fileRandomID uint64
}

type takeoutProvider interface {
	InitTakeout(contacts, msgUsers, msgChats, msgMegagroups, msgChannels, files bool, fileMaxSizeBytes int64) (int64, error)
	FinishTakeout() error
}

type exportStep struct {
	label string
	run   func(ctx context.Context, state *exportState) error
}

func (e *Engine) StartExport(accountID string, settings ExportSettings) error {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		return fmt.Errorf("account %q not found or not connected", accountID)
	}

	e.CancelExport(accountID)

	ctx, cancel := context.WithCancel(context.Background())
	state := &exportState{
		cancel:     cancel,
		skipFileCh: make(chan uint64, 1),
		running:    true,
	}

	e.exportMu.Lock()
	if e.exports == nil {
		e.exports = make(map[string]*exportState)
	}
	e.exports[accountID] = state
	e.exportMu.Unlock()

	e.wg.Add(1)
	go func() {
		defer e.wg.Done()
		defer func() {
			e.exportMu.Lock()
			delete(e.exports, accountID)
			e.exportMu.Unlock()
			state.mu.Lock()
			state.running = false
			state.mu.Unlock()
		}()
		e.runExport(ctx, acc, state, settings)
	}()

	return nil
}

func (e *Engine) SkipExportFile(accountID string, randomID uint64) {
	e.exportMu.RLock()
	state, ok := e.exports[accountID]
	e.exportMu.RUnlock()
	if !ok {
		return
	}
	select {
	case state.skipFileCh <- randomID:
	default:
	}
}

func (e *Engine) CancelExport(accountID string) {
	e.exportMu.Lock()
	state, ok := e.exports[accountID]
	if ok {
		state.cancel()
		delete(e.exports, accountID)
	}
	e.exportMu.Unlock()
}

func (e *Engine) SaveExportSettings(accountID string, data json.RawMessage) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account %q not found", accountID)
	}
	dir := filepath.Join(e.configDir, "accounts", acc.ID)
	os.MkdirAll(dir, 0o755)
	return os.WriteFile(filepath.Join(dir, "export_settings.json"), data, 0o644)
}

func (e *Engine) LoadExportSettings(accountID string) (json.RawMessage, error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return nil, fmt.Errorf("account %q not found", accountID)
	}
	path := filepath.Join(e.configDir, "accounts", acc.ID, "export_settings.json")
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return json.RawMessage("{}"), nil
		}
		return nil, err
	}
	return json.RawMessage(data), nil
}

// --- Export-ready suggestion (AyuGram Session::suggestStartExport / clearExportSuggestion) ---
//
// When a takeout init is delayed (TAKEOUT_INIT_DELAY) Telegram returns the time
// at which the export becomes available. AyuGram persists this in the export
// settings (settings.availableAt) and, on every startup, re-arms a timer
// (Session::suggestStartExport → base::call_delayed) that — once the time
// elapses and no export is running — re-prompts the user with the "Data export
// ready" box (Export::View::SuggestStart). We mirror that: SuggestStartExport
// persists availableAt and (re)arms a timer; when it fires we emit
// EventExportSuggest so Dart shows the box. ClearExportSuggestion (=
// ClearSuggestStart) cancels the timer and clears the persisted value.

// exportSuggestPath returns the per-account file persisting the export-ready
// availableAt timestamp. It is kept separate from export_settings.json so the
// periodic settings autosave (which writes the whole settings map) can't clobber it.
func (e *Engine) exportSuggestPath(accountID string) (string, bool) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return "", false
	}
	return filepath.Join(e.configDir, "accounts", acc.ID, "export_suggest.json"), true
}

func (e *Engine) writeExportSuggestAt(accountID string, availableAtMS int64) {
	path, ok := e.exportSuggestPath(accountID)
	if !ok {
		return
	}
	if availableAtMS <= 0 {
		os.Remove(path)
		return
	}
	os.MkdirAll(filepath.Dir(path), 0o755)
	b, err := json.Marshal(map[string]int64{"available_at_ms": availableAtMS})
	if err != nil {
		return
	}
	os.WriteFile(path, b, 0o644)
}

func (e *Engine) readExportSuggestAt(accountID string) int64 {
	path, ok := e.exportSuggestPath(accountID)
	if !ok {
		return 0
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return 0
	}
	var m map[string]int64
	if json.Unmarshal(data, &m) != nil {
		return 0
	}
	return m["available_at_ms"]
}

// SuggestStartExport persists availableAt and (re)arms the suggestion timer.
// Mirrors Session::suggestStartExport(TimeId availableAt).
func (e *Engine) SuggestStartExport(accountID string, availableAtMS int64) error {
	e.writeExportSuggestAt(accountID, availableAtMS)
	e.scheduleExportSuggest(accountID, availableAtMS)
	return nil
}

// ClearExportSuggestion cancels any pending suggestion timer and clears the
// persisted availableAt. Mirrors Export::View::ClearSuggestStart /
// Session::clearExportSuggestion.
func (e *Engine) ClearExportSuggestion(accountID string) error {
	e.cancelExportSuggest(accountID)
	e.writeExportSuggestAt(accountID, 0)
	return nil
}

// suggestExportIfNeeded re-arms the suggestion timer from persisted state when an
// account connects. Mirrors Domain::suggestExportIfNeeded().
func (e *Engine) suggestExportIfNeeded(accountID string) {
	if availableAt := e.readExportSuggestAt(accountID); availableAt > 0 {
		e.scheduleExportSuggest(accountID, availableAt)
	}
}

// scheduleExportSuggest is the timer body of Session::suggestStartExport(): while
// the available time is still in the future it re-arms after min(left+5s, 1h) and
// re-checks; once elapsed it emits the suggestion (or, if an export is already
// running, just clears it — matching the inProgress() → ClearSuggestStart branch).
func (e *Engine) scheduleExportSuggest(accountID string, availableAtMS int64) {
	e.cancelExportSuggest(accountID)

	e.mu.RLock()
	down := e.shuttingDown
	e.mu.RUnlock()
	if down || availableAtMS <= 0 {
		return
	}

	leftMS := availableAtMS - time.Now().UnixMilli()
	if leftMS > 0 {
		waitMS := leftMS + 5000
		if waitMS > 3600*1000 {
			waitMS = 3600 * 1000
		}
		timer := time.AfterFunc(time.Duration(waitMS)*time.Millisecond, func() {
			e.scheduleExportSuggest(accountID, availableAtMS)
		})
		e.exportSuggestMu.Lock()
		if e.exportSuggestTimers == nil {
			e.exportSuggestTimers = make(map[string]*time.Timer)
		}
		e.exportSuggestTimers[accountID] = timer
		e.exportSuggestMu.Unlock()
		return
	}

	if e.isExportRunning(accountID) {
		e.writeExportSuggestAt(accountID, 0)
		return
	}
	e.emitEvent(EventExportSuggest, accountID, ExportSuggestEvent{AvailableAtMS: availableAtMS})
}

func (e *Engine) cancelExportSuggest(accountID string) {
	e.exportSuggestMu.Lock()
	if t, ok := e.exportSuggestTimers[accountID]; ok {
		t.Stop()
		delete(e.exportSuggestTimers, accountID)
	}
	e.exportSuggestMu.Unlock()
}

// cancelAllExportSuggests stops every pending suggestion timer (used on shutdown).
func (e *Engine) cancelAllExportSuggests() {
	e.exportSuggestMu.Lock()
	for id, t := range e.exportSuggestTimers {
		t.Stop()
		delete(e.exportSuggestTimers, id)
	}
	e.exportSuggestMu.Unlock()
}

// isExportRunning reports whether a takeout export is currently in progress for
// the account (AyuGram Core::App().exportManager().inProgress()).
func (e *Engine) isExportRunning(accountID string) bool {
	e.exportMu.RLock()
	state, ok := e.exports[accountID]
	e.exportMu.RUnlock()
	if !ok {
		return false
	}
	state.mu.Lock()
	running := state.running
	state.mu.Unlock()
	return running
}

func (e *Engine) runExport(ctx context.Context, acc *Account, state *exportState, settings ExportSettings) {
	accountID := acc.ID
	exportDir := settings.ExportLocation
	if exportDir == "" {
		home, _ := os.UserHomeDir()
		exportDir = filepath.Join(home, "Downloads", "TelegramExport")
	}
	timestamp := time.Now().Format("2006-01-02")
	exportDir = filepath.Join(exportDir, "DataExport_"+timestamp)
	if err := os.MkdirAll(exportDir, 0o755); err != nil {
		e.emitEvent(EventExportError, accountID, ExportErrorEvent{
			ErrorType:   "disk_io",
			Description: "Failed to create export directory",
			Path:        exportDir,
		})
		return
	}

	isPerChat := settings.ChatID != ""

	steps := e.buildExportSteps(ctx, acc, state, settings, exportDir, isPerChat)
	totalSteps := len(steps)

	tp, hasTakeout := acc.Core.(takeoutProvider)
	if hasTakeout {
		e.emitExportProgress(accountID, state, "Initializing", 0, totalSteps, 0.0, "Starting takeout session...")
		takeoutID, err := tp.InitTakeout(
			settings.Contacts,
			settings.PersonalChats || settings.BotChats,
			settings.PrivateGroups,
			settings.PrivateGroups,
			settings.PrivateChannels || settings.PublicChannels,
			settings.MediaPhotos || settings.MediaVideo || settings.MediaVoice || settings.MediaFile || settings.MediaGif || settings.MediaSticker || settings.MediaVideoMsg,
			int64(settings.SizeLimitMB)*1024*1024,
		)
		if err != nil {
			e.handleTakeoutError(accountID, err)
			return
		}
		_ = takeoutID
		defer func() {
			if hasTakeout {
				tp.FinishTakeout()
			}
		}()
	}

	for i, step := range steps {
		if ctx.Err() != nil {
			return
		}
		e.emitExportProgress(accountID, state, step.label, i, totalSteps, 0.0, "Starting...")
		if err := step.run(ctx, state); err != nil {
			if ctx.Err() != nil {
				return
			}
			e.emitEvent(EventExportError, accountID, ExportErrorEvent{
				ErrorType:   "api_error",
				Description: err.Error(),
			})
			return
		}
		e.emitExportProgress(accountID, state, step.label, i, totalSteps, 1.0, "Done")
	}

	state.mu.Lock()
	totalFiles := state.totalFiles
	totalSize := state.totalSize
	state.mu.Unlock()

	e.emitEvent(EventExportComplete, accountID, ExportCompleteEvent{
		ExportPath: exportDir,
		TotalFiles: totalFiles,
		TotalSize:  totalSize,
	})
}

func (e *Engine) buildExportSteps(ctx context.Context, acc *Account, state *exportState, settings ExportSettings, exportDir string, isPerChat bool) []exportStep {
	var steps []exportStep

	if isPerChat {
		steps = append(steps, exportStep{
			label: "Chat History",
			run: func(ctx context.Context, st *exportState) error {
				return e.exportChatHistory(ctx, acc, st, settings, exportDir, settings.ChatID)
			},
		})
		return steps
	}

	steps = append(steps, exportStep{
		label: "Dialogs list",
		run: func(ctx context.Context, st *exportState) error {
			return e.exportDialogsList(ctx, acc, st, exportDir)
		},
	})

	if settings.PersonalInfo {
		steps = append(steps, exportStep{
			label: "Personal info",
			run: func(ctx context.Context, st *exportState) error {
				return e.exportPersonalInfo(ctx, acc, st, exportDir)
			},
		})
	}

	if settings.Contacts {
		steps = append(steps, exportStep{
			label: "Contacts",
			run: func(ctx context.Context, st *exportState) error {
				return e.exportContacts(ctx, acc, st, exportDir)
			},
		})
	}

	if settings.Sessions {
		steps = append(steps, exportStep{
			label: "Sessions",
			run: func(ctx context.Context, st *exportState) error {
				return e.exportSessions(ctx, acc, st, exportDir)
			},
		})
	}

	anyChatSelected := settings.PersonalChats || settings.BotChats ||
		settings.PrivateGroups || settings.PrivateChannels ||
		settings.PublicGroups || settings.PublicChannels

	if anyChatSelected {
		steps = append(steps, exportStep{
			label: "Chats",
			run: func(ctx context.Context, st *exportState) error {
				return e.exportChats(ctx, acc, st, settings, exportDir)
			},
		})
	}

	return steps
}

func (e *Engine) exportDialogsList(ctx context.Context, acc *Account, state *exportState, exportDir string) error {
	dialogs, err := acc.Core.GetDialogs(cores.PaginationOpts{Limit: 500})
	if err != nil {
		return fmt.Errorf("get dialogs: %w", err)
	}
	data, err := json.MarshalIndent(dialogs, "", "  ")
	if err != nil {
		return err
	}
	path := filepath.Join(exportDir, "dialogs_list.json")
	if err := os.WriteFile(path, data, 0o644); err != nil {
		return e.diskError(acc.ID, path, err)
	}
	state.mu.Lock()
	state.totalFiles++
	state.totalSize += int64(len(data))
	state.mu.Unlock()
	return nil
}

func (e *Engine) exportPersonalInfo(ctx context.Context, acc *Account, state *exportState, exportDir string) error {
	profile, err := acc.Core.GetProfile("self")
	if err != nil {
		return fmt.Errorf("get profile: %w", err)
	}
	data, err := json.MarshalIndent(profile, "", "  ")
	if err != nil {
		return err
	}
	dir := filepath.Join(exportDir, "personal_information")
	os.MkdirAll(dir, 0o755)
	path := filepath.Join(dir, "personal_information.json")
	if err := os.WriteFile(path, data, 0o644); err != nil {
		return e.diskError(acc.ID, path, err)
	}
	state.mu.Lock()
	state.totalFiles++
	state.totalSize += int64(len(data))
	state.mu.Unlock()
	return nil
}

func (e *Engine) exportContacts(ctx context.Context, acc *Account, state *exportState, exportDir string) error {
	contacts, err := acc.Core.GetContacts()
	if err != nil {
		return fmt.Errorf("get contacts: %w", err)
	}
	data, err := json.MarshalIndent(contacts, "", "  ")
	if err != nil {
		return err
	}
	dir := filepath.Join(exportDir, "contacts")
	os.MkdirAll(dir, 0o755)
	path := filepath.Join(dir, "contacts.json")
	if err := os.WriteFile(path, data, 0o644); err != nil {
		return e.diskError(acc.ID, path, err)
	}
	state.mu.Lock()
	state.totalFiles++
	state.totalSize += int64(len(data))
	state.mu.Unlock()
	return nil
}

func (e *Engine) exportSessions(ctx context.Context, acc *Account, state *exportState, exportDir string) error {
	sessions, err := acc.Core.GetSessions()
	if err != nil {
		return fmt.Errorf("get sessions: %w", err)
	}
	data, err := json.MarshalIndent(sessions, "", "  ")
	if err != nil {
		return err
	}
	dir := filepath.Join(exportDir, "other_data")
	os.MkdirAll(dir, 0o755)
	path := filepath.Join(dir, "sessions.json")
	if err := os.WriteFile(path, data, 0o644); err != nil {
		return e.diskError(acc.ID, path, err)
	}
	state.mu.Lock()
	state.totalFiles++
	state.totalSize += int64(len(data))
	state.mu.Unlock()
	return nil
}

func (e *Engine) exportChats(ctx context.Context, acc *Account, state *exportState, settings ExportSettings, exportDir string) error {
	dialogs, err := acc.Core.GetDialogs(cores.PaginationOpts{Limit: 500})
	if err != nil {
		return fmt.Errorf("get dialogs: %w", err)
	}

	var selected []cores.Dialog
	for _, d := range dialogs {
		if e.shouldExportDialog(d, settings) {
			selected = append(selected, d)
		}
	}

	for i, d := range selected {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		progress := float64(i) / float64(len(selected))
		e.emitExportProgress(acc.ID, state, "Chats", -1, -1, progress, fmt.Sprintf("%s (%d/%d)", d.Title, i+1, len(selected)))

		if err := e.exportChatHistory(ctx, acc, state, settings, exportDir, d.ID); err != nil {
			if ctx.Err() != nil {
				return ctx.Err()
			}
			continue
		}
		time.Sleep(500 * time.Millisecond)
	}
	return nil
}

func (e *Engine) shouldExportDialog(d cores.Dialog, s ExportSettings) bool {
	switch d.Type {
	case cores.ChatTypeDM:
		return s.PersonalChats
	case cores.ChatTypeGroup:
		return s.PrivateGroups
	case cores.ChatTypeChannel:
		return s.PrivateChannels || s.PublicChannels
	default:
		return s.PersonalChats
	}
}

func (e *Engine) exportChatHistory(ctx context.Context, acc *Account, state *exportState, settings ExportSettings, exportDir, chatID string) error {
	safeTitle := sanitizeFileName(chatID)
	chatDir := filepath.Join(exportDir, "chats", safeTitle)
	os.MkdirAll(chatDir, 0o755)

	var allMessages []cores.Message
	offset := ""
	for {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		batch, err := acc.Core.GetMessages(chatID, cores.PaginationOpts{Limit: 100, Offset: offset})
		if err != nil {
			return fmt.Errorf("get messages for %s: %w", chatID, err)
		}
		if len(batch) == 0 {
			break
		}
		allMessages = append(allMessages, batch...)

		state.mu.Lock()
		state.totalFiles += len(batch)
		state.mu.Unlock()

		e.emitExportProgress(acc.ID, state, chatID, -1, -1, -1, fmt.Sprintf("%d messages", len(allMessages)))

		offset = batch[len(batch)-1].ID
		time.Sleep(300 * time.Millisecond)

		if len(batch) < 100 {
			break
		}
	}

	data, err := json.MarshalIndent(map[string]interface{}{
		"chat_id":  chatID,
		"messages": allMessages,
		"count":    len(allMessages),
	}, "", "  ")
	if err != nil {
		return err
	}

	path := filepath.Join(chatDir, "messages.json")
	if err := os.WriteFile(path, data, 0o644); err != nil {
		return e.diskError(acc.ID, path, err)
	}

	state.mu.Lock()
	state.totalFiles++
	state.totalSize += int64(len(data))
	state.mu.Unlock()

	return nil
}

func (e *Engine) emitExportProgress(accountID string, state *exportState, step string, stepIndex, totalSteps int, progress float64, info string) {
	state.mu.Lock()
	rid := state.fileRandomID
	tf := state.totalFiles
	ts := state.totalSize
	state.mu.Unlock()

	e.emitEvent(EventExportProgress, accountID, ExportProgressEvent{
		Step:         step,
		StepIndex:    stepIndex,
		TotalSteps:   totalSteps,
		Progress:     progress,
		Info:         info,
		TotalFiles:   tf,
		TotalSize:    ts,
		FileRandomID: rid,
	})
}

func (e *Engine) handleTakeoutError(accountID string, err error) {
	errStr := err.Error()
	if strings.Contains(errStr, "TAKEOUT_INVALID") {
		e.emitEvent(EventExportError, accountID, ExportErrorEvent{
			ErrorType:   "takeout_invalid",
			Description: "Takeout session expired or invalid",
		})
		return
	}
	if strings.Contains(errStr, "TAKEOUT_INIT_DELAY") {
		hours := 24
		e.emitEvent(EventExportError, accountID, ExportErrorEvent{
			ErrorType:      "takeout_delay",
			Description:    "Please wait before starting another export",
			HoursRemaining: hours,
			AvailableAtMS:  time.Now().Add(time.Duration(hours) * time.Hour).UnixMilli(),
		})
		return
	}
	e.emitEvent(EventExportError, accountID, ExportErrorEvent{
		ErrorType:   "api_error",
		Description: errStr,
	})
}

func (e *Engine) diskError(accountID, path string, err error) error {
	e.emitEvent(EventExportError, accountID, ExportErrorEvent{
		ErrorType:   "disk_io",
		Description: err.Error(),
		Path:        path,
	})
	return err
}

func sanitizeFileName(name string) string {
	replacer := strings.NewReplacer(
		"/", "_", "\\", "_", ":", "_", "*", "_",
		"?", "_", "\"", "_", "<", "_", ">", "_", "|", "_",
	)
	s := replacer.Replace(name)
	if len(s) > 100 {
		s = s[:100]
	}
	if s == "" {
		s = fmt.Sprintf("chat_%d", rand.Int63())
	}
	return s
}

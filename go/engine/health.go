package engine

import (
	"context"
	"fmt"
	"log"
	"math/rand/v2"
	"time"

	"uniclient/cores"
)

// reconnectState tracks backoff for a single account.
type reconnectState struct {
	attempts  int
	lastOK    time.Time // last time connection was stable for >60s
}

var reconnectDelays = []time.Duration{
	0,
	2 * time.Second,
	5 * time.Second,
	15 * time.Second,
	30 * time.Second,
	60 * time.Second,
}

// nextDelay returns the backoff duration with ±25% jitter.
func (r *reconnectState) nextDelay() time.Duration {
	idx := r.attempts
	if idx >= len(reconnectDelays) {
		idx = len(reconnectDelays) - 1
	}
	base := reconnectDelays[idx]
	if base == 0 {
		return 0
	}
	// ±25% jitter
	jitter := time.Duration(rand.Int64N(int64(base)/2)) - base/4
	return base + jitter
}

// ConnectAccount creates a core, authenticates using saved credentials,
// registers the update handler, and starts connection monitoring.
func (e *Engine) ConnectAccount(accountID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account %q not found", accountID)
	}

	factory := getCoreFactory()
	if factory == nil {
		return fmt.Errorf("no core factory registered")
	}

	// Create core.
	core, err := factory(acc.Platform, accountID)
	if err != nil {
		return fmt.Errorf("create core %s: %w", acc.Platform, err)
	}

	// Load saved credentials.
	creds, err := e.LoadCredentials(accountID)
	if err != nil {
		core.Close()
		return fmt.Errorf("load credentials: %w", err)
	}

	e.setConnState(accountID, ConnConnecting)
	e.emitConnState(accountID, ConnConnecting, "")

	// Create cancellable context for this account's goroutines.
	ctx, cancel := context.WithCancel(context.Background())

	e.accountsMu.Lock()
	acc.Core = core
	acc.cancelFunc = cancel
	acc.lastEvent = time.Now()
	e.accountsMu.Unlock()

	// Register update handler before authenticating.
	core.OnUpdate(func(u cores.Update) {
		e.handleUpdate(accountID, u)
	})

	// Authenticate.
	if err := core.Authenticate(*creds); err != nil {
		e.setConnState(accountID, ConnAuthRequired)
		e.emitConnState(accountID, ConnAuthRequired, err.Error())
		return err
	}

	e.setConnState(accountID, ConnConnected)
	e.emitConnState(accountID, ConnConnected, "")

	// Update display name from profile.
	e.wg.Add(1)
	go func() {
		defer e.wg.Done()
		if profile, err := core.GetProfile(""); err == nil && profile != nil {
			name := profile.DisplayName
			if name == "" {
				name = profile.Username
			}
			if name != "" {
				e.UpdateAccountDisplay(accountID, name, "")
			}
		}
	}()

	// Start background sync.
	e.wg.Add(1)
	go func() {
		defer e.wg.Done()
		e.syncAccount(ctx, accountID)
	}()

	// Start heartbeat monitor.
	e.wg.Add(1)
	go func() {
		defer e.wg.Done()
		e.monitorConnection(ctx, accountID)
	}()

	return nil
}

// ConnectAllAccounts connects all accounts with staggered delays.
func (e *Engine) ConnectAllAccounts() {
	accounts := e.ListAccounts()
	for i, acc := range accounts {
		acc := acc
		delay := time.Duration(i) * 100 * time.Millisecond
		e.wg.Add(1)
		go func() {
			defer e.wg.Done()
			time.Sleep(delay)
			if err := e.ConnectAccount(acc.ID); err != nil {
				// Non-fatal: other accounts can still connect.
			}
		}()
	}
}

// syncAccount fetches fresh data from the network after connecting.
func (e *Engine) syncAccount(ctx context.Context, accountID string) {
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		log.Printf("[engine] syncAccount(%s): account not found or no core", accountID)
		return
	}

	// Sync chat list.
	log.Printf("[engine] syncAccount(%s): fetching dialogs...", accountID)
	dialogs, err := acc.Core.GetDialogs(cores.PaginationOpts{Limit: 200})
	if err != nil {
		log.Printf("[engine] syncAccount(%s): GetDialogs failed: %v", accountID, err)
		return
	}
	log.Printf("[engine] syncAccount(%s): got %d dialogs, syncing to cache...", accountID, len(dialogs))
	e.SyncChats(accountID, dialogs)
	log.Printf("[engine] syncAccount(%s): sync complete, emitted chat snapshot", accountID)

	// Cache contacts as users.
	contacts, err := acc.Core.GetContacts()
	if err == nil && len(contacts) > 0 {
		e.BulkUpsertUsers(accountID, contacts)
		log.Printf("[engine] syncAccount(%s): cached %d contacts", accountID, len(contacts))
	}
}

// monitorConnection watches for zombie connections and triggers reconnect.
func (e *Engine) monitorConnection(ctx context.Context, accountID string) {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			acc, ok := e.getAccount(accountID)
			if !ok || acc.ConnState != ConnConnected {
				continue
			}

			// Check if we've received any event in the last 60s.
			if time.Since(acc.lastEvent) > 60*time.Second {
				// Probe with a lightweight call.
				if acc.Core != nil {
					_, err := acc.Core.GetDialogs(cores.PaginationOpts{Limit: 1})
					if err != nil {
						e.handleDisconnect(accountID, err)
					} else {
						// Probe succeeded — update lastEvent.
						e.accountsMu.Lock()
						acc.lastEvent = time.Now()
						e.accountsMu.Unlock()
					}
				}
			}
		}
	}
}

// handleDisconnect processes a disconnection event and schedules reconnect.
func (e *Engine) handleDisconnect(accountID string, err error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return
	}

	// Check for flaky connection (unstable state).
	e.accountsMu.Lock()
	acc.reconnect.attempts++
	attempts := acc.reconnect.attempts

	// If 3+ reconnects in 60s → mark unstable.
	if attempts >= 3 && time.Since(acc.reconnect.lastOK) < 60*time.Second {
		acc.ConnState = ConnUnstable
		e.accountsMu.Unlock()
		e.emitConnState(accountID, ConnUnstable, "frequent disconnects")
	} else {
		acc.ConnState = ConnDisconnected
		e.accountsMu.Unlock()
		e.emitConnState(accountID, ConnDisconnected, err.Error())
	}

	// Schedule reconnect with backoff.
	delay := acc.reconnect.nextDelay()
	e.wg.Add(1)
	go func() {
		defer e.wg.Done()
		time.Sleep(delay)
		e.reconnectAccount(accountID)
	}()
}

// reconnectAccount attempts to reconnect a disconnected account.
func (e *Engine) reconnectAccount(accountID string) {
	e.mu.RLock()
	if e.shuttingDown {
		e.mu.RUnlock()
		return
	}
	e.mu.RUnlock()

	acc, ok := e.getAccount(accountID)
	if !ok {
		return
	}

	// Close old core if exists.
	if acc.Core != nil {
		acc.Core.Close()
	}

	err := e.ConnectAccount(accountID)
	if err != nil {
		return
	}

	// Reset reconnect state on success.
	e.accountsMu.Lock()
	acc.reconnect.attempts = 0
	acc.reconnect.lastOK = time.Now()
	e.accountsMu.Unlock()
}

// DisconnectAccount manually disconnects an account.
func (e *Engine) DisconnectAccount(accountID string) error {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account %q not found", accountID)
	}

	if acc.cancelFunc != nil {
		acc.cancelFunc()
	}
	if acc.Core != nil {
		acc.Core.Close()
	}

	e.setConnState(accountID, ConnDisconnected)
	e.emitConnState(accountID, ConnDisconnected, "")

	e.accountsMu.Lock()
	acc.Core = nil
	acc.cancelFunc = nil
	e.accountsMu.Unlock()

	return nil
}

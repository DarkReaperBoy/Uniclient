package engine

import (
	"context"
	"fmt"
	"log"
	"math/rand/v2"
	"time"

	"uniclient/cores"
)

type reconnectState struct {
	attempts int
	lastOK   time.Time
}

var reconnectDelays = []time.Duration{
	0,
	2 * time.Second,
	5 * time.Second,
	15 * time.Second,
	30 * time.Second,
	60 * time.Second,
}

func (r *reconnectState) nextDelay() time.Duration {
	idx := r.attempts
	if idx >= len(reconnectDelays) {
		idx = len(reconnectDelays) - 1
	}
	base := reconnectDelays[idx]
	if base == 0 {
		return 0
	}
	jitter := time.Duration(rand.Int64N(int64(base)/2)) - base/4
	return base + jitter
}

func (e *Engine) ConnectAccount(accountID string) error {
	log.Printf("[engine] ConnectAccount(%s): starting", accountID)
	acc, ok := e.getAccount(accountID)
	if !ok {
		return fmt.Errorf("account %q not found", accountID)
	}

	factory := getCoreFactory()
	if factory == nil {
		return fmt.Errorf("no core factory registered")
	}

	core, err := factory(acc.Platform, accountID)
	if err != nil {
		log.Printf("[engine] ConnectAccount(%s): create core failed: %v", accountID, err)
		return fmt.Errorf("create core %s: %w", acc.Platform, err)
	}
	e.applyProxyToCore(core)

	creds, err := e.LoadCredentials(accountID)
	if err != nil {
		log.Printf("[engine] ConnectAccount(%s): load credentials failed: %v", accountID, err)
		core.Close()
		return fmt.Errorf("load credentials: %w", err)
	}
	log.Printf("[engine] ConnectAccount(%s): credentials loaded, mode=%s", accountID, creds.Mode)

	e.setConnState(accountID, ConnConnecting)
	e.emitConnState(accountID, ConnConnecting, "")

	ctx, cancel := context.WithCancel(context.Background())

	e.accountsMu.Lock()
	acc.Core = core
	acc.cancelFunc = cancel
	acc.lastEvent = time.Now()
	e.accountsMu.Unlock()

	core.OnUpdate(func(u cores.Update) {
		e.HandleUpdate(accountID, u)
	})

	log.Printf("[engine] ConnectAccount(%s): authenticating...", accountID)
	if err := core.Authenticate(*creds); err != nil {
		log.Printf("[engine] ConnectAccount(%s): auth failed: %v", accountID, err)
		e.setConnState(accountID, ConnDisconnected)
		e.emitConnState(accountID, ConnDisconnected, err.Error())
		return err
	}
	log.Printf("[engine] ConnectAccount(%s): auth succeeded", accountID)

	e.setConnState(accountID, ConnConnected)
	e.emitConnState(accountID, ConnConnected, "")

	e.suggestExportIfNeeded(accountID)

	type peerHashPreloader interface {
		PreloadPeerHashes(channelHashes map[int64]int64, userHashes map[int64]int64)
	}
	if php, ok := core.(peerHashPreloader); ok {
		ch, uh := e.loadPeerHashes(accountID)
		if len(ch) > 0 || len(uh) > 0 {
			php.PreloadPeerHashes(ch, uh)
		}
	}

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
			e.accountsMu.Lock()
			if a, ok := e.accounts[accountID]; ok {
				a.IsVerified = profile.IsVerified
				a.IsPremium = profile.IsPremium
				a.Phone = profile.Phone
				a.Username = profile.Username
			}
			e.accountsMu.Unlock()
			e.emitAccountList()
		}
	}()

	e.wg.Add(1)
	go func() {
		defer e.wg.Done()
		e.syncAccount(ctx, accountID)
	}()

	e.wg.Add(1)
	go func() {
		defer e.wg.Done()
		e.monitorConnection(ctx, accountID)
	}()

	return nil
}

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
			}
		}()
	}
}

func SyncAccountContext(ctx context.Context) context.Context {
	if ctx == nil {
		return context.Background()
	}
	return ctx
}

func (e *Engine) syncAccount(ctx context.Context, accountID string) {
	ctx = SyncAccountContext(ctx)
	acc, ok := e.getAccount(accountID)
	if !ok || acc.Core == nil {
		log.Printf("[engine] syncAccount(%s): account not found or no core", accountID)
		return
	}

	log.Printf("[engine] syncAccount(%s): fetching dialogs...", accountID)
	dialogs, err := acc.Core.GetDialogs(cores.PaginationOpts{Limit: 100})
	if err != nil {
		log.Printf("[engine] syncAccount(%s): GetDialogs failed: %v", accountID, err)
		return
	}
	log.Printf("[engine] syncAccount(%s): got %d dialogs, syncing to cache...", accountID, len(dialogs))
	e.SyncChats(accountID, dialogs)
	log.Printf("[engine] syncAccount(%s): sync complete, emitted chat snapshot", accountID)

	if len(dialogs) >= 100 {
		go func() {
			more, err := acc.Core.GetDialogs(cores.PaginationOpts{Limit: 500})
			if err != nil || len(more) <= len(dialogs) {
				return
			}
			log.Printf("[engine] syncAccount(%s): background pagination got %d total dialogs", accountID, len(more))
			e.SyncChats(accountID, more)
		}()
	}

	contacts, err := acc.Core.GetContacts()
	if err == nil && len(contacts) > 0 {
		e.BulkUpsertUsers(accountID, contacts)
		log.Printf("[engine] syncAccount(%s): cached %d contacts", accountID, len(contacts))
	}
}

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

			if time.Since(acc.lastEvent) > 60*time.Second {
				if acc.Core != nil {
					_, err := acc.Core.GetDialogs(cores.PaginationOpts{Limit: 1})
					if err != nil {
						e.handleDisconnect(accountID, err)
					} else {
						e.accountsMu.Lock()
						acc.lastEvent = time.Now()
						e.accountsMu.Unlock()
					}
				}
			}
		}
	}
}

func (e *Engine) handleDisconnect(accountID string, err error) {
	acc, ok := e.getAccount(accountID)
	if !ok {
		return
	}

	e.accountsMu.Lock()
	acc.reconnect.attempts++
	attempts := acc.reconnect.attempts

	if attempts >= 3 && time.Since(acc.reconnect.lastOK) < 60*time.Second {
		acc.ConnState = ConnUnstable
		e.accountsMu.Unlock()
		e.emitConnState(accountID, ConnUnstable, "frequent disconnects")
	} else {
		acc.ConnState = ConnDisconnected
		e.accountsMu.Unlock()
		e.emitConnState(accountID, ConnDisconnected, err.Error())
	}

	delay := acc.reconnect.nextDelay()
	e.wg.Add(1)
	go func() {
		defer e.wg.Done()
		time.Sleep(delay)
		e.reconnectAccount(accountID)
	}()
}

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

	if acc.Core != nil {
		acc.Core.Close()
	}

	err := e.ConnectAccount(accountID)
	if err != nil {
		return
	}

	e.accountsMu.Lock()
	acc.reconnect.attempts = 0
	acc.reconnect.lastOK = time.Now()
	e.accountsMu.Unlock()
}

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

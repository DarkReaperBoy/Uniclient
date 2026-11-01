package engine

import (
	"database/sql"
	"sync"
	"time"

	"uniclient/cores"
	"uniclient/utils"
)

func (x *Engine) ForTestDb() *sql.DB {
	return x.db
}

func (x *AuthFlow) ForTestCollected() map[string]string {
	return x.collected
}

func (x *Engine) ForTestMedia() *MediaManager {
	return x.media
}

func (x *oggPage) ForTestGranule() int64 {
	return x.granule
}

func (x *httpImageCache) ForTestMu() *sync.Mutex {
	return &x.mu
}

func (x *MediaManager) ForTestMu() *sync.Mutex {
	return &x.mu
}

func (x *Engine) ForTestMu() *sync.RWMutex {
	return &x.mu
}

func (x *giftCache) ForTestMu() *sync.Mutex {
	return &x.mu
}

func (x *exportState) ForTestMu() *sync.Mutex {
	return &x.mu
}

func (x *suggestionDismiss) ForTestMu() *sync.Mutex {
	return &x.mu
}

func (x *MediaStream) ForTestMu() *sync.Mutex {
	return &x.mu
}

func (x *avatarState) ForTestMu() *sync.Mutex {
	return &x.mu
}

func (x *Engine) ForTestAccounts() map[string]*Account {
	return x.accounts
}

func (x *Engine) ForTestSponsoredMu() *sync.Mutex {
	return &x.sponsoredMu
}

func (x *Engine) ForTestSponsoredCache() map[string]*sponsoredCacheEntry {
	return x.sponsoredCache
}

func (x *httpImgFlight) ForTestDone() chan struct{} {
	return x.done
}

func (x *MediaStream) ForTestDone() bool {
	return x.done
}

func (x *Engine) ForTestConfig() *utils.AppConfig {
	return x.config
}

func (x *MediaManager) ForTestQueue() []*DownloadJob {
	return x.queue
}

func (x *Engine) ForTestSetConfig(v *utils.AppConfig) {
	x.config = v
}

func (x *Engine) ForTestSetMedia(v *MediaManager) {
	x.media = v
}

func (x *Engine) ForTestSetDownloadDir(v string) {
	x.downloadDir = v
}

func (x *Engine) ForTestSetAccounts(v map[string]*Account) {
	x.accounts = v
}

func (x *giftCache) ForTestSetByAcct(v map[string]GiftCacheEntry) {
	x.byAcct = v
}

func (x *Engine) ForTestSetVault(v *utils.Vault) {
	x.vault = v
}

func (x *Engine) ForTestSetMediaDir(v string) {
	x.mediaDir = v
}

func (x *httpImgFlight) ForTestSetDone(v chan struct{}) {
	x.done = v
}

func (x *MediaStream) ForTestSetDone(v bool) {
	x.done = v
}

func (x *sponsoredCacheEntry) ForTestSetFetchedAt(v time.Time) {
	x.fetchedAt = v
}

func (x *VoiceVAD) ForTestGate(frame []byte) bool {
	return x.gate(frame)
}

func (x *httpImageCache) ForTestStore(key string, data []byte) {
	x.store(key, data)
}

func (x *VoiceVAD) ForTestNeedTerminator() bool {
	return x.needTerminator()
}

func (x *httpImageCache) ForTestGet(key string) []byte {
	return x.get(key)
}

func (x *Engine) ForTestOpenMediaStream(accountID, chatID, msgID string, seq int, src partSource) (*MediaStream, string, int64, error) {
	return x.openMediaStream(accountID, chatID, msgID, seq, src)
}

func (x *httpImageCache) ForTestLen() int {
	return x.len()
}

func (x *Engine) ForTestGetAccount(accountID string) (*Account, bool) {
	return x.getAccount(accountID)
}

func (x *MediaStream) ForTestComplete() bool {
	return x.complete()
}

func (x *MediaManager) ForTestExecuteDownload(job *DownloadJob) {
	x.executeDownload(job)
}

func (x *Engine) ForTestSetAntiRecall(d, h, b bool) {
	x.saveDeletedMessages, x.saveMessagesHistory, x.saveForBots = d, h, b
}

func ForTestNewAuthFlow(core cores.Core) *AuthFlow {
	return &AuthFlow{collected: map[string]string{}, core: core}
}

func ForTestNewEngine(db *sql.DB, vault *utils.Vault, config *utils.AppConfig) *Engine {
	return &Engine{db: db, vault: vault, config: config}
}

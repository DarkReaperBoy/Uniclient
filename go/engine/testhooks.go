package engine

import (
	"sync"
)

func (x *Engine) ForTestMedia() *MediaManager {
	return x.media
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

func (x *MediaManager) ForTestQueue() []*DownloadJob {
	return x.queue
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

func (x *httpImageCache) ForTestLen() int {
	return x.len()
}

func (x *MediaManager) ForTestExecuteDownload(job *DownloadJob) {
	x.executeDownload(job)
}

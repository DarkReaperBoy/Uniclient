package engine

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

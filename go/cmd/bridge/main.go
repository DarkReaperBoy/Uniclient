// Entry point for the c-shared library build (native platforms).
//
// About `import "C"` below — it is the irreducible minimum the Go toolchain
// requires, NOT a CGo dependency on any C source/library of ours:
//
//   - `//export` directives only emit symbols when cgo is enabled. Verified on
//     Go 1.26.1: without `import "C"` the `//export` comments are silently
//     ignored and no symbols are produced.
//   - `-buildmode=c-shared` refuses to link with CGO_ENABLED=0
//     ("-buildmode=c-shared requires external (cgo) linking, but cgo is not
//     enabled"). A loadable shared library callable from dart:ffi cannot be
//     produced any other way on linux/windows/macos/android.
//
// What this file does NOT contain: no C preamble, no #include, no C types
// (C.int32_t, C.malloc, C.free, C.CBytes, …), and no C function calls. Every
// exported signature uses pure Go types (*byte, int32) and all memory handed to
// Dart is Go-allocated and pinned via runtime.Pinner.
//
// Async events used to be delivered by invoking a C function-pointer trampoline
// back into Dart — the last remaining piece of hand-written C. That is gone.
// Events are now delivered by a pull model: Go buffers serialized BridgeEvent
// bytes in a channel and the Dart side drains them via the blocking
// BridgeNextEvent export running on a dedicated isolate. Go never calls a C
// function pointer.
package main

import "C"

import (
	"runtime"
	"sync"
	"unsafe"

	"uniclient/bridge"
)

func main() {}

// ---- Go-managed memory for buffers handed across the FFI boundary ----
//
// Dart receives a *byte + length, copies the bytes, then calls BridgeFree to
// release them. We keep the backing slice alive and pinned (so the GC neither
// frees nor moves it) until BridgeFree is called.

type pinnedEntry struct {
	data   []byte
	pinner *runtime.Pinner
}

var (
	pinnedMu   sync.Mutex
	pinnedRefs = make(map[uintptr]pinnedEntry)
)

func pinBytes(data []byte) *byte {
	buf := make([]byte, len(data))
	copy(buf, data)
	ptr := &buf[0]

	p := new(runtime.Pinner)
	p.Pin(ptr)

	pinnedMu.Lock()
	pinnedRefs[uintptr(unsafe.Pointer(ptr))] = pinnedEntry{data: buf, pinner: p}
	pinnedMu.Unlock()
	return ptr
}

func unpinBytes(ptr *byte) {
	pinnedMu.Lock()
	entry, ok := pinnedRefs[uintptr(unsafe.Pointer(ptr))]
	if ok {
		entry.pinner.Unpin()
		delete(pinnedRefs, uintptr(unsafe.Pointer(ptr)))
	}
	pinnedMu.Unlock()
}

// ---- Synchronous request/response ----

// BridgeCallWithLen dispatches a serialized BridgeRequest and returns a
// Go-pinned buffer holding the serialized BridgeResponse (free with BridgeFree).
//
//export BridgeCallWithLen
func BridgeCallWithLen(data *byte, dataLen int32, outLen *int32) *byte {
	goData := make([]byte, int(dataLen))
	copy(goData, unsafe.Slice(data, int(dataLen)))

	result := bridge.Call(goData)
	*outLen = int32(len(result))
	if len(result) == 0 {
		return nil
	}
	return pinBytes(result)
}

// BridgeFree releases a buffer previously returned by BridgeCallWithLen or
// BridgeNextEvent.
//
//export BridgeFree
func BridgeFree(ptr *byte) {
	if ptr != nil {
		unpinBytes(ptr)
	}
}

// ---- Async event delivery (pull model — no C callback) ----

var (
	// eventQueue buffers serialized BridgeEvent bytes produced by the engine
	// until the Dart event isolate drains them. Buffered so a burst at startup
	// (before Dart begins pulling) does not block the producer.
	eventQueue = make(chan []byte, 256)

	stopOnce sync.Once
	stopped  = make(chan struct{})
)

func init() {
	// Wire the bridge's event source into the pull queue. PushEvent (driven by
	// the engine) calls this with freshly-marshaled bytes we take ownership of.
	bridge.SetEventCallback(func(data []byte) {
		select {
		case eventQueue <- data:
		case <-stopped:
		}
	})
}

// BridgeNextEvent blocks until the next async event is available, then returns
// a Go-pinned buffer holding the serialized BridgeEvent (free with BridgeFree).
// It returns nil with *outLen == 0 once BridgeStopEvents has been called, which
// is the signal for the Dart event isolate to terminate.
//
//export BridgeNextEvent
func BridgeNextEvent(outLen *int32) *byte {
	select {
	case data := <-eventQueue:
		*outLen = int32(len(data))
		if len(data) == 0 {
			return nil
		}
		return pinBytes(data)
	case <-stopped:
		*outLen = 0
		return nil
	}
}

// BridgeStopEvents permanently unblocks BridgeNextEvent so the Dart event
// isolate can exit cleanly during shutdown. Idempotent.
//
//export BridgeStopEvents
func BridgeStopEvents() {
	stopOnce.Do(func() { close(stopped) })
}

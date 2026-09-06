//go:build js && wasm

// Entry point for the WebAssembly (js/wasm) build.
//
// The native build (main.go) exposes the bridge to the host through cgo `//export`
// symbols in a c-shared library. That mechanism does not exist on js/wasm:
//   - cgo is unavailable for GOOS=js, so a file with `import "C"` (main.go) is
//     excluded from the wasm build entirely, and `//export` produces nothing.
//   - WebAssembly has no raw pointers reachable from JavaScript, so the
//     pointer/length FFI signatures (BridgeCallWithLen, *byte, *int32) cannot be
//     called from JS at all.
//
// Instead we register plain JS functions on the global object via syscall/js.
// The names and signatures match exactly what the web frontend
// imports, so no pointers ever cross the boundary — only JS Uint8Array values,
// marshaled with js.CopyBytesToGo / js.CopyBytesToJS:
//
//	globalThis.bridgeCall(req: Uint8Array) -> Uint8Array    // sync request/response
//	globalThis.bridgeSetEventCallback(cb: Function | null)  // cb(ev: Uint8Array)
//
// Unlike native (pull model: a dedicated isolate blocks on BridgeNextEvent),
// wasm runs single-threaded on the JS event loop and cannot block to pull, so
// events use a push model: the engine's event source invokes the registered JS
// callback directly. Calling js.Value.Invoke from an engine goroutine is safe
// because every goroutine is cooperatively scheduled onto the one JS thread.
package main

import (
	"syscall/js"

	"uniclient/bridge"
)

func main() {
	// Expose the bridge API to JavaScript. These stay callable for the lifetime
	// of the page; registering them as js.Func keeps the Go runtime alive so the
	// block below is not flagged as a deadlock.
	js.Global().Set("bridgeCall", js.FuncOf(bridgeCall))
	js.Global().Set("bridgeSetEventCallback", js.FuncOf(bridgeSetEventCallback))

	// Block forever: index.html resolves window.bridgeReady right after go.run()
	// starts (main() has already registered the functions by the time go.run
	// yields here), and the registered callbacks serve every later JS call.
	<-make(chan struct{})
}

// bridgeCall dispatches a serialized BridgeRequest and returns the serialized
// BridgeResponse. args[0] is a JS Uint8Array; the result is a fresh Uint8Array.
// A nil/empty response (e.g. an invalid request) returns an empty Uint8Array.
func bridgeCall(_ js.Value, args []js.Value) any {
	if len(args) < 1 || args[0].IsNull() || args[0].IsUndefined() {
		return js.Global().Get("Uint8Array").New(0)
	}
	src := args[0]
	req := make([]byte, src.Get("length").Int())
	js.CopyBytesToGo(req, src)

	resp := bridge.Call(req)

	out := js.Global().Get("Uint8Array").New(len(resp))
	if len(resp) > 0 {
		js.CopyBytesToJS(out, resp)
	}
	return out
}

// bridgeSetEventCallback wires the bridge's async event source to a JS callback.
// The callback is invoked with a Uint8Array of serialized BridgeEvent bytes for
// each event. Passing null/undefined (or no argument) clears the callback.
func bridgeSetEventCallback(_ js.Value, args []js.Value) any {
	if len(args) < 1 || args[0].IsNull() || args[0].IsUndefined() {
		bridge.SetEventCallback(nil)
		return js.Undefined()
	}
	cb := args[0]
	bridge.SetEventCallback(func(data []byte) {
		arr := js.Global().Get("Uint8Array").New(len(data))
		if len(data) > 0 {
			js.CopyBytesToJS(arr, data)
		}
		cb.Invoke(arr)
	})
	return js.Undefined()
}

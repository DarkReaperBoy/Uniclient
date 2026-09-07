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
// Instead we register plain JS functions on the global object via syscall/js:
//
//      globalThis.bridgeCall(req: Uint8Array) -> Promise<Uint8Array>
//      globalThis.bridgeSetEventCallback(cb: Function | null)  // cb(ev: Uint8Array)
//
// bridgeCall is ASYNCHRONOUS (returns a Promise). This is a hard requirement,
// not a style choice: js/wasm is single-threaded and a synchronous JS→Go call
// cannot yield to the event loop. The engine performs blocking filesystem
// work (vault open/save, config dirs, session migration) whose syscall/fs_js
// bridge suspends the goroutine and waits for a JS fs callback — which can
// only fire once the JS call stack unwinds. A synchronous bridgeCall that
// touches the filesystem therefore deadlocks ("all goroutines are asleep").
// Dispatching on a fresh goroutine and resolving the Promise when done lets
// the event loop run those fs callbacks in between.
//
// Events use a push model: the engine's event source invokes the registered
// JS callback directly from the goroutine that produced the event. Calling
// js.Value.Invoke from an engine goroutine is safe because every goroutine is
// cooperatively scheduled onto the one JS thread.
package main

import (
        "syscall/js"

        "uniclient/bridge"
)

func main() {
        // Expose the bridge API to JavaScript. These stay callable for the
        // lifetime of the page; registering them as js.Func keeps the Go
        // runtime alive so the block below is not flagged as a deadlock.
        js.Global().Set("bridgeCall", js.FuncOf(bridgeCall))
        js.Global().Set("bridgeSetEventCallback", js.FuncOf(bridgeSetEventCallback))

        // Block forever: the host resolves window.bridgeReady right after
        // go.run() starts (main() has already registered the functions by the
        // time go.run() yields here), and the registered callbacks serve every
        // later JS call.
        <-make(chan struct{})
}

// bridgeCall dispatches a serialized BridgeRequest and resolves with the
// serialized BridgeResponse. args[0] is a JS Uint8Array; the result is a
// fresh Uint8Array. An invalid/missing request resolves with an empty
// Uint8Array carrying the error response bytes (or an empty buffer only when
// no request bytes were supplied at all).
func bridgeCall(_ js.Value, args []js.Value) any {
        if len(args) < 1 || args[0].IsNull() || args[0].IsUndefined() {
                return js.Global().Get("Uint8Array").New(0)
        }
        src := args[0]
        req := make([]byte, src.Get("length").Int())
        js.CopyBytesToGo(req, src)

        // Resolve the promise from a dedicated goroutine so the JS call stack
        // can unwind — see the package comment for why this must be async.
        return js.Global().Get("Promise").New(js.FuncOf(func(_ js.Value, promiseArgs []js.Value) any {
                resolve := promiseArgs[0]
                go func() {
                        resp := bridge.Call(req)
                        out := js.Global().Get("Uint8Array").New(len(resp))
                        if len(resp) > 0 {
                                js.CopyBytesToJS(out, resp)
                        }
                        resolve.Invoke(out)
                }()
                return js.Undefined()
        }))
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

// Package main is the E2E exit-helper: a real Go wasm module whose main
// returns immediately. The shell's go.run() promise resolves for it, which
// drives the "Uniclient exited" → Retry journey the suite pins.
package main

func main() {}

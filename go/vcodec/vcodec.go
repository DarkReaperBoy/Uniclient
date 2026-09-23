// Package vcodec is the app-wide decode budget shared by every pure-Go
// video decoder in the tree (vp9anim for WebM/VP9 stickers and emoji,
// h264vid for MP4/H.264 video messages).
//
// Why it is shared rather than duplicated per codec: a chat full of
// video stickers plus a couple of video bubbles used to be able to start
// NumCPU producers each, so the two codecs together could open 2×NumCPU
// decoders and thrash the machine. One pool means the whole app has a
// single, bounded decode budget and mixed VP9 + H.264 media round-robins
// the CPU instead of fighting over it.
//
// The permits gate ONE frame decode at a time — acquire before decoding a
// frame, release immediately after — so a producer parks holding no locks
// while it waits its turn.
package vcodec

import "runtime"

// pool carries one permit per allowed concurrent decode. init deposits
// min(NumCPU, 4): enough to hide a slow frame behind another, few enough
// that a wall of visible media cannot starve the UI thread. The cap of 4
// keeps behaviour identical to the original per-package pool.
var pool = make(chan struct{}, 4)

func init() {
	n := runtime.NumCPU()
	if n < 1 {
		n = 1
	}
	if n > 4 {
		n = 4
	}
	for i := 0; i < n; i++ {
		pool <- struct{}{} // deposit the permits
	}
}

// Cap reports the pool's permit capacity.
func Cap() int { return cap(pool) }

// Acquire takes a decode permit (blocking while every permit is busy —
// the caller parks and holds no locks).
//
// The direction matters: a counting semaphore whose Acquire SENDS
// deadlocks the moment the buffer is full. That exact inversion shipped
// once and hung CI on machines where NumCPU fills the buffer, so both
// codecs pin it with a prime-to-capacity regression test — an inverted
// Acquire blocks instantly against a full pool on ANY machine, including
// small ones where spare capacity would otherwise mask the bug.
func Acquire() { <-pool }

// Release returns a decode permit.
func Release() { pool <- struct{}{} }

// PrimeToCapacity deposits permits until the pool is full and reports how
// many it added. It exists so the deadlock regression tests can start from
// a completely full pool.
func PrimeToCapacity() int {
	added := 0
	for {
		select {
		case pool <- struct{}{}:
			added++
		default:
			return added
		}
	}
}

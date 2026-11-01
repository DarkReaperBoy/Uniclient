package vcodec

import "runtime"

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
		pool <- struct{}{}
	}
}

func Cap() int { return cap(pool) }

func Acquire() { <-pool }

func Release() { pool <- struct{}{} }

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

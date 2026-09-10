package utils

import (
	"context"
	"time"
)

// Retry calls fn up to maxAttempts times with exponential backoff.
// It stops early if ctx is cancelled. The backoff starts at baseDelay
// and doubles each attempt, capped at maxDelay.
// If shouldRetry is non-nil, it's called with the error to decide whether to retry;
// returning false stops the loop and returns the error immediately.
// If shouldRetry is nil, all non-nil errors are retried.
func Retry(ctx context.Context, maxAttempts int, baseDelay, maxDelay time.Duration, shouldRetry func(error) bool, fn func() error) error {
	var lastErr error
	delay := baseDelay

	for attempt := 0; attempt < maxAttempts; attempt++ {
		// Check context before each attempt
		if ctx.Err() != nil {
			if lastErr != nil {
				return lastErr
			}
			return ctx.Err()
		}

		lastErr = fn()
		if lastErr == nil {
			return nil
		}

		// Check if we should retry this error
		if shouldRetry != nil && !shouldRetry(lastErr) {
			return lastErr
		}

		// Don't sleep after the last attempt
		if attempt+1 >= maxAttempts {
			break
		}

		// Sleep with context cancellation support
		timer := time.NewTimer(delay)
		select {
		case <-ctx.Done():
			timer.Stop()
			return lastErr
		case <-timer.C:
		}

		// Double the delay, cap at maxDelay
		delay *= 2
		if delay > maxDelay {
			delay = maxDelay
		}
	}

	return lastErr
}

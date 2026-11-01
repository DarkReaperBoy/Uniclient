package utils

import (
	"context"
	"time"
)

func Retry(ctx context.Context, maxAttempts int, baseDelay, maxDelay time.Duration, shouldRetry func(error) bool, fn func() error) error {
	var lastErr error
	delay := baseDelay

	for attempt := 0; attempt < maxAttempts; attempt++ {
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

		if shouldRetry != nil && !shouldRetry(lastErr) {
			return lastErr
		}

		if attempt+1 >= maxAttempts {
			break
		}

		timer := time.NewTimer(delay)
		select {
		case <-ctx.Done():
			timer.Stop()
			return lastErr
		case <-timer.C:
		}

		delay *= 2
		if delay > maxDelay {
			delay = maxDelay
		}
	}

	return lastErr
}

package utils

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestRetrySuccess(t *testing.T) {
	calls := 0
	err := Retry(context.Background(), 5, time.Millisecond, 100*time.Millisecond, nil, func() error {
		calls++
		if calls < 3 {
			return errors.New("not yet")
		}
		return nil
	})
	if err != nil {
		t.Fatalf("expected success, got: %v", err)
	}
	if calls != 3 {
		t.Errorf("calls = %d, want 3", calls)
	}
}

func TestRetryExhausted(t *testing.T) {
	calls := 0
	err := Retry(context.Background(), 3, time.Millisecond, 100*time.Millisecond, nil, func() error {
		calls++
		return errors.New("fail")
	})
	if err == nil {
		t.Fatal("expected error after exhausting attempts")
	}
	if calls != 3 {
		t.Errorf("calls = %d, want 3", calls)
	}
}

func TestRetryContextCancelled(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	calls := 0
	err := Retry(ctx, 100, 50*time.Millisecond, time.Second, nil, func() error {
		calls++
		if calls == 2 {
			cancel()
		}
		return errors.New("fail")
	})
	if err == nil {
		t.Fatal("expected error")
	}
	if calls > 3 {
		t.Errorf("too many calls after cancel: %d", calls)
	}
}

func TestRetryShouldRetryFalse(t *testing.T) {
	permanent := errors.New("permanent")
	calls := 0
	err := Retry(context.Background(), 10, time.Millisecond, 100*time.Millisecond,
		func(e error) bool { return !errors.Is(e, permanent) },
		func() error {
			calls++
			return permanent
		})
	if !errors.Is(err, permanent) {
		t.Fatalf("expected permanent error, got: %v", err)
	}
	if calls != 1 {
		t.Errorf("calls = %d, want 1 (should stop on non-retryable)", calls)
	}
}

func TestRetryFirstAttemptSuccess(t *testing.T) {
	err := Retry(context.Background(), 5, time.Millisecond, 100*time.Millisecond, nil, func() error {
		return nil
	})
	if err != nil {
		t.Fatalf("expected nil, got: %v", err)
	}
}

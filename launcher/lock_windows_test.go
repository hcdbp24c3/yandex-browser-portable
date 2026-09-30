//go:build windows

package main

// lock_windows_test.go — the real Global\ mutex and named-pipe forward
// channel, exercised on the windows-latest runner.
//
// These are the only pieces the CI driver cannot fake: the mutex name is the
// single-instance claim itself, and the pipe shutdown is a hang risk that only
// a real ConnectNamedPipe can show. Every test uses its own mutex name so a
// leaked handle from one case cannot make the next one pass or fail.

import (
	"testing"
	"time"
)

func TestAcquireReportsHeldByAnotherInstance(t *testing.T) {
	const name = `Global\YandexPortable_SingleInstance_test_mutex`

	primary := newPlatformLock()
	ok, err := primary.Acquire(name)
	if err != nil {
		t.Fatalf("first Acquire: %v", err)
	}
	if !ok {
		t.Fatal("first Acquire did not become primary on a free mutex name")
	}
	defer func() { _ = primary.Close() }()

	second := newPlatformLock()
	ok, err = second.Acquire(name)
	if err != nil {
		t.Fatalf("second Acquire: %v", err)
	}
	if ok {
		t.Fatal("second Acquire became primary while the mutex was held")
	}
	if err := second.Close(); err != nil {
		t.Fatalf("second Close: %v", err)
	}

	// Closing the primary must release the name for the next process.
	if err := primary.Close(); err != nil {
		t.Fatalf("primary Close: %v", err)
	}
	reopened := newPlatformLock()
	ok, err = reopened.Acquire(name)
	if err != nil {
		t.Fatalf("third Acquire after Close: %v", err)
	}
	if !ok {
		t.Fatal("mutex name was not released by Close")
	}
	_ = reopened.Close()
}

func TestStopReturnsWhileConnectNamedPipeIsPending(t *testing.T) {
	// The --dry-run selftest opens the listener, never connects to it and then
	// shuts it down. CloseHandle on a handle with a pending synchronous
	// ConnectNamedPipe waits for that call, so an uncancellable shutdown hangs
	// the launcher before it can print its verdict.
	const name = `Global\YandexPortable_SingleInstance_test_stop`

	l := newPlatformLock()
	ok, err := l.Acquire(name)
	if err != nil {
		t.Fatalf("Acquire: %v", err)
	}
	if !ok {
		t.Fatal("Acquire did not become primary on a free mutex name")
	}
	defer func() { _ = l.Close() }()

	stop, err := l.Listen(name, func(string) {})
	if err != nil {
		t.Fatalf("Listen: %v", err)
	}
	if stop == nil {
		t.Fatal("Listen returned no stop func")
	}

	done := make(chan struct{})
	go func() {
		_ = stop()
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("stop() blocked >5s with a ConnectNamedPipe pending: the listener shutdown is not cancellable")
	}
}

func TestForwardDeliversURLToTheListeningPrimary(t *testing.T) {
	const name = `Global\YandexPortable_SingleInstance_test_forward`
	const want = `https://example.test/from-second`

	primary := newPlatformLock()
	ok, err := primary.Acquire(name)
	if err != nil {
		t.Fatalf("Acquire: %v", err)
	}
	if !ok {
		t.Fatal("Acquire did not become primary on a free mutex name")
	}
	defer func() { _ = primary.Close() }()

	got := make(chan string, 1)
	stop, err := primary.Listen(name, func(url string) {
		select {
		case got <- url:
		default:
		}
	})
	if err != nil {
		t.Fatalf("Listen: %v", err)
	}
	defer func() { _ = stop() }()

	second := newPlatformLock()
	delivered, err := second.Forward(name, want)
	if err != nil {
		t.Fatalf("Forward: %v", err)
	}
	if !delivered {
		t.Fatal("Forward reported the URL as not delivered")
	}
	defer func() { _ = second.Close() }()

	select {
	case url := <-got:
		if url != want {
			t.Fatalf("primary received %q, want %q", url, want)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("primary never received the forwarded URL")
	}
}

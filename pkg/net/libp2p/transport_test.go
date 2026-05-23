package libp2p

import (
	"context"
	"net"
	"testing"
	"time"

	libp2pnetwork "github.com/libp2p/go-libp2p/core/network"
)

// TestResponderHandshakeRespectsConnectionDeadline is a regression test for the
// pre-fix vulnerability where a peer that completed TLS but never sent the
// first Keep handshake frame parked the responder goroutine on a blocking
// proto-delim read with no deadline. The libp2p resource manager reserves a
// transient inbound connection slot before the handshake runs and only
// releases it when the upgrade goroutine returns, so a stalled responder
// permanently consumes a slot.
//
// The fix arms a SetDeadline on the encrypted connection in
// transport.SecureInbound before invoking newAuthenticatedInboundConnection.
// This test confirms the responder honors that deadline: it constructs the
// inbound authenticated connection against a peer that never speaks, with a
// short deadline pre-armed on the conn, and asserts the call returns with
// an error well before the test deadline.
func TestResponderHandshakeRespectsConnectionDeadline(t *testing.T) {
	responder := createTestConnectionConfig(t)
	firewall := newMockFirewall()
	if err := firewall.updatePeer(responder.networkPublicKey, true); err != nil {
		t.Fatal(err)
	}

	responderConn, attackerConn := newConnPair()
	defer attackerConn.Close()

	// Attacker holds the other end of the pipe open but never writes the
	// first handshake frame — the responder's UnmarshalFrom would otherwise
	// block forever.

	// Arm the deadline that transport.SecureInbound would arm in production.
	const deadlineWindow = 150 * time.Millisecond
	armedAt := time.Now()
	if err := responderConn.SetDeadline(armedAt.Add(deadlineWindow)); err != nil {
		t.Fatalf("SetDeadline: %v", err)
	}

	done := make(chan error, 1)
	go func() {
		_, err := newAuthenticatedInboundConnection(
			responderConn,
			libp2pnetwork.ConnectionState{},
			responder.peerID,
			responder.networkPrivateKey,
			firewall,
			authProtocolID,
			nil,
		)
		done <- err
	}()

	// The regression we're guarding against is the responder blocking past
	// the armed deadline. The inbound handshake wraps the underlying error
	// with %v (breaking errors.Is/As), so we assert on the timing: the call
	// must return shortly after the deadline fires. A future regression that
	// returns for an unrelated reason would still need to return promptly,
	// keeping this assertion meaningful.
	const slack = 500 * time.Millisecond
	select {
	case err := <-done:
		elapsed := time.Since(armedAt)
		if err == nil {
			t.Fatal("expected handshake to fail under armed deadline")
		}
		if elapsed < deadlineWindow {
			t.Fatalf("handshake returned before deadline fired: elapsed=%v window=%v err=%v",
				elapsed, deadlineWindow, err)
		}
		if elapsed > deadlineWindow+slack {
			t.Fatalf("handshake returned too late: elapsed=%v window=%v err=%v",
				elapsed, deadlineWindow, err)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("responder handshake did not return after deadline — the unbounded read is still present")
	}
}

// TestClearHandshakeDeadlineRemovesArmedDeadline verifies that
// clearHandshakeDeadline actually disarms a previously-armed deadline, so
// post-handshake stream I/O is not subject to the handshake bound. A
// regression here would manifest as established connections being torn down
// 15s after the handshake completes.
func TestClearHandshakeDeadlineRemovesArmedDeadline(t *testing.T) {
	a, b := net.Pipe()
	defer a.Close()
	defer b.Close()

	short := 50 * time.Millisecond
	ctx, cancel := context.WithTimeout(context.Background(), short)
	defer cancel()

	if err := setHandshakeDeadline(ctx, a); err != nil {
		t.Fatalf("setHandshakeDeadline: %v", err)
	}
	if err := clearHandshakeDeadline(a); err != nil {
		t.Fatalf("clearHandshakeDeadline: %v", err)
	}

	// After clearing, a read must NOT trip the previously-armed 50ms deadline.
	// Wait past that window with the read still in flight.
	done := make(chan error, 1)
	go func() {
		_, err := a.Read(make([]byte, 1))
		done <- err
	}()

	select {
	case err := <-done:
		t.Fatalf("Read returned at %v with %v — cleared deadline still armed", short, err)
	case <-time.After(short + 200*time.Millisecond):
		// Expected: read still blocked, the 50ms deadline did not fire.
	}
}

func TestSetHandshakeDeadlinePicksEarlierOfContextOrDefault(t *testing.T) {
	a, b := net.Pipe()
	defer a.Close()
	defer b.Close()

	// Context deadline shorter than handshakeTimeout — context wins.
	short := 50 * time.Millisecond
	ctx, cancel := context.WithTimeout(context.Background(), short)
	defer cancel()

	if err := setHandshakeDeadline(ctx, a); err != nil {
		t.Fatalf("setHandshakeDeadline: %v", err)
	}

	// A read on `a` must observe the short deadline.
	start := time.Now()
	_, err := a.Read(make([]byte, 1))
	elapsed := time.Since(start)
	if err == nil {
		t.Fatal("expected Read to fail with timeout")
	}
	if elapsed > short+200*time.Millisecond {
		t.Fatalf("Read did not honor context deadline; elapsed=%v want≈%v", elapsed, short)
	}

	if err := clearHandshakeDeadline(a); err != nil {
		t.Fatalf("clearHandshakeDeadline: %v", err)
	}
}

func TestSetHandshakeDeadlineUsesDefaultWhenNoContextDeadline(t *testing.T) {
	a, b := net.Pipe()
	defer a.Close()
	defer b.Close()

	ctx := context.Background()
	if err := setHandshakeDeadline(ctx, a); err != nil {
		t.Fatalf("setHandshakeDeadline: %v", err)
	}

	// A read should not return immediately — the default handshakeTimeout
	// (15s) is well above the small window we observe here.
	done := make(chan error, 1)
	go func() {
		_, err := a.Read(make([]byte, 1))
		done <- err
	}()

	select {
	case err := <-done:
		t.Fatalf("Read returned prematurely with %v — default deadline was not respected", err)
	case <-time.After(200 * time.Millisecond):
		// Expected: read still blocked, the default 15s deadline has not fired.
	}

	if err := clearHandshakeDeadline(a); err != nil {
		t.Fatalf("clearHandshakeDeadline: %v", err)
	}
}

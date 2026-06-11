package retransmission

import (
	"context"
	"fmt"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/keep-network/keep-core/internal/testutils"

	"github.com/keep-network/keep-core/pkg/net"
)

func TestRetransmitExpectedNumberOfTimes(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 510*time.Millisecond)
	defer cancel()

	var retransmissionsCount uint64
	ScheduleRetransmissions(
		ctx,
		&testutils.MockLogger{},
		NewTimeTicker(ctx, 50*time.Millisecond),
		func() error {
			atomic.AddUint64(&retransmissionsCount, 1)
			return nil
		},
		WithStandardStrategy(),
	)

	<-ctx.Done()

	// Each retransmission runs in its own goroutine spawned by the tick
	// handler, so the last one may still be in flight when the context is
	// done. Wait for the expected count before asserting on the final value.
	deadline := time.Now().Add(5 * time.Second)
	for atomic.LoadUint64(&retransmissionsCount) < 10 &&
		time.Now().Before(deadline) {
		time.Sleep(time.Millisecond)
	}

	got := atomic.LoadUint64(&retransmissionsCount)
	if got != 10 {
		t.Errorf("expected [10] retransmissions, has [%v]", got)
	}
}

func TestHandlerReceiveUniqueMessages(t *testing.T) {
	var received []net.Message

	handler := WithRetransmissionSupport(func(message net.Message) {
		received = append(received, message)
	})

	handler(&mockNetworkMessage{senderID: "a", seqno: 1})
	handler(&mockNetworkMessage{senderID: "a", seqno: 2})
	handler(&mockNetworkMessage{senderID: "a", seqno: 4})
	handler(&mockNetworkMessage{senderID: "b", seqno: 1})
	handler(&mockNetworkMessage{senderID: "b", seqno: 2})

	if len(received) != 5 {
		t.Fatalf(
			"unexpected number of accepted messages\nactual:   [%v]\nexpected: [5]",
			len(received),
		)
	}
}

func TestHandlerReceiveRetransmissions(t *testing.T) {
	var received []net.Message

	handler := WithRetransmissionSupport(func(message net.Message) {
		received = append(received, message)
	})

	handler(&mockNetworkMessage{senderID: "a", seqno: 1})
	handler(&mockNetworkMessage{senderID: "a", seqno: 2})
	handler(&mockNetworkMessage{senderID: "a", seqno: 2})
	handler(&mockNetworkMessage{senderID: "a", seqno: 1})
	handler(&mockNetworkMessage{senderID: "b", seqno: 2})
	handler(&mockNetworkMessage{senderID: "b", seqno: 1})
	handler(&mockNetworkMessage{senderID: "b", seqno: 1})

	if len(received) != 4 {
		t.Fatalf(
			"unexpected number of accepted messages\nactual:   [%v]\nexpected: [4]",
			len(received),
		)
	}
}

type mockNetworkMessage struct {
	senderID string
	seqno    uint64
}

func (mnm *mockNetworkMessage) TransportSenderID() net.TransportIdentifier {
	return &mockTransportIdentifier{mnm.senderID}
}

func (mnm *mockNetworkMessage) Payload() interface{} {
	panic("not implemented")
}

func (mnm *mockNetworkMessage) Type() string {
	panic("not implemented")
}

func (mnm *mockNetworkMessage) SenderPublicKey() []byte {
	panic("not implemented")
}

func (mnm *mockNetworkMessage) Seqno() uint64 {
	return mnm.seqno
}

// TestScheduleRetransmissions_WithBackoffStrategy verifies that the integrated
// path of ScheduleRetransmissions + BackoffStrategy fires at the correct
// exponential-backoff ticks (1, 3, 6, 11, 20 out of the first 20 ticks).
func TestScheduleRetransmissions_WithBackoffStrategy(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	ticks := make(chan uint64)
	ticker := NewTicker(ticks)

	var retransmissions uint64

	strategy := &signallingStrategy{
		delegate: WithBackoffStrategy(),
		done:     make(chan struct{}, 20),
	}

	ScheduleRetransmissions(
		ctx,
		&testutils.MockLogger{},
		ticker,
		func() error {
			atomic.AddUint64(&retransmissions, 1)
			return nil
		},
		strategy,
	)

	waitForHandlerRegistration(t, ticker)

	// BackoffStrategy fires at ticks 1, 3, 6, 11, 20 -- 5 fires in 20 ticks.
	for i := uint64(1); i <= 20; i++ {
		ticks <- i
	}

	// Each tick's strategy.Tick runs in its own goroutine; join all of them
	// before asserting so an over-firing regression cannot slip through.
	for i := 0; i < 20; i++ {
		select {
		case <-strategy.done:
		case <-time.After(5 * time.Second):
			t.Fatalf("timed out waiting for tick processing; %d/20 ticks done", i)
		}
	}

	got := atomic.LoadUint64(&retransmissions)
	if got != 5 {
		t.Errorf(
			"expected 5 retransmissions with BackoffStrategy in 20 ticks, got %d",
			got,
		)
	}
}

// TestScheduleRetransmissions_LogsRetransmitError verifies that when the
// retransmit function returns an error the error is passed to the logger.
func TestScheduleRetransmissions_LogsRetransmitError(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	ticks := make(chan uint64)
	ticker := NewTicker(ticks)

	logger := &capturingLogger{}

	ScheduleRetransmissions(
		ctx,
		logger,
		ticker,
		func() error { return fmt.Errorf("network unavailable") },
		WithStandardStrategy(),
	)

	waitForHandlerRegistration(t, ticker)

	ticks <- 1

	// The retransmit function and the error logging run in a goroutine
	// spawned by the tick handler; poll until the error shows up instead of
	// sleeping a fixed amount.
	deadline := time.Now().Add(5 * time.Second)
	for len(logger.capturedErrors()) == 0 {
		if time.Now().After(deadline) {
			t.Fatal("expected error to be logged, got none")
		}
		time.Sleep(time.Millisecond)
	}

	errs := logger.capturedErrors()
	if !strings.Contains(errs[0], "network unavailable") {
		t.Errorf("unexpected logged error: %q", errs[0])
	}
}

// TestWithRetransmissionSupport_ConcurrentCallsAreSafe verifies that when
// many goroutines concurrently deliver the same message only one call reaches
// the delegate -- and there are no data races on the deduplication cache.
func TestWithRetransmissionSupport_ConcurrentCallsAreSafe(t *testing.T) {
	var delegateCount uint64

	handler := WithRetransmissionSupport(func(_ net.Message) {
		atomic.AddUint64(&delegateCount, 1)
	})

	var wg sync.WaitGroup
	for i := 0; i < 100; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			handler(&mockNetworkMessage{senderID: "peer-a", seqno: 42})
		}()
	}
	wg.Wait()

	got := atomic.LoadUint64(&delegateCount)
	if got != 1 {
		t.Errorf("expected delegate called exactly once for duplicate messages, got %d", got)
	}
}

type mockTransportIdentifier struct {
	senderID string
}

func (mti *mockTransportIdentifier) String() string {
	return mti.senderID
}

// capturingLogger wraps MockLogger and records Errorf calls for assertions.
type capturingLogger struct {
	testutils.MockLogger
	mu     sync.Mutex
	errors []string
}

func (cl *capturingLogger) Errorf(format string, args ...interface{}) {
	cl.mu.Lock()
	defer cl.mu.Unlock()
	cl.errors = append(cl.errors, fmt.Sprintf(format, args...))
}

func (cl *capturingLogger) capturedErrors() []string {
	cl.mu.Lock()
	defer cl.mu.Unlock()
	return append([]string{}, cl.errors...)
}

// waitForHandlerRegistration blocks until the ticker has at least one onTick
// handler registered. ScheduleRetransmissions registers its handler from a
// goroutine and the ticker consumes ticks even with no handlers attached, so
// ticks sent before the registration completes would be silently lost.
func waitForHandlerRegistration(t *testing.T, ticker *Ticker) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		ticker.handlersMutex.Lock()
		registered := len(ticker.handlers)
		ticker.handlersMutex.Unlock()
		if registered > 0 {
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatal("onTick handler was not registered on time")
}

// signallingStrategy wraps another Strategy and signals on the done channel
// after every Tick call, letting tests join the per-tick goroutines spawned
// by ScheduleRetransmissions before asserting.
type signallingStrategy struct {
	delegate Strategy
	done     chan struct{}
}

func (ss *signallingStrategy) Tick(retransmitFn RetransmitFn) error {
	defer func() { ss.done <- struct{}{} }()
	return ss.delegate.Tick(retransmitFn)
}

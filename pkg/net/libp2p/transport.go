package libp2p

import (
	"context"
	"fmt"
	"net"
	"sync/atomic"
	"time"

	libp2ptls "github.com/libp2p/go-libp2p/p2p/security/tls"

	keepNet "github.com/keep-network/keep-core/pkg/net"
	libp2pcrypto "github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/protocol"
	"github.com/libp2p/go-libp2p/core/sec"
	"github.com/libp2p/go-libp2p/p2p/net/upgrader"
)

// Keep Network protocol identifiers
const (
	// securityProtocolID is the ID of the secured transport protocol.
	securityProtocolID = "/keep/handshake/1.0.0"
	// authProtocolID is the ID of the authentication protocol.
	authProtocolID = "keep"
)

// handshakeTimeout bounds the Keep authentication handshake that runs after
// the TLS layer completes. Without it, a peer that completes TLS and then
// stops sending data parks the connection inside a blocking proto-delim read,
// holding the libp2p resource-manager transient inbound slot until the daemon
// restarts. The libp2p upgrader threads a 15s-deadline context into
// SecureInbound, but per Go's crypto/tls.HandshakeContext contract the ctx
// deadline applies only to the TLS handshake itself, not to subsequent reads
// on the resulting conn — so we arm an absolute deadline on the encrypted
// conn for the duration of the Keep handshake.
const handshakeTimeout = 15 * time.Second

// Compile time assertions of custom types
var _ sec.SecureTransport = (*transport)(nil)
var _ sec.SecureConn = (*authenticatedConnection)(nil)

// MetricsRecorder is an interface for recording network metrics.
type MetricsRecorder interface {
	IncrementCounter(name string, value float64)
	RecordDuration(name string, duration time.Duration)
}

// transport constructs an encrypted and authenticated connection for a peer.
type transport struct {
	protocolID     protocol.ID
	authProtocolID string

	localPeerID peer.ID
	privateKey  libp2pcrypto.PrivKey

	encryptionLayer sec.SecureTransport

	firewall keepNet.Firewall

	// metricsRecorderRef is a pointer to an atomic.Value that holds the metrics recorder.
	// This allows late binding of the metrics recorder after the transport is created.
	metricsRecorderRef *atomic.Value
}

func newEncryptedAuthenticatedTransport(
	protocolID protocol.ID,
	authProtocolID string,
	privateKey libp2pcrypto.PrivKey,
	muxers []upgrader.StreamMuxer,
	firewall keepNet.Firewall,
	metricsRecorderRef *atomic.Value,
) (*transport, error) {
	id, err := peer.IDFromPrivateKey(privateKey)
	if err != nil {
		return nil, err
	}

	encryptionLayer, err := libp2ptls.New(protocolID, privateKey, muxers)
	if err != nil {
		return nil, err
	}

	return &transport{
		protocolID:         protocolID,
		authProtocolID:     authProtocolID,
		localPeerID:        id,
		privateKey:         privateKey,
		encryptionLayer:    encryptionLayer,
		firewall:           firewall,
		metricsRecorderRef: metricsRecorderRef,
	}, nil
}

// getMetricsRecorder returns the current metrics recorder from the atomic reference,
// or nil if none is set.
func (t *transport) getMetricsRecorder() MetricsRecorder {
	if t.metricsRecorderRef == nil {
		return nil
	}
	if val := t.metricsRecorderRef.Load(); val != nil {
		if recorder, ok := val.(MetricsRecorder); ok {
			return recorder
		}
	}
	return nil
}

// SecureInbound secures an inbound connection.
func (t *transport) SecureInbound(
	ctx context.Context,
	connection net.Conn,
	remotePeerID peer.ID,
) (sec.SecureConn, error) {
	encryptedConnection, err := t.encryptionLayer.SecureInbound(ctx, connection, remotePeerID)
	if err != nil {
		return nil, err
	}

	if err := setHandshakeDeadline(ctx, encryptedConnection); err != nil {
		_ = encryptedConnection.Close()
		return nil, err
	}

	ac, err := newAuthenticatedInboundConnection(
		encryptedConnection,
		encryptedConnection.ConnState(),
		t.localPeerID,
		t.privateKey,
		t.firewall,
		t.authProtocolID,
		t.getMetricsRecorder(),
	)
	if err != nil {
		return nil, err
	}

	if err := clearHandshakeDeadline(encryptedConnection); err != nil {
		_ = ac.Close()
		return nil, err
	}

	return ac, nil
}

// SecureOutbound secures an outbound connection.
func (t *transport) SecureOutbound(
	ctx context.Context,
	connection net.Conn,
	remotePeerID peer.ID,
) (sec.SecureConn, error) {
	encryptedConnection, err := t.encryptionLayer.SecureOutbound(
		ctx,
		connection,
		remotePeerID,
	)
	if err != nil {
		return nil, err
	}

	if err := setHandshakeDeadline(ctx, encryptedConnection); err != nil {
		_ = encryptedConnection.Close()
		return nil, err
	}

	ac, err := newAuthenticatedOutboundConnection(
		encryptedConnection,
		encryptedConnection.ConnState(),
		t.localPeerID,
		t.privateKey,
		remotePeerID,
		t.firewall,
		t.authProtocolID,
		t.getMetricsRecorder(),
	)
	if err != nil {
		return nil, err
	}

	if err := clearHandshakeDeadline(encryptedConnection); err != nil {
		_ = ac.Close()
		return nil, err
	}

	return ac, nil
}

// setHandshakeDeadline arms an absolute read/write deadline on the encrypted
// connection covering the Keep authentication handshake. It picks the earlier
// of handshakeTimeout and the parent context's deadline (if any) so that
// caller-supplied deadlines still tighten the bound.
func setHandshakeDeadline(ctx context.Context, conn net.Conn) error {
	deadline := time.Now().Add(handshakeTimeout)
	if d, ok := ctx.Deadline(); ok && d.Before(deadline) {
		deadline = d
	}
	if err := conn.SetDeadline(deadline); err != nil {
		return fmt.Errorf("failed to set handshake deadline: %w", err)
	}
	return nil
}

// clearHandshakeDeadline removes the deadline armed for the handshake so that
// post-handshake stream I/O is not subject to the handshake bound.
func clearHandshakeDeadline(conn net.Conn) error {
	if err := conn.SetDeadline(time.Time{}); err != nil {
		return fmt.Errorf("failed to clear handshake deadline: %w", err)
	}
	return nil
}

// ID is the protocol ID of the security protocol.
func (t *transport) ID() protocol.ID {
	return t.protocolID
}

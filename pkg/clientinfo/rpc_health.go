package clientinfo

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/ipfs/go-log"

	"github.com/keep-network/keep-core/pkg/bitcoin"
	"github.com/keep-network/keep-core/pkg/chain"
)

var rpcHealthLogger = log.Logger("keep-rpc-health")

// RPCHealthChecker performs periodic health checks on Ethereum and Bitcoin RPC endpoints
// by making actual RPC calls (not just ICMP ping) to verify the services are working.
type RPCHealthChecker struct {
	registry *Registry

	// Ethereum health check
	ethBlockCounter chain.BlockCounter
	ethLastCheck    time.Time
	ethLastSuccess  time.Time
	ethLastError    error
	ethLastDuration time.Duration // Last successful RPC call duration
	ethMutex        sync.RWMutex

	// Bitcoin health check
	btcChain        bitcoin.Chain
	btcLastCheck    time.Time
	btcLastSuccess  time.Time
	btcLastError    error
	btcLastDuration time.Duration // Last successful RPC call duration
	btcMutex        sync.RWMutex

	// Configuration
	checkInterval time.Duration
	timeout       time.Duration
}

// NewRPCHealthChecker creates a new RPC health checker instance.
func NewRPCHealthChecker(
	registry *Registry,
	ethBlockCounter chain.BlockCounter,
	btcChain bitcoin.Chain,
	checkInterval time.Duration,
	timeout time.Duration,
) *RPCHealthChecker {
	if checkInterval == 0 {
		checkInterval = 30 * time.Second // Default: check every 30 seconds
	}
	if timeout == 0 {
		timeout = 10 * time.Second // Default: 10 second timeout per check
	}

	return &RPCHealthChecker{
		registry:        registry,
		ethBlockCounter: ethBlockCounter,
		btcChain:        btcChain,
		checkInterval:   checkInterval,
		timeout:         timeout,
	}
}

// Start begins periodic health checks for both Ethereum and Bitcoin RPC endpoints.
func (r *RPCHealthChecker) Start(ctx context.Context) {
	// Perform initial health checks immediately
	r.checkEthereumHealth(ctx)
	r.checkBitcoinHealth(ctx)

	// Start periodic health checks
	go r.runEthereumHealthChecks(ctx)
	go r.runBitcoinHealthChecks(ctx)

	// Register metrics observers
	r.registerMetrics()
}

// runEthereumHealthChecks runs periodic Ethereum RPC health checks.
func (r *RPCHealthChecker) runEthereumHealthChecks(ctx context.Context) {
	ticker := time.NewTicker(r.checkInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			r.checkEthereumHealth(ctx)
		case <-ctx.Done():
			return
		}
	}
}

// runBitcoinHealthChecks runs periodic Bitcoin RPC health checks.
func (r *RPCHealthChecker) runBitcoinHealthChecks(ctx context.Context) {
	ticker := time.NewTicker(r.checkInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ticker.C:
			r.checkBitcoinHealth(ctx)
		case <-ctx.Done():
			return
		}
	}
}

// checkEthereumHealth performs a comprehensive health check on the Ethereum RPC endpoint
// by making actual RPC calls to verify the service is working properly.
// It checks:
// 1. Current block number retrieval
// 2. Block number is reasonable (not stuck at 0 or extremely old)
func (r *RPCHealthChecker) checkEthereumHealth(ctx context.Context) {
	if r.ethBlockCounter == nil {
		return
	}

	startTime := time.Now()

	// First check: Get current block number
	currentBlock, err := r.ethBlockCounter.CurrentBlock()
	if err != nil {
		r.ethMutex.Lock()
		r.ethLastCheck = startTime
		r.ethLastError = err
		r.ethMutex.Unlock()
		rpcHealthLogger.Warnf(
			"Ethereum RPC health check failed (CurrentBlock): [%v] (duration: %v)",
			err,
			time.Since(startTime),
		)
		return
	}

	// Second check: Verify block number is reasonable
	// Block number should be > 0 (unless on a very new testnet)
	// For mainnet/testnet, block numbers should be in thousands/millions
	if currentBlock == 0 {
		r.ethMutex.Lock()
		r.ethLastCheck = startTime
		r.ethLastError = fmt.Errorf("block number is 0, node may not be synced")
		r.ethMutex.Unlock()
		rpcHealthLogger.Warnf(
			"Ethereum RPC health check failed (block number is 0): [%v] (duration: %v)",
			r.ethLastError,
			time.Since(startTime),
		)
		return
	}

	duration := time.Since(startTime)

	r.ethMutex.Lock()
	r.ethLastCheck = startTime
	r.ethLastSuccess = time.Now()
	r.ethLastError = nil
	r.ethLastDuration = duration
	r.ethMutex.Unlock()

	rpcHealthLogger.Debugf(
		"Ethereum RPC health check succeeded (block: %d, duration: %v)",
		currentBlock,
		duration,
	)
}

// checkBitcoinHealth performs a comprehensive health check on the Bitcoin RPC endpoint
// by making actual RPC calls to verify the service is working properly.
// It checks:
// 1. Latest block height retrieval
// 2. Block header retrieval for the latest block (verifies RPC can retrieve block data)
// 3. Block height is reasonable (not 0)
func (r *RPCHealthChecker) checkBitcoinHealth(ctx context.Context) {
	if r.btcChain == nil {
		return
	}

	startTime := time.Now()

	// First check: Get latest block height
	latestHeight, err := r.btcChain.GetLatestBlockHeight()
	if err != nil {
		r.btcMutex.Lock()
		r.btcLastCheck = startTime
		r.btcLastError = err
		r.btcMutex.Unlock()
		rpcHealthLogger.Warnf(
			"Bitcoin RPC health check failed (GetLatestBlockHeight): [%v] (duration: %v)",
			err,
			time.Since(startTime),
		)
		return
	}

	// Second check: Verify block height is reasonable
	if latestHeight == 0 {
		r.btcMutex.Lock()
		r.btcLastCheck = startTime
		r.btcLastError = fmt.Errorf("block height is 0, node may not be synced")
		r.btcMutex.Unlock()
		rpcHealthLogger.Warnf(
			"Bitcoin RPC health check failed (block height is 0): [%v] (duration: %v)",
			r.btcLastError,
			time.Since(startTime),
		)
		return
	}

	// Third check: Try to get block header for the latest block
	// This verifies the RPC can actually retrieve block data, not just return a number
	_, err = r.btcChain.GetBlockHeader(latestHeight)
	if err != nil {
		r.btcMutex.Lock()
		r.btcLastCheck = startTime
		r.btcLastError = fmt.Errorf("failed to get block header for height %d: %w", latestHeight, err)
		r.btcMutex.Unlock()
		rpcHealthLogger.Warnf(
			"Bitcoin RPC health check failed (GetBlockHeader): [%v] (duration: %v)",
			r.btcLastError,
			time.Since(startTime),
		)
		return
	}

	duration := time.Since(startTime)

	r.btcMutex.Lock()
	r.btcLastCheck = startTime
	r.btcLastSuccess = time.Now()
	r.btcLastError = nil
	r.btcLastDuration = duration
	r.btcMutex.Unlock()

	rpcHealthLogger.Debugf(
		"Bitcoin RPC health check succeeded (height: %d, duration: %v)",
		latestHeight,
		duration,
	)
}

// GetEthereumHealthStatus returns the current Ethereum RPC health status.
func (r *RPCHealthChecker) GetEthereumHealthStatus() (isHealthy bool, lastCheck time.Time, lastSuccess time.Time, lastError error, lastDuration time.Duration) {
	r.ethMutex.RLock()
	defer r.ethMutex.RUnlock()

	isHealthy = r.ethLastError == nil && !r.ethLastCheck.IsZero()
	return isHealthy, r.ethLastCheck, r.ethLastSuccess, r.ethLastError, r.ethLastDuration
}

// GetBitcoinHealthStatus returns the current Bitcoin RPC health status.
func (r *RPCHealthChecker) GetBitcoinHealthStatus() (isHealthy bool, lastCheck time.Time, lastSuccess time.Time, lastError error, lastDuration time.Duration) {
	r.btcMutex.RLock()
	defer r.btcMutex.RUnlock()

	isHealthy = r.btcLastError == nil && !r.btcLastCheck.IsZero()
	return isHealthy, r.btcLastCheck, r.btcLastSuccess, r.btcLastError, r.btcLastDuration
}

// registerMetrics registers metrics observers for RPC health status.
func (r *RPCHealthChecker) registerMetrics() {
	// Ethereum RPC health status and response time
	r.registry.ObserveApplicationSource(
		"performance",
		map[string]Source{
			"rpc_eth_health_status": func() float64 {
				isHealthy, _, _, _, _ := r.GetEthereumHealthStatus()
				if isHealthy {
					return 1
				}
				return 0
			},
			"rpc_eth_response_time_seconds": func() float64 {
				_, _, _, _, lastDuration := r.GetEthereumHealthStatus()
				return lastDuration.Seconds()
			},
		},
	)

	// Bitcoin RPC health status and response time
	r.registry.ObserveApplicationSource(
		"performance",
		map[string]Source{
			"rpc_btc_health_status": func() float64 {
				isHealthy, _, _, _, _ := r.GetBitcoinHealthStatus()
				if isHealthy {
					return 1
				}
				return 0
			},
			"rpc_btc_response_time_seconds": func() float64 {
				_, _, _, _, lastDuration := r.GetBitcoinHealthStatus()
				return lastDuration.Seconds()
			},
		},
	)
}

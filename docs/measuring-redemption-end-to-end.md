# Measuring Redemption Speed End-to-End

Yes, **end-to-end redemption speed can be measured**! This guide explains how to track redemptions from on-chain request submission to Bitcoin transaction confirmation.

## End-to-End Redemption Timeline

```
┌─────────────────────────────────────────────────────────────────┐
│                    End-to-End Redemption Flow                    │
└─────────────────────────────────────────────────────────────────┘

1. User submits redemption request on-chain
   └─> RedemptionRequested event emitted
       └─> RequestedAt timestamp recorded

2. Coordination leader creates proposal
   └─> Proposal creation time

3. Operators validate and execute redemption
   └─> Action execution starts
       ├─> Validation step
       ├─> Transaction assembly
       ├─> Signing step
       └─> Broadcast step
           └─> Bitcoin transaction broadcast

4. Bitcoin network confirms transaction
   └─> Transaction confirmation time

Total End-to-End Time = Confirmation Time - Request Time
```

## Available Data Points

### 1. Request Timestamp ✅
**Location**: `pkg/tbtc/RedemptionRequest.RequestedAt`
- Available from on-chain `RedemptionRequested` event
- Tracked in `pkg/tbtcpg/redemptions.go` when finding pending redemptions
- Already stored: `pendingRedemption.RequestedAt`

### 2. Action Start Time ✅
**Location**: `pkg/tbtc/wallet.go` - `walletDispatcher.dispatch()`
- When redemption action starts executing
- Currently tracked: `startTime := time.Now()`

### 3. Action Completion Time ✅
**Location**: `pkg/tbtc/wallet.go` - `walletDispatcher.dispatch()`
- When redemption action completes (success or failure)
- Currently tracked: `time.Since(startTime)`

### 4. Bitcoin Broadcast Time ✅
**Location**: `pkg/tbtc/wallet.go` - `broadcastTransaction()`
- When transaction is successfully broadcast to Bitcoin network
- Transaction hash available: `tx.Hash()`

### 5. Bitcoin Confirmation Time ✅
**Location**: `pkg/bitcoin/electrum/electrum.go` - `GetTransactionConfirmations()`
- Can check when transaction gets confirmed
- Method exists: `btcChain.GetTransactionConfirmations(txHash)`

## Implementation: End-to-End Tracking

### Option 1: Track Request Timestamp Through Redemption Flow

**Step 1**: Pass `RequestedAt` through redemption action

```go
// In pkg/tbtc/redemption.go
type redemptionAction struct {
    // ... existing fields ...
    requestTimestamp time.Time  // NEW: Track when request was made
}

func newRedemptionAction(
    logger *zap.SugaredLogger,
    chain Chain,
    btcChain bitcoin.Chain,
    redeemingWallet wallet,
    signingExecutor walletSigningExecutor,
    proposal *RedemptionProposal,
    proposalProcessingStartBlock uint64,
    proposalExpiryBlock uint64,
    waitForBlockFn waitForBlockFn,
    requestTimestamp time.Time,  // NEW parameter
) *redemptionAction {
    // ... existing code ...
    return &redemptionAction{
        // ... existing fields ...
        requestTimestamp: requestTimestamp,  // NEW
    }
}
```

**Step 2**: Extract request timestamp when creating redemption action

```go
// In pkg/tbtc/node.go - handleRedemptionProposal()
func (n *node) handleRedemptionProposal(
    wallet wallet,
    proposal *RedemptionProposal,
    startBlock uint64,
    expiryBlock uint64,
) {
    // Get request timestamp from chain
    walletPublicKeyHash := bitcoin.PublicKeyHash(wallet.publicKey)
    
    // Extract request timestamp from proposal's redeemers
    // Need to get RequestedAt for each redeemer output script
    var earliestRequestTime time.Time
    for _, script := range proposal.RedeemersOutputScripts {
        pendingRedemption, found, err := n.chain.GetPendingRedemptionRequest(
            walletPublicKeyHash,
            script,
        )
        if found && err == nil {
            if earliestRequestTime.IsZero() || 
               pendingRedemption.RequestedAt.Before(earliestRequestTime) {
                earliestRequestTime = pendingRedemption.RequestedAt
            }
        }
    }
    
    action := newRedemptionAction(
        walletActionLogger,
        n.chain,
        n.btcChain,
        wallet,
        signingExecutor,
        proposal,
        startBlock,
        expiryBlock,
        n.waitForBlockHeight,
        earliestRequestTime,  // Pass request timestamp
    )
    
    err = n.walletDispatcher.dispatch(action)
    // ...
}
```

**Step 3**: Record end-to-end metrics

```go
// In pkg/tbtc/redemption.go - execute()
func (ra *redemptionAction) execute() error {
    actionStartTime := time.Now()
    
    // ... existing execution steps ...
    
    // After successful broadcast
    redemptionTx, err := ra.transactionExecutor.signTransaction(...)
    if err != nil {
        return err
    }
    
    err = ra.transactionExecutor.broadcastTransaction(...)
    if err != nil {
        return err
    }
    
    // Record end-to-end metrics
    if ra.metricsRecorder != nil && !ra.requestTimestamp.IsZero() {
        // Time from request to action completion
        requestToCompletion := time.Since(ra.requestTimestamp)
        ra.metricsRecorder.RecordDuration(
            "redemption_request_to_completion_duration_seconds",
            requestToCompletion,
        )
        
        // Time from request to broadcast
        requestToBroadcast := time.Since(ra.requestTimestamp)
        ra.metricsRecorder.RecordDuration(
            "redemption_request_to_broadcast_duration_seconds",
            requestToBroadcast,
        )
        
        // Store transaction hash for later confirmation tracking
        txHash := redemptionTx.Hash()
        // Could store in a map or use labels
        ra.metricsRecorder.RecordDuration(
            "redemption_request_to_broadcast_duration_seconds",
            requestToBroadcast,
            map[string]string{
                "tx_hash": txHash.Hex(bitcoin.ReversedByteOrder),
            },
        )
    }
    
    return nil
}
```

### Option 2: Track Bitcoin Confirmation (Post-Broadcast)

**Step 1**: Monitor Bitcoin confirmations

```go
// New function to track confirmation
func (ra *redemptionAction) trackBitcoinConfirmation(
    txHash bitcoin.Hash,
    requestTimestamp time.Time,
) {
    if ra.metricsRecorder == nil || requestTimestamp.IsZero() {
        return
    }
    
    // Poll for confirmation (or use event-driven approach)
    go func() {
        ticker := time.NewTicker(30 * time.Second)
        defer ticker.Stop()
        
        for {
            select {
            case <-ticker.C:
                confirmations, err := ra.btcChain.GetTransactionConfirmations(txHash)
                if err == nil && confirmations > 0 {
                    // Transaction confirmed!
                    confirmationTime := time.Now()
                    endToEndDuration := confirmationTime.Sub(requestTimestamp)
                    
                    ra.metricsRecorder.RecordDuration(
                        "redemption_end_to_end_duration_seconds",
                        endToEndDuration,
                    )
                    
                    ra.metricsRecorder.RecordDuration(
                        "redemption_bitcoin_confirmation_duration_seconds",
                        confirmationTime.Sub(broadcastTime),
                    )
                    
                    return
                }
            case <-time.After(24 * time.Hour):
                // Timeout after 24 hours
                return
            }
        }
    }()
}
```

**Step 2**: Call after broadcast

```go
// In execute() after successful broadcast
err = ra.transactionExecutor.broadcastTransaction(...)
if err != nil {
    return err
}

broadcastTime := time.Now()

// Start tracking confirmation
ra.trackBitcoinConfirmation(redemptionTx.Hash(), ra.requestTimestamp)
```

## Complete End-to-End Metrics

### Metrics to Implement

1. **`redemption_request_to_completion_duration_seconds`**
   - Request → Action completion
   - Histogram

2. **`redemption_request_to_broadcast_duration_seconds`**
   - Request → Bitcoin broadcast
   - Histogram

3. **`redemption_end_to_end_duration_seconds`**
   - Request → Bitcoin confirmation
   - Histogram (most important!)

4. **`redemption_bitcoin_confirmation_duration_seconds`**
   - Broadcast → Confirmation
   - Histogram

5. **`redemption_coordination_delay_seconds`**
   - Request → Proposal creation
   - Histogram

### Metric Labels

```go
map[string]string{
    "wallet_pkh": hex.EncodeToString(walletPKH[:]),
    "tx_hash": txHash.Hex(bitcoin.ReversedByteOrder),
    "redemption_count": strconv.Itoa(len(proposal.RedeemersOutputScripts)),
}
```

## Alternative: External Monitoring Script

If modifying the codebase is not immediately feasible, you can track end-to-end speed externally:

### Script: Track End-to-End Redemptions

```bash
#!/bin/bash
# scripts/track-redemption-end-to-end.sh

# Monitor RedemptionRequested events
# Track transaction hashes
# Monitor Bitcoin confirmations
# Calculate end-to-end duration

# 1. Watch for RedemptionRequested events
cast watch --address <BridgeAddress> \
  "RedemptionRequested(address indexed walletPubKeyHash, bytes redeemerOutputScript, address indexed redeemer, uint64 requestedAmount, uint64 treasuryFee, uint64 txMaxFee)" \
  --rpc-url http://localhost:8545 | \
  jq -r '.args | "\(.walletPubKeyHash) \(.redeemerOutputScript) \(.redeemer)"' | \
  while read wallet_pkh script redeemer; do
    request_time=$(date +%s)
    echo "$request_time|$wallet_pkh|$script|$redeemer" >> /tmp/redemption_requests.log
  done

# 2. Monitor redemption transactions
# Extract from logs or monitor Bitcoin network
# Match by redeemer output script

# 3. Calculate end-to-end time
# Compare request_time with confirmation_time
```

## Prometheus Queries

Once implemented, query end-to-end metrics:

```promql
# Average end-to-end redemption time
rate(redemption_end_to_end_duration_seconds_sum[5m]) / 
  rate(redemption_end_to_end_duration_seconds_count[5m])

# P95 end-to-end time
histogram_quantile(0.95, 
  rate(redemption_end_to_end_duration_seconds_bucket[5m]))

# P99 end-to-end time
histogram_quantile(0.99, 
  rate(redemption_end_to_end_duration_seconds_bucket[5m]))

# Breakdown by phase
# Request to broadcast
rate(redemption_request_to_broadcast_duration_seconds_sum[5m]) / 
  rate(redemption_request_to_broadcast_duration_seconds_count[5m])

# Broadcast to confirmation
rate(redemption_bitcoin_confirmation_duration_seconds_sum[5m]) / 
  rate(redemption_bitcoin_confirmation_duration_seconds_count[5m])
```

## Current Limitations

1. **Request timestamp not passed through**: Currently, `RequestedAt` is available but not passed to `redemptionAction`
2. **No confirmation tracking**: Bitcoin confirmation is not automatically tracked after broadcast
3. **No correlation**: Request events and completion events are not correlated

## Implementation Priority

### Phase 1: Basic End-to-End (Easiest)
- Pass `RequestedAt` to `redemptionAction`
- Record `redemption_request_to_completion_duration_seconds`
- Record `redemption_request_to_broadcast_duration_seconds`

### Phase 2: Bitcoin Confirmation Tracking
- Track Bitcoin transaction confirmations
- Record `redemption_end_to_end_duration_seconds`
- Record `redemption_bitcoin_confirmation_duration_seconds`

### Phase 3: Full Correlation
- Correlate requests with completions
- Track multiple redemptions in batch
- Add detailed labels for filtering

## Example: Measuring a Specific Redemption

```bash
# 1. Find redemption request
cast logs --from-block <start> --to-block <end> \
  --address <BridgeAddress> \
  "RedemptionRequested(...)" | \
  grep <redeemer_address>

# 2. Extract request timestamp
REQUEST_TIME=$(cast logs ... | jq -r '.blockTime')

# 3. Find Bitcoin transaction (from logs or chain)
TX_HASH="<bitcoin_tx_hash>"

# 4. Check confirmation
bitcoin-cli gettransaction $TX_HASH | jq '.confirmations'

# 5. Calculate end-to-end time
CONFIRMATION_TIME=$(bitcoin-cli gettransaction $TX_HASH | jq '.blocktime')
END_TO_END=$((CONFIRMATION_TIME - REQUEST_TIME))
echo "End-to-end time: ${END_TO_END} seconds"
```

## See Also

- [Redemption Metrics Summary](./redemption-metrics-summary.md) - All redemption metrics
- [Redemption Metrics Implementation](./redemption-specific-metrics-implementation.md) - Implementation guide
- [Measuring Redemption Speed](./measuring-redemption-speed.md) - General redemption speed guide


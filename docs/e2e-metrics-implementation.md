# End-to-End Metrics Implementation for Deposits and Redemptions

## Overview

This document outlines the implementation of end-to-end metrics to measure deposit and redemption processing times in the tBTC system.

## Metrics to Track

### Deposit Metrics

1. **`deposit_e2e_duration_seconds`** (Histogram)
   - Time from `DepositRevealed` event to `DepositSwept` event
   - Labels: `wallet_pkh`, `deposit_key`

2. **`deposit_coordination_duration_seconds`** (Histogram)
   - Time from deposit detection to proposal creation
   - Labels: `wallet_pkh`

3. **`deposit_signing_duration_seconds`** (Histogram)
   - Time from proposal creation to transaction signing completion
   - Labels: `wallet_pkh`

4. **`deposit_broadcast_duration_seconds`** (Histogram)
   - Time from signing completion to Bitcoin broadcast
   - Labels: `wallet_pkh`

5. **`deposit_btc_confirmation_duration_seconds`** (Histogram)
   - Time from broadcast to Bitcoin confirmations
   - Labels: `wallet_pkh`

6. **`deposit_mint_duration_seconds`** (Histogram)
   - Time from Bitcoin confirmations to tBTC minting
   - Labels: `wallet_pkh`

### Redemption Metrics

1. **`redemption_e2e_duration_seconds`** (Histogram)
   - Time from `RedemptionRequested` event to `RedemptionCompleted` event
   - Labels: `wallet_pkh`, `redemption_key`

2. **`redemption_coordination_duration_seconds`** (Histogram)
   - Time from redemption request to proposal creation
   - Labels: `wallet_pkh`

3. **`redemption_signing_duration_seconds`** (Histogram)
   - Time from proposal creation to transaction signing completion
   - Labels: `wallet_pkh`

4. **`redemption_broadcast_duration_seconds`** (Histogram)
   - Time from signing completion to Bitcoin broadcast
   - Labels: `wallet_pkh`

5. **`redemption_btc_confirmation_duration_seconds`** (Histogram)
   - Time from broadcast to Bitcoin confirmations
   - Labels: `wallet_pkh`

6. **`redemption_proof_submission_duration_seconds`** (Histogram)
   - Time from Bitcoin confirmations to proof submission
   - Labels: `wallet_pkh`

## Implementation Approach

### Phase 1: Event Tracking

Track when deposits/redemptions start and end by monitoring chain events:

**For Deposits:**
- Start: `DepositRevealed` event (block number + timestamp)
- End: `DepositsSwept` event (block number + timestamp)
  - Note: This event contains `walletPubKeyHash` and `sweepTxHash`
  - Need to match deposits by wallet PKH and track which deposits were in the sweep

**For Redemptions:**
- Start: `RedemptionRequested` event (block number + timestamp)
- End: `RedemptionsCompleted` event (block number + timestamp)
  - Note: This event contains `walletPubKeyHash` and `redemptionTxHash`
  - Need to match redemptions by wallet PKH and output script

### Phase 2: Internal Phase Tracking

Track intermediate phases within the wallet action execution:

1. **Coordination Phase**: From detection to proposal creation
2. **Signing Phase**: From proposal to signed transaction
3. **Broadcast Phase**: From signing to Bitcoin broadcast
4. **Confirmation Phase**: From broadcast to confirmations
5. **Finalization Phase**: From confirmations to on-chain completion

### Phase 3: Metric Recording

Use the existing `PerformanceMetrics` infrastructure to record durations at key points.

## Implementation Locations

### 1. Add Metric Constants

**File**: `pkg/clientinfo/performance.go`

```go
const (
    // Deposit Metrics
    MetricDepositE2EDurationSeconds          = "deposit_e2e_duration_seconds"
    MetricDepositCoordinationDurationSeconds = "deposit_coordination_duration_seconds"
    MetricDepositSigningDurationSeconds      = "deposit_signing_duration_seconds"
    MetricDepositBroadcastDurationSeconds    = "deposit_broadcast_duration_seconds"
    MetricDepositBTCConfirmationDurationSeconds = "deposit_btc_confirmation_duration_seconds"
    MetricDepositMintDurationSeconds         = "deposit_mint_duration_seconds"
    
    // Redemption Metrics
    MetricRedemptionE2EDurationSeconds          = "redemption_e2e_duration_seconds"
    MetricRedemptionCoordinationDurationSeconds = "redemption_coordination_duration_seconds"
    MetricRedemptionSigningDurationSeconds      = "redemption_signing_duration_seconds"
    MetricRedemptionBroadcastDurationSeconds    = "redemption_broadcast_duration_seconds"
    MetricRedemptionBTCConfirmationDurationSeconds = "redemption_btc_confirmation_duration_seconds"
    MetricRedemptionProofSubmissionDurationSeconds = "redemption_proof_submission_duration_seconds"
)
```

### 2. Track Deposit Start Time

**File**: `pkg/tbtcpg/deposit_sweep.go`

Track when deposits are detected and when proposals are created:

```go
// In DepositSweepTask.Run()
func (dst *DepositSweepTask) Run(request *tbtc.CoordinationProposalRequest) (
    tbtc.CoordinationProposal,
    bool,
    error,
) {
    startTime := time.Now()
    
    // ... existing code ...
    
    // Record coordination duration when proposal is created
    if metricsRecorder != nil {
        metricsRecorder.RecordDuration(
            clientinfo.MetricDepositCoordinationDurationSeconds,
            time.Since(startTime),
        )
    }
    
    return proposal, true, nil
}
```

### 3. Track Deposit Action Phases

**File**: `pkg/tbtc/deposit_sweep.go`

Track phases within deposit sweep action execution:

```go
func (dsa *depositSweepAction) execute() error {
    actionStartTime := time.Now()
    var signingStartTime, broadcastStartTime time.Time
    
    // ... validate proposal ...
    
    // Start signing phase
    signingStartTime = time.Now()
    sweepTx, err := dsa.transactionExecutor.signTransaction(...)
    if err != nil {
        return fmt.Errorf("sign transaction step failed: [%v]", err)
    }
    
    // Record signing duration
    if dsa.metricsRecorder != nil {
        dsa.metricsRecorder.RecordDuration(
            clientinfo.MetricDepositSigningDurationSeconds,
            time.Since(signingStartTime),
        )
    }
    
    // Start broadcast phase
    broadcastStartTime = time.Now()
    err = dsa.transactionExecutor.broadcastTransaction(...)
    if err != nil {
        return fmt.Errorf("broadcast transaction step failed: [%v]", err)
    }
    
    // Record broadcast duration
    if dsa.metricsRecorder != nil {
        dsa.metricsRecorder.RecordDuration(
            clientinfo.MetricDepositBroadcastDurationSeconds,
            time.Since(broadcastStartTime),
        )
    }
    
    // ... rest of execution ...
    
    return nil
}
```

### 4. Track Redemption Action Phases

**File**: `pkg/tbtc/redemption.go`

Similar tracking for redemption actions:

```go
func (ra *redemptionAction) execute() error {
    actionStartTime := time.Now()
    var signingStartTime, broadcastStartTime time.Time
    
    // ... validate proposal ...
    
    // Start signing phase
    signingStartTime = time.Now()
    redemptionTx, err := ra.transactionExecutor.signTransaction(...)
    if err != nil {
        return fmt.Errorf("sign transaction step failed: [%v]", err)
    }
    
    // Record signing duration
    if ra.metricsRecorder != nil {
        ra.metricsRecorder.RecordDuration(
            clientinfo.MetricRedemptionSigningDurationSeconds,
            time.Since(signingStartTime),
        )
    }
    
    // Start broadcast phase
    broadcastStartTime = time.Now()
    err = ra.transactionExecutor.broadcastTransaction(...)
    if err != nil {
        return fmt.Errorf("broadcast transaction step failed: [%v]", err)
    }
    
    // Record broadcast duration
    if ra.metricsRecorder != nil {
        ra.metricsRecorder.RecordDuration(
            clientinfo.MetricRedemptionBroadcastDurationSeconds,
            time.Since(broadcastStartTime),
        )
    }
    
    // ... rest of execution ...
    
    return nil
}
```

### 5. Track End-to-End Times via Event Monitoring

**File**: `pkg/tbtc/node.go` or new file `pkg/tbtc/e2e_metrics.go`

Monitor chain events to track end-to-end times:

```go
// Track deposit lifecycle
// Note: DepositsSwept event doesn't list individual deposits, so we need to:
// 1. Track deposits by wallet PKH when revealed
// 2. When DepositsSwept fires, look up all deposits for that wallet PKH
// 3. Calculate E2E time for each deposit in that sweep
type depositLifecycleTracker struct {
    revealedAt map[string]time.Time // depositKey -> time
    walletDeposits map[string][]string // walletPKH -> []depositKey
    metricsRecorder interface {
        RecordDuration(name string, duration time.Duration)
    }
    chain Chain // to get block timestamps
}

func (n *node) trackDepositRevealed(event *DepositRevealedEvent) {
    depositKey := BuildDepositKey(event.FundingTxHash, event.FundingOutputIndex)
    key := depositKey.Text(16)
    walletPKH := hex.EncodeToString(event.WalletPublicKeyHash[:])
    
    if n.depositTracker != nil {
        // Get block timestamp for accurate timing
        block, err := n.chain.BlockByNumber(event.BlockNumber)
        if err == nil {
            n.depositTracker.revealedAt[key] = time.Unix(int64(block.Time()), 0)
        } else {
            n.depositTracker.revealedAt[key] = time.Now()
        }
        
        // Track which deposits belong to which wallet
        n.depositTracker.walletDeposits[walletPKH] = append(
            n.depositTracker.walletDeposits[walletPKH],
            key,
        )
    }
}

func (n *node) trackDepositsSwept(event *DepositsSweptEvent) {
    walletPKH := hex.EncodeToString(event.WalletPubKeyHash[:])
    
    if n.depositTracker != nil {
        // Get block timestamp for accurate timing
        block, err := n.chain.BlockByNumber(event.BlockNumber)
        sweptAt := time.Now()
        if err == nil {
            sweptAt = time.Unix(int64(block.Time()), 0)
        }
        
        // For each deposit in this wallet's sweep, record E2E time
        depositKeys := n.depositTracker.walletDeposits[walletPKH]
        for _, key := range depositKeys {
            if revealedAt, exists := n.depositTracker.revealedAt[key]; exists {
                duration := sweptAt.Sub(revealedAt)
                n.depositTracker.metricsRecorder.RecordDuration(
                    clientinfo.MetricDepositE2EDurationSeconds,
                    duration,
                )
                delete(n.depositTracker.revealedAt, key)
            }
        }
        
        // Clean up wallet tracking
        delete(n.depositTracker.walletDeposits, walletPKH)
    }
}
```

## Event Monitoring Setup

### Subscribe to Events

**File**: `pkg/tbtc/node.go`

Add event subscriptions for tracking:

```go
func (n *node) setupE2EMetrics(ctx context.Context) error {
    // Note: Need to add these methods to Chain interface if they don't exist
    // or use bridge contract directly
    
    bridge := n.chain.(*ethereum.TbtcChain).Bridge()
    
    // Subscribe to DepositRevealed events
    depositRevealedSub := bridge.DepositRevealedEvent(nil, nil, nil)
    depositRevealedSub.OnEvent(func(
        fundingTxHash [32]byte,
        fundingOutputIndex uint32,
        depositor common.Address,
        amount uint64,
        blindingFactor [8]byte,
        walletPubKeyHash [20]byte,
        refundPubKeyHash [20]byte,
        blockNumber uint64,
    ) {
        event := &DepositRevealedEvent{
            FundingTxHash:      fundingTxHash,
            FundingOutputIndex:  fundingOutputIndex,
            Depositor:           depositor,
            Amount:              amount,
            BlindingFactor:      blindingFactor,
            WalletPublicKeyHash: walletPubKeyHash,
            RefundPublicKeyHash: refundPubKeyHash,
            BlockNumber:         blockNumber,
        }
        n.trackDepositRevealed(event)
    })
    
    // Subscribe to DepositsSwept events
    depositsSweptSub := bridge.DepositsSweptEvent(nil)
    depositsSweptSub.OnEvent(func(
        walletPubKeyHash [20]byte,
        sweepTxHash [32]byte,
        blockNumber uint64,
    ) {
        event := &DepositsSweptEvent{
            WalletPubKeyHash: walletPubKeyHash,
            SweepTxHash:      sweepTxHash,
            BlockNumber:      blockNumber,
        }
        n.trackDepositsSwept(event)
    })
    
    // Subscribe to RedemptionRequested events
    redemptionRequestedSub := bridge.RedemptionRequestedEvent(nil, nil, nil)
    redemptionRequestedSub.OnEvent(func(
        walletPubKeyHash [20]byte,
        redeemerOutputScript []byte,
        redeemer common.Address,
        requestedAmount uint64,
        treasuryFee uint64,
        txMaxFee uint64,
        blockNumber uint64,
    ) {
        event := &RedemptionRequestedEvent{
            WalletPublicKeyHash:  walletPubKeyHash,
            RedeemerOutputScript: redeemerOutputScript,
            Redeemer:             redeemer,
            RequestedAmount:      requestedAmount,
            TreasuryFee:          treasuryFee,
            TxMaxFee:             txMaxFee,
            BlockNumber:          blockNumber,
        }
        n.trackRedemptionRequested(event)
    })
    
    // Subscribe to RedemptionsCompleted events
    redemptionsCompletedSub := bridge.RedemptionsCompletedEvent(nil, nil)
    redemptionsCompletedSub.OnEvent(func(
        walletPubKeyHash [20]byte,
        redemptionTxHash [32]byte,
        blockNumber uint64,
    ) {
        event := &RedemptionsCompletedEvent{
            WalletPubKeyHash:  walletPubKeyHash,
            RedemptionTxHash:  redemptionTxHash,
            BlockNumber:       blockNumber,
        }
        n.trackRedemptionsCompleted(event)
    })
    
    // Clean up on context cancellation
    go func() {
        <-ctx.Done()
        depositRevealedSub.Unsubscribe()
        depositsSweptSub.Unsubscribe()
        redemptionRequestedSub.Unsubscribe()
        redemptionsCompletedSub.Unsubscribe()
    }()
    
    return nil
}
```

## Testing

### Unit Tests

Test metric recording at each phase:

```go
func TestDepositSweepMetrics(t *testing.T) {
    metrics := &MockMetricsRecorder{}
    
    action := newDepositSweepAction(..., metrics)
    
    err := action.execute()
    
    assert.NoError(t, err)
    assert.True(t, metrics.RecordedDuration("deposit_signing_duration_seconds"))
    assert.True(t, metrics.RecordedDuration("deposit_broadcast_duration_seconds"))
}
```

### Integration Tests

Test end-to-end metric tracking:

```go
func TestDepositE2EMetrics(t *testing.T) {
    // Create deposit
    // Wait for sweep
    // Verify e2e metric was recorded
}
```

## Metric Export

Metrics are automatically exported via the `/metrics` endpoint (Prometheus format) when `PerformanceMetrics` is enabled.

## Example Queries

### Prometheus Queries

```promql
# Average deposit E2E time
rate(deposit_e2e_duration_seconds_sum[5m]) / rate(deposit_e2e_duration_seconds_count[5m])

# 95th percentile deposit E2E time
histogram_quantile(0.95, rate(deposit_e2e_duration_seconds_bucket[5m]))

# Average redemption E2E time
rate(redemption_e2e_duration_seconds_sum[5m]) / rate(redemption_e2e_duration_seconds_count[5m])

# Breakdown by phase
rate(deposit_coordination_duration_seconds_sum[5m]) / rate(deposit_coordination_duration_seconds_count[5m])
rate(deposit_signing_duration_seconds_sum[5m]) / rate(deposit_signing_duration_seconds_count[5m])
rate(deposit_broadcast_duration_seconds_sum[5m]) / rate(deposit_broadcast_duration_seconds_count[5m])
```

## Next Steps

1. **Add metric constants** to `performance.go`
2. **Add metrics recorder** to deposit/redemption actions
3. **Implement phase tracking** in action execution
4. **Implement event monitoring** for E2E tracking
5. **Add tests** for metric recording
6. **Document** metric meanings and expected ranges

## Implementation Challenges

### Challenge 1: DepositsSwept Event Doesn't List Individual Deposits

The `DepositsSwept` event only contains `walletPubKeyHash` and `sweepTxHash`, not the individual deposits. To track E2E time for each deposit:

**Option A**: Query the sweep transaction to get included deposits
```go
// When DepositsSwept fires, query the Bitcoin transaction
sweepTx, err := btcChain.GetTransaction(event.SweepTxHash)
// Match inputs to tracked deposits
```

**Option B**: Track deposits by wallet and assume all pending deposits were swept
- Less accurate but simpler
- Works if deposits are swept in order

**Option C**: Track at proposal creation time
- When deposit sweep proposal is created, record which deposits are included
- Match to DepositsSwept event by wallet PKH

### Challenge 2: RedemptionsCompleted Event Doesn't List Individual Redemptions

Similar issue - need to match by wallet PKH and potentially query the redemption transaction.

**Solution**: Track redemptions by `redemptionKey` (wallet PKH + output script) when requested, then match on completion.

## Notes

- Metrics are optional and only recorded if `PerformanceMetrics` is enabled
- Use histograms for duration metrics to enable percentile calculations
- Consider adding labels for wallet PKH, deposit/redemption keys for filtering
- Clean up tracking maps periodically to prevent memory leaks
- Consider adding metric for failed operations (timeout, error, etc.)
- For accurate E2E times, use block timestamps rather than `time.Now()` to account for chain reorgs
- Consider TTL for tracking maps to handle edge cases where events are missed


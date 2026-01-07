# Redemption-Specific Metrics Implementation Guide

This document outlines the **redemption-specific** metrics that should be implemented to measure redemption performance, organized by where they should be added in the codebase.

## Why Redemption-Specific Metrics?

Currently, redemptions are tracked only as part of generic `wallet_action_*` metrics, which don't distinguish between:
- Redemptions
- Deposit sweeps
- Moving funds
- Moved funds sweeps
- Heartbeats

**Redemption-specific metrics** allow you to:
1. Track redemption performance independently
2. Identify redemption-specific bottlenecks
3. Set redemption-specific alerts
4. Compare redemption performance across different periods

## Core Redemption Metrics (Priority 1)

### 1. Action-Level Metrics
**Location**: `pkg/tbtc/wallet.go` - `walletDispatcher.dispatch()`

```go
// When action is dispatched
if action.actionType() == ActionRedemption {
    metricsRecorder.IncrementCounter("redemption_actions_started_total", 1)
    metricsRecorder.SetGauge("redemption_active_count", 
        float64(len(wd.actions))) // count active redemptions
}

// On success
if action.actionType() == ActionRedemption {
    metricsRecorder.IncrementCounter("redemption_actions_success_total", 1)
    metricsRecorder.RecordDuration("redemption_duration_seconds", 
        time.Since(startTime))
}

// On failure
if action.actionType() == ActionRedemption {
    metricsRecorder.IncrementCounter("redemption_actions_failed_total", 1)
    metricsRecorder.RecordDuration("redemption_duration_seconds", 
        time.Since(startTime)) // record duration even on failure
}
```

**Metrics**:
- `redemption_actions_started_total` - Counter
- `redemption_actions_success_total` - Counter  
- `redemption_actions_failed_total` - Counter
- `redemption_duration_seconds` - Histogram
- `redemption_active_count` - Gauge

### 2. Step-Level Duration Metrics
**Location**: `pkg/tbtc/redemption.go` - `redemptionAction.execute()`

```go
func (ra *redemptionAction) execute() error {
    actionStartTime := time.Now()
    
    // VALIDATION STEP
    validateStartTime := time.Now()
    validatedRequests, err := ValidateRedemptionProposal(...)
    if ra.metricsRecorder != nil {
        validateDuration := time.Since(validateStartTime)
        ra.metricsRecorder.RecordDuration(
            "redemption_step_validation_duration_seconds",
            validateDuration,
        )
        if err != nil {
            ra.metricsRecorder.IncrementCounter(
                "redemption_step_validation_failed_total", 1)
        } else {
            ra.metricsRecorder.IncrementCounter(
                "redemption_step_validation_success_total", 1)
        }
    }
    if err != nil {
        return fmt.Errorf("validate proposal step failed: [%v]", err)
    }
    
    // ASSEMBLY STEP (unique to redemptions)
    assemblyStartTime := time.Now()
    unsignedRedemptionTx, err := assembleRedemptionTransaction(...)
    if ra.metricsRecorder != nil {
        ra.metricsRecorder.RecordDuration(
            "redemption_step_assembly_duration_seconds",
            time.Since(assemblyStartTime),
        )
    }
    if err != nil {
        return fmt.Errorf("error while assembling redemption transaction: [%v]", err)
    }
    
    // SIGNING STEP
    signStartTime := time.Now()
    redemptionTx, err := ra.transactionExecutor.signTransaction(...)
    if ra.metricsRecorder != nil {
        signDuration := time.Since(signStartTime)
        ra.metricsRecorder.RecordDuration(
            "redemption_step_signing_duration_seconds",
            signDuration,
        )
        if err != nil {
            ra.metricsRecorder.IncrementCounter(
                "redemption_step_signing_failed_total", 1)
            // Check if it's a timeout
            if strings.Contains(err.Error(), "timeout") {
                ra.metricsRecorder.IncrementCounter(
                    "redemption_step_signing_timeout_total", 1)
            }
        } else {
            ra.metricsRecorder.IncrementCounter(
                "redemption_step_signing_success_total", 1)
        }
    }
    if err != nil {
        return fmt.Errorf("sign transaction step failed: [%v]", err)
    }
    
    // BROADCAST STEP
    broadcastStartTime := time.Now()
    err = ra.transactionExecutor.broadcastTransaction(...)
    if ra.metricsRecorder != nil {
        broadcastDuration := time.Since(broadcastStartTime)
        ra.metricsRecorder.RecordDuration(
            "redemption_step_broadcast_duration_seconds",
            broadcastDuration,
        )
        if err != nil {
            ra.metricsRecorder.IncrementCounter(
                "redemption_step_broadcast_failed_total", 1)
        } else {
            ra.metricsRecorder.IncrementCounter(
                "redemption_step_broadcast_success_total", 1)
        }
    }
    if err != nil {
        return fmt.Errorf("broadcast transaction step failed: [%v]", err)
    }
    
    return nil
}
```

**Metrics**:
- `redemption_step_validation_duration_seconds` - Histogram
- `redemption_step_validation_success_total` - Counter
- `redemption_step_validation_failed_total` - Counter
- `redemption_step_assembly_duration_seconds` - Histogram (redemption-specific)
- `redemption_step_signing_duration_seconds` - Histogram
- `redemption_step_signing_success_total` - Counter
- `redemption_step_signing_failed_total` - Counter
- `redemption_step_signing_timeout_total` - Counter
- `redemption_step_broadcast_duration_seconds` - Histogram
- `redemption_step_broadcast_success_total` - Counter
- `redemption_step_broadcast_failed_total` - Counter

### 3. Bitcoin Network Metrics (Redemption-Specific)
**Location**: `pkg/tbtc/wallet.go` - `walletTransactionExecutor.broadcastTransaction()`

```go
func (wte *walletTransactionExecutor) broadcastTransaction(...) error {
    broadcastStartTime := time.Now()
    broadcastAttempt := 0
    
    for {
        broadcastAttempt++
        
        err := wte.btcChain.BroadcastTransaction(tx)
        if err == nil {
            // Success - record metrics
            if wte.metricsRecorder != nil {
                wte.metricsRecorder.RecordDuration(
                    "redemption_bitcoin_broadcast_duration_seconds",
                    time.Since(broadcastStartTime),
                )
                wte.metricsRecorder.IncrementCounter(
                    "redemption_bitcoin_broadcast_attempts_total",
                    float64(broadcastAttempt),
                )
            }
            break
        }
        
        // Record retry
        if wte.metricsRecorder != nil {
            wte.metricsRecorder.IncrementCounter(
                "redemption_bitcoin_broadcast_retries_total", 1)
        }
        
        // ... retry logic ...
    }
    
    return nil
}
```

**Metrics**:
- `redemption_bitcoin_broadcast_duration_seconds` - Histogram
- `redemption_bitcoin_broadcast_attempts_total` - Counter
- `redemption_bitcoin_broadcast_retries_total` - Counter
- `redemption_bitcoin_network_errors_total` - Counter

## Advanced Redemption Metrics (Priority 2)

### 4. Coordination Phase Metrics
**Location**: `pkg/tbtcpg/redemptions.go` - `RedemptionTask.Run()`

```go
func (rt *RedemptionTask) Run(request *tbtc.CoordinationProposalRequest) (...) {
    proposalStartTime := time.Now()
    
    // ... proposal creation logic ...
    
    proposal, hasProposal, err := rt.ProposeRedemption(...)
    
    if rt.metricsRecorder != nil && hasProposal {
        rt.metricsRecorder.RecordDuration(
            "redemption_proposal_creation_duration_seconds",
            time.Since(proposalStartTime),
        )
    }
    
    return proposal, hasProposal, err
}
```

**Metrics**:
- `redemption_proposal_creation_duration_seconds` - Histogram
- `redemption_request_to_proposal_duration_seconds` - Histogram (requires tracking from request event)

### 5. Error Classification
**Location**: Multiple locations - wherever errors occur

```go
// In redemptionAction.execute()
if err != nil {
    errorType := classifyRedemptionError(err)
    if ra.metricsRecorder != nil {
        ra.metricsRecorder.IncrementCounter(
            "redemption_errors_total",
            1,
            map[string]string{"error_type": errorType},
        )
    }
}

func classifyRedemptionError(err error) string {
    errStr := err.Error()
    switch {
    case strings.Contains(errStr, "validate proposal"):
        return "validation_failed"
    case strings.Contains(errStr, "sign transaction"):
        return "signing_failed"
    case strings.Contains(errStr, "timeout"):
        return "signing_timeout"
    case strings.Contains(errStr, "broadcast"):
        return "broadcast_failed"
    case strings.Contains(errStr, "bitcoin"):
        return "bitcoin_network_error"
    default:
        return "unknown"
    }
}
```

**Metrics**:
- `redemption_errors_total{error_type="validation_failed"}` - Counter
- `redemption_errors_total{error_type="signing_timeout"}` - Counter
- `redemption_errors_total{error_type="signing_failed"}` - Counter
- `redemption_errors_total{error_type="broadcast_failed"}` - Counter
- `redemption_errors_total{error_type="bitcoin_network_error"}` - Counter

### 6. Throughput Metrics
**Location**: `pkg/tbtc/wallet.go` - Calculate from counters

```go
// Calculate from existing counters (no new code needed)
// redemption_throughput_per_minute = rate(redemption_actions_success_total[1m]) * 60
```

**Metrics**:
- `redemption_throughput_per_minute` - Gauge (calculated)
- `redemption_throughput_per_hour` - Gauge (calculated)

## Summary: Redemption-Specific Metrics

### Essential Metrics (Implement First)
1. **Action-level**:
   - `redemption_actions_started_total`
   - `redemption_actions_success_total`
   - `redemption_actions_failed_total`
   - `redemption_duration_seconds`
   - `redemption_active_count`

2. **Step-level durations**:
   - `redemption_step_validation_duration_seconds`
   - `redemption_step_assembly_duration_seconds` (redemption-specific)
   - `redemption_step_signing_duration_seconds`
   - `redemption_step_broadcast_duration_seconds`

3. **Step-level success/failure**:
   - `redemption_step_validation_success_total` / `failed_total`
   - `redemption_step_signing_success_total` / `failed_total` / `timeout_total`
   - `redemption_step_broadcast_success_total` / `failed_total`

4. **Bitcoin network**:
   - `redemption_bitcoin_broadcast_duration_seconds`
   - `redemption_bitcoin_broadcast_attempts_total`
   - `redemption_bitcoin_broadcast_retries_total`

### Advanced Metrics (Implement Later)
5. **Coordination**:
   - `redemption_proposal_creation_duration_seconds`
   - `redemption_request_to_proposal_duration_seconds`

6. **Error classification**:
   - `redemption_errors_total{error_type="..."}`

7. **Throughput**:
   - `redemption_throughput_per_minute` (calculated)

## Key Differences from Generic Wallet Metrics

| Aspect | Generic Metrics | Redemption-Specific Metrics |
|--------|----------------|---------------------------|
| **Scope** | All wallet actions | Only redemptions |
| **Assembly Step** | Not tracked | `redemption_step_assembly_duration_seconds` |
| **Bitcoin Broadcast** | Generic | `redemption_bitcoin_*` metrics |
| **Error Types** | Generic failures | Redemption-specific error classification |
| **Throughput** | All actions | Redemption-only throughput |

## Implementation Checklist

- [ ] Add action-type check in `walletDispatcher.dispatch()`
- [ ] Add redemption-specific counters in wallet dispatcher
- [ ] Add step-level duration tracking in `redemptionAction.execute()`
- [ ] Add assembly step metrics (redemption-specific)
- [ ] Add Bitcoin broadcast metrics
- [ ] Add error classification
- [ ] Update metrics recorder interface if needed
- [ ] Add tests for metrics recording
- [ ] Update documentation

## See Also

- [Redemption Metrics Summary](./redemption-metrics-summary.md) - Complete list of all metrics
- [Redemption Metrics Proposal](./redemption-metrics-proposal.md) - Detailed implementation proposal
- [Measuring Redemption Speed](./measuring-redemption-speed.md) - User guide


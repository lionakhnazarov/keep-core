# Redemption Speed Metrics - Implementation Proposal

This document outlines the metrics that should be implemented to measure redemption speed comprehensively.

## Current Metrics Infrastructure

The codebase already has a metrics recording system:
- `IncrementCounter(name string, value float64)` - For counting events
- `SetGauge(name string, value float64)` - For current values
- `RecordDuration(name string, duration time.Duration)` - For timing measurements

Metrics are recorded through the `metricsRecorder` interface in various components.

## Current Redemption Metrics

Currently, redemptions are tracked as part of general wallet actions:

### Existing Metrics (from `wallet.go`)
- `wallet_actions_total` - Total wallet actions (includes redemptions)
- `wallet_action_duration_seconds` - Duration of wallet actions (includes redemptions)
- `wallet_action_success_total` - Successful wallet actions (includes redemptions)
- `wallet_action_failed_total` - Failed wallet actions (includes redemptions)
- `wallet_dispatcher_active_actions` - Currently active wallet actions

**Limitation**: These metrics don't distinguish between redemption and other wallet actions (deposit sweeps, moving funds, etc.).

## Proposed Redemption-Specific Metrics

### 1. High-Level Redemption Metrics

#### Counter Metrics
```go
// Total redemption actions started
"redemption_actions_started_total"

// Successful redemptions
"redemption_actions_success_total"

// Failed redemptions
"redemption_actions_failed_total"

// Redemptions rejected (wallet busy)
"redemption_actions_rejected_total"
```

#### Duration Metrics
```go
// Total redemption duration (from start to completion)
"redemption_duration_seconds"

// Time from request to proposal creation
"redemption_request_to_proposal_duration_seconds"

// Time from proposal to signing start
"redemption_proposal_to_signing_duration_seconds"
```

#### Gauge Metrics
```go
// Currently active redemptions
"redemption_active_count"

// Pending redemption requests
"redemption_pending_requests_count"
```

### 2. Step-Level Metrics (Per Phase)

#### Validation Phase
```go
// Validation duration
"redemption_step_validation_duration_seconds"

// Validation failures
"redemption_step_validation_failed_total"

// Validation successes
"redemption_step_validation_success_total"
```

#### Signing Phase
```go
// Signing duration
"redemption_step_signing_duration_seconds"

// Signing failures
"redemption_step_signing_failed_total"

// Signing timeouts
"redemption_step_signing_timeout_total"

// Signing successes
"redemption_step_signing_success_total"
```

#### Broadcast Phase
```go
// Broadcast duration
"redemption_step_broadcast_duration_seconds"

// Broadcast failures
"redemption_step_broadcast_failed_total"

// Broadcast retries
"redemption_step_broadcast_retries_total"

// Broadcast successes
"redemption_step_broadcast_success_total"
```

### 3. Bitcoin Network Metrics

```go
// Time from broadcast to Bitcoin confirmation
"redemption_bitcoin_confirmation_duration_seconds"

// Bitcoin transaction broadcast attempts
"redemption_bitcoin_broadcast_attempts_total"

// Bitcoin network errors
"redemption_bitcoin_network_errors_total"
```

### 4. Request-to-Completion Metrics

```go
// End-to-end time: from on-chain request to Bitcoin confirmation
"redemption_end_to_end_duration_seconds"

// Time from request to proposal (coordination phase)
"redemption_coordination_duration_seconds"

// Time from proposal acceptance to execution start
"redemption_proposal_acceptance_duration_seconds"
```

### 5. Error Classification Metrics

```go
// Errors by type
"redemption_errors_total" // with error_type label

// Common error types:
// - "validation_failed"
// - "signing_timeout"
// - "signing_failed"
// - "broadcast_failed"
// - "bitcoin_network_error"
// - "wallet_busy"
// - "proposal_expired"
```

## Implementation Locations

### 1. Wallet Dispatcher (`pkg/tbtc/wallet.go`)

**Current**: Records generic wallet action metrics
**Proposed**: Add action-type-specific metrics

```go
// In dispatch() function, after determining action type:
if wd.metricsRecorder != nil {
    actionType := action.actionType().String()
    wd.metricsRecorder.IncrementCounter(
        fmt.Sprintf("wallet_action_%s_started_total", strings.ToLower(actionType)),
        1,
    )
    
    // Record duration with action type label
    wd.metricsRecorder.RecordDuration(
        fmt.Sprintf("wallet_action_%s_duration_seconds", strings.ToLower(actionType)),
        time.Since(startTime),
    )
}
```

### 2. Redemption Action (`pkg/tbtc/redemption.go`)

**Current**: No step-level metrics
**Proposed**: Add metrics for each step

```go
// In execute() function:

// Validation step
validateStartTime := time.Now()
// ... validation logic ...
if wd.metricsRecorder != nil {
    wd.metricsRecorder.RecordDuration(
        "redemption_step_validation_duration_seconds",
        time.Since(validateStartTime),
    )
    if err != nil {
        wd.metricsRecorder.IncrementCounter(
            "redemption_step_validation_failed_total",
            1,
        )
    } else {
        wd.metricsRecorder.IncrementCounter(
            "redemption_step_validation_success_total",
            1,
        )
    }
}

// Signing step
signStartTime := time.Now()
// ... signing logic ...
if wd.metricsRecorder != nil {
    wd.metricsRecorder.RecordDuration(
        "redemption_step_signing_duration_seconds",
        time.Since(signStartTime),
    )
    // Similar success/failure tracking
}

// Broadcast step
broadcastStartTime := time.Now()
// ... broadcast logic ...
if wd.metricsRecorder != nil {
    wd.metricsRecorder.RecordDuration(
        "redemption_step_broadcast_duration_seconds",
        time.Since(broadcastStartTime),
    )
    // Similar success/failure tracking
}
```

### 3. Bitcoin Chain Integration (`pkg/bitcoin/`)

**Proposed**: Add metrics for Bitcoin operations

```go
// In BroadcastTransaction():
broadcastStartTime := time.Now()
attempts := 0
for {
    attempts++
    err := btcChain.BroadcastTransaction(tx)
    if err == nil {
        if metricsRecorder != nil {
            metricsRecorder.IncrementCounter(
                "redemption_bitcoin_broadcast_attempts_total",
                float64(attempts),
            )
            metricsRecorder.RecordDuration(
                "redemption_bitcoin_broadcast_duration_seconds",
                time.Since(broadcastStartTime),
            )
        }
        break
    }
    // Retry logic...
}
```

### 4. Coordination Layer (`pkg/tbtcpg/redemptions.go`)

**Proposed**: Track proposal creation timing

```go
// In Run() function:
proposalStartTime := time.Now()
proposal, hasProposal, err := rt.Run(request)
if metricsRecorder != nil && hasProposal {
    metricsRecorder.RecordDuration(
        "redemption_proposal_creation_duration_seconds",
        time.Since(proposalStartTime),
    )
}
```

## Metric Labels (Tags)

For better filtering and aggregation, add labels:

```go
// Example with labels:
metricsRecorder.RecordDurationWithLabels(
    "redemption_duration_seconds",
    duration,
    map[string]string{
        "wallet_pkh": hex.EncodeToString(walletPKH[:]),
        "step": "validation",
    },
)
```

**Useful Labels:**
- `action_type` - "redemption", "deposit_sweep", etc.
- `step` - "validation", "signing", "broadcast"
- `wallet_pkh` - Wallet public key hash (optional, for debugging)
- `error_type` - Error classification
- `threshold_group_size` - Size of threshold signing group

## Prometheus Query Examples

Once implemented, these metrics enable powerful queries:

```promql
# Average redemption duration
rate(redemption_duration_seconds_sum[5m]) / rate(redemption_duration_seconds_count[5m])

# Redemption success rate
rate(redemption_actions_success_total[5m]) / 
  (rate(redemption_actions_success_total[5m]) + rate(redemption_actions_failed_total[5m]))

# Step breakdown
rate(redemption_step_validation_duration_seconds_sum[5m]) / 
  rate(redemption_step_validation_duration_seconds_count[5m])

# Error rate by type
rate(redemption_errors_total{error_type="signing_timeout"}[5m])

# P95 redemption duration
histogram_quantile(0.95, rate(redemption_duration_seconds_bucket[5m]))
```

## Implementation Priority

### Phase 1 (High Priority)
1. Action-type-specific metrics in wallet dispatcher
2. Step-level duration metrics (validation, signing, broadcast)
3. Success/failure counters per step

### Phase 2 (Medium Priority)
4. Bitcoin network metrics
5. Error classification metrics
6. Request-to-proposal timing

### Phase 3 (Nice to Have)
7. End-to-end timing (requires tracking from request event)
8. Detailed labels for filtering
9. Histogram buckets for percentile analysis

## Benefits

1. **Performance Monitoring**: Identify bottlenecks in redemption flow
2. **Alerting**: Set up alerts for slow or failing redemptions
3. **Debugging**: Quickly identify which step is causing issues
4. **Capacity Planning**: Understand redemption throughput
5. **User Experience**: Track end-to-end redemption times

## See Also

- [Measuring Redemption Speed](./measuring-redemption-speed.md) - User guide
- [Measuring Node Performance](./measuring-node-performance.md) - General metrics guide


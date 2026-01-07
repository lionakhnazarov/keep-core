# Redemption Speed Metrics - Summary

This document provides a quick reference of all metrics that could be implemented to measure redemption speed.

## Metrics Categories

### 1. High-Level Redemption Metrics

| Metric Name | Type | Description |
|------------|------|-------------|
| `redemption_actions_started_total` | Counter | Total redemption actions initiated |
| `redemption_actions_success_total` | Counter | Successful redemptions completed |
| `redemption_actions_failed_total` | Counter | Failed redemption attempts |
| `redemption_actions_rejected_total` | Counter | Redemptions rejected (wallet busy) |
| `redemption_duration_seconds` | Histogram | Total redemption duration (start to completion) |
| `redemption_active_count` | Gauge | Currently active redemptions |
| `redemption_pending_requests_count` | Gauge | Pending redemption requests waiting |

### 2. Step-Level Duration Metrics

| Metric Name | Type | Description |
|------------|------|-------------|
| `redemption_step_validation_duration_seconds` | Histogram | Time spent validating proposal |
| `redemption_step_signing_duration_seconds` | Histogram | Time spent signing transaction |
| `redemption_step_broadcast_duration_seconds` | Histogram | Time spent broadcasting transaction |
| `redemption_step_assembly_duration_seconds` | Histogram | Time spent assembling transaction |

### 3. Step-Level Success/Failure Metrics

| Metric Name | Type | Description |
|------------|------|-------------|
| `redemption_step_validation_success_total` | Counter | Successful validations |
| `redemption_step_validation_failed_total` | Counter | Failed validations |
| `redemption_step_signing_success_total` | Counter | Successful signings |
| `redemption_step_signing_failed_total` | Counter | Failed signings |
| `redemption_step_signing_timeout_total` | Counter | Signing timeouts |
| `redemption_step_broadcast_success_total` | Counter | Successful broadcasts |
| `redemption_step_broadcast_failed_total` | Counter | Failed broadcasts |
| `redemption_step_broadcast_retries_total` | Counter | Broadcast retry attempts |

### 4. Coordination Phase Metrics

| Metric Name | Type | Description |
|------------|------|-------------|
| `redemption_request_to_proposal_duration_seconds` | Histogram | Time from request to proposal creation |
| `redemption_proposal_creation_duration_seconds` | Histogram | Time to create redemption proposal |
| `redemption_proposal_acceptance_duration_seconds` | Histogram | Time from proposal to execution start |
| `redemption_coordination_duration_seconds` | Histogram | Total coordination phase duration |

### 5. Bitcoin Network Metrics

| Metric Name | Type | Description |
|------------|------|-------------|
| `redemption_bitcoin_broadcast_duration_seconds` | Histogram | Time to broadcast to Bitcoin network |
| `redemption_bitcoin_broadcast_attempts_total` | Counter | Bitcoin broadcast attempts |
| `redemption_bitcoin_confirmation_duration_seconds` | Histogram | Time from broadcast to confirmation |
| `redemption_bitcoin_network_errors_total` | Counter | Bitcoin network errors |
| `redemption_bitcoin_mempool_delay_seconds` | Histogram | Time transaction spends in mempool |

### 6. End-to-End Metrics

| Metric Name | Type | Description |
|------------|------|-------------|
| `redemption_end_to_end_duration_seconds` | Histogram | Request submission to Bitcoin confirmation |
| `redemption_user_experience_duration_seconds` | Histogram | User-visible redemption time |

### 7. Error Classification Metrics

| Metric Name | Type | Description |
|------------|------|-------------|
| `redemption_errors_total` | Counter | Total errors (with `error_type` label) |
| `redemption_errors_total{error_type="validation_failed"}` | Counter | Validation errors |
| `redemption_errors_total{error_type="signing_timeout"}` | Counter | Signing timeout errors |
| `redemption_errors_total{error_type="signing_failed"}` | Counter | Signing failure errors |
| `redemption_errors_total{error_type="broadcast_failed"}` | Counter | Broadcast errors |
| `redemption_errors_total{error_type="bitcoin_network_error"}` | Counter | Bitcoin network errors |
| `redemption_errors_total{error_type="wallet_busy"}` | Counter | Wallet busy errors |
| `redemption_errors_total{error_type="proposal_expired"}` | Counter | Proposal expiry errors |

### 8. Throughput Metrics

| Metric Name | Type | Description |
|------------|------|-------------|
| `redemption_throughput_per_minute` | Gauge | Redemptions completed per minute |
| `redemption_throughput_per_hour` | Gauge | Redemptions completed per hour |
| `redemption_queue_depth` | Gauge | Number of redemptions in queue |

### 9. Resource Utilization Metrics

| Metric Name | Type | Description |
|------------|------|-------------|
| `redemption_wallet_utilization` | Gauge | Percentage of time wallet is processing redemptions |
| `redemption_concurrent_limit` | Gauge | Maximum concurrent redemptions |
| `redemption_concurrent_active` | Gauge | Currently concurrent redemptions |

## Metric Labels (Tags)

Recommended labels for filtering and aggregation:

- `action_type` - "redemption", "deposit_sweep", etc.
- `step` - "validation", "signing", "broadcast", "assembly"
- `wallet_pkh` - Wallet public key hash (optional, for debugging)
- `error_type` - Error classification
- `threshold_group_size` - Size of threshold signing group
- `redemption_size` - Number of redemption requests in batch
- `network` - "mainnet", "testnet", "regtest"

## Implementation Priority

### 🔴 Critical (Phase 1)
1. `redemption_actions_started_total`
2. `redemption_actions_success_total`
3. `redemption_actions_failed_total`
4. `redemption_duration_seconds`
5. `redemption_step_validation_duration_seconds`
6. `redemption_step_signing_duration_seconds`
7. `redemption_step_broadcast_duration_seconds`

### 🟡 Important (Phase 2)
8. `redemption_step_*_success_total` / `*_failed_total`
9. `redemption_bitcoin_broadcast_duration_seconds`
10. `redemption_bitcoin_broadcast_attempts_total`
11. `redemption_errors_total` (with error_type label)
12. `redemption_active_count`

### 🟢 Nice to Have (Phase 3)
13. `redemption_request_to_proposal_duration_seconds`
14. `redemption_end_to_end_duration_seconds`
15. `redemption_bitcoin_confirmation_duration_seconds`
16. `redemption_throughput_per_minute`
17. Detailed labels for all metrics

## Example Prometheus Queries

```promql
# Average redemption duration
rate(redemption_duration_seconds_sum[5m]) / 
  rate(redemption_duration_seconds_count[5m])

# Redemption success rate
rate(redemption_actions_success_total[5m]) / 
  (rate(redemption_actions_success_total[5m]) + 
   rate(redemption_actions_failed_total[5m]))

# Step breakdown (validation)
rate(redemption_step_validation_duration_seconds_sum[5m]) / 
  rate(redemption_step_validation_duration_seconds_count[5m])

# Step breakdown (signing)
rate(redemption_step_signing_duration_seconds_sum[5m]) / 
  rate(redemption_step_signing_duration_seconds_count[5m])

# Step breakdown (broadcast)
rate(redemption_step_broadcast_duration_seconds_sum[5m]) / 
  rate(redemption_step_broadcast_duration_seconds_count[5m])

# P95 redemption duration
histogram_quantile(0.95, 
  rate(redemption_duration_seconds_bucket[5m]))

# Error rate by type
rate(redemption_errors_total{error_type="signing_timeout"}[5m])

# Throughput
rate(redemption_actions_success_total[1m]) * 60

# Active redemptions
redemption_active_count
```

## Current Status

**Currently Implemented:**
- Generic wallet action metrics (includes redemptions but not specific)
- Signing metrics (used by redemptions but not redemption-specific)

**Not Yet Implemented:**
- All redemption-specific metrics listed above
- Step-level duration tracking for redemptions
- Error classification for redemptions
- Bitcoin network metrics for redemptions

## See Also

- [Redemption Metrics Proposal](./redemption-metrics-proposal.md) - Detailed implementation proposal
- [Measuring Redemption Speed](./measuring-redemption-speed.md) - User guide for measuring redemptions
- [Measuring Node Performance](./measuring-node-performance.md) - General performance metrics guide


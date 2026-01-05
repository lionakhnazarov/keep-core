# Redemption Process Telemetry Metrics

## Overview

The redemption process involves multiple phases: proposal creation, execution, and proof submission. This document describes the implemented redemption-specific metrics that provide visibility into redemption performance and bottlenecks.

## Implemented Metrics

### 1. Redemption Execution Metrics

**Location**: `pkg/tbtc/redemption.go` (`redemptionAction.execute()`)

#### Counters:
- `performance_redemption_executions_total` - Total number of redemption executions attempted
- `performance_redemption_executions_success_total` - Total number of successful redemption executions
- `performance_redemption_executions_failed_total` - Total number of failed redemption executions

#### Duration Metrics:
- `performance_redemption_execution_duration_seconds` - Total redemption execution time (from start to completion)
- `performance_redemption_tx_signing_duration_seconds` - Transaction signing time (critical step performance)

**Use Cases:**
- Track redemption execution success rate
- Measure total execution time
- Monitor transaction signing performance
- Detect slow redemption executions

**Implementation Details:**
- Execution metrics are recorded at the start and end of `redemptionAction.execute()`
- Signing duration is tracked separately for the transaction signing step
- Failures are recorded at each error point (validation, UTXO determination, sync, assembly, signing, broadcast)

---

### 2. Redemption Proof Submission Metrics

**Location**: `pkg/maintainer/spv/redemptions.go` (`submitRedemptionProof()`)

#### Counters:
- `performance_redemption_proof_submissions_total` - Total number of redemption proof submission attempts
- `performance_redemption_proof_submissions_success_total` - Total number of successful proof submissions
- `performance_redemption_proof_submissions_failed_total` - Total number of failed proof submissions

**Use Cases:**
- Track proof submission success rate
- Monitor proof submission health
- Detect proof submission issues

**Implementation Details:**
- Metrics are recorded in `submitRedemptionProof()` function
- Success is recorded after successful submission to the chain
- Failures are recorded for various failure points (invalid confirmations, proof assembly, transaction parsing, submission errors)
- **Note**: Metrics recorder must be wired via `spv.SetMetricsRecorder()` when initializing the SPV maintainer

---

### 3. Pending Redemption Requests Count

**Location**: `pkg/tbtcpg/redemptions.go` (`RedemptionTask.FindPendingRedemptions()`)

#### Gauges:
- `performance_redemption_pending_requests_count` - Current number of pending redemption requests (per wallet)

**Use Cases:**
- Monitor pending redemption backlog
- Track redemption request queue size
- Identify wallets with high redemption demand

**Implementation Details:**
- Gauge is updated each time `FindPendingRedemptions()` is called
- Value represents the current count of pending redemption requests for the wallet being processed
- Metrics recorder is wired through `ProposalGenerator.SetRedemptionMetricsRecorder()`

---

## Implementation Locations

### 1. Execution Metrics (`pkg/tbtc/redemption.go`)

```go
// In redemptionAction.execute()
executionStartTime := time.Now()
metricsRecorder.IncrementCounter("redemption_executions_total", 1)

// ... execution steps ...

// On success:
metricsRecorder.IncrementCounter("redemption_executions_success_total", 1)
metricsRecorder.RecordDuration("redemption_execution_duration_seconds", time.Since(executionStartTime))

// On failure:
metricsRecorder.IncrementCounter("redemption_executions_failed_total", 1)
metricsRecorder.RecordDuration("redemption_execution_duration_seconds", time.Since(executionStartTime))

// Transaction signing duration:
signingStartTime := time.Now()
// ... signing ...
metricsRecorder.RecordDuration("redemption_tx_signing_duration_seconds", time.Since(signingStartTime))
```

### 2. Proof Submission Metrics (`pkg/maintainer/spv/redemptions.go`)

```go
// In submitRedemptionProof()
metricsRecorder.IncrementCounter("redemption_proof_submissions_total", 1)

// On success:
metricsRecorder.IncrementCounter("redemption_proof_submissions_success_total", 1)

// On failure:
metricsRecorder.IncrementCounter("redemption_proof_submissions_failed_total", 1)
```

### 3. Pending Requests Count (`pkg/tbtcpg/redemptions.go`)

```go
// In FindPendingRedemptions()
metricsRecorder.SetGauge("redemption_pending_requests_count", float64(len(pendingRedemptions)))
```

---

## Key Performance Indicators (KPIs)

### Redemption Success Rates
- **Execution success rate**: `rate(performance_redemption_executions_success_total[5m]) / rate(performance_redemption_executions_total[5m])`
- **Proof submission success rate**: `rate(performance_redemption_proof_submissions_success_total[5m]) / rate(performance_redemption_proof_submissions_total[5m])`

### Redemption Performance
- **Average execution time**: `performance_redemption_execution_duration_seconds`
- **Average signing time**: `performance_redemption_tx_signing_duration_seconds`

### Redemption Health
- **Pending requests backlog**: `performance_redemption_pending_requests_count`
- **Execution throughput**: `rate(performance_redemption_executions_success_total[1h])`

---

## Alert Thresholds

### Critical Alerts
1. **Redemption execution failure rate > 10%**
   - Formula: `rate(performance_redemption_executions_failed_total[5m]) / rate(performance_redemption_executions_total[5m]) > 0.1`

2. **Redemption proof submission failure rate > 10%**
   - Formula: `rate(performance_redemption_proof_submissions_failed_total[5m]) / rate(performance_redemption_proof_submissions_total[5m]) > 0.1`

### Warning Alerts
1. **Redemption execution duration > 5 minutes**
   - Formula: `performance_redemption_execution_duration_seconds > 300`

2. **Transaction signing duration > 2 minutes**
   - Formula: `performance_redemption_tx_signing_duration_seconds > 120`

3. **Pending redemption requests > 100**
   - Formula: `sum(performance_redemption_pending_requests_count) > 100`

---

## Example Prometheus Queries

### Redemption Success Rates
```promql
# Execution success rate
rate(performance_redemption_executions_success_total[5m]) / 
rate(performance_redemption_executions_total[5m])

# Proof submission success rate
rate(performance_redemption_proof_submissions_success_total[5m]) / 
rate(performance_redemption_proof_submissions_total[5m])
```

### Redemption Performance
```promql
# Average redemption execution time
performance_redemption_execution_duration_seconds

# Average transaction signing time
performance_redemption_tx_signing_duration_seconds

# 95th percentile execution time
histogram_quantile(0.95, 
  rate(performance_redemption_execution_duration_seconds_bucket[5m])
)
```

### Redemption Throughput
```promql
# Redemption executions per hour
rate(performance_redemption_executions_success_total[1h]) * 3600

# Redemption proof submissions per hour
rate(performance_redemption_proof_submissions_success_total[1h]) * 3600
```

### Redemption Backlog
```promql
# Total pending redemption requests
sum(performance_redemption_pending_requests_count)

# Pending requests per wallet
performance_redemption_pending_requests_count
```

### Failure Analysis
```promql
# Execution failure rate
rate(performance_redemption_executions_failed_total[5m]) / 
rate(performance_redemption_executions_total[5m])

# Proof submission failure rate
rate(performance_redemption_proof_submissions_failed_total[5m]) / 
rate(performance_redemption_proof_submissions_total[5m])
```

---

## Benefits

1. **Execution Visibility**: Track redemption execution success rates and performance
2. **Bottleneck Identification**: Identify slow steps (especially signing) in the redemption process
3. **Failure Analysis**: Understand redemption execution and proof submission failures
4. **Performance Optimization**: Measure impact of optimizations on execution and signing times
5. **Capacity Planning**: Monitor redemption throughput and backlog
6. **Health Monitoring**: Track redemption system health through success rates and backlogs

---

## Summary

These implemented metrics provide visibility into the redemption process, enabling:
- **Proactive monitoring** of redemption execution and proof submission health
- **Performance optimization** through bottleneck identification (especially signing duration)
- **Capacity planning** based on throughput trends and backlog monitoring
- **Root cause analysis** of redemption execution and proof submission failures
- **Health tracking** through success rates and pending request counts

**Total implemented metrics: 5 redemption-specific metrics** covering execution, signing performance, proof submission, and pending request backlog.

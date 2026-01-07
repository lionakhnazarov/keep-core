# Measuring Node Performance for DKG, Deposits, and Redemptions

This guide explains how to measure and monitor node performance for DKG (Distributed Key Generation), deposits, and redemptions in Keep Core.

## Overview

Keep Core nodes expose performance metrics through:
1. **HTTP Metrics Endpoint** (`/metrics`) - Prometheus-compatible metrics
2. **Logs** - Structured logging with timestamps
3. **Diagnostics Endpoint** (`/diagnostics`) - Node status and health

## Metrics Endpoint

The metrics endpoint is available at `http://localhost:<port>/metrics` where `<port>` is configured in your `config.toml` under the `Metrics` section (default: `9601`).

### Available Performance Metrics

#### DKG Metrics

```bash
# DKG operation counts
curl -s http://localhost:9601/metrics | grep performance_dkg

# Available DKG metrics:
# - performance_dkg_requested_total - Number of DKG requests
# - performance_dkg_joined_total - Number of times node joined DKG
# - performance_dkg_failed_total - Number of failed DKG attempts
# - performance_dkg_validation_total - Number of DKG validations performed
# - performance_dkg_challenges_submitted_total - Number of challenges submitted
# - performance_dkg_approvals_submitted_total - Number of approvals submitted
# - performance_dkg_duration_seconds - Average DKG duration (seconds)
# - performance_dkg_duration_seconds_count - Total number of DKG operations
```

#### Wallet Action Metrics (Deposits & Redemptions)

```bash
# Wallet action metrics (includes deposit sweeps and redemptions)
curl -s http://localhost:9601/metrics | grep performance_wallet_action

# Available wallet action metrics:
# - performance_wallet_actions_total - Total wallet actions executed
# - performance_wallet_action_success_total - Successful wallet actions
# - performance_wallet_action_failed_total - Failed wallet actions
# - performance_wallet_action_duration_seconds - Average wallet action duration
# - performance_wallet_action_duration_seconds_count - Total wallet actions
```

#### Signing Metrics (Used in Deposits & Redemptions)

```bash
# Signing operation metrics
curl -s http://localhost:9601/metrics | grep performance_signing

# Available signing metrics:
# - performance_signing_operations_total - Total signing operations
# - performance_signing_success_total - Successful signings
# - performance_signing_failed_total - Failed signings
# - performance_signing_timeouts_total - Signing timeouts
# - performance_signing_duration_seconds - Average signing duration
# - performance_signing_duration_seconds_count - Total signing operations
```

## Measuring DKG Performance

### 1. Monitor DKG Duration

DKG duration measures the time from when a node joins a DKG until it completes (successfully or with failure).

```bash
# Get average DKG duration
curl -s http://localhost:9601/metrics | grep performance_dkg_duration_seconds | grep -v count

# Get total DKG count
curl -s http://localhost:9601/metrics | grep performance_dkg_duration_seconds_count

# Calculate success rate
DKG_TOTAL=$(curl -s http://localhost:9601/metrics | grep performance_dkg_joined_total | awk '{print $2}')
DKG_FAILED=$(curl -s http://localhost:9601/metrics | grep performance_dkg_failed_total | awk '{print $2}')
if [ "$DKG_TOTAL" -gt 0 ]; then
  SUCCESS_RATE=$(echo "scale=2; ($DKG_TOTAL - $DKG_FAILED) * 100 / $DKG_TOTAL" | bc)
  echo "DKG Success Rate: ${SUCCESS_RATE}%"
fi
```

### 2. Monitor DKG Stages in Logs

DKG goes through multiple stages. Monitor stage transitions with timestamps:

```bash
# Watch DKG state transitions
tail -f logs/node1.log | grep -E "DKG started|transitioning to|transitioned to" | grep -i dkg

# Extract DKG timing from logs
grep "DKG started" logs/node1.log | tail -5
grep "transitioned to new state" logs/node1.log | grep dkg | tail -10
```

**Key log patterns:**
- `DKG started with seed [0x...]` - DKG initiation
- `transitioning to a new state` - State change start
- `transitioned to new state` - State change complete
- `member [X,state:*dkg.*State]` - Shows which DKG stage

### 3. Track DKG Participation Rate

```bash
# Check how often your node participates in DKG
DKG_REQUESTED=$(curl -s http://localhost:9601/metrics | grep performance_dkg_requested_total | awk '{print $2}')
DKG_JOINED=$(curl -s http://localhost:9601/metrics | grep performance_dkg_joined_total | awk '{print $2}')

if [ "$DKG_REQUESTED" -gt 0 ]; then
  PARTICIPATION_RATE=$(echo "scale=2; $DKG_JOINED * 100 / $DKG_REQUESTED" | bc)
  echo "DKG Participation Rate: ${PARTICIPATION_RATE}%"
fi
```

## Measuring Deposit Performance

### 1. Monitor Deposit Sweep Duration

Deposit sweeps are tracked as wallet actions. The duration includes:
- Proposal validation
- Transaction signing
- Bitcoin transaction broadcast
- Confirmation waiting

```bash
# Get average deposit sweep duration
curl -s http://localhost:9601/metrics | grep performance_wallet_action_duration_seconds | grep -v count

# Get deposit sweep counts
curl -s http://localhost:9601/metrics | grep performance_wallet_action
```

### 2. Monitor Deposit Sweep Stages in Logs

```bash
# Watch deposit sweep execution
tail -f logs/node1.log | grep -i "deposit\|sweep" | grep -E "step|executing|completed|failed"

# Key log patterns for deposit sweeps:
# - "starting orchestration of the deposit sweep action" - Start
# - "step.*validateProposal" - Validation phase
# - "step.*signTransaction" - Signing phase
# - "step.*broadcastTransaction" - Broadcast phase
# - "wallet action dispatched successfully" - Success
```

### 3. Track Deposit Sweep Success Rate

```bash
# Calculate deposit sweep success rate
WALLET_ACTIONS_TOTAL=$(curl -s http://localhost:9601/metrics | grep performance_wallet_actions_total | awk '{print $2}')
WALLET_ACTIONS_FAILED=$(curl -s http://localhost:9601/metrics | grep performance_wallet_action_failed_total | awk '{print $2}')

if [ "$WALLET_ACTIONS_TOTAL" -gt 0 ]; then
  SUCCESS_RATE=$(echo "scale=2; ($WALLET_ACTIONS_TOTAL - $WALLET_ACTIONS_FAILED) * 100 / $WALLET_ACTIONS_TOTAL" | bc)
  echo "Deposit Sweep Success Rate: ${SUCCESS_RATE}%"
fi
```

### 4. Measure Deposit Processing Time

From logs, you can measure the time from deposit reveal to sweep completion:

```bash
# Extract deposit reveal events (from chain events)
# Then track when they get swept

# Example: Find deposit reveals in recent blocks
BRIDGE="0x8aca8D4Ad7b4f2768d1c13018712Da6E3887a79f"
FROM_BLOCK=$(cast block-number --rpc-url http://localhost:8545 | cast --to-dec)
FROM_BLOCK=$((FROM_BLOCK - 100))

cast logs --from-block $FROM_BLOCK --to-block latest \
  --address $BRIDGE \
  "DepositRevealed(bytes32,bytes32,address,uint256,bytes20,bytes20,uint32,bytes32)" \
  --rpc-url http://localhost:8545
```

## Measuring Redemption Performance

### 1. Monitor Redemption Duration

Redemptions are also tracked as wallet actions:

```bash
# Get average redemption duration
curl -s http://localhost:9601/metrics | grep performance_wallet_action_duration_seconds | grep -v count

# Note: This includes all wallet actions (deposits, redemptions, heartbeats)
# To filter specifically for redemptions, check logs
```

### 2. Monitor Redemption Stages in Logs

```bash
# Watch redemption execution
tail -f logs/node1.log | grep -i "redemption\|redeem" | grep -E "step|executing|completed|failed"

# Key log patterns for redemptions:
# - "starting orchestration of the redemption action" - Start
# - "step.*validateProposal" - Validation phase
# - "step.*signTransaction" - Signing phase
# - "step.*broadcastTransaction" - Broadcast phase
```

### 3. Track Redemption Success Rate

Redemptions share the same wallet action metrics as deposits. To distinguish them:

```bash
# Count redemption-specific log entries
REDEMPTION_STARTED=$(grep -c "redemption action" logs/node1.log)
REDEMPTION_FAILED=$(grep -c "redemption.*failed" logs/node1.log)

if [ "$REDEMPTION_STARTED" -gt 0 ]; then
  SUCCESS_RATE=$(echo "scale=2; ($REDEMPTION_STARTED - $REDEMPTION_FAILED) * 100 / $REDEMPTION_STARTED" | bc)
  echo "Redemption Success Rate: ${SUCCESS_RATE}%"
fi
```

## Comprehensive Performance Monitoring Script

Create a script to monitor all performance metrics:

```bash
#!/bin/bash
# scripts/monitor-performance.sh

METRICS_URL="http://localhost:9601/metrics"

echo "=== Keep Node Performance Metrics ==="
echo "Timestamp: $(date)"
echo ""

echo "--- DKG Metrics ---"
DKG_REQUESTED=$(curl -s $METRICS_URL | grep performance_dkg_requested_total | awk '{print $2}')
DKG_JOINED=$(curl -s $METRICS_URL | grep performance_dkg_joined_total | awk '{print $2}')
DKG_FAILED=$(curl -s $METRICS_URL | grep performance_dkg_failed_total | awk '{print $2}')
DKG_DURATION=$(curl -s $METRICS_URL | grep '^performance_dkg_duration_seconds ' | awk '{print $2}')

echo "DKG Requested: ${DKG_REQUESTED:-0}"
echo "DKG Joined: ${DKG_JOINED:-0}"
echo "DKG Failed: ${DKG_FAILED:-0}"
if [ -n "$DKG_DURATION" ]; then
  echo "Avg DKG Duration: ${DKG_DURATION}s"
fi

if [ "$DKG_JOINED" -gt 0 ] && [ -n "$DKG_FAILED" ]; then
  SUCCESS_RATE=$(echo "scale=2; ($DKG_JOINED - $DKG_FAILED) * 100 / $DKG_JOINED" | bc)
  echo "DKG Success Rate: ${SUCCESS_RATE}%"
fi

echo ""
echo "--- Wallet Action Metrics (Deposits & Redemptions) ---"
WALLET_ACTIONS=$(curl -s $METRICS_URL | grep performance_wallet_actions_total | awk '{print $2}')
WALLET_SUCCESS=$(curl -s $METRICS_URL | grep performance_wallet_action_success_total | awk '{print $2}')
WALLET_FAILED=$(curl -s $METRICS_URL | grep performance_wallet_action_failed_total | awk '{print $2}')
WALLET_DURATION=$(curl -s $METRICS_URL | grep '^performance_wallet_action_duration_seconds ' | awk '{print $2}')

echo "Total Wallet Actions: ${WALLET_ACTIONS:-0}"
echo "Successful: ${WALLET_SUCCESS:-0}"
echo "Failed: ${WALLET_FAILED:-0}"
if [ -n "$WALLET_DURATION" ]; then
  echo "Avg Duration: ${WALLET_DURATION}s"
fi

if [ "$WALLET_ACTIONS" -gt 0 ] && [ -n "$WALLET_FAILED" ]; then
  SUCCESS_RATE=$(echo "scale=2; ($WALLET_ACTIONS - $WALLET_FAILED) * 100 / $WALLET_ACTIONS" | bc)
  echo "Success Rate: ${SUCCESS_RATE}%"
fi

echo ""
echo "--- Signing Metrics ---"
SIGNING_OPS=$(curl -s $METRICS_URL | grep performance_signing_operations_total | awk '{print $2}')
SIGNING_SUCCESS=$(curl -s $METRICS_URL | grep performance_signing_success_total | awk '{print $2}')
SIGNING_FAILED=$(curl -s $METRICS_URL | grep performance_signing_failed_total | awk '{print $2}')
SIGNING_DURATION=$(curl -s $METRICS_URL | grep '^performance_signing_duration_seconds ' | awk '{print $2}')

echo "Total Signing Operations: ${SIGNING_OPS:-0}"
echo "Successful: ${SIGNING_SUCCESS:-0}"
echo "Failed: ${SIGNING_FAILED:-0}"
if [ -n "$SIGNING_DURATION" ]; then
  echo "Avg Duration: ${SIGNING_DURATION}s"
fi

echo ""
echo "--- Network Health ---"
PEERS=$(curl -s http://localhost:9601/diagnostics | jq -r '.connected_peers | length')
echo "Connected Peers: ${PEERS:-0}"
```

## Using Prometheus for Long-term Monitoring

For production environments, set up Prometheus to scrape metrics:

### Prometheus Configuration

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'keep-node'
    static_configs:
      - targets: ['localhost:9601']
    metrics_path: '/metrics'
    scrape_interval: 15s
```

### Example Prometheus Queries

```promql
# DKG success rate over time
rate(performance_dkg_joined_total[5m]) - rate(performance_dkg_failed_total[5m])

# Average DKG duration over last hour
avg_over_time(performance_dkg_duration_seconds[1h])

# Wallet action success rate
rate(performance_wallet_action_success_total[5m]) / rate(performance_wallet_actions_total[5m])

# Deposit sweep throughput (actions per minute)
rate(performance_wallet_actions_total[1m]) * 60

# Signing operation latency (p95)
histogram_quantile(0.95, rate(performance_signing_duration_seconds_bucket[5m]))
```

## Performance Benchmarks

### Expected Performance Ranges

**DKG:**
- Duration: 2-5 minutes (depending on network conditions)
- Success Rate: >95% (for healthy nodes)
- Participation Rate: Should match operator's stake proportion

**Deposit Sweeps:**
- Duration: 5-15 minutes (includes Bitcoin confirmation)
- Success Rate: >98%
- Typical flow: Reveal → Wait for confirmations → Sign → Broadcast → Confirm

**Redemptions:**
- Duration: 5-15 minutes (includes Bitcoin confirmation)
- Success Rate: >98%
- Typical flow: Request → Sign → Broadcast → Confirm

## Troubleshooting Performance Issues

### High DKG Failure Rate

```bash
# Check for common issues:
# 1. Network connectivity
curl -s http://localhost:9601/diagnostics | jq '.connected_peers | length'

# 2. Check logs for errors
grep -i "error\|failed\|timeout" logs/node1.log | grep -i dkg | tail -20

# 3. Check ETH balance (needed for transactions)
cast balance <OPERATOR_ADDRESS> --rpc-url http://localhost:8545
```

### Slow Deposit/Redemption Processing

```bash
# Check signing performance
curl -s http://localhost:9601/metrics | grep performance_signing_duration_seconds

# Check for signing timeouts
grep -c "signing.*timeout" logs/node1.log

# Check Bitcoin connectivity
curl -s http://localhost:9601/diagnostics | jq '.btc_connectivity'
```

### Low Participation Rate

```bash
# Check if operator is in sortition pool
OPERATOR=$(curl -s http://localhost:9601/diagnostics | jq -r '.client_info.chain_address')
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry is-operator-in-pool \
  "$OPERATOR" --config configs/config.toml --developer

# Check authorized stake
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum threshold token-staking authorized-stake \
  --staking-provider "$OPERATOR" \
  --application ECDSA \
  --config configs/config.toml \
  --developer
```

## Log Analysis for Performance

### Extract Timing Information from Logs

```bash
# Extract DKG timing from logs
grep "DKG started\|transitioned to new state" logs/node1.log | \
  awk '{print $1, $2, $NF}' | \
  grep -E "dkg\.(tssRoundOneState|tssRoundTwoState|symmetricKeyGenerationState|finalizationState)"

# Extract wallet action timing
grep "wallet action\|step.*" logs/node1.log | \
  awk '{print $1, $2, $NF}'
```

### Create Performance Report

```bash
#!/bin/bash
# scripts/performance-report.sh

LOG_FILE="logs/node1.log"
OUTPUT="performance-report-$(date +%Y%m%d-%H%M%S).txt"

{
  echo "=== Keep Node Performance Report ==="
  echo "Generated: $(date)"
  echo ""
  
  echo "--- DKG Statistics ---"
  echo "Total DKG Started: $(grep -c "DKG started" $LOG_FILE)"
  echo "DKG Failures: $(grep -c "DKG.*failed" $LOG_FILE)"
  echo ""
  
  echo "--- Wallet Action Statistics ---"
  echo "Total Wallet Actions: $(grep -c "wallet action dispatched" $LOG_FILE)"
  echo "Deposit Sweeps: $(grep -c "deposit sweep" $LOG_FILE)"
  echo "Redemptions: $(grep -c "redemption action" $LOG_FILE)"
  echo ""
  
  echo "--- Signing Statistics ---"
  echo "Signing Operations: $(grep -c "signing.*completed" $LOG_FILE)"
  echo "Signing Failures: $(grep -c "signing.*failed" $LOG_FILE)"
  echo ""
  
  echo "--- Recent Errors ---"
  grep -i "error\|failed\|timeout" $LOG_FILE | tail -20
  
} > $OUTPUT

echo "Report saved to: $OUTPUT"
```

## Next Steps

1. **Set up Prometheus** for long-term metric storage and visualization
2. **Create Grafana dashboards** to visualize performance trends
3. **Set up alerts** for performance degradation (see `docs-v1/monitoring-and-alerting.adoc`)
4. **Monitor peer connectivity** as it affects DKG and signing performance
5. **Track on-chain events** to correlate with node metrics

## References

- [DKG Stages Monitoring Guide](./dkg-stages-monitoring.md)
- [Testing Deposits and Redemptions](./TESTING_DEPOSITS_REDEMPTIONS.md)
- [Monitoring and Alerting](./docs-v1/monitoring-and-alerting.adoc)
- [Performance Metrics Code](../pkg/clientinfo/performance.go)


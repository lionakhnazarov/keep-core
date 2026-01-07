# Measuring Redemption Speed

This guide explains how to measure the speed and performance of redemption operations in the Keep Network.

## Overview

Redemptions involve multiple phases:
1. **Request Phase**: User submits redemption request on-chain
2. **Proposal Phase**: Coordination leader creates redemption proposal
3. **Validation Phase**: Operators validate the proposal
4. **Signing Phase**: Operators sign the Bitcoin transaction
5. **Broadcast Phase**: Transaction is broadcast to Bitcoin network
6. **Confirmation Phase**: Bitcoin transaction gets confirmed

## Key Metrics

### End-to-End Metrics

- **Total Redemption Time**: From request submission to Bitcoin confirmation
- **Request to Proposal Time**: Time from request to proposal creation
- **Proposal to Signing Time**: Time from proposal to signing completion
- **Signing to Broadcast Time**: Time from signing to broadcast
- **Broadcast to Confirmation Time**: Time from broadcast to Bitcoin confirmation

### Per-Step Metrics

- **Validation Duration**: Time spent validating the proposal
- **Signing Duration**: Time spent signing the transaction
- **Broadcast Duration**: Time spent broadcasting the transaction

## Measuring from Logs

### Log Patterns

Redemption operations produce logs with these patterns:

```
# Redemption proposal received
"starting orchestration of the redemption action"

# Step markers
"step": "validateProposal"
"step": "signTransaction"  
"step": "broadcastTransaction"

# Action completion
"action execution terminated with success"
"action execution terminated with error"
```

### Extracting Timing Information

Use the `scripts/measure-redemption-speed.sh` script to extract timing from logs:

```bash
./scripts/measure-redemption-speed.sh [log_file]
```

The script will:
- Parse redemption action logs
- Extract timing for each step
- Calculate durations
- Display statistics

## Measuring from Metrics Endpoint

If Prometheus metrics are enabled, query these metrics:

### Redemption Action Duration

```promql
wallet_action_duration_seconds{action="redemption"}
```

### Redemption Success Rate

```promql
rate(wallet_action_success_total{action="redemption"}[5m])
rate(wallet_action_failed_total{action="redemption"}[5m])
```

### Redemption Step Durations

```promql
# Validation step
wallet_action_step_duration_seconds{action="redemption",step="validateProposal"}

# Signing step
wallet_action_step_duration_seconds{action="redemption",step="signTransaction"}

# Broadcast step
wallet_action_step_duration_seconds{action="redemption",step="broadcastTransaction"}
```

## Measuring from Chain Events

### Redemption Request Event

Monitor `RedemptionRequested` events on the Bridge contract:

```bash
# Get redemption request events
cast logs --from-block <start> --to-block <end> \
  --address <BridgeAddress> \
  "RedemptionRequested(address indexed walletPubKeyHash, bytes redeemerOutputScript, address indexed redeemer, uint64 requestedAmount, uint64 treasuryFee, uint64 txMaxFee)"
```

### Redemption Completion

Monitor Bitcoin transactions to detect when redemptions complete:

```bash
# Check Bitcoin transaction confirmations
bitcoin-cli gettransaction <txid>
```

## Expected Performance

### Typical Timings

- **Validation**: 5-30 seconds
- **Signing**: 30-120 seconds (depends on threshold group size)
- **Broadcast**: 1-5 seconds
- **Total (excluding Bitcoin confirmation)**: 1-3 minutes

### Factors Affecting Speed

1. **Network Latency**: P2P communication between operators
2. **Threshold Group Size**: Larger groups take longer to sign
3. **Bitcoin Network**: Confirmation time depends on Bitcoin network
4. **Proposal Validity**: Redemptions have ~600 block validity window (~2 hours)

## Troubleshooting Slow Redemptions

### Check Logs for Errors

```bash
grep -i "redemption.*error\|error.*redemption" logs/node*.log
```

### Check Step Durations

```bash
grep -E "step.*validateProposal|step.*signTransaction|step.*broadcastTransaction" logs/node*.log | \
  awk '{print $1, $2, $NF}'
```

### Check Network Connectivity

```bash
# Check peer connections
grep "number of connected peers" logs/node*.log | tail -5
```

### Check Bitcoin Network Status

```bash
# Check Bitcoin node sync status
bitcoin-cli getblockchaininfo | grep -E "blocks|verificationprogress"
```

## Example: Measuring a Specific Redemption

1. **Find the redemption request**:
   ```bash
   grep "RedemptionRequested" logs/node*.log | grep <wallet_pkh>
   ```

2. **Track the action**:
   ```bash
   grep "redemption action" logs/node*.log | grep <wallet_pkh>
   ```

3. **Measure step durations**:
   ```bash
   ./scripts/measure-redemption-speed.sh logs/node1.log | grep <wallet_pkh>
   ```

4. **Check completion**:
   ```bash
   grep "action execution terminated with success" logs/node*.log | grep <wallet_pkh>
   ```

## Integration with Performance Monitoring

The `scripts/monitor-performance.sh` script includes redemption metrics:

```bash
./scripts/monitor-performance.sh
```

This displays:
- Redemption success rate
- Average redemption duration
- Redemption step breakdowns

## Advanced: Custom Metrics Collection

To collect custom redemption metrics:

1. **Enable Prometheus metrics** in your config
2. **Query metrics**:
   ```bash
   curl http://localhost:9601/metrics | grep redemption
   ```

3. **Set up Grafana dashboards** using the metrics above

## See Also

- [Measuring Node Performance](./measuring-node-performance.md) - General performance metrics
- [Performance Monitoring Quick Reference](./performance-monitoring-quick-reference.md) - Quick command reference


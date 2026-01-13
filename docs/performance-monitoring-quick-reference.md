# Performance Monitoring Quick Reference

Quick reference guide for measuring node performance for DKG, deposits, and redemptions.

## Quick Commands

### Check All Performance Metrics

```bash
# Use the monitoring script
./scripts/monitor-performance.sh [port] [log_file]

# Or query metrics directly
curl -s http://localhost:9601/metrics | grep performance_
```

### DKG Performance

```bash
# DKG duration and counts
curl -s http://localhost:9601/metrics | grep performance_dkg

# DKG success rate
DKG_JOINED=$(curl -s http://localhost:9601/metrics | grep performance_dkg_joined_total | awk '{print $2}')
DKG_FAILED=$(curl -s http://localhost:9601/metrics | grep performance_dkg_failed_total | awk '{print $2}')
echo "Success Rate: $(echo "scale=2; ($DKG_JOINED - $DKG_FAILED) * 100 / $DKG_JOINED" | bc)%"

# Watch DKG in logs
tail -f logs/node1.log | grep -i "DKG\|dkg"
```

### Deposit Performance

```bash
# Wallet action metrics (includes deposits)
curl -s http://localhost:9601/metrics | grep performance_wallet_action

# Watch deposit sweeps in logs
tail -f logs/node1.log | grep -i "deposit\|sweep"

# Check deposit sweep duration
curl -s http://localhost:9601/metrics | grep performance_wallet_action_duration_seconds
```

### Redemption Performance

```bash
# Wallet action metrics (includes redemptions)
curl -s http://localhost:9601/metrics | grep performance_wallet_action

# Watch redemptions in logs
tail -f logs/node1.log | grep -i "redemption\|redeem"

# Check redemption duration
curl -s http://localhost:9601/metrics | grep performance_wallet_action_duration_seconds
```

### Signing Performance (Used in Deposits/Redemptions)

```bash
# Signing metrics
curl -s http://localhost:9601/metrics | grep performance_signing

# Signing success rate
SIGNING_OPS=$(curl -s http://localhost:9601/metrics | grep performance_signing_operations_total | awk '{print $2}')
SIGNING_FAILED=$(curl -s http://localhost:9601/metrics | grep performance_signing_failed_total | awk '{print $2}')
echo "Success Rate: $(echo "scale=2; ($SIGNING_OPS - $SIGNING_FAILED) * 100 / $SIGNING_OPS" | bc)%"
```

## Key Metrics

### DKG Metrics
- `performance_dkg_requested_total` - Total DKG requests
- `performance_dkg_joined_total` - Times node joined DKG
- `performance_dkg_failed_total` - Failed DKG attempts
- `performance_dkg_duration_seconds` - Average DKG duration
- `performance_dkg_duration_seconds_count` - Total DKG operations

### Wallet Action Metrics (Deposits & Redemptions)
- `performance_wallet_actions_total` - Total wallet actions
- `performance_wallet_action_success_total` - Successful actions
- `performance_wallet_action_failed_total` - Failed actions
- `performance_wallet_action_duration_seconds` - Average duration
- `performance_wallet_action_duration_seconds_count` - Total actions

### Signing Metrics
- `performance_signing_operations_total` - Total signing operations
- `performance_signing_success_total` - Successful signings
- `performance_signing_failed_total` - Failed signings
- `performance_signing_duration_seconds` - Average signing duration

## Expected Performance

| Metric | Expected Value |
|--------|---------------|
| DKG Duration | 2-5 minutes |
| DKG Success Rate | >95% |
| Deposit Sweep Duration | 5-15 minutes |
| Redemption Duration | 5-15 minutes |
| Wallet Action Success Rate | >98% |
| Signing Success Rate | >95% |

## Log Patterns

### DKG Stages
```
DKG started with seed [0x...]
transitioning to a new state [*dkg.tssRoundOneState]
transitioned to new state [*dkg.tssRoundTwoState]
```

### Deposit Sweep Stages
```
starting orchestration of the deposit sweep action
step: validateProposal
step: signTransaction
step: broadcastTransaction
wallet action dispatched successfully
```

### Redemption Stages
```
starting orchestration of the redemption action
step: validateProposal
step: signTransaction
step: broadcastTransaction
wallet action dispatched successfully
```

## Troubleshooting

### High Failure Rates
```bash
# Check network connectivity
curl -s http://localhost:9601/diagnostics | jq '.connected_peers | length'

# Check for errors in logs
grep -i "error\|failed\|timeout" logs/node1.log | tail -20
```

### Slow Performance
```bash
# Check signing duration
curl -s http://localhost:9601/metrics | grep performance_signing_duration_seconds

# Check Bitcoin/Ethereum connectivity
curl -s http://localhost:9601/metrics | grep -E "eth_connectivity|btc_connectivity"
```

## Continuous Monitoring

```bash
# Watch metrics every 30 seconds
watch -n 30 './scripts/monitor-performance.sh'

# Or use a loop
while true; do
  ./scripts/monitor-performance.sh
  sleep 60
done
```

## See Also

- [Full Performance Monitoring Guide](./measuring-node-performance.md)
- [DKG Stages Monitoring](./dkg-stages-monitoring.md)
- [Testing Deposits and Redemptions](./TESTING_DEPOSITS_REDEMPTIONS.md)



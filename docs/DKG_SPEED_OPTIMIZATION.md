# DKG Speed Optimization Guide

When you **cannot increase the timeout**, here are alternative ways to process DKG successfully:

## Problem

DKG timeout is 30 blocks, but the protocol needs more real-time to complete. The timeout is measured in **blocks**, not seconds, so we can optimize by:

1. **Speeding up block mining** (gives more real-time)
2. **Auto-resetting on timeout** (prevents stuck state)
3. **Optimizing network** (reduces protocol time)
4. **Monitoring closely** (catch issues early)

## Solution 1: Speed Up Block Mining ⚡ (Most Effective)

### Option A: Use Manual Block Mining

During DKG execution, manually mine blocks to speed up the countdown:

```bash
# Mine 50 blocks quickly
./scripts/mine-blocks-fast.sh 50 0.1

# Or mine continuously during DKG
while true; do
  cast rpc evm_mine --rpc-url http://localhost:8545 >/dev/null 2>&1
  sleep 0.1
done
```

**How it works**: The timeout is 30 blocks. If you mine blocks faster, you give the protocol more real-time to complete before hitting the block-based timeout.

### Option B: Modify Geth for Faster Mining

Edit `infrastructure/docker/ethereum/geth-node/docker-entrypoint.sh`:

```bash
# Add these flags to speed up mining:
--dev --dev.period=1 \
--miner.gastarget=8000000 \
--miner.gaslimit=8000000 \
```

Then restart Geth:
```bash
docker-compose -f infrastructure/docker-compose.yml restart geth-node
```

## Solution 2: Auto-Reset on Timeout 🔄 (Prevents Stuck State)

Run a background monitor that automatically resets timed-out DKG and retries:

```bash
# Run in background
./scripts/auto-reset-dkg.sh configs/config.toml &

# Or run in separate terminal
nohup ./scripts/auto-reset-dkg.sh configs/config.toml > /tmp/dkg-monitor.log 2>&1 &
```

**What it does**:
- Monitors DKG state every 5 seconds
- When timeout detected, automatically resets DKG
- Immediately triggers new DKG
- Prevents getting stuck in AWAITING_RESULT

**Stop monitoring**:
```bash
pkill -f auto-reset-dkg.sh
```

## Solution 3: Optimize Network Communication 🌐

DKG protocol speed depends on P2P communication between nodes:

### Check All Nodes Are Running
```bash
ps aux | grep 'keep-client.*start' | wc -l
# Should show number of nodes (e.g., 10)
```

### Check libp2p Connectivity
```bash
tail -f logs/node*.log | grep -i 'peer\|connection\|network'
```

### Ensure Low Latency
- Run all nodes on the same machine (best)
- Or use a low-latency network
- Check `configs/node*.toml` for libp2p addresses

## Solution 4: Monitor Protocol Speed 📊

Track how long each phase takes:

```bash
# Monitor DKG phases
tail -f logs/node*.log | grep -E "starting.*phase|phase.*complete|submitting.*result"
```

Look for:
- `starting announcement phase` - Protocol started
- `submitting DKG result` - Result ready to submit
- `DKG result.*submitted` - Success!

If phases take too long, check for:
- Network delays
- Node synchronization issues
- CPU/memory constraints

## Solution 5: Combined Approach (Recommended) 🎯

**Best practice**: Combine multiple solutions:

```bash
# Terminal 1: Start auto-reset monitor
./scripts/auto-reset-dkg.sh configs/config.toml

# Terminal 2: Trigger DKG
./scripts/request-new-wallet.sh

# Terminal 3: Monitor progress
tail -f logs/node*.log | grep -i "dkg\|phase\|submitting"

# Terminal 4: Mine blocks if needed
./scripts/mine-blocks-fast.sh 30 0.1
```

## Quick Reference

### Check Current State
```bash
./scripts/check-dkg-status.sh
```

### Reset Timed-Out DKG
```bash
./scripts/fix-dkg-stuck-in-stage2.sh configs/config.toml
```

### Mine Blocks Fast
```bash
./scripts/mine-blocks-fast.sh 50 0.1
```

### Auto-Reset Monitor
```bash
./scripts/auto-reset-dkg.sh configs/config.toml
```

## Understanding the Timeout

- **Timeout**: 30 blocks
- **Block time**: ~1 second per block (in normal Geth)
- **Real-time**: ~30 seconds

**With faster mining**:
- Block time: ~0.1 seconds per block
- Real-time: ~3 seconds (not enough!)
- **But**: You can mine blocks manually during DKG to give more real-time

**Key insight**: The timeout is block-based, but the protocol needs real-time. By mining blocks faster, you're essentially "pausing" the timeout countdown while giving the protocol more real-time to complete.

## Troubleshooting

### DKG Still Times Out
1. Check if protocol phases are completing: `tail -f logs/node*.log | grep phase`
2. Verify network connectivity: Check libp2p logs
3. Ensure all nodes are participating: Check member selection logs
4. Try mining blocks more aggressively during protocol execution

### Auto-Reset Not Working
1. Check script permissions: `chmod +x scripts/auto-reset-dkg.sh`
2. Verify RPC access: `cast block-number --rpc-url http://localhost:8545`
3. Check WalletRegistry address: `jq -r '.address' solidity/ecdsa/deployments/development/WalletRegistry.json`

### Blocks Not Mining Fast Enough
1. Use `evm_mine` RPC call (instant)
2. Modify Geth to use `--dev` mode
3. Consider reducing timeout via governance (if possible)

## Summary

**Without increasing timeout**, the best approach is:

1. ✅ **Auto-reset monitor** - Prevents stuck state
2. ✅ **Manual block mining** - Gives more real-time during DKG
3. ✅ **Network optimization** - Reduces protocol execution time
4. ✅ **Close monitoring** - Catch issues early

The combination of auto-reset + manual block mining during DKG execution gives you the best chance of success without modifying the timeout parameter.

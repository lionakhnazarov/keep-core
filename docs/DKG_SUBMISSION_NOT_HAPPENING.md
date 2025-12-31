# Why DKG Result Submission Doesn't Happen

## Problem

Operators are **not submitting the DKG result** even though DKG is in `AWAITING_RESULT` state (2).

## Root Cause

**The DKG protocol times out before it can complete and submit the result.**

### What Should Happen

```
AWAITING_RESULT (2)
    ↓
1. Protocol runs (announcement → key generation → signing)
    ↓
2. Collect signatures (need GroupQuorum)
    ↓
3. Wait for submission block (with delay)
    ↓
4. Submit result → CHALLENGE (3)
```

### What Actually Happens

```
AWAITING_RESULT (2)
    ↓
1. Protocol starts running...
    ↓
2. ⏰ TIMEOUT (30 blocks) occurs
    ↓
3. Operators abort: "DKG is no longer awaiting the result"
    ↓
4. ❌ Result never submitted
```

## Why Submission Fails

The submission code checks these conditions (from `pkg/tbtc/dkg_submit.go`):

1. **Enough signatures**: `len(signatures) >= GroupQuorum`
2. **State is AWAITING_RESULT**: `dkgState == AwaitingResult`
3. **Result is valid**: `IsDKGResultValid() == true`
4. **Wait for submission block**: Wait for `currentBlock + delayBlocks`
5. **State still AWAITING_RESULT**: Check again before submitting

**But the timeout occurs before step 1-4 can complete**, so operators abort at step 5.

## Evidence from Logs

```
[member:X] DKG is no longer awaiting the result; aborting DKG protocol execution
```

This message appears because:
- The timeout context is cancelled (`ctx.Err() != nil`)
- Operators detect DKG state is no longer `AWAITING_RESULT` (or timeout occurred)
- They abort the protocol execution before submission

## Debugging

Use the debug script:

```bash
./scripts/debug-dkg-submission.sh configs/config.toml
```

This will show:
- Current DKG state
- Timeout status
- Protocol progress
- Why submission isn't happening

## Solutions

### Solution 1: Speed Up Block Mining (Recommended) ⚡

Mine blocks faster during DKG to give the protocol more real-time:

```bash
# Mine blocks during DKG execution
./scripts/mine-blocks-fast.sh 50 0.1

# Or continuously
while true; do
  cast rpc evm_mine --rpc-url http://localhost:8545 >/dev/null 2>&1
  sleep 0.1
done
```

**How it works**: The timeout is block-based (30 blocks). By mining blocks faster, you give the protocol more real-time before hitting the timeout.

### Solution 2: Auto-Reset Monitor 🔄

Automatically reset timed-out DKG and retry:

```bash
# Run in background
./scripts/auto-reset-dkg.sh configs/config.toml &

# This will:
# - Monitor DKG state every 5 seconds
# - Reset when timeout detected
# - Immediately trigger new DKG
```

### Solution 3: Increase Timeout (If Possible) ⏱️

If you can modify governance parameters:

```bash
# Increase resultSubmissionTimeout from 30 to at least 500 blocks
# This requires governance delay (60 seconds in development)
```

### Solution 4: Optimize Protocol Speed 🚀

Ensure optimal conditions for protocol execution:

1. **Check network connectivity**:
   ```bash
   tail -f logs/node*.log | grep -i "peer\|connection\|network"
   ```

2. **Verify all nodes are running**:
   ```bash
   ps aux | grep 'keep-client.*start' | wc -l
   # Should show number of nodes (e.g., 10)
   ```

3. **Check for errors**:
   ```bash
   tail -100 logs/node*.log | grep -i "error\|fail"
   ```

## Combined Approach (Best Results)

Use multiple solutions together:

```bash
# Terminal 1: Auto-reset monitor
./scripts/auto-reset-dkg.sh configs/config.toml &

# Terminal 2: Trigger DKG
./scripts/request-new-wallet.sh

# Terminal 3: Monitor progress
tail -f logs/node*.log | grep -E "dkg|phase|submitting|result"

# Terminal 4: Mine blocks during DKG
./scripts/mine-blocks-fast.sh 30 0.1
```

## Understanding the Submission Requirements

For submission to succeed, ALL of these must be true:

1. ✅ **Protocol completes**: All phases finish successfully
2. ✅ **Enough signatures**: At least `GroupQuorum` signatures collected
3. ✅ **Result is valid**: Validation passes
4. ✅ **State is AWAITING_RESULT**: Still in state 2
5. ✅ **Submission block reached**: Delay blocks have passed
6. ✅ **No timeout**: Timeout hasn't occurred yet

**Current issue**: Step 6 fails because timeout occurs before steps 1-5 complete.

## Monitoring Submission Attempts

Watch for these log messages:

**Good signs** (submission happening):
```
[member:X] waiting for block [Y] to submit DKG result
[member:X] submitting DKG result with [Z] supporting member signatures
DKG result submitted at block [W]
```

**Bad signs** (submission failing):
```
[member:X] DKG is no longer awaiting the result; aborting DKG protocol execution
could not submit result with [X] signatures for group quorum [Y]
DKG protocol execution aborted
```

## Expected Timeline

With a 30-block timeout:

| Step | Blocks | Real-time (1s/block) | Status |
|------|--------|---------------------|--------|
| Protocol start | 0 | 0s | ✅ |
| Protocol phases | 1-20 | 1-20s | ⚠️ May timeout |
| Signature collection | 20-25 | 20-25s | ⚠️ May timeout |
| Submission delay | 25-28 | 25-28s | ⚠️ May timeout |
| **Timeout** | **30** | **30s** | ❌ **TOO SHORT** |
| Submission | 30+ | 30s+ | ❌ Never reached |

**Solution**: Mine blocks faster or increase timeout to give more real-time.

## Quick Fix Script

```bash
#!/bin/bash
# Quick fix: Mine blocks and monitor during DKG

# Start mining blocks in background
(
  while true; do
    cast rpc evm_mine --rpc-url http://localhost:8545 >/dev/null 2>&1
    sleep 0.1
  done
) &
MINER_PID=$!

# Trigger DKG
./scripts/request-new-wallet.sh

# Monitor for submission
echo "Monitoring for result submission..."
tail -f logs/node*.log | grep -E "submitting.*result|result.*submitted" &
MONITOR_PID=$!

# Wait for submission or timeout
sleep 60

# Cleanup
kill $MINER_PID $MONITOR_PID 2>/dev/null
```

## Summary

**Why submission doesn't happen:**
- DKG protocol needs more time than the 30-block timeout allows
- Operators abort when timeout occurs
- Result never gets submitted

**How to fix:**
1. ✅ Speed up block mining (gives more real-time)
2. ✅ Auto-reset monitor (prevents stuck state)
3. ✅ Optimize network (reduces protocol time)
4. ✅ Increase timeout (if possible)

**Best approach**: Combine auto-reset monitor + fast block mining during DKG execution.

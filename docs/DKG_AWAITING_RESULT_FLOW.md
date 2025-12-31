# What Happens After AWAITING_RESULT (State 2)

## Overview

When DKG reaches **AWAITING_RESULT (state 2)**, the following sequence should occur automatically:

```
AWAITING_RESULT (2) 
    ↓ [Protocol completes]
Result Submission
    ↓ [State changes]
CHALLENGE (3)
    ↓ [Challenge period ends]
Result Approval
    ↓ [Approval succeeds]
IDLE (0) - Wallet Created ✓
```

## Step-by-Step Process

### Step 1: DKG Protocol Execution (Automatic) ⚙️

**What happens:**
- Selected operators run the distributed key generation protocol **off-chain**
- Protocol involves multiple phases:
  1. **Announcement phase** - Operators announce participation
  2. **Key generation phase** - Generate distributed keys
  3. **Result signing phase** - Collect signatures on the result

**Expected logs:**
```
[member:X] starting announcement phase for attempt [1]
[member:X] starting key generation phase
[member:X] DKG protocol completed
```

**How to monitor:**
```bash
# Watch for protocol phases
tail -f logs/node*.log | grep -E "starting.*phase|phase.*complete|protocol.*complete"

# Check specific member activity
tail -f logs/node*.log | grep "member:"
```

**Duration:** Varies based on network latency and number of operators (typically 10-60 seconds)

---

### Step 2: Result Submission (Automatic) 📤

**What happens:**
- When protocol completes, operators collect signatures
- One operator (the submitter) submits the DKG result to the chain
- Result includes:
  - Group public key
  - Member list
  - Supporting signatures (must meet quorum)

**State transition:** `AWAITING_RESULT (2)` → `CHALLENGE (3)`

**Expected logs:**
```
[member:X] submitting DKG result with [Y] supporting member signatures
DKG result submitted at block [Z]
```

**How to verify:**
```bash
# Check state (should change from 2 to 3)
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry get-wallet-creation-state \
  --config configs/config.toml --developer

# Check for submission event
./scripts/check-dkg-status.sh

# Or check events directly
cd solidity/ecdsa
npx hardhat run scripts/check-dkg-status.ts --network development
```

**What can go wrong:**
- ❌ **Timeout**: Protocol doesn't complete before `resultSubmissionTimeout` (30 blocks)
- ❌ **Insufficient signatures**: Not enough operators signed the result
- ❌ **Network issues**: Operators can't communicate

**If submission fails:** DKG will timeout and reset to IDLE

---

### Step 3: Challenge Period (Waiting) ⏳

**What happens:**
- DKG state changes to **CHALLENGE (3)**
- Challenge period starts (default: 10 blocks with minimum params)
- During this period, anyone can challenge the result if invalid
- If challenged, DKG reverts to AWAITING_RESULT and restarts

**State:** `CHALLENGE (3)`

**Expected logs:**
```
starting DKG result validation
DKG result is valid
scheduling DKG result approval
```

**How to monitor:**
```bash
# Check state (should be 3)
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry get-wallet-creation-state \
  --config configs/config.toml --developer

# Check challenge period parameters
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry dkg-parameters \
  --config configs/config.toml --developer
```

**Duration:** 
- Minimum params: 10 blocks (~10 seconds)
- Production: 11,520 blocks (~2 hours)

**What happens if challenged:**
- If result is invalid, any operator can challenge
- DKG state reverts to AWAITING_RESULT (2)
- New DKG attempt starts

---

### Step 4: Result Approval (Automatic) ✅

**What happens:**
- After challenge period ends, operators automatically approve the result
- Submitter can approve immediately after challenge period
- Other members can approve after precedence period
- Approval finalizes DKG and creates the wallet

**State transition:** `CHALLENGE (3)` → `IDLE (0)`

**Expected logs:**
```
[member:X] waiting for block [Y] to approve DKG result
approving DKG result...
DKG result approved
Wallet created: [walletID]
```

**How to verify:**
```bash
# Check state (should change from 3 to 0)
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry get-wallet-creation-state \
  --config configs/config.toml --developer

# Check for approval event
./scripts/check-dkg-status.sh

# List created wallets
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry get-wallets \
  --config configs/config.toml --developer
```

**Duration:**
- Submit precedence period: 20 blocks (~20 seconds)
- Then other members can approve

---

### Step 5: Finalization (Automatic) 🎉

**What happens:**
- Wallet is created and registered
- `WalletCreated` event is emitted
- DKG state returns to **IDLE (0)**
- Wallet is ready for use

**State:** `IDLE (0)`

**Expected logs:**
```
Wallet created: [walletID]
Group public key: [0x...]
DKG complete
```

**How to verify:**
```bash
# Check state (should be 0)
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry get-wallet-creation-state \
  --config configs/config.toml --developer

# List wallets
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry get-wallets \
  --config configs/config.toml --developer

# Check wallet details
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry get-wallet \
  [WALLET_ID] \
  --config configs/config.toml --developer
```

---

## Complete Monitoring Script

```bash
#!/bin/bash
# Monitor DKG from AWAITING_RESULT to completion

CONFIG_FILE="${1:-configs/config.toml}"

echo "Monitoring DKG process..."
echo "Press Ctrl+C to stop"
echo ""

PREV_STATE=""
while true; do
  STATE=$(KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry get-wallet-creation-state \
    --config "$CONFIG_FILE" --developer 2>&1 | grep -E "^[0-9]+$" | head -1)
  
  if [ "$STATE" != "$PREV_STATE" ]; then
    case "$STATE" in
      0) echo "[$(date +'%H:%M:%S')] ✓ DKG Complete (IDLE) - Wallet Created!" ;;
      1) echo "[$(date +'%H:%M:%S')] ⏳ Waiting for seed (AWAITING_SEED)" ;;
      2) echo "[$(date +'%H:%M:%S')] ⚙️  DKG protocol running (AWAITING_RESULT)" ;;
      3) echo "[$(date +'%H:%M:%S')] ⏳ Challenge period (CHALLENGE)" ;;
      *) echo "[$(date +'%H:%M:%S')] ? Unknown state: $STATE" ;;
    esac
    PREV_STATE="$STATE"
  fi
  
  sleep 2
done
```

---

## Timeline Example (Minimum Params)

With minimum DKG parameters:

| Step | State | Duration | Description |
|------|-------|----------|-------------|
| 1 | 2 | ~10-60s | Protocol execution |
| 2 | 2→3 | ~1s | Result submission |
| 3 | 3 | ~10s | Challenge period (10 blocks) |
| 4 | 3→0 | ~20s | Approval (submitter precedence) |
| 5 | 0 | - | Wallet created |

**Total time:** ~30-90 seconds from AWAITING_RESULT to completion

---

## Troubleshooting

### Stuck in AWAITING_RESULT (2)

**Symptoms:**
- State stays at 2 for extended period
- No result submission logs
- `hasDkgTimedOut()` returns `true`

**Solutions:**
```bash
# Check timeout status
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry has-dkg-timed-out \
  --config configs/config.toml --developer

# Reset if timed out
./scripts/fix-dkg-stuck-in-stage2.sh configs/config.toml

# Or use auto-reset monitor
./scripts/auto-reset-dkg.sh configs/config.toml &
```

### Result Submitted but Stuck in CHALLENGE (3)

**Symptoms:**
- State stays at 3
- Challenge period has ended
- No approval logs

**Solutions:**
```bash
# Check if challenge period ended
# Get submission block from events
# Calculate: submissionBlock + challengePeriodLength
# Current block must exceed this

# Check logs for approval scheduling
grep -i "scheduling.*approval\|waiting.*block.*approve" logs/node*.log

# Manually trigger approval (if needed)
# See approve-dkg-result.sh script
```

### Protocol Not Completing

**Symptoms:**
- No "protocol completed" logs
- Operators aborting: "DKG is no longer awaiting the result"

**Solutions:**
```bash
# Check network connectivity
tail -f logs/node*.log | grep -i "peer\|connection\|network"

# Verify all nodes are running
ps aux | grep 'keep-client.*start'

# Check for errors
tail -100 logs/node*.log | grep -i "error\|fail"
```

---

## Summary

**After AWAITING_RESULT (2), the process is mostly automatic:**

1. ✅ **Protocol execution** - Operators run DKG protocol (automatic)
2. ✅ **Result submission** - Operators submit result (automatic)
3. ⏳ **Challenge period** - Wait for challenge period (automatic waiting)
4. ✅ **Result approval** - Operators approve result (automatic)
5. ✅ **Wallet creation** - Wallet created, DKG complete (automatic)

**You mainly need to:**
- Monitor the process
- Ensure nodes are running
- Wait for automatic completion
- Intervene only if something goes wrong (timeout, stuck state)

**Key monitoring commands:**
```bash
# Check current state
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry get-wallet-creation-state \
  --config configs/config.toml --developer

# Full status check
./scripts/check-dkg-status.sh

# Monitor logs
tail -f logs/node*.log | grep -i "dkg\|submit\|approve\|wallet"
```

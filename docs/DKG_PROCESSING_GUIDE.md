# DKG Processing Guide: From AWAITING_RESULT to Finalization

This guide explains how DKG progresses from state 2 (AWAITING_RESULT) to completion.

## DKG States Overview

- **0 = IDLE**: No active DKG
- **1 = AWAITING_SEED**: Waiting for Random Beacon seed
- **2 = AWAITING_RESULT**: DKG protocol running, waiting for result submission
- **3 = CHALLENGE**: Result submitted, waiting for challenge period to end

## Process Flow: AWAITING_RESULT → Finalization

### Step 1: DKG Protocol Execution (Automatic)

When DKG is in **AWAITING_RESULT** state (state 2):

1. **Operators run the DKG protocol off-chain**
   - All selected operators participate in the distributed key generation
   - Protocol involves multiple phases: announcement, key generation, result signing
   - This happens automatically in the background

2. **Monitor protocol progress:**
```bash
# Watch node logs for DKG activity
tail -f logs/node*.log | grep -i "dkg\|announcement\|key.*generation\|result.*signing"

# Check for protocol phases
tail -f logs/node*.log | grep -E "starting.*phase|member.*phase"
```

### Step 2: Result Submission (Automatic)

When the DKG protocol completes:

1. **Operators automatically submit the DKG result**
   - One operator (the submitter) submits the result to the chain
   - Result includes: group public key, member list, signatures
   - State changes from **AWAITING_RESULT (2)** to **CHALLENGE (3)**

2. **Check if result was submitted:**
```bash
# Check DKG state
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry get-wallet-creation-state \
  --config configs/config.toml --developer

# Check for DkgResultSubmitted events
./scripts/check-dkg-status.sh

# Or manually check events
cd solidity/ecdsa
npx hardhat run scripts/check-dkg-status.ts --network development
```

3. **Expected log messages:**
```
[member:X] submitting DKG result with [Y] supporting member signatures
DKG result submitted at block [Z]
```

### Step 3: Challenge Period (Waiting)

After result submission, DKG enters **CHALLENGE** state (state 3):

1. **Challenge period starts**
   - Default: 10 blocks (if using minimum params) or 11,520 blocks (production)
   - During this period, anyone can challenge the result if invalid
   - If challenged, DKG reverts to AWAITING_RESULT

2. **Monitor challenge period:**
```bash
# Check current state (should be 3 = CHALLENGE)
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry get-wallet-creation-state \
  --config configs/config.toml --developer

# Check DKG parameters to see challenge period length
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry dkg-parameters \
  --config configs/config.toml --developer
```

3. **Check if challenge period ended:**
```bash
# Get submission block from events, then calculate:
# challengePeriodEnd = submissionBlock + resultChallengePeriodLength
# Current block must be > challengePeriodEnd to approve
```

### Step 4: Result Approval (Automatic or Manual)

After challenge period ends:

1. **Automatic Approval (Recommended)**
   - Nodes automatically schedule approval
   - Submitter can approve immediately after challenge period
   - Other members can approve after precedence period
   - Approval finalizes DKG and creates the wallet

2. **Check if approval is scheduled:**
```bash
# Check node logs for approval scheduling
grep -i "scheduling.*approval\|waiting.*block.*approve" logs/node*.log

# Run approval check script
./scripts/approve-dkg-result.sh configs/config.toml
```

3. **Expected log messages:**
```
scheduling DKG result approval
[member:X] waiting for block [Y] to approve DKG result
approving DKG result...
DKG result approved
Wallet created: [walletID]
```

### Step 5: Finalization (Automatic)

When result is approved:

1. **Wallet is created**
   - `WalletCreated` event is emitted
   - Wallet ID and public key are registered
   - DKG state returns to **IDLE (0)**

2. **Verify completion:**
```bash
# Check state (should be 0 = IDLE)
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry get-wallet-creation-state \
  --config configs/config.toml --developer

# Check for WalletCreated events
./scripts/check-dkg-status.sh

# List created wallets
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry get-wallets \
  --config configs/config.toml --developer
```

## Complete Monitoring Script

Create a script to monitor the entire process:

```bash
#!/bin/bash
# Monitor DKG from AWAITING_RESULT to completion

while true; do
  STATE=$(KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry get-wallet-creation-state \
    --config configs/config.toml --developer 2>&1 | grep -E "^[0-9]+$" | head -1)
  
  case "$STATE" in
    0) echo "✓ DKG Complete (IDLE)" ;;
    1) echo "⏳ Waiting for seed (AWAITING_SEED)" ;;
    2) echo "⏳ DKG protocol running (AWAITING_RESULT)" ;;
    3) echo "⏳ Challenge period (CHALLENGE)" ;;
    *) echo "? Unknown state: $STATE" ;;
  esac
  
  sleep 5
done
```

## Manual Intervention

### If Result Submission Fails

If operators don't submit the result:

1. **Check why:**
```bash
# Check node logs for errors
tail -100 logs/node*.log | grep -i "error\|fail\|timeout"

# Verify operators are participating
tail -f logs/node*.log | grep -i "member.*participating\|selected.*group"
```

2. **Common issues:**
   - DKG timeout too short (increase `resultSubmissionTimeout`)
   - Not enough operators participating
   - Network communication issues
   - Insufficient signatures collected

### If Approval Doesn't Happen

If result is submitted but not approved:

1. **Check if challenge period ended:**
```bash
# Get submission block and challenge period
# Calculate: submissionBlock + challengePeriodLength
# Current block must exceed this
```

2. **Manually approve (if you have the result JSON):**
```bash
# Extract DKG result from logs or contract
# Then approve:
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry approve-dkg-result \
  '<DKG_RESULT_JSON>' \
  --submit \
  --config configs/config.toml \
  --developer
```

3. **Use the approval script:**
```bash
./scripts/approve-dkg-result.sh configs/config.toml
```

## Quick Reference Commands

```bash
# Check current state
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry get-wallet-creation-state \
  --config configs/config.toml --developer

# Check DKG status (full details)
./scripts/check-dkg-status.sh

# Monitor logs
tail -f logs/node*.log | grep -i "dkg\|approve\|submit\|wallet"

# Check if timed out
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry has-dkg-timed-out \
  --config configs/config.toml --developer

# Reset if timed out
./scripts/reset-dkg-if-timed-out.sh
```

## Timeline Example (with minimum params)

With minimum DKG parameters:
- **Result Submission Timeout**: 30 blocks (~30 seconds)
- **Challenge Period**: 10 blocks (~10 seconds)
- **Submitter Precedence**: 20 blocks (~20 seconds)

**Total time**: ~60 seconds from AWAITING_RESULT to completion (if everything works smoothly)

## Troubleshooting

### DKG Stuck in AWAITING_RESULT

- **Check timeout**: `hasDkgTimedOut()` should return `true` after timeout
- **Reset if timed out**: `./scripts/reset-dkg-if-timed-out.sh`
- **Increase timeout**: Update `resultSubmissionTimeout` via governance

### Result Submitted but Not Approved

- **Wait for challenge period**: Must wait for `resultChallengePeriodLength` blocks
- **Check precedence period**: Submitter has precedence for `submitterPrecedencePeriodLength` blocks
- **Monitor logs**: Nodes should schedule approval automatically

### No Result Submitted

- **Check protocol completion**: Look for "DKG protocol completed" in logs
- **Verify signatures**: Need enough signatures to meet quorum
- **Check timeout**: Protocol must complete before `resultSubmissionTimeout`

## Summary

The DKG process from AWAITING_RESULT to finalization is **mostly automatic**:

1. ✅ Operators run DKG protocol (automatic)
2. ✅ Operators submit result (automatic)
3. ⏳ Challenge period (waiting)
4. ✅ Operators approve result (automatic)
5. ✅ Wallet created, DKG complete

**You mainly need to:**
- Monitor the process
- Ensure nodes are running
- Wait for automatic completion
- Intervene only if something goes wrong

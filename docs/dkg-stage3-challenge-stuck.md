# DKG Stuck in CHALLENGE State (Stage 3)

## Quick Fix

**To approve a DKG result stuck in CHALLENGE state:**

```bash
# Complete automated approval process
./scripts/approve-dkg-result-complete.sh configs/node1.toml 1
```

This script will:
1. ✅ Check DKG is in CHALLENGE state
2. ✅ Verify challenge period has passed
3. ✅ Get DKG result JSON from on-chain events
4. ✅ Approve the result using operator key

**Requirements:**
- Challenge period must have ended (10 blocks in development)
- Use an operator key that was part of the DKG
- If in precedence period, only submitter can approve

---

## Current Situation

When DKG is stuck in **CHALLENGE state (3)**, it means:
- ✅ A DKG result was successfully submitted
- ⏳ The result is in the challenge period
- ❌ Operators are failing to approve the result

## Diagnosis

Run the diagnostic script:
```bash
./scripts/check-dkg-approval-status.sh
```

This will show:
- Current DKG state
- When challenge period ends
- Whether result was already approved
- Timing information

## Common Causes

### 1. Approval Failing with "execution reverted"

**Symptoms:**
- Logs show: `cannot approve DKG result: [execution reverted]`
- Challenge period has passed
- Result not approved yet

**Possible reasons:**
- **Challenge period hasn't passed**: Approval only allowed after challenge period ends
- **Not the submitter during precedence period**: Only submitter can approve during precedence period
- **Result hash mismatch**: The result being approved doesn't match submitted result
- **Member not eligible**: The member trying to approve wasn't part of the DKG
- **DKG state changed**: State changed between checking and approving

**Solution:**
```bash
# Check approval status
./scripts/check-dkg-approval-status.sh

# If challenge period hasn't passed, mine blocks
./scripts/mine-blocks-fast.sh [number_of_blocks]

# Check if operators are eligible
# Look at logs to see which members are trying to approve
grep -i "approve\|member:" logs/node*.log | tail -20
```

### 2. Operators Not Attempting Approval

**Symptoms:**
- No approval attempts in logs
- Challenge period has passed
- Nodes are running but not approving

**Possible reasons:**
- Operators not selected for this DKG
- Network connectivity issues
- Nodes crashed or restarted

**Solution:**
```bash
# Check if nodes are running
./scripts/check-dkg-metrics.sh

# Check operator connectivity
for i in {1..10}; do
  curl -s http://localhost:960$i/metrics | grep connected_peers_count
done

# Check if operators were part of DKG
grep -i "member:" logs/node*.log | grep -i "dkg\|joined" | tail -20
```

### 3. Result Already Approved But State Not Updated

**Symptoms:**
- Approval events exist on-chain
- But state still shows CHALLENGE
- Nodes think result isn't approved

**Solution:**
```bash
# Check if result was approved
./scripts/check-dkg-approval-status.sh

# If approved but state wrong, wait for next block or restart nodes
# The state should sync on next block
```

## Solutions

### Solution 1: Wait for Automatic Approval

Operators will automatically retry approval. Check logs:
```bash
tail -f logs/node*.log | grep -i "approve\|challenge"
```

### Solution 2: Mine Blocks to Advance Time

If challenge period hasn't passed:
```bash
# Mine blocks to reach challenge period end
./scripts/mine-blocks-fast.sh 10
```

### Solution 3: Reset DKG (If Timed Out)

If DKG has timed out:
```bash
# Check if timed out
./scripts/check-dkg-timeout-details.sh

# Reset if timed out
./scripts/reset-dkg.sh
```

### Solution 4: Check Operator Eligibility

Verify operators are eligible to approve:
```bash
# Check which operators are in the DKG result
# Look at logs for member indexes
grep -i "member:" logs/node*.log | grep -E "approve|joined|DKG" | tail -30

# Check operator addresses
for i in {1..10}; do
  echo "Node $i:"
  curl -s http://localhost:960$i/diagnostics | jq -r '.client_info.chain_address'
done
```

### Solution 5: Manual Approval (Complete Process)

**Recommended: Use the complete approval script**

```bash
# Automatically gets result, checks timing, and approves
./scripts/approve-dkg-result-complete.sh [config-file] [node-number]

# Example: Use node 1's config
./scripts/approve-dkg-result-complete.sh configs/node1.toml 1
```

**Manual process (if script doesn't work):**

```bash
# Step 1: Get the DKG result JSON
./scripts/get-dkg-result.sh configs/config.toml

# Step 2: Approve using the JSON (replace with actual JSON)
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry approve-dkg-result '<json>' \
  --submit --config configs/node1.toml --developer
```

**Requirements for approval:**
- Challenge period must have passed
- If in precedence period, only the submitter can approve
- After precedence period, any eligible member can approve
- Must use an operator key that was part of the DKG

## Monitoring

### Watch Approval Progress

```bash
# Monitor approval attempts
watch -n 2 'grep -h "approve\|challenge" logs/node*.log | tail -10'

# Monitor metrics
watch -n 5 './scripts/check-dkg-metrics.sh'
```

### Check State Changes

```bash
# Watch state transitions
watch -n 5 './scripts/check-dkg-status.sh | grep "Wallet Creation State"'
```

## Expected Flow

```
AWAITING_RESULT (2) 
  → Result Submitted
  → CHALLENGE (3) 
  → Challenge Period (10 blocks)
  → Approval Period
  → Result Approved
  → IDLE (0) + Wallet Created
```

## Quick Checklist

- [ ] Check current state: `./scripts/check-dkg-status.sh`
- [ ] Check approval timing: `./scripts/check-dkg-approval-status.sh`
- [ ] Check if timed out: `./scripts/check-dkg-timeout-details.sh`
- [ ] Check node connectivity: `./scripts/check-dkg-metrics.sh`
- [ ] Check logs for errors: `grep -i "error\|revert\|approve" logs/node*.log | tail -20`
- [ ] **Approve DKG result**: `./scripts/approve-dkg-result-complete.sh [config] [node]`
- [ ] Mine blocks if needed: `./scripts/mine-blocks-fast.sh [blocks]`
- [ ] Reset if timed out: `./scripts/reset-dkg.sh`

## Next Steps

1. **Run diagnostics**: `./scripts/check-dkg-approval-status.sh`
2. **Check logs**: Look for approval attempts and errors
3. **Verify timing**: Ensure challenge period has passed
4. **Check connectivity**: Ensure nodes can communicate
5. **Wait or reset**: Either wait for automatic retry or reset if timed out


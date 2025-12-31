# How to Proceed from CHALLENGE State

Now that the `walletOwner` issue is fixed, you can approve the DKG result and move forward from the CHALLENGE state.

## Overview

The DKG process has these states:
1. **IDLE** - No DKG in progress
2. **AWAITING_SEED** - Waiting for random beacon seed
3. **AWAITING_RESULT** - Waiting for DKG result submission
4. **CHALLENGE** - Result submitted, in challenge period

From CHALLENGE state, the result can be **approved** to complete the DKG and create the wallet.

## Prerequisites

✅ **Wallet Owner Fixed**: The `walletOwner` is now set to a contract (`SimpleWalletOwner`), so `approveDkgResult` will work.

## Methods to Proceed

### Method 1: Automatic Approval (Recommended)

The nodes automatically schedule and execute DKG result approvals. They will approve when:

1. **Challenge period ends** (typically 11,520 blocks ≈ 48 hours on mainnet, much faster locally)
2. **Precedence period ends** (for non-submitters)
3. **Scheduled block is reached**

**Check if nodes are scheduling approvals:**
```bash
# Check node logs for approval scheduling
grep -i "scheduling DKG result approval\|waiting for block.*to approve" logs/node*.log

# Monitor DKG state
./scripts/check-dkg-state.sh

# Monitor logs in real-time
tail -f logs/node*.log | grep -i "approve\|DKG"
```

**The nodes will automatically approve when eligible.** Just wait for the challenge period to end.

### Method 2: Manual Approval Using Existing Script

If you have the DKG result JSON (from logs or previous submission):

```bash
# Use the approve script
KEEP_ETHEREUM_PASSWORD=password ./scripts/approve

# Or use the approve-dkg-result script
./scripts/approve-dkg-result.sh
```

The `scripts/approve` file contains a complete DKG result JSON that was previously submitted.

### Method 3: Manual Approval via CLI

If you have the DKG result JSON:

```bash
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry approve-dkg-result '<DKG_RESULT_JSON>' \
  --submit --config configs/config.toml --developer
```

**To get the DKG result JSON:**
1. Check node logs: `grep -i "submitted.*dkg.*result" logs/node*.log`
2. Extract the JSON from the log entry
3. Use it in the approval command

### Method 4: Query and Approve via Hardhat

```bash
cd solidity/ecdsa
npx hardhat console --network development
```

Then in the console:
```javascript
const { ethers, helpers } = require("hardhat");
const wr = await helpers.contracts.getContract("WalletRegistry");

// Get submitted result hash
const submittedHash = await wr.submittedResultHash();
console.log("Submitted hash:", submittedHash);

// Get DKG state
const state = await wr.getDkgState();
console.log("DKG State:", state); // 3 = CHALLENGE

// Get DKG parameters
const params = await wr.dkgParameters();
console.log("Challenge period:", params.resultChallengePeriodLength.toString());
console.log("Precedence period:", params.submitterPrecedencePeriodLength.toString());

// Get submission block
const submissionBlock = await wr.submittedResultBlock();
console.log("Submission block:", submissionBlock.toString());

// Calculate when approval is possible
const currentBlock = await ethers.provider.getBlockNumber();
const challengeEnd = submissionBlock.add(params.resultChallengePeriodLength);
const precedenceEnd = challengeEnd.add(params.submitterPrecedencePeriodLength);

console.log("Current block:", currentBlock);
console.log("Challenge period ends at block:", challengeEnd.toString());
console.log("Precedence period ends at block:", precedenceEnd.toString());

if (currentBlock >= challengeEnd) {
  console.log("✓ Challenge period has ended - approval is possible");
} else {
  console.log("⏳ Need to wait", challengeEnd.sub(currentBlock).toString(), "more blocks");
}
```

## Important Notes

### Challenge Period Requirements

1. **Challenge period must end** before approval is possible
   - Default: 11,520 blocks (~48 hours on mainnet, ~3 hours locally)
   - Check: `submittedResultBlock + resultChallengePeriodLength`

2. **Submitter precedence**
   - The submitter can approve immediately after challenge period ends
   - Others must wait for precedence period to end
   - Default precedence: 5,760 blocks (~24 hours on mainnet)

3. **Result must match**
   - The approved result must exactly match the submitted result
   - Hash verification: `keccak256(abi.encode(result)) == submittedResultHash`

### What Happens After Approval

1. **DKG state changes** from `CHALLENGE` (3) to `IDLE` (0)
2. **Wallet is created** with the approved public key
3. **WalletCreated event** is emitted
4. **walletOwner callback** is called (now works because walletOwner is a contract!)

## Troubleshooting

### "execution reverted" Error

If you still get revert errors:
- ✅ **Fixed**: `walletOwner` is now a contract (no more `extcodesize` errors)
- Check: `walletOwner` should be `0xeD641368ACAD4460A158C43cB62D94FaD15D0FDC` (SimpleWalletOwner)

### Challenge Period Not Ended

If approval fails with "Challenge period has not passed yet":
- Wait for more blocks to be mined
- Check current block vs. `submittedResultBlock + resultChallengePeriodLength`
- On local dev: blocks mine quickly, so wait a few minutes

### Result Hash Mismatch

If approval fails with "Result under approval is different":
- The DKG result JSON must exactly match what was submitted
- Extract the exact JSON from logs
- Don't modify the JSON structure

## Quick Check Commands

```bash
# Check current DKG state
./scripts/check-dkg-state.sh

# Check if nodes are scheduling approvals
grep -i "scheduling.*approval\|waiting.*approve" logs/node*.log

# Monitor DKG progress
tail -f logs/node*.log | grep -i "dkg\|approve\|challenge"

# Check challenge period status
./scripts/check-dkg-timing.sh

# Check DKG metrics
./scripts/check-dkg-metrics.sh
```

## Summary

**Recommended approach**: Let the nodes handle approval automatically. They will:
1. Detect the DKG result submission
2. Schedule approval for the appropriate block
3. Execute approval when eligible
4. Complete the DKG and create the wallet

Just monitor the logs and state to see when it completes!

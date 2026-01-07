# How DKG Result Approval Works

## Overview

DKG (Distributed Key Generation) result approval is the final step in the DKG process. After a DKG result is submitted on-chain, it enters a **CHALLENGE** state where it can be challenged if invalid, or approved if valid. Once approved, the DKG process completes and the wallet becomes active.

## DKG State Flow

```
IDLE → AWAITING_SEED → AWAITING_RESULT → CHALLENGE → IDLE (approved)
                                    ↓
                              (if challenged)
                              AWAITING_RESULT
```

## Approval Process Timeline

### 1. Result Submission
- A DKG participant submits the DKG result on-chain
- The contract stores:
  - The result hash (`keccak256(abi.encode(result))`)
  - The submission block number
  - The DKG state changes to `CHALLENGE`

### 2. Challenge Period
- **Duration**: `resultChallengePeriodLength` blocks (default: 10 blocks in development)
- **Purpose**: Allows any participant to challenge invalid results
- **During this period**: 
  - ❌ Approval is **NOT** allowed
  - ✅ Challenges are allowed
  - If challenged, DKG returns to `AWAITING_RESULT` state

**Timing:**
```
Submission Block: N
Challenge Period End: N + resultChallengePeriodLength
```

### 3. Submitter Precedence Period
- **Duration**: `submitterPrecedencePeriodLength` blocks (default: 5 blocks in development)
- **Purpose**: Gives the submitter priority to approve first
- **During this period**:
  - ✅ **Only the submitter** can approve
  - ❌ Other members cannot approve yet

**Timing:**
```
Challenge Period End: N + resultChallengePeriodLength
Precedence Period Start: N + resultChallengePeriodLength + 1
Precedence Period End: N + resultChallengePeriodLength + submitterPrecedencePeriodLength
```

### 4. General Approval Period
- **After precedence period ends**: Any eligible member can approve
- **Staggered delays**: Each member waits additional blocks based on their member index to avoid simultaneous approvals
- **Delay formula**: `(memberIndex - 1) * 15 blocks`

**Timing for non-submitter member M:**
```
Approval Block = Precedence Period End + (M - 1) * 15
```

## Contract Requirements

The `approveResult` function in `EcdsaDkg.sol` enforces these checks:

### 1. State Check
```solidity
require(
    currentState(self) == State.CHALLENGE,
    "Current state is not CHALLENGE"
);
```
- DKG must be in `CHALLENGE` state

### 2. Challenge Period Check
```solidity
uint256 challengePeriodEnd = self.submittedResultBlock +
    self.parameters.resultChallengePeriodLength;

require(
    block.number > challengePeriodEnd,
    "Challenge period has not passed yet"
);
```
- Current block must be **greater than** challenge period end
- Note: Uses `>` not `>=`, so approval is possible starting at `challengePeriodEnd + 1`

### 3. Result Hash Match
```solidity
require(
    keccak256(abi.encode(result)) == self.submittedResultHash,
    "Result under approval is different than the submitted one"
);
```
- **Critical**: The result being approved must **exactly match** the submitted result
- The hash is calculated as `keccak256(abi.encode(result))` where `result` is a tuple:
  ```solidity
  tuple(
      uint256 submitterMemberIndex,
      bytes groupPubKey,
      uint8[] misbehavedMembersIndices,
      bytes signatures,
      uint256[] signingMembersIndices,
      uint32[] members,
      bytes32 membersHash
  )
  ```
- **Common failure**: Local DKG result doesn't match on-chain submitted result

### 4. Submitter Precedence Check
```solidity
address submitterMember = self.sortitionPool.getIDOperator(
    result.members[result.submitterMemberIndex - 1]
);

require(
    msg.sender == submitterMember ||
        block.number >
        challengePeriodEnd +
            self.parameters.submitterPrecedencePeriodLength,
    "Only the DKG result submitter can approve the result at this moment"
);
```
- If within precedence period: Only submitter can approve
- After precedence period: Anyone can approve

## Node Implementation

### Automatic Approval Scheduling

Each node that participated in the DKG automatically schedules approval:

1. **Validates the result** locally
2. **If valid**: Schedules approval based on member index
3. **If invalid**: Submits a challenge instead

### Approval Timing Logic

```go
// Challenge period ends
challengePeriodEndBlock := submissionBlock + parameters.ChallengePeriodBlocks

// Submitter can approve starting here
approvePrecedencePeriodStartBlock := challengePeriodEndBlock + 1

// Others can approve starting here
approvePeriodStartBlock := approvePrecedencePeriodStartBlock +
    parameters.ApprovePrecedencePeriodBlocks

if memberIndex == result.SubmitterMemberIndex {
    // Submitter: approve at precedence period start
    approveBlock = approvePrecedencePeriodStartBlock
} else {
    // Others: approve after precedence + delay based on member index
    delayBlocks := uint64(memberIndex-1) * 15
    approveBlock = approvePeriodStartBlock + delayBlocks
}
```

### Example Timeline

**Assumptions:**
- Submission block: 1494
- Challenge period: 10 blocks
- Precedence period: 5 blocks
- Member 1 is submitter

**Timeline:**
```
Block 1494: Result submitted → State: CHALLENGE
Block 1504: Challenge period ends
Block 1505: Precedence period starts
  - Member 1 (submitter) can approve at block 1505
Block 1509: Precedence period ends
  - Member 2 can approve at block 1509 + (2-1)*15 = 1524
  - Member 3 can approve at block 1509 + (3-1)*15 = 1539
  - Member 63 can approve at block 1509 + (63-1)*15 = 2439
```

## Common Issues

### 1. "execution reverted" Error

This generic error means one of the require statements failed. Common causes:

**a) Result Hash Mismatch** (Most Common)
- **Cause**: Local DKG result doesn't match on-chain submitted result
- **Why**: Nodes use their local DKG result, which may have slight differences
- **Solution**: Use the **exact result from the on-chain event**

**b) Wrong Account**
- **Cause**: Account doesn't match submitter or precedence period hasn't passed
- **Solution**: Use submitter's account during precedence period, or wait for precedence period to end

**c) State Not CHALLENGE**
- **Cause**: DKG is in wrong state (already approved, challenged, etc.)
- **Solution**: Check current state first

**d) Challenge Period Not Passed**
- **Cause**: Trying to approve before challenge period ends
- **Solution**: Wait for `block.number > challengePeriodEnd`

### 2. Nodes Failing to Approve Automatically

**Symptoms:**
- Logs show: `[member:X] cannot approve DKG result: [execution reverted]`
- Multiple nodes trying but all failing

**Root Cause:**
- Nodes use their **local DKG result** which may not exactly match the **on-chain submitted result**
- Even tiny differences (e.g., byte ordering, encoding) cause hash mismatch

**Why This Happens:**
- DKG result submission uses the submitter's local result
- Other nodes may have slightly different internal representations
- The contract requires **exact match** via hash comparison

**Solution:**
- Use the **exact result from the `DkgResultSubmitted` event**
- Extract it from on-chain events, not from local DKG state

## Manual Approval Process

### Step 1: Get Exact Result from Event

```typescript
const filter = wr.filters.DkgResultSubmitted();
const events = await wr.queryFilter(filter, -2000);
const latestEvent = events[events.length - 1];
const result = latestEvent.args.result; // Use THIS exact result
```

### Step 2: Verify Hash Matches

```typescript
const resultHash = ethers.utils.keccak256(
  ethers.utils.defaultAbiCoder.encode(
    ["tuple(uint256,bytes,uint8[],bytes,uint256[],uint32[],bytes32)"],
    [[
      result.submitterMemberIndex,
      result.groupPubKey,
      result.misbehavedMembersIndices,
      result.signatures,
      result.signingMembersIndices,
      result.members,
      result.membersHash
    ]]
  )
);

// Must match event's resultHash
assert(resultHash === latestEvent.args.resultHash);
```

### Step 3: Check Timing

```typescript
const currentBlock = await ethers.provider.getBlockNumber();
const params = await wr.dkgParameters();
const challengePeriodEnd = submissionBlock + params.resultChallengePeriodLength;
const precedencePeriodEnd = challengePeriodEnd + params.submitterPrecedencePeriodLength;

// Must be past challenge period
assert(currentBlock > challengePeriodEnd);

// If not submitter, must be past precedence period
if (msg.sender !== submitterAddress) {
  assert(currentBlock > precedencePeriodEnd);
}
```

### Step 4: Approve

```go
// Using keep-client CLI
./keep-client --config configs/node2.toml \
  ethereum ecdsa wallet-registry approve-dkg-result \
  "$(cat /tmp/dkg-result.json)" \
  --submit --developer
```

## JSON Format for CLI

The `keep-client` CLI expects JSON matching the Go struct:

```json
{
  "SubmitterMemberIndex": 1,
  "GroupPubKey": "base64-encoded-bytes",
  "MisbehavedMembersIndices": [],
  "Signatures": "base64-encoded-bytes",
  "SigningMembersIndices": [1, 2, 3, ...],
  "Members": [123, 456, 789, ...],
  "MembersHash": [244, 174, 86, ...]  // Array of 32 numbers (0-255)
}
```

**Important Notes:**
- `GroupPubKey` and `Signatures`: Base64-encoded strings (Go decodes to `[]byte`)
- `SigningMembersIndices`: Array of numbers (Go converts to `[]*big.Int`)
- `MembersHash`: Array of exactly 32 numbers (Go converts to `[32]byte`)
- `SubmitterMemberIndex`: Number (Go converts to `*big.Int`)

## Why Approval Can Fail

### Hash Mismatch (Most Common)

The contract calculates the hash as:
```solidity
keccak256(abi.encode(result))
```

This requires **exact** match of:
- Field order
- Data types
- Byte encoding
- Array ordering

Even if the data is logically the same, encoding differences cause hash mismatch.

### Example: Why Local Result Might Differ

1. **Byte ordering**: Local result might have different byte order
2. **Array sorting**: Signing members indices might be sorted differently
3. **Encoding**: Different serialization methods
4. **Precision**: BigNumber vs number conversions

### Solution: Always Use Event Result

The `DkgResultSubmitted` event contains the **exact** result that was submitted. Use this, not your local DKG result.

## Best Practices

1. **Always verify hash** before attempting approval
2. **Use event result**, not local DKG result
3. **Check timing** - ensure challenge/precedence periods have passed
4. **Use submitter account** during precedence period for fastest approval
5. **Monitor logs** - nodes will automatically retry if they fail

## Monitoring Approval

### Check Current State
```bash
cd solidity/ecdsa
npx hardhat run scripts/check-dkg-status.ts --network development
```

### Check Approval Status
```bash
cd solidity/ecdsa
npx hardhat run scripts/check-dkg-approval-status.ts --network development
```

### Monitor Node Logs
```bash
tail -f logs/node*.log | grep -i "approve\|challenge"
```

## Summary

DKG result approval is a **two-phase process**:

1. **Challenge Period** (10 blocks): No approvals allowed, challenges only
2. **Approval Period**:
   - **Precedence Period** (5 blocks): Only submitter can approve
   - **General Period**: Anyone can approve, with staggered delays

**Key Requirements:**
- ✅ State must be `CHALLENGE`
- ✅ Challenge period must have passed
- ✅ Result hash must **exactly match** submitted result
- ✅ Account must be submitter OR precedence period must have passed

**Common Failure:**
- Result hash mismatch because local result doesn't match on-chain result
- **Solution**: Always use the exact result from the `DkgResultSubmitted` event


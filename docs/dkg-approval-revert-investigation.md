# DKG Approval Revert Investigation

## Summary

Multiple members (1, 26, 34) are experiencing "execution reverted" errors when attempting to approve a DKG result that was submitted at block 862.

## Current State

- **Contract State**: CHALLENGE (3) ✓
- **Current Block**: ~1421
- **Submission Block**: 862
- **Result Hash**: `0x4020d2456623b188c9f5a0692e0938fbf59658b8f7f89a1b743db7c416ff822e`
- **DKG Parameters**:
  - Challenge Period: 8 blocks
  - Precedence Period: 10 blocks
  - Submission Timeout: 50000 blocks
  - Seed Timeout: 120 blocks

## Approval Timeline

- **Submission Block**: 862
- **Challenge Period End**: 870 (862 + 8)
- **Precedence Period Start**: 871 (870 + 1)
- **Precedence Period End**: 881 (871 + 10)
- **General Approval Start**: 882 (881 + 1)

At block 1421, we are well past the general approval period, so timing is not the issue.

## Root Cause Analysis

### Possible Causes

1. **Result Hash Mismatch** (MOST LIKELY)
   - The contract checks: `keccak256(abi.encode(result)) == self.submittedResultHash`
   - If the result structure being approved doesn't exactly match what was submitted, the approval will revert
   - The error message would be: "Result under approval is different than the submitted one"

2. **State Inconsistency**
   - `submittedResultBlock()` call is reverting, suggesting internal state inconsistency
   - However, state is still CHALLENGE, which is correct

3. **Member Eligibility**
   - During precedence period (blocks 871-881), only submitter can approve
   - After block 882, anyone can approve
   - Member 1 is the submitter, so this shouldn't be an issue

4. **Code Version Mismatch**
   - Logs show warning: "failed to approve using ABI result, falling back to legacy method"
   - This code doesn't exist in current source, suggesting running binary differs from source

## Smart Contract Requirements

From `EcdsaDkg.sol::approveResult()`:

```solidity
require(
    currentState(self) == State.CHALLENGE,
    "Current state is not CHALLENGE"
);

require(
    block.number > challengePeriodEnd,
    "Challenge period has not passed yet"
);

require(
    keccak256(abi.encode(result)) == self.submittedResultHash,
    "Result under approval is different than the submitted one"
);

require(
    msg.sender == submitterMember ||
        block.number > challengePeriodEnd + self.parameters.submitterPrecedencePeriodLength,
    "Only the DKG result submitter can approve the result at this moment"
);
```

## Diagnostic Steps

### 1. Verify Result Hash Match

The result hash from the event matches the expected hash:
- Event Hash: `0x4020d2456623b188c9f5a0692e0938fbf59658b8f7f89a1b743db7c416ff822e`
- Expected Hash: `0x4020d2456623b188c9f5a0692e0938fbf59658b8f7f89a1b743db7c416ff822e`
- ✓ **Hashes match**

### 2. Check Contract State

```bash
# Check state
cast call 0xd49141e044801DEE237993deDf9684D59fafE2e6 \
  "getWalletCreationState()(uint8)" \
  --rpc-url http://localhost:8545

# Result: 3 (CHALLENGE) ✓
```

### 3. Verify Timing

Current block (1421) is well past:
- Challenge period end (870)
- Precedence period end (881)
- General approval start (882)

✓ **Timing is correct**

## Most Likely Issue

**Result encoding mismatch**: The DKG result being passed to `approveDkgResult()` doesn't produce the same hash as what was submitted. This could be due to:

1. **Field ordering differences** in ABI encoding
2. **Data type mismatches** (e.g., uint8 vs uint256)
3. **Array ordering** (misbehaved members, signing members, etc.)
4. **Public key encoding** differences
5. **Members hash calculation** differences

## Recommendations

### Immediate Actions

1. **Add detailed logging** to capture the exact result structure being approved
2. **Compare the result structure** used for submission vs approval
3. **Verify ABI encoding** matches between submission and approval
4. **Check if result data changed** between submission and approval attempts

### Code Investigation

1. Verify `convertDkgResultToAbiType()` produces identical encoding to submission
2. Check if result data is being modified between submission and approval
3. Ensure all arrays are sorted consistently (misbehaved members, signing members)
4. Verify public key encoding matches exactly

### Debugging Scripts

Use the provided scripts:
- `scripts/check-dkg-approval-state.sh` - Check current contract state
- `scripts/diagnose-dkg-approval-revert.sh` - Comprehensive diagnosis
- `scripts/check-submitted-result-hash.sh` - Verify result hash

### Next Steps

1. **Enable trace logging** to see the exact revert reason from the contract
2. **Compare result structures** byte-by-byte between submission and approval
3. **Test with a known-good result** to isolate the issue
4. **Check for any result mutations** between submission and approval

## Related Files

- `pkg/tbtc/dkg.go:765` - Approval call
- `pkg/chain/ethereum/tbtc.go:971` - ApproveDKGResult implementation
- `pkg/chain/ethereum/tbtc.go:594` - convertDkgResultToAbiType
- `solidity/ecdsa/contracts/libraries/EcdsaDkg.sol:327` - approveResult function

## Error Pattern

All failing members show the same pattern:
1. Wait for their assigned approval block
2. Attempt approval
3. Get "execution reverted" error
4. No approval event emitted

This suggests a systematic issue with the result encoding rather than member-specific problems.



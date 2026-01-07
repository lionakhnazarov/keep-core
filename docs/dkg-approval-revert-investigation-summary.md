# DKG Approval Revert Investigation Summary

## Problem
DKG approval transactions are reverting with empty error data (`0x`), making it difficult to diagnose the root cause.

## Investigation Findings

### Contract State
- **Current State**: `CHALLENGE` (3) ✓
- **SortitionPool**: Locked ✓
- **Challenge Period**: 8 blocks
- **Precedence Period**: 10 blocks
- **Current Block**: 1886
- **Submission Block**: 862
- **Challenge Period End**: Block 870 (862 + 8)
- **Precedence Period End**: Block 880 (870 + 10)

### DKG Result Validation
- **Submitter Member Index**: 1 ✓ (valid, range is 1-100)
- **Total Members**: 100
- **Misbehaved Members**: 0 (no array access issues)
- **Signing Members**: 100
- **Result Hash**: `0x4020d2456623b188c9f5a0692e0938fbf59658b8f7f89a1b743db7c416ff822e`
- **Array Bounds**: All indices are valid ✓

### Contract Components Status
- **WalletRegistry**: `0xd49141e044801DEE237993deDf9684D59fafE2e6` ✓
- **SortitionPool**: `0x88b2480f0014ED6789690C1c4F35Fc230ef83458` (Locked) ✓
- **WalletOwner**: `0xc0a2ee534F004a4ec2EFA541489acBD5ff4bBA99` (Contract) ✓
- **ReimbursementPool**: `0x1E2C06EEf15A4cD7fc9712267b55cB5337dCf75a` (Not a contract?) ⚠️

### Revert Analysis

The `approveDkgResult` function executes these steps in order:

1. ✅ `dkg.approveResult(dkgResult)` - **PASSES** (would have error message if failed)
   - State check: CHALLENGE ✓
   - Challenge period check: Passed ✓
   - Result hash match: Matches ✓
   - Submitter precedence check: Passed ✓
   - Array bounds: All valid ✓

2. ✅ `wallets.addWallet(...)` - **Storage write** (shouldn't revert)

3. ✅ `emit WalletCreated(...)` - **Event emission** (shouldn't revert)

4. ⏭️ `sortitionPool.setRewardIneligibility(...)` - **SKIPPED** (misbehavedMembers.length = 0)

5. ⚠️ `walletOwner.__ecdsaWalletCreatedCallback(...)` - **EXTERNAL CALL** ⚠️
   - This is the most likely revert point
   - External calls can revert without error messages
   - WalletOwner is a contract with code

6. ⏭️ `dkg.complete()` - **Not reached** (if callback reverts)

7. ⏭️ `reimbursementPool.refund(...)` - **Not reached** (if callback reverts)

### Root Cause Hypothesis

**Most Likely**: The `walletOwner.__ecdsaWalletCreatedCallback()` external call is reverting.

**Why empty revert (0x)?**
- External calls that revert without a custom error string return empty data
- The WalletOwner contract might have an internal failure (assert, array bounds, etc.)
- The callback might be checking some state that causes it to revert

**Alternative Possibilities**:
1. **ReimbursementPool issue**: The ReimbursementPool address doesn't appear to be a contract (no code), but this wouldn't cause a revert until after the callback
2. **Gas exhaustion**: Unlikely, but possible if the callback consumes too much gas
3. **State inconsistency**: Some internal state in WalletOwner might be inconsistent

## Next Steps

1. **Test WalletOwner callback directly**:
   ```bash
   # Calculate walletID from groupPubKey
   walletID = keccak256(groupPubKey)
   # Call the callback directly to see if it reverts
   cast call 0xc0a2ee534F004a4ec2EFA541489acBD5ff4bBA99 \
     "__ecdsaWalletCreatedCallback(bytes32,bytes32,bytes32)" \
     <walletID> <publicKeyX> <publicKeyY> \
     --rpc-url http://localhost:8545
   ```

2. **Check WalletOwner contract implementation**:
   - Find the actual WalletOwner contract code
   - Review what `__ecdsaWalletCreatedCallback` does
   - Check for any state checks or conditions that could cause reverts

3. **Use debug_traceCall**:
   - Enable debug APIs on the local geth node
   - Use `debug_traceCall` to get exact execution trace
   - Identify the exact opcode where the revert occurs

4. **Check ReimbursementPool**:
   - Verify if ReimbursementPool is actually deployed
   - Check if it's supposed to be a contract or EOA

## Files Created

- `scripts/investigate-contract-state.sh` - Comprehensive state investigation
- `scripts/test-approval-steps.sh` - Step-by-step approval testing
- `solidity/ecdsa/scripts/decode-event-and-test.ts` - TypeScript script to decode and test DKG result
- `docs/dkg-approval-revert-investigation-summary.md` - This summary

## Key Observations

1. ✅ All array bounds are valid (no underflow/overflow)
2. ✅ DKG state is correct (CHALLENGE)
3. ✅ Challenge period has passed
4. ✅ Result hash matches
5. ⚠️ External WalletOwner callback is the most likely failure point
6. ⚠️ Empty revert suggests assert() or external call revert without message


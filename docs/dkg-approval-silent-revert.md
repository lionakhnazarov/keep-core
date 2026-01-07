# DKG Approval Silent Revert Issue

## Problem
The `approveDkgResult()` function reverts silently (no error data) even though:
- ✅ Encoding matches: Struct encoding from event matches original submission
- ✅ Hash matches: Computed hash matches stored hash (`0xa4c691f074124bfbce638356b4c89d4d2d1966b0e29faa7f3ef9ed5fce7b4d75`)
- ✅ Timing correct: Challenge period ended, precedence period ended
- ✅ Callback works: BridgeStub callback function is functional

## Investigation Results

### Encoding Verification
- Created `trace-approval-encoding.ts` to compare submission vs approval encoding
- **Result**: Struct encodings match exactly
- **Result**: Hashes match exactly

### Hash Verification  
- Created `debug-hash-mismatch.ts` to test different struct field orders
- **Result**: Correct order is: `submitterMemberIndex, groupPubKey, misbehavedMembersIndices, signatures, signingMembersIndices, members, membersHash` (membersHash LAST)
- **Result**: This order produces the correct hash

### Timing Verification
- Challenge period ends at block: 692
- Precedence period ends at block: 697  
- Current block: 5235
- **Result**: Timing is correct - anyone can approve

### Callback Verification
- Created `test-wallet-owner-callback.ts` to test BridgeStub callback
- **Result**: Callback executes successfully

## Possible Causes

1. **Hash Check Failure**: Despite matching encoding, Solidity's `abi.encode()` might produce different results than Hardhat's encoder in some edge case
2. **Other Validation**: There might be another check in `approveResult()` that's failing silently
3. **Gas Limit**: Unlikely but possible - transaction might be running out of gas

## Code References

### approveResult() checks (EcdsaDkg.sol:327-379)
```solidity
require(currentState(self) == State.CHALLENGE, "Current state is not CHALLENGE");
require(block.number > challengePeriodEnd, "Challenge period has not passed yet");
require(keccak256(abi.encode(result)) == self.submittedResultHash, "Result under approval is different than the submitted one");
require(msg.sender == submitterMember || block.number > precedenceEnd, "Only the DKG result submitter can approve the result at this moment");
```

### approveDkgResult() flow (WalletRegistry.sol:729-761)
1. Calls `dkg.approveResult(dkgResult)` - this is where the revert happens
2. Adds wallet: `wallets.addWallet(...)`
3. Emits `WalletCreated` event
4. Sets reward ineligibility if needed
5. Calls `walletOwner.__ecdsaWalletCreatedCallback(...)` - verified working
6. Completes DKG: `dkg.complete()`
7. Refunds gas

## Next Steps

1. **Trace Transaction**: Use `cast run` or Hardhat's trace to see exact revert point
2. **Check Stored Hash**: Verify the hash stored in the contract matches what we computed
3. **Manual Encoding Test**: Try encoding the struct manually using Solidity's exact ABI definition
4. **Check for Custom Errors**: The contract might be using custom errors instead of require strings

## Scripts Created

- `solidity/ecdsa/scripts/trace-approval-encoding.ts` - Compare encodings
- `solidity/ecdsa/scripts/decode-approval-revert.ts` - Decode revert reason
- `solidity/ecdsa/scripts/approve-dkg-manual-encode.ts` - Manual encoding test
- `solidity/ecdsa/scripts/test-wallet-owner-callback.ts` - Test callback

## Current Status

**BLOCKED**: Approval reverts silently despite all checks passing. Need to trace the exact revert point to identify the root cause.


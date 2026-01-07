# DKG Result Hash Mismatch Issue

## Problem Summary

DKG approval is failing because the hash of the reconstructed DKG result doesn't match the hash stored in the contract when the result was submitted.

**Symptoms:**
- DKG stuck in CHALLENGE state (state 3)
- Nodes repeatedly trying to approve but failing with "execution reverted"
- Error: "failed to approve using ABI result, falling back to legacy method"
- Both ABI and legacy approval methods fail

**Root Cause:**
The contract stores the hash as `keccak256(abi.encode(result))` when the result is submitted. When nodes try to approve, they reconstruct the result using `AssembleDKGResult()`, but the hash of the reconstructed result doesn't match the stored hash.

**Stored Hash:** `0xa4c691f074124bfbce638356b4c89d4d2d1966b0e29faa7f3ef9ed5fce7b4d75`  
**Computed Hash (from event):** `0xb9178005cc73169fcb82f7a2f0fa3f18b0572830846a81e9bb2d69c019c69221`

## Root Cause Identified ✅

**The issue is struct field order mismatch!**

The DKG Result struct has this field order:
1. `uint256 submitterMemberIndex`
2. `bytes groupPubKey`
3. `uint8[] misbehavedMembersIndices`
4. `bytes signatures`
5. `uint256[] signingMembersIndices`
6. `uint32[] members`
7. `bytes32 membersHash` **← LAST!**

When encoding with `abi.encode()`, **`membersHash` must be the LAST field**, not third.

**What was happening:**
- Contract stores hash correctly: `keccak256(abi.encode(result))` with correct order
- Nodes reconstruct result but encode with `membersHash` in wrong position (likely third)
- Hash doesn't match → approval fails

**Proof:**
- Wrong order (membersHash third): `0xb9178005cc73169fcb82f7a2f0fa3f18b0572830846a81e9bb2d69c019c69221` ❌
- Correct order (membersHash last): `0xa4c691f074124bfbce638356b4c89d4d2d1966b0e29faa7f3ef9ed5fce7b4d75` ✅

## Other Possible Causes (Not the Issue)

1. ~~Array Type Mismatch~~: `misbehavedMembersIndices` is correctly `uint8[]`
2. ~~Array Ordering~~: Arrays are in correct order
3. ~~Signature Concatenation~~: Signatures are correct
4. ~~Event Decoding~~: Event data matches transaction data exactly

## Workarounds (Without Fixing Node Code)

### Option 1: Approve Using Event Data Directly

Use the exact result structure from the submission event to approve:

```bash
cd solidity/ecdsa
npx hardhat run scripts/approve-dkg-from-event.ts --network development
```

Or use the convenience script:

```bash
./scripts/approve-dkg-from-event.sh
```

This script:
- Extracts the exact DKG result from the submission event
- Uses that exact structure to approve (bypassing reconstruction)
- Should work because it uses the same data that was submitted

### Option 2: Check Timing

Ensure the challenge and precedence periods have passed:

```bash
# Check current DKG state
KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry get-wallet-creation-state --config configs/node1.toml --developer

# Check current block
cast block-number --rpc-url http://localhost:8545

# Mine blocks if needed
./scripts/mine-blocks-fast.sh <number-of-blocks>
```

### Option 3: Reset DKG (Last Resort)

If approval continues to fail, reset the DKG:

```bash
./scripts/reset-dkg-from-challenge.sh
```

**Note:** This will lose the current DKG result and require starting a new DKG.

## Diagnosis Scripts

### Check Hash Mismatch

```bash
cd solidity/ecdsa
npx hardhat run scripts/check-dkg-result-hash.ts --network development
```

This script:
- Compares the stored hash with the hash computed from event data
- Shows the exact result structure
- Helps identify what's different

### Check WalletOwner Callback

```bash
cd solidity/ecdsa
npx hardhat run scripts/test-wallet-owner-callback.ts --network development
```

This verifies the callback function is working (it is - the issue is hash mismatch).

## Node Code Fix (For Future)

The proper fix is in the Go code to ensure `convertDkgResultToAbiType()` encodes the result with the **correct field order**.

**The fix:**
Ensure when encoding the DKG result struct, `membersHash` is placed **LAST**, not third.

**Correct field order for encoding:**
```go
// Correct order:
1. submitterMemberIndex
2. groupPubKey
3. misbehavedMembersIndices
4. signatures
5. signingMembersIndices
6. members
7. membersHash  // ← MUST BE LAST!
```

**Files to fix:**
- `pkg/chain/ethereum/tbtc.go` - `convertDkgResultToAbiType()` function
  - Check how the struct is being encoded
  - Ensure `membersHash` is the last field in the tuple encoding

**Current issue:**
The encoding likely has `membersHash` in the wrong position (probably third), causing hash mismatch.

## Current Status

- ✅ WalletOwner callback is working
- ✅ Challenge period has passed
- ✅ Precedence period has passed (or will pass soon)
- ❌ Hash mismatch preventing approval
- ✅ Workaround script available (`approve-dkg-from-event.ts`)

## Next Steps

1. **Immediate**: Use `approve-dkg-from-event.ts` to approve using event data
2. **Short-term**: Investigate why hash doesn't match (check array types, ordering)
3. **Long-term**: Fix `AssembleDKGResult()` to match submission encoding exactly


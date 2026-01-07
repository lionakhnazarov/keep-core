# DKG Approval - Next Steps

## Problem Identified ✅

✅ **Root Cause Found**: Struct field order mismatch in encoding

**The Issue:**
- DKG Result struct has `membersHash` as the **LAST** field (7th position)
- When encoding with `abi.encode()`, `membersHash` must be last
- Nodes are encoding with `membersHash` in wrong position (likely 3rd)
- This causes hash mismatch

**Proof:**
- Wrong order (membersHash 3rd): `0xb9178005cc73169fcb82f7a2f0fa3f18b0572830846a81e9bb2d69c019c69221` ❌
- Correct order (membersHash last): `0xa4c691f074124bfbce638356b4c89d4d2d1966b0e29faa7f3ef9ed5fce7b4d75` ✅

**Correct Struct Field Order:**
1. `uint256 submitterMemberIndex`
2. `bytes groupPubKey`
3. `uint8[] misbehavedMembersIndices`
4. `bytes signatures`
5. `uint256[] signingMembersIndices`
6. `uint32[] members`
7. `bytes32 membersHash` ← **MUST BE LAST!**

✅ **WalletOwner Callback**: Working correctly (not the issue)

## Immediate Action: Approve Using Event Data

**Use the workaround script to approve immediately:**

```bash
./scripts/approve-dkg-from-event.sh
```

This bypasses the hash mismatch by using the exact result structure from the submission event.

## Available Tools

### 1. Approval Script (Workaround)
**File**: `scripts/approve-dkg-from-event.sh`  
**Purpose**: Approve DKG using exact event data  
**Usage**: `./scripts/approve-dkg-from-event.sh`

### 2. Diagnosis Script
**File**: `scripts/diagnose-dkg-approval.sh`  
**Purpose**: Comprehensive DKG approval diagnosis  
**Usage**: `./scripts/diagnose-dkg-approval.sh [config-file]`

### 3. Hash Check Script
**File**: `solidity/ecdsa/scripts/check-dkg-result-hash.ts`  
**Purpose**: Compare stored hash vs computed hash  
**Usage**: `cd solidity/ecdsa && npx hardhat run scripts/check-dkg-result-hash.ts --network development`

### 4. Callback Test Script
**File**: `solidity/ecdsa/scripts/test-wallet-owner-callback.ts`  
**Purpose**: Verify WalletOwner callback works  
**Usage**: `cd solidity/ecdsa && npx hardhat run scripts/test-wallet-owner-callback.ts --network development`

## Documentation Created

1. **`docs/dkg-hash-mismatch-issue.md`**
   - Detailed explanation of the problem
   - Possible causes
   - Workarounds
   - Future fix guidance

2. **`docs/dkg-approval-quick-fix.md`**
   - Quick reference guide
   - Step-by-step instructions
   - Prerequisites

3. **`docs/dkg-approval-next-steps.md`** (this file)
   - Summary of next steps
   - Available tools
   - Action items

## Fix Needed (For Node Code)

✅ **Root Cause Identified**: Struct field order in encoding

**The Fix:**
In `pkg/chain/ethereum/tbtc.go`, function `convertDkgResultToAbiType()`:
- Ensure when encoding the struct tuple, `membersHash` is the **LAST** field
- Current code likely has `membersHash` in wrong position (probably 3rd)

**Correct encoding order:**
```go
// When creating the ABI struct/tuple, ensure this order:
1. submitterMemberIndex (uint256)
2. groupPubKey (bytes)
3. misbehavedMembersIndices (uint8[])
4. signatures (bytes)
5. signingMembersIndices (uint256[])
6. members (uint32[])
7. membersHash (bytes32)  // ← MUST BE LAST!
```

**File to fix:**
- `pkg/chain/ethereum/tbtc.go` - `convertDkgResultToAbiType()` function
  - Find where the struct is encoded for ABI
  - Ensure `membersHash` is last in the tuple/struct encoding

**Debug script confirms:**
- Run `solidity/ecdsa/scripts/debug-hash-mismatch.ts` to verify the fix
- It shows which encoding matches the stored hash

## Action Items

### Immediate (Use Workaround)
- [x] Create approval script using event data
- [x] Create diagnosis scripts
- [x] Create documentation
- [ ] Run approval script to unblock DKG

### Short-term (Investigation)
- [ ] Compare submission vs approval encoding
- [ ] Check array type handling (`uint8[]` vs `uint32[]`)
- [ ] Verify array ordering consistency
- [ ] Test hash computation with different inputs

### Long-term (Fix Node Code)
- [ ] Fix `AssembleDKGResult()` to match submission encoding
- [ ] Add tests to prevent regression
- [ ] Document encoding requirements

## Testing the Fix

After fixing node code, verify:

1. Nodes can approve DKG results successfully
2. Hash matches between submission and approval
3. No "execution reverted" errors
4. Wallet creation completes successfully

## Notes

- The workaround script (`approve-dkg-from-event.ts`) should work immediately
- It uses the exact same data structure from the event, so hash will match
- This is a temporary solution until node code is fixed
- The issue is in result reconstruction, not in the contract or callback


# DKG Hash Mismatch - Root Cause Analysis

## ✅ Root Cause Identified

**Issue**: Struct field order mismatch when encoding DKG result for approval.

## The Problem

When nodes try to approve a DKG result, they reconstruct it and encode it using `abi.encode()`. However, the field order in the encoding doesn't match what was used during submission.

### Correct Struct Field Order

The `DKG.Result` struct in Solidity has this order:

```solidity
struct Result {
    uint256 submitterMemberIndex;        // 1
    bytes groupPubKey;                    // 2
    uint8[] misbehavedMembersIndices;    // 3
    bytes signatures;                     // 4
    uint256[] signingMembersIndices;     // 5
    uint32[] members;                     // 6
    bytes32 membersHash;                  // 7 ← MUST BE LAST!
}
```

### What Was Happening

**During Submission:**
- Contract correctly encodes: `keccak256(abi.encode(result))` with `membersHash` LAST
- Stored hash: `0xa4c691f074124bfbce638356b4c89d4d2d1966b0e29faa7f3ef9ed5fce7b4d75` ✅

**During Approval (Nodes):**
- Nodes reconstruct result via `AssembleDKGResult()`
- Convert to ABI type via `convertDkgResultToAbiType()`
- Encode with `membersHash` in wrong position (likely third)
- Computed hash: `0xb9178005cc73169fcb82f7a2f0fa3f18b0572830846a81e9bb2d69c019c69221` ❌
- Hash mismatch → approval fails

## Proof

Debug script (`debug-hash-mismatch.ts`) confirms:

```
Test 1: Correct order (membersHash LAST)
  Hash: 0xa4c691f074124bfbce638356b4c89d4d2d1966b0e29faa7f3ef9ed5fce7b4d75
  Match: ✅ YES - FOUND IT!

Test 1b: Wrong order (membersHash third)
  Hash: 0xb9178005cc73169fcb82f7a2f0fa3f18b0572830846a81e9bb2d69c019c69221
  Match: ❌ NO
```

## Solution

### Immediate Workaround

Use the event data directly (Hardhat handles encoding correctly):

```bash
./scripts/approve-dkg-from-event.sh
```

### Long-term Fix

Fix `convertDkgResultToAbiType()` in `pkg/chain/ethereum/tbtc.go` to ensure the struct is encoded with `membersHash` as the **last** field in the tuple.

**Correct encoding order:**
```go
tuple(
    uint256,      // submitterMemberIndex
    bytes,        // groupPubKey
    uint8[],      // misbehavedMembersIndices
    bytes,        // signatures
    uint256[],    // signingMembersIndices
    uint32[],     // members
    bytes32       // membersHash ← LAST!
)
```

## Files Involved

- **Contract**: `solidity/ecdsa/contracts/libraries/EcdsaDkg.sol` - Struct definition (line 87-118)
- **Node Code**: `pkg/chain/ethereum/tbtc.go` - `convertDkgResultToAbiType()` function
- **Debug Script**: `solidity/ecdsa/scripts/debug-hash-mismatch.ts` - Confirms root cause

## Testing

After fixing node code, verify:
1. Nodes can approve DKG results successfully
2. Hash matches between submission and approval
3. No "execution reverted" errors
4. Wallet creation completes

## Related Documentation

- [DKG Hash Mismatch Issue](./dkg-hash-mismatch-issue.md) - Full problem description
- [DKG Approval Quick Fix](./dkg-approval-quick-fix.md) - Workaround guide


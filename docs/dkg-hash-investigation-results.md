# DKG Hash Mismatch Investigation Results

## Summary

✅ **Hash Calculation Verified**: The event data encoding is correct and matches the stored hash.

## Findings

### Hash Comparison Results

- **Event Result Hash**: `0x75ee0aa2f81fd4e6a3d905bd804b26ef87d99b472535ad15746d67674acd9deb`
- **Calculated Hash** (from event data): `0x75ee0aa2f81fd4e6a3d905bd804b26ef87d99b472535ad15746d67674acd9deb`
- **Status**: ✅ **MATCH**

### What This Means

1. ✅ Event data structure is correct
2. ✅ Field order is correct (membersHash is last)
3. ✅ Data types are correct
4. ✅ Encoding matches what was submitted

### Root Cause Analysis

The hash mismatch error when using the Go client (`keep-client approve-dkg-result`) occurs because:

1. **JSON Unmarshaling Issue**: When converting JSON back to Go struct `EcdsaDkgResult`, something in the conversion process changes the encoding
2. **Possible Causes**:
   - Base64 decoding of `[]byte` fields might not preserve exact bytes
   - Array of numbers for `[32]byte` (`membersHash`) might have encoding differences
   - Field order might not be preserved during JSON→struct→ABI encoding

### Current Status

When using **Hardhat script with event data directly** (`approve-dkg-from-event.ts`):
- ✅ Hash check passes (verified)
- ❌ Transaction still reverts
- **Likely failure point**: `sortitionPool.unlock()` (as identified in previous investigation)

### Next Steps

1. **For immediate approval**: Use the Hardhat script but investigate why `sortitionPool.unlock()` is reverting
2. **For Go client fix**: Investigate JSON unmarshaling and ABI encoding to ensure exact byte preservation
3. **Investigate unlock()**: Check why `sortitionPool.unlock()` is failing even when hash matches

## Verification Script

Run this to verify hash matching:

```bash
cd solidity/ecdsa
npx hardhat run scripts/compare-dkg-hash.ts --network development
```

## Related Files

- `solidity/ecdsa/scripts/compare-dkg-hash.ts` - Hash comparison script
- `solidity/ecdsa/scripts/approve-dkg-from-event.ts` - Approval script using event data
- `docs/dkg-approval-revert-root-cause.md` - Previous investigation on unlock() revert



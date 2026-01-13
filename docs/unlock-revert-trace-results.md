# Transaction Trace Results - approveDkgResult Revert

## Trace Summary

**Transaction reverts at**: DELEGATECALL to `0xa1d026081e446c8929582ca007f451fe7e70e87c` (EcdsaDkg library)

**Revert type**: Low-level revert without error message (`data="0x"`)

**Calculated hash**: `0x75ee0aa2f81fd4e6a3d905bd804b26ef87d99b472535ad15746d67674acd9deb`

## approveResult() Function Analysis

The `approveResult()` function in `EcdsaDkg.sol` has the following require statements:

1. **Line 331-334**: State check - `currentState(self) == State.CHALLENGE`
   - Error: "Current state is not CHALLENGE"
   - ✅ All require statements have error messages

2. **Line 339-342**: Challenge period check - `block.number > challengePeriodEnd`
   - Error: "Challenge period has not passed yet"
   - ✅ All require statements have error messages

3. **Line 344-347**: Hash match check - `keccak256(abi.encode(result)) == self.submittedResultHash`
   - Error: "Result under approval is different than the submitted one"
   - ⚠️ **Most likely cause** - Hash mismatch

4. **Line 352-354**: Array access - `result.members[result.submitterMemberIndex - 1]`
   - ⚠️ **Possible cause** - Array out of bounds or underflow
   - If `submitterMemberIndex` is 0, `- 1` would underflow
   - If `submitterMemberIndex > members.length`, would be out of bounds
   - Solidity array access errors revert with panic, not silent revert

5. **Line 356-362**: Precedence period check
   - Error: "Only the DKG result submitter can approve the result at this moment"
   - ✅ All require statements have error messages

## Possible Causes of Silent Revert

Since the revert has no error message (`data="0x"`), it's likely one of:

1. **Array access out of bounds** (line 353 or 372)
   - Solidity 0.8+ should panic with error code, but might be caught differently
   - Check: `result.submitterMemberIndex` must be in range [1, members.length]

2. **Underflow in array index calculation**
   - If `submitterMemberIndex` is 0, `- 1` would underflow
   - Solidity 0.8+ should revert with panic

3. **External call failure** (line 352: `sortitionPool.getIDOperator()`)
   - If this call reverts, it would propagate up
   - Check: Member ID must exist in sortition pool

4. **Gas exhaustion**
   - Unlikely but possible if gas limit is too low

## Next Steps

1. **Verify array bounds**:
   - Check `result.submitterMemberIndex` is in valid range [1, members.length]
   - Check all `misbehavedMembersIndices` are in valid range

2. **Verify sortition pool membership**:
   - Ensure `result.members[submitterMemberIndex - 1]` exists in sortition pool
   - Call `sortitionPool.getIDOperator()` directly to verify

3. **Compare hash calculation**:
   - Get `submittedResultHash` from contract
   - Compare with calculated hash from event data
   - Verify ABI encoding matches exactly

4. **Use Hardhat console.log**:
   - Add console.log statements in approveResult to see exact revert point
   - Or use Hardhat's debugger to step through execution

## Related Documents
- `docs/unlock-revert-investigation.md` - Initial investigation
- `docs/dkg-hash-mismatch-issue.md` - Hash mismatch root cause



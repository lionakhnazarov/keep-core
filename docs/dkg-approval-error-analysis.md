# DKG Approval Error Analysis: Member 1 (Submitter) Failure

## Error Context

**Timestamp**: `2026-01-06T18:00:21.629Z`  
**Member**: 1 (Submitter)  
**Error**: `[execution reverted]`  
**Scheduled Block**: 1505 (challenge period end + 1)  
**Result Hash**: `0xde41e51c8ae414300c6511740fe8c2761d3b8e21baaa57476ca2a421fc2f9c1f`

## Why This Is Particularly Problematic

Member 1 is the **submitter** - they submitted the DKG result on-chain. Yet even they are failing to approve it. This indicates a fundamental issue with how the result is being encoded/decoded.

## Root Cause Analysis

### The Problem Flow

1. **Result Submission** (block ~1494):
   - Member 1 submits DKG result using their local result
   - Contract stores: `submittedResultHash = keccak256(abi.encode(result))`
   - All nodes receive `DkgResultSubmitted` event

2. **Result Reception** (all nodes):
   - Nodes receive event with `result` struct
   - Nodes convert event result to local format: `convertDkgResultFromAbiType()`
   - Nodes store this in their local DKG state

3. **Approval Attempt** (block 1505):
   - Member 1 uses their **local DKG result** (from `executeDkgValidation`)
   - Converts to ABI format: `convertDkgResultToAbiType()`
   - Calls `ApproveDKGResult()` with this converted result
   - Contract checks: `keccak256(abi.encode(result)) == submittedResultHash`
   - **FAILS**: Hash doesn't match!

### Why Even the Submitter Fails

The submitter fails because:

1. **Different Conversion Paths**:
   - **Submission**: Local result → `convertDkgResultToAbiType()` → Submit
   - **Approval**: Event result → `convertDkgResultFromAbiType()` → Local format → `convertDkgResultToAbiType()` → Approve
   
2. **Potential Encoding Differences**:
   - Event result may have been processed/modified by the contract
   - Round-trip conversion (ABI → Local → ABI) may introduce differences
   - Array ordering, byte padding, or type conversions could differ

3. **The Contract's Exact Match Requirement**:
   ```solidity
   require(
       keccak256(abi.encode(result)) == self.submittedResultHash,
       "Result under approval is different than the submitted one"
   );
   ```
   This requires **byte-for-byte** exact match. Even tiny differences fail.

## Code Flow

### Submission (Member 1)
```go
// pkg/tbtc/dkg_submit.go
dkgResult := AssembleDKGResult(...)  // Creates local result
abiResult := convertDkgResultToAbiType(dkgResult)  // Convert to ABI
SubmitDKGResult(abiResult)  // Submit to chain
```

### Approval (Member 1)
```go
// pkg/tbtc/dkg.go:executeDkgValidation()
// Receives result from DkgResultSubmitted event
result := convertDkgResultFromAbiType(eventResult)  // Event → Local

// Later, when approving:
abiResult := convertDkgResultToAbiType(result)  // Local → ABI
ApproveDKGResult(abiResult)  // Approve
```

### The Conversion Functions

**`convertDkgResultToAbiType`** (pkg/chain/ethereum/tbtc.go:594):
```go
func convertDkgResultToAbiType(result *tbtc.DKGChainResult) ecdsaabi.EcdsaDkgResult {
    signingMembersIndices := make([]*big.Int, len(result.SigningMembersIndexes))
    for i, memberIndex := range result.SigningMembersIndexes {
        signingMembersIndices[i] = big.NewInt(int64(memberIndex))
    }
    return ecdsaabi.EcdsaDkgResult{
        SubmitterMemberIndex:     big.NewInt(int64(result.SubmitterMemberIndex)),
        GroupPubKey:              result.GroupPublicKey,
        MisbehavedMembersIndices: result.MisbehavedMembersIndexes,
        Signatures:               result.Signatures,
        SigningMembersIndices:    signingMembersIndices,
        Members:                  result.Members,
        MembersHash:              result.MembersHash,
    }
}
```

**`convertDkgResultFromAbiType`** (pkg/chain/ethereum/tbtc.go:556):
```go
func convertDkgResultFromAbiType(result ecdsaabi.EcdsaDkgResult) (*tbtc.DKGChainResult, error) {
    signingMembersIndexes := make([]group.MemberIndex, len(result.SigningMembersIndices))
    for i, memberIndex := range result.SigningMembersIndices {
        signingMembersIndexes[i] = group.MemberIndex(memberIndex.Uint64())
    }
    return &tbtc.DKGChainResult{
        SubmitterMemberIndex:     group.MemberIndex(result.SubmitterMemberIndex.Uint64()),
        GroupPublicKey:           result.GroupPubKey,
        MisbehavedMembersIndexes: result.MisbehavedMembersIndices,
        Signatures:               result.Signatures,
        SigningMembersIndexes:    signingMembersIndexes,
        Members:                  result.Members,
        MembersHash:              result.MembersHash,
    }, nil
}
```

## Potential Issues

### 1. Array Ordering
- `SigningMembersIndices` might be sorted differently
- Contract might enforce ordering that's lost in conversion

### 2. Byte Array Differences
- `GroupPubKey` and `Signatures` might have padding differences
- Event decoding vs direct encoding might differ

### 3. BigInt Conversion
- `big.NewInt(int64(memberIndex))` vs `memberIndex.Uint64()`
- Potential overflow or sign issues

### 4. Members Array
- `Members` array ordering might differ
- Event might have different ordering than local state

## Solution

**Use the exact result from the event**, not the converted local result:

```go
// Instead of:
result := convertDkgResultFromAbiType(eventResult)
// ... later ...
ApproveDKGResult(result)  // Uses converted result

// Should be:
eventAbiResult := eventResult  // Use event result directly
ApproveDKGResult(eventAbiResult)  // Use exact event result
```

However, the current code architecture doesn't support this easily because:
- `executeDkgValidation` receives the converted result
- `ApproveDKGResult` expects `*tbtc.DKGChainResult` (local format)
- The event's ABI result is lost after conversion

## Workaround

For manual approval, use the exact result from the `DkgResultSubmitted` event:

```typescript
const filter = wr.filters.DkgResultSubmitted();
const events = await wr.queryFilter(filter, -2000);
const latestEvent = events[events.length - 1];
const result = latestEvent.args.result; // Use THIS exact result
await wr.approveDkgResult(result);  // Approve with exact event result
```

## Timeline of Failures

From node2.log:
- **18:00:21** - Member 1 fails (submitter, block 1505)
- **18:17:30** - Member 1 retries (still fails)
- **18:22:30** - Member 1 retries again
- **18:30:39** - Member 1 retries again
- **18:45:45** - Member 1 retries again
- **18:56:29** - Member 1 retries again
- **19:02:11** - Member 80 fails (block ~2695)
- **19:02:32** - Member 81 fails (block ~2710)
- **19:09:23** - Member 88 fails (block ~2815)
- **19:11:43** - Member 90 fails (block ~2845)
- **19:14:45** - Member 93 fails (block ~2890)
- **19:36:07** - Member 98 fails (block ~2965)
- **19:36:53** - Member 99 fails (block ~2980)

**All members are failing with the same error**, confirming it's a systematic issue with result encoding, not a timing or account issue.

## Conclusion

The root cause is that nodes use a **converted version** of the submitted result for approval, rather than the **exact result** that was submitted. Even the submitter fails because they're using the event result (which went through conversion) rather than their original submission result.

**Fix Required**: Nodes should store and use the exact ABI-encoded result from the event for approval, rather than converting it to local format and back.



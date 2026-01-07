# DKG Hash Mismatch - Action Plan

## Current Status

✅ **Verified**: All struct field orders are correct
- Solidity struct: `membersHash` is last ✅
- Go struct: `MembersHash` is last ✅  
- ABI JSON: `membersHash` is last ✅
- Reflection order: `MembersHash` is last ✅

❌ **Issue**: Encoding still produces wrong hash
- Expected: `0xa4c691f074124bfbce638356b4c89d4d2d1966b0e29faa7f3ef9ed5fce7b4d75`
- Got: Different hash

## Root Cause Hypothesis

The issue is likely in **go-ethereum's ABI encoder behavior**:
- The encoder may match struct fields by **name** to ABI components
- But it might encode them in **ABI JSON component order** instead of **Go struct field order**
- Even though both orders match, there might be a subtle encoding difference

## Action Plan

### Step 1: Test with Actual Event Data ✅ Ready

**Goal**: Verify encoding with exact data from chain event

**Scripts Created**:
- `solidity/ecdsa/scripts/extract-event-data.ts` - Extracts event data as JSON
- `scripts/test-go-encoding-with-real-data.go` - Tests Go encoding with real data

**Commands**:
```bash
# Extract event data
cd solidity/ecdsa
npx hardhat run scripts/extract-event-data.ts --network development > /tmp/event-data.json

# Test Go encoding (after updating script with JSON parser)
cd ../..
go run scripts/test-go-encoding-with-real-data.go /tmp/event-data.json
```

### Step 2: Investigate go-ethereum Encoder Behavior

**Goal**: Understand exactly how `abi.Arguments.Pack()` encodes structs

**Approach**:
1. Check go-ethereum source code for struct encoding logic
2. Test if encoder uses struct field order or ABI component order
3. Verify field name matching behavior

**Files to Check**:
- `github.com/ethereum/go-ethereum/accounts/abi/pack.go`
- `github.com/ethereum/go-ethereum/accounts/abi/type.go`

### Step 3: Create Manual Encoding Workaround

**Goal**: If encoder has a bug, manually encode struct in correct order

**Implementation**:
```go
func convertDkgResultToAbiTypeManual(
	result *tbtc.DKGChainResult,
) ([]byte, error) {
	// Manually create ABI arguments in correct order
	uint256Type, _ := abi.NewType("uint256", "uint256", nil)
	bytesType, _ := abi.NewType("bytes", "bytes", nil)
	uint8ArrayType, _ := abi.NewType("uint8[]", "uint8[]", nil)
	uint256ArrayType, _ := abi.NewType("uint256[]", "uint256[]", nil)
	uint32ArrayType, _ := abi.NewType("uint32[]", "uint32[]", nil)
	bytes32Type, _ := abi.NewType("bytes32", "bytes32", nil)
	
	args := abi.Arguments{
		{Name: "submitterMemberIndex", Type: uint256Type},
		{Name: "groupPubKey", Type: bytesType},
		{Name: "misbehavedMembersIndices", Type: uint8ArrayType},
		{Name: "signatures", Type: bytesType},
		{Name: "signingMembersIndices", Type: uint256ArrayType},
		{Name: "members", Type: uint32ArrayType},
		{Name: "membersHash", Type: bytes32Type}, // LAST
	}
	
	// Pack in correct order
	return args.Pack(
		big.NewInt(int64(result.SubmitterMemberIndex)),
		result.GroupPublicKey,
		result.MisbehavedMembersIndexes,
		result.Signatures,
		convertSigningMembersIndices(result.SigningMembersIndexes),
		result.Members,
		result.MembersHash,
	)
}
```

### Step 4: Regenerate Bindings (If Needed)

**Goal**: Ensure ABI bindings match contract exactly

**Commands**:
```bash
# If bindings are out of sync
cd solidity/ecdsa
# Regenerate bindings using abigen or your build process
```

### Step 5: Test Fix

**Goal**: Verify the fix works with actual chain data

**Steps**:
1. Implement fix (manual encoding or binding regeneration)
2. Test with actual event data
3. Verify hash matches stored hash
4. Test approval transaction succeeds

## Immediate Next Actions

1. **Run event data extraction**:
   ```bash
   cd solidity/ecdsa
   npx hardhat run scripts/extract-event-data.ts --network development
   ```

2. **Update Go test script** with JSON parser to use real data

3. **Test encoding** and compare hashes

4. **If mismatch persists**, implement manual encoding workaround

## Files Created

- `scripts/test-encoding-with-event-data.sh` - Shell script to extract and test
- `scripts/test-go-encoding-with-real-data.go` - Go test template
- `solidity/ecdsa/scripts/extract-event-data.ts` - Extract event data as JSON
- `docs/dkg-hash-mismatch-action-plan.md` - This file

## Success Criteria

✅ Hash computed from Go encoding matches stored hash  
✅ Approval transaction succeeds  
✅ Wallet creation completes  
✅ Nodes can approve DKG results without errors


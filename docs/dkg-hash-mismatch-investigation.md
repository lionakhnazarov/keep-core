# DKG Hash Mismatch - Investigation Summary

## Root Cause Analysis

### ✅ What We Know

1. **Solidity Struct Order** (correct):
   ```solidity
   struct Result {
       uint256 submitterMemberIndex;      // 1
       bytes groupPubKey;                  // 2
       uint8[] misbehavedMembersIndices;  // 3
       bytes signatures;                   // 4
       uint256[] signingMembersIndices;   // 5
       uint32[] members;                   // 6
       bytes32 membersHash;                // 7 ← LAST
   }
   ```

2. **Go Struct Order** (correct):
   ```go
   type EcdsaDkgResult struct {
       SubmitterMemberIndex     *big.Int   // 1
       GroupPubKey              []byte     // 2
       MisbehavedMembersIndices []uint8   // 3
       Signatures               []byte     // 4
       SigningMembersIndices    []*big.Int // 5
       Members                  []uint32   // 6
       MembersHash              [32]byte   // 7 ← LAST
   }
   ```

3. **Hash Mismatch Confirmed**:
   - Stored hash: `0xa4c691f074124bfbce638356b4c89d4d2d1966b0e29faa7f3ef9ed5fce7b4d75` ✅
   - Wrong encoding: `0xb9178005cc73169fcb82f7a2f0fa3f18b0572830846a81e9bb2d69c019c69221` ❌
   - Correct encoding (membersHash last): `0xa4c691f074124bfbce638356b4c89d4d2d1966b0e29faa7f3ef9ed5fce7b4d75` ✅

### 🔍 Where the Issue Might Be

The encoding happens in the go-ethereum ABI encoder (`contract.Transact()`). The encoder uses:
1. Go struct field order (via reflection)
2. ABI JSON component order (from contract metadata)

**Hypothesis**: The go-ethereum ABI encoder might be using the **ABI JSON component order** instead of the Go struct field order, even though both appear correct.

### 📍 Code Flow

1. `pkg/tbtc/dkg.go:765` → `de.chain.ApproveDKGResult(result)`
2. `pkg/chain/ethereum/tbtc.go:988` → `ApproveDKGResult()` calls `convertDkgResultToAbiType()`
3. `pkg/chain/ethereum/tbtc.go:1000` → `tc.walletRegistry.ApproveDkgResult(result)`
4. `pkg/chain/ethereum/ecdsa/gen/contract/WalletRegistry.go:281` → `wr.contract.ApproveDkgResult()`
5. `pkg/chain/ethereum/ecdsa/gen/abi/WalletRegistry.go:1258` → `contract.Transact(opts, "approveDkgResult", dkgResult)`
6. **go-ethereum ABI encoder** encodes the struct using ABI metadata

### 🔧 Potential Issues

1. **ABI JSON Component Order Mismatch**
   - The ABI JSON might have components in a different order than the Solidity struct
   - The go-ethereum encoder might use ABI JSON order instead of Go struct order
   - **Fix**: Regenerate bindings or verify ABI JSON matches Solidity struct order

2. **Struct Field Tag Ordering**
   - Go struct fields might need explicit tags to match ABI JSON
   - **Fix**: Add struct tags to ensure correct encoding order

3. **ABI Binding Generator Issue**
   - The binding generator might have reordered fields during generation
   - **Fix**: Regenerate bindings from the correct contract ABI

### 🎯 Next Steps

1. **Verify ABI JSON Component Order**:
   ```bash
   # Extract and check the actual ABI JSON component order
   # Compare with Solidity struct order
   ```

2. **Check go-ethereum ABI Encoder Behavior**:
   - Verify if it uses Go struct field order or ABI JSON component order
   - Test with a simple struct to confirm encoding behavior

3. **Regenerate Bindings** (if needed):
   ```bash
   # Regenerate contract bindings to ensure ABI JSON matches Solidity struct
   ```

4. **Add Struct Tags** (if needed):
   ```go
   type EcdsaDkgResult struct {
       SubmitterMemberIndex     *big.Int   `abi:"submitterMemberIndex"`
       GroupPubKey              []byte     `abi:"groupPubKey"`
       // ... etc
   }
   ```

5. **Test Encoding Directly**:
   - Create a test that encodes the struct and compares the hash
   - Verify the encoding matches the contract's hash computation

### 📝 Files to Investigate

- `pkg/chain/ethereum/ecdsa/gen/abi/WalletRegistry.go` - ABI metadata and struct definition
- `pkg/chain/ethereum/tbtc.go` - `convertDkgResultToAbiType()` function
- `solidity/ecdsa/contracts/libraries/EcdsaDkg.sol` - Solidity struct definition
- go-ethereum `accounts/abi` package - How struct encoding works

### 🐛 Debugging Tools

- `solidity/ecdsa/scripts/debug-hash-mismatch.ts` - Confirms correct encoding order
- `solidity/ecdsa/scripts/approve-dkg-from-event.ts` - Workaround using event data


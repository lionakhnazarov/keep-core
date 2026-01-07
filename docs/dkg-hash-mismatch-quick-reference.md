# DKG Hash Mismatch - Quick Reference

## Problem
Nodes fail to approve DKG results because computed hash doesn't match stored hash.

## Root Cause
All struct field orders are correct, but go-ethereum ABI encoder may have encoding behavior issue.

## Quick Fix (Workaround)
Use `approve-dkg-from-event.sh` which uses event data directly:
```bash
./scripts/approve-dkg-from-event.sh
```

## Investigation Status

### ✅ Verified Correct
- Solidity struct order: `membersHash` is last
- Go struct order: `MembersHash` is last  
- ABI JSON order: `membersHash` is last
- Reflection order: `MembersHash` is last

### ❌ Issue Found
- Encoding produces wrong hash despite correct orders
- Likely issue in go-ethereum ABI encoder behavior

## Next Steps

### 1. Extract Event Data
```bash
cd solidity/ecdsa
npx hardhat run scripts/extract-event-data.ts --network development > /tmp/event-data.json
```

### 2. Test Go Encoding
```bash
# Update test-go-encoding-with-real-data.go with JSON parser
# Then run:
go run scripts/test-go-encoding-with-real-data.go /tmp/event-data.json
```

### 3. If Mismatch Persists
Implement manual encoding workaround in `convertDkgResultToAbiType()`.

## Files Reference

### Scripts
- `scripts/approve-dkg-from-event.sh` - Workaround using event data
- `scripts/debug-hash-mismatch.ts` - Debug script (TypeScript)
- `scripts/extract-event-data.ts` - Extract event data as JSON
- `scripts/test-go-encoding-with-real-data.go` - Test Go encoding

### Documentation
- `docs/dkg-hash-mismatch-issue.md` - Problem description
- `docs/dkg-hash-mismatch-root-cause.md` - Root cause analysis
- `docs/dkg-hash-mismatch-action-plan.md` - Detailed action plan
- `docs/dkg-hash-mismatch-next-steps.md` - Investigation findings

## Expected Hash
```
0xa4c691f074124bfbce638356b4c89d4d2d1966b0e29faa7f3ef9ed5fce7b4d75
```

## Wrong Hash (Current)
```
0xb9178005cc73169fcb82f7a2f0fa3f18b0572830846a81e9bb2d69c019c69221
```

## Key Code Locations

- `pkg/chain/ethereum/tbtc.go:594` - `convertDkgResultToAbiType()`
- `pkg/chain/ethereum/ecdsa/gen/abi/WalletRegistry.go:42` - `EcdsaDkgResult` struct
- `solidity/ecdsa/contracts/libraries/EcdsaDkg.sol:87` - Solidity `Result` struct


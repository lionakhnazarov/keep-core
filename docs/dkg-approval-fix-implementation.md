# DKG Approval Fix Implementation Proposal

## Problem Summary

Nodes fail to approve DKG results because they use a **converted version** of the submitted result instead of the **exact ABI-encoded result** from the event. The round-trip conversion (ABI → Local → ABI) introduces subtle encoding differences that cause hash mismatches.

## Root Cause

**Current Flow:**
```
Event (ABI format) → convertDkgResultFromAbiType() → Local format → Store
                                                                    ↓
Approval: Local format → convertDkgResultToAbiType() → ABI format → Approve → Hash mismatch!
```

**Required Flow:**
```
Event (ABI format) → Store ABI format directly → Approve with exact ABI format → Success!
```

## Implementation Plan

### Step 1: Extend Event Struct

**File**: `pkg/tbtc/chain.go`

Add an `AbiResult` field to store the original ABI-encoded result:

```go
// DKGResultSubmittedEvent represents a DKG result submission event. It is
// emitted after a submitted DKG result lands on the chain.
type DKGResultSubmittedEvent struct {
	Seed        *big.Int
	ResultHash  DKGChainResultHash
	Result      *DKGChainResult  // Local format (for validation/compatibility)
	AbiResult   interface{}       // Original ABI format (for approval)
	BlockNumber uint64
}
```

**Note**: The `AbiResult` field type needs to be `ecdsaabi.EcdsaDkgResult`, but we need to import it. Since this is in `pkg/tbtc` and the ABI types are in `pkg/chain/ethereum/ecdsa/gen/abi`, we have two options:

**Option A**: Use `interface{}` and type assert when needed
**Option B**: Import the ABI package (may create circular dependency issues)

**Recommended**: Use a wrapper type or store as `interface{}` and type assert in the chain implementation.

### Step 2: Modify Event Handler

**File**: `pkg/chain/ethereum/tbtc.go`

Modify `OnDKGResultSubmitted` to store both formats:

```go
func (tc *TbtcChain) OnDKGResultSubmitted(
	handler func(event *tbtc.DKGResultSubmittedEvent),
) subscription.EventSubscription {
	onEvent := func(
		resultHash [32]byte,
		seed *big.Int,
		result ecdsaabi.EcdsaDkgResult,  // Original ABI format
		blockNumber uint64,
	) {
		tbtcResult, err := convertDkgResultFromAbiType(result)
		if err != nil {
			logger.Errorf(
				"unexpected DKG result in DKGResultSubmitted event: [%v]",
				err,
			)
			return
		}

		handler(&tbtc.DKGResultSubmittedEvent{
			Seed:        seed,
			ResultHash:  resultHash,
			Result:      tbtcResult,      // Local format (for compatibility)
			AbiResult:   result,          // Original ABI format (for approval)
			BlockNumber: blockNumber,
		})
	}

	return tc.walletRegistry.
		DkgResultSubmittedEvent(nil, nil, nil).
		OnEvent(onEvent)
}
```

### Step 3: Add ABI Approval Method

**File**: `pkg/chain/ethereum/tbtc.go`

Add a new method that accepts ABI format directly:

```go
// ApproveDKGResultFromAbi approves a DKG result using the exact ABI-encoded result.
// This avoids hash mismatches caused by round-trip conversions.
func (tc *TbtcChain) ApproveDKGResultFromAbi(abiResult ecdsaabi.EcdsaDkgResult) error {
	gasEstimate, err := tc.walletRegistry.ApproveDkgResultGasEstimate(abiResult)
	if err != nil {
		return err
	}

	// The original estimate for this contract call turned out to be too low.
	// Here we add a 20% margin to overcome the gas problems.
	gasEstimateWithMargin := float64(gasEstimate) * float64(1.2)

	_, err = tc.walletRegistry.ApproveDkgResult(
		abiResult,  // Use exact ABI format, no conversion
		ethutil.TransactionOptions{
			GasLimit: uint64(gasEstimateWithMargin),
		},
	)

	return err
}
```

### Step 4: Update Chain Interface

**File**: `pkg/tbtc/chain.go`

Add the new method to the chain interface:

```go
// Chain defines the subset of the TBTC chain interface that pertains
// specifically to the tBTC operations.
type Chain interface {
	// ... existing methods ...
	
	// ApproveDKGResult approves a DKG result using local format (legacy, may have hash issues)
	ApproveDKGResult(dkgResult *DKGChainResult) error
	
	// ApproveDKGResultFromAbi approves a DKG result using exact ABI format (recommended)
	ApproveDKGResultFromAbi(abiResult interface{}) error
}
```

### Step 5: Update Approval Logic

**File**: `pkg/tbtc/dkg.go`

Modify `executeDkgValidation` to use the ABI result for approval:

```go
func (de *dkgExecutor) executeDkgValidation(
	seed *big.Int,
	submissionBlock uint64,
	result *DKGChainResult,
	resultHash [32]byte,
	abiResult interface{},  // Add this parameter
) {
	// ... existing validation code ...

	// When approving, use the ABI result directly
	for _, currentMemberIndex := range memberIndexes {
		go func(memberIndex group.MemberIndex) {
			// ... timing logic ...

			// Use ABI result for approval instead of converted result
			if abiResult != nil {
				// Type assert to ecdsaabi.EcdsaDkgResult
				if abiDkgResult, ok := abiResult.(ecdsaabi.EcdsaDkgResult); ok {
					err = de.chain.ApproveDKGResultFromAbi(abiDkgResult)
				} else {
					// Fallback to legacy method if type assertion fails
					dkgLogger.Warnf(
						"[member:%v] cannot use ABI result for approval, falling back to legacy method",
						memberIndex,
					)
					err = de.chain.ApproveDKGResult(result)
				}
			} else {
				// Fallback to legacy method if ABI result not available
				err = de.chain.ApproveDKGResult(result)
			}

			if err != nil {
				dkgLogger.Errorf(
					"[member:%v] cannot approve DKG result: [%v]",
					memberIndex,
					err,
				)
				return
			}

			// ... rest of approval logic ...
		}(currentMemberIndex)
	}
}
```

### Step 6: Update Event Handler Call

**File**: `pkg/tbtc/dkg.go`

Modify the event handler to pass the ABI result:

```go
subscription := de.chain.OnDKGResultSubmitted(
	func(event *DKGResultSubmittedEvent) {
		defer cancelCtx()

		dkgLogger.Infof(
			"[member:%v] DKG result with group public "+
				"key [0x%x] and result hash [0x%x] submitted "+
				"at block [%v] by member [%v]",
			memberIndex,
			event.Result.GroupPublicKey,
			event.ResultHash,
			event.BlockNumber,
			event.Result.SubmitterMemberIndex,
		)

		// Pass both formats to validation
		de.executeDkgValidation(
			seed,
			event.BlockNumber,
			event.Result,      // Local format
			event.ResultHash,
			event.AbiResult,   // ABI format (NEW)
		)
	})
```

## Alternative Approach: Store ABI Result in dkgExecutor

If modifying the event struct is problematic, we can store the ABI result in the `dkgExecutor` struct:

**File**: `pkg/tbtc/dkg.go`

```go
type dkgExecutor struct {
	// ... existing fields ...
	submittedAbiResult ecdsaabi.EcdsaDkgResult  // Store ABI result
	submittedAbiResultMutex sync.RWMutex
}

// In event handler:
subscription := de.chain.OnDKGResultSubmitted(
	func(event *DKGResultSubmittedEvent) {
		defer cancelCtx()

		// Store ABI result for later use
		de.submittedAbiResultMutex.Lock()
		if abiResult, ok := event.AbiResult.(ecdsaabi.EcdsaDkgResult); ok {
			de.submittedAbiResult = abiResult
		}
		de.submittedAbiResultMutex.Unlock()

		de.executeDkgValidation(
			seed,
			event.BlockNumber,
			event.Result,
			event.ResultHash,
		)
	})

// In executeDkgValidation:
func (de *dkgExecutor) executeDkgValidation(
	seed *big.Int,
	submissionBlock uint64,
	result *DKGChainResult,
	resultHash [32]byte,
) {
	// ... validation code ...

	// Get stored ABI result
	de.submittedAbiResultMutex.RLock()
	abiResult := de.submittedAbiResult
	de.submittedAbiResultMutex.RUnlock()

	// Use ABI result for approval
	if abiResult != nil {
		err = de.chain.ApproveDKGResultFromAbi(abiResult)
	} else {
		// Fallback
		err = de.chain.ApproveDKGResult(result)
	}
}
```

## Testing Strategy

1. **Unit Tests**: Test that `ApproveDKGResultFromAbi` uses the exact ABI format
2. **Integration Tests**: Verify that approval succeeds when using ABI format
3. **Hash Verification**: Add logging to compare hashes before/after conversion
4. **Backward Compatibility**: Ensure legacy `ApproveDKGResult` still works

## Migration Path

1. **Phase 1**: Add new methods alongside existing ones (non-breaking)
2. **Phase 2**: Update nodes to use new methods
3. **Phase 3**: Deprecate old methods
4. **Phase 4**: Remove old methods (breaking change)

## Benefits

1. **Fixes Hash Mismatch**: Uses exact ABI format, eliminating conversion errors
2. **Backward Compatible**: Legacy methods still available
3. **Minimal Changes**: Only adds new code, doesn't break existing functionality
4. **Clear Separation**: ABI format for approval, local format for validation

## Risks

1. **Type Assertions**: Need to handle type assertion failures gracefully
2. **Circular Dependencies**: May need to restructure imports
3. **Testing**: Need comprehensive tests to ensure hash matches

## Recommended Implementation Order

1. ✅ Add `ApproveDKGResultFromAbi` method (Step 3)
2. ✅ Store ABI result in event handler (Step 2)
3. ✅ Update approval logic to use ABI result (Step 5)
4. ✅ Add tests and verify hash matching
5. ✅ Deploy and monitor

## Quick Fix (Temporary Workaround)

For immediate relief, nodes can be manually approved using the exact event result via CLI scripts (already implemented in `approve-dkg-result-complete.sh`).



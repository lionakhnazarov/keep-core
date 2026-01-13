# Redemption Request Minimum Age Delay - Storage and Location

## Overview

The Redemption Request Minimum Age Delay is stored **on-chain** in an optional smart contract called **`RedemptionWatchtower`**. This delay is used to prevent front-running attacks and can be set per redemption request.

## Storage Location

### On-Chain Contract: `RedemptionWatchtower`

**Contract Address**: Retrieved from `Bridge.getRedemptionWatchtower()`

**Storage Structure**: The delay is stored in a mapping:
```solidity
mapping(bytes32 => uint256) public redemptionDelays;
```

**Key**: `bytes32` redemption key (computed from wallet + redeemer output script)  
**Value**: `uint256` delay in **seconds**

### Key Generation

The redemption key is computed as follows:

```go
// From pkg/chain/ethereum/tbtc.go:1670-1688

func buildRedemptionKey(
    walletPublicKeyHash [20]byte,
    redeemerOutputScript bitcoin.Script,
) (*big.Int, error) {
    // 1. Prefix the redeemer output script with its length
    prefixedRedeemerOutputScript, err := redeemerOutputScript.ToVarLenData()
    
    // 2. Hash the prefixed script
    redeemerOutputScriptHash := crypto.Keccak256Hash(prefixedRedeemerOutputScript)
    
    // 3. Concatenate script hash + wallet PKH and hash again
    redemptionKey := crypto.Keccak256Hash(
        append(redeemerOutputScriptHash[:], walletPublicKeyHash[:]...),
    )
    
    return redemptionKey.Big(), nil
}
```

**Formula**: `keccak256(keccak256(lengthPrefixed(redeemerOutputScript)) || walletPublicKeyHash)`

## Code Flow

### 1. Retrieving the Delay

**Location**: `pkg/chain/ethereum/tbtc.go:2390-2409`

```go
func (tc *TbtcChain) GetRedemptionDelay(
    walletPublicKeyHash [20]byte,
    redeemerOutputScript bitcoin.Script,
) (time.Duration, error) {
    // If RedemptionWatchtower is not set, return 0 delay
    if tc.redemptionWatchtower == nil {
        return 0, nil
    }

    // Build the redemption key
    redemptionKey, err := tc.BuildRedemptionKey(walletPublicKeyHash, redeemerOutputScript)
    if err != nil {
        return 0, fmt.Errorf("cannot build redemption key: [%v]", err)
    }

    // Query the contract for the delay (returns seconds)
    delay, err := tc.redemptionWatchtower.GetRedemptionDelay(redemptionKey)
    if err != nil {
        return 0, fmt.Errorf("cannot get redemption delay: [%v]", err)
    }

    // Convert seconds to time.Duration
    return time.Duration(delay) * time.Second, nil
}
```

### 2. Using the Delay

**Location**: `pkg/tbtcpg/redemptions.go:378-404`

The delay is used when filtering pending redemption requests:

```go
redemptionRequestsRangeEndTimestampFn := func(
    redemption *RedemptionRequest,
) (time.Time, error) {
    // Get the delay from the RedemptionWatchtower contract
    delay, err := chain.GetRedemptionDelay(
        redemption.WalletPublicKeyHash,
        redemption.RedeemerOutputScript,
    )
    if err != nil {
        return time.Time{}, fmt.Errorf("failed to get redemption delay: [%w]", err)
    }

    // Use the maximum of requestMinAge (config) and delay (on-chain)
    minAge := time.Duration(requestMinAge) * time.Second
    if delay > minAge {
        minAge = delay
    }

    // Only process requests that are old enough
    return timeNow.Add(-minAge), nil
}
```

**Formula**: `minAge = max(requestMinAge, redemptionDelay)`

## Contract Initialization

**Location**: `pkg/chain/ethereum/tbtc.go:207-239`

```go
// Get RedemptionWatchtower address from Bridge contract
redemptionWatchtowerAddress, err := bridge.GetRedemptionWatchtower()

// The RedemptionWatchtower contract is optional
// If address is zero, it's not deployed/configured
var redemptionWatchtower *tbtccontract.RedemptionWatchtower
if redemptionWatchtowerAddress != [20]byte{} {
    redemptionWatchtower, err = tbtccontract.NewRedemptionWatchtower(
        redemptionWatchtowerAddress,
        baseChain.chainID,
        baseChain.key,
        baseChain.client,
        // ... other parameters
    )
}
```

## Default Behavior

### If RedemptionWatchtower is NOT Set

- **Delay**: `0 seconds`
- **Behavior**: Only `requestMinAge` (from config) is used
- **Code**: Returns `0` immediately if `redemptionWatchtower == nil`

### If RedemptionWatchtower IS Set

- **Delay**: Value from contract mapping (can be 0 or any positive value)
- **Behavior**: Uses `max(requestMinAge, redemptionDelay)`
- **Code**: Queries contract via `GetRedemptionDelay(bytes32 redemptionKey)`

## Setting the Delay

The delay is set **on-chain** by calling the `RedemptionWatchtower` contract. The exact method depends on the contract implementation, but typically:

```solidity
function setRedemptionDelay(bytes32 redemptionKey, uint256 delaySeconds) external;
```

**Who can set it**: Depends on contract access control (typically governance or authorized addresses)

## Development Environment

In the development environment (`pkg/chain/ethereum/tbtc/gen/_address/RedemptionWatchtower`):
```
0x0000000000000000000000000000000000000000
```

This means **RedemptionWatchtower is NOT deployed** in development, so delays default to `0`.

## Storage Summary

| Component | Location | Type | Key | Value |
|-----------|----------|------|-----|-------|
| **RedemptionWatchtower** | On-chain contract | `mapping(bytes32 => uint256)` | `redemptionKey` (32 bytes) | Delay in seconds |
| **Redemption Key** | Computed | `bytes32` | `keccak256(keccak256(lengthPrefixed(script)) \|\| walletPKH)` | N/A |
| **Delay Value** | Contract storage | `uint256` | N/A | Seconds (0 = no delay) |

## Code References

1. **Delay Retrieval**: `pkg/chain/ethereum/tbtc.go:2390-2409`
2. **Key Building**: `pkg/chain/ethereum/tbtc.go:1670-1688`
3. **Delay Usage**: `pkg/tbtcpg/redemptions.go:378-404`
4. **Contract Init**: `pkg/chain/ethereum/tbtc.go:207-239`
5. **Contract Interface**: `pkg/chain/ethereum/tbtc/gen/contract/RedemptionWatchtower.go` (generated)

## Example

### Scenario: Redemption with Delay

1. **User submits redemption request** → `RedemptionRequested` event emitted
2. **System queries delay**:
   - Build redemption key: `keccak256(keccak256(script) || walletPKH)`
   - Call `RedemptionWatchtower.getRedemptionDelay(key)` → Returns `86400` (24 hours)
3. **Filter pending redemptions**:
   - Check if `now - RequestedAt >= max(requestMinAge, 86400)`
   - If yes, include in proposal; if no, skip
4. **Process redemption** → Once delay period has elapsed

### Scenario: No Delay (Development)

1. **User submits redemption request** → `RedemptionRequested` event emitted
2. **System queries delay**:
   - `RedemptionWatchtower` is `nil` → Returns `0`
3. **Filter pending redemptions**:
   - Check if `now - RequestedAt >= max(requestMinAge, 0)`
   - Uses only `requestMinAge` from config
4. **Process redemption** → Once `requestMinAge` has elapsed

## Security Considerations

- **Per-request delays**: Each redemption can have a different delay
- **On-chain storage**: Delays are immutable once set (or require governance to change)
- **Front-running protection**: Delays prevent immediate redemption after request
- **Optional component**: System works without RedemptionWatchtower (uses config-based delays)


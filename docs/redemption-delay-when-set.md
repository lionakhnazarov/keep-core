# When is Redemption Request Minimum Age Delay Set?

## Overview

The Redemption Request Minimum Age Delay is set **BEFORE** a redemption request is created. It's a **proactive fraud prevention mechanism** that must be configured in advance.

## Timing: When Delay is Set

### ✅ **BEFORE Redemption Request Creation**

The delay **must be set before** a user submits a redemption request for it to be effective. Here's why:

1. **Delay is checked during filtering**: When the system filters pending redemption requests to include in proposals, it queries the delay from the `RedemptionWatchtower` contract
2. **No automatic setting**: The delay is **NOT** automatically set when a redemption request is created
3. **Pre-configured protection**: It's designed as a pre-configured security measure

### Timeline

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Delay Set (BEFORE request)                              │
│    └─> Governance/Authorized address calls                 │
│        RedemptionWatchtower.setRedemptionDelay(key, delay) │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. User Submits Redemption Request                         │
│    └─> Bridge.requestRedemption(...)                       │
│    └─> RedemptionRequested event emitted                    │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. System Filters Pending Redemptions                       │
│    └─> Queries delay: GetRedemptionDelay(key)               │
│    └─> Checks: RequestedAt + delay <= now                  │
│    └─> Only includes requests that meet minimum age        │
└─────────────────────────────────────────────────────────────┘
```

## Code Flow

### 1. Delay Setting (Manual/Governance)

**Who sets it**: Governance or authorized addresses

**How it's set**: Direct contract call to `RedemptionWatchtower`:

```solidity
// Example contract interface (exact implementation may vary)
function setRedemptionDelay(bytes32 redemptionKey, uint256 delaySeconds) external;
```

**When**: 
- **Before** any redemption requests are created
- **Proactively** as a security measure
- **Per redemption key** (wallet + redeemer output script combination)

### 2. Delay Querying (Automatic)

**Location**: `pkg/tbtcpg/redemptions.go:378-404`

When filtering pending redemption requests, the system queries the delay:

```go
redemptionRequestsRangeEndTimestampFn := func(
    redemption *RedemptionRequest,
) (time.Time, error) {
    // Query delay from RedemptionWatchtower contract
    delay, err := chain.GetRedemptionDelay(
        redemption.WalletPublicKeyHash,
        redemption.RedeemerOutputScript,
    )
    
    // Use maximum of config-based and on-chain delay
    minAge := time.Duration(requestMinAge) * time.Second
    if delay > minAge {
        minAge = delay
    }
    
    // Only process requests old enough
    return timeNow.Add(-minAge), nil
}
```

**When this happens**:
- During coordination window (every ~3 hours)
- When generating redemption proposals
- **AFTER** redemption requests already exist

## Key Points

### ⚠️ Delay Must Be Set BEFORE Request

- If delay is set **after** a redemption request is created, it will only affect **future** filtering cycles
- The delay is checked **when filtering**, not when the request is created
- Setting delay after request creation won't retroactively delay existing requests

### 🔒 Per-Request Configuration

- Each redemption can have a **different delay**
- Delay is keyed by: `keccak256(keccak256(script) || walletPKH)`
- Same wallet + same redeemer output script = same delay

### 🛡️ Fraud Prevention Purpose

The delay is designed to prevent:
- **Front-running attacks**: Attackers can't immediately redeem after seeing a request
- **Time-based exploits**: Forces attackers to wait, giving time for detection
- **Rapid redemption abuse**: Prevents instant redemption of suspicious requests

## Example Scenarios

### Scenario 1: Delay Set Before Request ✅

```
Time T0: Governance sets delay = 24 hours for wallet X + script Y
Time T1: User submits redemption request (wallet X, script Y)
Time T2: System filters requests → Finds delay = 24 hours
Time T3: Request included in proposal only if (T1 + 24h) <= T2
```

**Result**: Delay is effective, request waits 24 hours

### Scenario 2: Delay Set After Request ❌

```
Time T0: User submits redemption request (wallet X, script Y)
Time T1: Governance sets delay = 24 hours for wallet X + script Y
Time T2: System filters requests → Finds delay = 24 hours
Time T3: Request included if (T0 + 24h) <= T2
```

**Result**: Delay applies, but request was already created at T0, so it may be processed earlier than intended

### Scenario 3: No Delay Set (Default)

```
Time T0: User submits redemption request
Time T1: System filters requests → No delay found (returns 0)
Time T2: Uses only requestMinAge from config
```

**Result**: Only config-based minimum age applies

## Who Can Set Delays?

### Typical Implementations

1. **Governance**: Multi-sig or DAO-controlled
2. **Authorized addresses**: Pre-approved addresses with setter permissions
3. **Admin**: Single admin address (less common, less secure)

### Access Control

The exact access control depends on the `RedemptionWatchtower` contract implementation, but typically includes:

- **Ownership-based**: Only contract owner can set delays
- **Role-based**: Specific roles (e.g., `DELAY_SETTER_ROLE`)
- **Governance-based**: Requires governance proposal and voting

## When Delays Are Typically Set

### 1. **Initial Configuration**
- When `RedemptionWatchtower` is first deployed
- Setting default delays for known wallets/scripts
- Establishing baseline security parameters

### 2. **Security Response**
- After detecting suspicious activity
- In response to fraud attempts
- As part of incident response

### 3. **Proactive Protection**
- For high-value wallets
- For known risky addresses
- As part of risk management

### 4. **Policy Changes**
- When updating security policies
- Adjusting delay requirements
- Responding to protocol upgrades

## Checking Current Delay

To check if a delay is set for a specific redemption:

```go
// Build redemption key
redemptionKey := buildRedemptionKey(walletPKH, redeemerOutputScript)

// Query delay from contract
delay, err := redemptionWatchtower.GetRedemptionDelay(redemptionKey)
// Returns: delay in seconds (0 if not set)
```

Or using `cast`:

```bash
# Get redemption key (computed off-chain)
REDEMPTION_KEY="0x..."

# Query delay
cast call $REDEMPTION_WATCHTOWER \
  "getRedemptionDelay(bytes32)(uint256)" \
  $REDEMPTION_KEY \
  --rpc-url $RPC_URL
```

## Summary

| Aspect | Details |
|--------|---------|
| **When Set** | **BEFORE** redemption request creation |
| **Who Sets** | Governance or authorized addresses |
| **How Set** | Direct contract call to `RedemptionWatchtower` |
| **When Checked** | During pending redemption filtering (every coordination window) |
| **Effect** | Prevents requests from being processed until delay period elapses |
| **Default** | 0 seconds (if not set) |
| **Purpose** | Fraud prevention and front-running protection |

## Code References

1. **Delay Query**: `pkg/chain/ethereum/tbtc.go:2390-2409`
2. **Delay Usage**: `pkg/tbtcpg/redemptions.go:378-404`
3. **Key Building**: `pkg/chain/ethereum/tbtc.go:1670-1688`
4. **Request Filtering**: `pkg/tbtcpg/redemptions.go:406-444`


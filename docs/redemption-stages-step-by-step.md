# tBTC Redemption: Complete Step-by-Step Stages with Timing

## Overview

This document provides a complete breakdown of all stages in the tBTC redemption process, from request creation to final settlement, with precise timing for each step.

**Total Average Time**: ~6-7 hours  
**Total Maximum Time**: ~8-9 hours

---

## Stage 1: Redemption Request Creation

**Duration**: ~1-2 minutes  
**Code**: `pkg/chain/ethereum/tbtc.go` (Bridge contract interaction)

### Steps:

1. **User initiates redemption**
   - User calls `Bridge.requestRedemption()` on-chain
   - Provides: amount, redeemer output script (Bitcoin address)
   - Transaction submitted to Ethereum network

2. **Request validation**
   - Bridge contract validates:
     - Sufficient tBTC balance
     - Valid output script format
     - Request within limits
   - `RedemptionRequested` event emitted

3. **Request recorded**
   - Request stored on-chain with timestamp
   - Request becomes "pending"

**Timing**:
- Transaction submission: ~30 seconds
- Block confirmation: ~12 seconds (1 block)
- Event emission: Immediate
- **Total: ~1-2 minutes**

---

## Stage 2: Minimum Age Delay (Waiting Period)

**Duration**: ~2-4 hours (configurable)  
**Code**: `pkg/tbtcpg/redemptions.go:392-403`

### Purpose:
- Security measure to prevent front-running
- Allows time for fraud detection
- Configurable per wallet via `RedemptionWatchtower`

### Steps:

1. **Request timestamp recorded**
   - `RequestedAt` timestamp stored on-chain
   - Used to calculate age

2. **Minimum age check**
   ```go
   minAge = max(requestMinAge, redemptionDelay)
   ```
   - `requestMinAge`: Global minimum (typically 2-4 hours)
   - `redemptionDelay`: Wallet-specific delay (can be higher)

3. **Age validation**
   - Request must be older than `minAge` before processing
   - Checked during proposal generation

**Timing**:
- **Default**: ~2-4 hours (`REDEMPTION_REQUEST_MIN_AGE`)
- **Wallet-specific**: Can be higher if `redemptionDelay` is set
- **Average**: ~2-4 hours

**Storage**: `WalletProposalValidator.requestMinAge` (on-chain)

---

## Stage 3: Coordination Window Arrival

**Duration**: Up to ~3 hours (900 blocks)  
**Code**: `pkg/tbtc/coordination.go:25-44`

### Purpose:
- Periodic windows for wallet coordination
- Prevents conflicts between concurrent actions
- Ensures synchronized execution

### Steps:

1. **Window detection**
   - Coordination windows occur every **900 blocks** (~3 hours)
   - Window starts at blocks: 900, 1800, 2700, 3600, ...
   - Each window has:
     - **Active phase**: 80 blocks (~16 minutes) - communication allowed
     - **Passive phase**: 20 blocks (~4 minutes) - validation/preparation

2. **Window timing**
   ```
   Coordination Block: Block N (where N % 900 == 0)
   Active Phase: Blocks N to N+80 (~16 minutes)
   Passive Phase: Blocks N+80 to N+100 (~4 minutes)
   Next Window: Block N+900 (~3 hours later)
   ```

3. **Waiting for next window**
   - If request created mid-window, waits for next window
   - Maximum wait: ~3 hours (if created just after window start)

**Timing**:
- **Best case**: Request created just before window → ~0 minutes wait
- **Average case**: Request created mid-window → ~1.5 hours wait
- **Worst case**: Request created just after window → ~3 hours wait
- **Average wait**: ~1.5 hours

---

## Stage 4: Proposal Generation

**Duration**: ~1-2 minutes  
**Code**: `pkg/tbtcpg/redemptions.go:33-84`

### Steps:

1. **Find pending redemptions**
   - Query `RedemptionRequested` events
   - Filter by:
     - Not timed out (`now - requestTimeout`)
     - Old enough (`now - minAge`)
     - Not already processed
   - Sort by age (oldest first)

2. **Validate eligibility**
   - Check request age: `RequestedAt < (now - minAge)`
   - Check request timeout: `RequestedAt > (now - requestTimeout)`
   - Verify request still pending on-chain

3. **Build proposal**
   - Collect eligible redemption requests (up to `redemptionMaxSize`)
   - Estimate transaction fee
   - Create `RedemptionProposal`:
     - List of redeemer output scripts
     - Transaction fee amount

4. **Proposal validation**
   - Validate proposal on-chain
   - Check wallet state
   - Verify sufficient funds

**Timing**:
- Event query: ~10-20 seconds
- Validation: ~30 seconds
- Proposal building: ~30 seconds
- **Total: ~1-2 minutes**

---

## Stage 5: Proposal Submission (Coordination)

**Duration**: ~16-20 minutes (active + passive phase)  
**Code**: `pkg/tbtc/coordination.go:340-462`

### Steps:

1. **Leader selection**
   - Compute coordination seed from block hash
   - Select leader deterministically from operators
   - Leader generates proposal

2. **Active phase (80 blocks = ~16 minutes)**
   - Leader broadcasts proposal to followers
   - Followers receive and validate proposal
   - Retransmissions if needed
   - All operators agree on proposal

3. **Passive phase (20 blocks = ~4 minutes)**
   - Operators validate proposal
   - Prepare for execution
   - No communication allowed

4. **Proposal finalized**
   - Proposal becomes valid
   - Execution can begin

**Timing**:
- Leader selection: ~1 minute
- Active phase: ~16 minutes (80 blocks)
- Passive phase: ~4 minutes (20 blocks)
- **Total: ~20 minutes**

---

## Stage 6: Proposal Execution

**Duration**: ~1-1.5 hours  
**Code**: `pkg/tbtc/redemption.go:160-259`

### Sub-Stage 6.1: Proposal Validation

**Duration**: ~7 minutes

**Steps**:
1. **On-chain validation**
   - Validate proposal on-chain
   - Check redemption requests still valid
   - Verify wallet state

2. **UTXO determination**
   - Determine wallet's main UTXO
   - Query Bitcoin chain
   - Verify UTXO exists and is valid

3. **Chain synchronization**
   - Ensure wallet synced between BTC and host chain
   - Verify no conflicting transactions

**Timing**:
- On-chain validation: ~2-3 minutes
- UTXO lookup: ~1-2 minutes
- Chain sync check: ~2-5 minutes
- **Total: ~7 minutes**

### Sub-Stage 6.2: Transaction Assembly

**Duration**: ~1.5 minutes

**Steps**:
1. **Build unsigned transaction**
   - Create Bitcoin transaction structure
   - Add wallet main UTXO as input
   - Add redemption outputs
   - Calculate change output

2. **Compute signature hashes**
   - Compute hash for each input
   - Prepare for signing

**Timing**:
- Transaction assembly: ~30 seconds
- Hash computation: ~30 seconds
- **Total: ~1.5 minutes**

### Sub-Stage 6.3: Multi-Party Threshold Signing

**Duration**: ~30 minutes (average)

**Steps**:
1. **Announcement phase**
   - Operators announce readiness
   - Wait for threshold number of operators
   - Network propagation

2. **Protocol execution**
   - Multi-round cryptographic protocol
   - Signature share generation
   - Share aggregation
   - Threshold signature creation

3. **Retry logic**
   - If some operators slow/unavailable
   - Retry with cooldown (5 blocks = ~1 minute)
   - Multiple attempts if needed

**Timing**:
- Per attempt: ~8 minutes (41 blocks)
- Best case: ~15-20 minutes (first attempt succeeds)
- **Average case: ~30 minutes** (1-2 retries)
- Worst case: Up to 1 hour (300 blocks timeout)

**Code**: `pkg/tbtc/signing_loop.go:22-46`

### Sub-Stage 6.4: Transaction Broadcast

**Duration**: ~15 minutes (maximum timeout)

**Steps**:
1. **Broadcast to Bitcoin network**
   - Send signed transaction to Bitcoin nodes
   - Wait for propagation

2. **Verification**
   - Check transaction known on chain
   - Verify propagation (1 minute check delay)
   - Retry if not confirmed

**Timing**:
- Happy path: ~2-5 minutes
- Average: ~5-10 minutes
- Maximum: **15 minutes** (timeout)

**Code**: `pkg/tbtc/redemption.go:43-48`

### Sub-Stage 6.5: Safety Margin

**Duration**: ~15 minutes (reserved buffer)

**Purpose**:
- Prevents signature leaks if signing completes late
- Ensures enough time for broadcast
- Protects against timing edge cases

**Timing**:
- Reserved: 300 blocks (~1 hour)
- Typically used: ~15 minutes
- Buffer: ~30-45 minutes

**Total Proposal Execution Time**:
- Validation: ~7 minutes
- Assembly: ~1.5 minutes
- Signing: ~30 minutes
- Broadcast: ~15 minutes
- Safety: ~15 minutes
- **Total: ~68 minutes (~1.1 hours)**

---

## Stage 7: Bitcoin Transaction Confirmation

**Duration**: ~1 hour (6 confirmations)  
**Code**: Bitcoin network consensus

### Steps:

1. **Transaction in mempool**
   - Transaction broadcast to Bitcoin network
   - Included in mempool
   - Waiting for miner inclusion

2. **Block inclusion**
   - Miner includes transaction in block
   - First confirmation received
   - Block propagation (~10 minutes)

3. **Additional confirmations**
   - Standard: 6 confirmations for security
   - Each confirmation: ~10 minutes
   - Total: ~60 minutes (6 × 10 min)

**Timing**:
- Mempool inclusion: ~0-10 minutes (varies)
- First confirmation: ~10 minutes (average)
- 6 confirmations: ~60 minutes
- **Total: ~1 hour**

---

## Stage 8: SPV Proof Submission

**Duration**: ~10-20 minutes  
**Code**: `pkg/maintainer/spv/redemptions.go`

### Steps:

1. **SPV proof generation**
   - Generate Simplified Payment Verification proof
   - Include block headers and Merkle proof
   - Verify proof validity

2. **Proof submission**
   - Submit proof to Bridge contract
   - Contract validates proof
   - Redemption marked as completed

3. **Settlement**
   - tBTC tokens burned
   - Redemption finalized on-chain

**Timing**:
- Proof generation: ~2-5 minutes
- Submission: ~1-2 minutes
- Validation: ~5-10 minutes
- **Total: ~10-20 minutes**

---

## Complete Timeline Summary

### Best Case Scenario (~4 hours)

| Stage | Duration | Cumulative |
|-------|----------|------------|
| 1. Request Creation | ~2 min | T+0:02 |
| 2. Min Age Delay | ~2 hours | T+2:02 |
| 3. Window Wait | ~0 min | T+2:02 |
| 4. Proposal Generation | ~2 min | T+2:04 |
| 5. Proposal Submission | ~20 min | T+2:24 |
| 6. Proposal Execution | ~45 min | T+3:09 |
| 7. BTC Confirmation | ~60 min | T+4:09 |
| 8. SPV Proof | ~15 min | T+4:24 |
| **TOTAL** | **~4.5 hours** | |

### Average Case Scenario (~6-7 hours)

| Stage | Duration | Cumulative |
|-------|----------|------------|
| 1. Request Creation | ~2 min | T+0:02 |
| 2. Min Age Delay | ~3 hours | T+3:02 |
| 3. Window Wait | ~1.5 hours | T+4:32 |
| 4. Proposal Generation | ~2 min | T+4:34 |
| 5. Proposal Submission | ~20 min | T+4:54 |
| 6. Proposal Execution | ~68 min | T+6:02 |
| 7. BTC Confirmation | ~60 min | T+7:02 |
| 8. SPV Proof | ~15 min | T+7:17 |
| **TOTAL** | **~7.3 hours** | |

### Worst Case Scenario (~9 hours)

| Stage | Duration | Cumulative |
|-------|----------|------------|
| 1. Request Creation | ~2 min | T+0:02 |
| 2. Min Age Delay | ~4 hours | T+4:02 |
| 3. Window Wait | ~3 hours | T+7:02 |
| 4. Proposal Generation | ~2 min | T+7:04 |
| 5. Proposal Submission | ~20 min | T+7:24 |
| 6. Proposal Execution | ~90 min | T+8:54 |
| 7. BTC Confirmation | ~60 min | T+9:54 |
| 8. SPV Proof | ~20 min | T+10:14 |
| **TOTAL** | **~10 hours** | |

---

## Key Timing Constants

```go
// Minimum Age Delay
REDEMPTION_REQUEST_MIN_AGE = 2-4 hours (configurable)

// Coordination Windows
coordinationFrequencyBlocks = 900 blocks (~3 hours)
coordinationActivePhaseDurationBlocks = 80 blocks (~16 minutes)
coordinationPassivePhaseDurationBlocks = 20 blocks (~4 minutes)

// Proposal Validity
redemptionProposalValidityBlocks = 600 blocks (~2 hours)

// Signing
redemptionSigningTimeoutSafetyMarginBlocks = 300 blocks (~1 hour)
signingAttemptMaximumProtocolBlocks = 30 blocks (~6 minutes)
signingAttemptCoolDownBlocks = 5 blocks (~1 minute)

// Broadcast
redemptionBroadcastTimeout = 15 minutes
redemptionBroadcastCheckDelay = 1 minute

// Bitcoin Confirmation
BitcoinBlockTime = ~10 minutes
ConfirmationsRequired = 6 blocks (~60 minutes)
```

---

## Why Each Stage Takes Time

### Stage 2: Minimum Age Delay (~2-4 hours)
- **Security**: Prevents front-running attacks
- **Fraud Detection**: Allows time to detect suspicious activity
- **Configurable**: Can be adjusted per wallet

### Stage 3: Coordination Window Wait (~0-3 hours)
- **Synchronization**: Ensures all operators coordinate
- **Conflict Prevention**: Prevents concurrent wallet actions
- **Deterministic**: Windows occur every 900 blocks

### Stage 5: Proposal Submission (~20 minutes)
- **Consensus**: Requires agreement from all operators
- **Network Communication**: P2P message propagation
- **Validation**: Operators validate proposal before execution

### Stage 6.3: Signing (~30 minutes)
- **Multi-Party Protocol**: Threshold signing requires coordination
- **Network Latency**: P2P communication between operators
- **Retry Logic**: Multiple attempts if operators slow

### Stage 6.4: Broadcast (~15 minutes)
- **Network Propagation**: Bitcoin network propagation time
- **Verification**: Ensure transaction known on chain
- **Retry Logic**: Retry on failure

### Stage 7: Bitcoin Confirmation (~1 hour)
- **Network Consensus**: Bitcoin network confirmation time
- **Security**: 6 confirmations for finality
- **Block Time**: ~10 minutes per block

---

## References

- Request creation: `pkg/chain/ethereum/tbtc.go`
- Minimum age delay: `pkg/tbtcpg/redemptions.go:392-403`
- Coordination windows: `pkg/tbtc/coordination.go:25-44`
- Proposal generation: `pkg/tbtcpg/redemptions.go:33-84`
- Proposal submission: `pkg/tbtc/coordination.go:340-462`
- Proposal execution: `pkg/tbtc/redemption.go:160-259`
- Signing: `pkg/tbtc/signing_loop.go:22-46`
- Broadcast: `pkg/tbtc/redemption.go:43-48`
- SPV proof: `pkg/maintainer/spv/redemptions.go`


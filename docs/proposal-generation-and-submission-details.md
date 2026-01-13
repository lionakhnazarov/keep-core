# Proposal Generation and Submission: Detailed Breakdown

## Overview

This document provides a detailed breakdown of what happens during **Proposal Generation** (Stage 4) and **Proposal Submission** (Stage 5) in the tBTC redemption process.

---

## Stage 4: Proposal Generation

**Duration**: ~1-2 minutes  
**Code**: `pkg/tbtcpg/redemptions.go:33-236`

### What is Generated

A `RedemptionProposal` contains:
```go
type RedemptionProposal struct {
    RedeemersOutputScripts []bitcoin.Script  // List of Bitcoin addresses to redeem to
    RedemptionTxFee        *big.Int          // Estimated Bitcoin transaction fee
}
```

### Step-by-Step Process

#### Step 4.1: Get Redemption Parameters

**Code**: `pkg/tbtcpg/redemptions.go:45-149`

1. **Get redemption max size**
   ```go
   redemptionMaxSize, err := rt.chain.GetRedemptionMaxSize()
   ```
   - Maximum number of redemptions per proposal
   - Limits transaction size

2. **Get current block number**
   ```go
   currentBlockNumber, err := blockCounter.CurrentBlock()
   ```
   - Used for age calculations

3. **Get minimum age requirement**
   ```go
   requestMinAge, err := rt.chain.GetRedemptionRequestMinAge()
   ```
   - Global minimum age (typically 2-4 hours)
   - From `WalletProposalValidator` contract

4. **Get redemption parameters**
   ```go
   requestTimeout, err := rt.chain.GetRedemptionParameters()
   ```
   - Request timeout duration
   - Other redemption parameters

#### Step 4.2: Find Pending Redemptions

**Code**: `pkg/tbtcpg/redemptions.go:53-57` and `findPendingRedemptions()`

**Process**:

1. **Calculate filter range**
   ```go
   requestTimeoutBlocks = requestTimeout / averageBlockTime
   filterStartBlock = currentBlockNumber - (requestTimeoutBlocks + 1000)
   ```
   - Look back `requestTimeout + 1000 blocks` for events
   - 1000 block buffer for safety

2. **Query `RedemptionRequested` events**
   ```go
   events, err := chain.PastRedemptionRequestedEvents(filter)
   ```
   - Filter by wallet public key hash (if specified)
   - Get all events in the block range

3. **Deduplicate events**
   - Multiple events may target same redemption key
   - Keep only latest event per redemption key
   - Bridge allows only one pending request per key

4. **Sort by age**
   - Sort events from oldest to newest
   - Process oldest requests first

5. **Filter by eligibility**
   ```go
   // Request must be:
   // - Not timed out: RequestedAt > (now - requestTimeout)
   // - Old enough: RequestedAt < (now - minAge)
   //   where minAge = max(requestMinAge, redemptionDelay)
   ```
   
   For each request:
   - Check if still pending on-chain
   - Verify request age meets minimum requirement
   - Verify request hasn't timed out
   - Get wallet-specific delay if exists
   - Calculate effective minimum age: `max(requestMinAge, redemptionDelay)`

6. **Collect eligible requests**
   - Take up to `redemptionMaxSize` requests
   - Stop when limit reached
   - Return list of redeemer output scripts

**Output**: List of `bitcoin.Script` (Bitcoin addresses) to redeem to

#### Step 4.3: Estimate Transaction Fee

**Code**: `pkg/tbtcpg/redemptions.go:200-215`

**Process**:

1. **Check if fee provided**
   - If `fee <= 0`, estimate fee
   - Otherwise use provided fee

2. **Estimate Bitcoin transaction fee**
   ```go
   estimatedFee, err := EstimateRedemptionFee(
       rt.btcChain,
       redeemersOutputScripts,
   )
   ```
   - Query Bitcoin network for fee rates
   - Calculate fee based on transaction size
   - Consider number of outputs

**Output**: Estimated fee in satoshi

#### Step 4.4: Build Proposal

**Code**: `pkg/tbtcpg/redemptions.go:219-222`

**Process**:

1. **Create proposal object**
   ```go
   proposal := &tbtc.RedemptionProposal{
       RedeemersOutputScripts: redeemersOutputScripts,
       RedemptionTxFee:        big.NewInt(fee),
   }
   ```

2. **Proposal contains**:
   - List of redeemer output scripts (Bitcoin addresses)
   - Estimated transaction fee

#### Step 4.5: Validate Proposal On-Chain

**Code**: `pkg/tbtcpg/redemptions.go:224-233`

**Process**:

1. **Call on-chain validation**
   ```go
   _, err := tbtc.ValidateRedemptionProposal(
       taskLogger,
       walletPublicKeyHash,
       proposal,
       rt.chain,
   )
   ```

2. **On-chain checks** (`WalletProposalValidator` contract):
   - Proposal structure is valid
   - Number of redemptions within limits
   - Transaction fee within allowed range
   - Per-redemption fee within limits
   - All redemption requests exist and are pending
   - Wallet has sufficient funds
   - Wallet is not busy (no other action in progress)

3. **Verify each request**
   ```go
   for each redeemerOutputScript:
       request, found, err := chain.GetPendingRedemptionRequest(
           walletPublicKeyHash,
           script,
       )
       // Verify request exists and is pending
   ```

**Output**: Validated `RedemptionProposal` ready for coordination

### Summary: What's in a Proposal

- **Redeemers Output Scripts**: List of Bitcoin addresses (up to `redemptionMaxSize`)
- **Transaction Fee**: Estimated Bitcoin transaction fee in satoshi
- **Validation**: On-chain validation confirms proposal is valid

---

## Stage 5: Proposal Submission (Coordination)

**Duration**: ~20 minutes (80 blocks active + 20 blocks passive)  
**Code**: `pkg/tbtc/coordination.go:340-462`

### Purpose

- Ensure all operators agree on the proposal
- Prevent conflicts between concurrent actions
- Synchronize execution across operators

### Step-by-Step Process

#### Step 5.1: Window Detection

**Code**: `pkg/tbtc/coordination.go:122-150`

**Process**:

1. **Detect coordination window**
   - Windows occur every 900 blocks (~3 hours)
   - Window starts at blocks: 900, 1800, 2700, ...
   - Each window has:
     - **Active phase**: Blocks N to N+80 (~16 minutes)
     - **Passive phase**: Blocks N+80 to N+100 (~4 minutes)

2. **Window validation**
   ```go
   if window.index() == 0 {
       return error("invalid coordination block")
   }
   ```
   - Verify window is valid
   - Window index must be > 0

#### Step 5.2: Compute Coordination Seed

**Code**: `pkg/tbtc/coordination.go:375-380`

**Process**:

1. **Get seed from block hash**
   ```go
   seed, err := ce.getSeed(window.coordinationBlock)
   ```
   - Uses block hash at `coordinationBlock + 32`
   - Deterministic seed for leader selection

2. **Seed purpose**:
   - Determines which operator is leader
   - Ensures deterministic leader selection
   - Same seed = same leader

#### Step 5.3: Leader Selection

**Code**: `pkg/tbtc/coordination.go:382-384`

**Process**:

1. **Select leader deterministically**
   ```go
   leader := ce.getLeader(seed)
   ```
   - Uses coordination seed
   - Selects operator from wallet's signing group
   - Same seed always selects same leader

2. **Leader responsibilities**:
   - Generate proposal (if not already generated)
   - Broadcast proposal to followers
   - Retransmit if needed

#### Step 5.4: Actions Checklist

**Code**: `pkg/tbtc/coordination.go:386-388`

**Process**:

1. **Determine allowed actions**
   ```go
   actionsChecklist := ce.getActionsChecklist(window.index(), seed)
   ```
   - Redemption: Checked every window
   - Deposit sweep: Every 4 windows
   - Moved funds sweep: Every 4 windows
   - Moving funds: Every 4 windows
   - Heartbeat: Random (6.25% probability)

2. **Priority order**:
   - Redemption (highest priority)
   - Other actions (lower priority)
   - No-op (if no action needed)

#### Step 5.5: Active Phase - Leader Routine

**Code**: `pkg/tbtc/coordination.go:410-431` and `executeLeaderRoutine()`

**Duration**: 80 blocks (~16 minutes)

**Process**:

1. **Generate proposal** (if leader)
   ```go
   proposal, err := ce.generateProposal(
       &CoordinationProposalRequest{
           WalletPublicKeyHash: walletPublicKeyHash,
           WalletOperators:     signingGroupOperators,
           ExecutingOperator:   operatorAddress,
           ActionsChecklist:    actionsChecklist,
       },
       2,             // 2 attempts max
       1*time.Minute, // 1 minute between attempts
   )
   ```
   - Calls `RedemptionTask.Run()` (Stage 4)
   - Retries up to 2 times if generation fails
   - Waits 1 minute between retries

2. **Create coordination message**
   ```go
   message := &coordinationMessage{
       senderID:            senderID,           // Member index
       coordinationBlock:   coordinationBlock,   // Window block number
       walletPublicKeyHash: walletPublicKeyHash, // Wallet identifier
       proposal:            proposal,            // The proposal
   }
   ```

3. **Broadcast message**
   ```go
   err = ce.broadcastChannel.Send(
       ctx,
       message,
       net.BackoffRetransmissionStrategy,
   )
   ```
   - Send via libp2p broadcast channel
   - Retransmit with backoff strategy
   - Keep sending until active phase ends
   - Ensures all followers receive message

4. **Message structure**:
   - `senderID`: Member index of sender
   - `coordinationBlock`: Block number of coordination window
   - `walletPublicKeyHash`: 20-byte wallet identifier
   - `proposal`: The actual proposal (RedemptionProposal)

#### Step 5.6: Active Phase - Follower Routine

**Code**: `pkg/tbtc/coordination.go:434-461` and `executeFollowerRoutine()`

**Duration**: Until message received (typically < 1 minute)

**Process**:

1. **Listen for coordination message**
   ```go
   ce.broadcastChannel.Recv(ctx, func(message net.Message) {
       messagesChan <- message
   })
   ```
   - Listen on broadcast channel
   - Buffer messages in channel

2. **Filter messages** (multiple checks):

   a. **Message type check**
      ```go
      message, ok := netMessage.Payload().(*coordinationMessage)
      ```
      - Must be coordination message type

   b. **Self-filter**
      ```go
      if slices.Contains(ce.membersIndexes, message.senderID) {
          continue  // Ignore own messages
      }
      ```

   c. **Membership validation**
      ```go
      if !ce.membershipValidator.IsValidMembership(
          message.senderID,
          netMessage.SenderPublicKey(),
      ) {
          continue  // Invalid membership
      }
      ```

   d. **Coordination block check**
      ```go
      if coordinationBlock != message.coordinationBlock {
          continue  // Wrong window
      }
      ```

   e. **Wallet check**
      ```go
      if walletPublicKeyHash != message.walletPublicKeyHash {
          continue  // Wrong wallet
      }
      ```

   f. **Leader verification**
      ```go
      if leaderID != message.senderID {
          // Record fault: leader impersonation
          faults = append(faults, &coordinationFault{
              culprit:   sender,
              faultType: FaultLeaderImpersonation,
          })
          continue
      }
      ```

   g. **Action validation**
      ```go
      if !slices.Contains(actionsAllowed, message.proposal.ActionType()) {
          // Record fault: leader mistake
          faults = append(faults, &coordinationFault{
              culprit:   leader,
              faultType: FaultLeaderMistake,
          })
          continue
      }
      ```

3. **Accept proposal**
   - If all checks pass, accept proposal
   - Return proposal and any observed faults
   - Prepare for execution

4. **Timeout handling**
   - If active phase ends without valid message:
     - Record fault: `FaultLeaderIdleness`
     - Return error

#### Step 5.7: Passive Phase

**Duration**: 20 blocks (~4 minutes)

**Process**:

1. **No communication allowed**
   - Operators validate proposal independently
   - Prepare for execution
   - No messages sent/received

2. **Validation**
   - Each operator validates proposal
   - Ensures proposal is executable
   - Prepares execution context

3. **Preparation**
   - Set up execution environment
   - Initialize transaction executor
   - Prepare wallet state

#### Step 5.8: Coordination Result

**Code**: `pkg/tbtc/coordination.go:464-485`

**Process**:

1. **Create coordination result**
   ```go
   result := &coordinationResult{
       wallet:   coordinatedWallet,
       window:   window,
       leader:   leader,
       proposal: proposal,
       faults:   faults,
   }
   ```

2. **Result contains**:
   - Wallet being coordinated
   - Coordination window
   - Leader address
   - Final proposal (agreed by all)
   - Any observed faults

3. **Proposal becomes valid**
   - All operators agree on proposal
   - Proposal ready for execution
   - Execution can begin

### Summary: What Happens During Submission

**Active Phase (80 blocks = ~16 minutes)**:
- Leader generates proposal (if needed)
- Leader broadcasts proposal to followers
- Followers receive and validate proposal
- All operators agree on proposal

**Passive Phase (20 blocks = ~4 minutes)**:
- No communication
- Operators validate proposal
- Prepare for execution

**Result**:
- All operators have same proposal
- Proposal validated and ready
- Execution can begin

---

## Key Data Structures

### CoordinationMessage

```go
type coordinationMessage struct {
    senderID            group.MemberIndex  // Member index of sender
    coordinationBlock   uint64              // Window block number
    walletPublicKeyHash [20]byte            // Wallet identifier
    proposal            CoordinationProposal // The proposal
}
```

### RedemptionProposal

```go
type RedemptionProposal struct {
    RedeemersOutputScripts []bitcoin.Script  // Bitcoin addresses
    RedemptionTxFee        *big.Int          // Fee in satoshi
}
```

### CoordinationResult

```go
type coordinationResult struct {
    wallet   wallet              // Wallet being coordinated
    window   *coordinationWindow // Coordination window
    leader   chain.Address       // Leader operator
    proposal CoordinationProposal // Final proposal
    faults   []*coordinationFault // Observed faults
}
```

---

## Fault Detection

During coordination, followers detect and record faults:

1. **FaultLeaderImpersonation**: Non-leader operator sends message claiming to be leader
2. **FaultLeaderMistake**: Leader proposes action not in allowed checklist
3. **FaultLeaderIdleness**: Leader fails to send message during active phase

Faults are recorded but don't prevent coordination from completing.

---

## Timing Breakdown

### Proposal Generation (~1-2 minutes)

| Step | Time | Details |
|------|------|---------|
| Get parameters | ~10 sec | Query on-chain parameters |
| Find redemptions | ~30 sec | Query events, filter, validate |
| Estimate fee | ~20 sec | Query Bitcoin network |
| Build proposal | ~5 sec | Create proposal object |
| Validate | ~30 sec | On-chain validation |
| **Total** | **~1.5 min** | |

### Proposal Submission (~20 minutes)

| Phase | Duration | Details |
|-------|----------|---------|
| Seed computation | ~1 min | Compute from block hash |
| Leader selection | ~1 min | Deterministic selection |
| Active phase | ~16 min | Leader broadcasts, followers receive |
| Passive phase | ~4 min | Validation and preparation |
| **Total** | **~20 min** | |

---

## Code References

- Proposal generation: `pkg/tbtcpg/redemptions.go:33-236`
- Find pending redemptions: `pkg/tbtcpg/redemptions.go:238-420`
- Coordination execution: `pkg/tbtc/coordination.go:340-462`
- Leader routine: `pkg/tbtc/coordination.go:602-649`
- Follower routine: `pkg/tbtc/coordination.go:685-784`
- Proposal validation: `pkg/tbtc/redemption.go:261-326`
- On-chain validation: `pkg/chain/ethereum/tbtc.go:2155-2181`


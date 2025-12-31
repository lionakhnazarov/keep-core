# Local Development Setup Guide

Complete guide for setting up a local tBTC development environment.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Setup](#initial-setup)
   - [Step-by-Step Action List for Fresh Setup](#step-by-step-action-list-for-fresh-setup)
   - [Start Geth Node](#step-1-start-geth-node)
   - [Deploy All Contracts](#step-2-deploy-all-contracts)
   - [Verify Deployments](#step-3-verify-deployments)
3. [Node Configuration](#node-configuration)
4. [Wallet Creation](#wallet-creation)
5. [Deposit Testing](#deposit-testing)
6. [Useful Commands](#useful-commands)
7. [Troubleshooting](#troubleshooting)

**Quick Reference**: See [`FRESH_SETUP_CHECKLIST.md`](./FRESH_SETUP_CHECKLIST.md) for a printable checklist version.

---

## Prerequisites

- Go 1.19+
- Node.js 16+ and Yarn
- Git
- Geth (Ethereum client)
- `cast` (Foundry tool)
- `jq` (JSON processor)
- `openssl` (for cryptographic operations)

---

## Initial Setup

### Step-by-Step Action List for Fresh Setup

This section provides a detailed checklist of all actions performed during a fresh setup. Run `./scripts/complete-reset.sh` to execute all steps automatically, or follow this list manually.

#### Phase 1: Environment Cleanup

1. **Stop Geth** (if running)
   - Kill any existing Geth processes on port 8545
   - Wait 3 seconds for cleanup

2. **Delete Chaindata**
   - Remove `~/ethereum/data/geth/` directory
   - Clears all blockchain state for fresh start

3. **Clean Deployment Files**
   - Remove RandomBeacon deployment JSONs: `solidity/random-beacon/deployments/development/*.json`
   - Remove ECDSA deployment JSONs: `solidity/ecdsa/deployments/development/*.json`
   - Remove OpenZeppelin manifest: `solidity/ecdsa/.openzeppelin/`
   - Remove TBTC stub deployments: `solidity/tbtc-stub/deployments/development/*.json`
   - Remove T token deployments: `tmp/solidity-contracts/deployments/development/*.json`

#### Phase 2: Blockchain Initialization

4. **Start Geth Node**
   - Execute `./scripts/start-geth-fast.sh` in background
   - Wait for Geth to initialize (5 seconds)
   - Verify Geth is responding: `cast block-number --rpc-url http://localhost:8545`

5. **Unlock Ethereum Accounts**
   - Extract private keys from Geth keystore
   - Unlock accounts using Hardhat unlock-accounts task
   - Fallback: Use `cast rpc personal_unlockAccount` for each account

#### Phase 3: Contract Deployment

6. **Deploy Threshold Network Contracts**
   - Clone `threshold-network/solidity-contracts` to `tmp/solidity-contracts`
   - Build contracts: `yarn install && yarn build`
   - Deploy T token: `yarn deploy --network development --reset`
   - Deploy TokenStaking contract
   - **Result**: T token and TokenStaking addresses saved

7. **Deploy ExtendedTokenStaking** (Development Only)
   - Navigate to `solidity/ecdsa/`
   - Deploy ExtendedTokenStaking: `npx hardhat deploy --network development --tags ExtendedTokenStaking`
   - Mint T tokens if totalSupply is zero (1M tokens to deployer)
   - Save as TokenStaking for development use
   - **Result**: ExtendedTokenStaking address saved

8. **Deploy Random Beacon Contracts**
   - Navigate to `solidity/random-beacon/`
   - Deploy ReimbursementPool (with staticGas: 40,800, maxGasPrice: 500 Gwei)
   - Deploy BeaconSortitionPool (with T token address, poolWeightDivisor: 1e18)
   - Deploy BeaconDkgValidator
   - Deploy libraries: BLS, BeaconAuthorization, BeaconDkg, BeaconInactivity
   - Deploy RandomBeacon (with all dependencies)
   - Deploy RandomBeaconChaosnet
   - Deploy RandomBeaconGovernance
   - **Result**: All RandomBeacon contracts deployed

9. **Approve RandomBeacon in TokenStaking**
   - Execute approval transaction: `npx hardhat deploy --network development --tags RandomBeaconApprove`
   - **Result**: RandomBeacon authorized in TokenStaking

10. **Deploy ECDSA Contracts**
    - Navigate to `solidity/ecdsa/`
    - Deploy EcdsaSortitionPool (with T token address, poolWeightDivisor: 1e18)
    - Deploy EcdsaDkgValidator
    - Deploy EcdsaInactivity library
    - Deploy WalletRegistry as TransparentUpgradeableProxy
      - Implementation contract with EcdsaInactivity library
      - Proxy with EcdsaSortitionPool and TokenStaking addresses
      - Initialize with EcdsaDkgValidator, RandomBeacon, ReimbursementPool
    - Deploy WalletRegistryGovernance
    - Deploy ProxyAdmin (OpenZeppelin)
    - **Result**: All ECDSA contracts deployed

11. **Deploy TBTC Stub Contracts**
    - Navigate to `solidity/tbtc-stub/`
    - Deploy BridgeStub (with WalletRegistry address, ReimbursementPool address)
    - Save as `Bridge.json` for compatibility
    - Deploy MaintainerProxyStub
    - Save as `MaintainerProxy.json`
    - Deploy WalletProposalValidatorStub
    - Save as `WalletProposalValidator.json`
    - **Result**: All TBTC stub contracts deployed

#### Phase 4: Contract Configuration

12. **Transfer Ownerships**
    - Transfer BeaconSortitionPool ownership → RandomBeacon contract
    - Transfer EcdsaSortitionPool ownership → WalletRegistry contract
    - Transfer chaosnet owner roles (if applicable)

13. **Initialize WalletRegistry walletOwner**
    - Read Bridge address from `solidity/tbtc-stub/deployments/development/Bridge.json`
    - Read WalletRegistry address from `solidity/ecdsa/deployments/development/WalletRegistry.json`
    - Check current walletOwner
    - If not set: Execute `npx hardhat run scripts/init-wallet-owner.ts --network development`
    - Verify walletOwner was set correctly
    - **Result**: Bridge set as WalletRegistry's walletOwner

#### Phase 5: Operator Setup

14. **Extract Operator Addresses**
    - Scan `configs/node*.toml` files
    - Read KeyFile path from each config
    - Extract operator address from each keyfile JSON
    - **Result**: List of operator addresses

15. **Initialize Operators** (Stake & Authorize)
    - For each operator:
      - Initialize RandomBeacon: `npx hardhat initialize --network development --owner <operator> --provider <operator> --operator <operator> --beneficiary <operator> --authorizer <operator> --amount 1000000`
      - Initialize WalletRegistry: Same command in ECDSA directory
      - Stake 1M T tokens (default)
      - Authorize with minimum authorization amount
    - **Result**: All operators staked and authorized

16. **Verify Operator Initialization**
    - For each operator:
      - Check `eligibleStake(address)` in ExtendedTokenStaking
      - Verify stake > 0
    - Re-initialize any operators with zero stake
    - **Result**: All operators have eligible stake

17. **Fund Operators with ETH**
    - Execute `./scripts/fund-operators.sh <num_nodes> 1`
    - Send 1 ETH to each operator address
    - **Result**: Operators funded for gas

18. **Join Operators to Sortition Pools**
    - For each operator:
      - Join RandomBeacon pool: `keep-client ethereum beacon random-beacon join-sortition-pool --submit --config configs/node<N>.toml --developer`
      - Join WalletRegistry pool: `keep-client ethereum ecdsa wallet-registry join-sortition-pool --submit --config configs/node<N>.toml --developer`
    - **Result**: Operators eligible for selection

#### Phase 6: DKG Configuration

19. **Set Minimum DKG Parameters**
    - Execute `./scripts/set-minimum-dkg-params.sh`
    - Set group formation timeout (development: ~100 blocks)
    - Set result challenge period (development: ~50 blocks)
    - Set result submission timeout (development: ~200 blocks)
    - **Result**: DKG parameters configured for development

#### Phase 7: Configuration Files Update

20. **Update Config Files with Contract Addresses**
    - Read deployed addresses:
      - WalletRegistry: `solidity/ecdsa/deployments/development/WalletRegistry.json`
      - RandomBeacon: `solidity/random-beacon/deployments/development/RandomBeacon.json`
      - TokenStaking: `solidity/ecdsa/deployments/development/ExtendedTokenStaking.json`
      - Bridge: `solidity/tbtc-stub/deployments/development/Bridge.json`
      - MaintainerProxy: `solidity/tbtc-stub/deployments/development/MaintainerProxy.json`
      - WalletProposalValidator: `solidity/tbtc-stub/deployments/development/WalletProposalValidator.json`
    - Update config files:
      - `config.toml`
      - `node5.toml`
      - `configs/config.toml`
      - `configs/node*.toml` (all node configs)
    - Replace addresses using sed:
      - `RandomBeaconAddress`
      - `WalletRegistryAddress`
      - `TokenStakingAddress`
      - `BridgeAddress`
      - `MaintainerProxyAddress`
      - `WalletProposalValidatorAddress`
    - **Result**: All config files updated with new addresses

#### Phase 8: Node Restart

21. **Restart All Nodes**
    - Stop existing keep-client processes: `pkill -f "keep-client.*start"`
    - Wait 2 seconds
    - Execute `./scripts/restart-all-nodes.sh`
    - **Result**: All nodes restarted with new configuration

#### Verification Checklist

After completion, verify:

- [ ] Geth is running and producing blocks
- [ ] All contracts deployed (check deployment JSONs exist)
- [ ] WalletRegistry.walletOwner() == Bridge address
- [ ] All operators have eligibleStake > 0
- [ ] All operators are in sortition pools (check `isOperatorInPool`)
- [ ] DKG parameters are set (check `getDkgParameters`)
- [ ] Config files have correct addresses
- [ ] Nodes are running (check logs)

---

### Step 1: Start Geth Node

```bash
# Start Geth with fast block production (Clique PoA)
./scripts/start-geth-fast.sh
```

**Important**: Ensure Geth is producing blocks. Check with:
```bash
cast block-number --rpc-url http://localhost:8545
# Should increment over time
```

### Step 2: Deploy All Contracts

```bash
# Deploy Threshold Network, Random Beacon, ECDSA, and TBTC contracts
./scripts/complete-reset.sh
```

This script automates:
- ✅ Contract deployment (Threshold, Random Beacon, ECDSA, TBTC stubs)
- ✅ Operator funding
- ✅ Operator initialization
- ✅ Sortition pool joining
- ✅ DKG parameter configuration
- ✅ WalletOwner initialization

#### Complete List of Smart Contract Deployments

The `complete-reset.sh` script deploys the following contracts in order:

##### 1. Threshold Network Contracts (`tmp/solidity-contracts`)
Deployed via `./scripts/install.sh --network development`:

| Contract | Purpose | Location |
|----------|---------|----------|
| **T** | Threshold Network token (T token) | `tmp/solidity-contracts/deployments/development/T.json` |
| **TokenStaking** | Base staking contract (used in production) | `tmp/solidity-contracts/deployments/development/TokenStaking.json` |

**Note**: For development, `ExtendedTokenStaking` is deployed separately (see ECDSA section below).

##### 2. Extended Token Staking (Development Only)
Deployed before RandomBeacon to enable `stake()` function:

| Contract | Purpose | Location |
|----------|---------|----------|
| **ExtendedTokenStaking** | Development version with `stake()` function | `solidity/ecdsa/deployments/development/ExtendedTokenStaking.json` |

##### 3. Random Beacon Contracts (`solidity/random-beacon`)
Deployed via `npx hardhat deploy --network development --tags RandomBeacon`:

| Contract | Purpose | Location |
|----------|---------|----------|
| **ReimbursementPool** | Gas reimbursement for operators | `solidity/random-beacon/deployments/development/ReimbursementPool.json` |
| **BeaconSortitionPool** | Operator selection pool for Random Beacon | `solidity/random-beacon/deployments/development/BeaconSortitionPool.json` |
| **BeaconDkgValidator** | DKG result validation for Random Beacon | `solidity/random-beacon/deployments/development/BeaconDkgValidator.json` |
| **BLS** | BLS signature library | `solidity/random-beacon/deployments/development/BLS.json` |
| **BeaconAuthorization** | Authorization logic library | `solidity/random-beacon/deployments/development/BeaconAuthorization.json` |
| **BeaconDkg** | DKG logic library | `solidity/random-beacon/deployments/development/BeaconDkg.json` |
| **BeaconInactivity** | Inactivity tracking library | `solidity/random-beacon/deployments/development/BeaconInactivity.json` |
| **RandomBeacon** | Main Random Beacon contract | `solidity/random-beacon/deployments/development/RandomBeacon.json` |
| **RandomBeaconChaosnet** | Chaosnet-specific Random Beacon | `solidity/random-beacon/deployments/development/RandomBeaconChaosnet.json` |
| **RandomBeaconGovernance** | Governance for Random Beacon | `solidity/random-beacon/deployments/development/RandomBeaconGovernance.json` |

**Deployment Tags**: `RandomBeacon`, `RandomBeaconChaosnet`, `RandomBeaconGovernance`, `RandomBeaconApprove`

##### 4. ECDSA Contracts (`solidity/ecdsa`)
Deployed via `npx hardhat deploy --network development`:

| Contract | Purpose | Location |
|----------|---------|----------|
| **EcdsaSortitionPool** | Operator selection pool for ECDSA wallets | `solidity/ecdsa/deployments/development/EcdsaSortitionPool.json` |
| **EcdsaDkgValidator** | DKG result validation for ECDSA wallets | `solidity/ecdsa/deployments/development/EcdsaDkgValidator.json` |
| **EcdsaInactivity** | Inactivity tracking library | `solidity/ecdsa/deployments/development/EcdsaInactivity.json` |
| **WalletRegistry** | Main ECDSA wallet registry (proxy) | `solidity/ecdsa/deployments/development/WalletRegistry.json` |
| **WalletRegistryGovernance** | Governance for WalletRegistry | `solidity/ecdsa/deployments/development/WalletRegistryGovernance.json` |
| **ProxyAdmin** | OpenZeppelin proxy admin | `solidity/ecdsa/.openzeppelin/unknown-development.json` |

**Note**: `WalletRegistry` is deployed as a TransparentUpgradeableProxy using OpenZeppelin's upgradeable pattern.

##### 5. TBTC Stub Contracts (`solidity/tbtc-stub`)
Deployed via `npx hardhat deploy --network development --tags TBTCStubs`:

| Contract | Purpose | Location |
|----------|---------|----------|
| **BridgeStub** | Minimal Bridge implementation (saved as `Bridge`) | `solidity/tbtc-stub/deployments/development/Bridge.json` |
| **MaintainerProxyStub** | Minimal MaintainerProxy (saved as `MaintainerProxy`) | `solidity/tbtc-stub/deployments/development/MaintainerProxy.json` |
| **WalletProposalValidatorStub** | Minimal validator (saved as `WalletProposalValidator`) | `solidity/tbtc-stub/deployments/development/WalletProposalValidator.json` |

**Note**: These are stub contracts with minimal functionality. For full deposit/redemption testing, deploy the complete Bridge from `tbtc-v2` repository (see Step 10).

#### Deployment Dependencies

Contracts must be deployed in this order due to dependencies:

```
1. T Token
   └─> ExtendedTokenStaking (depends on T)
       └─> ReimbursementPool
           └─> BeaconSortitionPool (depends on T)
               └─> BeaconDkgValidator
                   └─> RandomBeacon (depends on all above)
                       └─> RandomBeaconChaosnet
                           └─> RandomBeaconGovernance
                               └─> EcdsaSortitionPool (depends on T)
                                   └─> EcdsaDkgValidator
                                       └─> WalletRegistry (depends on RandomBeacon, ReimbursementPool)
                                           └─> BridgeStub (depends on WalletRegistry)
```

#### Post-Deployment Configuration

After deployment, the script performs:

1. **RandomBeacon Approval**: Approves RandomBeacon in TokenStaking
2. **WalletOwner Initialization**: Sets Bridge as WalletRegistry's `walletOwner`
3. **Ownership Transfers**:
   - BeaconSortitionPool → RandomBeacon
   - EcdsaSortitionPool → WalletRegistry

**Alternative**: Deploy step-by-step:
```bash
# 1. Deploy Threshold Network contracts
./scripts/install.sh --network development

# 2. Deploy ExtendedTokenStaking (development only)
cd solidity/ecdsa
npx hardhat deploy --network development --tags ExtendedTokenStaking

# 3. Deploy Random Beacon contracts
cd ../random-beacon
npx hardhat deploy --network development --tags RandomBeacon
npx hardhat deploy --network development --tags RandomBeaconChaosnet
npx hardhat deploy --network development --tags RandomBeaconGovernance
npx hardhat deploy --network development --tags RandomBeaconApprove

# 4. Deploy ECDSA contracts
cd ../ecdsa
npx hardhat deploy --network development

# 5. Deploy TBTC stubs
cd ../tbtc-stub
npx hardhat deploy --network development --tags TBTCStubs

# 6. Initialize WalletOwner
cd ../ecdsa
BRIDGE=$(jq -r '.address' ../tbtc-stub/deployments/development/Bridge.json)
npx hardhat run scripts/init-wallet-owner.ts --network development
```

### Step 3: Verify Deployments

```bash
# Check all contract addresses
./scripts/check-deployments.sh

# Or manually check:
jq -r '.address' solidity/ecdsa/deployments/development/WalletRegistry.json
jq -r '.address' solidity/tbtc-stub/deployments/development/BridgeStub.json
```

---

## Node Configuration

### Step 4: Configure and Start Nodes

The `complete-reset.sh` script handles operator setup, but if you need to do it manually:

```bash
# Initialize all operators
./scripts/initialize-all-operators.sh

# Join all operators to sortition pools
./scripts/join-all-operators-to-pools.sh

# Restart all nodes
./scripts/restart-all-nodes.sh
```

### Step 5: Verify Node Status

```bash
# Check node logs
tail -f logs/node1.log

# Check if operators are in sortition pools
WR=$(jq -r '.address' solidity/ecdsa/deployments/development/WalletRegistry.json)
OPERATOR_ADDR="0x..." # Your operator address
cast call $WR "isOperatorInPool(address)" $OPERATOR_ADDR --rpc-url http://localhost:8545
```

---

## Wallet Creation

### Step 6: Request New Wallet

```bash
# Request wallet creation (triggers DKG)
./scripts/request-new-wallet.sh
```

**What happens:**
1. Bridge calls `WalletRegistry.requestNewWallet()`
2. DKG process starts (off-chain)
3. DKG result is submitted to blockchain
4. DKG result is approved
5. Wallet is created and `WalletCreated` event is emitted

### Step 7: Check Wallet Status

```bash
# List all created wallets
./scripts/check-wallet-status.sh
```

**Manual check:**
```bash
WR=$(jq -r '.address' solidity/ecdsa/deployments/development/WalletRegistry.json)

# Check DKG state
cast call $WR "getWalletCreationState()" --rpc-url http://localhost:8545
# 0 = IDLE, 1 = AWAITING_SEED, 2 = AWAITING_RESULT, 3 = CHALLENGE

# Check for WalletCreated events
cast logs --from-block 0 --to-block latest \
  --address $WR \
  "WalletCreated(bytes32,bytes32)" \
  --rpc-url http://localhost:8545 \
  --json
```

### Step 8: Monitor DKG Progress

```bash
# Watch node logs for DKG progress
tail -f logs/node1.log | grep -i "dkg\|wallet\|tss"

# Check for DKG events
WR=$(jq -r '.address' solidity/ecdsa/deployments/development/WalletRegistry.json)
cast logs --from-block 0 --to-block latest \
  --address $WR \
  "DkgResultSubmitted(bytes32,uint256)" \
  --rpc-url http://localhost:8545

cast logs --from-block 0 --to-block latest \
  --address $WR \
  "DkgResultApproved(bytes32,address)" \
  --rpc-url http://localhost:8545
```

---

## Deposit Testing

### Step 9: Prepare Deposit Data

```bash
# Generate deposit data structures
./scripts/emulate-deposit.sh [depositor_address] [amount_satoshis]

# Example: Generate deposit for specific address with 0.5 BTC
./scripts/emulate-deposit.sh 0x1234...abcd 50000000
```

**Output**: Files in `deposit-data/`:
- `deposit-data.json` - Complete deposit info
- `funding-tx-info.json` - BitcoinTxInfo structure
- `deposit-reveal-info.json` - DepositDepositRevealInfo structure

### Step 10: Deploy Complete Bridge Contract (Optional)

**Note**: BridgeStub doesn't implement `revealDeposit()`. For full deposit functionality:

```bash
# Deploy complete Bridge from tbtc-v2
./scripts/deploy-bridge-complete.sh
```

This will:
1. Clone tbtc-v2 repository
2. Build and deploy complete Bridge contract
3. Set Bridge as WalletRegistry's walletOwner

### Step 11: Reveal Deposit (If Full Bridge Deployed)

```bash
BRIDGE=$(jq -r '.address' tmp/tbtc-v2/solidity/deployments/development/Bridge.json)

# Using cast
cast send $BRIDGE \
  "revealDeposit((bytes4,bytes,bytes,bytes4),(uint32,bytes8,bytes20,bytes20,bytes4,address))" \
  "$(cat deposit-data/funding-tx-info.json | jq -c .)" \
  "$(cat deposit-data/deposit-reveal-info.json | jq -c .)" \
  --rpc-url http://localhost:8545

# Or using keep-client (if available)
keep-client bridge reveal-deposit \
  --funding-tx-info "$(cat deposit-data/funding-tx-info.json | jq -c .)" \
  --deposit-reveal-info "$(cat deposit-data/deposit-reveal-info.json | jq -c .)"
```

---

## Useful Commands

### Contract Addresses

```bash
# Get contract addresses
WR=$(jq -r '.address' solidity/ecdsa/deployments/development/WalletRegistry.json)
BRIDGE=$(jq -r '.address' solidity/tbtc-stub/deployments/development/BridgeStub.json)
RB=$(jq -r '.address' solidity/random-beacon/deployments/development/RandomBeacon.json)

echo "WalletRegistry: $WR"
echo "Bridge: $BRIDGE"
echo "RandomBeacon: $RB"
```

### Check Operator Status

```bash
# Check if operator is registered
OPERATOR="0x..." # Operator address
cast call $WR "isOperatorRegistered(address)" $OPERATOR --rpc-url http://localhost:8545

# Check eligible stake
cast call $WR "eligibleStake(address)" $OPERATOR --rpc-url http://localhost:8545

# Check minimum authorization
cast call $WR "minimumAuthorization()" --rpc-url http://localhost:8545
```

### Monitor Events

```bash
# Monitor all tBTC events
./scripts/monitor-tbtc-events.sh

# Check for specific events
WR=$(jq -r '.address' solidity/ecdsa/deployments/development/WalletRegistry.json)
FROM_BLOCK=$(cast block-number --rpc-url http://localhost:8545 | cast --to-dec)
FROM_BLOCK=$((FROM_BLOCK - 1000))

# WalletCreated events
cast logs --from-block $FROM_BLOCK --to-block latest \
  --address $WR \
  "WalletCreated(bytes32,bytes32)" \
  --rpc-url http://localhost:8545 \
  --json
```

### Reset Everything

```bash
# Complete reset (deploys contracts, initializes operators, creates wallet)
./scripts/complete-reset.sh

# Or reset just DKG if stuck
./scripts/reset-dkg-if-timed-out.sh
```

---

## Troubleshooting

### Issue: Geth Not Producing Blocks

**Solution**:
```bash
# Stop Geth
pkill -f geth

# Remove chaindata
rm -rf ~/ethereum/data/geth/chaindata

# Restart with fast mining
./scripts/start-geth-fast.sh
```

### Issue: Operators Not Joining Sortition Pools

**Symptoms**: `Failed: 10` when joining pools

**Solution**:
```bash
# Check operator authorization
OPERATOR="0x..."
cast call $WR "eligibleStake(address)" $OPERATOR --rpc-url http://localhost:8545

# Re-initialize operators
./scripts/initialize-all-operators.sh

# Try joining again
./scripts/join-all-operators-to-pools.sh
```

### Issue: DKG Stuck in AWAITING_RESULT

**Solution**:
```bash
# Check DKG state
cast call $WR "getWalletCreationState()" --rpc-url http://localhost:8545

# Wait for blocks to progress (DKG has timeouts)
# Or reset DKG if timed out
./scripts/reset-dkg-if-timed-out.sh
```

### Issue: WalletOwner Not Set

**Solution**:
```bash
# Check current walletOwner
cast call $WR "walletOwner()" --rpc-url http://localhost:8545

# Set Bridge as walletOwner
BRIDGE=$(jq -r '.address' solidity/tbtc-stub/deployments/development/BridgeStub.json)
cd solidity/ecdsa
npx hardhat run scripts/init-wallet-owner.ts --network development -- --wallet-owner-address $BRIDGE
```

### Issue: DKG Result Approval Fails

**Symptoms**: `execution reverted` when approving DKG result

**Solution**: Ensure BridgeStub has callback functions:
- `__ecdsaWalletCreatedCallback`
- `__ecdsaWalletHeartbeatFailedCallback`

These should already be in `solidity/tbtc-stub/contracts/BridgeStub.sol`. If not, redeploy:
```bash
cd solidity/tbtc-stub
yarn deploy --network development --reset
```

---

## Quick Reference: Complete Setup Flow

```bash
# 1. Start Geth
./scripts/start-geth-fast.sh

# 2. Deploy everything and initialize operators
./scripts/complete-reset.sh

# 3. Request wallet creation
./scripts/request-new-wallet.sh

# 4. Monitor wallet creation (wait for DKG to complete)
tail -f logs/node1.log | grep -i "wallet\|dkg"

# 5. Check wallet status
./scripts/check-wallet-status.sh

# 6. Prepare deposit data
./scripts/emulate-deposit.sh

# 7. (Optional) Deploy complete Bridge for deposit testing
./scripts/deploy-bridge-complete.sh
```

---

## Script Reference

| Script | Purpose |
|--------|---------|
| `complete-reset.sh` | Full environment setup (contracts + operators) |
| `start-geth-fast.sh` | Start Geth with fast block production |
| `request-new-wallet.sh` | Request wallet creation (triggers DKG) |
| `check-wallet-status.sh` | List all created wallets |
| `emulate-deposit.sh` | Prepare deposit data for testing |
| `deploy-bridge-complete.sh` | Deploy complete Bridge from tbtc-v2 |
| `initialize-all-operators.sh` | Initialize all operators |
| `join-all-operators-to-pools.sh` | Join operators to sortition pools |
| `restart-all-nodes.sh` | Restart all keep-client nodes |
| `monitor-tbtc-events.sh` | Monitor tBTC contract events |
| `check-deployments.sh` | Verify all contract deployments |

---

## Next Steps

1. **Test Deposits**: Use `emulate-deposit.sh` and deploy complete Bridge
2. **Test Redemptions**: Create redemption requests
3. **Monitor Operations**: Watch node logs for wallet operations
4. **Debug Issues**: Use troubleshooting section above

For more details, see:
- `docs/development/README.adoc`
- `docs/development/local-t-network.adoc`
- Individual script comments

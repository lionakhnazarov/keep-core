# DKG Initialization Guide

Complete step-by-step guide to initialize the DKG (Distributed Key Generation) process after Geth is running.

## Prerequisites

✅ **Geth is running** (with Clique PoA for faster block times)
```bash
# Verify Geth is running
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:8545
```

## Step-by-Step Process

### Step 0: Initialize RandomBeacon Groups (CRITICAL)

**RandomBeacon requires at least one active group before it can accept relay entry requests.**

If you get the error "No active groups" when trying to trigger DKG, you need to create the initial group first:

```bash
# Check if RandomBeacon has active groups
cd solidity/random-beacon
npx hardhat console --network development
> const rb = await ethers.getContract("RandomBeacon")
> (await rb.numberOfActiveGroups()).toString()
# If this returns "0", you need to create a group

# Create initial group via genesis()
> const tx = await rb.genesis()
> await tx.wait()
> console.log("✓ Initial group created!")
```

**Important:** RandomBeacon needs operators in its sortition pool to create groups. Make sure RandomBeacon operators are registered and in the sortition pool before calling `genesis()`.

### Step 1: Deploy Contracts (if not already deployed)

If you're starting fresh or need to redeploy:

```bash
# Deploy ExtendedTokenStaking (required for development)
cd solidity/ecdsa
npx hardhat deploy --tags ExtendedTokenStaking --network development

# Deploy all ECDSA contracts
npx hardhat deploy --network development

# Deploy RandomBeacon (if not already deployed)
cd ../random-beacon
npx hardhat deploy --network development

# Deploy TBTC stub contracts (if not already deployed)
cd ../tbtc-stub
npx hardhat deploy --network development
```

**Note:** If `WalletRegistry` was deployed before `ExtendedTokenStaking`, you may need to redeploy it:
```bash
cd solidity/ecdsa
npx hardhat deploy --tags WalletRegistry --network development --reset
```

### Step 2: Configure Governance Parameters

This is **critical** for DKG to work properly:

```bash
cd solidity/ecdsa

# Run the complete governance setup script
npx hardhat run scripts/setup-governance-complete.ts --network development
```

This script will:
- ✅ Deploy `SimpleWalletOwner` contract
- ✅ Set `walletOwner` (required for `requestNewWallet()`)
- ✅ Reduce `governanceDelay` to 60 seconds
- ✅ Set `resultChallengePeriodLength` to 100 blocks

**Verify governance setup:**
```bash
npx hardhat run scripts/check-governance-status.ts --network development
```

### Step 3: Approve Applications in TokenStaking

Ensure `WalletRegistry` and `RandomBeacon` are approved in `TokenStaking`:

```bash
cd solidity/ecdsa

# Approve WalletRegistry
npx hardhat deploy --tags WalletRegistryApprove --network development

# Approve RandomBeacon
cd ../random-beacon
npx hardhat deploy --tags RandomBeaconApprove --network development
```

### Step 4: Register Operators

Register all operators (stake, authorize, register):

```bash
# From project root
./scripts/register-all-operators.sh
```

This script will:
- Extract operator addresses from `configs/node*.toml`
- Mint T tokens for each operator
- Approve TokenStaking to spend tokens
- Stake tokens for each operator
- Authorize operators for RandomBeacon and WalletRegistry
- Register operators in the contracts

**Or register individually:**
```bash
cd solidity/ecdsa
npx hardhat initialize \
  --network development \
  --owner <OWNER_ADDRESS> \
  --provider <PROVIDER_ADDRESS> \
  --operator <OPERATOR_ADDRESS> \
  --amount 1000000
```

### Step 5: Update Configuration Files

Update `configs/config.toml` and `configs/node*.toml` with deployed contract addresses:

```bash
# Get contract addresses
WR_ADDR=$(cat solidity/ecdsa/deployments/development/WalletRegistry.json | jq -r '.address')
RB_ADDR=$(cat solidity/random-beacon/deployments/development/RandomBeacon.json | jq -r '.address')
TS_ADDR=$(cat solidity/ecdsa/deployments/development/ExtendedTokenStaking.json | jq -r '.address')
BRIDGE_ADDR=$(cat solidity/tbtc-stub/deployments/development/BridgeStub.json | jq -r '.address')

# Update main config
sed -i '' "s|WalletRegistryAddress = \".*\"|WalletRegistryAddress = \"$WR_ADDR\"|" configs/config.toml
sed -i '' "s|RandomBeaconAddress = \".*\"|RandomBeaconAddress = \"$RB_ADDR\"|" configs/config.toml
sed -i '' "s|TokenStakingAddress = \".*\"|TokenStakingAddress = \"$TS_ADDR\"|" configs/config.toml
sed -i '' "s|BridgeAddress = \".*\"|BridgeAddress = \"$BRIDGE_ADDR\"|" configs/config.toml

# Update node configs (repeat for each node)
for i in {1..10}; do
  if [ -f "configs/node${i}.toml" ]; then
    sed -i '' "s|WalletRegistryAddress = \".*\"|WalletRegistryAddress = \"$WR_ADDR\"|" configs/node${i}.toml
    sed -i '' "s|RandomBeaconAddress = \".*\"|RandomBeaconAddress = \"$RB_ADDR\"|" configs/node${i}.toml
    sed -i '' "s|TokenStakingAddress = \".*\"|TokenStakingAddress = \"$TS_ADDR\"|" configs/node${i}.toml
    sed -i '' "s|BridgeAddress = \".*\"|BridgeAddress = \"$BRIDGE_ADDR\"|" configs/node${i}.toml
  fi
done
```

### Step 6: Start Keep-Client Nodes

Start all nodes:

```bash
./configs/start-all-nodes.sh
```

**Or start individual nodes:**
```bash
./keep-client start --config configs/node1.toml
```

**Verify nodes are running:**
```bash
# Check node logs
tail -f logs/node1.log
tail -f logs/node2.log
# ... etc

# Check if nodes are initialized
grep -i "initialized\|ready\|error" logs/node*.log
```

### Step 7: Trigger DKG

**Summary of Methods to Trigger DKG:**

The DKG process is triggered by calling `WalletRegistry.requestNewWallet()`. This function can only be called by the `walletOwner` (which is set to Bridge). Here are the available methods:

1. **Using geth script (Easiest for development)** ⭐ Recommended
2. **Using cast command (Foundry)**
3. **Using keep-client CLI**
4. **Using Hardhat console**
5. **Using geth console directly** Process

Once all nodes are running and registered, trigger DKG by requesting a new wallet:

**Option A: Using Hardhat console**
```bash
cd solidity/ecdsa
npx hardhat console --network development
```

Then in the console:
```javascript
const { ethers } = require("hardhat");
const wr = await ethers.getContractAt("WalletRegistry", "<WALLET_REGISTRY_ADDRESS>");
const tx = await wr.requestNewWallet();
await tx.wait();
console.log("DKG triggered! Tx:", tx.hash);
```

**Option B: Using cast (Foundry) - Recommended**
```bash
# Get Bridge address from deployments
BRIDGE=$(cat solidity/tbtc-stub/deployments/development/Bridge.json | jq -r '.address')
WALLET_REGISTRY=$(cat solidity/ecdsa/deployments/development/WalletRegistry.json | jq -r '.address')

# Unlock Bridge account in Geth (if not already unlocked)
# Then call WalletRegistry.requestNewWallet() as Bridge
cast send $WALLET_REGISTRY "requestNewWallet()" \
  --rpc-url http://localhost:8545 \
  --unlocked \
  --from $BRIDGE
```

**Option B2: Using geth console**
```bash
# Attach to Geth
geth attach http://localhost:8545

# In geth console:
BRIDGE="0x1132297422C9D48E8343F2c37877FC36cE4e15a0"  # Update with actual Bridge address
WALLET_REGISTRY="0x50E550fDEAC9DEFEf3Bb3a03cb0Fa1d4C37Af5ab"  # Update with actual WalletRegistry address

# Unlock Bridge account
personal.unlockAccount(BRIDGE, "", 0)

# Call requestNewWallet (function selector: 0x72cc8c6d)
eth.sendTransaction({
  from: BRIDGE,
  to: WALLET_REGISTRY,
  data: "0x72cc8c6d"
})
```

**Option B3: Using the request-new-wallet script (may require Bridge account setup)**
```bash
# Simple script that attempts to call requestNewWallet via Bridge
./scripts/request-new-wallet.sh
```

**Option B4: Using keep-client CLI**
```bash
# The CLI command structure:
# keep-client ethereum ecdsa wallet-registry request-new-wallet [flags]

# Basic usage (requires --submit flag to actually send transaction):
keep-client ethereum ecdsa wallet-registry request-new-wallet \
  --config configs/config.toml \
  --submit \
  --ethereum.url http://localhost:8545

# Important Notes:
# - The CLI uses the account from your config file's ethereum.keyFile
# - For WalletRegistry.requestNewWallet() to work, the caller must be walletOwner (Bridge)
# - In development, BridgeStub is a contract, not an account
# - BridgeStub.requestNewWallet() forwards to WalletRegistry, so calling Bridge
#   from any account works (Bridge becomes msg.sender in WalletRegistry)
#
# Recommended approach for development:
#   1. Use ./scripts/request-new-wallet-geth.sh (easiest)
#   2. Or use cast: cast send <BRIDGE> "requestNewWallet()" --rpc-url http://localhost:8545 --unlocked --from <ACCOUNT>
#
# For production (when Bridge has an owner account):
#   Use the CLI with Bridge owner's keyfile:
keep-client ethereum ecdsa wallet-registry request-new-wallet \
  --config configs/config.toml \
  --submit \
  --ethereum.keyFile <PATH_TO_BRIDGE_OWNER_KEYFILE> \
  --ethereum.url http://localhost:8545
```

**Quick Reference - CLI Commands for DKG:**
```bash
# Check DKG state (0=IDLE, 1=AWAITING_SEED, 2=AWAITING_RESULT, 3=CHALLENGE)
keep-client ethereum ecdsa wallet-registry get-wallet-creation-state \
  --config configs/config.toml \
  --ethereum.url http://localhost:8545

# Request new wallet (triggers DKG) - requires --submit flag
keep-client ethereum ecdsa wallet-registry request-new-wallet \
  --config configs/config.toml \
  --submit \
  --ethereum.url http://localhost:8545

# Check wallet owner
keep-client ethereum ecdsa wallet-registry wallet-owner \
  --config configs/config.toml \
  --ethereum.url http://localhost:8545

# Check DKG timeout status
keep-client ethereum ecdsa wallet-registry has-dkg-timed-out \
  --config configs/config.toml \
  --ethereum.url http://localhost:8545

# See all available WalletRegistry commands
keep-client ethereum ecdsa wallet-registry --help
```

**Option C: Using curl (if walletOwner is a contract)**
```bash
# Get walletOwner address
WALLET_OWNER=$(cat solidity/ecdsa/deployments/development/SimpleWalletOwner.json | jq -r '.address')

# Call requestNewWallet via RPC
curl -X POST -H "Content-Type: application/json" \
  --data "{
    \"jsonrpc\":\"2.0\",
    \"method\":\"eth_sendTransaction\",
    \"params\":[{
      \"from\":\"$WALLET_OWNER\",
      \"to\":\"<WALLET_REGISTRY_ADDRESS>\",
      \"data\":\"0x...\" // ABI encoded requestNewWallet()
    }],
    \"id\":1
  }" \
  http://localhost:8545
```

### Step 8: Monitor DKG Progress

Monitor the DKG process:

```bash
# Watch node logs for DKG activity
tail -f logs/node*.log | grep -i "dkg\|wallet\|group"

# Check DKG state on-chain
cd solidity/ecdsa
npx hardhat console --network development
```

In console:
```javascript
const wr = await ethers.getContractAt("WalletRegistry", "<WALLET_REGISTRY_ADDRESS>");
const state = await wr.getWalletCreationState();
console.log("DKG State:", state); // 0=IDLE, 1=AWAITING_SEED, 2=AWAITING_RESULT, 3=CHALLENGE

// Check if sortition pool is locked
const sp = await wr.sortitionPool();
const spContract = await ethers.getContractAt(["function isLocked() view returns (bool)"], sp);
const isLocked = await spContract.isLocked();
console.log("Sortition Pool Locked:", isLocked);

// Check DKG timeout
const timedOut = await wr.hasDkgTimedOut();
console.log("DKG Timed Out:", timedOut);
```

**Alternative: Using cast commands**
```bash
# Check wallet creation state (0=IDLE, 1=AWAITING_SEED, 2=AWAITING_RESULT, 3=CHALLENGE)
cast call <WALLET_REGISTRY_ADDRESS> "getWalletCreationState()" --rpc-url http://localhost:8545

# Check if sortition pool is locked
SP=$(cast call <WALLET_REGISTRY_ADDRESS> "sortitionPool()" --rpc-url http://localhost:8545 | cast --to-ascii | tail -1 | xargs)
cast call $SP "isLocked()" --rpc-url http://localhost:8545

# Check DKG timeout
cast call <WALLET_REGISTRY_ADDRESS> "hasDkgTimedOut()" --rpc-url http://localhost:8545

# Check DKG events
cast logs --from-block latest-1000 --to-block latest \
  --address <WALLET_REGISTRY_ADDRESS> \
  --rpc-url http://localhost:8545 | grep -E '(DkgStarted|DkgStateLocked|DkgResult)'
```

**Using the provided scripts:**
```bash
# Full status check (shows state, events, parameters)
./scripts/check-dkg-status.sh

# Simple status check (quick state check)
./scripts/check-dkg-simple.sh
```

## Quick Checklist

- [ ] Geth is running and mining blocks
- [ ] All contracts deployed (ExtendedTokenStaking, WalletRegistry, RandomBeacon, TBTC stubs)
- [ ] Governance parameters configured (walletOwner, governanceDelay, resultChallengePeriodLength)
- [ ] Applications approved in TokenStaking (WalletRegistry, RandomBeacon)
- [ ] All operators registered (staked, authorized, registered)
- [ ] Configuration files updated with correct contract addresses
- [ ] All keep-client nodes started and initialized
- [ ] DKG triggered via `requestNewWallet()`

## Troubleshooting

### "operator not registered for the staking provider"
- Run `./scripts/register-all-operators.sh` to register all operators

### "Application is not approved"
- Run approval scripts: `npx hardhat deploy --tags WalletRegistryApprove --network development`

### "Caller is not the staking contract"
- Ensure `WalletRegistry` was deployed with `ExtendedTokenStaking` address
- Redeploy if needed: `npx hardhat deploy --tags WalletRegistry --network development --reset`

### "authentication needed: password or unlock"
- Ensure accounts are unlocked in Geth
- Use `./scripts/start-geth-fast.sh` which unlocks all accounts automatically

### Nodes not initializing
- Check contract addresses in `configs/node*.toml` match deployed addresses
- Verify operators are registered and authorized
- Check node logs: `tail -f logs/node1.log`

## Setting Minimum DKG Parameters for Development

For faster development cycles, you can reduce **all** DKG timeouts to minimum values. This significantly speeds up the entire DKG process.

### Quick Setup (All Parameters)

**Easiest method - sets all parameters at once:**
```bash
./scripts/set-minimum-dkg-params.sh
```

This script sets:
- `seedTimeout`: 8 blocks (~8 seconds at 1s/block)
- `resultChallengePeriodLength`: 10 blocks (~10 seconds) - minimum allowed
- `resultSubmissionTimeout`: 30 blocks (~30 seconds)
- `submitterPrecedencePeriodLength`: 5 blocks (~5 seconds)

**Prerequisites:**
- DKG must be in IDLE state (state 0)
- Requires governance access (WalletRegistryGovernance owner)

**What it does:**
1. Checks current DKG state (must be IDLE)
2. Displays current vs. new parameter values
3. Updates all parameters in one transaction
4. Verifies the update was successful

**Note:** If governance delay is enabled, the script will handle the two-step governance process automatically.

### Parameter Comparison

| Parameter | Production Default | Development Minimum |
|-----------|------------------|---------------------|
| `seedTimeout` | 11,520 blocks (~48h) | 8 blocks (~8s) |
| `resultChallengePeriodLength` | 11,520 blocks (~48h) | 10 blocks (~10s) |
| `resultSubmissionTimeout` | 536 blocks | 30 blocks (~30s) |
| `submitterPrecedencePeriodLength` | 20 blocks | 5 blocks (~5s) |

**Important:** These minimum values are for **development only**. Production deployments should use default values for security.

## Decreasing Challenge Period Length

The DKG Result Challenge Period Length determines how long submitted DKG results can be challenged. For development/testing, you may want to decrease this value to speed up the DKG process.

**Current default:** 11520 blocks (~48 hours at 15s/block)  
**Minimum:** 10 blocks  
**Governance delay:** 60 seconds (for development)

### Method 1: Using the provided script (Recommended)

```bash
# Decrease to 100 blocks (~25 minutes at 15s/block)
cd solidity/ecdsa
NEW_VALUE=100 npx hardhat run scripts/update-result-challenge-period-length.ts --network development

# After governance delay (60 seconds), finalize:
NEW_VALUE=100 npx hardhat run scripts/update-result-challenge-period-length.ts --network development
```

The script will:
1. Check current value
2. Begin the update if no pending update exists
3. Finalize the update if governance delay has passed
4. Handle pending updates automatically

### Method 2: Using cast/geth directly

```bash
WR_GOV="0x5996cf0764C21fC992dd64Ab6f8041CEB68272a7"  # WalletRegistryGovernance
OWNER="0x23d5975f6d72a57ba984886d3df40dca7f10ceca"   # Governance owner
NEW_VALUE=100  # blocks

# Step 1: Begin the update
cast send $WR_GOV "beginDkgResultChallengePeriodLengthUpdate(uint256)" $NEW_VALUE \
  --rpc-url http://localhost:8545 \
  --unlocked \
  --from $OWNER

# Step 2: Wait for governance delay (60 seconds for development)
sleep 61

# Step 3: Finalize the update
cast send $WR_GOV "finalizeDkgResultChallengePeriodLengthUpdate()" \
  --rpc-url http://localhost:8545 \
  --unlocked \
  --from $OWNER

# Verify
WR="0x64F6B5b4AeF3F69952d3B8313F33E99AaAb69241"
cast call $WR "dkgParameters()" --rpc-url http://localhost:8545
```

### Checking Current Value

```bash
# Using Hardhat console
cd solidity/ecdsa
npx hardhat console --network development
> const wr = await ethers.getContract("WalletRegistry")
> const params = await wr.dkgParameters()
> params.resultChallengePeriodLength.toString()
```

### Important Notes

- **You can BEGIN the update anytime** (even when DKG is active)
- **You can only FINALIZE when DKG is IDLE** (not during active DKG)
  - If DKG is active (AWAITING_SEED, AWAITING_RESULT, or CHALLENGE), you can begin the update now
  - The update will be finalized after governance delay, but only when DKG returns to IDLE
  - The new value will apply to the **NEXT** DKG cycle (after current DKG completes)
  - Check current state: `./scripts/check-dkg-status.sh`
  - To reset DKG to IDLE: Wait for timeout or call `notifyDkgTimeout()` if timeout has passed
- **Minimum value is 10 blocks**
- **Governance delay applies** - you must wait between begin and finalize
- **For development**, governance delay is typically 60 seconds
- **For production**, governance delay is much longer (e.g., 7 days)

### If DKG is Active (Cannot Update Parameters)

If you get the error "Current state is not IDLE", DKG is currently in progress. You have several options:

**Option 1: Wait for DKG to Complete**
- Wait for operators to submit and approve DKG result
- Or wait for DKG timeout (check with `./scripts/check-dkg-status.sh`)

**Option 2: Notify DKG Timeout (if timeout has passed)**

⚠️ **Note:** `notifyDkgTimeout()` requires ReimbursementPool to be properly configured and funded. If you get refund errors, you may need to:
1. Authorize WalletRegistry in ReimbursementPool
2. Fund ReimbursementPool with ETH
3. Then call `notifyDkgTimeout()`

```bash
WR="0x64F6B5b4AeF3F69952d3B8313F33E99AaAb69241"
RB=$(cast call $WR "reimbursementPool()" --rpc-url http://localhost:8545 | sed 's/0x000000000000000000000000//' | sed 's/^/0x/')
OWNER=$(cast call $RB "owner()" --rpc-url http://localhost:8545 | sed 's/0x000000000000000000000000//' | sed 's/^/0x/')

# Authorize WalletRegistry (if not already authorized)
cast send $RB "authorize(address)" $WR \
  --rpc-url http://localhost:8545 \
  --unlocked \
  --from $OWNER

# Fund ReimbursementPool
cast send $RB --value 1ether \
  --rpc-url http://localhost:8545 \
  --unlocked \
  --from $OWNER

# Then notify timeout
cast send $WR "notifyDkgTimeout()" \
  --rpc-url http://localhost:8545 \
  --unlocked \
  --from $(cast rpc eth_accounts --rpc-url http://localhost:8545 | jq -r '.[0]')
```

**Option 3: For Development - Wait for Natural Timeout**

Since the challenge period is 11520 blocks (~48 hours), you can:
1. Wait for DKG to timeout naturally
2. Or mine blocks faster to speed up the timeout
3. Then update parameters when DKG returns to IDLE

**Option 4: Begin Update Now (Recommended for Active DKG)**

You can begin the parameter update even when DKG is active. The update will be queued and finalized after governance delay, but only when DKG returns to IDLE. The new value will apply to the **next** DKG cycle.

```bash
WR_GOV="0x5996cf0764C21fC992dd64Ab6f8041CEB68272a7"
OWNER="0x23d5975f6d72a57ba984886d3df40dca7f10ceca"
NEW_VALUE=100

# Step 1: Begin the update (works even when DKG is active)
cast send $WR_GOV "beginDkgResultChallengePeriodLengthUpdate(uint256)" $NEW_VALUE \
  --rpc-url http://localhost:8545 \
  --unlocked \
  --from $OWNER

# Step 2: Wait for governance delay (60 seconds)
sleep 61

# Step 3: Finalize (only works when DKG is IDLE)
# If DKG is still active, this will fail. Wait for DKG to complete/timeout first.
cast send $WR_GOV "finalizeDkgResultChallengePeriodLengthUpdate()" \
  --rpc-url http://localhost:8545 \
  --unlocked \
  --from $OWNER
```

**Workflow Summary:**
1. ✅ Begin update anytime → Transaction succeeds
2. ⏳ Wait for governance delay (60s for development)
3. ⏳ Wait for DKG to return to IDLE (complete or timeout)
4. ✅ Finalize update → New value applies to next DKG cycle

## Next Steps After DKG Completes

Once DKG completes successfully:
1. Wallet will be registered in `WalletRegistry`
2. Group public key will be available
3. Operators can participate in signing operations
4. Monitor wallet status and signing activity

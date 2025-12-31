# Contract Deployment Guide

## Current Status

✅ **All core contracts are deployed:**
- TokenStaking: `0xF6e82633F3D9334Ba2717B4Acf46C6FC684619FE`
- T Token: `0x49C3cDEdaF8B842bDBF7437cE6150D4c4bAE78bd`
- RandomBeacon: `0x54EAc22087b2998d93C72ABa3D3510aBcF76468a`
- WalletRegistry: `0x0AFfA4CBE43Be91CF83Ea605531fb523D70BAd0B`
- WalletRegistryGovernance: `0xfF6B1a329d97d041408790b82890B590Bab09989`

## Next Steps

### Step 1: Verify Geth is Running

```bash
# Check if Geth is running
ps aux | grep geth | grep -v grep

# Or check RPC endpoint
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:8545
```

If not running, start Geth:
```bash
./scripts/start-geth.sh
# Or for faster block times:
./scripts/start-geth-fast.sh
```

### Step 2: Configure Governance Parameters

This is the most important step for DKG to work properly:

```bash
cd solidity/ecdsa
npx hardhat run scripts/setup-governance-complete.ts --network development
```

This script will:
1. ✅ Deploy `SimpleWalletOwner` contract
2. ✅ Set `walletOwner` (no delay if initializing)
3. ✅ Reduce `governanceDelay` to 60 seconds (automatically mines blocks)
4. ✅ Set `resultChallengePeriodLength` to 100 blocks

**Note:** Mining blocks to reduce governance delay may take a few minutes if the current delay is long (e.g., 7 days ≈ ~40,000 blocks). The script shows progress.

### Step 3: Verify Configuration

After running the governance setup, verify everything is configured:

```bash
cd solidity/ecdsa
npx hardhat console --network development
```

Then in the console:
```javascript
const wr = await ethers.getContractAt("WalletRegistry", "0x0AFfA4CBE43Be91CF83Ea605531fb523D70BAd0B")
const wrGov = await ethers.getContractAt("WalletRegistryGovernance", "0xfF6B1a329d97d041408790b82890B590Bab09989")

// Check wallet owner
const wo = await wr.walletOwner()
const woCode = await ethers.provider.getCode(wo)
console.log("Wallet Owner:", wo)
console.log("Is Contract:", woCode.length > 2) // Should be true

// Check governance delay
const delay = await wrGov.governanceDelay()
console.log("Governance Delay:", delay.toString(), "seconds") // Should be 60

// Check challenge period
const params = await wr.dkgParameters()
console.log("Challenge Period:", params.resultChallengePeriodLength.toString(), "blocks") // Should be 100
```

### Step 4: Start Nodes

Once governance is configured, start your keep-client nodes:

```bash
# Start all nodes
./configs/start-all-nodes.sh

# Or start individual nodes
./keep-client start --config configs/node1.toml
```

## Troubleshooting

### If contracts are not deployed:

1. **Deploy TokenStaking and T token:**
   ```bash
   cd tmp/solidity-contracts
   yarn deploy --network development --reset
   ```

2. **Deploy RandomBeacon:**
   ```bash
   cd solidity/random-beacon
   yarn deploy --network development --reset
   ```

3. **Deploy ECDSA contracts:**
   ```bash
   cd solidity/ecdsa
   yarn deploy --network development --reset
   ```

### If config.toml has wrong addresses:

The addresses in `configs/config.toml` should match the deployed contracts:

```bash
# Update RandomBeacon address
RB_ADDR=$(cat solidity/random-beacon/deployments/development/RandomBeacon.json | grep -o '"address":\s*"[^"]*"' | head -1 | cut -d'"' -f4)
sed -i '' "s|RandomBeaconAddress = \".*\"|RandomBeaconAddress = \"$RB_ADDR\"|" configs/config.toml

# Update WalletRegistry address
WR_ADDR=$(cat solidity/ecdsa/deployments/development/WalletRegistry.json | grep -o '"address":\s*"[^"]*"' | head -1 | cut -d'"' -f4)
sed -i '' "s|WalletRegistryAddress = \".*\"|WalletRegistryAddress = \"$WR_ADDR\"|" configs/config.toml
```

### If governance setup fails:

- Make sure Geth is running and mining blocks
- Check that you have enough ETH in the deployer account
- Verify contracts are accessible at their addresses:
  ```bash
  curl -X POST -H "Content-Type: application/json" \
    --data "{\"jsonrpc\":\"2.0\",\"method\":\"eth_getCode\",\"params\":[\"0x0AFfA4CBE43Be91CF83Ea605531fb523D70BAd0B\",\"latest\"],\"id\":1}" \
    http://localhost:8545
  ```
  Should return non-empty code (not `"0x"`)

## Quick Reset

If you need to completely reset everything:

```bash
./scripts/reset-local-setup.sh
```

This will:
- Stop Geth
- Clean Geth data
- Clean Hardhat artifacts
- Initialize fresh Geth chain
- Deploy all contracts
- Configure governance parameters
- Update config.toml

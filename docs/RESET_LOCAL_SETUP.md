# Complete Local Setup Reset Guide

This guide explains how to completely reset your local development environment with DKG-ready governance parameters.

## Quick Reset

Run the automated reset script:

```bash
./scripts/reset-local-setup.sh
```

Or with a custom Geth data directory:

```bash
GETH_DATA_DIR=~/custom/path ./scripts/reset-local-setup.sh
```

## What the Script Does

1. **Stops Geth** - Kills any running Geth processes
2. **Cleans Geth Chain Data** - Removes `~/ethereum/data/geth/`
3. **Cleans Hardhat Artifacts** - Removes deployment files and OpenZeppelin cache
4. **Initializes Fresh Chain** - Creates new genesis block
5. **Starts Geth** - Launches Geth with mining enabled
6. **Unlocks Accounts** - Unlocks first 10 accounts (password: `password`)
7. **Deploys Contracts** - Runs `yarn deploy --network development --reset`
8. **Configures Governance** - Sets up:
   - `walletOwner` (SimpleWalletOwner contract)
   - `governanceDelay` (reduced to 60 seconds)
   - `resultChallengePeriodLength` (set to 100 blocks)
9. **Updates config.toml** - Updates `WalletRegistryAddress` with new deployment

## Manual Steps (if script fails)

### 1. Stop Geth

```bash
pkill -f "geth.*--datadir.*ethereum"
```

### 2. Clean Chain Data

```bash
export GETH_DATA_DIR=~/ethereum/data
rm -rf $GETH_DATA_DIR/geth
```

### 3. Clean Hardhat Artifacts

```bash
cd solidity/ecdsa
rm -rf deployments/development .openzeppelin
yarn hardhat clean
```

### 4. Initialize Chain

```bash
geth --datadir=$GETH_DATA_DIR init $GETH_DATA_DIR/genesis.json
```

### 5. Start Geth

```bash
export GETH_ETHEREUM_ACCOUNT=$(geth account list --keystore ~/ethereum/data/keystore/ 2>/dev/null | head -1 | grep -o '{[^}]*}' | sed 's/{//;s/}//' | sed 's/^/0x/')

geth --port 3000 --networkid 1101 --identity 'local-dev' \
    --ws --ws.addr '127.0.0.1' --ws.port '8546' --ws.origins '*' \
    --ws.api 'admin,debug,web3,eth,txpool,personal,ethash,miner,net' \
    --http --http.port '8545' --http.addr '127.0.0.1' --http.corsdomain '' \
    --http.api 'admin,debug,web3,eth,txpool,personal,ethash,miner,net' \
    --datadir=$GETH_DATA_DIR --allow-insecure-unlock \
    --miner.etherbase=$GETH_ETHEREUM_ACCOUNT --mine --miner.threads=1
```

### 6. Unlock Accounts

```bash
# Get accounts
ACCOUNTS=$(geth account list --keystore ~/ethereum/data/keystore/ 2>/dev/null | grep -o '{[^}]*}' | sed 's/{//;s/}//')

# Unlock each (password: password)
for addr in $ACCOUNTS; do
    curl -X POST -H "Content-Type: application/json" \
        --data "{\"jsonrpc\":\"2.0\",\"method\":\"personal_unlockAccount\",\"params\":[\"0x$addr\",\"password\",0],\"id\":1}" \
        http://localhost:8545
done
```

### 7. Deploy Contracts

```bash
cd solidity/ecdsa
yarn deploy --network development --reset
```

### 8. Configure Governance

```bash
cd solidity/ecdsa

# Setup wallet owner
npx hardhat run scripts/setup-wallet-owner-complete.ts --network development

# Reduce governance delay (may take time on first run)
npx hardhat run scripts/reduce-governance-delay-complete.ts --network development

# Set resultChallengePeriodLength (after delay is reduced)
NEW_VALUE=100 npx hardhat run scripts/update-result-challenge-period-length.ts --network development
```

Or use the complete setup script:

```bash
npx hardhat run scripts/setup-governance-complete.ts --network development
```

### 9. Update config.toml

```bash
# Get WalletRegistry address
WR_ADDR=$(cat solidity/ecdsa/deployments/development/WalletRegistry.json | grep -o '"address":\s*"[^"]*"' | head -1 | cut -d'"' -f4)

# Update config.toml (macOS)
sed -i '' "s|WalletRegistryAddress = \".*\"|WalletRegistryAddress = \"$WR_ADDR\"|" configs/config.toml

# Or (Linux)
sed -i "s|WalletRegistryAddress = \".*\"|WalletRegistryAddress = \"$WR_ADDR\"|" configs/config.toml
```

## Verification

After reset, verify everything is configured:

```bash
cd solidity/ecdsa
npx hardhat console --network development
```

Then in the console:

```javascript
const { ethers, helpers } = require("hardhat");
const wr = await helpers.contracts.getContract("WalletRegistry");
const wrGov = await helpers.contracts.getContract("WalletRegistryGovernance");

// Check wallet owner
const wo = await wr.walletOwner();
const woCode = await ethers.provider.getCode(wo);
console.log("Wallet Owner:", wo);
console.log("Is Contract:", woCode.length > 2);

// Check governance delay
const delay = await wrGov.governanceDelay();
console.log("Governance Delay:", delay.toString(), "seconds");

// Check challenge period
const params = await wr.dkgParameters();
console.log("resultChallengePeriodLength:", params.resultChallengePeriodLength.toString(), "blocks");
```

## Troubleshooting

### Geth won't start
- Check if port 8545 is already in use: `lsof -i :8545`
- Check Geth logs: `tail -f ~/ethereum/data/geth.log`

### Contracts won't deploy
- Ensure Geth is running and mining blocks
- Check accounts are unlocked
- Verify you have enough ETH in deployer account

### Governance delay reduction is slow
- First time reducing from 7 days requires mining ~40,000 blocks
- This is normal and only happens once
- After that, all updates will be fast (60 seconds)

### Script fails partway through
- You can re-run the script - it's idempotent
- Or continue manually from where it failed
- Check the error messages for specific issues

## Files Created/Modified

- `~/ethereum/data/geth/` - Geth chain data
- `solidity/ecdsa/deployments/development/` - Contract deployment records
- `solidity/ecdsa/.openzeppelin/` - OpenZeppelin upgrade cache
- `configs/config.toml` - Updated with new contract addresses

## Next Steps

After reset:
1. Register operators and stake tokens
2. Authorize operators
3. Join sortition pools
4. Trigger DKG ceremony
5. Approve DKG result (should work now with proper walletOwner)

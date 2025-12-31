# Solutions to Advance Time or Reduce Governance Delay

## Problem
The `walletOwner` is currently an EOA (Externally Owned Account), but the contract requires it to be a contract. We've deployed `SimpleWalletOwner` and initiated an update, but need to wait 7 days (604,800 seconds) for the governance delay to pass.

## Solution Options

### Option 1: Restart Geth with Faketime (Recommended for Development)

Since geth uses system time for block timestamps, you can restart it with `faketime`:

```bash
# Stop current geth
pkill geth

# Start geth with faketime (advance by 7 days)
faketime '7 days' geth \
  --port 3000 \
  --networkid 1101 \
  --identity somerandomidentity \
  --ws --ws.addr 127.0.0.1 --ws.port 8546 --ws.origins * \
  --ws.api admin,debug,web3,eth,txpool,personal,ethash,miner,net \
  --http --http.port 8545 --http.addr 127.0.0.1 --http.corsdomain \
  --http.api admin,debug,web3,eth,txpool,personal,ethash,miner,net \
  --datadir=/Users/levakhnazarov/ethereum/data \
  --allow-insecure-unlock \
  --miner.etherbase=0x7966c178f466b060aaeb2b91e9149a5fb2ec9c53 \
  --mine --miner.threads=1
```

Then mine a block and finalize:
```bash
npx hardhat console --network development
```
```javascript
const { ethers, helpers } = require('hardhat');
const wrGov = await helpers.contracts.getContract('WalletRegistryGovernance');
const owner = await wrGov.owner();
const signer = await ethers.getSigner(owner);
await wrGov.connect(signer).finalizeWalletOwnerUpdate();
```

### Option 2: Modify System Time (if geth is in Docker)

If geth is running in Docker:
```bash
# Find container
CONTAINER=$(docker ps --filter "ancestor=geth-node" --format "{{.ID}}" | head -1)

# Advance time by 7 days
docker exec $CONTAINER date -s "@$(($(date +%s) + 604800))"

# Mine a block
curl -X POST http://localhost:8545 -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"miner_start","params":[1],"id":1}'
```

### Option 3: Use debug_setHead to Rewind and Initialize Directly

If you can find a block before walletOwner was initialized:

```javascript
// Rewind to before initialization
await ethers.provider.send("debug_setHead", ["0x<block_number>"]);
// Then initialize directly (no delay)
await wrGov.initializeWalletOwner(simpleWalletOwnerAddress);
```

### Option 4: Wait for Real Time (Not Practical)

Wait 7 days for the governance delay to pass naturally.

## Current Status

- ✅ SimpleWalletOwner deployed at: `0x133e2d564f8eC8b2ddC249dB1ec282E73752f228`
- ⏳ Update initiated, waiting for governance delay
- ⚠️  Chain state may be corrupted after rewinds - consider restarting geth

## Quick Fix Script

After restarting geth with faketime, run:
```bash
cd solidity/ecdsa
npx hardhat run scripts/fix-wallet-owner.ts --network development
```

# How to Run Geth for Local Development

## Quick Start

Use the helper script:

```bash
./scripts/start-geth.sh
```

Or with a custom data directory:

```bash
GETH_DATA_DIR=~/custom/path ./scripts/start-geth.sh
```

## Manual Start

If you prefer to start Geth manually:

```bash
# Set environment variables
export GETH_DATA_DIR=~/ethereum/data
export GETH_ETHEREUM_ACCOUNT=$(geth account list --keystore ~/ethereum/data/keystore/ 2>/dev/null | head -1 | grep -o '{[^}]*}' | sed 's/{//;s/}//' | sed 's/^/0x/')

# Start Geth
geth \
    --port 3000 \
    --networkid 1101 \
    --identity 'local-dev' \
    --ws --ws.addr '127.0.0.1' --ws.port '8546' --ws.origins '*' \
    --ws.api 'admin,debug,web3,eth,txpool,personal,ethash,miner,net' \
    --http --http.port '8545' --http.addr '127.0.0.1' --http.corsdomain '' \
    --http.api 'admin,debug,web3,eth,txpool,personal,ethash,miner,net' \
    --datadir=$GETH_DATA_DIR \
    --allow-insecure-unlock \
    --miner.etherbase=$GETH_ETHEREUM_ACCOUNT \
    --mine \
    --miner.threads=1
```

## Start in Background

To run Geth in the background:

```bash
nohup ./scripts/start-geth.sh > ~/ethereum/data/geth.log 2>&1 &
```

Or manually:

```bash
nohup geth \
    --port 3000 \
    --networkid 1101 \
    --identity 'local-dev' \
    --ws --ws.addr '127.0.0.1' --ws.port '8546' --ws.origins '*' \
    --ws.api 'admin,debug,web3,eth,txpool,personal,ethash,miner,net' \
    --http --http.port '8545' --http.addr '127.0.0.1' --http.corsdomain '' \
    --http.api 'admin,debug,web3,eth,txpool,personal,ethash,miner,net' \
    --datadir=$GETH_DATA_DIR \
    --allow-insecure-unlock \
    --miner.etherbase=$GETH_ETHEREUM_ACCOUNT \
    --mine \
    --miner.threads=1 \
    > ~/ethereum/data/geth.log 2>&1 &
```

## Verify Geth is Running

Check if Geth is responding:

```bash
curl -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    http://localhost:8545
```

You should get a response with a block number.

## Check Geth Status

Check if Geth process is running:

```bash
pgrep -f "geth.*--datadir.*ethereum"
```

View Geth logs (if running in background):

```bash
tail -f ~/ethereum/data/geth.log
```

## Stop Geth

If running in foreground: Press `Ctrl+C`

If running in background:

```bash
pkill -f "geth.*--datadir.*ethereum"
```

Or find the PID and kill it:

```bash
pkill -f "geth.*--datadir.*ethereum"
# Or
kill $(pgrep -f "geth.*--datadir.*ethereum")
```

## Geth Configuration

- **Network ID**: 1101 (local development)
- **Chain ID**: 1101
- **RPC Port**: 8545 (http://localhost:8545)
- **WebSocket Port**: 8546 (ws://localhost:8546)
- **P2P Port**: 3000
- **Mining**: Enabled (1 thread)
- **Data Directory**: ~/ethereum/data (default)

## Troubleshooting

### Port Already in Use

If port 8545 is already in use:

```bash
lsof -i :8545
```

Kill the process using that port, or change the port in the Geth command.

### Chain Not Initialized

If you see errors about chain not being initialized:

```bash
geth --datadir=~/ethereum/data init ~/ethereum/data/genesis.json
```

Or run the full reset script:

```bash
./scripts/reset-local-setup.sh
```

### No Accounts Found

Create accounts first:

```bash
geth account new --keystore ~/ethereum/data/keystore
# Enter password: password
```

Or create multiple accounts:

```bash
for i in {1..11}; do
    echo "password" | geth account new --keystore ~/ethereum/data/keystore --password <(echo "password")
done
```

### Geth Won't Start Mining

Make sure:
1. Chain is initialized
2. Mining account exists and has ETH (from genesis)
3. Geth has write permissions to data directory

## Next Steps

After Geth is running:
1. Deploy contracts: `cd solidity/ecdsa && yarn deploy --network development`
2. Configure governance: `npx hardhat run scripts/setup-governance-complete.ts --network development`
3. Start your Keep client nodes

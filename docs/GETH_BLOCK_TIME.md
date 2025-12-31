# Changing Geth Block Time

Yes, you can change the block time for Geth! Here are several options:

## Option 1: Clique PoA Consensus (Recommended for Fast Blocks)

**Best for:** Precise control over block time (e.g., 1 second blocks)

### Setup Clique Genesis

```bash
# Create Clique genesis with 1 second blocks
./scripts/create-genesis-clique.sh

# Or with custom block period (e.g., 2 seconds)
BLOCK_PERIOD=2 ./scripts/create-genesis-clique.sh
```

### Start Geth with Clique

```bash
./scripts/start-geth-fast.sh
```

This will mine blocks every 1 second (or your specified period).

## Option 2: Lower Difficulty (PoW - Less Precise)

**Best for:** Faster PoW blocks without changing consensus

### Modify Genesis Difficulty

Edit your `genesis.json` and set a very low difficulty:

```json
{
  "config": {
    "chainId": 1101,
    ...
  },
  "difficulty": "0x1",  // Very low difficulty = faster blocks
  "gasLimit": "0x7A1200",
  ...
}
```

Then reinitialize:

```bash
rm -rf ~/ethereum/data/geth
geth --datadir=~/ethereum/data init ~/ethereum/data/genesis.json
```

Blocks will mine faster, but timing is not precise.

## Option 3: Dev Mode (Instant Blocks)

**Best for:** Development/testing - blocks mine instantly when transactions are pending

```bash
geth --dev \
    --http --http.port 8545 --http.addr 127.0.0.1 \
    --ws --ws.port 8546 --ws.addr 127.0.0.1 \
    --allow-insecure-unlock
```

**Note:** Dev mode creates a temporary chain that's deleted when Geth stops.

## Comparison

| Method | Block Time | Precision | Use Case |
|--------|-----------|-----------|----------|
| **Clique PoA** | Configurable (1s+) | Precise | Production-like testing |
| **Low Difficulty PoW** | Variable (~1-5s) | Imprecise | Quick testing |
| **Dev Mode** | Instant | Instant | Rapid development |

## Quick Start: Clique PoA (1 Second Blocks)

```bash
# 1. Create Clique genesis (1 second blocks)
./scripts/create-genesis-clique.sh

# 2. Initialize chain
geth --datadir=~/ethereum/data init ~/ethereum/data/genesis.json

# 3. Start Geth with Clique
./scripts/start-geth-fast.sh
```

## Changing Block Period After Setup

If you want to change the block period:

1. Stop Geth
2. Create new genesis with different period:
   ```bash
   BLOCK_PERIOD=2 ./scripts/create-genesis-clique.sh
   ```
3. Reset chain:
   ```bash
   rm -rf ~/ethereum/data/geth
   geth --datadir=~/ethereum/data init ~/ethereum/data/genesis.json
   ```
4. Restart Geth

## Current Setup (PoW)

Your current setup uses PoW mining with difficulty `0x20` (very low), which typically produces blocks every few seconds, but timing is not guaranteed.

To switch to Clique PoA for precise 1-second blocks, use the scripts above.

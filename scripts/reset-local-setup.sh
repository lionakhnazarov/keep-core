#!/bin/bash
set -eou pipefail

# Complete reset script for local development setup with DKG-ready governance parameters
#
# This script:
#   1. Stops Geth (if running)
#   2. Cleans Geth chain data
#   3. Cleans Hardhat deployment artifacts
#   4. Cleans OpenZeppelin cache
#   5. Restarts Geth
#   6. Redeploys contracts
#   7. Configures governance parameters (reduced delay, walletOwner, etc.)
#   8. Updates config.toml with new contract addresses
#
# Usage:
#   ./scripts/reset-local-setup.sh [GETH_DATA_DIR]
#
# Environment variables:
#   GETH_DATA_DIR - Geth data directory (default: ~/ethereum/data)
#   GETH_ETHEREUM_ACCOUNT - Mining account (auto-detected if not set)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ECDSA_DIR="$PROJECT_ROOT/solidity/ecdsa"

# Default values
GETH_DATA_DIR="${GETH_DATA_DIR:-$HOME/ethereum/data}"
GETH_DATA_DIR="${1:-$GETH_DATA_DIR}"

# Expand ~ in path
EXPANDED_GETH_DATA_DIR=$(eval echo "$GETH_DATA_DIR")

echo "=========================================="
echo "Complete Local Setup Reset"
echo "=========================================="
echo ""
echo "GETH_DATA_DIR: $EXPANDED_GETH_DATA_DIR"
echo "PROJECT_ROOT: $PROJECT_ROOT"
echo ""

# Step 1: Stop Geth if running
echo "=== Step 1: Stopping Geth ==="
if pgrep -f "geth.*--datadir.*$EXPANDED_GETH_DATA_DIR" > /dev/null; then
    echo "Stopping Geth..."
    pkill -f "geth.*--datadir.*$EXPANDED_GETH_DATA_DIR" || true
    sleep 2
    echo "✓ Geth stopped"
else
    echo "✓ Geth not running"
fi
echo ""

# Step 2: Clean Geth chain data
echo "=== Step 2: Cleaning Geth Chain Data ==="
if [ -d "$EXPANDED_GETH_DATA_DIR/geth" ]; then
    echo "Removing $EXPANDED_GETH_DATA_DIR/geth..."
    rm -rf "$EXPANDED_GETH_DATA_DIR/geth"
    echo "✓ Geth chain data removed"
else
    echo "✓ No Geth chain data to remove"
fi
echo ""

# Step 3: Clean Hardhat deployment artifacts
echo "=== Step 3: Cleaning Hardhat Artifacts ==="
cd "$ECDSA_DIR"

# Remove deployment files (but keep mainnet)
if [ -d "deployments/development" ]; then
    echo "Removing deployments/development..."
    rm -rf deployments/development
    echo "✓ Deployment artifacts removed"
fi

# Remove OpenZeppelin cache
if [ -d ".openzeppelin" ]; then
    echo "Removing .openzeppelin cache..."
    rm -rf .openzeppelin
    echo "✓ OpenZeppelin cache removed"
fi

# Clean Hardhat cache
echo "Cleaning Hardhat cache..."
yarn hardhat clean || npm run clean || true
echo "✓ Hardhat cache cleaned"
echo ""

# Step 4: Initialize Geth chain
echo "=== Step 4: Initializing Geth Chain ==="
# Always recreate genesis.json during reset to ensure proper configuration
if [ -f "$EXPANDED_GETH_DATA_DIR/genesis.json" ]; then
    echo "Removing existing genesis.json to create fresh one..."
    rm -f "$EXPANDED_GETH_DATA_DIR/genesis.json"
fi

if [ ! -f "$EXPANDED_GETH_DATA_DIR/genesis.json" ]; then
    echo "Creating proper genesis file..."
    
    # Get accounts for genesis allocation
    if [ -d "$EXPANDED_GETH_DATA_DIR/keystore" ]; then
        ACCOUNTS=$(geth account list --keystore "$EXPANDED_GETH_DATA_DIR/keystore" 2>/dev/null | grep -o '{[^}]*}' | sed 's/{//;s/}//' | head -15 || echo "")
        if [ -n "$ACCOUNTS" ]; then
            # Create genesis.json with proper fork ordering
            cat > "$EXPANDED_GETH_DATA_DIR/genesis.json" <<EOF
{
  "config": {
    "chainId": 1101,
    "eip150Block": 0,
    "eip155Block": 0,
    "eip158Block": 0,
    "byzantiumBlock": 0,
    "homesteadBlock": 0,
    "constantinopleBlock": 0,
    "petersburgBlock": 0,
    "daoForkBlock": 0,
    "istanbulBlock": 0,
    "daoForkSupport": true,
    "terminalTotalDifficulty": null
  },
  "difficulty": "0x20",
  "gasLimit": "0x7A1200",
  "alloc": {
EOF
            
            # Add accounts to alloc
            FIRST=true
            for addr in $ACCOUNTS; do
                if [ "$FIRST" = true ]; then
                    FIRST=false
                else
                    echo "," >> "$EXPANDED_GETH_DATA_DIR/genesis.json"
                fi
                echo "    \"0x$addr\": { \"balance\": \"1000000000000000000000000000000000000000000000000000000\" }" | tr -d '\n' >> "$EXPANDED_GETH_DATA_DIR/genesis.json"
            done
            
            cat >> "$EXPANDED_GETH_DATA_DIR/genesis.json" <<EOF

  }
}
EOF
            echo "✓ Created genesis.json with $(echo $ACCOUNTS | wc -w | tr -d ' ') accounts"
        else
            echo "⚠️  No accounts found. Please create accounts first:"
            echo "   geth account new --keystore $EXPANDED_GETH_DATA_DIR/keystore"
            exit 1
        fi
    else
        echo "⚠️  Keystore directory not found. Please create accounts first."
        exit 1
    fi
fi

echo "Initializing Geth chain..."
geth --datadir="$EXPANDED_GETH_DATA_DIR" init "$EXPANDED_GETH_DATA_DIR/genesis.json"
echo "✓ Chain initialized"
echo ""

# Step 5: Start Geth
echo "=== Step 5: Starting Geth ==="
export GETH_DATA_DIR="$EXPANDED_GETH_DATA_DIR"
export GETH_ETHEREUM_ACCOUNT="${GETH_ETHEREUM_ACCOUNT:-$(geth account list --keystore "$EXPANDED_GETH_DATA_DIR/keystore" 2>/dev/null | head -1 | grep -o '{[^}]*}' | sed 's/{//;s/}//' | sed 's/^/0x/' || echo "")}"

if [ -z "$GETH_ETHEREUM_ACCOUNT" ]; then
    echo "⚠️  Could not determine mining account. Please set GETH_ETHEREUM_ACCOUNT"
    exit 1
fi

echo "Mining account: $GETH_ETHEREUM_ACCOUNT"
echo "Starting Geth in background..."

# Start Geth in background
nohup geth \
    --port 3000 \
    --networkid 1101 \
    --identity 'local-dev' \
    --ws --ws.addr '127.0.0.1' --ws.port '8546' --ws.origins '*' \
    --ws.api 'admin,debug,web3,eth,txpool,personal,ethash,miner,net' \
    --http --http.port '8545' --http.addr '127.0.0.1' --http.corsdomain '' \
    --http.api 'admin,debug,web3,eth,txpool,personal,ethash,miner,net' \
    --datadir="$EXPANDED_GETH_DATA_DIR" \
    --allow-insecure-unlock \
    --miner.etherbase="$GETH_ETHEREUM_ACCOUNT" \
    --mine \
    --miner.threads=1 \
    > "$EXPANDED_GETH_DATA_DIR/geth.log" 2>&1 &

GETH_PID=$!
echo "Geth started (PID: $GETH_PID)"
echo ""

# Step 6: Wait for Geth to be ready
echo "=== Step 6: Waiting for Geth to be Ready ==="
echo "Waiting for RPC endpoint..."
for i in {1..30}; do
    if curl -s -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        http://localhost:8545 > /dev/null 2>&1; then
        echo "✓ Geth is ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "❌ Geth failed to start. Check logs: $EXPANDED_GETH_DATA_DIR/geth.log"
        exit 1
    fi
    sleep 1
done
echo ""

# Step 7: Unlock accounts
echo "=== Step 7: Unlocking Accounts ==="
echo "Unlocking accounts (password: password)..."
python3 <<EOF
import json
import subprocess
import sys

# Get accounts
result = subprocess.run(
    ["geth", "account", "list", "--keystore", "$EXPANDED_GETH_DATA_DIR/keystore"],
    capture_output=True,
    text=True
)

accounts = []
for line in result.stdout.split('\n'):
    if '{' in line:
        addr = line.split('{')[1].split('}')[0]
        accounts.append('0x' + addr)

if not accounts:
    print("No accounts found")
    sys.exit(1)

# Unlock each account
for addr in accounts[:10]:  # Unlock first 10 accounts
    unlock_data = {
        "jsonrpc": "2.0",
        "method": "personal_unlockAccount",
        "params": [addr, "password", 0],
        "id": 1
    }
    
    result = subprocess.run(
        ["curl", "-s", "-X", "POST", "-H", "Content-Type: application/json",
         "--data", json.dumps(unlock_data), "http://localhost:8545"],
        capture_output=True,
        text=True
    )
    
    response = json.loads(result.stdout)
    if response.get("result"):
        print(f"✓ Unlocked {addr}")
    else:
        print(f"⚠ Failed to unlock {addr}: {response.get('error', {}).get('message', 'unknown')}")

print(f"\n✓ Unlocked {len(accounts[:10])} accounts")
EOF
echo ""

# Step 8: Deploy contracts
echo "=== Step 8: Deploying Contracts ==="
cd "$ECDSA_DIR"
echo "Deploying contracts (this may take a few minutes)..."
if yarn deploy --network development --reset 2>&1 | tee /tmp/deploy.log; then
    echo "✓ Contracts deployed successfully"
else
    DEPLOY_EXIT_CODE=$?
    echo ""
    echo "⚠️  Deployment had issues (exit code: $DEPLOY_EXIT_CODE)"
    echo "   Checking if critical contracts were deployed..."
    
    # Check if WalletRegistry was deployed
    if [ -f "deployments/development/WalletRegistry.json" ]; then
        WR_ADDR=$(cat deployments/development/WalletRegistry.json | grep -o '"address":\s*"[^"]*"' | head -1 | cut -d'"' -f4)
        echo "   ✓ WalletRegistry deployed at: $WR_ADDR"
        echo ""
        echo "   Deployment may have failed on non-critical steps."
        echo "   You can try to continue with governance setup."
    else
        echo "   ❌ WalletRegistry not deployed. Please check the error above."
        echo "   Deployment log: /tmp/deploy.log"
        exit $DEPLOY_EXIT_CODE
    fi
fi
echo ""

# Step 9: Configure governance parameters
echo "=== Step 9: Configuring Governance Parameters ==="
cd "$ECDSA_DIR"

# 9a: Setup wallet owner
echo "Setting up wallet owner..."
npx hardhat run scripts/setup-wallet-owner-complete.ts --network development || {
    echo "⚠️  Wallet owner setup failed. You may need to run it manually."
}
echo ""

# 9b: Reduce governance delay (this will take time on first run)
echo "Reducing governance delay to 60 seconds..."
echo "Note: First time this may take a while (mining ~40k blocks)"
echo "      Subsequent runs will be much faster!"
echo ""
npx hardhat run scripts/reduce-governance-delay-complete.ts --network development || {
    echo "⚠️  Governance delay reduction failed or already in progress."
    echo "   Run it again later: npx hardhat run scripts/reduce-governance-delay-complete.ts --network development"
}
echo ""

# 9c: Set resultChallengePeriodLength (after governance delay is reduced)
echo "Setting resultChallengePeriodLength to 100 blocks..."
NEW_VALUE=100 npx hardhat run scripts/update-result-challenge-period-length.ts --network development || {
    echo "⚠️  resultChallengePeriodLength update failed."
    echo "   You may need to wait for governance delay to be reduced first."
}
echo ""

# Step 10: Update config.toml
echo "=== Step 10: Updating config.toml ==="
CONFIG_FILE="$PROJECT_ROOT/configs/config.toml"

if [ -f "$CONFIG_FILE" ]; then
    # Get WalletRegistry address from deployments
    WALLET_REGISTRY_ADDR=$(cat "$ECDSA_DIR/deployments/development/WalletRegistry.json" 2>/dev/null | grep -o '"address":\s*"[^"]*"' | head -1 | cut -d'"' -f4 || echo "")
    
    if [ -n "$WALLET_REGISTRY_ADDR" ]; then
        echo "Updating WalletRegistryAddress in config.toml..."
        
        # Use sed to update the address (works on macOS and Linux)
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s|WalletRegistryAddress = \".*\"|WalletRegistryAddress = \"$WALLET_REGISTRY_ADDR\"|" "$CONFIG_FILE"
        else
            sed -i "s|WalletRegistryAddress = \".*\"|WalletRegistryAddress = \"$WALLET_REGISTRY_ADDR\"|" "$CONFIG_FILE"
        fi
        
        echo "✓ Updated WalletRegistryAddress to $WALLET_REGISTRY_ADDR"
    else
        echo "⚠️  Could not find WalletRegistry address in deployments"
    fi
else
    echo "⚠️  Config file not found at $CONFIG_FILE"
fi
echo ""

# Summary
echo "=========================================="
echo "✅ Reset Complete!"
echo "=========================================="
echo ""
echo "Summary:"
echo "  ✓ Geth restarted and mining"
echo "  ✓ Contracts redeployed"
echo "  ✓ Governance parameters configured"
echo ""
echo "Next steps:"
echo "  1. Verify Geth is running: curl http://localhost:8545"
echo "  2. Check contract addresses in: $ECDSA_DIR/deployments/development/"
echo "  3. If governance delay reduction is still pending, run:"
echo "     cd $ECDSA_DIR"
echo "     npx hardhat run scripts/reduce-governance-delay-complete.ts --network development"
echo ""
echo "Geth logs: $EXPANDED_GETH_DATA_DIR/geth.log"
echo "Geth PID: $GETH_PID"
echo ""
echo "To stop Geth: kill $GETH_PID"
echo ""

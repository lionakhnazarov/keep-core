#!/bin/bash
# Script to deploy the complete Bridge contract from tbtc-v2
# This replaces BridgeStub with the full Bridge implementation

set -e

cd "$(dirname "$0")/.."

PROJECT_ROOT="$(pwd)"
NETWORK="${NETWORK:-development}"
TMP="$PROJECT_ROOT/tmp"
TBTC_SOL_PATH="$TMP/tbtc-v2/solidity"
THRESHOLD_SOL_PATH="$TMP/solidity-contracts"
ECDSA_SOL_PATH="$PROJECT_ROOT/solidity/ecdsa"
BEACON_SOL_PATH="$PROJECT_ROOT/solidity/random-beacon"

echo "=========================================="
echo "Deploy Complete Bridge Contract"
echo "=========================================="
echo ""
echo "Network: $NETWORK"
echo ""

# Check prerequisites
echo "Step 1: Checking prerequisites..."

if [ ! -d "$THRESHOLD_SOL_PATH/deployments/$NETWORK" ]; then
  echo "❌ Error: Threshold Network contracts not deployed"
  echo "   Run: ./scripts/install.sh --network $NETWORK"
  exit 1
fi

if [ ! -d "$BEACON_SOL_PATH/deployments/$NETWORK" ]; then
  echo "❌ Error: Random Beacon contracts not deployed"
  echo "   Run: ./scripts/install.sh --network $NETWORK"
  exit 1
fi

if [ ! -d "$ECDSA_SOL_PATH/deployments/$NETWORK" ]; then
  echo "❌ Error: ECDSA contracts not deployed"
  echo "   Run: ./scripts/install.sh --network $NETWORK"
  exit 1
fi

echo "✅ Prerequisites met"
echo ""

# Clone tbtc-v2 if needed
echo "Step 2: Setting up tbtc-v2 repository..."
mkdir -p "$TMP"

if [ ! -d "$TBTC_SOL_PATH" ]; then
  echo "Cloning tbtc-v2 repository..."
  cd "$TMP"
  git clone https://github.com/keep-network/tbtc-v2.git || {
    echo "❌ Error: Failed to clone tbtc-v2 repository"
    echo "   Make sure you have git access to https://github.com/keep-network/tbtc-v2"
    exit 1
  }
else
  echo "tbtc-v2 repository already exists, updating..."
  cd "$TBTC_SOL_PATH"
  git pull || echo "Warning: Could not update tbtc-v2 repository"
fi

cd "$TBTC_SOL_PATH"
echo "✅ tbtc-v2 repository ready"
echo ""

# Install dependencies
echo "Step 3: Installing dependencies..."
yarn install --mode=update-lockfile && yarn install || {
  echo "❌ Error: Failed to install tbtc-v2 dependencies"
  exit 1
}

# Update resolutions for local development
if [ -f "package.json" ] && [ -n "$THRESHOLD_SOL_PATH" ]; then
  echo "Updating package resolutions..."
  THRESHOLD_PORTAL_PATH="portal:$THRESHOLD_SOL_PATH"
  node -e "
    const fs = require('fs');
    const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
    if (!pkg.resolutions) pkg.resolutions = {};
    pkg.resolutions['@threshold-network/solidity-contracts'] = '$THRESHOLD_PORTAL_PATH';
    pkg.resolutions['@openzeppelin/contracts'] = '4.7.3';
    fs.writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');
  " 2>/dev/null || true
  
  yarn install --mode=update-lockfile && yarn install 2>/dev/null || true
fi

echo "✅ Dependencies installed"
echo ""

# Link local dependencies
echo "Step 4: Linking local dependencies..."

# Link threshold-network/solidity-contracts
yarn unlink "@threshold-network/solidity-contracts" 2>/dev/null || true
cd "$THRESHOLD_SOL_PATH"
yarn unlink 2>/dev/null || true && yarn link 2>/dev/null || true
cd "$TBTC_SOL_PATH"
yarn link "@threshold-network/solidity-contracts" 2>/dev/null || {
  echo "⚠️  Warning: Could not link threshold-network/solidity-contracts"
}

# Link random-beacon
yarn unlink "@keep-network/random-beacon" 2>/dev/null || true
cd "$BEACON_SOL_PATH"
yarn unlink 2>/dev/null || true && yarn link 2>/dev/null || true
cd "$TBTC_SOL_PATH"
yarn link "@keep-network/random-beacon" 2>/dev/null || {
  echo "⚠️  Warning: Could not link random-beacon"
}

# Link ecdsa
yarn unlink "@keep-network/ecdsa" 2>/dev/null || true
cd "$ECDSA_SOL_PATH"
yarn unlink 2>/dev/null || true && yarn link 2>/dev/null || true
cd "$TBTC_SOL_PATH"
yarn link "@keep-network/ecdsa" 2>/dev/null || {
  echo "⚠️  Warning: Could not link ecdsa"
}

echo "✅ Dependencies linked"
echo ""

# Build contracts
echo "Step 5: Building tbtc-v2 contracts..."
yarn build || {
  echo "❌ Error: Failed to build tbtc-v2 contracts"
  exit 1
}
echo "✅ Contracts built"
echo ""

# Get contract addresses needed for Bridge deployment
echo "Step 6: Getting contract addresses..."

WALLET_REGISTRY=$(jq -r '.address' "$ECDSA_SOL_PATH/deployments/$NETWORK/WalletRegistry.json" 2>/dev/null || echo "")
if [ -z "$WALLET_REGISTRY" ] || [ "$WALLET_REGISTRY" = "null" ]; then
  echo "❌ Error: WalletRegistry not found"
  exit 1
fi

REIMBURSEMENT_POOL=$(jq -r '.address' "$BEACON_SOL_PATH/deployments/$NETWORK/ReimbursementPool.json" 2>/dev/null || echo "")
if [ -z "$REIMBURSEMENT_POOL" ] || [ "$REIMBURSEMENT_POOL" = "null" ]; then
  echo "⚠️  Warning: ReimbursementPool not found, using zero address"
  REIMBURSEMENT_POOL="0x0000000000000000000000000000000000000000"
fi

echo "  WalletRegistry: $WALLET_REGISTRY"
echo "  ReimbursementPool: $REIMBURSEMENT_POOL"
echo ""

# Check if BridgeStub is deployed and needs to be replaced
echo "Step 7: Checking existing Bridge deployment..."
BRIDGE_STUB_PATH="$PROJECT_ROOT/solidity/tbtc-stub/deployments/$NETWORK/BridgeStub.json"
if [ -f "$BRIDGE_STUB_PATH" ]; then
  BRIDGE_STUB_ADDR=$(jq -r '.address' "$BRIDGE_STUB_PATH" 2>/dev/null || echo "")
  echo "  Found BridgeStub at: $BRIDGE_STUB_ADDR"
  echo "  This will be replaced with the complete Bridge contract"
fi
echo ""

# Deploy Bridge contract
echo "Step 8: Deploying complete Bridge contract..."
echo ""
echo "⚠️  Note: Bridge deployment requires additional contracts:"
echo "   - Bank (TBTCToken)"
echo "   - LightRelay"
echo "   - MaintainerProxy"
echo "   - WalletProposalValidator"
echo ""
echo "Deploying all tbtc-v2 contracts..."
yarn deploy --reset --network $NETWORK || {
  echo "❌ Error: Failed to deploy tbtc-v2 contracts"
  echo ""
  echo "Troubleshooting:"
  echo "  1. Make sure Geth is running: ./scripts/start-geth-fast.sh"
  echo "  2. Check that all dependencies are linked correctly"
  echo "  3. Review the error messages above"
  exit 1
}

# Get deployed Bridge address
BRIDGE_DEPLOYMENT="$TBTC_SOL_PATH/deployments/$NETWORK/Bridge.json"
if [ ! -f "$BRIDGE_DEPLOYMENT" ]; then
  echo "❌ Error: Bridge deployment file not found"
  exit 1
fi

BRIDGE_ADDRESS=$(jq -r '.address' "$BRIDGE_DEPLOYMENT" 2>/dev/null || echo "")
if [ -z "$BRIDGE_ADDRESS" ] || [ "$BRIDGE_ADDRESS" = "null" ]; then
  echo "❌ Error: Could not get Bridge address from deployment"
  exit 1
fi

echo "✅ Bridge deployed at: $BRIDGE_ADDRESS"
echo ""

# Update WalletRegistry walletOwner
echo "Step 9: Setting Bridge as WalletRegistry walletOwner..."
cd "$ECDSA_SOL_PATH"

# Check current walletOwner
CURRENT_OWNER=$(cast call "$WALLET_REGISTRY" "walletOwner()" --rpc-url http://localhost:8545 2>/dev/null || echo "0x0")

if [ "$CURRENT_OWNER" != "$BRIDGE_ADDRESS" ]; then
  echo "  Current walletOwner: $CURRENT_OWNER"
  echo "  Setting to Bridge: $BRIDGE_ADDRESS"
  
  # Try to use the initialize-wallet-owner script
  if [ -f "scripts/init-wallet-owner.ts" ]; then
    npx hardhat run scripts/init-wallet-owner.ts --network $NETWORK -- --wallet-owner-address "$BRIDGE_ADDRESS" || {
      echo "⚠️  Warning: Could not run init-wallet-owner script"
      echo "   You may need to set walletOwner manually:"
      echo "   cast send $WALLET_REGISTRY \"updateWalletOwner(address)\" $BRIDGE_ADDRESS --rpc-url http://localhost:8545"
    }
  else
    echo "⚠️  init-wallet-owner.ts not found, setting manually..."
    echo "   Run: cast send $WALLET_REGISTRY \"updateWalletOwner(address)\" $BRIDGE_ADDRESS --rpc-url http://localhost:8545"
  fi
else
  echo "  ✅ walletOwner already set to Bridge"
fi

echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""
echo "Bridge Contract: $BRIDGE_ADDRESS"
echo ""
echo "Deployed Contracts:"
echo "  - Bridge: $BRIDGE_ADDRESS"
if [ -f "$TBTC_SOL_PATH/deployments/$NETWORK/Bank.json" ]; then
  BANK_ADDR=$(jq -r '.address' "$TBTC_SOL_PATH/deployments/$NETWORK/Bank.json" 2>/dev/null || echo "N/A")
  echo "  - Bank: $BANK_ADDR"
fi
if [ -f "$TBTC_SOL_PATH/deployments/$NETWORK/MaintainerProxy.json" ]; then
  MP_ADDR=$(jq -r '.address' "$TBTC_SOL_PATH/deployments/$NETWORK/MaintainerProxy.json" 2>/dev/null || echo "N/A")
  echo "  - MaintainerProxy: $MP_ADDR"
fi
echo ""
echo "Next Steps:"
echo "  1. Verify Bridge is set as walletOwner in WalletRegistry"
echo "  2. Use ./scripts/emulate-deposit.sh to prepare deposit data"
echo "  3. Call revealDeposit() on Bridge with the prepared data"
echo ""

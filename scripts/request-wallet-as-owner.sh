#!/bin/bash
# Request new wallet using the account that IS the wallet owner

set -e

WALLET_REGISTRY=${1:-0xc0a2ee534F004a4ec2EFA541489acBD5ff4bBA99}
RPC_URL=${2:-http://localhost:8545}

echo "=== Request New Wallet ==="
echo "WalletRegistry: $WALLET_REGISTRY"
echo ""

# Try to get wallet owner using Hardhat
echo "Checking current wallet owner..."
cd solidity/ecdsa

WALLET_OWNER=$(npx hardhat run --network development << 'EOF' 2>/dev/null | grep -i "wallet owner" | tail -1 | awk -F': ' '{print $2}' || echo "")
const hre = require("hardhat");
(async () => {
  const { deployments } = hre;
  const WalletRegistry = await deployments.get("WalletRegistry");
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address);
  const walletOwner = await wr.walletOwner();
  console.log("Wallet Owner:", walletOwner);
})();
EOF

# Alternative: try using a simple node script
if [ -z "$WALLET_OWNER" ] || [ "$WALLET_OWNER" = "" ]; then
  echo "Trying alternative method..."
  WALLET_OWNER=$(node << 'EOF'
const hre = require("hardhat");
(async () => {
  await hre.run("compile");
  const { deployments } = hre;
  const WalletRegistry = await deployments.get("WalletRegistry");
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address);
  const walletOwner = await wr.walletOwner();
  console.log(walletOwner);
  process.exit(0);
})().catch(err => {
  console.error(err.message);
  process.exit(1);
});
EOF
  )
fi

cd ../..

if [ -z "$WALLET_OWNER" ] || [ "$WALLET_OWNER" = "0x0000000000000000000000000000000000000000" ]; then
  echo "❌ Could not determine wallet owner"
  echo ""
  echo "Please check manually:"
  echo "  cd solidity/ecdsa"
  echo "  npx hardhat console --network development"
  echo "  const wr = await ethers.getContractAt('WalletRegistry', '0xc0a2ee534F004a4ec2EFA541489acBD5ff4bBA99')"
  echo "  await wr.walletOwner()"
  exit 1
fi

echo "Current Wallet Owner: $WALLET_OWNER"
echo ""

# Check if this is a contract (Bridge) or EOA
IS_CONTRACT=$(cast code "$WALLET_OWNER" --rpc-url "$RPC_URL" 2>/dev/null | grep -q "0x" && echo "yes" || echo "no")

if [ "$IS_CONTRACT" = "yes" ]; then
  echo "Wallet owner is a contract (likely Bridge)"
  echo ""
  echo "Calling Bridge.requestNewWallet()..."
  cast send "$WALLET_OWNER" "requestNewWallet()" \
    --rpc-url "$RPC_URL" \
    --unlocked \
    --from $(cast rpc eth_accounts --rpc-url "$RPC_URL" | jq -r '.[0]') || {
    echo ""
    echo "If that failed, try calling directly:"
    echo "  cast send $WALLET_OWNER \"requestNewWallet()\" \\"
    echo "    --rpc-url $RPC_URL \\"
    echo "    --unlocked"
  }
else
  echo "Wallet owner is an EOA (Externally Owned Account)"
  echo ""
  echo "To request a new wallet, use this account:"
  echo "  cast send $WALLET_REGISTRY \"requestNewWallet()\" \\"
  echo "    --rpc-url $RPC_URL \\"
  echo "    --unlocked \\"
  echo "    --from $WALLET_OWNER"
  echo ""
  read -p "Call requestNewWallet() now? (y/n) [default: n]: " confirm
  confirm=${confirm:-n}
  
  if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
    cast send "$WALLET_REGISTRY" "requestNewWallet()" \
      --rpc-url "$RPC_URL" \
      --unlocked \
      --from "$WALLET_OWNER"
    echo ""
    echo "✓ Wallet request submitted!"
  else
    echo "Skipped. Run the command manually when ready."
  fi
fi



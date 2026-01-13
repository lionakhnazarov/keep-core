#!/bin/bash
# Simple script to check wallet owner and provide instructions

set -e

WALLET_REGISTRY=${1:-0xc0a2ee534F004a4ec2EFA541489acBD5ff4bBA99}
RPC_URL=${2:-http://localhost:8545}

echo "=== Wallet Owner Check ==="
echo "WalletRegistry: $WALLET_REGISTRY"
echo ""

cd solidity/ecdsa

echo "Checking wallet owner via Hardhat..."
npx hardhat run --network development << 'SCRIPT' 2>&1 | grep -v "You are using a version" | grep -v "No need to generate" | grep -v "Contract Name" | grep -v "·" | grep -v "Size" | grep -v "Error encountered" || true

const hre = require("hardhat");

(async () => {
  try {
    const { deployments } = hre;
    const WalletRegistry = await deployments.get("WalletRegistry");
    const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address);
    const walletOwner = await wr.walletOwner();
    
    console.log("\nCurrent Wallet Owner:", walletOwner);
    
    if (walletOwner === ethers.constants.AddressZero) {
      console.log("\n❌ Wallet owner is not set!");
      console.log("\nTo set it:");
      console.log("  npx hardhat initialize-wallet-owner --wallet-owner-address <ADDRESS> --network development");
      process.exit(1);
    }
    
    // Check if contract
    const code = await ethers.provider.getCode(walletOwner);
    const isContract = code !== "0x";
    
    if (isContract) {
      console.log("\n✓ Wallet owner is a contract (likely Bridge)");
      console.log("\nTo request a new wallet:");
      console.log(`  cast send ${walletOwner} "requestNewWallet()" \\`);
      console.log(`    --rpc-url ${process.env.RPC_URL || "http://localhost:8545"} \\`);
      console.log(`    --unlocked`);
    } else {
      console.log("\n✓ Wallet owner is an EOA");
      console.log("\nTo use Keep Client, update config.toml KeyFile to this account's keystore");
      console.log("\nOr call directly:");
      console.log(`  cast send ${WalletRegistry.address} "requestNewWallet()" \\`);
      console.log(`    --rpc-url ${process.env.RPC_URL || "http://localhost:8545"} \\`);
      console.log(`    --unlocked \\`);
      console.log(`    --from ${walletOwner}`);
    }
    
    // Check DKG state
    try {
      const dkgState = await wr.getWalletCreationState();
      const states = ["IDLE", "AWAITING_SEED", "AWAITING_RESULT", "CHALLENGE"];
      const stateName = states[dkgState] || `UNKNOWN(${dkgState})`;
      console.log(`\nDKG State: ${stateName}`);
      if (dkgState === 0) {
        console.log("✓ Ready for new wallet request");
      }
    } catch (e) {
      // Ignore
    }
    
  } catch (error) {
    console.error("Error:", error.message);
    process.exit(1);
  }
})();

SCRIPT

cd ../..



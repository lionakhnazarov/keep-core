#!/usr/bin/env node
// Check wallet owner and request new wallet

const path = require("path");
const fs = require("fs");

// Change to solidity/ecdsa directory if running from root
const originalDir = process.cwd();
const ecdsaDir = path.join(originalDir, "solidity", "ecdsa");
if (fs.existsSync(ecdsaDir)) {
  process.chdir(ecdsaDir);
}

const hre = require("hardhat");
const { deployments } = require("hardhat");

async function main() {
  const network = process.env.NETWORK || "development";
  
  console.log("=== Check Wallet Owner and Request New Wallet ===\n");
  
  try {
    await hre.run("compile");
    
    const WalletRegistry = await deployments.get("WalletRegistry");
    console.log(`WalletRegistry: ${WalletRegistry.address}\n`);
    
    const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address);
    const walletOwner = await wr.walletOwner();
    
    console.log(`Current Wallet Owner: ${walletOwner}\n`);
    
    if (walletOwner === ethers.constants.AddressZero) {
      console.log("❌ Wallet owner is not set!");
      console.log("\nTo set it, run:");
      console.log("  cd solidity/ecdsa");
      console.log("  npx hardhat initialize-wallet-owner --wallet-owner-address <ADDRESS> --network development");
      process.exit(1);
    }
    
    // Check if it's a contract
    const code = await ethers.provider.getCode(walletOwner);
    const isContract = code !== "0x";
    
    if (isContract) {
      console.log("Wallet owner is a contract (likely Bridge)");
      console.log("\nTo request a new wallet, call Bridge.requestNewWallet():");
      console.log(`  cast send ${walletOwner} "requestNewWallet()" \\`);
      console.log(`    --rpc-url http://localhost:8545 \\`);
      console.log(`    --unlocked`);
      
      // Try to get Bridge contract and call it
      try {
        const bridge = await ethers.getContractAt(
          ["function requestNewWallet() external"],
          walletOwner
        );
        console.log("\nAttempting to call Bridge.requestNewWallet()...");
        const tx = await bridge.requestNewWallet({ gasLimit: 500000 });
        console.log(`Transaction submitted: ${tx.hash}`);
        const receipt = await tx.wait();
        console.log(`✓ Success! Transaction confirmed in block: ${receipt.blockNumber}`);
      } catch (error) {
        console.log(`\n⚠️  Could not call Bridge directly: ${error.message}`);
        console.log("Please use cast command above or ensure Bridge contract is deployed correctly.");
      }
    } else {
      console.log("Wallet owner is an EOA (Externally Owned Account)");
      console.log("\nTo request a new wallet using Keep Client:");
      console.log("Update your config.toml KeyFile to use this account:");
      console.log(`  KeyFile = "<path-to-keystore-for-${walletOwner}>"`);
      console.log("\nOr use cast directly:");
      console.log(`  cast send ${WalletRegistry.address} "requestNewWallet()" \\`);
      console.log(`    --rpc-url http://localhost:8545 \\`);
      console.log(`    --unlocked \\`);
      console.log(`    --from ${walletOwner}`);
    }
    
    // Check DKG state
    try {
      const dkgState = await wr.getWalletCreationState();
      const states = ["IDLE", "AWAITING_SEED", "AWAITING_RESULT", "CHALLENGE"];
      const stateName = states[dkgState] || `UNKNOWN(${dkgState})`;
      console.log(`\nCurrent DKG State: ${stateName}`);
      
      if (dkgState !== 0) {
        console.log("⚠️  DKG is not in IDLE state. Wait for current DKG to complete.");
      } else {
        console.log("✓ DKG is in IDLE state - ready for new wallet request");
      }
    } catch (error) {
      console.log(`\n⚠️  Could not check DKG state: ${error.message}`);
    }
    
  } catch (error) {
    console.error("Error:", error.message);
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });


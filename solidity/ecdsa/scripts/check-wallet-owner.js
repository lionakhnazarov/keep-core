const hre = require("hardhat");

async function main() {
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
      console.log(`    --rpc-url http://localhost:8545 \\`);
      console.log(`    --unlocked`);
    } else {
      console.log("\n✓ Wallet owner is an EOA");
      console.log("\nTo use Keep Client, update config.toml KeyFile to this account's keystore");
      console.log("\nOr call directly:");
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
      console.log(`\nDKG State: ${stateName}`);
      if (dkgState === 0) {
        console.log("✓ Ready for new wallet request");
      } else {
        console.log("⚠️  Wait for current DKG to complete");
      }
    } catch (e) {
      // Ignore
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


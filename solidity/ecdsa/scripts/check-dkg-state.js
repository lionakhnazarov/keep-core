const hre = require("hardhat");

async function main() {
  const { deployments } = hre;
  const WalletRegistry = await deployments.get("WalletRegistry");
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address);
  
  const dkgState = await wr.getWalletCreationState();
  const states = ["IDLE", "AWAITING_SEED", "AWAITING_RESULT", "CHALLENGE"];
  const stateName = states[dkgState] || `UNKNOWN(${dkgState})`;
  
  console.log("DKG State:", stateName);
  console.log("");
  
  if (dkgState === 0) {
    console.log("✓ Ready to request a new wallet");
  } else if (dkgState === 1) {
    console.log("✓ Waiting for RandomBeacon to generate seed");
    console.log("DKG will start automatically once seed is ready");
  } else if (dkgState === 2) {
    console.log("✓ DKG in progress - operators are generating keys");
  } else if (dkgState === 3) {
    console.log("⚠️  DKG result was challenged - operators are validating");
  }
  
  // Get DKG data if available
  try {
    const dkgData = await wr.getDkgData();
    if (dkgData.seed.gt(0)) {
      console.log("\nDKG Details:");
      console.log("  Seed:", dkgData.seed.toString());
      console.log("  Start Block:", dkgData.startBlock.toString());
    }
  } catch (e) {
    // Ignore if not available
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });


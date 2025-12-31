import { HardhatRuntimeEnvironment } from "hardhat/types"

async function main() {
  const hre: HardhatRuntimeEnvironment = require("hardhat")
  const { ethers, helpers } = hre
  
  console.log("=== Update Governance Delay ===")
  console.log("")
  console.log("Reducing governance delay will make future updates much faster.")
  console.log("")
  
  const wrGov = await helpers.contracts.getContract("WalletRegistryGovernance")
  
  // Get current value
  const currentDelay = await wrGov.governanceDelay()
  console.log("Current governanceDelay:", currentDelay.toString(), "seconds")
  console.log("  (~", (currentDelay.toNumber() / 3600).toFixed(2), "hours)")
  console.log("  (~", (currentDelay.toNumber() / 86400).toFixed(2), "days)")
  console.log("")
  
  // Get new value from environment or use default
  const newValueArg = process.env.NEW_VALUE || process.argv[process.argv.length - 1]
  if (!newValueArg || isNaN(parseInt(newValueArg))) {
    console.log("Usage: NEW_VALUE=<seconds> npx hardhat run scripts/update-governance-delay.ts --network development")
    console.log("")
    console.log("Example: NEW_VALUE=60 npx hardhat run scripts/update-governance-delay.ts --network development")
    console.log("  (sets governance delay to 60 seconds)")
    console.log("")
    console.log("Recommended values:")
    console.log("  - 60 seconds: Very fast for development")
    console.log("  - 300 seconds (5 min): Quick testing")
    console.log("  - 3600 seconds (1 hour): Moderate delay")
    console.log("  - 604800 seconds (7 days): Production default")
    process.exit(1)
  }
  
  const newValue = ethers.BigNumber.from(newValueArg)
  console.log("New value:", newValue.toString(), "seconds")
  console.log("  (~", (newValue.toNumber() / 60).toFixed(1), "minutes)")
  console.log("")
  
  if (newValue.eq(currentDelay)) {
    console.log("⚠️  New value is the same as current value. No update needed.")
    process.exit(0)
  }
  
  // Get owner
  const owner = await wrGov.owner()
  const signer = await ethers.getSigner(owner)
  const wrGovConnected = wrGov.connect(signer)
  
  // Check pending update
  const changeInitiated = await wrGov.governanceDelayChangeInitiated()
  const pendingNewValue = await wrGov.newGovernanceDelay()
  
  if (changeInitiated.gt(0)) {
    console.log("⚠️  There's already a pending update:")
    console.log("  Pending value:", pendingNewValue.toString(), "seconds")
    console.log("  Change initiated:", changeInitiated.toString())
    
    const block = await ethers.provider.getBlock("latest")
    const blockTimestamp = (block.timestamp as any).toNumber ? (block.timestamp as any).toNumber() : Number(block.timestamp)
    const timeElapsed = blockTimestamp - changeInitiated.toNumber()
    const remaining = currentDelay.toNumber() - timeElapsed
    
    console.log("  Time elapsed:", timeElapsed.toString(), "seconds")
    console.log("  Remaining:", remaining.toString(), "seconds")
    console.log("")
    
    if (remaining <= 0) {
      console.log("✓ Governance delay has passed! Finalizing pending update...")
      const finalizeTx = await wrGovConnected.finalizeGovernanceDelayUpdate()
      await finalizeTx.wait()
      console.log("✓ Finalized! Transaction:", finalizeTx.hash)
      console.log("")
      
      // Verify
      const newDelay = await wrGov.governanceDelay()
      console.log("New governanceDelay:", newDelay.toString(), "seconds")
      console.log("")
      
      // Now begin new update if different
      if (!newValue.eq(newDelay)) {
        console.log("Beginning new update...")
        const beginTx = await wrGovConnected.beginGovernanceDelayUpdate(newValue)
        await beginTx.wait()
        console.log("✓ Update initiated! Transaction:", beginTx.hash)
        console.log("")
        console.log("To finalize after governance delay:")
        console.log("  NEW_VALUE=" + newValue.toString() + " npx hardhat run scripts/update-governance-delay.ts --network development")
      } else {
        console.log("✓ Already at desired value!")
      }
    } else {
      console.log("⏳ Cannot finalize yet. Need to wait", remaining.toString(), "more seconds")
      console.log("   (~", (remaining / 3600).toFixed(2), "hours)")
      console.log("")
      console.log("Options:")
      console.log("  1. Wait for governance delay to pass")
      console.log("  2. Use faketime + mine blocks to advance time")
      console.log("  3. Run this script again later to finalize")
      process.exit(0)
    }
  } else {
    // No pending update, begin new one
    console.log("Beginning governance delay update...")
    console.log("⚠️  Note: This update itself requires the current governance delay to pass!")
    console.log("   After this update is finalized, future updates will be faster.")
    console.log("")
    
    const beginTx = await wrGovConnected.beginGovernanceDelayUpdate(newValue)
    await beginTx.wait()
    console.log("✓ Update initiated! Transaction:", beginTx.hash)
    console.log("")
    
    console.log("Current governance delay:", currentDelay.toString(), "seconds")
    console.log("  (~", (currentDelay.toNumber() / 3600).toFixed(2), "hours)")
    console.log("")
    console.log("To finalize after governance delay:")
    console.log("  NEW_VALUE=" + newValue.toString() + " npx hardhat run scripts/update-governance-delay.ts --network development")
    console.log("")
    console.log("Or use faketime + mine blocks to advance time faster.")
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

import { HardhatRuntimeEnvironment } from "hardhat/types"

async function main() {
  const hre: HardhatRuntimeEnvironment = require("hardhat")
  const { ethers, helpers } = hre
  
  console.log("=== Update resultChallengePeriodLength ===")
  console.log("")
  
  const wr = await helpers.contracts.getContract("WalletRegistry")
  const wrGov = await helpers.contracts.getContract("WalletRegistryGovernance")
  
  // Get current value
  const params = await wr.dkgParameters()
  const currentValue = params.resultChallengePeriodLength
  console.log("Current resultChallengePeriodLength:", currentValue.toString(), "blocks")
  console.log("  (~", (currentValue.toNumber() / 240).toFixed(1), "hours at 15s/block)")
  console.log("")
  
  // Get new value from environment variable or command line args
  const newValueArg = process.env.NEW_VALUE || process.argv[process.argv.length - 1]
  if (!newValueArg || isNaN(parseInt(newValueArg))) {
    console.log("Usage: NEW_VALUE=<blocks> npx hardhat run scripts/update-result-challenge-period-length.ts --network development")
    console.log("   OR: npx hardhat run scripts/update-result-challenge-period-length.ts --network development -- <blocks>")
    console.log("")
    console.log("Example: NEW_VALUE=100 npx hardhat run scripts/update-result-challenge-period-length.ts --network development")
    console.log("  (sets challenge period to 100 blocks)")
    console.log("")
    console.log("Current value:", currentValue.toString(), "blocks")
    process.exit(1)
  }
  
  const newValue = ethers.BigNumber.from(newValueArg)
  console.log("New value:", newValue.toString(), "blocks")
  console.log("  (~", (newValue.toNumber() / 240).toFixed(1), "hours at 15s/block)")
  console.log("")
  
  // Validate
  if (newValue.lt(10)) {
    console.log("❌ Error: resultChallengePeriodLength must be >= 10 blocks")
    process.exit(1)
  }
  
  if (newValue.eq(currentValue)) {
    console.log("⚠️  New value is the same as current value. No update needed.")
    process.exit(0)
  }
  
  // Get owner
  const owner = await wrGov.owner()
  const signer = await ethers.getSigner(owner)
  const wrGovConnected = wrGov.connect(signer)
  
  // Check if there's a pending update
  const changeInitiated = await wrGov.dkgResultChallengePeriodLengthChangeInitiated()
  const pendingNewValue = await wrGov.newDkgResultChallengePeriodLength()
  
  if (changeInitiated.gt(0)) {
    console.log("⚠️  There's already a pending update:")
    console.log("  Pending value:", pendingNewValue.toString(), "blocks")
    console.log("  Change initiated:", changeInitiated.toString())
    
    const governanceDelay = await wrGov.governanceDelay()
    const block = await ethers.provider.getBlock("latest")
    const timeElapsed = block.timestamp - changeInitiated.toNumber()
    const remaining = governanceDelay.toNumber() - timeElapsed
    
    console.log("  Time elapsed:", timeElapsed.toString(), "seconds")
    console.log("  Remaining:", remaining.toString(), "seconds")
    console.log("")
    
    if (remaining <= 0) {
      console.log("✓ Governance delay has passed! Finalizing pending update...")
      const finalizeTx = await wrGovConnected.finalizeDkgResultChallengePeriodLengthUpdate()
      await finalizeTx.wait()
      console.log("✓ Finalized! Transaction:", finalizeTx.hash)
      console.log("")
      
      // Verify
      const newParams = await wr.dkgParameters()
      console.log("Updated resultChallengePeriodLength:", newParams.resultChallengePeriodLength.toString(), "blocks")
      console.log("")
      
      // Now begin new update if different
      if (!newValue.eq(newParams.resultChallengePeriodLength)) {
        console.log("Beginning new update...")
        const beginTx = await wrGovConnected.beginDkgResultChallengePeriodLengthUpdate(newValue)
        await beginTx.wait()
        console.log("✓ Update initiated! Transaction:", beginTx.hash)
        console.log("")
        console.log("To finalize after governance delay:")
        console.log("  npx hardhat run scripts/update-result-challenge-period-length.ts --network development", newValue.toString())
      } else {
        console.log("✓ Already at desired value!")
      }
    } else {
      console.log("⏳ Cannot finalize yet. Need to wait", remaining.toString(), "more seconds")
      console.log("")
      console.log("Options:")
      console.log("  1. Wait for governance delay to pass")
      console.log("  2. Use faketime to advance time (for development)")
      console.log("  3. Cancel and start new update (not supported - must finalize first)")
      process.exit(0)
    }
  } else {
    // No pending update, begin new one
    console.log("Beginning update...")
    const beginTx = await wrGovConnected.beginDkgResultChallengePeriodLengthUpdate(newValue)
    await beginTx.wait()
    console.log("✓ Update initiated! Transaction:", beginTx.hash)
    console.log("")
    
    const governanceDelay = await wrGov.governanceDelay()
    console.log("Governance delay:", governanceDelay.toString(), "seconds")
    console.log("  (~", (governanceDelay.toNumber() / 3600).toFixed(2), "hours)")
    console.log("")
    console.log("To finalize after governance delay:")
    console.log("  npx hardhat run scripts/update-result-challenge-period-length.ts --network development", newValue.toString())
    console.log("")
    console.log("Or use faketime to advance time (for development):")
    console.log("  bash /tmp/restart-geth-with-faketime.sh")
    console.log("  # Then run this script again to finalize")
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

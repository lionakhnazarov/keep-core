import { HardhatRuntimeEnvironment } from "hardhat/types"

async function main() {
  const hre: HardhatRuntimeEnvironment = require("hardhat")
  const { ethers, helpers } = hre
  
  console.log("=== Finalize Update with Faketime ===")
  console.log("")
  console.log("Note: This script assumes geth is running with faketime")
  console.log("and that enough blocks have been mined to advance timestamps.")
  console.log("")
  
  const wr = await helpers.contracts.getContract("WalletRegistry")
  const wrGov = await helpers.contracts.getContract("WalletRegistryGovernance")
  
  // Check pending update
  const changeInitiated = await wrGov.dkgResultChallengePeriodLengthChangeInitiated()
  const newValue = await wrGov.newDkgResultChallengePeriodLength()
  
  if (changeInitiated.eq(0)) {
    console.log("⚠️  No pending update to finalize")
    process.exit(0)
  }
  
  console.log("Pending update:")
  console.log("  New value:", newValue.toString(), "blocks")
  console.log("  Change initiated:", changeInitiated.toString())
  
  // Check timing
  const governanceDelay = await wrGov.governanceDelay()
  const block = await ethers.provider.getBlock("latest")
  const timeElapsed = block.timestamp - changeInitiated.toNumber()
  const remaining = governanceDelay.toNumber() - timeElapsed
  
  console.log("\nTiming:")
  console.log("  Current block timestamp:", block.timestamp.toString())
  console.log("  Time elapsed:", timeElapsed.toString(), "seconds")
  console.log("  Governance delay:", governanceDelay.toString(), "seconds")
  console.log("  Remaining:", remaining.toString(), "seconds")
  
  if (remaining > 0) {
    const blocksNeeded = Math.ceil(remaining / 15)
    console.log("\n⚠️  Cannot finalize yet. Need", remaining.toString(), "more seconds")
    console.log("   (~", blocksNeeded.toString(), "blocks at 15s/block)")
    console.log("")
    console.log("Options:")
    console.log("1. Mine blocks manually (slow):")
    console.log("   Each block advances ~15 seconds")
    console.log("   You need ~", blocksNeeded.toString(), "more blocks")
    console.log("")
    console.log("2. Use a shorter governance delay (if possible):")
    console.log("   Update governanceDelay first, then retry")
    console.log("")
    console.log("3. Wait for real time to pass (7 days)")
    process.exit(0)
  }
  
  // Finalize
  console.log("\n✓ Governance delay has passed! Finalizing...")
  const owner = await wrGov.owner()
  const signer = await ethers.getSigner(owner)
  const wrGovConnected = wrGov.connect(signer)
  
  const finalizeTx = await wrGovConnected.finalizeDkgResultChallengePeriodLengthUpdate()
  await finalizeTx.wait()
  console.log("✓ Finalized! Transaction:", finalizeTx.hash)
  
  // Verify
  const params = await wr.dkgParameters()
  console.log("\n=== Verification ===")
  console.log("New resultChallengePeriodLength:", params.resultChallengePeriodLength.toString(), "blocks")
  
  if (params.resultChallengePeriodLength.eq(newValue)) {
    console.log("\n✅ SUCCESS! Parameter updated successfully!")
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

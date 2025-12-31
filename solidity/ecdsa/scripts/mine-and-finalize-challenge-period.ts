import { HardhatRuntimeEnvironment } from "hardhat/types"

async function main() {
  const hre: HardhatRuntimeEnvironment = require("hardhat")
  const { ethers, helpers } = hre
  
  console.log("=== Mine Blocks and Finalize resultChallengePeriodLength ===")
  console.log("")
  console.log("This script will mine blocks until governance delay passes,")
  console.log("then automatically finalize the update.")
  console.log("")
  
  const wr = await helpers.contracts.getContract("WalletRegistry")
  const wrGov = await helpers.contracts.getContract("WalletRegistryGovernance")
  
  // Check pending update
  const changeInitiated = await wrGov.dkgResultChallengePeriodLengthChangeInitiated()
  const newValue = await wrGov.newDkgResultChallengePeriodLength()
  
  if (changeInitiated.eq(0)) {
    console.log("⚠️  No pending update")
    process.exit(0)
  }
  
  const governanceDelay = await wrGov.governanceDelay()
  let block = await ethers.provider.getBlock("latest")
  let elapsed = block.timestamp - changeInitiated.toNumber()
  let remaining = governanceDelay.toNumber() - elapsed
  
  console.log("Pending update:", newValue.toString(), "blocks")
  console.log("Time remaining:", remaining.toString(), "seconds")
  console.log("Blocks needed: ~", Math.ceil(remaining / 15))
  console.log("")
  
  if (remaining <= 0) {
    console.log("✓ Ready to finalize!")
  } else {
    console.log("⚠️  This will mine", Math.ceil(remaining / 15), "blocks")
    console.log("   This may take a while. Press Ctrl+C to cancel.")
    console.log("")
    
    // Mine blocks in background batches
    const [deployer] = await ethers.getSigners()
    const batchSize = 100
    let totalMined = 0
    
    while (remaining > 0 && totalMined < 50000) {
      // Mine a batch
      for (let i = 0; i < batchSize; i++) {
        try {
          const tx = await deployer.sendTransaction({
            to: deployer.address,
            value: 0,
            gasLimit: 21000
          })
          await tx.wait()
          totalMined++
        } catch (e) {
          // Continue on error
        }
      }
      
      // Check progress
      block = await ethers.provider.getBlock("latest")
      elapsed = block.timestamp - changeInitiated.toNumber()
      remaining = governanceDelay.toNumber() - elapsed
      
      console.log(`Mined ${totalMined} blocks. Remaining: ${remaining.toString()} seconds`)
      
      if (remaining <= 0) {
        console.log("✓ Enough time has passed!")
        break
      }
    }
  }
  
  // Finalize
  block = await ethers.provider.getBlock("latest")
  elapsed = block.timestamp - changeInitiated.toNumber()
  remaining = governanceDelay.toNumber() - elapsed
  
  if (remaining > 0) {
    console.log("\n⚠️  Still need", remaining.toString(), "seconds")
    console.log("   Run this script again to continue mining")
    process.exit(0)
  }
  
  console.log("\n✓ Finalizing...")
  const owner = await wrGov.owner()
  const signer = await ethers.getSigner(owner)
  const wrGovConnected = wrGov.connect(signer)
  
  const finalizeTx = await wrGovConnected.finalizeDkgResultChallengePeriodLengthUpdate()
  await finalizeTx.wait()
  console.log("✓ Finalized! Transaction:", finalizeTx.hash)
  
  // Verify
  const params = await wr.dkgParameters()
  console.log("\nNew resultChallengePeriodLength:", params.resultChallengePeriodLength.toString(), "blocks")
  console.log("✅ SUCCESS!")
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

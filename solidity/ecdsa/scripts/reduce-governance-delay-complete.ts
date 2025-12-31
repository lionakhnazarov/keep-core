import { HardhatRuntimeEnvironment } from "hardhat/types"

async function main() {
  const hre: HardhatRuntimeEnvironment = require("hardhat")
  const { ethers, helpers } = hre
  
  console.log("=== Complete: Reduce Governance Delay ===")
  console.log("")
  console.log("This script will:")
  console.log("  1. Begin governance delay update to 60 seconds")
  console.log("  2. Mine blocks until current delay passes")
  console.log("  3. Finalize the governance delay update")
  console.log("  4. Then future updates will be much faster!")
  console.log("")
  
  const wrGov = await helpers.contracts.getContract("WalletRegistryGovernance")
  
  // Get current value
  const currentDelay = await wrGov.governanceDelay()
  console.log("Current governanceDelay:", currentDelay.toString(), "seconds")
  console.log("  (~", (currentDelay.toNumber() / 3600).toFixed(2), "hours)")
  console.log("")
  
  // Target: 60 seconds for development
  const targetDelay = ethers.BigNumber.from("60")
  console.log("Target governanceDelay:", targetDelay.toString(), "seconds")
  console.log("")
  
  // Get owner
  const owner = await wrGov.owner()
  const signer = await ethers.getSigner(owner)
  const wrGovConnected = wrGov.connect(signer)
  
  // Check pending update
  const changeInitiated = await wrGov.governanceDelayChangeInitiated()
  const pendingNewValue = await wrGov.newGovernanceDelay()
  
  if (changeInitiated.gt(0)) {
    console.log("⚠️  Pending update exists:")
    console.log("  Pending value:", pendingNewValue.toString(), "seconds")
    
    const block = await ethers.provider.getBlock("latest")
    const blockTimestamp = (block.timestamp as any).toNumber ? (block.timestamp as any).toNumber() : Number(block.timestamp)
    const timeElapsed = blockTimestamp - changeInitiated.toNumber()
    const remaining = currentDelay.toNumber() - timeElapsed
    
    console.log("  Time elapsed:", timeElapsed.toString(), "seconds")
    console.log("  Remaining:", remaining.toString(), "seconds")
    console.log("")
    
    if (remaining <= 0) {
      console.log("✓ Ready to finalize!")
    } else {
      console.log("⏳ Need to mine blocks to advance time...")
      console.log("   Remaining:", remaining.toString(), "seconds")
      console.log("   Blocks needed: ~", Math.ceil(remaining / 15))
      console.log("")
      console.log("Mining blocks (this may take a while)...")
      
      const [deployer] = await ethers.getSigners()
      const batchSize = 100
      let totalMined = 0
      const maxBlocks = Math.ceil(remaining / 15) + 100
      
      while (remaining > 0 && totalMined < maxBlocks) {
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
        const checkBlock = await ethers.provider.getBlock("latest")
        const checkTimestamp = (checkBlock.timestamp as any).toNumber ? (checkBlock.timestamp as any).toNumber() : Number(checkBlock.timestamp)
        const newElapsed = checkTimestamp - changeInitiated.toNumber()
        const newRemaining = currentDelay.toNumber() - newElapsed
        
        if (totalMined % 500 === 0 || newRemaining <= 0) {
          console.log(`  Mined ${totalMined} blocks. Remaining: ${newRemaining.toString()} seconds`)
        }
        
        if (newRemaining <= 0) {
          console.log("  ✓ Enough time has passed!")
          break
        }
      }
      
      // Final check
      const finalBlock = await ethers.provider.getBlock("latest")
      const finalTimestamp = (finalBlock.timestamp as any).toNumber ? (finalBlock.timestamp as any).toNumber() : Number(finalBlock.timestamp)
      const finalElapsed = finalTimestamp - changeInitiated.toNumber()
      const finalRemaining = currentDelay.toNumber() - finalElapsed
      
      if (finalRemaining > 0) {
        console.log("\n⚠️  Still need", finalRemaining.toString(), "seconds")
        console.log("   Run this script again to continue mining")
        process.exit(0)
      }
    }
    
    // Finalize
    console.log("\n✓ Finalizing governance delay update...")
    const finalizeTx = await wrGovConnected.finalizeGovernanceDelayUpdate()
    await finalizeTx.wait()
    console.log("✓ Finalized! Transaction:", finalizeTx.hash)
    
    // Verify
    const newDelay = await wrGov.governanceDelay()
    console.log("\nNew governanceDelay:", newDelay.toString(), "seconds")
    console.log("✅ SUCCESS! Future updates will be much faster!")
    
  } else {
    // Begin update
    console.log("Beginning governance delay update to 60 seconds...")
    const beginTx = await wrGovConnected.beginGovernanceDelayUpdate(targetDelay)
    await beginTx.wait()
    console.log("✓ Update initiated! Transaction:", beginTx.hash)
    console.log("")
    console.log("Now run this script again to mine blocks and finalize:")
    console.log("  npx hardhat run scripts/reduce-governance-delay-complete.ts --network development")
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

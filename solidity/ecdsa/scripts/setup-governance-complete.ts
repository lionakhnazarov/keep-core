import { HardhatRuntimeEnvironment } from "hardhat/types"

/**
 * Complete governance setup script for DKG-ready local development
 * 
 * This script:
 * 1. Deploys SimpleWalletOwner
 * 2. Sets walletOwner (via initializeWalletOwner - no delay)
 * 3. Reduces governanceDelay to 60 seconds (automatically mines blocks to advance time)
 * 4. Sets resultChallengePeriodLength to 100 blocks
 * 
 * Run after contract deployment:
 *   npx hardhat run scripts/setup-governance-complete.ts --network development
 * 
 * Note: The script will automatically mine blocks to reduce governance delays.
 * This may take a few minutes if the current delay is very long (e.g., 7 days).
 */
async function main() {
  const hre: HardhatRuntimeEnvironment = require("hardhat")
  const { ethers, helpers } = hre
  
  console.log("=== Complete Governance Setup for DKG ===")
  console.log("")
  
  // Get contracts
  let wr, wrGov
  try {
    wr = await helpers.contracts.getContract("WalletRegistry")
    wrGov = await helpers.contracts.getContract("WalletRegistryGovernance")
    console.log("✓ Contracts accessible!")
    console.log("WalletRegistry:", wr.address)
    console.log("WalletRegistryGovernance:", wrGov.address)
  } catch (error: any) {
    console.log("\n❌ Could not access contracts")
    console.log("Error:", error.message)
    console.log("\nPlease deploy contracts first:")
    console.log("  yarn deploy --network development --reset")
    process.exit(1)
  }
  
  const [deployer] = await ethers.getSigners()
  const owner = await wrGov.owner()
  const ownerSigner = await ethers.getSigner(owner)
  const wrGovConnected = wrGov.connect(ownerSigner)
  
  console.log("Governance owner:", owner)
  console.log("")
  
  // Step 1: Setup wallet owner
  console.log("=== Step 1: Setting up Wallet Owner ===")
  const currentWalletOwner = await wr.walletOwner()
  const woCode = await ethers.provider.getCode(currentWalletOwner)
  const isContract = woCode.length > 2
  
  if (isContract) {
    console.log("✓ Wallet Owner is already a contract:", currentWalletOwner)
  } else {
    console.log("Current Wallet Owner:", currentWalletOwner)
    console.log("Is Contract:", isContract)
    console.log("")
    
    // Deploy SimpleWalletOwner
    console.log("Deploying SimpleWalletOwner...")
    const SimpleWalletOwner = await ethers.getContractFactory("SimpleWalletOwner")
    const simpleWalletOwner = await SimpleWalletOwner.connect(deployer).deploy()
    await simpleWalletOwner.deployed()
    console.log("✓ Deployed to:", simpleWalletOwner.address)
    
    // Initialize wallet owner (no delay if zero address)
    if (currentWalletOwner === ethers.constants.AddressZero) {
      console.log("Initializing wallet owner (no delay)...")
      const initTx = await wrGovConnected.initializeWalletOwner(simpleWalletOwner.address)
      await initTx.wait()
      console.log("✓ Initialized! Transaction:", initTx.hash)
    } else {
      console.log("Updating wallet owner...")
      const beginTx = await wrGovConnected.beginWalletOwnerUpdate(simpleWalletOwner.address)
      await beginTx.wait()
      console.log("✓ Update initiated. Transaction:", beginTx.hash)
      console.log("⚠️  Note: This requires governance delay. Run this script again to finalize.")
    }
  }
  console.log("")
  
  // Step 2: Reduce governance delay
  console.log("=== Step 2: Reducing Governance Delay ===")
  const currentDelay = await wrGov.governanceDelay()
  const targetDelay = ethers.BigNumber.from("60")
  
  console.log("Current delay:", currentDelay.toString(), "seconds")
  console.log("Target delay:", targetDelay.toString(), "seconds")
  console.log("")
  
  if (currentDelay.eq(targetDelay)) {
    console.log("✓ Governance delay is already", targetDelay.toString(), "seconds")
  } else {
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
        const finalizeTx = await wrGovConnected.finalizeGovernanceDelayUpdate()
        await finalizeTx.wait()
        console.log("✓ Finalized! Transaction:", finalizeTx.hash)
      } else {
        console.log("⏳ Mining blocks to advance time...")
        console.log("   Remaining:", remaining.toString(), "seconds")
        console.log("   Blocks needed: ~", Math.ceil(remaining / 15))
        console.log("")
        console.log("Mining blocks (this may take a while)...")
        
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
        
        if (finalRemaining <= 0) {
          console.log("\n✓ Finalizing governance delay update...")
          const finalizeTx = await wrGovConnected.finalizeGovernanceDelayUpdate()
          await finalizeTx.wait()
          console.log("✓ Finalized! Transaction:", finalizeTx.hash)
          
          // Verify
          const newDelay = await wrGov.governanceDelay()
          console.log("New governanceDelay:", newDelay.toString(), "seconds")
          console.log("✅ Governance delay reduced!")
        } else {
          console.log("\n⚠️  Still need", finalRemaining.toString(), "seconds")
          console.log("   Run this script again to continue mining")
        }
      }
    } else {
      console.log("Beginning governance delay update...")
      const beginTx = await wrGovConnected.beginGovernanceDelayUpdate(targetDelay)
      await beginTx.wait()
      console.log("✓ Update initiated! Transaction:", beginTx.hash)
      console.log("")
      console.log("⏳ Mining blocks to advance time...")
      console.log("   This may take a while (~", Math.ceil(currentDelay.toNumber() / 15), "blocks)")
      console.log("")
      
      const batchSize = 100
      let totalMined = 0
      const maxBlocks = Math.ceil(currentDelay.toNumber() / 15) + 100
      const startTime = (await ethers.provider.getBlock("latest")).timestamp
      const startTimestamp = (startTime as any).toNumber ? (startTime as any).toNumber() : Number(startTime)
      
      while (totalMined < maxBlocks) {
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
        const timeElapsed = checkTimestamp - startTimestamp
        
        if (totalMined % 500 === 0 || timeElapsed >= currentDelay.toNumber()) {
          console.log(`  Mined ${totalMined} blocks. Time elapsed: ${timeElapsed.toString()} seconds`)
        }
        
        if (timeElapsed >= currentDelay.toNumber()) {
          console.log("  ✓ Enough time has passed!")
          break
        }
      }
      
      // Finalize
      const finalBlock = await ethers.provider.getBlock("latest")
      const finalTimestamp = (finalBlock.timestamp as any).toNumber ? (finalBlock.timestamp as any).toNumber() : Number(finalBlock.timestamp)
      const finalElapsed = finalTimestamp - startTimestamp
      
      if (finalElapsed >= currentDelay.toNumber()) {
        console.log("\n✓ Finalizing governance delay update...")
        const finalizeTx = await wrGovConnected.finalizeGovernanceDelayUpdate()
        await finalizeTx.wait()
        console.log("✓ Finalized! Transaction:", finalizeTx.hash)
        
        // Verify
        const newDelay = await wrGov.governanceDelay()
        console.log("New governanceDelay:", newDelay.toString(), "seconds")
        console.log("✅ Governance delay reduced!")
      } else {
        console.log("\n⚠️  Still need", (currentDelay.toNumber() - finalElapsed).toString(), "more seconds")
        console.log("   Run this script again to continue mining")
      }
    }
  }
  console.log("")
  
  // Step 3: Set resultChallengePeriodLength
  console.log("=== Step 3: Setting resultChallengePeriodLength ===")
  const params = await wr.dkgParameters()
  const currentChallengePeriod = params.resultChallengePeriodLength
  const targetChallengePeriod = ethers.BigNumber.from("100") // 100 blocks
  
  console.log("Current resultChallengePeriodLength:", currentChallengePeriod.toString(), "blocks")
  console.log("Target resultChallengePeriodLength:", targetChallengePeriod.toString(), "blocks")
  console.log("")
  
  if (currentChallengePeriod.eq(targetChallengePeriod)) {
    console.log("✓ resultChallengePeriodLength is already", targetChallengePeriod.toString(), "blocks")
  } else {
    // Check if governance delay is low enough
    const currentDelayCheck = await wrGov.governanceDelay()
    if (currentDelayCheck.gt(3600)) {
      console.log("⚠️  Governance delay is still too high (", currentDelayCheck.toString(), "seconds)")
      console.log("   Please reduce governance delay first, then run this script again.")
      console.log("")
      return
    }
    
    const changeInitiated = await wrGov.dkgResultChallengePeriodLengthChangeInitiated()
    const pendingNewValue = await wrGov.newDkgResultChallengePeriodLength()
    
    if (changeInitiated.gt(0)) {
      console.log("⚠️  Pending update exists:")
      console.log("  Pending value:", pendingNewValue.toString(), "blocks")
      
      const governanceDelay = await wrGov.governanceDelay()
      const block = await ethers.provider.getBlock("latest")
      const blockTimestamp = (block.timestamp as any).toNumber ? (block.timestamp as any).toNumber() : Number(block.timestamp)
      const timeElapsed = blockTimestamp - changeInitiated.toNumber()
      const remaining = governanceDelay.toNumber() - timeElapsed
      
      console.log("  Time elapsed:", timeElapsed.toString(), "seconds")
      console.log("  Remaining:", remaining.toString(), "seconds")
      console.log("")
      
      if (remaining <= 0) {
        console.log("✓ Ready to finalize!")
        const finalizeTx = await wrGovConnected.finalizeDkgResultChallengePeriodLengthUpdate()
        await finalizeTx.wait()
        console.log("✓ Finalized! Transaction:", finalizeTx.hash)
      } else {
        console.log("⏳ Need to wait", remaining.toString(), "more seconds")
        console.log("   Run this script again after the delay passes")
      }
    } else {
      console.log("Beginning resultChallengePeriodLength update...")
      const beginTx = await wrGovConnected.beginDkgResultChallengePeriodLengthUpdate(targetChallengePeriod)
      await beginTx.wait()
      console.log("✓ Update initiated! Transaction:", beginTx.hash)
      console.log("")
      console.log("⚠️  This requires waiting for governance delay (", currentDelayCheck.toString(), "seconds)")
      console.log("   Run this script again after the delay passes")
    }
  }
  console.log("")
  
  // Final verification
  console.log("=== Final Verification ===")
  const finalWalletOwner = await wr.walletOwner()
  const finalWOCode = await ethers.provider.getCode(finalWalletOwner)
  const finalDelay = await wrGov.governanceDelay()
  const finalParams = await wr.dkgParameters()
  
  console.log("Wallet Owner:", finalWalletOwner)
  console.log("  Is Contract:", finalWOCode.length > 2)
  console.log("Governance Delay:", finalDelay.toString(), "seconds")
  console.log("resultChallengePeriodLength:", finalParams.resultChallengePeriodLength.toString(), "blocks")
  console.log("")
  
  if (finalWOCode.length > 2 && finalDelay.lte(60) && finalParams.resultChallengePeriodLength.eq(100)) {
    console.log("✅ SUCCESS! All governance parameters are configured for DKG!")
  } else {
    console.log("⚠️  Some parameters still need configuration:")
    if (finalWOCode.length <= 2) console.log("  - Wallet Owner is not a contract")
    if (finalDelay.gt(60)) console.log("  - Governance delay is still high (", finalDelay.toString(), "seconds)")
    if (!finalParams.resultChallengePeriodLength.eq(100)) console.log("  - resultChallengePeriodLength is not 100 blocks")
    console.log("")
    console.log("Run this script again to complete the setup.")
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

import { HardhatRuntimeEnvironment } from "hardhat/types"

async function main() {
  const hre: HardhatRuntimeEnvironment = require("hardhat")
  const { ethers, helpers } = hre
  
  console.log("=== Deploying SimpleWalletOwner ===")
  
  // Get signers
  const [deployer] = await ethers.getSigners()
  console.log("Deployer:", deployer.address)
  
  // Deploy SimpleWalletOwner
  const SimpleWalletOwner = await ethers.getContractFactory("SimpleWalletOwner")
  const simpleWalletOwner = await SimpleWalletOwner.connect(deployer).deploy()
  await simpleWalletOwner.deployed()
  
  console.log("SimpleWalletOwner deployed to:", simpleWalletOwner.address)
  
  // Verify it's a contract
  const code = await ethers.provider.getCode(simpleWalletOwner.address)
  if (code.length <= 2) {
    throw new Error("Deployed address is not a contract!")
  }
  console.log("✓ Verified: Contract has code")
  
  // Get governance contract
  const wrGov = await helpers.contracts.getContract("WalletRegistryGovernance")
  const wr = await helpers.contracts.getContract("WalletRegistry")
  
  // Get the actual governance owner
  const governanceOwner = await wrGov.owner()
  console.log("\nGovernance Owner:", governanceOwner)
  
  // Get the governance signer
  const governanceSigner = await ethers.getSigner(governanceOwner)
  const wrGovConnected = wrGov.connect(governanceSigner)
  
  console.log("\n=== Checking Current State ===")
  const currentWalletOwner = await wr.walletOwner()
  console.log("Current Wallet Owner:", currentWalletOwner)
  
  const pendingNewOwner = await wrGov.newWalletOwner()
  const changeInitiated = await wrGov.walletOwnerChangeInitiated()
  const governanceDelay = await wrGov.governanceDelay()
  
  console.log("Pending New Owner:", pendingNewOwner)
  console.log("Change Initiated:", changeInitiated.toString())
  console.log("Governance Delay:", governanceDelay.toString(), "seconds")
  
  // Get current block timestamp
  const currentBlock = await ethers.provider.getBlock("latest")
  const currentTimestamp = currentBlock.timestamp
  const timeElapsed = currentTimestamp - changeInitiated.toNumber()
  const delayPassed = timeElapsed >= governanceDelay.toNumber()
  
  console.log("\nCurrent Timestamp:", currentTimestamp.toString())
  console.log("Time Elapsed:", timeElapsed.toString(), "seconds")
  console.log("Delay Passed:", delayPassed)
  
  // If there's a pending update and delay has passed, finalize it first
  if (pendingNewOwner !== ethers.constants.AddressZero && delayPassed) {
    console.log("\n⚠️  There's a pending update that can be finalized")
    console.log("   Finalizing it first...")
    const finalizeTx = await wrGovConnected.finalizeWalletOwnerUpdate()
    await finalizeTx.wait()
    console.log("✓ Finalized pending update")
  }
  
  // Begin new wallet owner update
  console.log("\n=== Beginning Wallet Owner Update ===")
  const beginTx = await wrGovConnected.beginWalletOwnerUpdate(simpleWalletOwner.address)
  await beginTx.wait()
  console.log("✓ Update initiated. Transaction:", beginTx.hash)
  
  // Check if we can advance time
  console.log("\n=== Checking Governance Delay ===")
  const newChangeInitiated = await wrGov.walletOwnerChangeInitiated()
  
  // Try to advance time if possible (for local networks)
  try {
    const blocksToMine = Math.ceil(governanceDelay.toNumber() / 12) // Assuming 12s per block
    console.log(`Attempting to advance time by mining ${blocksToMine} blocks...`)
    
    // Try evm_setNextBlockTimestamp first (more reliable)
    const targetTimestamp = newChangeInitiated.toNumber() + governanceDelay.toNumber() + 1
    try {
      await ethers.provider.send("evm_setNextBlockTimestamp", [targetTimestamp])
      await ethers.provider.send("evm_mine", [])
      console.log("✓ Time advanced using evm_setNextBlockTimestamp")
    } catch (e) {
      // Fallback to evm_increaseTime
      try {
        await ethers.provider.send("evm_increaseTime", [governanceDelay.toNumber() + 1])
        await ethers.provider.send("evm_mine", [])
        console.log("✓ Time advanced using evm_increaseTime")
      } catch (e2) {
        console.log("⚠️  Cannot advance time automatically (not a local Hardhat network)")
        console.log("   You'll need to wait for the governance delay or manually advance time")
      }
    }
  } catch (e) {
    console.log("⚠️  Cannot advance time automatically")
  }
  
  // Verify delay has passed
  const newBlock = await ethers.provider.getBlock("latest")
  const newTimestamp = newBlock.timestamp
  const newTimeElapsed = newTimestamp - newChangeInitiated.toNumber()
  const newDelayPassed = newTimeElapsed >= governanceDelay.toNumber()
  
  console.log("\nNew Timestamp:", newTimestamp.toString())
  console.log("New Time Elapsed:", newTimeElapsed.toString(), "seconds")
  console.log("Delay Passed:", newDelayPassed)
  
  if (!newDelayPassed) {
    console.log("\n⚠️  Governance delay has not passed yet!")
    console.log(`   Need to wait ${(governanceDelay.toNumber() - newTimeElapsed).toString()} more seconds`)
    console.log("   Or manually advance time and run finalizeWalletOwnerUpdate")
    console.log("\nTo finalize later, run:")
    console.log(`   npx hardhat console --network development`)
    console.log(`   const wrGov = await helpers.contracts.getContract("WalletRegistryGovernance")`)
    console.log(`   const owner = await wrGov.owner()`)
    console.log(`   const signer = await ethers.getSigner(owner)`)
    console.log(`   await wrGov.connect(signer).finalizeWalletOwnerUpdate()`)
    return
  }
  
  // Finalize the update
  console.log("\n=== Finalizing Wallet Owner Update ===")
  const finalizeTx = await wrGovConnected.finalizeWalletOwnerUpdate()
  await finalizeTx.wait()
  console.log("✓ Wallet Owner updated! Transaction:", finalizeTx.hash)
  
  // Verify the update
  const newWalletOwner = await wr.walletOwner()
  console.log("\n=== Verification ===")
  console.log("New Wallet Owner:", newWalletOwner)
  console.log("Matches deployed contract:", newWalletOwner.toLowerCase() === simpleWalletOwner.address.toLowerCase())
  
  const newCode = await ethers.provider.getCode(newWalletOwner)
  console.log("Is Contract:", newCode.length > 2)
  
  if (newCode.length <= 2) {
    throw new Error("New wallet owner is not a contract!")
  }
  
  console.log("\n✅ Success! Wallet Owner is now a contract.")
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

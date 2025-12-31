import { HardhatRuntimeEnvironment } from "hardhat/types"

async function main() {
  const hre: HardhatRuntimeEnvironment = require("hardhat")
  const { ethers, helpers } = hre
  
  console.log("=== Advancing Time and Finalizing Wallet Owner Update ===")
  
  const wrGov = await helpers.contracts.getContract("WalletRegistryGovernance")
  const changeInitiated = await wrGov.walletOwnerChangeInitiated()
  const governanceDelay = await wrGov.governanceDelay()
  const currentBlock = await ethers.provider.getBlock("latest")
  
  const targetTimestamp = changeInitiated.toNumber() + governanceDelay.toNumber() + 1
  const timeNeeded = targetTimestamp - currentBlock.timestamp
  
  console.log("Current Timestamp:", currentBlock.timestamp.toString())
  console.log("Target Timestamp:", targetTimestamp.toString())
  console.log("Time Needed:", timeNeeded.toString(), "seconds")
  
  // Try to advance time using geth's RPC
  // Method 1: Try debug_setHead to rewind, then mine forward
  // Method 2: Try to use miner_setExtraData or similar
  // Method 3: Directly call geth's RPC to manipulate time
  
  console.log("\n=== Attempting to Advance Time ===")
  
  try {
    // For geth, we can try to use debug_setHead to rewind to before the change
    // Then mine blocks with future timestamps
    
    // Actually, a simpler approach: use a Python script or direct RPC calls
    // to mine blocks with adjusted timestamps
    
    // Let's try using curl to call geth's RPC directly
    const blocksToMine = Math.ceil(timeNeeded / 12) // Assuming 12s per block
    console.log(`Need to mine approximately ${blocksToMine} blocks`)
    
    // Try to use geth's miner.start() and then mine blocks
    // For development, we can use a workaround:
    // 1. Use debug_setHead to go back
    // 2. Mine blocks with future timestamps
    
    console.log("\n⚠️  Direct time manipulation not available via Hardhat")
    console.log("   Trying alternative approach...")
    
    // Alternative: Use a Python script to call geth RPC directly
    // Or modify the geth node's time
    
    // For now, let's try to finalize if enough time has passed
    // (in case time was advanced externally)
    const owner = await wrGov.owner()
    const signer = await ethers.getSigner(owner)
    const wrGovConnected = wrGov.connect(signer)
    
    const newBlock = await ethers.provider.getBlock("latest")
    const newTimeElapsed = newBlock.timestamp - changeInitiated.toNumber()
    const delayPassed = newTimeElapsed >= governanceDelay.toNumber()
    
    console.log("\n=== Checking if Delay Has Passed ===")
    console.log("New Timestamp:", newBlock.timestamp.toString())
    console.log("Time Elapsed:", newTimeElapsed.toString(), "seconds")
    console.log("Delay Passed:", delayPassed)
    
    if (delayPassed) {
      console.log("\n✓ Delay has passed! Finalizing update...")
      const finalizeTx = await wrGovConnected.finalizeWalletOwnerUpdate()
      await finalizeTx.wait()
      console.log("✓ Wallet Owner updated! Transaction:", finalizeTx.hash)
      
      // Verify
      const wr = await helpers.contracts.getContract("WalletRegistry")
      const newWalletOwner = await wr.walletOwner()
      console.log("\nNew Wallet Owner:", newWalletOwner)
      
      const code = await ethers.provider.getCode(newWalletOwner)
      console.log("Is Contract:", code.length > 2)
      
      if (code.length > 2) {
        console.log("✅ Success! Wallet Owner is now a contract.")
      }
    } else {
      console.log("\n⚠️  Delay has not passed yet")
      console.log(`   Need to wait ${(governanceDelay.toNumber() - newTimeElapsed).toString()} more seconds`)
      console.log("\nTo advance time on geth node, you can:")
      console.log("1. Use geth's debug_setHead to rewind, then mine forward")
      console.log("2. Modify the node's system time (if running in Docker)")
      console.log("3. Use a script to mine blocks with future timestamps")
    }
    
  } catch (error: any) {
    console.error("Error:", error.message)
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

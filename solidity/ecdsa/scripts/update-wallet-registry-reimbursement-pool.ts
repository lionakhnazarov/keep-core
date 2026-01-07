import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * Update WalletRegistry to use the new ReimbursementPool
 */
async function main() {
  const { getNamedAccounts, deployments } = hre
  const { deployer } = await getNamedAccounts()
  const deployerSigner = await ethers.getSigner(deployer)

  console.log("==========================================")
  console.log("Updating WalletRegistry ReimbursementPool")
  console.log("==========================================")
  console.log(`Deployer: ${deployer}`)
  console.log("")

  // Get contracts
  const WalletRegistry = await deployments.get("WalletRegistry")
  const ReimbursementPool = await deployments.get("ReimbursementPool")
  
  const walletRegistry = await ethers.getContractAt("WalletRegistry", WalletRegistry.address)

  console.log(`WalletRegistry: ${WalletRegistry.address}`)
  console.log(`New ReimbursementPool: ${ReimbursementPool.address}`)
  console.log("")

  // Check current ReimbursementPool
  const currentPool = await walletRegistry.reimbursementPool()
  console.log(`Current ReimbursementPool: ${currentPool}`)
  
  if (currentPool.toLowerCase() === ReimbursementPool.address.toLowerCase()) {
    console.log("✓ WalletRegistry already uses the correct ReimbursementPool")
    return
  }

  console.log("")
  console.log("Attempting to update ReimbursementPool...")
  
  // Get governance address
  const governanceAddress = await walletRegistry.governance()
  console.log(`WalletRegistry governance: ${governanceAddress}`)
  
  // Try to get WalletRegistryGovernance
  const WalletRegistryGovernance = await deployments.getOrNull("WalletRegistryGovernance")
  
  if (WalletRegistryGovernance && WalletRegistryGovernance.address.toLowerCase() === governanceAddress.toLowerCase()) {
    console.log("✓ Found WalletRegistryGovernance")
    
    const governance = await ethers.getContractAt(
      "WalletRegistryGovernance",
      WalletRegistryGovernance.address
    )
    
    // Check if deployer owns governance
    const governanceOwner = await governance.owner()
    console.log(`WalletRegistryGovernance owner: ${governanceOwner}`)
    
    if (governanceOwner.toLowerCase() === deployer.toLowerCase()) {
      console.log("✓ Deployer owns WalletRegistryGovernance")
      console.log("   Starting reimbursement pool update...")
      
      // Begin update
      const beginTx = await governance.beginReimbursementPoolUpdate(ReimbursementPool.address)
      await beginTx.wait()
      console.log(`✓ Started update process`)
      console.log(`   Transaction: ${beginTx.hash}`)
      
      // Check the delay
      const delay = await governance.governanceDelay()
      console.log(`   Governance delay: ${delay.toString()} seconds`)
      
      if (delay.eq(0)) {
        // No delay, finalize immediately
        console.log("   Finalizing immediately (no delay)...")
        const finalizeTx = await governance.finalizeReimbursementPoolUpdate()
        await finalizeTx.wait()
        console.log(`✓ Finalized update`)
        console.log(`   Transaction: ${finalizeTx.hash}`)
      } else {
        console.log("")
        console.log("⚠️  Governance delay is required")
        console.log(`   Wait ${delay.toString()} seconds, then run:`)
        console.log(`   cast send ${governance.address} "finalizeReimbursementPoolUpdate()" --rpc-url http://localhost:8545`)
        console.log("")
        console.log("Or use this script again after the delay.")
        return
      }
    } else {
      console.log("⚠️  Deployer does not own WalletRegistryGovernance")
      console.log("   Cannot update ReimbursementPool")
      console.log("   Owner is:", governanceOwner)
      return
    }
  } else {
    console.log("⚠️  WalletRegistryGovernance not found or doesn't match")
    console.log("   Cannot update ReimbursementPool through governance")
    console.log("   You may need to update it directly if you have governance access")
    return
  }

  // Verify update
  console.log("")
  console.log("Verifying update...")
  const newPool = await walletRegistry.reimbursementPool()
  console.log(`New ReimbursementPool: ${newPool}`)
  
  if (newPool.toLowerCase() === ReimbursementPool.address.toLowerCase()) {
    console.log("✓ Update successful!")
    console.log("")
    console.log("The DKG approval should now work correctly.")
  } else {
    console.log("⚠️  Update not yet complete")
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

import { ethers } from "hardhat"
import hre from "hardhat"

async function main() {
  console.log("==========================================")
  console.log("Update Wallet Owner to Bridge Stub")
  console.log("==========================================")
  console.log("")

  const WalletRegistry = await hre.deployments.get("WalletRegistry")
  const wr = await ethers.getContractAt(
    [
      "function walletOwner() view returns (address)",
    ],
    WalletRegistry.address
  )

  const currentWalletOwner = await wr.walletOwner()
  console.log(`Current walletOwner: ${currentWalletOwner}`)

  // Get Bridge stub address
  const path = require("path")
  const bridgePath = path.resolve(__dirname, "../../tbtc-stub/deployments/development/Bridge.json")
  const fs = require("fs")
  let bridgeAddress: string
  
  if (fs.existsSync(bridgePath)) {
    const bridgeData = JSON.parse(fs.readFileSync(bridgePath, "utf8"))
    bridgeAddress = bridgeData.address
    console.log(`Bridge stub address: ${bridgeAddress}`)
  } else {
    console.error("❌ Bridge stub deployment not found!")
    console.error(`   Expected at: ${bridgePath}`)
    process.exit(1)
  }

  if (currentWalletOwner.toLowerCase() === bridgeAddress.toLowerCase()) {
    console.log("")
    console.log("✓ walletOwner is already set to Bridge stub address")
    process.exit(0)
  }

  console.log("")
  console.log("⚠️  walletOwner mismatch detected!")
  console.log(`   Current: ${currentWalletOwner}`)
  console.log(`   Expected: ${bridgeAddress}`)
  console.log("")

  // Check if walletOwner is uninitialized (address(0))
  if (currentWalletOwner === ethers.constants.AddressZero) {
    console.log("WalletOwner is uninitialized. Using initializeWalletOwner()...")
    
    const WalletRegistryGovernance = await hre.deployments.get("WalletRegistryGovernance")
    const wrGov = await ethers.getContractAt(
      [
        "function owner() view returns (address)",
        "function initializeWalletOwner(address) external",
      ],
      WalletRegistryGovernance.address
    )

    const [signer] = await ethers.getSigners()
    const governanceOwner = await wrGov.owner()
    
    if (governanceOwner.toLowerCase() !== signer.address.toLowerCase()) {
      console.error("❌ Signer is not the governance owner!")
      console.error(`   Governance owner: ${governanceOwner}`)
      console.error(`   Signer: ${signer.address}`)
      console.error("")
      console.error("   To fix manually, run:")
      console.error(`   cast send ${WalletRegistryGovernance.address} "initializeWalletOwner(address)" ${bridgeAddress} --rpc-url http://localhost:8545 --unlocked --from ${governanceOwner}`)
      process.exit(1)
    }

    console.log("✓ Signer is the governance owner")
    console.log("Initializing walletOwner...")

    const tx = await wrGov.initializeWalletOwner(bridgeAddress)
    console.log(`Transaction hash: ${tx.hash}`)
    console.log("Waiting for confirmation...")
    await tx.wait()

    console.log("")
    console.log("✓ walletOwner initialized successfully!")
    
    const newWalletOwner = await wr.walletOwner()
    console.log(`New walletOwner: ${newWalletOwner}`)
    process.exit(0)
  }

  // WalletOwner is already set, need to use two-step process
  console.log("WalletOwner is already set. Using two-step update process...")
  
  const WalletRegistryGovernance = await hre.deployments.get("WalletRegistryGovernance")
  const wrGov = await ethers.getContractAt(
    [
      "function owner() view returns (address)",
      "function beginWalletOwnerUpdate(address) external",
      "function finalizeWalletOwnerUpdate() external",
      "function walletOwnerChangeInitiated() view returns (uint256)",
      "function governanceDelay() view returns (uint256)",
    ],
    WalletRegistryGovernance.address
  )

  const [signer] = await ethers.getSigners()
  const governanceOwner = await wrGov.owner()
  
  if (governanceOwner.toLowerCase() !== signer.address.toLowerCase()) {
    console.error("❌ Signer is not the governance owner!")
    console.error(`   Governance owner: ${governanceOwner}`)
    console.error(`   Signer: ${signer.address}`)
    console.error("")
    console.error("   To fix manually, run:")
    console.error(`   # Step 1: Begin update`)
    console.error(`   cast send ${WalletRegistryGovernance.address} "beginWalletOwnerUpdate(address)" ${bridgeAddress} --rpc-url http://localhost:8545 --unlocked --from ${governanceOwner}`)
    console.error(`   # Step 2: Wait for governance delay (check with:)`)
    console.error(`   cast call ${WalletRegistryGovernance.address} "walletOwnerChangeInitiated()" --rpc-url http://localhost:8545`)
    console.error(`   # Step 3: Finalize update`)
    console.error(`   cast send ${WalletRegistryGovernance.address} "finalizeWalletOwnerUpdate()" --rpc-url http://localhost:8545 --unlocked --from ${governanceOwner}`)
    process.exit(1)
  }

  console.log("✓ Signer is the governance owner")
  
  // Check if update is already in progress
  const changeInitiated = await wrGov.walletOwnerChangeInitiated()
  const governanceDelay = await wrGov.governanceDelay()
  
  if (changeInitiated.gt(0)) {
    console.log("")
    console.log("⚠️  WalletOwner update already in progress!")
    console.log(`   Change initiated at: ${changeInitiated.toString()}`)
    console.log(`   Governance delay: ${governanceDelay.toString()} seconds`)
    
    const currentTime = Math.floor(Date.now() / 1000)
    const elapsed = currentTime - changeInitiated.toNumber()
    const remaining = governanceDelay.toNumber() - elapsed
    
    if (remaining > 0) {
      console.log(`   Time elapsed: ${elapsed} seconds`)
      console.log(`   Time remaining: ${remaining} seconds`)
      console.log("")
      console.log("   Waiting for governance delay to pass...")
      console.log("   Then run:")
      console.log(`   cast send ${WalletRegistryGovernance.address} "finalizeWalletOwnerUpdate()" --rpc-url http://localhost:8545 --unlocked --from ${governanceOwner}`)
    } else {
      console.log(`   Time elapsed: ${elapsed} seconds`)
      console.log("   ✓ Governance delay has passed!")
      console.log("")
      console.log("Finalizing walletOwner update...")
      
      const tx = await wrGov.finalizeWalletOwnerUpdate()
      console.log(`Transaction hash: ${tx.hash}`)
      console.log("Waiting for confirmation...")
      await tx.wait()

      console.log("")
      console.log("✓ walletOwner updated successfully!")
      
      const newWalletOwner = await wr.walletOwner()
      console.log(`New walletOwner: ${newWalletOwner}`)
    }
  } else {
    console.log("")
    console.log("Starting walletOwner update process...")
    console.log(`Governance delay: ${governanceDelay.toString()} seconds`)
    
    const tx = await wrGov.beginWalletOwnerUpdate(bridgeAddress)
    console.log(`Transaction hash: ${tx.hash}`)
    console.log("Waiting for confirmation...")
    await tx.wait()

    console.log("")
    console.log("✓ Update process started!")
    console.log(`   Wait ${governanceDelay.toString()} seconds, then run:`)
    console.log(`   cast send ${WalletRegistryGovernance.address} "finalizeWalletOwnerUpdate()" --rpc-url http://localhost:8545 --unlocked --from ${governanceOwner}`)
    console.log("")
    console.log("   Or run this script again to finalize automatically.")
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

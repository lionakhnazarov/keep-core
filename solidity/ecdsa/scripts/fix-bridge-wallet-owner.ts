import { ethers } from "hardhat"
import hre from "hardhat"

async function main() {
  console.log("==========================================")
  console.log("Fix Bridge Wallet Owner")
  console.log("==========================================")
  console.log("")

  const WalletRegistry = await hre.deployments.get("WalletRegistry")
  const wr = await ethers.getContractAt(
    [
      "function walletOwner() view returns (address)",
      "function setWalletOwner(address) external",
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

  // Check if we can update it
  const [signer] = await ethers.getSigners()
  console.log(`Using signer: ${signer.address}`)

  // Check if signer is the owner/governance
  try {
    const WalletRegistryGovernance = await hre.deployments.get("WalletRegistryGovernance")
    const wrGov = await ethers.getContractAt(
      [
        "function owner() view returns (address)",
        "function setWalletOwner(address) external",
      ],
      WalletRegistryGovernance.address
    )

    const governanceOwner = await wrGov.owner()
    console.log(`Governance owner: ${governanceOwner}`)

    if (governanceOwner.toLowerCase() !== signer.address.toLowerCase()) {
      console.log("")
      console.log("⚠️  Signer is not the governance owner!")
      console.log(`   Governance owner: ${governanceOwner}`)
      console.log(`   Signer: ${signer.address}`)
      console.log("")
      console.log("   To fix manually, run:")
      console.log(`   cast send ${WalletRegistryGovernance.address} "setWalletOwner(address)" ${bridgeAddress} --rpc-url http://localhost:8545 --unlocked --from ${governanceOwner}`)
      process.exit(1)
    }

    console.log("✓ Signer is the governance owner")
    console.log("")
    console.log("Updating walletOwner...")

    const tx = await wrGov.setWalletOwner(bridgeAddress)
    console.log(`Transaction hash: ${tx.hash}`)
    console.log("Waiting for confirmation...")
    await tx.wait()

    console.log("")
    console.log("✓ walletOwner updated successfully!")
    
    const newWalletOwner = await wr.walletOwner()
    console.log(`New walletOwner: ${newWalletOwner}`)

    if (newWalletOwner.toLowerCase() === bridgeAddress.toLowerCase()) {
      console.log("✓ Verification successful!")
    } else {
      console.log("⚠️  Verification failed - walletOwner doesn't match!")
    }
  } catch (error: any) {
    console.error("❌ Error updating walletOwner:")
    console.error(error.message)
    process.exit(1)
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

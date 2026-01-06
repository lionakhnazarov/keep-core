import { ethers } from "hardhat"
import hre from "hardhat"

async function main() {
  console.log("==========================================")
  console.log("Finalize Wallet Owner Update")
  console.log("==========================================")
  console.log("")

  const WalletRegistryGovernance = await hre.deployments.get("WalletRegistryGovernance")
  const wrGov = await ethers.getContractAt(
    "WalletRegistryGovernance",
    WalletRegistryGovernance.address
  )

  // Check if update is pending
  const changeInitiated = await wrGov.walletOwnerChangeInitiated()
  if (changeInitiated.toNumber() === 0) {
    console.log("No pending wallet owner update")
    return
  }

  const governanceDelay = await wrGov.governanceDelay()
  const block = await ethers.provider.getBlock("latest")
  const timeElapsed = block.timestamp - changeInitiated.toNumber()

  console.log(`Governance delay: ${governanceDelay.toString()} seconds`)
  console.log(`Time elapsed: ${timeElapsed.toString()} seconds`)
  console.log("")

  if (timeElapsed < governanceDelay.toNumber()) {
    const waitTime = governanceDelay.toNumber() - timeElapsed
    console.error(`✗ Delay not yet passed. Need to wait ${waitTime} more seconds`)
    console.log("")
    console.log("To advance time:")
    console.log("  ./scripts/advance-geth-time.sh")
    console.log("")
    process.exit(1)
  }

  const { deployer } = await hre.getNamedAccounts()
  const deployerSigner = await ethers.getSigner(deployer)
  const owner = await wrGov.owner()

  if (owner.toLowerCase() !== deployer.toLowerCase()) {
    console.error(`✗ Governance owner (${owner}) != deployer (${deployer})`)
    console.error("Run manually with correct account")
    process.exit(1)
  }

  console.log("Finalizing wallet owner update...")
  const tx = await wrGov.connect(deployerSigner).finalizeWalletOwnerUpdate()
  console.log(`Transaction: ${tx.hash}`)
  await tx.wait()
  console.log("✓ Wallet owner update finalized!")
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})


import { HardhatRuntimeEnvironment } from "hardhat/types"

async function main() {
  const hre: HardhatRuntimeEnvironment = require("hardhat")
  const { ethers, helpers } = hre
  
  console.log("=== Transferring Governance ===")
  console.log("")
  
  const wr = await helpers.contracts.getContract("WalletRegistry")
  const wrGov = await helpers.contracts.getContract("WalletRegistryGovernance")
  const { deployer, governance } = await helpers.signers.getNamedSigners()
  
  const currentGov = await wr.governance()
  console.log("Current WalletRegistry governance:", currentGov)
  console.log("Target WalletRegistryGovernance:", wrGov.address)
  console.log("")
  
  if (currentGov.toLowerCase() === wrGov.address.toLowerCase()) {
    console.log("✓ Governance is already transferred!")
    return
  }
  
  console.log("Transferring governance...")
  try {
    const tx = await wr.connect(deployer).transferGovernance(wrGov.address)
    await tx.wait()
    console.log("✓ Governance transferred! Transaction:", tx.hash)
  } catch (error: any) {
    if (error.message?.includes("not the governance")) {
      console.log("Deployer is not governance, trying with governance account...")
      const tx = await wr.connect(governance).transferGovernance(wrGov.address)
      await tx.wait()
      console.log("✓ Governance transferred! Transaction:", tx.hash)
    } else {
      throw error
    }
  }
  
  // Verify
  const newGov = await wr.governance()
  console.log("")
  console.log("New governance:", newGov)
  if (newGov.toLowerCase() === wrGov.address.toLowerCase()) {
    console.log("✅ SUCCESS! Governance transferred!")
  } else {
    console.log("⚠️  Governance transfer may have failed")
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

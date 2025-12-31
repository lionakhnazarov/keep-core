import { ethers } from "hardhat"
import hre from "hardhat"

async function main() {
  const { getNamedAccounts, deployments } = hre
  const { deployer, governance } = await getNamedAccounts()
  
  // Get Bridge address from tbtc-stub deployments
  const fs = require("fs")
  const path = require("path")
  const bridgePath = path.resolve(__dirname, "../../tbtc-stub/deployments/development/Bridge.json")
  const bridgeData = JSON.parse(fs.readFileSync(bridgePath, "utf8"))
  const bridgeAddress = bridgeData.address
  
  const WalletRegistryGovernance = await deployments.get("WalletRegistryGovernance")
  const WalletRegistry = await deployments.get("WalletRegistry")
  
  const wrGov = await ethers.getContractAt(
    "WalletRegistryGovernance",
    WalletRegistryGovernance.address
  )
  const wr = await ethers.getContractAt(
    ["function walletOwner() view returns (address)"],
    WalletRegistry.address
  )
  
  const currentOwner = await wr.walletOwner()
  console.log(`WalletRegistry: ${WalletRegistry.address}`)
  console.log(`Current walletOwner: ${currentOwner}`)
  console.log(`Bridge address: ${bridgeAddress}`)
  console.log(`Using governance account: ${governance}`)
  
  if (currentOwner.toLowerCase() === bridgeAddress.toLowerCase()) {
    console.log("✓ WalletOwner already set correctly")
    return
  }
  
  // Use governance account (which owns WalletRegistryGovernance)
  const governanceSigner = await ethers.getSigner(governance)
  const wrGovWithSigner = wrGov.connect(governanceSigner)
  
  if (currentOwner === "0x0000000000000000000000000000000000000000") {
    console.log("Initializing walletOwner (no delay)...")
    const tx = await wrGovWithSigner.initializeWalletOwner(bridgeAddress)
    console.log(`Transaction submitted: ${tx.hash}`)
    await tx.wait()
    console.log(`✓ WalletOwner initialized!`)
  } else {
    console.log("Updating walletOwner (requires governance delay)...")
    const beginTx = await wrGovWithSigner.beginWalletOwnerUpdate(bridgeAddress)
    await beginTx.wait()
    console.log("Waiting 60 seconds for governance delay...")
    await new Promise(resolve => setTimeout(resolve, 61000))
    const finalizeTx = await wrGovWithSigner.finalizeWalletOwnerUpdate()
    await finalizeTx.wait()
    console.log(`✓ WalletOwner updated!`)
  }
  
  // Verify
  const newOwner = await wr.walletOwner()
  console.log(`New walletOwner: ${newOwner}`)
}

main().catch(console.error)

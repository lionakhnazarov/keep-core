import { ethers } from "hardhat"
import hre from "hardhat"

async function main() {
  const { getNamedAccounts, deployments } = hre
  const { deployer, governance } = await getNamedAccounts()
  
  // Get Bridge address from deployments
  // IMPORTANT: Prefer Bridge stub (has callback) over Bridge v2 (may not have callback)
  const fs = require("fs")
  const path = require("path")
  const bridgePathStub = path.resolve(__dirname, "../../tbtc-stub/deployments/development/Bridge.json")
  const bridgePathV2 = path.resolve(__dirname, "../../../tmp/tbtc-v2/solidity/deployments/development/Bridge.json")
  
  let bridgeAddress: string
  let bridgePath: string
  
  // Prefer Bridge stub first (has callback function)
  if (fs.existsSync(bridgePathStub)) {
    bridgePath = bridgePathStub
    const bridgeData = JSON.parse(fs.readFileSync(bridgePath, "utf8"))
    bridgeAddress = bridgeData.address
    console.log("Using Bridge stub (has callback function):", bridgeAddress)
  } else if (fs.existsSync(bridgePathV2)) {
    bridgePath = bridgePathV2
    const bridgeData = JSON.parse(fs.readFileSync(bridgePath, "utf8"))
    bridgeAddress = bridgeData.address
    console.log("Using Bridge v2 (may not have callback):", bridgeAddress)
    console.warn("⚠️  Bridge v2 may not have callback function - DKG approvals may fail")
  } else {
    console.error("Error: Bridge deployment not found at:")
    console.error("  -", bridgePathStub)
    console.error("  -", bridgePathV2)
    console.error("Please deploy Bridge first or provide Bridge address manually")
    process.exit(1)
  }
  
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

import { ethers } from "hardhat"
import hre from "hardhat"

async function main() {
  const { getNamedAccounts, deployments } = hre
  const { deployer, governance } = await getNamedAccounts()
  
  const WalletRegistry = await deployments.get("WalletRegistry")
  const RandomBeacon = await deployments.get("RandomBeacon")
  
  console.log("==========================================")
  console.log("Authorizing WalletRegistry in RandomBeacon")
  console.log("==========================================")
  console.log(`WalletRegistry: ${WalletRegistry.address}`)
  console.log(`RandomBeacon: ${RandomBeacon.address}`)
  console.log("")
  
  // Check if already authorized
  const rb = await ethers.getContractAt(
    ["function authorizedRequesters(address) view returns (bool)"],
    RandomBeacon.address
  )
  const isAuthorized = await rb.authorizedRequesters(WalletRegistry.address)
  
  if (isAuthorized) {
    console.log("✓ WalletRegistry is already authorized in RandomBeacon")
    return
  }
  
  console.log("WalletRegistry is not authorized. Authorizing...")
  
  // Try to get RandomBeaconGovernance
  let RandomBeaconGovernance = await deployments.getOrNull("RandomBeaconGovernance")
  if (!RandomBeaconGovernance) {
    const fs = require("fs")
    const path = require("path")
    const governancePath = path.resolve(__dirname, "../../random-beacon/deployments/development/RandomBeaconGovernance.json")
    if (fs.existsSync(governancePath)) {
      const governanceData = JSON.parse(fs.readFileSync(governancePath, "utf8"))
      await deployments.save("RandomBeaconGovernance", {
        address: governanceData.address,
        abi: governanceData.abi,
      })
      RandomBeaconGovernance = await deployments.get("RandomBeaconGovernance")
    }
  }
  
  // Try using RandomBeaconGovernance if available
  if (RandomBeaconGovernance) {
    console.log(`Using RandomBeaconGovernance: ${RandomBeaconGovernance.address}`)
    const rbGov = await ethers.getContractAt(
      "RandomBeaconGovernance",
      RandomBeaconGovernance.address
    )
    
    // Check owner
    const owner = await rbGov.owner()
    console.log(`RandomBeaconGovernance owner: ${owner}`)
    console.log(`Using account: ${governance}`)
    
    const governanceSigner = await ethers.getSigner(governance)
    const rbGovWithSigner = rbGov.connect(governanceSigner)
    
    try {
      const tx = await rbGovWithSigner.setRequesterAuthorization(WalletRegistry.address, true)
      console.log(`Transaction submitted: ${tx.hash}`)
      await tx.wait()
      console.log("✓ WalletRegistry authorized via RandomBeaconGovernance!")
    } catch (error: any) {
      if (error.message?.includes("not the owner") || error.message?.includes("caller is not the owner")) {
        console.log("Governance account is not owner, trying deployer...")
        const deployerSigner = await ethers.getSigner(deployer)
        const rbGovWithDeployer = rbGov.connect(deployerSigner)
        const tx = await rbGovWithDeployer.setRequesterAuthorization(WalletRegistry.address, true)
        await tx.wait()
        console.log("✓ WalletRegistry authorized via deployer!")
      } else {
        throw error
      }
    }
  } else {
    // Try direct RandomBeacon call (if it's Ownable)
    console.log("RandomBeaconGovernance not found, trying direct RandomBeacon...")
    const rbContract = await ethers.getContractAt(
      ["function setRequesterAuthorization(address, bool) external", "function owner() view returns (address)"],
      RandomBeacon.address
    )
    
    const owner = await rbContract.owner()
    console.log(`RandomBeacon owner: ${owner}`)
    
    const ownerSigner = await ethers.getSigner(owner)
    const rbWithOwner = await ethers.getContractAt(
      "RandomBeacon",
      RandomBeacon.address,
      ownerSigner
    )
    
    const tx = await rbWithOwner.setRequesterAuthorization(WalletRegistry.address, true)
    await tx.wait()
    console.log("✓ WalletRegistry authorized directly!")
  }
  
  // Verify
  const nowAuthorized = await rb.authorizedRequesters(WalletRegistry.address)
  console.log("")
  console.log(`Authorization status: ${nowAuthorized ? "✓ Authorized" : "✗ Not authorized"}`)
}

main().catch(console.error)

import { ethers } from "hardhat"
import hre from "hardhat"

async function main() {
  const fs = require("fs")
  const path = require("path")
  
  // Get RandomBeaconChaosnet address
  const chaosnetPath = path.resolve(__dirname, "../../random-beacon/deployments/development/RandomBeaconChaosnet.json")
  const chaosnetData = JSON.parse(fs.readFileSync(chaosnetPath, "utf8"))
  const chaosnetAddress = chaosnetData.address
  
  // Get WalletRegistry address
  const WalletRegistry = await hre.deployments.get("WalletRegistry")
  const walletRegistryAddress = WalletRegistry.address
  
  console.log("==========================================")
  console.log("Authorizing WalletRegistry in RandomBeaconChaosnet")
  console.log("==========================================")
  console.log(`WalletRegistry: ${walletRegistryAddress}`)
  console.log(`RandomBeaconChaosnet: ${chaosnetAddress}`)
  console.log("")
  
  // Check if already authorized
  const rb = await ethers.getContractAt(
    ["function authorizedRequesters(address) view returns (bool)"],
    chaosnetAddress
  )
  const isAuthorized = await rb.authorizedRequesters(walletRegistryAddress)
  
  if (isAuthorized) {
    console.log("✓ WalletRegistry is already authorized in RandomBeaconChaosnet")
    return
  }
  
  console.log("WalletRegistry is not authorized. Authorizing...")
  
  // Get the owner
  const rbOwner = await ethers.getContractAt(
    ["function owner() view returns (address)"],
    chaosnetAddress
  )
  const owner = await rbOwner.owner()
  console.log(`RandomBeaconChaosnet owner: ${owner}`)
  
  // Get RandomBeaconGovernance if available
  const governancePath = path.resolve(__dirname, "../../random-beacon/deployments/development/RandomBeaconGovernance.json")
  let governanceAddress: string | null = null
  if (fs.existsSync(governancePath)) {
    const governanceData = JSON.parse(fs.readFileSync(governancePath, "utf8"))
    governanceAddress = governanceData.address
    console.log(`RandomBeaconGovernance: ${governanceAddress}`)
  }
  
  // Try using RandomBeaconGovernance first
  if (governanceAddress) {
    try {
      const rbGov = await ethers.getContractAt(
        "RandomBeaconGovernance",
        governanceAddress
      )
      
      const govOwner = await rbGov.owner()
      console.log(`RandomBeaconGovernance owner: ${govOwner}`)
      
      // Try with deployer account (first signer)
      const [deployer] = await ethers.getSigners()
      console.log(`Using account: ${deployer.address}`)
      
      const rbGovWithSigner = rbGov.connect(deployer)
      const tx = await rbGovWithSigner.setRequesterAuthorization(walletRegistryAddress, true)
      console.log(`Transaction submitted: ${tx.hash}`)
      await tx.wait()
      console.log("✓ WalletRegistry authorized via RandomBeaconGovernance!")
      
      // Verify
      const nowAuthorized = await rb.authorizedRequesters(walletRegistryAddress)
      console.log(`Authorization status: ${nowAuthorized ? "✓ Authorized" : "✗ Not authorized"}`)
      return
    } catch (error: any) {
      console.log(`Failed via governance: ${error.message}`)
      console.log("Trying direct authorization...")
    }
  }
  
  // Try direct authorization (if RandomBeaconChaosnet has setRequesterAuthorization)
  try {
    const rbContract = await ethers.getContractAt(
      ["function setRequesterAuthorization(address, bool) external"],
      chaosnetAddress
    )
    
    // Find the owner account in Hardhat's signers
    const accounts = await ethers.getSigners()
    let ownerSigner: any = null
    
    for (const account of accounts) {
      if (account.address.toLowerCase() === owner.toLowerCase()) {
        ownerSigner = account
        console.log(`Found owner account in Hardhat signers: ${account.address}`)
        break
      }
    }
    
    if (!ownerSigner) {
      // If not found, try to get it by address (might work if it's unlocked in Geth)
      console.log("Owner not in Hardhat signers, trying to get signer by address...")
      try {
        ownerSigner = await ethers.getSigner(owner)
      } catch (e) {
        throw new Error(`Could not get signer for owner ${owner}. Make sure the account is available.`)
      }
    }
    
    const rbWithSigner = rbContract.connect(ownerSigner)
    
    const tx = await rbWithSigner.setRequesterAuthorization(walletRegistryAddress, true, { gasLimit: 100000 })
    console.log(`Transaction submitted: ${tx.hash}`)
    await tx.wait()
    console.log("✓ WalletRegistry authorized directly!")
    
    // Verify
    const nowAuthorized = await rb.authorizedRequesters(walletRegistryAddress)
    console.log(`Authorization status: ${nowAuthorized ? "✓ Authorized" : "✗ Not authorized"}`)
  } catch (error: any) {
    console.error(`Failed to authorize: ${error.message}`)
    throw error
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})


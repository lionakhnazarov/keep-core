import { ethers } from "hardhat"
import hre from "hardhat"

async function main() {
  const { getNamedAccounts, deployments } = hre
  const { deployer, governance } = await getNamedAccounts()

  const WalletRegistry = await deployments.get("WalletRegistry")
  
  // Get RandomBeaconChaosnet address - use the actual deployed address
  // The actual RandomBeaconChaosnet is at 0x53d83C9B3951bB833b669E325dBf462384d511B1
  const RandomBeaconChaosnetAddress = "0x53d83C9B3951bB833b669E325dBf462384d511B1"
  
  // Verify it has code
  const code = await ethers.provider.getCode(RandomBeaconChaosnetAddress)
  if (!code || code === "0x") {
    throw new Error(`RandomBeaconChaosnet at ${RandomBeaconChaosnetAddress} has no code!`)
  }

  console.log("==========================================")
  console.log("Upgrading RandomBeacon to RandomBeaconChaosnet")
  console.log("==========================================")
  console.log(`WalletRegistry: ${WalletRegistry.address}`)
  const currentRandomBeacon = await (await ethers.getContractAt("WalletRegistry", WalletRegistry.address)).randomBeacon()
  console.log(`Current randomBeacon: ${currentRandomBeacon}`)
  console.log(`Target RandomBeaconChaosnet: ${RandomBeaconChaosnetAddress}`)
  console.log("")

  // Get WalletRegistryGovernance
  const WalletRegistryGovernance = await deployments.get("WalletRegistryGovernance")
  console.log(`WalletRegistryGovernance: ${WalletRegistryGovernance.address}`)
  
  // Check governance owner
  const wrGov = await ethers.getContractAt("WalletRegistryGovernance", WalletRegistryGovernance.address)
  const govOwner = await wrGov.owner()
  console.log(`Governance owner: ${govOwner}`)
  console.log("")

  // Find the owner account in Hardhat's signers
  const accounts = await ethers.getSigners()
  let ownerSigner: any = null
  
  for (const account of accounts) {
    if (account.address.toLowerCase() === govOwner.toLowerCase()) {
      ownerSigner = account
      console.log(`Found governance owner account in Hardhat signers: ${account.address}`)
      break
    }
  }
  
  if (!ownerSigner) {
    throw new Error(`Could not find governance owner ${govOwner} in Hardhat signers`)
  }

  // Upgrade via governance
  const wrGovWithSigner = wrGov.connect(ownerSigner)
  console.log("Calling upgradeRandomBeacon via governance...")
  const tx = await wrGovWithSigner.upgradeRandomBeacon(RandomBeaconChaosnetAddress, { gasLimit: 200000 })
  console.log(`Transaction submitted: ${tx.hash}`)
  await tx.wait()
  console.log("✓ RandomBeacon upgraded successfully!")
  
  // Verify
  const newRandomBeacon = await (await ethers.getContractAt("WalletRegistry", WalletRegistry.address)).randomBeacon()
  console.log("")
  console.log(`New randomBeacon address: ${newRandomBeacon}`)
  console.log(`Match: ${newRandomBeacon.toLowerCase() === RandomBeaconChaosnetAddress.toLowerCase() ? "✓ Yes" : "✗ No"}`)
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})


import type { HardhatRuntimeEnvironment } from "hardhat/types"
import type { DeployFunction } from "hardhat-deploy/types"

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { getNamedAccounts, helpers, ethers } = hre
  const { deployer, governance } = await getNamedAccounts()
  const { deployments } = hre

  // Get the RandomBeaconChaosnet deployment
  const RandomBeaconChaosnet = await deployments.getOrNull("RandomBeaconChaosnet")
  
  if (!RandomBeaconChaosnet) {
    console.log("⚠️  RandomBeaconChaosnet not found, skipping ownership transfer")
    return
  }

  // Check if contract actually exists at the address
  const code = await ethers.provider.getCode(RandomBeaconChaosnet.address)
  if (code === "0x" || code.length <= 2) {
    console.log(`⚠️  No contract found at ${RandomBeaconChaosnet.address}, skipping ownership transfer`)
    console.log("   This is normal on a fresh chain where RandomBeaconChaosnet hasn't been deployed yet")
    return
  }

  try {
    await helpers.ownable.transferOwnership(
      "RandomBeaconChaosnet",
      governance,
      deployer
    )
  } catch (error: any) {
    // If the contract doesn't support owner() or transferOwnership(), skip
    if (error.message?.includes("call revert") || error.message?.includes("CALL_EXCEPTION")) {
      console.log(`⚠️  Could not transfer ownership of RandomBeaconChaosnet: ${error.message}`)
      console.log("   Skipping ownership transfer (contract may not exist on this chain)")
      return
    }
    throw error
  }
}

export default func

func.tags = ["RandomBeaconChaosnetTransferOwnership"]
func.dependencies = ["RandomBeaconChaosnet"]

func.skip = async (hre: HardhatRuntimeEnvironment): Promise<boolean> =>
  !hre.network.tags.useRandomBeaconChaosnet

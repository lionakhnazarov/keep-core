import type { HardhatRuntimeEnvironment } from "hardhat/types"
import type { DeployFunction } from "hardhat-deploy/types"

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { getNamedAccounts, deployments, helpers } = hre
  const { deployer, governance } = await getNamedAccounts()

  const RandomBeaconGovernance = await deployments.get("RandomBeaconGovernance")

  await helpers.ownable.transferOwnership(
    "RandomBeaconGovernance",
    governance,
    deployer
  )

  // Check current governance of RandomBeacon
  const randomBeacon = await helpers.contracts.getContract("RandomBeacon")
  const currentGovernance = await randomBeacon.governance()
  const targetGovernance = RandomBeaconGovernance.address

  // If governance is already set to the target, skip
  if (currentGovernance.toLowerCase() === targetGovernance.toLowerCase()) {
    deployments.log(`RandomBeacon governance is already set to ${targetGovernance}. Skipping transfer.`)
    return
  }

  // Try to transfer governance from deployer (if deployer is current governance)
  try {
    await deployments.execute(
      "RandomBeacon",
      { from: deployer, log: true, waitConfirmations: 1 },
      "transferGovernance",
      targetGovernance
    )
  } catch (error: any) {
    const errorMessage = error.message || error.toString() || ""
    // If deployer is not the governance, check if governance is already set correctly
    if (errorMessage.includes("Caller is not the governance") || errorMessage.includes("not the governance")) {
      // Check if governance is already the target
      if (currentGovernance.toLowerCase() === targetGovernance.toLowerCase()) {
        deployments.log(`RandomBeacon governance is already set to ${targetGovernance}. Skipping transfer.`)
        return
      }
      // If governance is set to something else, log a warning
      deployments.log(`⚠️  RandomBeacon governance is ${currentGovernance}, but deployer (${deployer}) is not the governance.`)
      deployments.log(`   Target governance: ${targetGovernance}`)
      deployments.log(`   This step may need to be done manually by the current governance.`)
      // Don't fail the deployment - governance transfer can be done manually
    } else {
      throw error
    }
  }
}

export default func

func.tags = ["RandomBeaconTransferGovernance"]
func.dependencies = ["RandomBeaconGovernance"]

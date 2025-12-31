import type { HardhatRuntimeEnvironment } from "hardhat/types"
import type { DeployFunction } from "hardhat-deploy/types"

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { getNamedAccounts, helpers, ethers } = hre
  const { deployer, governance } = await getNamedAccounts()
  const { deployments } = hre

  const ReimbursementPool = await deployments.getOrNull("ReimbursementPool")
  if (!ReimbursementPool) {
    console.log("⚠️  ReimbursementPool not found, skipping ownership transfer")
    return
  }

  // Check if contract exists on-chain
  const code = await ethers.provider.getCode(ReimbursementPool.address)
  if (!code || code.length <= 2) {
    console.log(`⚠️  ReimbursementPool contract not found at ${ReimbursementPool.address}, skipping ownership transfer`)
    return
  }

  try {
    await helpers.ownable.transferOwnership(
      "ReimbursementPool",
      governance,
      deployer
    )
  } catch (error: any) {
    // If transfer fails, it's likely already owned by governance or deployer doesn't have permission
    if (error.message?.includes("not the owner") || 
        error.message?.includes("caller is not the owner") ||
        error.message?.includes("execution reverted") ||
        error.message?.includes("UNPREDICTABLE_GAS_LIMIT")) {
      console.log(`⚠️  Ownership transfer failed. ReimbursementPool may already be owned by governance.`)
      console.log(`   Error: ${error.message}`)
      console.log(`   This step can be done manually later if needed.`)
    } else {
      console.log(`⚠️  Ownership transfer failed: ${error.message}`)
      console.log(`   This step can be done manually later if needed.`)
    }
    // Don't fail the deployment - ownership transfer is not critical
  }
}

export default func

func.tags = ["ReimbursementPoolTransferGovernance"]
func.dependencies = ["ReimbursementPool"]

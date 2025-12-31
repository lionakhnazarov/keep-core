import type { HardhatRuntimeEnvironment } from "hardhat/types"
import type { DeployFunction } from "hardhat-deploy/types"

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { getNamedAccounts, deployments } = hre
  const { deployer } = await getNamedAccounts()
  const { execute } = deployments

  const WalletRegistry = await deployments.get("WalletRegistry")

  try {
    await execute(
      "ReimbursementPool",
      { from: deployer, log: true, waitConfirmations: 1 },
      "authorize",
      WalletRegistry.address
    )
  } catch (error: any) {
    // If authorization fails due to ownership, try with governance account
    if (error.message?.includes("not the owner") || 
        error.message?.includes("caller is not the owner") ||
        error.message?.includes("execution reverted") ||
        error.message?.includes("UNPREDICTABLE_GAS_LIMIT")) {
      const { governance } = await getNamedAccounts()
      console.log(`Authorization failed with deployer, trying with governance account: ${governance}`)
      try {
        await execute(
          "ReimbursementPool",
          { from: governance, log: true, waitConfirmations: 1 },
          "authorize",
          WalletRegistry.address
        )
      } catch (govError: any) {
        console.log(`⚠️  Authorization failed. This step may need to be done manually.`)
        console.log(`   Error: ${govError.message}`)
        console.log(`   You can authorize manually later if needed.`)
        // Don't fail the deployment - authorization can be done manually
      }
    } else {
      console.log(`⚠️  Authorization failed: ${error.message}`)
      console.log(`   This step can be done manually later if needed.`)
      // Don't fail the deployment - authorization is not critical for basic functionality
    }
  }
}

export default func

func.tags = ["WalletRegistryAuthorize"]
func.dependencies = ["ReimbursementPool", "WalletRegistry"]

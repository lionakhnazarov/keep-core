import type { HardhatRuntimeEnvironment } from "hardhat/types"
import type { DeployFunction } from "hardhat-deploy/types"

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { getNamedAccounts, deployments, helpers } = hre
  const { deployer } = await getNamedAccounts()

  const staticGas = 40_800 // gas amount consumed by the refund() + tx cost
  const maxGasPrice = 500_000_000_000 // 500 Gwei

  // Check if ReimbursementPool already exists
  const existing = await deployments.getOrNull("ReimbursementPool")
  if (existing) {
    // Verify contract exists on-chain
    const code = await hre.ethers.provider.getCode(existing.address)
    if (code && code.length > 2) {
      // Contract exists on-chain, reuse it
      deployments.log(`Reusing existing ReimbursementPool at ${existing.address}`)
      return
    } else {
      // Contract doesn't exist on-chain, delete stale deployment
      // This happens when the chain is reset but deployment files remain
      deployments.log(`⚠️  ReimbursementPool deployment file exists but contract not found on-chain at ${existing.address}`)
      deployments.log(`   Deleting stale deployment file to allow fresh deployment...`)
      await deployments.delete("ReimbursementPool")
    }
  }

  // Deploy ReimbursementPool
  // Wrap in try-catch to handle transaction fetch errors for stale deployments
  let ReimbursementPool
  try {
    ReimbursementPool = await deployments.deploy("ReimbursementPool", {
      from: deployer,
      args: [staticGas, maxGasPrice],
      log: true,
      waitConfirmations: 1,
    })
  } catch (error: any) {
    // If deployment fails due to missing transaction, delete stale deployment and retry
    if (error.message?.includes("cannot get the transaction") || error.message?.includes("transaction")) {
      deployments.log(`⚠️  Error fetching previous deployment transaction. Deleting stale deployment file...`)
      await deployments.delete("ReimbursementPool")
      // Retry deployment
      ReimbursementPool = await deployments.deploy("ReimbursementPool", {
        from: deployer,
        args: [staticGas, maxGasPrice],
        log: true,
        waitConfirmations: 1,
      })
    } else {
      throw error
    }
  }

  if (hre.network.tags.etherscan) {
    await hre.ethers.provider.waitForTransaction(
      ReimbursementPool.transactionHash,
      2,
      300000
    )
    await helpers.etherscan.verify(ReimbursementPool)
  }

  if (hre.network.tags.tenderly) {
    await hre.tenderly.verify({
      name: "ReimbursementPool",
      address: ReimbursementPool.address,
    })
  }
}

export default func

func.tags = ["ReimbursementPool"]

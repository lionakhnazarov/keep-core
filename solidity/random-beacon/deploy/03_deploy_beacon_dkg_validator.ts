import type { HardhatRuntimeEnvironment } from "hardhat/types"
import type { DeployFunction } from "hardhat-deploy/types"

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { getNamedAccounts, deployments, helpers } = hre
  const { deployer } = await getNamedAccounts()

  const BeaconSortitionPool = await deployments.get("BeaconSortitionPool")

  // Check if BeaconDkgValidator already exists
  const existing = await deployments.getOrNull("BeaconDkgValidator")
  if (existing) {
    // Verify contract exists on-chain
    const code = await hre.ethers.provider.getCode(existing.address)
    if (code && code.length > 2) {
      // Contract exists on-chain, reuse it
      deployments.log(`Reusing existing BeaconDkgValidator at ${existing.address}`)
      return
    } else {
      // Contract doesn't exist on-chain, delete stale deployment
      deployments.log(`⚠️  BeaconDkgValidator deployment file exists but contract not found on-chain at ${existing.address}`)
      deployments.log(`   Deleting stale deployment file to allow fresh deployment...`)
      await deployments.delete("BeaconDkgValidator")
    }
  }

  // Deploy BeaconDkgValidator
  // Wrap in try-catch to handle transaction fetch errors for stale deployments
  let BeaconDkgValidator
  try {
    BeaconDkgValidator = await deployments.deploy("BeaconDkgValidator", {
      from: deployer,
      args: [BeaconSortitionPool.address],
      log: true,
      waitConfirmations: 1,
    })
  } catch (error: any) {
    // If deployment fails due to missing transaction, delete stale deployment and retry
    const errorMessage = error.message || error.toString() || ""
    if (
      errorMessage.includes("cannot get the transaction") || 
      errorMessage.includes("transaction") ||
      errorMessage.includes("node synced status")
    ) {
      deployments.log(`⚠️  Error fetching previous deployment transaction: ${errorMessage}`)
      deployments.log(`   Deleting stale deployment file and retrying...`)
      await deployments.delete("BeaconDkgValidator")
      // Retry deployment
      BeaconDkgValidator = await deployments.deploy("BeaconDkgValidator", {
        from: deployer,
        args: [BeaconSortitionPool.address],
        log: true,
        waitConfirmations: 1,
      })
    } else {
      throw error
    }
  }

  if (hre.network.tags.etherscan) {
    await hre.ethers.provider.waitForTransaction(
      BeaconDkgValidator.transactionHash,
      2,
      300000
    )
    await helpers.etherscan.verify(BeaconDkgValidator)
  }

  if (hre.network.tags.tenderly) {
    await hre.tenderly.verify({
      name: "BeaconDkgValidator",
      address: BeaconDkgValidator.address,
    })
  }
}

export default func

func.tags = ["BeaconDkgValidator"]
func.dependencies = ["BeaconSortitionPool"]

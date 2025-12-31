import type { HardhatRuntimeEnvironment } from "hardhat/types"
import type { DeployFunction, DeployOptions } from "hardhat-deploy/types"

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { getNamedAccounts, deployments, helpers } = hre
  const { deployer } = await getNamedAccounts()

  const deployOptions: DeployOptions = {
    from: deployer,
    log: true,
    waitConfirmations: 1,
  }

  // Check if RandomBeaconChaosnet already exists
  const existing = await deployments.getOrNull("RandomBeaconChaosnet")
  if (existing) {
    // Verify contract exists on-chain
    const code = await hre.ethers.provider.getCode(existing.address)
    if (code && code.length > 2) {
      // Contract exists on-chain, reuse it
      deployments.log(`Reusing existing RandomBeaconChaosnet at ${existing.address}`)
      return
    } else {
      // Contract doesn't exist on-chain, delete stale deployment
      deployments.log(`⚠️  RandomBeaconChaosnet deployment file exists but contract not found on-chain at ${existing.address}`)
      deployments.log(`   Deleting stale deployment file to allow fresh deployment...`)
      await deployments.delete("RandomBeaconChaosnet")
    }
  }

  // Deploy RandomBeaconChaosnet
  // Wrap in try-catch to handle transaction fetch errors for stale deployments
  let RandomBeaconChaosnet
  try {
    RandomBeaconChaosnet = await deployments.deploy(
      "RandomBeaconChaosnet",
      {
        ...deployOptions,
      }
    )
  } catch (error: any) {
    // If deployment fails due to missing transaction, delete stale deployment and retry
    const errorMessage = error.message || error.toString() || ""
    if (
      errorMessage.includes("cannot get the transaction") || 
      errorMessage.includes("transaction") ||
      errorMessage.includes("node synced status")
    ) {
      deployments.log(`⚠️  Error fetching previous deployment transaction for RandomBeaconChaosnet: ${errorMessage}`)
      deployments.log(`   Deleting stale deployment file and retrying...`)
      await deployments.delete("RandomBeaconChaosnet")
      // Retry deployment
      RandomBeaconChaosnet = await deployments.deploy(
        "RandomBeaconChaosnet",
        {
          ...deployOptions,
        }
      )
    } else {
      throw error
    }
  }

  if (hre.network.tags.etherscan) {
    await hre.ethers.provider.waitForTransaction(
      RandomBeaconChaosnet.transactionHash,
      2,
      300000
    )
    await helpers.etherscan.verify(RandomBeaconChaosnet)
  }

  if (hre.network.tags.tenderly) {
    await hre.tenderly.verify({
      name: "RandomBeaconChaosnet",
      address: RandomBeaconChaosnet.address,
    })
  }
}

export default func

func.tags = ["RandomBeaconChaosnet"]

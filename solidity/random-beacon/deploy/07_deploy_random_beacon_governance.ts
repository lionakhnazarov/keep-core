import type { HardhatRuntimeEnvironment } from "hardhat/types"
import type { DeployFunction } from "hardhat-deploy/types"

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { getNamedAccounts, deployments, helpers } = hre
  const { deployer } = await getNamedAccounts()

  const RandomBeacon = await deployments.get("RandomBeacon")

  const GOVERNANCE_DELAY = 604_800 // 1 week

  // Check if RandomBeaconGovernance already exists
  const existing = await deployments.getOrNull("RandomBeaconGovernance")
  if (existing) {
    // Verify contract exists on-chain
    const code = await hre.ethers.provider.getCode(existing.address)
    if (code && code.length > 2) {
      // Contract exists on-chain, reuse it
      deployments.log(`Reusing existing RandomBeaconGovernance at ${existing.address}`)
      return
    } else {
      // Contract doesn't exist on-chain, delete stale deployment
      deployments.log(`⚠️  RandomBeaconGovernance deployment file exists but contract not found on-chain at ${existing.address}`)
      deployments.log(`   Deleting stale deployment file to allow fresh deployment...`)
      await deployments.delete("RandomBeaconGovernance")
    }
  }

  // Deploy RandomBeaconGovernance
  // Wrap in try-catch to handle transaction fetch errors for stale deployments
  let RandomBeaconGovernance
  try {
    RandomBeaconGovernance = await deployments.deploy(
      "RandomBeaconGovernance",
      {
        from: deployer,
        args: [RandomBeacon.address, GOVERNANCE_DELAY],
        log: true,
        waitConfirmations: 1,
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
      deployments.log(`⚠️  Error fetching previous deployment transaction for RandomBeaconGovernance: ${errorMessage}`)
      deployments.log(`   Deleting stale deployment file and retrying...`)
      await deployments.delete("RandomBeaconGovernance")
      // Retry deployment
      RandomBeaconGovernance = await deployments.deploy(
        "RandomBeaconGovernance",
        {
          from: deployer,
          args: [RandomBeacon.address, GOVERNANCE_DELAY],
          log: true,
          waitConfirmations: 1,
        }
      )
    } else {
      throw error
    }
  }

  if (hre.network.tags.etherscan) {
    await hre.ethers.provider.waitForTransaction(
      RandomBeaconGovernance.transactionHash,
      2,
      300000
    )
    await helpers.etherscan.verify(RandomBeaconGovernance)
  }

  if (hre.network.tags.tenderly) {
    await hre.tenderly.verify({
      name: "RandomBeaconGovernance",
      address: RandomBeaconGovernance.address,
    })
  }
}

export default func

func.tags = ["RandomBeaconGovernance"]
func.dependencies = ["RandomBeacon"]

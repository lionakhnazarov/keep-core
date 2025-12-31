import type { HardhatRuntimeEnvironment } from "hardhat/types"
import type { DeployFunction } from "hardhat-deploy/types"

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { getNamedAccounts, deployments, helpers } = hre
  const { deployer, chaosnetOwner } = await getNamedAccounts()
  const { execute } = deployments
  const { to1e18 } = helpers.number

  const POOL_WEIGHT_DIVISOR = to1e18(1)

  const T = await deployments.get("T")

  // Check if BeaconSortitionPool already exists
  const existing = await deployments.getOrNull("BeaconSortitionPool")
  if (existing) {
    // Verify contract exists on-chain
    const code = await hre.ethers.provider.getCode(existing.address)
    if (code && code.length > 2) {
      // Contract exists on-chain, reuse it
      deployments.log(`Reusing existing BeaconSortitionPool at ${existing.address}`)
      // Still need to execute transferChaosnetOwnerRole if needed
      try {
        await execute(
          "BeaconSortitionPool",
          { from: deployer, log: true, waitConfirmations: 1 },
          "transferChaosnetOwnerRole",
          chaosnetOwner
        )
      } catch (error: any) {
        if (error.message?.includes("Not the chaosnet owner") || error.message?.includes("not the chaosnet owner")) {
          deployments.log("Chaosnet owner role already transferred or deployer is not chaosnet owner. Skipping transfer.")
        } else {
          throw error
        }
      }
      return
    } else {
      // Contract doesn't exist on-chain, delete stale deployment
      deployments.log(`⚠️  BeaconSortitionPool deployment file exists but contract not found on-chain at ${existing.address}`)
      deployments.log(`   Deleting stale deployment file to allow fresh deployment...`)
      await deployments.delete("BeaconSortitionPool")
    }
  }

  // Deploy BeaconSortitionPool
  // Wrap in try-catch to handle transaction fetch errors for stale deployments
  let BeaconSortitionPool
  try {
    BeaconSortitionPool = await deployments.deploy("BeaconSortitionPool", {
      contract: "SortitionPool",
      from: deployer,
      args: [T.address, POOL_WEIGHT_DIVISOR],
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
      await deployments.delete("BeaconSortitionPool")
      // Retry deployment
      BeaconSortitionPool = await deployments.deploy("BeaconSortitionPool", {
        contract: "SortitionPool",
        from: deployer,
        args: [T.address, POOL_WEIGHT_DIVISOR],
        log: true,
        waitConfirmations: 1,
      })
    } else {
      throw error
    }
  }

  await execute(
    "BeaconSortitionPool",
    { from: deployer, log: true, waitConfirmations: 1 },
    "transferChaosnetOwnerRole",
    chaosnetOwner
  )

  if (hre.network.tags.etherscan) {
    await hre.ethers.provider.waitForTransaction(
      BeaconSortitionPool.transactionHash,
      2,
      300000
    )
    await helpers.etherscan.verify(BeaconSortitionPool)
  }

  if (hre.network.tags.tenderly) {
    await hre.tenderly.verify({
      name: "BeaconSortitionPool",
      address: BeaconSortitionPool.address,
    })
  }
}

export default func

func.tags = ["BeaconSortitionPool"]
// TokenStaking and T deployments are expected to be resolved from
// @threshold-network/solidity-contracts
func.dependencies = ["TokenStaking", "T"]

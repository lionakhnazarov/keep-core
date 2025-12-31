import type { HardhatRuntimeEnvironment } from "hardhat/types"
import type { DeployFunction, DeployOptions } from "hardhat-deploy/types"

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { getNamedAccounts, deployments, helpers } = hre
  const { deployer } = await getNamedAccounts()

  const T = await deployments.get("T")
  
  // For development, use ExtendedTokenStaking which has stake() function
  let TokenStaking
  if (hre.network.name === "development") {
    try {
      // Try to get ExtendedTokenStaking from ecdsa deployments
      const fs = require("fs")
      const path = require("path")
      const projectRoot = path.resolve(__dirname, "../../../")
      const ecdsaDeployPath = path.join(
        projectRoot,
        "solidity/ecdsa/deployments/development/ExtendedTokenStaking.json"
      )
      
      if (fs.existsSync(ecdsaDeployPath)) {
        const ExtendedTokenStakingData = JSON.parse(fs.readFileSync(ecdsaDeployPath, "utf8"))
        // Save ExtendedTokenStaking as TokenStaking for this deployment
        await deployments.save("TokenStaking", {
          address: ExtendedTokenStakingData.address,
          abi: ExtendedTokenStakingData.abi,
        })
        TokenStaking = await deployments.get("TokenStaking")
        deployments.log(`Using ExtendedTokenStaking at ${ExtendedTokenStakingData.address} for RandomBeacon deployment`)
      } else {
        // Fallback to regular TokenStaking
        TokenStaking = await deployments.get("TokenStaking")
      }
    } catch (e: any) {
      // Fallback to regular TokenStaking
      TokenStaking = await deployments.get("TokenStaking")
      deployments.log(`Using regular TokenStaking (ExtendedTokenStaking not found: ${e.message})`)
    }
  } else {
    TokenStaking = await deployments.get("TokenStaking")
  }
  
  const ReimbursementPool = await deployments.get("ReimbursementPool")
  const BeaconSortitionPool = await deployments.get("BeaconSortitionPool")
  const BeaconDkgValidator = await deployments.get("BeaconDkgValidator")

  const deployOptions: DeployOptions = {
    from: deployer,
    log: true,
    waitConfirmations: 1,
  }

  // Helper function to deploy with stale file handling
  const deployWithStaleHandling = async (contractName: string, options: DeployOptions) => {
    // Check if contract already exists
    const existing = await deployments.getOrNull(contractName)
    if (existing) {
      // Verify contract exists on-chain
      const code = await hre.ethers.provider.getCode(existing.address)
      if (code && code.length > 2) {
        // Contract exists on-chain, reuse it
        deployments.log(`Reusing existing ${contractName} at ${existing.address}`)
        return existing
      } else {
        // Contract doesn't exist on-chain, delete stale deployment
        deployments.log(`⚠️  ${contractName} deployment file exists but contract not found on-chain at ${existing.address}`)
        deployments.log(`   Deleting stale deployment file to allow fresh deployment...`)
        await deployments.delete(contractName)
      }
    }

    // Deploy contract
    try {
      return await deployments.deploy(contractName, options)
    } catch (error: any) {
      // If deployment fails due to missing transaction, delete stale deployment and retry
      const errorMessage = error.message || error.toString() || ""
      if (
        errorMessage.includes("cannot get the transaction") || 
        errorMessage.includes("transaction") ||
        errorMessage.includes("node synced status")
      ) {
        deployments.log(`⚠️  Error fetching previous deployment transaction for ${contractName}: ${errorMessage}`)
        deployments.log(`   Deleting stale deployment file and retrying...`)
        await deployments.delete(contractName)
        // Retry deployment
        return await deployments.deploy(contractName, options)
      } else {
        throw error
      }
    }
  }

  const BLS = await deployWithStaleHandling("BLS", deployOptions)

  const BeaconAuthorization = await deployWithStaleHandling(
    "BeaconAuthorization",
    deployOptions
  )

  const BeaconDkg = await deployWithStaleHandling("BeaconDkg", deployOptions)

  const BeaconInactivity = await deployWithStaleHandling(
    "BeaconInactivity",
    deployOptions
  )

  // Check if RandomBeacon already exists before deploying
  const existingRandomBeacon = await deployments.getOrNull("RandomBeacon")
  if (existingRandomBeacon) {
    // Verify contract exists on-chain
    const code = await hre.ethers.provider.getCode(existingRandomBeacon.address)
    if (code && code.length > 2) {
      // Check if we're using ExtendedTokenStaking in development
      // If so, we need to redeploy RandomBeacon to use ExtendedTokenStaking
      if (hre.network.name === "development") {
        try {
          const randomBeaconContract = await hre.ethers.getContractAt(
            ["function staking() view returns (address)"],
            existingRandomBeacon.address
          )
          const currentStaking = await randomBeaconContract.staking()
          const expectedStaking = TokenStaking.address.toLowerCase()
          
          if (currentStaking.toLowerCase() !== expectedStaking) {
            deployments.log(`⚠️  RandomBeacon uses TokenStaking at ${currentStaking}, but ExtendedTokenStaking is at ${expectedStaking}`)
            deployments.log(`   For development, RandomBeacon should use ExtendedTokenStaking.`)
            deployments.log(`   To redeploy RandomBeacon, you need to reset the chain or manually delete the contract.`)
            deployments.log(`   For now, reusing existing RandomBeacon. You may need to stake to regular TokenStaking instead.`)
            // Still transfer ownership
            await helpers.ownable.transferOwnership(
              "BeaconSortitionPool",
              existingRandomBeacon.address,
              deployer
            )
            return
          }
        } catch (e) {
          // If we can't check, just reuse
          deployments.log(`Could not verify RandomBeacon staking address, reusing existing deployment`)
        }
      }
      
      // Contract exists on-chain and staking matches (or not development), reuse it
      deployments.log(`Reusing existing RandomBeacon at ${existingRandomBeacon.address}`)
      // Still need to transfer ownership
      await helpers.ownable.transferOwnership(
        "BeaconSortitionPool",
        existingRandomBeacon.address,
        deployer
      )
      return
    } else {
      // Contract doesn't exist on-chain, delete stale deployment
      deployments.log(`⚠️  RandomBeacon deployment file exists but contract not found on-chain at ${existingRandomBeacon.address}`)
      deployments.log(`   Deleting stale deployment file to allow fresh deployment...`)
      await deployments.delete("RandomBeacon")
    }
  }

  // Deploy RandomBeacon with stale file handling
  let RandomBeacon
  try {
    RandomBeacon = await deployments.deploy("RandomBeacon", {
      contract:
        process.env.TEST_USE_STUBS_BEACON === "true"
          ? "RandomBeaconStub"
          : undefined,
      args: [
        BeaconSortitionPool.address,
        T.address,
        TokenStaking.address,
        BeaconDkgValidator.address,
        ReimbursementPool.address,
      ],
      libraries: {
        BLS: BLS.address,
        BeaconAuthorization: BeaconAuthorization.address,
        BeaconDkg: BeaconDkg.address,
        BeaconInactivity: BeaconInactivity.address,
      },
      ...deployOptions,
    })
  } catch (error: any) {
    // If deployment fails due to missing transaction, delete stale deployment and retry
    const errorMessage = error.message || error.toString() || ""
    if (
      errorMessage.includes("cannot get the transaction") || 
      errorMessage.includes("transaction") ||
      errorMessage.includes("node synced status")
    ) {
      deployments.log(`⚠️  Error fetching previous deployment transaction for RandomBeacon: ${errorMessage}`)
      deployments.log(`   Deleting stale deployment file and retrying...`)
      await deployments.delete("RandomBeacon")
      // Retry deployment
      RandomBeacon = await deployments.deploy("RandomBeacon", {
        contract:
          process.env.TEST_USE_STUBS_BEACON === "true"
            ? "RandomBeaconStub"
            : undefined,
        args: [
          BeaconSortitionPool.address,
          T.address,
          TokenStaking.address,
          BeaconDkgValidator.address,
          ReimbursementPool.address,
        ],
        libraries: {
          BLS: BLS.address,
          BeaconAuthorization: BeaconAuthorization.address,
          BeaconDkg: BeaconDkg.address,
          BeaconInactivity: BeaconInactivity.address,
        },
        ...deployOptions,
      })
    } else {
      throw error
    }
  }

  // Transfer ownership (if not already done for existing contract)
  if (!existingRandomBeacon || RandomBeacon.address !== existingRandomBeacon.address) {
    // If we're redeploying, check who currently owns BeaconSortitionPool
    if (existingRandomBeacon && RandomBeacon.address !== existingRandomBeacon.address) {
      try {
        const beaconSortitionPool = await helpers.contracts.getContract("BeaconSortitionPool")
        const currentOwner = await beaconSortitionPool.owner()
        
        if (currentOwner.toLowerCase() === existingRandomBeacon.address.toLowerCase()) {
          // Old RandomBeacon owns it - we can't transfer from a contract, so skip
          // The new RandomBeacon will need to be authorized differently, or we keep using old one
          deployments.log(`⚠️  BeaconSortitionPool is owned by old RandomBeacon (${existingRandomBeacon.address})`)
          deployments.log(`   Cannot transfer ownership from contract. Keeping old RandomBeacon ownership.`)
          deployments.log(`   Note: New RandomBeacon at ${RandomBeacon.address} will not own BeaconSortitionPool.`)
        } else {
          // Someone else owns it - try to transfer from deployer
          await helpers.ownable.transferOwnership(
            "BeaconSortitionPool",
            RandomBeacon.address,
            deployer
          )
        }
      } catch (e: any) {
        deployments.log(`⚠️  Could not transfer BeaconSortitionPool ownership: ${e.message}`)
        deployments.log(`   You may need to manually transfer ownership to ${RandomBeacon.address}`)
      }
    } else {
      // Normal deployment - transfer from deployer
      await helpers.ownable.transferOwnership(
        "BeaconSortitionPool",
        RandomBeacon.address,
        deployer
      )
    }
  }

  if (hre.network.tags.etherscan) {
    await hre.ethers.provider.waitForTransaction(
      RandomBeacon.transactionHash,
      2,
      300000
    )
    await helpers.etherscan.verify(BLS)
    await helpers.etherscan.verify(BeaconAuthorization)
    await helpers.etherscan.verify(BeaconDkg)
    await helpers.etherscan.verify(BeaconInactivity)
    await helpers.etherscan.verify(RandomBeacon)
  }

  if (hre.network.tags.tenderly) {
    await hre.tenderly.verify({
      name: "RandomBeacon",
      address: RandomBeacon.address,
    })
  }
}

export default func

func.tags = ["RandomBeacon"]
func.dependencies = [
  "T",
  "TokenStaking",
  "ReimbursementPool",
  "BeaconSortitionPool",
  "BeaconDkgValidator",
]

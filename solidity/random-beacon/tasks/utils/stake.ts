/* eslint-disable no-console */
import type { BigNumberish, BigNumber } from "ethers"
import type { HardhatRuntimeEnvironment } from "hardhat/types"

export async function stake(
  hre: HardhatRuntimeEnvironment,
  owner: string,
  provider: string,
  amount: BigNumberish,
  beneficiary?: string,
  authorizer?: string
): Promise<void> {
  const { ethers, helpers, deployments } = hre
  const { to1e18, from1e18 } = helpers.number
  const ownerAddress = ethers.utils.getAddress(owner)
  const providerAddress = ethers.utils.getAddress(provider)
  const stakeAmount = to1e18(amount)

  // Beneficiary can equal to the owner if not set otherwise. This simplification
  // is used for development purposes.
  const beneficiaryAddress = beneficiary
    ? ethers.utils.getAddress(beneficiary)
    : ownerAddress

  // Authorizer can equal to the owner if not set otherwise. This simplification
  // is used for development purposes.
  const authorizerAddress = authorizer
    ? ethers.utils.getAddress(authorizer)
    : ownerAddress

  // For development, prefer ExtendedTokenStaking which has stake() function
  let staking
  if (hre.network.name === "development") {
    try {
      // Try to get ExtendedTokenStaking from ecdsa deployments (it's deployed there)
      const fs = require("fs")
      const path = require("path")
      // Path from random-beacon/tasks/utils/stake.ts to solidity/ecdsa/deployments/development/
      // __dirname is random-beacon/tasks/utils/, so go up 4 levels to project root
      // (utils -> tasks -> random-beacon -> solidity -> project root)
      const projectRoot = path.resolve(__dirname, "../../../../")
      const ecdsaDeployPath = path.join(
        projectRoot,
        "solidity/ecdsa/deployments/development/ExtendedTokenStaking.json"
      )
      
      if (fs.existsSync(ecdsaDeployPath)) {
        const ExtendedTokenStakingData = JSON.parse(fs.readFileSync(ecdsaDeployPath, "utf8"))
        // Use the ABI from the deployment file
        staking = (await hre.ethers.getContractAt(
          ExtendedTokenStakingData.abi || [],
          ExtendedTokenStakingData.address
        )) as any
        console.log(`Using ExtendedTokenStaking at ${ExtendedTokenStakingData.address}`)
      } else {
        throw new Error(
          `ExtendedTokenStaking deployment file not found at ${ecdsaDeployPath}. ` +
          `Please deploy ExtendedTokenStaking first by running ECDSA deployment.`
        )
      }
    } catch (e: any) {
      // Fallback to regular TokenStaking
      staking = await helpers.contracts.getContract("TokenStaking")
      console.log(`ExtendedTokenStaking not found (${e.message}), using TokenStaking`)
    }
  } else {
    staking = await helpers.contracts.getContract("TokenStaking")
  }

  const { tStake: currentStake } = await staking.callStatic.stakes(
    providerAddress
  )

  console.log(
    `Current stake for ${providerAddress} is ${from1e18(currentStake)} T`
  )

  if (currentStake.eq(0)) {
    console.log(
      `Staking ${from1e18(
        stakeAmount
      )} T to the staking provider ${providerAddress}...`
    )

    const stakingWithSigner = staking.connect(await ethers.getSigner(ownerAddress))
    
    // Check if stake function exists (ExtendedTokenStaking has it, regular TokenStaking doesn't)
    let hasStakeFunction = false
    try {
      staking.interface.getFunction("stake")
      hasStakeFunction = true
    } catch (e) {
      hasStakeFunction = false
    }
    
    if (hasStakeFunction) {
      try {
        // Call stake function (available in ExtendedTokenStaking)
        await (await stakingWithSigner.stake(
            providerAddress,
            beneficiaryAddress,
            authorizerAddress,
            stakeAmount
        )).wait()
        console.log(`✓ Successfully staked ${from1e18(stakeAmount)} T`)
      } catch (error: any) {
        const errorMessage = error.message || error.toString() || ""
        if (errorMessage.includes("execution reverted") || 
            errorMessage.includes("stake is not a function") || 
            errorMessage.includes("is not a function") ||
            errorMessage.includes("no matching function") ||
            error.code === "INVALID_ARGUMENT") {
          throw new Error(
            `TokenStaking.stake() function call failed. ` +
            `The deployed TokenStaking contract may not be ExtendedTokenStaking. ` +
            `Please ensure ExtendedTokenStaking is deployed for development network. ` +
            `Error: ${errorMessage}`
          )
        } else {
          throw error
        }
      }
    } else {
      throw new Error(
        `TokenStaking contract does not have stake() function. ` +
        `For development, you need to deploy ExtendedTokenStaking which includes this function. ` +
        `The stake() function is not available in the standard TokenStaking contract.`
      )
    }
  } else if (currentStake.lt(stakeAmount)) {
    const topUpAmount = stakeAmount.sub(currentStake)

    console.log(
      `Topping up ${from1e18(
        topUpAmount
      )} T to the staking provider ${providerAddress}...`
    )

    await (
      await staking
        .connect(await ethers.getSigner(ownerAddress))
        .topUp(providerAddress, topUpAmount)
    ).wait()
  }
}

export async function calculateTokensNeededForStake(
  hre: HardhatRuntimeEnvironment,
  provider: string,
  amount: BigNumberish
): Promise<BigNumber> {
  const { ethers, helpers } = hre
  const { to1e18, from1e18 } = helpers.number

  const stakeAmount = to1e18(amount)

  const staking = await helpers.contracts.getContract("TokenStaking")

  const { tStake: currentStake } = await staking.callStatic.stakes(provider)

  if (currentStake.lt(stakeAmount)) {
    return ethers.BigNumber.from(from1e18(stakeAmount.sub(currentStake)))
  }

  return ethers.constants.Zero
}

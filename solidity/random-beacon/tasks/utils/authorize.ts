/* eslint-disable no-console */
import type { BigNumber, BigNumberish } from "ethers"
import type { HardhatRuntimeEnvironment } from "hardhat/types"

// eslint-disable-next-line import/prefer-default-export
export async function authorize(
  hre: HardhatRuntimeEnvironment,
  deploymentName: string, // TODO: Change to IApplication
  owner: string,
  provider: string,
  authorizer?: string,
  authorization?: BigNumberish
): Promise<void> {
  const { ethers, helpers } = hre
  const ownerAddress = ethers.utils.getAddress(owner)
  const providerAddress = ethers.utils.getAddress(provider)

  const application = await helpers.contracts.getContract(deploymentName)

  console.log(
    `Authorizing provider's ${providerAddress} stake in ${deploymentName} application (${application.address})`
  )

  // Authorizer can equal to the owner if not set otherwise. This simplification
  // is used for development purposes.
  const authorizerAddress = authorizer
    ? ethers.utils.getAddress(authorizer)
    : ownerAddress

  const { to1e18, from1e18 } = helpers.number
  
  // For authorization, we MUST use the TokenStaking contract that the application expects
  // because the application will check authorization in that contract
  // Get the staking contract address from the application
  let staking
  try {
    const applicationStakingAddress = await application.staking()
    
    // Use minimal ABI with just the functions we need
    const minimalABI = [
      "function authorizedStake(address,address) view returns (uint96)",
      "function increaseAuthorization(address,address,uint96)",
      "function stake(address,address,address,uint96) payable",
      "function stakeOf(address) view returns (uint96)"
    ]
    
    staking = (await hre.ethers.getContractAt(
      minimalABI,
      applicationStakingAddress
    )) as any
    console.log(`Using TokenStaking at ${applicationStakingAddress} (expected by ${deploymentName})`)
    
    // For development, check if stake exists in this contract
    // If not, and ExtendedTokenStaking exists, we may need to transfer stake
    if (hre.network.name === "development") {
      try {
        const stakeAmount = await staking.stakeOf(providerAddress)
        if (stakeAmount.isZero()) {
          // Check if ExtendedTokenStaking exists and has stake
          const fs = require("fs")
          const path = require("path")
          const projectRoot = path.resolve(__dirname, "../../../../")
          const ecdsaDeployPath = path.join(
            projectRoot,
            "solidity/ecdsa/deployments/development/ExtendedTokenStaking.json"
          )
          
          if (fs.existsSync(ecdsaDeployPath)) {
            const ExtendedTokenStakingData = JSON.parse(fs.readFileSync(ecdsaDeployPath, "utf8"))
            const extendedStaking = (await hre.ethers.getContractAt(
              minimalABI,
              ExtendedTokenStakingData.address
            )) as any
            const extendedStake = await extendedStaking.stakeOf(providerAddress)
            
            if (!extendedStake.isZero()) {
              console.log(`⚠️  Stake exists in ExtendedTokenStaking but RandomBeacon expects regular TokenStaking`)
              console.log(`   Stake amount in ExtendedTokenStaking: ${from1e18(extendedStake)} T`)
              console.log(`   Authorization will fail because stake is not in the expected contract`)
              console.log(`   Consider redeploying RandomBeacon with ExtendedTokenStaking`)
            }
          }
        }
      } catch (e) {
        // Ignore errors checking stake
      }
    }
  } catch (e: any) {
    // Fallback to helpers
    staking = await helpers.contracts.getContract("TokenStaking")
    console.log(`Using TokenStaking from helpers (could not load from application: ${e.message})`)
  }

  const authorizationBN: BigNumber = authorization
    ? to1e18(authorization)
    : await application.minimumAuthorization()

  const currentAuthorization = await staking.authorizedStake(
    providerAddress,
    application.address
  )

  if (currentAuthorization.gte(authorizationBN)) {
    console.log(
      `Authorized stake is already ${from1e18(currentAuthorization)} T`
    )
    return
  }

  const increaseAmount: BigNumber = authorizationBN.sub(currentAuthorization)

  console.log(
    `Increasing authorization by ${from1e18(increaseAmount)} T to ${from1e18(
      authorizationBN
    )} T...`
  )

  await (
    await staking
      .connect(await ethers.getSigner(authorizerAddress))
      .increaseAuthorization(
        providerAddress,
        application.address,
        increaseAmount
      )
  ).wait()
}

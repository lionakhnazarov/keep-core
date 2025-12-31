/* eslint-disable no-console */
import type { BigNumberish, BigNumber } from "ethers"
import type { HardhatRuntimeEnvironment } from "hardhat/types"

// eslint-disable-next-line import/prefer-default-export
export async function mint(
  hre: HardhatRuntimeEnvironment,
  owner: string,
  amount: BigNumberish
): Promise<void> {
  const { ethers, helpers, deployments } = hre
  const { to1e18, from1e18 } = helpers.number
  const ownerAddress = ethers.utils.getAddress(owner)
  const stakeAmount = to1e18(amount)

  // For development, get T token from ExtendedTokenStaking deployment args
  // ExtendedTokenStaking uses a specific T token that may differ from helpers
  let t
  if (hre.network.name === "development") {
    try {
      const fs = require("fs")
      const path = require("path")
      const projectRoot = path.resolve(__dirname, "../../../")
      const ecdsaDeployPath = path.join(
        projectRoot,
        "solidity/ecdsa/deployments/development/ExtendedTokenStaking.json"
      )
      
      if (fs.existsSync(ecdsaDeployPath)) {
        const ExtendedTokenStakingData = JSON.parse(fs.readFileSync(ecdsaDeployPath, "utf8"))
        // ExtendedTokenStaking constructor takes T token as first arg
        const tTokenAddress = ExtendedTokenStakingData.args?.[0]
        if (tTokenAddress) {
          // Get T token ABI from helpers or use minimal ABI
          try {
            const tFromHelpers = await helpers.contracts.getContract("T")
            // Use the address from ExtendedTokenStaking but keep the ABI from helpers
            // Get ABI as JSON array
            const tABI = JSON.parse(JSON.stringify(tFromHelpers.interface.format(ethers.utils.FormatTypes.json)))
            t = (await hre.ethers.getContractAt(tABI, tTokenAddress)) as any
            console.log(`Using T token at ${tTokenAddress} (from ExtendedTokenStaking deployment)`)
          } catch (e: any) {
            // Fallback: use helpers T
            t = await helpers.contracts.getContract("T")
            console.log(`Using T token from helpers (could not load from ExtendedTokenStaking: ${e.message})`)
          }
        } else {
          t = await helpers.contracts.getContract("T")
        }
      } else {
        t = await helpers.contracts.getContract("T")
      }
    } catch (e) {
      // Fallback to helpers
      t = await helpers.contracts.getContract("T")
    }
  } else {
    t = await helpers.contracts.getContract("T")
  }
  
  // For development, prefer ExtendedTokenStaking which has stake() function
  let staking
  let stakingAddress: string
  if (hre.network.name === "development") {
    try {
      // Try to get ExtendedTokenStaking from ecdsa deployments (it's deployed there)
      const fs = require("fs")
      const path = require("path")
      // Path from random-beacon/tasks/utils/mint.ts to project root
      // Go up 4 levels: utils -> tasks -> random-beacon -> solidity -> project root
      const projectRoot = path.resolve(__dirname, "../../../../")
      const ecdsaDeployPath = path.join(
        projectRoot,
        "solidity/ecdsa/deployments/development/ExtendedTokenStaking.json"
      )
      
      if (fs.existsSync(ecdsaDeployPath)) {
        const ExtendedTokenStakingData = JSON.parse(fs.readFileSync(ecdsaDeployPath, "utf8"))
        stakingAddress = ExtendedTokenStakingData.address
        staking = (await hre.ethers.getContractAt(
          ExtendedTokenStakingData.abi || [],
          ExtendedTokenStakingData.address
        )) as any
        console.log(`Using ExtendedTokenStaking at ${ExtendedTokenStakingData.address} for approval`)
      } else {
        throw new Error(
          `ExtendedTokenStaking deployment file not found at ${ecdsaDeployPath}. ` +
          `Please deploy ExtendedTokenStaking first by running ECDSA deployment.`
        )
      }
    } catch (e: any) {
      // Fallback to regular TokenStaking
      staking = await helpers.contracts.getContract("TokenStaking")
      stakingAddress = staking.address
      console.log(`ExtendedTokenStaking not found (${e.message}), using TokenStaking for approval`)
    }
  } else {
    staking = await helpers.contracts.getContract("TokenStaking")
    stakingAddress = staking.address
  }

  const tokenContractOwner = await t.owner()

  const currentBalance: BigNumber = await t.balanceOf(ownerAddress)

  console.log(
    `Account ${ownerAddress} balance is ${from1e18(currentBalance)} T`
  )

  if (currentBalance.lt(stakeAmount)) {
    const mintAmount = stakeAmount.sub(currentBalance)

    console.log(`Minting ${from1e18(mintAmount)} T for ${ownerAddress}...`)

    await (
      await t
        .connect(await ethers.getSigner(tokenContractOwner))
        .mint(ownerAddress, mintAmount)
    ).wait()
  }

  const currentAllowance: BigNumber = await t.allowance(
    ownerAddress,
    stakingAddress
  )

  console.log(
    `Account ${ownerAddress} allowance for ${stakingAddress} is ${from1e18(
      currentAllowance
    )} T`
  )

  // Approve slightly more than needed to account for any rounding or edge cases
  // Use max(uint256) for simplicity in development, or 110% of stake amount
  const approvalAmount = hre.network.name === "development" 
    ? ethers.constants.MaxUint256 
    : stakeAmount.mul(110).div(100) // 110% of stake amount
  
  // Always approve if current allowance is less than or equal to stake amount
  // This ensures we have enough allowance even if it's exactly equal
  if (currentAllowance.lte(stakeAmount)) {
    console.log(
      `Approving ${hre.network.name === "development" ? "MAX" : from1e18(approvalAmount)} T for ${stakingAddress}...`
    )
    await (
      await t
        .connect(await ethers.getSigner(ownerAddress))
        .approve(stakingAddress, approvalAmount)
    ).wait()
    console.log(`✓ Approved ${hre.network.name === "development" ? "MAX" : from1e18(approvalAmount)} T`)
  } else {
    console.log(`✓ Already approved: ${from1e18(currentAllowance)} T`)
  }
}

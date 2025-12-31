import type { HardhatRuntimeEnvironment } from "hardhat/types"
import type { DeployFunction } from "hardhat-deploy/types"

/**
 * Deploy ExtendedTokenStaking for development network
 * This contract has the stake() function needed for development
 */
const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, helpers } = hre
  const { log } = deployments
  const { deployer } = await getNamedAccounts()

  // Only deploy ExtendedTokenStaking for development network
  if (hre.network.name !== "development") {
    log("Skipping ExtendedTokenStaking deployment (not development network)")
    return
  }

  // Check if already deployed
  const existing = await deployments.getOrNull("ExtendedTokenStaking")
  if (existing && helpers.address.isValid(existing.address)) {
    log(`Using existing ExtendedTokenStaking at ${existing.address}`)
    return
  }

  // Get T token
  const T = await deployments.get("T")
  
  // Get T contract instance to check totalSupply
  const t = await helpers.contracts.getContract("T")
  const totalSupply = await t.totalSupply()
  
  // TokenStaking constructor requires totalSupply > 0
  // If T has zero supply, mint some tokens to ensure deployment succeeds
  if (totalSupply.eq(0)) {
    log(`T token has zero totalSupply. Minting tokens to ensure deployment succeeds...`)
    const tokenContractOwner = await t.owner()
    const mintAmount = helpers.number.to1e18(1000000) // Mint 1M tokens
    
    // Mint tokens to the deployer address
    const ownerSigner = await hre.ethers.getSigner(tokenContractOwner)
    const mintTx = await t.connect(ownerSigner).mint(deployer, mintAmount)
    await mintTx.wait()
    
    log(`Minted ${helpers.number.from1e18(mintAmount)} T tokens to ${deployer}`)
  }

  log("Deploying ExtendedTokenStaking for development...")

  // Deploy ExtendedTokenStaking using the contract from node_modules
  // The contract path format: "package/path/to/file.sol:ContractName"
  const ExtendedTokenStaking = await deployments.deploy("ExtendedTokenStaking", {
    contract: "@threshold-network/solidity-contracts/contracts/test/TokenStakingTestSet.sol:ExtendedTokenStaking",
    from: deployer,
    args: [T.address],
    log: true,
    waitConfirmations: 1,
  })

  log(`ExtendedTokenStaking deployed at ${ExtendedTokenStaking.address}`)

  // Also save as TokenStaking for development so other contracts can use it
  await deployments.save("TokenStaking", {
    address: ExtendedTokenStaking.address,
    abi: ExtendedTokenStaking.abi,
  })

  log("Saved ExtendedTokenStaking as TokenStaking for development")
}

export default func

func.tags = ["ExtendedTokenStaking", "TokenStaking"]
func.dependencies = ["T"]
// Run before resolve_token_staking so we deploy ExtendedTokenStaking first
func.runAtTheEnd = false

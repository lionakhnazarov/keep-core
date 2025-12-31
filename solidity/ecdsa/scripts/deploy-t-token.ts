import { HardhatRuntimeEnvironment } from "hardhat/types"

/**
 * Deploy T token contract directly
 * Usage: npx hardhat run scripts/deploy-t-token.ts --network development
 */
async function main() {
  const hre: HardhatRuntimeEnvironment = require("hardhat")
  const { deployments, getNamedAccounts } = hre
  const { deployer } = await getNamedAccounts()
  const { log } = deployments
  
  if (hre.network.name !== "development") {
    console.log("This script only works for development network")
    process.exit(1)
  }
  
  // Check if T already exists on-chain
  const existingT = await deployments.getOrNull("T")
  if (existingT) {
    const code = await hre.ethers.provider.getCode(existingT.address)
    if (code && code.length > 2) {
      log(`T token already deployed at ${existingT.address}`)
      return
    } else {
      log(`Deleting stale T deployment...`)
      await deployments.delete("T")
    }
  }
  
  log("Deploying T token contract...")
  
  // Deploy T token from @threshold-network/solidity-contracts
  const T = await deployments.deploy("T", {
    contract: "@threshold-network/solidity-contracts/contracts/token/T.sol:T",
    from: deployer,
    args: [],
    log: true,
    waitConfirmations: 1,
  })
  
  log(`T token deployed at ${T.address}`)
  
  // Verify it's on-chain
  const code = await hre.ethers.provider.getCode(T.address)
  if (!code || code.length <= 2) {
    throw new Error("T token deployment failed - no code at address")
  }
  
  log("✓ T token deployment verified on-chain")
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

import type { HardhatRuntimeEnvironment } from "hardhat/types"
import type { DeployFunction } from "hardhat-deploy/types"

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, helpers } = hre
  const { log } = deployments

  // For development, prefer ExtendedTokenStaking if it exists
  if (hre.network.name === "development") {
    const ExtendedTokenStaking = await deployments.getOrNull("ExtendedTokenStaking")
    if (ExtendedTokenStaking && helpers.address.isValid(ExtendedTokenStaking.address)) {
      log(`using ExtendedTokenStaking at ${ExtendedTokenStaking.address} for development`)
      // Save as TokenStaking so other contracts can use it
      await deployments.save("TokenStaking", {
        address: ExtendedTokenStaking.address,
        abi: ExtendedTokenStaking.abi,
      })
      return
    }
  }

  const TokenStaking = await deployments.getOrNull("TokenStaking")

  if (TokenStaking && helpers.address.isValid(TokenStaking.address)) {
    log(`using existing TokenStaking at ${TokenStaking.address}`)
  } else {
    // Try to find it from threshold-network/solidity-contracts package
    const fs = require("fs")
    const path = require("path")
    
    // Check node_modules first
    const nodeModulesPath = path.resolve(
      __dirname,
      "../../../node_modules/@threshold-network/solidity-contracts/deployments/development/TokenStaking.json"
    )
    
    // Check tmp directory (from install script)
    const tmpPath = path.resolve(
      __dirname,
      "../../../tmp/solidity-contracts/deployments/development/TokenStaking.json"
    )
    
    let tokenStakingData
    let sourcePath = ""
    
    if (fs.existsSync(nodeModulesPath)) {
      tokenStakingData = JSON.parse(fs.readFileSync(nodeModulesPath, "utf8"))
      sourcePath = "node_modules"
    } else if (fs.existsSync(tmpPath)) {
      tokenStakingData = JSON.parse(fs.readFileSync(tmpPath, "utf8"))
      sourcePath = "tmp/solidity-contracts"
    }
    
    if (!tokenStakingData) {
      // Last resort: check if contract exists at address from config
      // This assumes TokenStaking was deployed manually or via install script
      const configPath = path.resolve(__dirname, "../../../configs/config.toml")
      if (fs.existsSync(configPath)) {
        const configContent = fs.readFileSync(configPath, "utf8")
        const match = configContent.match(/TokenStakingAddress\s*=\s*"([^"]+)"/)
        if (match && match[1]) {
          const configAddress = match[1]
          // Verify contract exists at this address
          const code = await hre.ethers.provider.getCode(configAddress)
          if (code && code.length > 2) {
            log(`using TokenStaking from config.toml at ${configAddress}`)
            // Save it to deployments so other scripts can find it
            await deployments.save("TokenStaking", {
              address: configAddress,
              abi: [], // ABI will be loaded from external contracts
            })
            return
          }
        }
      }
      
      throw new Error(
        "deployed TokenStaking contract not found. " +
        "Please deploy TokenStaking from @threshold-network/solidity-contracts first. " +
        "Run: cd tmp/solidity-contracts && yarn deploy --network development --reset"
      )
    }
    
    // Verify contract exists on-chain
    const code = await hre.ethers.provider.getCode(tokenStakingData.address)
    if (!code || code.length <= 2) {
      log(`⚠️  TokenStaking deployment file found at ${tokenStakingData.address} but contract doesn't exist on-chain`)
      log(`   This usually means Geth was reset. TokenStaking needs to be redeployed.`)
      throw new Error(
        `TokenStaking contract not found on-chain at ${tokenStakingData.address}. ` +
        `Please deploy TokenStaking first: ` +
        `cd tmp/solidity-contracts && yarn deploy --network development`
      )
    }
    
    // Register the deployment
    await deployments.save("TokenStaking", {
      address: tokenStakingData.address,
      abi: tokenStakingData.abi || [],
    })
    log(`using TokenStaking from ${sourcePath} at ${tokenStakingData.address}`)
  }
}

export default func

func.tags = ["TokenStaking"]
func.dependencies = ["ExtendedTokenStaking"]

import type { HardhatRuntimeEnvironment } from "hardhat/types"
import type { DeployFunction } from "hardhat-deploy/types"

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, helpers } = hre
  const { log } = deployments

  const T = await deployments.getOrNull("T")

  if (T && helpers.address.isValid(T.address)) {
    log(`using existing T at ${T.address}`)
  } else {
    // Try to find it from threshold-network/solidity-contracts package
    const fs = require("fs")
    const path = require("path")
    
    // Check node_modules first
    const nodeModulesPath = path.resolve(
      __dirname,
      "../../../node_modules/@threshold-network/solidity-contracts/deployments/development/T.json"
    )
    
    // Check tmp directory (from install script)
    const tmpPath = path.resolve(
      __dirname,
      "../../../tmp/solidity-contracts/deployments/development/T.json"
    )
    
    let tData
    let sourcePath = ""
    
    if (fs.existsSync(nodeModulesPath)) {
      tData = JSON.parse(fs.readFileSync(nodeModulesPath, "utf8"))
      sourcePath = "node_modules"
    } else if (fs.existsSync(tmpPath)) {
      tData = JSON.parse(fs.readFileSync(tmpPath, "utf8"))
      sourcePath = "tmp/solidity-contracts"
    }
    
    if (!tData) {
      throw new Error(
        "deployed T contract not found. " +
        "Please deploy T from @threshold-network/solidity-contracts first. " +
        "Run: cd tmp/solidity-contracts && yarn deploy --network development --reset"
      )
    }
    
    // Verify contract exists on-chain
    const code = await hre.ethers.provider.getCode(tData.address)
    if (!code || code.length <= 2) {
      log(`⚠️  T deployment file found at ${tData.address} but contract doesn't exist on-chain`)
      log(`   This usually means Geth was reset. T needs to be redeployed.`)
      
      // Try to delete stale deployment to allow redeployment
      const existingDeployment = await deployments.getOrNull("T")
      if (existingDeployment && existingDeployment.address === tData.address) {
        log(`   Deleting stale T deployment artifact...`)
        await deployments.delete("T")
      }
      
      // Check if tmp/solidity-contracts exists and suggest deploying from there
      const fs = require("fs")
      const path = require("path")
      const tmpContractsPath = path.resolve(__dirname, "../../../tmp/solidity-contracts")
      
      if (fs.existsSync(tmpContractsPath)) {
        throw new Error(
          `T contract not found on-chain at ${tData.address}. ` +
          `Please deploy T first: ` +
          `cd tmp/solidity-contracts && yarn deploy --network development --reset`
        )
      } else {
        throw new Error(
          `T contract not found on-chain at ${tData.address}. ` +
          `Please run the install script first: ` +
          `./scripts/install.sh` +
          `\nThen deploy T: cd tmp/solidity-contracts && yarn deploy --network development --reset`
        )
      }
    }
    
    // Register the deployment
    await deployments.save("T", {
      address: tData.address,
      abi: tData.abi || [],
    })
    log(`using T from ${sourcePath} at ${tData.address}`)
  }
}

export default func

func.tags = ["T"]

import type { HardhatRuntimeEnvironment } from "hardhat/types"
import type { DeployFunction } from "hardhat-deploy/types"

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { getNamedAccounts, deployments, ethers, helpers, upgrades } = hre
  const { deployer } = await getNamedAccounts()
  const { log } = deployments

  const EcdsaSortitionPool = await deployments.get("EcdsaSortitionPool")
  let TokenStaking = await deployments.get("TokenStaking")
  const ReimbursementPool = await deployments.get("ReimbursementPool")
  
  // Try to get RandomBeacon, or find it from random-beacon package
  let RandomBeacon = await deployments.getOrNull("RandomBeacon")
  if (!RandomBeacon) {
    const fs = require("fs")
    const path = require("path")
    const randomBeaconPath = path.resolve(
      __dirname,
      "../../random-beacon/deployments/development/RandomBeacon.json"
    )
    if (fs.existsSync(randomBeaconPath)) {
      const beaconData = JSON.parse(fs.readFileSync(randomBeaconPath, "utf8"))
      await deployments.save("RandomBeacon", {
        address: beaconData.address,
        abi: beaconData.abi,
      })
      RandomBeacon = await deployments.get("RandomBeacon")
    } else {
      throw new Error("RandomBeacon contract not found")
    }
  }
  
  // Ensure we use the same TokenStaking that RandomBeacon expects
  let randomBeaconStakingAddress: string | null = null
  try {
    const randomBeaconContract = await helpers.contracts.getContract("RandomBeacon")
    randomBeaconStakingAddress = await randomBeaconContract.staking()
  } catch (e) {
    // If we can't get RandomBeacon contract, try loading from file
    const fs = require("fs")
    const path = require("path")
    const randomBeaconPath = path.resolve(
      __dirname,
      "../../random-beacon/deployments/development/RandomBeacon.json"
    )
    if (fs.existsSync(randomBeaconPath)) {
      const beaconData = JSON.parse(fs.readFileSync(randomBeaconPath, "utf8"))
      const randomBeaconContract = await ethers.getContractAt(
        ["function staking() view returns (address)"],
        beaconData.address
      )
      randomBeaconStakingAddress = await randomBeaconContract.staking()
    }
  }
  
  // If RandomBeacon expects a different TokenStaking, use that one
  if (randomBeaconStakingAddress && randomBeaconStakingAddress.toLowerCase() !== TokenStaking.address.toLowerCase()) {
    log(`⚠️  RandomBeacon expects TokenStaking at ${randomBeaconStakingAddress}, but we have ${TokenStaking.address}`)
    log(`   Using TokenStaking that RandomBeacon expects...`)
    // Try to load the TokenStaking that RandomBeacon expects
    const fs = require("fs")
    const path = require("path")
    const tsPath = path.resolve(__dirname, "../../tmp/solidity-contracts/deployments/development/TokenStaking.json")
    if (fs.existsSync(tsPath)) {
      const tsData = JSON.parse(fs.readFileSync(tsPath, "utf8"))
      if (tsData.address.toLowerCase() === randomBeaconStakingAddress.toLowerCase()) {
        await deployments.save("TokenStaking", {
          address: tsData.address,
          abi: tsData.abi || TokenStaking.abi,
        })
        // Re-fetch TokenStaking to get the updated address
        TokenStaking = await deployments.get("TokenStaking")
        log(`✓ Using TokenStaking from tmp/solidity-contracts: ${TokenStaking.address}`)
      } else {
        log(`⚠️  TokenStaking file exists but address doesn't match. Using address directly.`)
        // Use the address directly
        await deployments.save("TokenStaking", {
          address: randomBeaconStakingAddress,
          abi: TokenStaking.abi,
        })
        TokenStaking = await deployments.get("TokenStaking")
      }
    } else {
      log(`⚠️  TokenStaking file not found at ${tsPath}. Using address directly.`)
      // Use the address directly
      await deployments.save("TokenStaking", {
        address: randomBeaconStakingAddress,
        abi: TokenStaking.abi,
      })
      TokenStaking = await deployments.get("TokenStaking")
    }
  }
  
  const EcdsaDkgValidator = await deployments.get("EcdsaDkgValidator")

  const EcdsaInactivity = await deployments.deploy("EcdsaInactivity", {
    from: deployer,
    log: true,
    waitConfirmations: 1,
  })

  // Check if WalletRegistry is already deployed and if it uses the correct TokenStaking
  let existingWalletRegistry = await deployments.getOrNull("WalletRegistry")
  let walletRegistry, proxyDeployment
  if (existingWalletRegistry) {
    walletRegistry = await helpers.contracts.getContract("WalletRegistry")
    const wrStaking = await walletRegistry.staking()
    
    // Get RandomBeacon's staking address to ensure they match
    let randomBeaconStaking: string | null = null
    try {
      const randomBeaconContract = await helpers.contracts.getContract("RandomBeacon")
      randomBeaconStaking = (await randomBeaconContract.staking()).toLowerCase()
    } catch (e) {
      // If we can't get RandomBeacon, try loading from file
      const fs = require("fs")
      const path = require("path")
      const randomBeaconPath = path.resolve(
        __dirname,
        "../../random-beacon/deployments/development/RandomBeacon.json"
      )
      if (fs.existsSync(randomBeaconPath)) {
        const beaconData = JSON.parse(fs.readFileSync(randomBeaconPath, "utf8"))
        const randomBeaconContract = await ethers.getContractAt(
          ["function staking() view returns (address)"],
          beaconData.address
        )
        randomBeaconStaking = (await randomBeaconContract.staking()).toLowerCase()
      }
    }
    
    const expectedStaking = TokenStaking.address.toLowerCase()
    const wrStakingLower = wrStaking.toLowerCase()
    let needsRedeploy = false
    
    // Check if WalletRegistry uses different staking than expected
    if (wrStakingLower !== expectedStaking.toLowerCase()) {
      log(`⚠️  WalletRegistry uses TokenStaking (${wrStaking}) but expected ${expectedStaking}`)
      needsRedeploy = true
    }
    
    // Also check if RandomBeacon expects a different staking address
    if (randomBeaconStaking && wrStakingLower !== randomBeaconStaking) {
      log(`⚠️  WalletRegistry uses TokenStaking (${wrStaking}) but RandomBeacon expects ${randomBeaconStaking}`)
      log(`   This will cause validation errors. Redeploying WalletRegistry to match RandomBeacon...`)
      needsRedeploy = true
    }
    
    if (needsRedeploy && hre.network.name === "development") {
      // Force redeploy by removing the existing deployment
      await deployments.delete("WalletRegistry")
      // Also delete related contracts that depend on it
      await deployments.delete("WalletRegistryGovernance")
      existingWalletRegistry = null // Force new deployment
    } else if (!needsRedeploy) {
      log(`WalletRegistry already deployed at ${existingWalletRegistry.address}, reusing it`)
      // Get proxy deployment info from OpenZeppelin upgrades
      const proxyAdmin = await upgrades.admin.getInstance()
      proxyDeployment = {
        address: walletRegistry.address,
        args: [],
      }
    }
  }
  
  if (!existingWalletRegistry) {
    log(`Deploying WalletRegistry with TokenStaking at ${TokenStaking.address}...`)
    const deploymentResult = await helpers.upgrades.deployProxy(
      "WalletRegistry",
      {
        contractName:
          process.env.TEST_USE_STUBS_ECDSA === "true"
            ? "WalletRegistryStub"
            : undefined,
        initializerArgs: [
          EcdsaDkgValidator.address,
          RandomBeacon.address,
          ReimbursementPool.address,
        ],
        factoryOpts: {
          signer: await ethers.getSigner(deployer),
          libraries: {
            EcdsaInactivity: EcdsaInactivity.address,
          },
        },
        proxyOpts: {
          constructorArgs: [EcdsaSortitionPool.address, TokenStaking.address],
          unsafeAllow: ["external-library-linking"],
          kind: "transparent",
        },
      }
    )
    walletRegistry = deploymentResult[0]
    proxyDeployment = deploymentResult[1]
    log(`✓ Deployed WalletRegistry at ${walletRegistry.address} with TokenStaking at ${TokenStaking.address}`)
  }

  // Transfer ownership of EcdsaSortitionPool to WalletRegistry
  try {
    await helpers.ownable.transferOwnership(
      "EcdsaSortitionPool",
      walletRegistry.address,
      deployer
    )
  } catch (error: any) {
    const errorMessage = error.message || error.toString() || ""
    if (errorMessage.includes("caller is not the owner") || errorMessage.includes("not the owner")) {
      // Check current owner
      const ecdsaSP = await helpers.contracts.getContract("EcdsaSortitionPool")
      const currentOwner = await ecdsaSP.owner()
      if (currentOwner.toLowerCase() === walletRegistry.address.toLowerCase()) {
        log(`EcdsaSortitionPool ownership is already set to WalletRegistry. Skipping transfer.`)
      } else {
        log(`⚠️  Cannot transfer EcdsaSortitionPool ownership: deployer is not the owner`)
        log(`   Current owner: ${currentOwner}`)
        log(`   Target owner: ${walletRegistry.address}`)
        log(`   This step may need to be done manually by the current owner.`)
      }
    } else {
      throw error
    }
  }

  if (hre.network.tags.etherscan) {
    await helpers.etherscan.verify(EcdsaInactivity)

    // We use `verify` instead of `verify:verify` as the `verify` task is defined
    // in "@openzeppelin/hardhat-upgrades" to perform Etherscan verification
    // of Proxy and Implementation contracts.
    await hre.run("verify", {
      address: proxyDeployment.address,
      constructorArgsParams: proxyDeployment.args,
    })
  }

  if (hre.network.tags.tenderly) {
    await hre.tenderly.verify({
      name: "WalletRegistry",
      address: walletRegistry.address,
    })
  }
}

export default func

func.tags = ["WalletRegistry"]
func.dependencies = [
  "ReimbursementPool",
  "RandomBeacon",
  "EcdsaSortitionPool",
  "TokenStaking",
  "EcdsaDkgValidator",
]

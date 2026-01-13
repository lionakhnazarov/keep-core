import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * Deploy ReimbursementPool and authorize WalletRegistry
 */
async function main() {
  const { getNamedAccounts, deployments } = hre
  const { deployer } = await getNamedAccounts()
  const deployerSigner = await ethers.getSigner(deployer)

  console.log("==========================================")
  console.log("Deploying and Setting Up ReimbursementPool")
  console.log("==========================================")
  console.log(`Deployer: ${deployer}`)
  console.log("")

  // Step 1: Deploy ReimbursementPool
  console.log("Step 1: Deploying ReimbursementPool...")
  
  const staticGas = 40_800 // gas amount consumed by the refund() + tx cost
  const maxGasPrice = 500_000_000_000 // 500 Gwei
  
  // Check if ReimbursementPool already exists
  let reimbursementPoolAddress: string
  let reimbursementPool
  
  const existing = await deployments.getOrNull("ReimbursementPool")
  if (existing) {
    const code = await hre.ethers.provider.getCode(existing.address)
    if (code && code.length > 2) {
      console.log(`✓ ReimbursementPool already exists at ${existing.address}`)
      reimbursementPoolAddress = existing.address
    } else {
      console.log(`⚠️  ReimbursementPool deployment file exists but contract not found on-chain`)
      console.log(`   Deploying new ReimbursementPool...`)
      
      // Delete stale deployment
      await deployments.delete("ReimbursementPool")
      
      // Deploy new one
      const ReimbursementPoolDeployment = await deployments.deploy("ReimbursementPool", {
        from: deployer,
        args: [staticGas, maxGasPrice],
        log: true,
        waitConfirmations: 1,
      })
      reimbursementPoolAddress = ReimbursementPoolDeployment.address
      console.log(`✓ Deployed ReimbursementPool at ${reimbursementPoolAddress}`)
    }
  } else {
    // Deploy new ReimbursementPool
    const ReimbursementPoolDeployment = await deployments.deploy("ReimbursementPool", {
      from: deployer,
      args: [staticGas, maxGasPrice],
      log: true,
      waitConfirmations: 1,
    })
    reimbursementPoolAddress = ReimbursementPoolDeployment.address
    console.log(`✓ Deployed ReimbursementPool at ${reimbursementPoolAddress}`)
  }

  // Get ReimbursementPool contract instance
  const ReimbursementPoolArtifact = await deployments.getArtifact("ReimbursementPool")
  reimbursementPool = new ethers.Contract(
    reimbursementPoolAddress,
    ReimbursementPoolArtifact.abi,
    deployerSigner
  )

  console.log("")

  // Step 2: Get WalletRegistry address
  console.log("Step 2: Getting WalletRegistry address...")
  const WalletRegistry = await deployments.get("WalletRegistry")
  const walletRegistryAddress = WalletRegistry.address
  console.log(`WalletRegistry: ${walletRegistryAddress}`)
  console.log("")

  // Step 3: Check if WalletRegistry is already authorized
  console.log("Step 3: Checking authorization...")
  const isAuthorized = await reimbursementPool.isAuthorized(walletRegistryAddress)
  
  if (isAuthorized) {
    console.log(`✓ WalletRegistry is already authorized`)
  } else {
    console.log(`⚠️  WalletRegistry is NOT authorized`)
    console.log(`   Authorizing WalletRegistry...`)
    
    const tx = await reimbursementPool.authorize(walletRegistryAddress)
    await tx.wait()
    console.log(`✓ Authorized WalletRegistry`)
    console.log(`   Transaction: ${tx.hash}`)
  }
  console.log("")

  // Step 4: Fund ReimbursementPool
  console.log("Step 4: Funding ReimbursementPool...")
  const balance = await ethers.provider.getBalance(reimbursementPoolAddress)
  const minBalance = ethers.utils.parseEther("10.0") // 10 ETH minimum
  
  if (balance.lt(minBalance)) {
    const amountToSend = minBalance.sub(balance)
    console.log(`   Current balance: ${ethers.utils.formatEther(balance)} ETH`)
    console.log(`   Sending ${ethers.utils.formatEther(amountToSend)} ETH...`)
    
    const fundTx = await deployerSigner.sendTransaction({
      to: reimbursementPoolAddress,
      value: amountToSend,
    })
    await fundTx.wait()
    
    const newBalance = await ethers.provider.getBalance(reimbursementPoolAddress)
    console.log(`✓ Funded ReimbursementPool`)
    console.log(`   New balance: ${ethers.utils.formatEther(newBalance)} ETH`)
    console.log(`   Transaction: ${fundTx.hash}`)
  } else {
    console.log(`✓ ReimbursementPool already has sufficient balance`)
    console.log(`   Balance: ${ethers.utils.formatEther(balance)} ETH`)
  }
  console.log("")

  // Step 5: Verify setup
  console.log("Step 5: Verifying setup...")
  const finalIsAuthorized = await reimbursementPool.isAuthorized(walletRegistryAddress)
  const finalBalance = await ethers.provider.getBalance(reimbursementPoolAddress)
  
  console.log(`   WalletRegistry authorized: ${finalIsAuthorized ? "✓ YES" : "✗ NO"}`)
  console.log(`   ReimbursementPool balance: ${ethers.utils.formatEther(finalBalance)} ETH`)
  console.log(`   Static gas: ${await reimbursementPool.staticGas()}`)
  console.log(`   Max gas price: ${await reimbursementPool.maxGasPrice()}`)
  console.log("")

  if (finalIsAuthorized && finalBalance.gte(minBalance)) {
    console.log("==========================================")
    console.log("✅ Setup Complete!")
    console.log("==========================================")
    console.log(`ReimbursementPool: ${reimbursementPoolAddress}`)
    console.log(`WalletRegistry: ${walletRegistryAddress}`)
    console.log("")
    console.log("The DKG approval should now work correctly.")
  } else {
    console.log("==========================================")
    console.log("⚠️  Setup Incomplete")
    console.log("==========================================")
    if (!finalIsAuthorized) {
      console.log("   - WalletRegistry is not authorized")
    }
    if (finalBalance.lt(minBalance)) {
      console.log("   - ReimbursementPool has insufficient balance")
    }
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})



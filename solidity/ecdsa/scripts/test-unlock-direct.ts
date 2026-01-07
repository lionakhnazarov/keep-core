import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * Test unlock() call directly from WalletRegistry to verify the issue
 */
async function main() {
  const WalletRegistry = await hre.deployments.get("WalletRegistry")
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address)

  const sortitionPoolAddress = await wr.sortitionPool()
  console.log("==========================================")
  console.log("Test Unlock Direct Call")
  console.log("==========================================")
  console.log("")
  console.log(`WalletRegistry: ${WalletRegistry.address}`)
  console.log(`SortitionPool: ${sortitionPoolAddress}`)
  console.log("")

  // Get sortition pool contract
  const sortitionPoolABI = [
    "function unlock()",
    "function isLocked() view returns (bool)",
    "function owner() view returns (address)",
  ]
  
  const sortitionPool = new ethers.Contract(
    sortitionPoolAddress,
    sortitionPoolABI,
    ethers.provider
  )

  const owner = await sortitionPool.owner()
  const isLocked = await sortitionPool.isLocked()
  
  console.log(`SortitionPool Owner: ${owner}`)
  console.log(`WalletRegistry: ${WalletRegistry.address}`)
  console.log(`Match: ${owner.toLowerCase() === WalletRegistry.address.toLowerCase() ? "✅ YES" : "❌ NO"}`)
  console.log("")
  console.log(`Pool isLocked: ${isLocked}`)
  console.log("")

  // Try to call unlock() directly from WalletRegistry
  // We need to impersonate WalletRegistry
  console.log("Testing unlock() call from WalletRegistry...")
  console.log("")
  
  try {
    // Impersonate WalletRegistry
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [WalletRegistry.address],
    })
    
    const walletRegistrySigner = await ethers.getSigner(WalletRegistry.address)
    
    // Fund the account if needed
    const balance = await ethers.provider.getBalance(WalletRegistry.address)
    if (balance.lt(ethers.utils.parseEther("0.1"))) {
      const [deployer] = await ethers.getSigners()
      await deployer.sendTransaction({
        to: WalletRegistry.address,
        value: ethers.utils.parseEther("1.0"),
      })
    }
    
    const sortitionPoolConnected = sortitionPool.connect(walletRegistrySigner)
    
    console.log("Calling unlock() from WalletRegistry...")
    const tx = await sortitionPoolConnected.unlock()
    console.log(`Transaction hash: ${tx.hash}`)
    console.log("Waiting for confirmation...")
    
    const receipt = await tx.wait()
    console.log(`✅ Transaction confirmed in block ${receipt.blockNumber}`)
    console.log("")
    
    // Verify pool is unlocked
    const isLockedAfter = await sortitionPool.isLocked()
    console.log(`Pool isLocked after unlock: ${isLockedAfter}`)
    
    if (!isLockedAfter) {
      console.log("✅ Pool successfully unlocked!")
    } else {
      console.log("❌ Pool is still locked")
    }
    
    // Stop impersonating
    await hre.network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [WalletRegistry.address],
    })
    
  } catch (error: any) {
    console.error("Error calling unlock():")
    console.error(`  ${error.message}`)
    
    if (error.data) {
      console.error(`  Error data: ${error.data}`)
    }
    
    // Try to decode error
    try {
      const errorSig = ethers.utils.id("Ownable: caller is not the owner").slice(0, 10)
      if (error.data && error.data.startsWith(errorSig)) {
        console.error("")
        console.error("❌ ERROR: Caller is not the owner!")
        console.error("   This confirms the issue - msg.sender is not WalletRegistry")
        console.error("   when called from within the library function.")
      }
    } catch (e) {
      // Ignore
    }
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})


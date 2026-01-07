import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * Transfer SortitionPool ownership from WalletRegistry to deployer account
 * This fixes the issue where unlock() reverts because msg.sender != owner()
 * 
 * This script uses Hardhat's account impersonation to call transferOwnership
 * from WalletRegistry's context. Only works on local/test networks.
 */
async function main() {
  const { getNamedAccounts } = hre
  const { deployer } = await getNamedAccounts()
  
  // Only works on local/test networks
  if (hre.network.name !== "development" && hre.network.name !== "hardhat" && !hre.network.name.includes("localhost")) {
    console.error("⚠️  This script only works on local/test networks")
    console.error(`   Current network: ${hre.network.name}`)
    console.error("   For mainnet/testnet, you'll need to add a function to WalletRegistry")
    process.exit(1)
  }
  
  const WalletRegistry = await hre.deployments.get("WalletRegistry")
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address)
  
  const sortitionPoolAddress = await wr.sortitionPool()
  console.log("==========================================")
  console.log("Transfer SortitionPool Ownership")
  console.log("==========================================")
  console.log("")
  console.log(`SortitionPool: ${sortitionPoolAddress}`)
  console.log(`WalletRegistry: ${WalletRegistry.address}`)
  console.log(`Deployer: ${deployer}`)
  console.log("")
  
  // Get SortitionPool contract
  const sortitionPoolABI = [
    "function owner() view returns (address)",
    "function transferOwnership(address newOwner)",
    "function isLocked() view returns (bool)",
  ]
  const sp = new ethers.Contract(sortitionPoolAddress, sortitionPoolABI, ethers.provider)
  
  const currentOwner = await sp.owner()
  const isLocked = await sp.isLocked()
  
  console.log(`Current owner: ${currentOwner}`)
  console.log(`Is locked: ${isLocked}`)
  console.log("")
  
  if (currentOwner.toLowerCase() === deployer.toLowerCase()) {
    console.log("✅ SortitionPool is already owned by deployer!")
    console.log("   No transfer needed.")
    return
  }
  
  if (currentOwner.toLowerCase() !== WalletRegistry.address.toLowerCase()) {
    console.log(`⚠️  Current owner (${currentOwner}) is not WalletRegistry (${WalletRegistry.address})`)
    console.log(`   Cannot transfer from this owner using this script.`)
    console.log(`   Please transfer ownership manually from ${currentOwner} to ${deployer}`)
    return
  }
  
  console.log("Transferring ownership from WalletRegistry to deployer...")
  console.log("")
  console.log("Using Hardhat account impersonation...")
  
  // Impersonate WalletRegistry to call transferOwnership
  await hre.network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [WalletRegistry.address],
  })
  
  // Fund WalletRegistry if needed (for gas)
  const wrBalance = await ethers.provider.getBalance(WalletRegistry.address)
  if (wrBalance.lt(ethers.utils.parseEther("0.1"))) {
    const [deployerSigner] = await ethers.getSigners()
    await deployerSigner.sendTransaction({
      to: WalletRegistry.address,
      value: ethers.utils.parseEther("1.0"),
    })
    console.log("Funded WalletRegistry account for gas")
  }
  
  const walletRegistrySigner = await ethers.getSigner(WalletRegistry.address)
  const spConnected = sp.connect(walletRegistrySigner)
  
  try {
    console.log("Calling transferOwnership...")
    const tx = await spConnected.transferOwnership(deployer)
    console.log(`Transaction hash: ${tx.hash}`)
    const receipt = await tx.wait()
    console.log(`✅ Success! Block: ${receipt.blockNumber}`)
    console.log("")
    
    // Verify ownership transfer
    const newOwner = await sp.owner()
    if (newOwner.toLowerCase() === deployer.toLowerCase()) {
      console.log("✅ Ownership successfully transferred to deployer!")
      console.log(`   New owner: ${newOwner}`)
    } else {
      console.log(`⚠️  Ownership transfer may have failed. Current owner: ${newOwner}`)
    }
  } catch (error: any) {
    console.error("❌ Transfer failed:")
    console.error(`   ${error.message}`)
    if (error.reason) {
      console.error(`   Reason: ${error.reason}`)
    }
    throw error
  } finally {
    // Stop impersonating
    await hre.network.provider.request({
      method: "hardhat_stopImpersonatingAccount",
      params: [WalletRegistry.address],
    })
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

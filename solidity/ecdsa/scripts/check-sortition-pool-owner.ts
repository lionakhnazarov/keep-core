import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * Check if WalletRegistry is the owner of SortitionPool
 */
async function main() {
  const WalletRegistry = await hre.deployments.get("WalletRegistry")
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address)
  
  const sortitionPoolAddress = await wr.sortitionPool()
  console.log("SortitionPool address:", sortitionPoolAddress)
  
  // Get owner using Ownable's owner() function
  const sortitionPoolABI = [
    "function owner() view returns (address)",
    "function isLocked() view returns (bool)",
  ]
  const sp = new ethers.Contract(sortitionPoolAddress, sortitionPoolABI, ethers.provider)
  
  const owner = await sp.owner()
  const isLocked = await sp.isLocked()
  
  console.log("")
  console.log("SortitionPool owner:", owner)
  console.log("WalletRegistry address:", WalletRegistry.address)
  console.log("Match:", owner.toLowerCase() === WalletRegistry.address.toLowerCase() ? "✅ YES" : "❌ NO")
  console.log("")
  console.log("SortitionPool isLocked:", isLocked)
  console.log("")
  
  if (owner.toLowerCase() !== WalletRegistry.address.toLowerCase()) {
    console.log("❌ PROBLEM: WalletRegistry is NOT the owner of SortitionPool!")
    console.log("   This would cause unlock() to revert with onlyOwner modifier")
  } else {
    console.log("✅ WalletRegistry is the owner")
    console.log("")
    console.log("The issue might be that msg.sender is not WalletRegistry")
    console.log("when unlock() is called. Let's check the call context...")
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

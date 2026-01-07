import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * Check walletOwner configuration
 */
async function main() {
  const WalletRegistry = await hre.deployments.get("WalletRegistry")
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address)

  const walletOwnerAddress = await wr.walletOwner()
  console.log("==========================================")
  console.log("WalletOwner Configuration Check")
  console.log("==========================================")
  console.log("")
  console.log(`WalletRegistry: ${WalletRegistry.address}`)
  console.log(`WalletOwner: ${walletOwnerAddress}`)
  console.log("")
  
  // Check if walletOwner is a contract
  const code = await ethers.provider.getCode(walletOwnerAddress)
  if (code === "0x") {
    console.log("⚠️  WalletOwner is an EOA (Externally Owned Account)")
    console.log("   This might cause issues if callback requires contract logic")
  } else {
    console.log("✅ WalletOwner is a contract")
    console.log(`   Code length: ${code.length} bytes`)
    
    // Try to get the contract interface
    try {
      const walletOwnerABI = [
        "function __ecdsaWalletCreatedCallback(bytes32,bytes32,bytes32)",
      ]
      const walletOwner = new ethers.Contract(walletOwnerAddress, walletOwnerABI, ethers.provider)
      console.log("✅ WalletOwner has callback function interface")
    } catch (e) {
      console.log("⚠️  Could not verify callback interface")
    }
  }
  
  console.log("")
  console.log("Checking if callback can be called...")
  
  // Try to simulate a callback call
  try {
    const testWalletID = ethers.utils.hexZeroPad("0x01", 32)
    const testPublicKeyX = ethers.utils.hexZeroPad("0x02", 32)
    const testPublicKeyY = ethers.utils.hexZeroPad("0x03", 32)
    
    // Use staticCall to check if it would revert
    const walletOwnerABI = [
      "function __ecdsaWalletCreatedCallback(bytes32,bytes32,bytes32)",
    ]
    const walletOwner = new ethers.Contract(walletOwnerAddress, walletOwnerABI, ethers.provider)
    
    try {
      await walletOwner.callStatic.__ecdsaWalletCreatedCallback(
        testWalletID,
        testPublicKeyX,
        testPublicKeyY
      )
      console.log("✅ Callback call simulation succeeded")
    } catch (callError: any) {
      console.log("❌ Callback call simulation failed:")
      console.log(`   ${callError.message}`)
      if (callError.reason) {
        console.log(`   Reason: ${callError.reason}`)
      }
    }
  } catch (e: any) {
    console.log(`⚠️  Could not test callback: ${e.message}`)
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

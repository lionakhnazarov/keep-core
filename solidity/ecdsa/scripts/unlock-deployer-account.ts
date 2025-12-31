import { HardhatRuntimeEnvironment } from "hardhat/types"

/**
 * Unlock deployer account in Geth via RPC
 * Usage: npx hardhat run scripts/unlock-deployer-account.ts --network development
 */
async function main() {
  const hre: HardhatRuntimeEnvironment = require("hardhat")
  const { getNamedAccounts, ethers } = hre
  
  if (hre.network.name !== "development") {
    console.log("This script only works for development network")
    process.exit(1)
  }
  
  const { deployer } = await getNamedAccounts()
  const password = process.env.KEEP_ETHEREUM_PASSWORD || "password"
  
  console.log("=== Unlocking Deployer Account ===")
  console.log(`Deployer: ${deployer}`)
  console.log("")
  
  const provider = ethers.provider
  
  // Check if personal namespace is available
  let personalNamespaceAvailable = false
  try {
    await provider.send("personal_listAccounts", [])
    personalNamespaceAvailable = true
  } catch (error: any) {
    if (error.code === -32601 || error.error?.code === -32601) {
      personalNamespaceAvailable = false
    } else {
      personalNamespaceAvailable = true
    }
  }
  
  if (!personalNamespaceAvailable) {
    console.log("⚠️  Geth 1.16+ detected: personal namespace is deprecated.")
    console.log("   Accounts should be unlocked via --unlock flag when starting Geth.")
    console.log("   Please restart Geth with: ./scripts/start-geth-fast.sh")
    process.exit(1)
  }
  
  try {
    console.log("Unlocking account...")
    const result = await provider.send("personal_unlockAccount", [deployer, password, 0])
    if (result) {
      console.log("✅ Account unlocked successfully!")
    } else {
      console.log("⚠️  Account unlock returned false (may already be unlocked or wrong password)")
    }
  } catch (error: any) {
    console.log("❌ Error unlocking account:", error.message)
    if (error.message?.includes("account unlock with HTTP access is forbidden")) {
      console.log("")
      console.log("Geth needs to be started with --allow-insecure-unlock flag")
      console.log("Please restart Geth with: ./scripts/start-geth-fast.sh")
    }
    process.exit(1)
  }
  
  // Verify account is unlocked by checking if we can get balance
  try {
    const balance = await provider.getBalance(deployer)
    console.log(`✓ Account balance: ${ethers.utils.formatEther(balance)} ETH`)
  } catch (error: any) {
    console.log("⚠️  Could not verify account balance")
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

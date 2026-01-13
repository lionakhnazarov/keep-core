import { ethers } from "hardhat"
import hre from "hardhat"

async function main() {
  const ownerAddress = "0x2e666F38Cf0A5ed375AE5ae2c40baed553410038"
  
  console.log("==========================================")
  console.log("Getting Owner Private Key")
  console.log("==========================================")
  console.log(`Owner address: ${ownerAddress}`)
  console.log("")
  
  // Try to get from Hardhat accounts (if using Hardhat's default mnemonic)
  const accounts = await ethers.getSigners()
  console.log(`Hardhat has ${accounts.length} accounts available`)
  
  // Check if owner is in Hardhat accounts
  let found = false
  for (let i = 0; i < accounts.length; i++) {
    if (accounts[i].address.toLowerCase() === ownerAddress.toLowerCase()) {
      console.log(`✓ Found owner at account index ${i}`)
      // Note: Hardhat doesn't expose private keys directly for security
      // But we can use the signer to send transactions
      console.log("")
      console.log("To use this account:")
      console.log(`  const accounts = await ethers.getSigners()`)
      console.log(`  const owner = accounts[${i}]`)
      console.log(`  // Use owner to send transactions`)
      found = true
      break
    }
  }
  
  if (!found) {
    console.log("⚠️  Owner address not found in Hardhat accounts")
    console.log("")
    console.log("This means the owner is likely a Geth account.")
    console.log("To get the private key from Geth keystore:")
    console.log("")
    console.log("1. Find the keystore file:")
    console.log("   geth account list --keystore ~/ethereum/data/keystore")
    console.log("")
    console.log("2. Export the private key:")
    console.log(`   geth account export <account-path> --keystore ~/ethereum/data/keystore`)
    console.log("   (You'll need the account password)")
    console.log("")
    console.log("3. Or use Hardhat's default mnemonic to derive:")
    console.log("   Hardhat uses: 'test test test test test test test test test test test junk'")
    console.log("   Account index 3 (chaosnetOwner) can be derived from this mnemonic")
  }
  
  // Show Hardhat's default accounts for reference
  console.log("")
  console.log("Hardhat accounts (first 5):")
  for (let i = 0; i < Math.min(5, accounts.length); i++) {
    console.log(`  [${i}]: ${accounts[i].address}`)
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})



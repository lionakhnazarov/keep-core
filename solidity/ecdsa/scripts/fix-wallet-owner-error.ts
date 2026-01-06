import { ethers } from "hardhat"
import hre from "hardhat"

async function main() {
  console.log("==========================================")
  console.log("Fix 'Caller is not the Wallet Owner' Error")
  console.log("==========================================")
  console.log("")

  // Get Bridge address
  const fs = require("fs")
  const path = require("path")
  const bridgePath = path.resolve(__dirname, "../../tbtc-stub/deployments/development/Bridge.json")
  
  let bridgeAddress: string
  if (fs.existsSync(bridgePath)) {
    const bridgeData = JSON.parse(fs.readFileSync(bridgePath, "utf8"))
    bridgeAddress = bridgeData.address
  } else {
    console.error("Error: Bridge deployment not found")
    console.error("Run: cd solidity/tbtc-stub && npx hardhat deploy --network development")
    process.exit(1)
  }

  // Get WalletRegistry
  const WalletRegistry = await hre.deployments.get("WalletRegistry")
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address)

  console.log(`Bridge address: ${bridgeAddress}`)
  console.log(`WalletRegistry address: ${WalletRegistry.address}`)
  console.log("")

  // Step 1: Check current walletOwner
  console.log("Step 1: Checking current walletOwner...")
  const currentWalletOwner = await wr.walletOwner()
  console.log(`  Current walletOwner: ${currentWalletOwner}`)
  console.log(`  Expected walletOwner: ${bridgeAddress}`)
  console.log("")

  // Check if addresses match (case-sensitive comparison)
  const addressesMatch = currentWalletOwner.toLowerCase() === bridgeAddress.toLowerCase()
  const exactMatch = currentWalletOwner === bridgeAddress

  if (!addressesMatch) {
    console.error("✗ ERROR: walletOwner doesn't match Bridge address!")
    console.error("  This is the root cause of the error.")
    console.error("")
    console.error("Solution: Update walletOwner to Bridge address")
    console.error("")
  } else if (!exactMatch) {
    console.warn("⚠️  WARNING: Addresses match but case differs!")
    console.warn(`  Stored: ${currentWalletOwner}`)
    console.warn(`  Bridge: ${bridgeAddress}`)
    console.warn("  This might cause issues. Updating to exact match...")
    console.log("")
  } else {
    console.log("✓ walletOwner matches Bridge address")
    console.log("")
  }

  // Step 2: Verify Bridge contract exists
  console.log("Step 2: Verifying Bridge contract...")
  const bridgeCode = await ethers.provider.getCode(bridgeAddress)
  if (bridgeCode === "0x" || bridgeCode.length <= 2) {
    console.error("✗ ERROR: Bridge contract not found at address!")
    console.error("  Deploy Bridge first:")
    console.error("  cd solidity/tbtc-stub && npx hardhat deploy --network development")
    process.exit(1)
  }
  console.log("✓ Bridge contract exists")
  console.log("")

  // Step 3: Check Bridge's ecdsaWalletRegistry
  console.log("Step 3: Checking Bridge configuration...")
  try {
    const Bridge = await ethers.getContractAt(
      ["function ecdsaWalletRegistry() view returns (address)"],
      bridgeAddress
    )
    const bridgeEcdsaWalletRegistry = await Bridge.ecdsaWalletRegistry()
    console.log(`  Bridge.ecdsaWalletRegistry: ${bridgeEcdsaWalletRegistry}`)
    console.log(`  WalletRegistry address: ${WalletRegistry.address}`)
    
    if (bridgeEcdsaWalletRegistry.toLowerCase() !== WalletRegistry.address.toLowerCase()) {
      console.error("✗ ERROR: Bridge.ecdsaWalletRegistry doesn't match WalletRegistry!")
      console.error("  Bridge needs to be redeployed or updated")
      process.exit(1)
    }
    console.log("✓ Bridge.ecdsaWalletRegistry matches WalletRegistry")
  } catch (e: any) {
    console.log(`  ⚠ Could not check Bridge.ecdsaWalletRegistry: ${e.message}`)
  }
  console.log("")

  // Step 4: Update walletOwner if needed
  if (!exactMatch) {
    console.log("Step 4: Updating walletOwner to Bridge address...")
    
    try {
      // Get WalletRegistryGovernance
      const WalletRegistryGovernance = await hre.deployments.get("WalletRegistryGovernance")
      const wrGov = await ethers.getContractAt(
        "WalletRegistryGovernance",
        WalletRegistryGovernance.address
      )

      // Check if walletOwner is zero (can use initialize)
      const isZero = currentWalletOwner === ethers.constants.AddressZero
      
      if (isZero) {
        console.log("  Using initializeWalletOwner (no delay)...")
        const { deployer } = await hre.getNamedAccounts()
        const deployerSigner = await ethers.getSigner(deployer)
        const owner = await wrGov.owner()
        
        if (owner.toLowerCase() === deployer.toLowerCase()) {
          const tx = await wrGov.connect(deployerSigner).initializeWalletOwner(bridgeAddress)
          console.log(`  Transaction: ${tx.hash}`)
          await tx.wait()
          console.log("  ✓ walletOwner initialized!")
        } else {
          console.error(`  ✗ Governance owner (${owner}) != deployer (${deployer})`)
          console.error("  Run manually with correct account")
          process.exit(1)
        }
      } else {
        console.log("  Using beginWalletOwnerUpdate + finalizeWalletOwnerUpdate...")
        const { deployer } = await hre.getNamedAccounts()
        const deployerSigner = await ethers.getSigner(deployer)
        const owner = await wrGov.owner()
        
        if (owner.toLowerCase() === deployer.toLowerCase()) {
          // Begin update
          console.log("  Beginning update...")
          const beginTx = await wrGov.connect(deployerSigner).beginWalletOwnerUpdate(bridgeAddress)
          await beginTx.wait()
          console.log(`  Begin transaction: ${beginTx.hash}`)
          
          // Check delay
          const governanceDelay = await wrGov.governanceDelay()
          const changeInitiated = await wrGov.walletOwnerChangeInitiated()
          const block = await ethers.provider.getBlock("latest")
          const timeElapsed = block.timestamp - changeInitiated.toNumber()
          
          console.log(`  Governance delay: ${governanceDelay.toString()} seconds`)
          console.log(`  Time elapsed: ${timeElapsed.toString()} seconds`)
          
          if (timeElapsed >= governanceDelay.toNumber()) {
            console.log("  ✓ Delay passed! Finalizing...")
            const finalizeTx = await wrGov.connect(deployerSigner).finalizeWalletOwnerUpdate()
            await finalizeTx.wait()
            console.log(`  Finalize transaction: ${finalizeTx.hash}`)
            console.log("  ✓ walletOwner updated!")
          } else {
            const waitTime = governanceDelay.toNumber() - timeElapsed
            console.log(`  ⚠ Need to wait ${waitTime} seconds`)
            console.log("")
            console.log("  To finalize, run:")
            console.log("    npx hardhat run scripts/finalize-wallet-owner-update.ts --network development")
            console.log("")
            console.log("  Or advance time and finalize:")
            console.log("    ./scripts/advance-geth-time.sh")
            console.log("    npx hardhat run scripts/finalize-wallet-owner-update.ts --network development")
            return
          }
        } else {
          console.error(`  ✗ Governance owner (${owner}) != deployer (${deployer})`)
          console.error("  Run manually with correct account")
          process.exit(1)
        }
      }
    } catch (error: any) {
      console.error(`  ✗ Error updating walletOwner: ${error.message}`)
      if (error.data) {
        console.error(`  Error data: ${error.data}`)
      }
      process.exit(1)
    }
    console.log("")
  } else {
    console.log("Step 4: walletOwner already correct, skipping update")
    console.log("")
  }

  // Step 5: Verify final state
  console.log("Step 5: Verifying final state...")
  const finalWalletOwner = await wr.walletOwner()
  console.log(`  Final walletOwner: ${finalWalletOwner}`)
  console.log(`  Bridge address: ${bridgeAddress}`)
  
  if (finalWalletOwner.toLowerCase() !== bridgeAddress.toLowerCase()) {
    console.error("  ✗ ERROR: walletOwner still doesn't match!")
    process.exit(1)
  }
  
  if (finalWalletOwner !== bridgeAddress) {
    console.warn("  ⚠ Addresses match but case differs - this might still cause issues")
  } else {
    console.log("  ✓ walletOwner matches Bridge address exactly!")
  }
  console.log("")

  // Step 6: Test static call
  console.log("Step 6: Testing Bridge.requestNewWallet() call...")
  const [signer] = await ethers.getSigners()
  try {
    const Bridge = await ethers.getContractAt(
      ["function requestNewWallet() external"],
      bridgeAddress
    )
    
    // Try static call
    await Bridge.connect(signer).callStatic.requestNewWallet({ gasLimit: 500000 })
    console.log("  ✓ Static call succeeded!")
    console.log("")
    console.log("==========================================")
    console.log("✅ SUCCESS! The fix is complete.")
    console.log("==========================================")
    console.log("")
    console.log("You can now call Bridge.requestNewWallet():")
    console.log("  cd solidity/ecdsa")
    console.log("  npx hardhat run scripts/request-new-wallet.ts --network development")
    console.log("")
  } catch (error: any) {
    console.error("  ✗ Static call failed")
    console.error(`  Error: ${error.message}`)
    console.log("")
    console.log("  The walletOwner is set correctly, but the call still fails.")
    console.log("  This might be due to:")
    console.log("    1. DKG state not being IDLE")
    console.log("    2. SortitionPool being locked")
    console.log("    3. RandomBeacon authorization issue")
    console.log("")
    console.log("  Check DKG state:")
    console.log("    cd solidity/ecdsa")
    console.log("    npx hardhat run scripts/check-dkg-status.ts --network development")
    console.log("")
    process.exit(1)
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})


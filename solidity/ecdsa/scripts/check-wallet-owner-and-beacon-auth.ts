import { ethers } from "hardhat"
import hre from "hardhat"

async function main() {
  console.log("==========================================")
  console.log("Check Wallet Owner & RandomBeacon Auth")
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
    process.exit(1)
  }

  // Get WalletRegistry
  const WalletRegistry = await hre.deployments.get("WalletRegistry")
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address)

  console.log(`Bridge: ${bridgeAddress}`)
  console.log(`WalletRegistry: ${WalletRegistry.address}`)
  console.log("")

  // Check 1: walletOwner
  console.log("Check 1: Wallet Owner")
  console.log("====================")
  const walletOwner = await wr.walletOwner()
  console.log(`  Current walletOwner: ${walletOwner}`)
  console.log(`  Expected (Bridge):  ${bridgeAddress}`)
  
  const addressesMatch = walletOwner.toLowerCase() === bridgeAddress.toLowerCase()
  const exactMatch = walletOwner === bridgeAddress
  
  if (!addressesMatch) {
    console.error("  ✗ MISMATCH - This is likely the root cause!")
    console.error("  Fix: Run scripts/fix-wallet-owner-error.ts")
  } else if (!exactMatch) {
    console.warn("  ⚠ Addresses match but case differs")
    console.warn(`    Stored: ${walletOwner}`)
    console.warn(`    Bridge: ${bridgeAddress}`)
    console.warn("  This might cause issues - update to exact match")
  } else {
    console.log("  ✓ walletOwner matches Bridge exactly")
  }
  console.log("")

  // Check 2: RandomBeacon
  console.log("Check 2: RandomBeacon Configuration")
  console.log("===================================")
  try {
    const randomBeaconAddress = await wr.randomBeacon()
    console.log(`  RandomBeacon address: ${randomBeaconAddress}`)
    
    if (randomBeaconAddress === ethers.constants.AddressZero) {
      console.error("  ✗ RandomBeacon is not set!")
      process.exit(1)
    }

    // Check RandomBeacon type and authorization method
    const randomBeaconCode = await ethers.provider.getCode(randomBeaconAddress)
    if (randomBeaconCode === "0x" || randomBeaconCode.length <= 2) {
      console.error("  ✗ RandomBeacon contract not found!")
      process.exit(1)
    }
    console.log("  ✓ RandomBeacon contract exists")
    console.log("")

    // Check authorization - RandomBeaconChaosnet uses authorizedRequesters mapping
    console.log("Check 3: RandomBeacon Authorization")
    console.log("===================================")
    
    // Check if it's RandomBeaconChaosnet (has authorizedRequesters)
    try {
      const RandomBeaconChaosnet = await ethers.getContractAt(
        ["function authorizedRequesters(address) view returns (bool)", "function owner() view returns (address)"],
        randomBeaconAddress
      )
      
      const isAuthorized = await RandomBeaconChaosnet.authorizedRequesters(WalletRegistry.address)
      console.log(`  RandomBeaconChaosnet.authorizedRequesters(${WalletRegistry.address}): ${isAuthorized}`)
      
      if (!isAuthorized) {
        console.error("  ✗ WalletRegistry is NOT authorized in RandomBeaconChaosnet!")
        console.error("  This WILL cause requestNewWallet() to fail!")
        console.error("")
        console.error("  The error 'Caller is not the Wallet Owner' might be misleading.")
        console.error("  The actual issue is RandomBeacon authorization!")
        console.error("")
        console.error("  Fix: Authorize WalletRegistry in RandomBeaconChaosnet")
        console.error("    cd solidity/ecdsa")
        console.error("    npx hardhat run scripts/authorize-wallet-registry-in-beacon.ts --network development")
        console.error("")
        console.error("  Or manually:")
        const owner = await RandomBeaconChaosnet.owner()
        console.error(`    RandomBeaconChaosnet owner: ${owner}`)
        console.error(`    Call: RandomBeaconChaosnet.setRequesterAuthorization(${WalletRegistry.address}, true)`)
        console.log("")
      } else {
        console.log("  ✓ WalletRegistry is authorized in RandomBeaconChaosnet")
      }
    } catch (e: any) {
      console.log(`  ⚠ Could not check authorization: ${e.message}`)
      console.log("  ⚠ This might be a different RandomBeacon implementation")
    }
    console.log("")

    // Check 4: Test what happens when requestNewWallet is called
    console.log("Check 4: Testing requestNewWallet() Call Chain")
    console.log("==============================================")
    
    // Check DKG state
    const dkgState = await wr.getWalletCreationState()
    const stateNames = ["IDLE", "AWAITING_SEED", "AWAITING_RESULT", "CHALLENGE"]
    console.log(`  DKG State: ${stateNames[dkgState]} (${dkgState})`)
    
    if (dkgState !== 0) {
      console.warn("  ⚠ DKG is not in IDLE state")
      console.warn("  This will cause dkg.lockState() to revert")
    } else {
      console.log("  ✓ DKG is in IDLE state")
    }
    
    // Check sortition pool lock
    try {
      const sortitionPoolAddress = await wr.sortitionPool()
      const SortitionPool = await ethers.getContractAt(
        ["function isLocked() view returns (bool)"],
        sortitionPoolAddress
      )
      const isLocked = await SortitionPool.isLocked()
      console.log(`  SortitionPool isLocked: ${isLocked}`)
      
      if (isLocked) {
        console.warn("  ⚠ SortitionPool is locked")
        console.warn("  This will cause dkg.lockState() to revert")
      } else {
        console.log("  ✓ SortitionPool is not locked")
      }
    } catch (e: any) {
      console.log(`  ⚠ Could not check SortitionPool: ${e.message}`)
    }
    console.log("")

    // Summary
    console.log("==========================================")
    console.log("Summary")
    console.log("==========================================")
    
    const issues: string[] = []
    
    if (!addressesMatch) {
      issues.push("walletOwner doesn't match Bridge address")
    } else if (!exactMatch) {
      issues.push("walletOwner case mismatch")
    }
    
    // We can't definitively check authorization without knowing the exact interface
    // But we've tried common methods
    
    if (issues.length === 0) {
      console.log("✓ All checks passed!")
      console.log("")
      console.log("If requestNewWallet() still fails, the issue might be:")
      console.log("  1. RandomBeacon authorization (check manually)")
      console.log("  2. DKG state not IDLE")
      console.log("  3. SortitionPool locked")
      console.log("  4. Call forwarding issue (try Geth console)")
    } else {
      console.error("✗ Issues found:")
      issues.forEach(issue => console.error(`  - ${issue}`))
      console.log("")
      console.log("Fix these issues first, then test again.")
    }
    
  } catch (error: any) {
    console.error(`Error checking RandomBeacon: ${error.message}`)
    process.exit(1)
  }
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})


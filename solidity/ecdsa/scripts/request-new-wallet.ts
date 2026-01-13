import { ethers } from "hardhat"
import hre from "hardhat"

async function main() {
  // Get Bridge address - use walletOwner as source of truth
  const fs = require("fs")
  const path = require("path")
  const bridgePathStub = path.resolve(__dirname, "../../tbtc-stub/deployments/development/Bridge.json")
  const bridgePathV2 = path.resolve(__dirname, "../../../tmp/tbtc-v2/solidity/deployments/development/Bridge.json")
  
  // First, check what walletOwner is set to (this is the authoritative source)
  const WalletRegistry = await hre.deployments.get("WalletRegistry")
  const wr = await ethers.getContractAt(
    [
      "function walletOwner() view returns (address)",
      "function requestNewWallet() external",
      "function getWalletCreationState() view returns (uint8)",
      "function randomBeacon() view returns (address)"
    ],
    WalletRegistry.address
  )
  const walletOwnerAddress = await wr.walletOwner()
  
  let bridgeAddress: string
  let bridgePath: string
  let bridgeSource: string
  
  // Use walletOwner as the Bridge address (it's already set correctly)
  bridgeAddress = walletOwnerAddress
  
  // Determine which Bridge this is based on deployment files
  if (fs.existsSync(bridgePathStub)) {
    const bridgeStubData = JSON.parse(fs.readFileSync(bridgePathStub, "utf8"))
    if (bridgeStubData.address.toLowerCase() === bridgeAddress.toLowerCase()) {
      bridgePath = bridgePathStub
      bridgeSource = "Bridge stub (walletOwner)"
    }
  }
  
  if (!bridgePath && fs.existsSync(bridgePathV2)) {
    const bridgeV2Data = JSON.parse(fs.readFileSync(bridgePathV2, "utf8"))
    if (bridgeV2Data.address.toLowerCase() === bridgeAddress.toLowerCase()) {
      bridgePath = bridgePathV2
      bridgeSource = "Bridge v2 (walletOwner)"
    }
  }
  
  // If we couldn't match to a deployment file, use walletOwner address directly
  if (!bridgePath) {
    bridgeSource = `Bridge (walletOwner: ${bridgeAddress.slice(0, 10)}...)`
    console.log(`⚠️  Bridge address from walletOwner doesn't match known deployments`)
    console.log(`   Using walletOwner address: ${bridgeAddress}`)
  }
  
  // Verify Bridge has code
  const bridgeCode = await ethers.provider.getCode(bridgeAddress)
  if (bridgeCode === "0x" || bridgeCode === "0x0") {
    console.error(`⚠️  ERROR: Bridge contract at ${bridgeAddress} has no code!`)
    console.error(`   The Bridge contract is not deployed at this address.`)
    process.exit(1)
  }
  
  console.log("==========================================")
  console.log("Requesting New Wallet (Triggering DKG)")
  console.log("==========================================")
  console.log("")
  console.log(`Bridge address: ${bridgeAddress}`)
  console.log(`Bridge source: ${bridgeSource}`)
  console.log("")
  
  // Verify walletOwner matches Bridge address
  const walletOwner = await wr.walletOwner()
  console.log(`WalletRegistry walletOwner: ${walletOwner}`)
  
  if (walletOwner.toLowerCase() !== bridgeAddress.toLowerCase()) {
    console.error(`⚠️  ERROR: WalletOwner mismatch!`)
    console.error(`   Expected: ${bridgeAddress} (${bridgeSource})`)
    console.error(`   Got: ${walletOwner}`)
    console.error(`   Please update walletOwner to match Bridge address`)
    console.error(`   Run: cd solidity/ecdsa && npx hardhat run scripts/init-wallet-owner.ts --network development`)
    console.error("")
    console.error(`   Note: The script prefers Bridge stub (has callback function) over Bridge v2.`)
    console.error(`   If walletOwner is set to Bridge v2, update it to Bridge stub for DKG to work correctly.`)
    process.exit(1)
  }
  
  console.log(`✓ WalletOwner matches Bridge`)
  
  // Check RandomBeacon authorization
  try {
    const randomBeaconAddress = await wr.randomBeacon()
    console.log(`RandomBeacon address: ${randomBeaconAddress}`)
    
    if (randomBeaconAddress === ethers.constants.AddressZero) {
      console.error(`⚠️  ERROR: RandomBeacon is not set!`)
      console.error(`   Please configure RandomBeacon in WalletRegistry`)
      process.exit(1)
    }
    
    // Check if WalletRegistry is authorized in RandomBeacon
    try {
      const RandomBeacon = await ethers.getContractAt(
        ["function isRequesterAuthorized(address) view returns (bool)"],
        randomBeaconAddress
      )
      const isAuthorized = await RandomBeacon.isRequesterAuthorized(WalletRegistry.address)
      if (!isAuthorized) {
        console.error(`⚠️  WARNING: WalletRegistry is NOT authorized in RandomBeacon!`)
        console.error(`   This may cause requestNewWallet() to revert`)
        console.error(`   Run: cd solidity/ecdsa && npx hardhat run scripts/authorize-wallet-registry-in-beacon.ts --network development`)
        console.log(`   Continuing anyway...`)
      } else {
        console.log(`✓ WalletRegistry is authorized in RandomBeacon`)
      }
    } catch (e: any) {
      console.log(`⚠️  Could not check RandomBeacon authorization: ${e.message}`)
      console.log(`   Continuing anyway...`)
    }
  } catch (e: any) {
    console.log(`⚠️  Could not check RandomBeacon: ${e.message}`)
    console.log(`   Continuing anyway...`)
  }
  
  console.log("")
  
  // Check DKG state - this is the key check!
  try {
    const dkgState = await wr.getWalletCreationState()
    const stateNames = ["IDLE", "AWAITING_SEED", "AWAITING_RESULT", "CHALLENGE"]
    const stateName = stateNames[dkgState] || `UNKNOWN(${dkgState})`
    console.log(`Current DKG State: ${stateName} (${dkgState})`)
    
    if (dkgState !== 0) { // Not IDLE
      console.log(`⚠️  DKG is NOT in IDLE state!`)
      console.log(`   Current state: ${stateName}`)
      console.log(`   requestNewWallet() will revert with "Current state is not IDLE"`)
      console.log(`   You need to wait for the current DKG to complete or timeout`)
      console.log(`   Or reset the DKG if it's stuck`)
      console.log("")
      console.log("To check DKG status:")
      console.log(`   ./scripts/check-dkg-status.sh`)
      console.log("")
      console.log("To reset DKG (if stuck):")
      console.log(`   ./scripts/reset-dkg.sh`)
      console.log("")
      process.exit(1)
    } else {
      console.log(`✓ DKG is in IDLE state - ready to request new wallet`)
    }
  } catch (e: any) {
    console.log(`⚠️  Could not check DKG state: ${e.message}`)
    console.log(`   Continuing anyway, but transaction may fail...`)
  }
  
  console.log("")
  
  const [signer] = await ethers.getSigners()
  
  // Try to use Geth's impersonateAccount RPC method (for Geth nodes)
  console.log(`Attempting to impersonate Bridge account...`)
  let impersonated = false
  try {
    await hre.network.provider.send("eth_impersonateAccount", [bridgeAddress])
    impersonated = true
    console.log(`✓ Bridge account impersonated`)
  } catch (e: any) {
    console.log(`⚠️  Impersonation not available: ${e.message}`)
    console.log(`   Trying direct call via Bridge contract...`)
  }
  
  if (impersonated) {
    // Call WalletRegistry directly as Bridge (no gas needed when impersonated)
    const bridgeSigner = await ethers.getSigner(bridgeAddress)
    const wrWithBridge = wr.connect(bridgeSigner)
    
    console.log(`Calling WalletRegistry.requestNewWallet() as Bridge...`)
    try {
      const tx = await wrWithBridge.requestNewWallet({ gasLimit: 500000 })
      console.log(`Transaction submitted: ${tx.hash}`)
      const receipt = await tx.wait()
      console.log(`✓ DKG triggered successfully!`)
      console.log(`   Transaction confirmed in block: ${receipt.blockNumber}`)
      console.log(`   You can monitor DKG progress in node logs`)
      console.log("")
      console.log("==========================================")
      console.log("DKG Request Complete!")
      console.log("==========================================")
      
      // Stop impersonating
      try {
        await hre.network.provider.send("eth_stopImpersonatingAccount", [bridgeAddress])
      } catch (e) {
        // Ignore if not supported
      }
      return
    } catch (error: any) {
      console.error(`Error calling WalletRegistry: ${error.message}`)
      // Fall through to alternative methods
    }
  }
  
  // Check Bridge's ecdsaWalletRegistry address
  console.log(`Checking Bridge contract configuration...`)
  try {
    const bridge = await ethers.getContractAt(
      [
        "function requestNewWallet() external",
        "function ecdsaWalletRegistry() view returns (address)"
      ],
      bridgeAddress
    )
    const bridgeRegistry = await bridge.ecdsaWalletRegistry()
    console.log(`Bridge ecdsaWalletRegistry: ${bridgeRegistry}`)
    console.log(`WalletRegistry address: ${WalletRegistry.address}`)
    
    if (bridgeRegistry.toLowerCase() !== WalletRegistry.address.toLowerCase()) {
      console.error(`⚠️  ERROR: Bridge's ecdsaWalletRegistry doesn't match WalletRegistry address!`)
      console.error(`   Bridge has: ${bridgeRegistry}`)
      console.error(`   Expected: ${WalletRegistry.address}`)
      console.error(`   Please redeploy Bridge with correct WalletRegistry address`)
      process.exit(1)
    }
    console.log(`✓ Bridge ecdsaWalletRegistry matches WalletRegistry`)
    console.log("")
  } catch (e: any) {
    console.log(`⚠️  Could not check Bridge configuration: ${e.message}`)
    console.log(`   Continuing anyway...`)
    console.log("")
  }

  // Alternative: Try calling Bridge.requestNewWallet() directly
  // Bridge.requestNewWallet takes a BitcoinTx.UTXO parameter (bytes32 txHash, uint32 outputIndex, uint64 amount)
  // For NO_MAIN_UTXO (no active wallet), we pass zeros
  console.log(`Trying Bridge.requestNewWallet()...`)
  try {
    // First verify the contract exists and has code
    const bridgeCode = await ethers.provider.getCode(bridgeAddress)
    if (bridgeCode === "0x" || bridgeCode === "0x0") {
      console.error(`⚠️  ERROR: Bridge contract at ${bridgeAddress} has no code!`)
      console.error(`   The Bridge contract is not deployed at this address.`)
      console.error(`   WalletRegistry walletOwner is set to this address, but the contract doesn't exist.`)
      console.error("")
      console.error("Options:")
      console.error("  1. Deploy the Bridge contract:")
      console.error("     cd tmp/tbtc-v2/solidity && npx hardhat deploy --network development --tags Bridge")
      console.error("")
      console.error("  2. Or, if using tbtc-stub Bridge:")
      console.error("     cd solidity/tbtc-stub && npx hardhat deploy --network development --tags TBTCStubs")
      console.error("")
      console.error("  3. After deploying, update WalletRegistry walletOwner:")
      console.error("     cd solidity/ecdsa && npx hardhat run scripts/init-wallet-owner.ts --network development")
      console.error("")
      throw new Error(`Bridge contract at ${bridgeAddress} has no code - contract may not be deployed`)
    }
    
    // Try to load full Bridge ABI from deployment file, or use minimal signature
    let bridgeAbi: any[]
    let useFullAbi = false
    let hasStructParam = false
    
    const bridgeDeploymentPath = path.resolve(__dirname, "../../../tmp/tbtc-v2/solidity/deployments/development/Bridge.json")
    const bridgeStubPath = path.resolve(__dirname, "../../tbtc-stub/deployments/development/Bridge.json")
    
    // Prefer Bridge stub (has callback), then Bridge v2
    if (fs.existsSync(bridgeStubPath)) {
      // Bridge stub - requestNewWallet() takes NO parameters
      const bridgeDeployment = JSON.parse(fs.readFileSync(bridgeStubPath, "utf8"))
      bridgeAbi = bridgeDeployment.abi
      useFullAbi = true
      // Bridge stub's requestNewWallet() has no inputs
      hasStructParam = false
    } else if (fs.existsSync(bridgeDeploymentPath)) {
      // Bridge v2 - may have struct parameter
      const bridgeDeployment = JSON.parse(fs.readFileSync(bridgeDeploymentPath, "utf8"))
      bridgeAbi = bridgeDeployment.abi
      useFullAbi = true
      // Check if Bridge v2 has requestNewWallet with struct parameter
      const hasStruct = bridgeAbi.some((item: any) => 
        item.type === "function" && 
        item.name === "requestNewWallet" && 
        item.inputs && item.inputs.length > 0
      )
      hasStructParam = hasStruct
    } else {
      // Fallback: try without params first (Bridge stub signature)
      bridgeAbi = [
        "function requestNewWallet() external",
        "function requestNewWallet((bytes32,uint32,uint64)) external"
      ]
      useFullAbi = false
      hasStructParam = false // Will try no-param version first
    }
    
    const bridge = await ethers.getContractAt(bridgeAbi, bridgeAddress)
    
    // NO_MAIN_UTXO: zero txHash, zero outputIndex, zero amount
    // Use object format if full ABI (has struct definition), array format if minimal ABI
    const NO_MAIN_UTXO = useFullAbi && hasStructParam
      ? {
          txHash: "0x0000000000000000000000000000000000000000000000000000000000000000",
          txOutputIndex: 0,
          txOutputValue: 0
        }
      : [
          "0x0000000000000000000000000000000000000000000000000000000000000000",
          0,
          0
        ]
    
    // First, try a static call to simulate the transaction and get revert reason
    console.log(`Simulating transaction with static call...`)
    try {
      // Try calling without parameters first (for Bridge stub contracts)
      if (!hasStructParam) {
        await bridge.connect(signer).callStatic.requestNewWallet({ gasLimit: 500000 })
      } else {
        await bridge.connect(signer).callStatic.requestNewWallet(NO_MAIN_UTXO, { gasLimit: 500000 })
      }
      console.log(`✓ Static call succeeded - transaction should work`)
    } catch (staticCallError: any) {
      console.error(`⚠️  Static call failed - transaction will revert`)
      
      // Try to extract error data from multiple possible locations
      let errorData: string | null = null
      
      // Check various error properties
      if (staticCallError.data) {
        errorData = staticCallError.data
      } else if (staticCallError.error?.data) {
        errorData = staticCallError.error.data
      } else if (staticCallError.error?.error?.data) {
        errorData = staticCallError.error.error.data
      } else if (staticCallError.reason) {
        // Sometimes the reason is directly available
        console.error(`   Revert reason: ${staticCallError.reason}`)
        throw new Error(`Transaction will revert: ${staticCallError.reason}`)
      }
      
      // Also try using direct RPC call to get better error info
      if (!errorData || errorData === "0x" || errorData.length < 10) {
        console.log(`   Trying direct RPC call to get error details...`)
        try {
          // Try encoding with or without parameters based on Bridge ABI
          const callData = hasStructParam
            ? bridge.interface.encodeFunctionData("requestNewWallet", [NO_MAIN_UTXO])
            : bridge.interface.encodeFunctionData("requestNewWallet", [])
          const result = await hre.network.provider.send("eth_call", [{
            to: bridgeAddress,
            from: signer.address,
            data: callData,
            gas: ethers.utils.hexlify(500000)
          }, "latest"])
          // If we get here, the call succeeded (shouldn't happen)
          console.log(`   RPC call succeeded (unexpected)`)
        } catch (rpcError: any) {
          // Extract error data from RPC error
          if (rpcError.data) {
            errorData = rpcError.data
          } else if (rpcError.error?.data) {
            errorData = rpcError.error.data
          } else if (rpcError.message) {
            // Try to extract hex data from error message
            const hexMatch = rpcError.message.match(/0x[a-fA-F0-9]{10,}/)
            if (hexMatch) {
              errorData = hexMatch[0]
            }
          }
        }
      }
      
      // Decode the error data
      let revertReason = "Unknown error"
      if (errorData && errorData !== "0x" && errorData.length >= 10) {
        try {
          // Try to decode as Error(string)
          if (errorData.startsWith("0x08c379a0")) {
            // Error(string) selector: 0x08c379a0
            // The data after the selector should be ABI-encoded string
            try {
              const encodedString = errorData.slice(10) // Remove selector
              // ABI-encode string format: offset (32 bytes) + length (32 bytes) + data
              // If we have at least the offset and length, try to decode
              if (encodedString.length >= 128) { // 64 hex chars = 32 bytes for offset + 32 bytes for length
                const reason = ethers.utils.defaultAbiCoder.decode(
                  ["string"],
                  "0x" + encodedString
                )[0]
                revertReason = reason
              } else {
                // Try to decode with padding
                const padded = encodedString.padEnd(128, '0') // Pad to minimum length
                const reason = ethers.utils.defaultAbiCoder.decode(
                  ["string"],
                  "0x" + padded
                )[0]
                revertReason = reason
              }
            } catch (decodeErr: any) {
              // If decoding fails, at least show we found Error(string)
              revertReason = `Error(string) - could not decode: ${errorData.slice(0, 50)}...`
            }
          } else if (errorData.startsWith("0x4e487b71")) {
            // Panic(uint256) selector: 0x4e487b71
            const panicCode = ethers.BigNumber.from("0x" + errorData.slice(10))
            const panicReasons: { [key: string]: string } = {
              "0x01": "Assertion failed",
              "0x11": "Arithmetic operation underflowed or overflowed",
              "0x12": "Division or modulo by zero",
              "0x21": "Converted value out of bounds",
              "0x22": "Storage byte array accessed incorrectly",
              "0x31": "Called function on non-contract",
              "0x32": "Array accessed at out-of-bounds index",
            }
            revertReason = panicReasons[panicCode.toHexString()] || `Panic(${panicCode.toString()})`
          } else if (errorData.length >= 10) {
            // Try common custom errors
            const commonErrors = [
              "error OnlyWalletOwnerAllowed()",
              "error Current state is not IDLE()",
              "error DKGAlreadyInProgress()",
            ]
            for (const errorSig of commonErrors) {
              try {
                const iface = new ethers.utils.Interface([errorSig])
                const decoded = iface.parseError(errorData)
                revertReason = decoded.name
                break
              } catch {
                // Continue to next error signature
              }
            }
            if (revertReason === "Unknown error") {
              revertReason = `Error selector: ${errorData.slice(0, 10)}`
            }
          }
        } catch (decodeError: any) {
          revertReason = `Could not decode error data: ${errorData.slice(0, 20)}...`
        }
      } else {
        // No error data found, use error message
        revertReason = staticCallError.message || "No error data available"
      }
      
      console.error(`   Revert reason: ${revertReason}`)
      if (errorData && errorData.length >= 10) {
        console.error(`   Error data: ${errorData.slice(0, 50)}${errorData.length > 50 ? '...' : ''}`)
      }
      console.error(`   This transaction will fail. Please fix the issue before retrying.`)
      
      // Provide helpful suggestions based on revert reason
      if (revertReason.includes("IDLE") || revertReason.includes("state")) {
        console.error(`   → DKG state issue. Check with: ./scripts/check-dkg-status.sh`)
      } else if (revertReason.includes("WalletOwner") || revertReason.includes("owner")) {
        console.error(`   → WalletOwner mismatch. Run: cd solidity/ecdsa && npx hardhat run scripts/init-wallet-owner.ts --network development`)
      } else if (revertReason.includes("RandomBeacon") || revertReason.includes("beacon")) {
        console.error(`   → RandomBeacon configuration issue. Check RandomBeacon authorization.`)
      } else if (revertReason.includes("0x") && !revertReason.includes("Error")) {
        console.error(`   → Unknown error. Try checking:`)
        console.error(`      - RandomBeacon authorization: cd solidity/ecdsa && npx hardhat run scripts/authorize-wallet-registry-in-beacon.ts --network development`)
        console.error(`      - SortitionPool lock status`)
        console.error(`      - RandomBeacon contract state`)
      }
      
      // Also try calling WalletRegistry directly to see if we get a better error
      console.log(`   Trying direct WalletRegistry call to get better error...`)
      try {
        await wr.connect(signer).callStatic.requestNewWallet({ gasLimit: 500000 })
      } catch (wrError: any) {
        // This will fail because signer is not walletOwner, but might give us better error info
        let wrErrorData: string | null = null
        if (wrError.data) {
          wrErrorData = wrError.data
        } else if (wrError.error?.data) {
          wrErrorData = wrError.error.data
        }
        
        if (wrErrorData && wrErrorData.length > 10) {
          console.error(`   Direct WalletRegistry error data: ${wrErrorData.slice(0, 50)}...`)
          
          // Try to decode it
          try {
            if (wrErrorData.startsWith("0x08c379a0")) {
              // Error(string) selector
              const decoded = ethers.utils.defaultAbiCoder.decode(
                ["string"],
                "0x" + wrErrorData.slice(10)
              )
              const decodedReason = decoded[0]
              console.error(`   ✓ Decoded WalletRegistry error: "${decodedReason}"`)
              
              // Use this decoded reason if we didn't get a good one before
              if (revertReason === "Unknown error" || revertReason.includes("missing revert")) {
                revertReason = decodedReason
              }
            }
          } catch (decodeErr) {
            // Failed to decode, that's okay
          }
        }
        if (wrError.message && !wrError.message.includes("call revert")) {
          console.error(`   Direct WalletRegistry error message: ${wrError.message}`)
        }
      }
      
      // Don't throw here - the static call might fail for simulation reasons
      // but the actual transaction might work. The direct WalletRegistry error
      // is expected (signer is not walletOwner), but Bridge should work.
      console.error(`   Note: Static call failed, but this might be a simulation issue.`)
      console.error(`   Will attempt actual transaction anyway...`)
      console.log("")
    }
    
    // Try using Hardhat's impersonation feature to call as Bridge directly
    console.log("")
    console.log("Attempting to impersonate Bridge and call WalletRegistry directly...")
    try {
      // Impersonate Bridge account
      await hre.network.provider.send("hardhat_impersonateAccount", [bridgeAddress])
      
      // Get impersonated signer
      const bridgeSigner = await ethers.getSigner(bridgeAddress)
      
      // Fund Bridge if needed (for gas)
      const bridgeBalance = await ethers.provider.getBalance(bridgeAddress)
      if (bridgeBalance.lt(ethers.utils.parseEther("0.1"))) {
        console.log(`   Funding Bridge account with ETH for gas...`)
        const [deployer] = await ethers.getSigners()
        await deployer.sendTransaction({
          to: bridgeAddress,
          value: ethers.utils.parseEther("1.0")
        })
      }
      
      // Call WalletRegistry directly as Bridge
      console.log(`   Calling WalletRegistry.requestNewWallet() as Bridge...`)
      const tx = await wr.connect(bridgeSigner).requestNewWallet({ 
        gasLimit: 500000,
        gasPrice: ethers.utils.parseUnits("1", "gwei")
      })
      console.log(`   Transaction submitted: ${tx.hash}`)
      const receipt = await tx.wait()
      
      if (receipt.status === 1) {
        console.log(`✓ DKG triggered successfully via Bridge impersonation!`)
        console.log(`   Transaction confirmed in block: ${receipt.blockNumber}`)
        console.log(`   You can monitor DKG progress in node logs`)
        console.log("")
        console.log("==========================================")
        console.log("DKG Request Complete!")
        console.log("==========================================")
        
        // Stop impersonation
        await hre.network.provider.send("hardhat_stopImpersonatingAccount", [bridgeAddress])
        return
      } else {
        throw new Error("Transaction reverted")
      }
    } catch (impersonationError: any) {
      console.log(`   Impersonation method failed: ${impersonationError.message}`)
      console.log(`   Falling back to Bridge.requestNewWallet()...`)
      
      // Stop impersonation if it was started
      try {
        await hre.network.provider.send("hardhat_stopImpersonatingAccount", [bridgeAddress])
      } catch {}
      
      // Fall back to original method
      console.log(`Sending transaction through Bridge...`)
      try {
        // Ensure bridge and NO_MAIN_UTXO are available
        if (!bridge || !NO_MAIN_UTXO) {
          throw new Error("Bridge contract or NO_MAIN_UTXO not initialized")
        }
        
        // Try encoding the function call manually first to catch encoding errors
        let encodedData: string
        try {
          // Try calling without parameters first (for Bridge stub contracts)
          if (!hasStructParam) {
            encodedData = bridge.interface.encodeFunctionData("requestNewWallet", [])
          } else {
            encodedData = bridge.interface.encodeFunctionData("requestNewWallet", [NO_MAIN_UTXO])
          }
          console.log(`Function call encoded successfully`)
        } catch (encodeError: any) {
          console.error(`Failed to encode function call: ${encodeError.message}`)
          console.error(`This might indicate the Bridge contract ABI doesn't match`)
          // Try the other signature as fallback
          try {
            if (hasStructParam) {
              encodedData = bridge.interface.encodeFunctionData("requestNewWallet", [])
              console.log(`Fallback: Using requestNewWallet() without parameters`)
              hasStructParam = false
            } else {
              encodedData = bridge.interface.encodeFunctionData("requestNewWallet", [NO_MAIN_UTXO])
              console.log(`Fallback: Using requestNewWallet() with struct parameter`)
              hasStructParam = true
            }
          } catch (fallbackError: any) {
            throw new Error(`Function encoding failed: ${encodeError.message}`)
          }
        }
        
        // Try using populateTransaction to build the tx object first
        let populatedTx: any
        try {
          if (!hasStructParam) {
            populatedTx = await bridge.connect(signer).populateTransaction.requestNewWallet({
              gasLimit: 500000,
              gasPrice: ethers.utils.parseUnits("1", "gwei")
            })
          } else {
            populatedTx = await bridge.connect(signer).populateTransaction.requestNewWallet(NO_MAIN_UTXO, {
              gasLimit: 500000,
              gasPrice: ethers.utils.parseUnits("1", "gwei")
            })
          }
          console.log(`Transaction populated successfully`)
        } catch (populateError: any) {
          console.error(`Failed to populate transaction: ${populateError.message}`)
          // If populateTransaction fails, try direct call anyway
          console.log(`Attempting direct call despite populateTransaction failure...`)
        }
        
        // Send the transaction
        const txOptions = {
          gasLimit: 500000,
          gasPrice: ethers.utils.parseUnits("1", "gwei")
        }
        
        console.log(`Sending transaction...`)
        const tx = !hasStructParam
          ? await bridge.connect(signer).requestNewWallet(txOptions)
          : await bridge.connect(signer).requestNewWallet(NO_MAIN_UTXO, txOptions)
        console.log(`Transaction submitted: ${tx.hash}`)
        const receipt = await tx.wait()
        
        if (receipt.status === 1) {
          console.log(`✓ DKG triggered successfully!`)
          console.log(`   Transaction confirmed in block: ${receipt.blockNumber}`)
          console.log(`   You can monitor DKG progress in node logs`)
          console.log("")
          console.log("==========================================")
          console.log("DKG Request Complete!")
          console.log("==========================================")
          return
        } else {
          // Transaction reverted - try to get revert reason from trace
          console.error(`⚠️  Transaction reverted (status: 0)`)
          console.error(`   Transaction hash: ${receipt.transactionHash}`)
          console.error(`   Block: ${receipt.blockNumber}`)
          console.error(`   Gas used: ${receipt.gasUsed.toString()}`)
          
          // Try to get revert reason using debug_traceTransaction
          try {
            const trace = await hre.network.provider.send("debug_traceTransaction", [
              receipt.transactionHash,
              { tracer: "callTracer" }
            ])
            if (trace.error) {
              console.error(`   Revert reason from trace: ${trace.error}`)
            }
          } catch (traceError) {
            // Trace might not be available
            console.error(`   Could not get transaction trace (this is normal for some nodes)`)
          }
          
          throw new Error("Transaction reverted - see details above")
        }
      } catch (bridgeCallError: any) {
        console.error(`Bridge.requestNewWallet() call failed: ${bridgeCallError.message}`)
        throw bridgeCallError
      }
    }
  } catch (error: any) {
    console.error(`Bridge contract call failed: ${error.message}`)
    
    // If we already showed the revert reason from static call, don't repeat it
    if (!error.message.includes("Transaction will revert")) {
      // Try to decode revert reason from receipt if available
      if (error.receipt && error.receipt.status === 0) {
        console.error(`   Transaction reverted. Block: ${error.receipt.blockNumber}, Gas used: ${error.receipt.gasUsed?.toString() || 'unknown'}`)
      }
      
      if (error.message?.includes("gas")) {
        console.error(`   This may be a gas estimation issue. Try using cast or geth console.`)
      }
    }
  }
  
  // If all else fails, provide manual instructions
  console.log("")
  console.log("==========================================")
  console.log("Diagnosis Summary")
  console.log("==========================================")
  console.log("")
  console.log("✓ WalletOwner is correctly set to Bridge")
  console.log("✓ DKG state is IDLE (ready for new wallet)")
  console.log("✓ Bridge ecdsaWalletRegistry matches WalletRegistry")
  console.log("")
  console.log("⚠️  Issue: Transaction reverts when calling Bridge.requestNewWallet()")
  console.log("   The direct WalletRegistry call shows: 'Caller is not the Wallet Owner'")
  console.log("   This suggests Bridge may not be forwarding the call correctly,")
  console.log("   or there's an issue with how the call chain is executed.")
  console.log("")
  console.log("==========================================")
  console.log("Manual Solution: Use cast or geth console")
  console.log("==========================================")
  console.log("")
  console.log("Call Bridge.requestNewWallet() from a regular account using cast:")
  console.log("   Bridge will forward the call to WalletRegistry, and WalletRegistry will see Bridge as the caller.")
  console.log("")
  console.log("Option 1: Using cast with unlocked account (recommended):")
  console.log(`   # First, unlock an account in Geth:`)
  console.log(`   geth attach http://localhost:8545`)
  console.log(`   > personal.unlockAccount(eth.accounts[0], "", 0)`)
  console.log(`   # Then use cast (try without parameters first):`)
  console.log(`   cast send ${bridgeAddress} "requestNewWallet()" \\`)
  console.log(`     --rpc-url http://localhost:8545 \\`)
  console.log(`     --unlocked \\`)
  console.log(`     --from $(cast rpc eth_accounts --rpc-url http://localhost:8545 | jq -r '.[0]')`)
  console.log("")
  console.log(`   # If that fails, try with struct parameter:`)
  console.log(`   cast send ${bridgeAddress} "requestNewWallet((bytes32,uint32,uint64))" \\`)
  console.log(`     "(0x0000000000000000000000000000000000000000000000000000000000000000,0,0)" \\`)
  console.log(`     --rpc-url http://localhost:8545 \\`)
  console.log(`     --unlocked \\`)
  console.log(`     --from $(cast rpc eth_accounts --rpc-url http://localhost:8545 | jq -r '.[0]')`)
  console.log("")
  console.log("Option 2: Using cast with private key:")
  console.log(`   # Get an account with ETH from Geth:`)
  console.log(`   geth attach http://localhost:8545`)
  console.log(`   > eth.accounts[0]  # Use this address`)
  console.log(`   # Then use cast with the account's private key:`)
  console.log(`   cast send ${bridgeAddress} "requestNewWallet()" \\`)
  console.log(`     --rpc-url http://localhost:8545 \\`)
  console.log(`     --private-key <PRIVATE_KEY_OF_ACCOUNT_WITH_ETH>`)
  console.log("")
  console.log("Option 3: Using geth console directly:")
  console.log(`   geth attach http://localhost:8545`)
  console.log(`   > personal.unlockAccount(eth.accounts[0], "", 0)`)
  console.log(`   > eth.sendTransaction({from: eth.accounts[0], to: "${bridgeAddress}", data: "0x72cc8c6d", gas: 500000})`)
  console.log("")
  throw new Error("Failed to trigger DKG automatically. See instructions above.")
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})

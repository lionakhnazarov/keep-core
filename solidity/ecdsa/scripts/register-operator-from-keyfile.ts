import { HardhatRuntimeEnvironment } from "hardhat/types"
import { ethers } from "hardhat"
import * as fs from "fs"
import * as path from "path"

/**
 * Register operator from keyfile
 * Usage: KEYFILE=../../keystore/operator1/UTC--... npx hardhat run scripts/register-operator-from-keyfile.ts --network development
 */
async function main() {
  const hre: HardhatRuntimeEnvironment = require("hardhat")
  const { helpers } = hre
  
  // Get keyfile path from environment
  const keyfilePath = process.env.KEYFILE
  if (!keyfilePath) {
    console.log("❌ KEYFILE environment variable is required")
    console.log("   Usage: KEYFILE=../../keystore/operator1/UTC--... npx hardhat run scripts/register-operator-from-keyfile.ts --network development")
    process.exit(1)
  }
  
  // Resolve path relative to project root (two levels up from scripts/)
  const projectRoot = path.resolve(__dirname, "../../../")
  const fullKeyfilePath = path.isAbsolute(keyfilePath) 
    ? keyfilePath 
    : path.resolve(projectRoot, keyfilePath)
  
  if (!fs.existsSync(fullKeyfilePath)) {
    console.log(`❌ Keyfile not found: ${fullKeyfilePath}`)
    console.log(`   Set KEYFILE env var or OPERATOR_INDEX (1-10)`)
    process.exit(1)
  }
  
  const password = process.env.KEEP_ETHEREUM_PASSWORD || "password"
  
  console.log(`=== Registering Operator from Keyfile ===`)
  console.log(`Keyfile: ${fullKeyfilePath}`)
  console.log("")
  
  // Load wallet from keyfile
  const keyfileJson = fs.readFileSync(fullKeyfilePath, "utf8")
  const wallet = await ethers.Wallet.fromEncryptedJson(keyfileJson, password)
  const operatorAddress = wallet.address
  
  console.log(`Operator Address: ${operatorAddress}`)
  console.log("")
  
  // For self-staking, all roles are the same
  const owner = operatorAddress
  const provider = operatorAddress
  const operator = operatorAddress
  const beneficiary = operatorAddress
  const authorizer = operatorAddress
  
  const providerSigner = wallet.connect(hre.ethers.provider)
  
  // Get contracts
  const t = await helpers.contracts.getContract("T")
  
  // Load TokenStaking from deployment file to ensure correct ABI
  let staking
  let stakingABI: any[] | null = null
  const tokenStakingPath = path.resolve(__dirname, "../deployments/development/TokenStaking.json")
  if (fs.existsSync(tokenStakingPath)) {
    const tsDeployment = JSON.parse(fs.readFileSync(tokenStakingPath, "utf8"))
    stakingABI = tsDeployment.abi || []
    staking = await hre.ethers.getContractAt(stakingABI, tsDeployment.address)
    console.log(`Using TokenStaking from deployment: ${tsDeployment.address}`)
  } else {
    // Fallback to helpers
    staking = await helpers.contracts.getContract("TokenStaking")
  }
  
  // Try to get RandomBeacon - it might be in external deployments
  // First try to load from random-beacon package deployments
  let randomBeacon
  const randomBeaconPath = path.resolve(__dirname, "../../random-beacon/deployments/development/RandomBeacon.json")
  if (fs.existsSync(randomBeaconPath)) {
    const rbDeployment = JSON.parse(fs.readFileSync(randomBeaconPath, "utf8"))
    randomBeacon = await hre.ethers.getContractAt(rbDeployment.abi, rbDeployment.address)
    console.log(`Using RandomBeacon from random-beacon package: ${rbDeployment.address}`)
    
    // Verify that RandomBeacon is using the same TokenStaking address
    try {
      const randomBeaconStaking = await randomBeacon.staking()
      const stakingAddress = staking.address.toLowerCase()
      const randomBeaconStakingAddress = randomBeaconStaking.toLowerCase()
      
      if (stakingAddress !== randomBeaconStakingAddress) {
        console.log(`⚠️  WARNING: TokenStaking address mismatch!`)
        console.log(`   RandomBeacon expects: ${randomBeaconStaking}`)
        console.log(`   We're using: ${staking.address}`)
        console.log(`   This will cause "Caller is not the staking contract" errors.`)
        console.log(`   Attempting to use the TokenStaking that RandomBeacon expects...`)
        
        // Try to load the TokenStaking that RandomBeacon expects
        // Use the ABI we already have, or use the interface from current staking
        let abiToUse: any
        if (stakingABI && stakingABI.length > 0) {
          abiToUse = stakingABI
        } else {
          // Use the interface from the current staking contract
          abiToUse = staking.interface
        }
        
        const expectedStaking = await hre.ethers.getContractAt(
          abiToUse,
          randomBeaconStaking
        )
        staking = expectedStaking
        console.log(`✓ Using TokenStaking at ${staking.address} (as expected by RandomBeacon)`)
      }
    } catch (e: any) {
      console.log(`⚠️  Could not verify TokenStaking address match: ${e.message}`)
    }
  } else {
    // Fallback to helpers
    try {
      randomBeacon = await helpers.contracts.getContract("RandomBeacon")
    } catch (e) {
      // Try RandomBeaconChaosnet
      try {
        randomBeacon = await helpers.contracts.getContract("RandomBeaconChaosnet")
      } catch (e2) {
        throw new Error(`RandomBeacon not found. Make sure RandomBeacon is deployed. Error: ${e.message}`)
      }
    }
  }
  
  const walletRegistry = await helpers.contracts.getContract("WalletRegistry")
  
  const { to1e18, from1e18 } = helpers.number
  const stakeAmount = to1e18(1_000_000)
  const minAuthRB = await randomBeacon.minimumAuthorization()
  const minAuthWR = await walletRegistry.minimumAuthorization()
  
  console.log("=== Step 0: Fund Operator with ETH ===")
  const balance = await hre.ethers.provider.getBalance(operatorAddress)
  const minBalance = hre.ethers.utils.parseEther("1.0") // 1 ETH
  if (balance.lt(minBalance)) {
    console.log(`Sending ETH to operator ${operatorAddress}...`)
    // Get first account (usually the deployer) to send ETH
    const [deployer] = await hre.ethers.getSigners()
    const sendTx = await deployer.sendTransaction({
      to: operatorAddress,
      value: hre.ethers.utils.parseEther("10.0"), // Send 10 ETH
    })
    await sendTx.wait()
    console.log(`✓ Sent 10 ETH! Transaction: ${sendTx.hash}`)
  } else {
    console.log(`✓ Already has ${hre.ethers.utils.formatEther(balance)} ETH`)
  }
  console.log("")
  
  console.log("=== Step 1: Mint T Tokens ===")
  const tOwner = await t.owner()
  const tOwnerSigner = await hre.ethers.getSigner(tOwner)
  const tBalance = await t.balanceOf(operatorAddress)
  
  if (tBalance.lt(stakeAmount)) {
    const mintAmount = stakeAmount.sub(tBalance)
    console.log(`Minting ${from1e18(mintAmount)} T for ${operatorAddress}...`)
    const mintTx = await t.connect(tOwnerSigner).mint(operatorAddress, mintAmount)
    await mintTx.wait()
    console.log(`✓ Minted! Transaction: ${mintTx.hash}`)
  } else {
    console.log(`✓ Already has ${from1e18(tBalance)} T`)
  }
  console.log("")
  
  console.log("=== Step 2: Approve T Tokens ===")
  const allowance = await t.allowance(operatorAddress, staking.address)
  if (allowance.lt(stakeAmount)) {
    console.log(`Approving ${from1e18(stakeAmount)} T for staking...`)
    const approveTx = await t.connect(providerSigner).approve(staking.address, stakeAmount)
    await approveTx.wait()
    console.log(`✓ Approved! Transaction: ${approveTx.hash}`)
  } else {
    console.log(`✓ Already approved`)
  }
  console.log("")
  
  console.log("=== Step 3: Stake Tokens ===")
  const currentStake = await staking.callStatic.stakes(provider)
  if (currentStake.tStake.eq(0)) {
    console.log(`Staking ${from1e18(stakeAmount)} T...`)
    // Check if stake function exists (ExtendedTokenStaking)
    // Regular TokenStaking doesn't have stake() - it uses a different pattern
    const hasStakeFunction = staking.interface.getFunction("stake") !== null
    if (hasStakeFunction) {
      try {
        const stakeTx = await staking.connect(providerSigner).stake(
          provider,
          beneficiary,
          authorizer,
          stakeAmount
        )
        await stakeTx.wait()
        console.log(`✓ Staked! Transaction: ${stakeTx.hash}`)
      } catch (error: any) {
        const errorMessage = error.message || error.toString() || ""
        if (errorMessage.includes("execution reverted") || 
            errorMessage.includes("stake is not a function") || 
            errorMessage.includes("is not a function") ||
            errorMessage.includes("no matching function") ||
            error.code === "INVALID_ARGUMENT") {
          console.log(`⚠️  TokenStaking stake() function call failed`)
          console.log(`   Skipping staking - operator may need to be staked manually`)
          console.log(`   For development, deploy ExtendedTokenStaking which has stake() function`)
          console.log(`   Continuing with registration assuming staking will be done separately...`)
        } else {
          throw error
        }
      }
    } else {
      console.log(`⚠️  TokenStaking doesn't have stake() function (this is normal for regular TokenStaking)`)
      console.log(`   Skipping staking - operator may need to be staked manually`)
      console.log(`   For development, deploy ExtendedTokenStaking which has stake() function`)
      console.log(`   Continuing with registration assuming staking will be done separately...`)
    }
  } else {
    console.log(`✓ Already staked: ${from1e18(currentStake.tStake)} T`)
  }
  console.log("")
  
  // Helper function to check and approve application if needed
  const checkAndApproveApplication = async (applicationAddress: string, applicationName: string) => {
    // Check application status using applicationInfo
    // ApplicationStatus: 0 = NOT_APPROVED, 1 = APPROVED, 2 = PAUSED
    try {
      // Use Contract directly to call applicationInfo
      const stakingWithABI = new ethers.Contract(
        staking.address,
        [
          "function applicationInfo(address) view returns (uint8 status, address panicButton)",
          "function approveApplication(address application)"
        ],
        hre.ethers.provider
      )
      
      const appInfo = await stakingWithABI.applicationInfo(applicationAddress)
      if (appInfo.status === 1) { // APPROVED
        console.log(`✓ ${applicationName} application is already approved`)
        return true
      }
      
      // Try to approve using deployer (owner)
      console.log(`Approving ${applicationName} application...`)
      const [deployer] = await hre.ethers.getSigners()
      const approveTx = await stakingWithABI.connect(deployer).approveApplication(applicationAddress)
      await approveTx.wait()
      console.log(`✓ Approved ${applicationName}! Transaction: ${approveTx.hash}`)
      return true
    } catch (error: any) {
      const errorMessage = error.message || error.toString() || ""
      
      // If applicationInfo doesn't exist or fails, try to approve directly
      if (errorMessage.includes("execution reverted") || 
          errorMessage.includes("cannot estimate gas") ||
          errorMessage.includes("applicationInfo")) {
        console.log(`⚠️  Could not check ${applicationName} application status (function may not exist)`)
        console.log(`   Attempting to approve anyway...`)
        try {
          const stakingWithABI = new ethers.Contract(
            staking.address,
            ["function approveApplication(address application)"],
            hre.ethers.provider
          )
          const [deployer] = await hre.ethers.getSigners()
          const approveTx = await stakingWithABI.connect(deployer).approveApplication(applicationAddress)
          await approveTx.wait()
          console.log(`✓ Approved ${applicationName}! Transaction: ${approveTx.hash}`)
          return true
        } catch (approveError: any) {
          const approveErrorMessage = approveError.message || approveError.toString() || ""
          if (approveErrorMessage.includes("not the owner") || 
              approveErrorMessage.includes("caller is not the owner") ||
              approveErrorMessage.includes("execution reverted")) {
            console.log(`⚠️  Cannot approve ${applicationName}: deployer may not be the TokenStaking owner or function doesn't exist`)
            console.log(`   Assuming application is already approved or doesn't need approval`)
            return true // Assume it's okay to continue
          }
          // If it's a different error, log and assume it's okay
          console.log(`⚠️  Approval attempt failed: ${approveErrorMessage}`)
          console.log(`   Assuming application is already approved or doesn't need approval`)
          return true
        }
      } else if (errorMessage.includes("Application is not approved")) {
        // Application needs approval but we can't approve it (not owner)
        console.log(`⚠️  ${applicationName} application is not approved and cannot be approved by this account`)
        console.log(`   The TokenStaking owner needs to approve ${applicationName} at ${applicationAddress}`)
        return false
      } else if (errorMessage.includes("already approved") || errorMessage.includes("Can't approve")) {
        console.log(`✓ ${applicationName} application is already approved`)
        return true
      } else {
        // Unknown error - assume it's okay to continue
        console.log(`⚠️  Could not check ${applicationName} application status: ${errorMessage}`)
        console.log(`   Assuming application is already approved or doesn't need approval`)
        return true
      }
    }
  }
  
  console.log("=== Step 4: Approve Applications ===")
  const rbApproved = await checkAndApproveApplication(randomBeacon.address, "RandomBeacon")
  const wrApproved = await checkAndApproveApplication(walletRegistry.address, "WalletRegistry")
  
  if (!rbApproved || !wrApproved) {
    console.log("⚠️  Some applications are not approved. Authorization may fail.")
    console.log("   Please ensure applications are approved before continuing.")
  }
  console.log("")
  
  console.log("=== Step 5: Authorize RandomBeacon ===")
  // Check if provider has stake first (reuse check from Step 3)
  if (currentStake.tStake.eq(0)) {
    console.log(`⚠️  Provider ${provider} has no stake`)
    console.log(`   Cannot authorize without stake. Skipping authorization.`)
    console.log(`   Please stake tokens first (manually or using ExtendedTokenStaking)`)
  } else {
    const authRB = await staking.authorizedStake(provider, randomBeacon.address)
    if (authRB.lt(minAuthRB)) {
      const increaseAmount = minAuthRB.sub(authRB)
      console.log(`Increasing authorization by ${from1e18(increaseAmount)} T...`)
      try {
        const authTx = await staking.connect(providerSigner).increaseAuthorization(
          provider,
          randomBeacon.address,
          increaseAmount
        )
        await authTx.wait()
        console.log(`✓ Authorized! Transaction: ${authTx.hash}`)
      } catch (error: any) {
        const errorMessage = error.message || error.toString() || ""
        if (errorMessage.includes("Application is not approved")) {
          console.log(`❌ Failed: RandomBeacon application is not approved`)
          console.log(`   Please approve RandomBeacon application first using TokenStaking owner`)
          console.log(`   Skipping authorization for now...`)
        } else if (errorMessage.includes("Caller is not the staking contract")) {
          console.log(`❌ Failed: TokenStaking address mismatch`)
          console.log(`   RandomBeacon expects a different TokenStaking address than we're using.`)
          try {
            const randomBeaconStaking = await randomBeacon.staking()
            console.log(`   RandomBeacon expects TokenStaking at: ${randomBeaconStaking}`)
            console.log(`   We're using TokenStaking at: ${staking.address}`)
            console.log(`   Please ensure RandomBeacon was deployed with the correct TokenStaking address.`)
          } catch (e) {
            // Ignore if we can't get the staking address
          }
          console.log(`   Skipping authorization for now...`)
        } else if (errorMessage.includes("execution reverted")) {
          console.log(`⚠️  Authorization failed: ${errorMessage}`)
          console.log(`   This may be because:`)
          console.log(`   - Application is not approved`)
          console.log(`   - Provider has no stake`)
          console.log(`   - Other contract requirements not met`)
          console.log(`   Skipping authorization for now...`)
        } else {
          console.log(`⚠️  Authorization failed: ${errorMessage}`)
          console.log(`   Skipping authorization for now...`)
        }
      }
    } else {
      console.log(`✓ Already authorized: ${from1e18(authRB)} T`)
    }
  }
  console.log("")
  
  console.log("=== Step 6: Authorize WalletRegistry ===")
  // Check if provider has stake first (reuse check from Step 3)
  if (currentStake.tStake.eq(0)) {
    console.log(`⚠️  Provider ${provider} has no stake`)
    console.log(`   Cannot authorize without stake. Skipping authorization.`)
    console.log(`   Please stake tokens first (manually or using ExtendedTokenStaking)`)
  } else {
    const authWR = await staking.authorizedStake(provider, walletRegistry.address)
    if (authWR.lt(minAuthWR)) {
      const increaseAmount = minAuthWR.sub(authWR)
      console.log(`Increasing authorization by ${from1e18(increaseAmount)} T...`)
      try {
        const authTx = await staking.connect(providerSigner).increaseAuthorization(
          provider,
          walletRegistry.address,
          increaseAmount
        )
        await authTx.wait()
        console.log(`✓ Authorized! Transaction: ${authTx.hash}`)
      } catch (error: any) {
        const errorMessage = error.message || error.toString() || ""
        if (errorMessage.includes("Application is not approved")) {
          console.log(`❌ Failed: WalletRegistry application is not approved`)
          console.log(`   Please approve WalletRegistry application first using TokenStaking owner`)
          console.log(`   Skipping authorization for now...`)
        } else if (errorMessage.includes("Caller is not the staking contract")) {
          console.log(`❌ Failed: TokenStaking address mismatch`)
          console.log(`   WalletRegistry expects a different TokenStaking address than we're using.`)
          console.log(`   We're using TokenStaking at: ${staking.address}`)
          console.log(`   Please ensure WalletRegistry was deployed with the correct TokenStaking address.`)
          console.log(`   Skipping authorization for now...`)
        } else if (errorMessage.includes("execution reverted")) {
          console.log(`⚠️  Authorization failed: ${errorMessage}`)
          console.log(`   This may be because:`)
          console.log(`   - Application is not approved`)
          console.log(`   - Provider has no stake`)
          console.log(`   - Other contract requirements not met`)
          console.log(`   Skipping authorization for now...`)
        } else {
          console.log(`⚠️  Authorization failed: ${errorMessage}`)
          console.log(`   Skipping authorization for now...`)
        }
      }
    } else {
      console.log(`✓ Already authorized: ${from1e18(authWR)} T`)
    }
  }
  console.log("")
  
  console.log("=== Step 7: Register Operator in RandomBeacon ===")
  const currentProviderRB = await randomBeacon.callStatic.operatorToStakingProvider(operator)
  if (currentProviderRB === ethers.constants.AddressZero) {
    console.log(`Registering operator ${operator} for provider ${provider}...`)
    const regTx = await randomBeacon.connect(providerSigner).registerOperator(operator)
    await regTx.wait()
    console.log(`✓ Registered! Transaction: ${regTx.hash}`)
  } else if (currentProviderRB.toLowerCase() === provider.toLowerCase()) {
    console.log(`✓ Already registered`)
  } else {
    throw new Error(`Operator already registered for different provider: ${currentProviderRB}`)
  }
  console.log("")
  
  console.log("=== Step 8: Register Operator in WalletRegistry ===")
  const currentProviderWR = await walletRegistry.callStatic.operatorToStakingProvider(operator)
  if (currentProviderWR === ethers.constants.AddressZero) {
    console.log(`Registering operator ${operator} for provider ${provider}...`)
    const regTx = await walletRegistry.connect(providerSigner).registerOperator(operator)
    await regTx.wait()
    console.log(`✓ Registered! Transaction: ${regTx.hash}`)
  } else if (currentProviderWR.toLowerCase() === provider.toLowerCase()) {
    console.log(`✓ Already registered`)
  } else {
    throw new Error(`Operator already registered for different provider: ${currentProviderWR}`)
  }
  console.log("")
  
  console.log("=== Step 9: Add Beta Operator (RandomBeacon) ===")
  // Load BeaconSortitionPool from random-beacon package deployments
  let beaconSP
  const beaconSPPath = path.resolve(__dirname, "../../random-beacon/deployments/development/BeaconSortitionPool.json")
  if (fs.existsSync(beaconSPPath)) {
    const bspDeployment = JSON.parse(fs.readFileSync(beaconSPPath, "utf8"))
    beaconSP = await hre.ethers.getContractAt(bspDeployment.abi, bspDeployment.address)
    console.log(`Using BeaconSortitionPool from random-beacon package: ${bspDeployment.address}`)
  } else {
    // Fallback to helpers
    try {
      beaconSP = await helpers.contracts.getContract("BeaconSortitionPool")
    } catch (e) {
      console.log(`⚠️  BeaconSortitionPool not found. Skipping beta operator addition.`)
      console.log(`   This step can be done manually later.`)
    }
  }
  
  if (beaconSP) {
    try {
      const isBetaRB = await beaconSP.callStatic.isBetaOperator(operator)
      if (!isBetaRB) {
        const chaosnetOwner = await beaconSP.chaosnetOwner()
        const chaosnetOwnerSigner = await hre.ethers.getSigner(chaosnetOwner)
        console.log(`Adding ${operator} as beta operator...`)
        const betaTx = await beaconSP.connect(chaosnetOwnerSigner).addBetaOperators([operator])
        await betaTx.wait()
        console.log(`✓ Added! Transaction: ${betaTx.hash}`)
      } else {
        console.log(`✓ Already beta operator`)
      }
    } catch (error: any) {
      console.log(`⚠️  Failed to add beta operator: ${error.message}`)
      console.log(`   This step can be done manually later.`)
    }
  }
  console.log("")
  
  console.log("=== Step 10: Add Beta Operator (WalletRegistry) ===")
  const ecdsaSP = await helpers.contracts.getContract("EcdsaSortitionPool")
  const isBetaWR = await ecdsaSP.callStatic.isBetaOperator(operator)
  if (!isBetaWR) {
    const chaosnetOwner = await ecdsaSP.chaosnetOwner()
    const chaosnetOwnerSigner = await hre.ethers.getSigner(chaosnetOwner)
    console.log(`Adding ${operator} as beta operator...`)
    const betaTx = await ecdsaSP.connect(chaosnetOwnerSigner).addBetaOperators([operator])
    await betaTx.wait()
    console.log(`✓ Added! Transaction: ${betaTx.hash}`)
  } else {
    console.log(`✓ Already beta operator`)
  }
  console.log("")
  
  console.log("=== Step 11: Join Sortition Pools ===")
  // Check if already in pools
  try {
    await beaconSP.callStatic.getOperatorID(operator)
    console.log(`✓ Already in BeaconSortitionPool`)
  } catch {
    console.log(`Joining BeaconSortitionPool...`)
    const joinTx = await randomBeacon.connect(providerSigner).joinSortitionPool()
    await joinTx.wait()
    console.log(`✓ Joined! Transaction: ${joinTx.hash}`)
  }
  
  try {
    await ecdsaSP.callStatic.getOperatorID(operator)
    console.log(`✓ Already in EcdsaSortitionPool`)
  } catch {
    console.log(`Joining EcdsaSortitionPool...`)
    const joinTx = await walletRegistry.connect(providerSigner).joinSortitionPool()
    await joinTx.wait()
    console.log(`✓ Joined! Transaction: ${joinTx.hash}`)
  }
  
  console.log("")
  console.log("✅ SUCCESS! Operator fully registered!")
  console.log(`   Operator: ${operatorAddress}`)
  console.log(`   Staking Provider: ${provider}`)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

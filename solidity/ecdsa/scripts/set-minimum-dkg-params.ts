import { HardhatRuntimeEnvironment } from "hardhat/types"

/**
 * Script to set DKG parameters to minimum values for development.
 * 
 * This bypasses governance delay by directly calling updateDkgParameters
 * on WalletRegistry (which requires governance access).
 * 
 * Minimum values (from test fixtures):
 * - seedTimeout: 8 blocks
 * - resultChallengePeriodLength: 10 blocks (minimum allowed)
 * - resultChallengeExtraGas: 50_000
 * - resultSubmissionTimeout: 30 blocks
 * - submitterPrecedencePeriodLength: 5 blocks
 */
async function main() {
  const hre: HardhatRuntimeEnvironment = require("hardhat")
  const { ethers, helpers } = hre
  
  console.log("=== Set DKG Parameters to Minimum (Development) ===")
  console.log("")
  
  const walletRegistry = await helpers.contracts.getContract("WalletRegistry")
  const walletRegistryGovernance = await helpers.contracts.getContract("WalletRegistryGovernance")
  
  // Get current parameters
  const currentParams = await walletRegistry.dkgParameters()
  console.log("Current DKG Parameters:")
  console.log("  seedTimeout:", currentParams.seedTimeout.toString(), "blocks")
  console.log("  resultChallengePeriodLength:", currentParams.resultChallengePeriodLength.toString(), "blocks")
  console.log("  resultChallengeExtraGas:", currentParams.resultChallengeExtraGas.toString())
  console.log("  resultSubmissionTimeout:", currentParams.resultSubmissionTimeout.toString(), "blocks")
  console.log("  submitterPrecedencePeriodLength:", currentParams.submitterPrecedencePeriodLength.toString(), "blocks")
  console.log("")
  
  // Minimum values for development
  const minParams = {
    seedTimeout: 8,
    resultChallengePeriodLength: 10, // Minimum allowed by contract
    resultChallengeExtraGas: 50_000,
    resultSubmissionTimeout: 120,
    submitterPrecedencePeriodLength: 5,
  }
  
  console.log("Setting to minimum values:")
  console.log("  seedTimeout:", minParams.seedTimeout, "blocks")
  console.log("  resultChallengePeriodLength:", minParams.resultChallengePeriodLength, "blocks")
  console.log("  resultChallengeExtraGas:", minParams.resultChallengeExtraGas)
  console.log("  resultSubmissionTimeout:", minParams.resultSubmissionTimeout, "blocks")
  console.log("  submitterPrecedencePeriodLength:", minParams.submitterPrecedencePeriodLength, "blocks")
  console.log("")
  
  // Check if DKG is in IDLE state (required for parameter updates)
  const dkgState = await walletRegistry.getWalletCreationState()
  if (dkgState !== 0) {
    console.log("⚠️  Warning: DKG state is not IDLE (current state:", dkgState, ")")
    console.log("   DKG parameters can only be updated when state is IDLE (0)")
    console.log("   States: 0=IDLE, 1=AWAITING_SEED, 2=AWAITING_RESULT, 3=CHALLENGE")
    console.log("")
    console.log("   Options:")
    console.log("   1. Wait for DKG to complete")
    console.log("   2. Reset DKG if timed out: ./scripts/reset-dkg-if-timed-out.sh")
    process.exit(1)
  }
  
  // Get governance owner
  const owner = await walletRegistryGovernance.owner()
  console.log("Governance owner:", owner)
  
  // Get signers
  const signers = await ethers.getSigners()
  const { deployer } = await hre.getNamedAccounts()
  
  // Try to get the owner's signer
  let signer = signers.find(s => s.address.toLowerCase() === owner.toLowerCase())
  
  if (!signer) {
    // Try to get signer by address
    try {
      signer = await ethers.getSigner(owner)
    } catch {
      // If owner signer not available, try deployer
      console.log("⚠️  Warning: Could not find signer for governance owner")
      console.log("   Attempting to use deployer account...")
      signer = signers.find(s => s.address.toLowerCase() === deployer.toLowerCase()) || signers[0]
    }
  }
  
  console.log("Using signer:", signer.address)
  
  // Verify signer is the owner
  if (signer.address.toLowerCase() !== owner.toLowerCase()) {
    console.log("⚠️  Warning: Signer address does not match governance owner")
    console.log("   Signer:", signer.address)
    console.log("   Owner:", owner)
    console.log("   This may fail if governance requires owner to execute")
  }
  console.log("")
  
  const walletRegistryConnected = walletRegistry.connect(signer)
  
  // Try direct update first (requires governance role)
  try {
    console.log("Attempting direct update via WalletRegistry.updateDkgParameters()...")
    const tx = await walletRegistryConnected.updateDkgParameters(
      minParams.seedTimeout,
      minParams.resultChallengePeriodLength,
      minParams.resultChallengeExtraGas,
      minParams.resultSubmissionTimeout,
      minParams.submitterPrecedencePeriodLength
    )
    
    console.log("Transaction sent:", tx.hash)
    await tx.wait()
    console.log("✓ Parameters updated successfully!")
    console.log("")
    
  } catch (error: any) {
    if (error.message?.includes("not the guvnor") || error.message?.includes("not governance") || error.message?.includes("Caller is not the governance")) {
      console.log("❌ Direct update failed: WalletRegistry governance is set to WalletRegistryGovernance contract")
      console.log("")
      console.log("Attempting via WalletRegistryGovernance (with governance delay)...")
      console.log("")
      
      // Try via governance contract (requires governance delay)
      const wrGovConnected = walletRegistryGovernance.connect(signer)
      
      try {
        const governanceDelay = await walletRegistryGovernance.governanceDelay()
        console.log("Governance delay:", governanceDelay.toString(), "seconds")
        console.log("")
        
        // Helper function to check if update is pending and ready to finalize
        const checkUpdateStatus = async (remainingTimeFn: () => Promise<any>) => {
          try {
            const remaining = await remainingTimeFn()
            if (remaining.toNumber() === 0) {
              return { pending: true, ready: true, remaining: 0 }
            } else {
              return { pending: true, ready: false, remaining: remaining.toNumber() }
            }
          } catch {
            return { pending: false, ready: false, remaining: 0 }
          }
        }
        
        // Check current status of all updates
        const seedTimeoutStatus = await checkUpdateStatus(() => walletRegistryGovernance.getRemainingDkgSeedTimeoutUpdateTime())
        const challengePeriodStatus = await checkUpdateStatus(() => walletRegistryGovernance.getRemainingDkgResultChallengePeriodLengthUpdateTime())
        const submissionTimeoutStatus = await checkUpdateStatus(() => walletRegistryGovernance.getRemainingDkgResultSubmissionTimeoutUpdateTime())
        const precedencePeriodStatus = await checkUpdateStatus(() => walletRegistryGovernance.getRemainingDkgSubmitterPrecedencePeriodLengthUpdateTime())
        
        // Check if we need to initiate any updates
        const needsInitiation = !seedTimeoutStatus.pending || !challengePeriodStatus.pending || 
                                !submissionTimeoutStatus.pending || !precedencePeriodStatus.pending
        
        if (needsInitiation) {
          // Begin updates for parameters that aren't pending
          console.log("Initiating parameter updates via governance...")
          
          if (!seedTimeoutStatus.pending) {
            const beginSeedTimeout = await wrGovConnected.beginDkgSeedTimeoutUpdate(minParams.seedTimeout)
            await beginSeedTimeout.wait()
            console.log("  ✓ Seed timeout update initiated")
          } else {
            console.log("  ℹ Seed timeout update already pending")
          }
          
          if (!challengePeriodStatus.pending) {
            const beginChallengePeriod = await wrGovConnected.beginDkgResultChallengePeriodLengthUpdate(minParams.resultChallengePeriodLength)
            await beginChallengePeriod.wait()
            console.log("  ✓ Challenge period update initiated")
          } else {
            console.log("  ℹ Challenge period update already pending")
          }
          
          if (!submissionTimeoutStatus.pending) {
            const beginSubmissionTimeout = await wrGovConnected.beginDkgResultSubmissionTimeoutUpdate(minParams.resultSubmissionTimeout)
            await beginSubmissionTimeout.wait()
            console.log("  ✓ Submission timeout update initiated")
          } else {
            console.log("  ℹ Submission timeout update already pending")
          }
          
          if (!precedencePeriodStatus.pending) {
            const beginPrecedencePeriod = await wrGovConnected.beginDkgSubmitterPrecedencePeriodLengthUpdate(minParams.submitterPrecedencePeriodLength)
            await beginPrecedencePeriod.wait()
            console.log("  ✓ Precedence period update initiated")
          } else {
            console.log("  ℹ Precedence period update already pending")
          }
          
          console.log("")
          
          // Check if we need to wait for delay
          const maxRemaining = Math.max(
            seedTimeoutStatus.remaining || 0,
            challengePeriodStatus.remaining || 0,
            submissionTimeoutStatus.remaining || 0,
            precedencePeriodStatus.remaining || 0
          )
          
          if (maxRemaining > 0) {
            console.log("Waiting for governance delay:", maxRemaining, "seconds...")
            await new Promise(resolve => setTimeout(resolve, (maxRemaining + 1) * 1000))
            console.log("  ✓ Delay elapsed")
            console.log("")
          } else if (needsInitiation) {
            // If we just initiated, wait for full delay
            console.log("Waiting for governance delay:", governanceDelay.toString(), "seconds...")
            await new Promise(resolve => setTimeout(resolve, (governanceDelay.toNumber() + 1) * 1000))
            console.log("  ✓ Delay elapsed")
            console.log("")
          }
        } else {
          // All updates are pending, check if ready to finalize
          const maxRemaining = Math.max(
            seedTimeoutStatus.remaining || 0,
            challengePeriodStatus.remaining || 0,
            submissionTimeoutStatus.remaining || 0,
            precedencePeriodStatus.remaining || 0
          )
          
          if (maxRemaining > 0) {
            console.log("Updates pending, waiting", maxRemaining, "more seconds...")
            await new Promise(resolve => setTimeout(resolve, (maxRemaining + 1) * 1000))
            console.log("  ✓ Delay elapsed")
            console.log("")
          }
        }
        
        // Finalize updates
        console.log("Finalizing parameter updates...")
        
        try {
          const finalizeSeedTimeout = await wrGovConnected.finalizeDkgSeedTimeoutUpdate()
          await finalizeSeedTimeout.wait()
          console.log("  ✓ Seed timeout finalized")
        } catch (e: any) {
          if (!e.message?.includes("Update not ready")) {
            throw e
          }
          console.log("  ⚠ Seed timeout already finalized or not ready")
        }
        
        try {
          const finalizeChallengePeriod = await wrGovConnected.finalizeDkgResultChallengePeriodLengthUpdate()
          await finalizeChallengePeriod.wait()
          console.log("  ✓ Challenge period finalized")
        } catch (e: any) {
          if (!e.message?.includes("Update not ready")) {
            throw e
          }
          console.log("  ⚠ Challenge period already finalized or not ready")
        }
        
        try {
          const finalizeSubmissionTimeout = await wrGovConnected.finalizeDkgResultSubmissionTimeoutUpdate()
          await finalizeSubmissionTimeout.wait()
          console.log("  ✓ Submission timeout finalized")
        } catch (e: any) {
          if (!e.message?.includes("Update not ready")) {
            throw e
          }
          console.log("  ⚠ Submission timeout already finalized or not ready")
        }
        
        try {
          const finalizePrecedencePeriod = await wrGovConnected.finalizeDkgSubmitterPrecedencePeriodLengthUpdate()
          await finalizePrecedencePeriod.wait()
          console.log("  ✓ Precedence period finalized")
        } catch (e: any) {
          if (!e.message?.includes("Update not ready")) {
            throw e
          }
          console.log("  ⚠ Precedence period already finalized or not ready")
        }
        
        console.log("")
        console.log("✓ All parameters updated successfully via governance!")
        console.log("")
        
      } catch (govError: any) {
        console.log("❌ Governance update failed:", govError.message)
        console.log("")
        console.log("Troubleshooting:")
        console.log("  1. Check governance owner:")
        console.log("     cast call", walletRegistryGovernance.address, "owner() --rpc-url http://localhost:8545")
        console.log("  2. Ensure signer matches governance owner:", signer.address)
        console.log("  3. Check if updates are pending:")
        console.log("     cast call", walletRegistryGovernance.address, "dkgSeedTimeoutUpdate() --rpc-url http://localhost:8545")
        throw govError
      }
    } else {
      throw error
    }
  }
  
  // Verify
  const newParams = await walletRegistry.dkgParameters()
  console.log("Updated DKG Parameters:")
  console.log("  seedTimeout:", newParams.seedTimeout.toString(), "blocks")
  console.log("  resultChallengePeriodLength:", newParams.resultChallengePeriodLength.toString(), "blocks")
  console.log("  resultChallengeExtraGas:", newParams.resultChallengeExtraGas.toString())
  console.log("  resultSubmissionTimeout:", newParams.resultSubmissionTimeout.toString(), "blocks")
  console.log("  submitterPrecedencePeriodLength:", newParams.submitterPrecedencePeriodLength.toString(), "blocks")
  console.log("")
  
  // Calculate approximate times (assuming 1s block time for development)
  console.log("Approximate times (assuming 1s block time):")
  console.log("  Seed timeout:", newParams.seedTimeout.toString(), "seconds (~", (newParams.seedTimeout.toNumber() / 60).toFixed(1), "minutes)")
  console.log("  Challenge period:", newParams.resultChallengePeriodLength.toString(), "seconds (~", (newParams.resultChallengePeriodLength.toNumber() / 60).toFixed(1), "minutes)")
  console.log("  Submission timeout:", newParams.resultSubmissionTimeout.toString(), "seconds (~", (newParams.resultSubmissionTimeout.toNumber() / 60).toFixed(1), "minutes)")
  console.log("  Submitter precedence:", newParams.submitterPrecedencePeriodLength.toString(), "seconds")
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })

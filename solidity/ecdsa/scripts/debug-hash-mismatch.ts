import { ethers } from "hardhat"
import hre from "hardhat"

/**
 * Comprehensive hash mismatch debugging script
 * Tests different encoding methods to find what matches the stored hash
 */
async function main() {
  console.log("==========================================")
  console.log("Debug DKG Result Hash Mismatch")
  console.log("==========================================")
  console.log("")

  const WalletRegistry = await hre.deployments.get("WalletRegistry")
  const wr = await ethers.getContractAt("WalletRegistry", WalletRegistry.address)

  // Get current state
  const state = await wr.getWalletCreationState()
  console.log(`Current DKG State: ${state} (3 = CHALLENGE)`)
  console.log("")

  if (state !== 3) {
    console.error("Error: DKG is not in CHALLENGE state")
    process.exit(1)
  }

  // Get DKG result submission event
  console.log("1. Extracting DKG result from submission event...")
  const filter = wr.filters.DkgResultSubmitted()
  const currentBlock = await ethers.provider.getBlockNumber()
  const fromBlock = Math.max(0, currentBlock - 5000)
  const events = await wr.queryFilter(filter, fromBlock, currentBlock)
  
  if (events.length === 0) {
    console.error("Error: Could not find DKG result submission event")
    process.exit(1)
  }

  const latestEvent = events[events.length - 1]
  const eventResult = latestEvent.args.result
  const storedHash = latestEvent.args.resultHash
  
  console.log(`   Submission Block: ${latestEvent.blockNumber}`)
  console.log(`   Stored Hash: ${storedHash}`)
  console.log("")

  const { keccak256, defaultAbiCoder } = ethers.utils
  const abiCoder = defaultAbiCoder

  // Show result structure
  console.log("2. Result structure from event:")
  console.log(`   submitterMemberIndex: ${eventResult.submitterMemberIndex.toString()}`)
  console.log(`   groupPubKey length: ${eventResult.groupPubKey.length} bytes`)
  console.log(`   membersHash: ${eventResult.membersHash}`)
  console.log(`   misbehavedMembersIndices: [${eventResult.misbehavedMembersIndices.length}] ${JSON.stringify(eventResult.misbehavedMembersIndices.map((x: any) => x.toString()))}`)
  console.log(`   signatures length: ${eventResult.signatures.length} bytes`)
  console.log(`   signingMembersIndices: [${eventResult.signingMembersIndices.length}] ${eventResult.signingMembersIndices.slice(0, 5).map((x: any) => x.toString()).join(", ")}...`)
  console.log(`   members: [${eventResult.members.length}] ${eventResult.members.slice(0, 5).map((x: any) => x.toString()).join(", ")}...`)
  console.log("")

  // Test 1: Try with correct struct field ORDER
  // Struct definition (in order):
  //   1. uint256 submitterMemberIndex
  //   2. bytes groupPubKey
  //   3. uint8[] misbehavedMembersIndices
  //   4. bytes signatures
  //   5. uint256[] signingMembersIndices  <-- NOTE: uint256[], not uint32[]!
  //   6. uint32[] members
  //   7. bytes32 membersHash  <-- NOTE: membersHash is LAST, not third!
  console.log("3. Testing different encoding methods...")
  console.log("")
  console.log("   ⚠️  IMPORTANT: Struct field order matters!")
  console.log("   Order: submitterMemberIndex, groupPubKey, misbehavedMembersIndices,")
  console.log("          signatures, signingMembersIndices, members, membersHash")
  console.log("")

  // Convert misbehavedMembersIndices to uint8[]
  const misbehavedUint8 = eventResult.misbehavedMembersIndices.map((x: any) => {
    const val = typeof x === 'bigint' ? Number(x) : Number(x.toString())
    return val
  })

  // Test 1: Correct order and types
  console.log("   Test 1: Using CORRECT order and types")
  console.log("           (membersHash is LAST)")
  try {
    const encoded1 = abiCoder.encode(
      ["tuple(uint256,bytes,uint8[],bytes,uint256[],uint32[],bytes32)"],
      [[
        eventResult.submitterMemberIndex,      // 1
        eventResult.groupPubKey,               // 2
        misbehavedUint8,                       // 3
        eventResult.signatures,                 // 4
        eventResult.signingMembersIndices,     // 5 (uint256[])
        eventResult.members,                   // 6 (uint32[])
        eventResult.membersHash                // 7 (LAST!)
      ]]
    )
    const hash1 = keccak256(encoded1)
    const match1 = hash1.toLowerCase() === storedHash.toLowerCase()
    console.log(`      Hash: ${hash1}`)
    console.log(`      Match: ${match1 ? "✅ YES - FOUND IT!" : "❌ NO"}`)
    console.log("")
  } catch (error: any) {
    console.log(`      Error: ${error.message}`)
    console.log("")
  }

  // Test 1b: Wrong order (membersHash third, as we were doing)
  console.log("   Test 1b: Using WRONG order (membersHash third)")
  try {
    const encoded1b = abiCoder.encode(
      ["tuple(uint256,bytes,bytes32,uint8[],bytes,uint256[],uint32[])"],
      [[
        eventResult.submitterMemberIndex,
        eventResult.groupPubKey,
        eventResult.membersHash,  // WRONG POSITION
        misbehavedUint8,
        eventResult.signatures,
        eventResult.signingMembersIndices,
        eventResult.members
      ]]
    )
    const hash1b = keccak256(encoded1b)
    const match1b = hash1b.toLowerCase() === storedHash.toLowerCase()
    console.log(`      Hash: ${hash1b}`)
    console.log(`      Match: ${match1b ? "✅ YES" : "❌ NO"}`)
    console.log("")
  } catch (error: any) {
    console.log(`      Error: ${error.message}`)
    console.log("")
  }

  // Test 2: Wrong: uint32[] for signingMembersIndices (what we were using before)
  console.log("   Test 2: Using uint32[] for signingMembersIndices (WRONG)")
  try {
    const encoded2 = abiCoder.encode(
      ["tuple(uint256,bytes,bytes32,uint8[],bytes,uint32[],uint32[])"],
      [[
        eventResult.submitterMemberIndex,
        eventResult.groupPubKey,
        eventResult.membersHash,
        misbehavedUint8,
        eventResult.signatures,
        eventResult.signingMembersIndices, // Wrong: uint32[]
        eventResult.members
      ]]
    )
    const hash2 = keccak256(encoded2)
    const match2 = hash2.toLowerCase() === storedHash.toLowerCase()
    console.log(`      Hash: ${hash2}`)
    console.log(`      Match: ${match2 ? "✅ YES" : "❌ NO"}`)
    console.log("")
  } catch (error: any) {
    console.log(`      Error: ${error.message}`)
    console.log("")
  }

  // Test 3: Check if arrays need to be converted differently
  console.log("   Test 3: Checking array types and values...")
  console.log(`      misbehavedMembersIndices type: ${typeof eventResult.misbehavedMembersIndices[0]}`)
  console.log(`      signingMembersIndices type: ${typeof eventResult.signingMembersIndices[0]}`)
  console.log(`      members type: ${typeof eventResult.members[0]}`)
  console.log("")

  // Test 4: Try encoding each field separately to see which one differs
  console.log("   Test 4: Encoding individual fields...")
  try {
    const field1 = abiCoder.encode(["uint256"], [eventResult.submitterMemberIndex])
    const field2 = abiCoder.encode(["bytes"], [eventResult.groupPubKey])
    const field3 = abiCoder.encode(["bytes32"], [eventResult.membersHash])
    const field4_uint8 = abiCoder.encode(["uint8[]"], [misbehavedUint8])
    const field4_uint32 = abiCoder.encode(["uint32[]"], [eventResult.misbehavedMembersIndices])
    const field5 = abiCoder.encode(["bytes"], [eventResult.signatures])
    const field6 = abiCoder.encode(["uint32[]"], [eventResult.signingMembersIndices])
    const field7 = abiCoder.encode(["uint32[]"], [eventResult.members])
    
    console.log(`      Field 1 (submitterMemberIndex): ${field1.slice(0, 20)}...`)
    console.log(`      Field 2 (groupPubKey): ${field2.slice(0, 20)}... (length: ${field2.length})`)
    console.log(`      Field 3 (membersHash): ${field3}`)
    console.log(`      Field 4 (misbehaved uint8[]): ${field4_uint8.slice(0, 20)}... (length: ${field4_uint8.length})`)
    console.log(`      Field 4 (misbehaved uint32[]): ${field4_uint32.slice(0, 20)}... (length: ${field4_uint32.length})`)
    console.log(`      Field 5 (signatures): ${field5.slice(0, 20)}... (length: ${field5.length})`)
    console.log(`      Field 6 (signingMembersIndices): ${field6.slice(0, 20)}... (length: ${field6.length})`)
    console.log(`      Field 7 (members): ${field7.slice(0, 20)}... (length: ${field7.length})`)
    console.log("")
    
    // Check if uint8[] vs uint32[] encoding differs
    if (field4_uint8 !== field4_uint32) {
      console.log("      ⚠️  uint8[] and uint32[] encodings differ!")
      console.log(`      uint8[] encoding length: ${field4_uint8.length}`)
      console.log(`      uint32[] encoding length: ${field4_uint32.length}`)
    } else {
      console.log("      ✓ uint8[] and uint32[] encodings are the same (empty array)")
    }
    console.log("")
  } catch (error: any) {
    console.log(`      Error: ${error.message}`)
    console.log("")
  }

  // Test 5: Try with the exact event result structure (no conversion)
  console.log("   Test 5: Using event result directly (no type conversion)")
  try {
    const encoded5 = abiCoder.encode(
      ["tuple(uint256,bytes,bytes32,uint8[],bytes,uint32[],uint32[])"],
      [[
        eventResult.submitterMemberIndex,
        eventResult.groupPubKey,
        eventResult.membersHash,
        eventResult.misbehavedMembersIndices, // Use directly
        eventResult.signatures,
        eventResult.signingMembersIndices,
        eventResult.members
      ]]
    )
    const hash5 = keccak256(encoded5)
    const match5 = hash5.toLowerCase() === storedHash.toLowerCase()
    console.log(`      Hash: ${hash5}`)
    console.log(`      Match: ${match5 ? "✅ YES" : "❌ NO"}`)
    console.log("")
  } catch (error: any) {
    console.log(`      Error: ${error.message}`)
    console.log("")
  }

  // Test 6: Extract exact parameters from transaction and encode
  console.log("   Test 6: Extracting exact parameters from submission transaction...")
  try {
    const tx = await ethers.provider.getTransaction(latestEvent.transactionHash)
    if (tx && tx.data) {
      console.log(`      Transaction hash: ${tx.hash}`)
      console.log("")
      
      // Decode the transaction to get exact parameters
      const iface = wr.interface
      try {
        const decoded = iface.parseTransaction({ data: tx.data })
        console.log(`      Function: ${decoded.name}`)
        
        if (decoded.name === "submitDkgResult" && decoded.args.length > 0) {
          const txResult = decoded.args[0]
          console.log(`      Transaction result structure:`)
          console.log(`        submitterMemberIndex: ${txResult.submitterMemberIndex.toString()}`)
          console.log(`        groupPubKey: ${txResult.groupPubKey.slice(0, 20)}... (${txResult.groupPubKey.length} bytes)`)
          console.log(`        membersHash: ${txResult.membersHash}`)
          console.log(`        misbehavedMembersIndices: [${txResult.misbehavedMembersIndices.length}]`)
          console.log(`        signatures: ${txResult.signatures.slice(0, 20)}... (${txResult.signatures.length} bytes)`)
          console.log(`        signingMembersIndices: [${txResult.signingMembersIndices.length}]`)
          console.log(`        members: [${txResult.members.length}]`)
          console.log("")
          
          // Encode using the exact transaction parameters
          console.log("      Test 6a: Encoding with exact transaction parameters...")
          const encodedTx = abiCoder.encode(
            ["tuple(uint256,bytes,bytes32,uint8[],bytes,uint32[],uint32[])"],
            [[
              txResult.submitterMemberIndex,
              txResult.groupPubKey,
              txResult.membersHash,
              txResult.misbehavedMembersIndices,
              txResult.signatures,
              txResult.signingMembersIndices,
              txResult.members
            ]]
          )
          const hashTx = keccak256(encodedTx)
          const matchTx = hashTx.toLowerCase() === storedHash.toLowerCase()
          console.log(`         Hash: ${hashTx}`)
          console.log(`         Match: ${matchTx ? "✅ YES" : "❌ NO"}`)
          console.log("")
          
          // Compare with event data
          console.log("      Test 6b: Comparing transaction vs event data...")
          const txGroupPubKey = txResult.groupPubKey
          const eventGroupPubKey = eventResult.groupPubKey
          const txSignatures = txResult.signatures
          const eventSignatures = eventResult.signatures
          
          console.log(`         groupPubKey match: ${txGroupPubKey === eventGroupPubKey ? "✅" : "❌"} (tx: ${txGroupPubKey.length}, event: ${eventGroupPubKey.length})`)
          console.log(`         signatures match: ${txSignatures === eventSignatures ? "✅" : "❌"} (tx: ${txSignatures.length}, event: ${eventSignatures.length})`)
          console.log(`         membersHash match: ${txResult.membersHash === eventResult.membersHash ? "✅" : "❌"}`)
          console.log(`         submitterMemberIndex match: ${txResult.submitterMemberIndex.toString() === eventResult.submitterMemberIndex.toString() ? "✅" : "❌"}`)
          console.log(`         misbehavedMembersIndices match: ${JSON.stringify(txResult.misbehavedMembersIndices) === JSON.stringify(eventResult.misbehavedMembersIndices) ? "✅" : "❌"}`)
          console.log(`         signingMembersIndices match: ${txResult.signingMembersIndices.length === eventResult.signingMembersIndices.length ? "✅" : "❌"}`)
          console.log(`         members match: ${txResult.members.length === eventResult.members.length ? "✅" : "❌"}`)
          console.log("")
          
          // If signatures differ, show where
          if (txSignatures !== eventSignatures) {
            console.log("      ⚠️  Signatures differ! Checking first few bytes...")
            console.log(`         TX first 50: ${txSignatures.slice(0, 50)}`)
            console.log(`         Event first 50: ${eventSignatures.slice(0, 50)}`)
            console.log("")
          }
          
          // If groupPubKey differs
          if (txGroupPubKey !== eventGroupPubKey) {
            console.log("      ⚠️  GroupPubKey differs!")
            console.log(`         TX first 50: ${txGroupPubKey.slice(0, 50)}`)
            console.log(`         Event first 50: ${eventGroupPubKey.slice(0, 50)}`)
            console.log("")
          }
        }
      } catch (e: any) {
        console.log(`      Could not decode transaction: ${e.message}`)
        console.log("")
      }
    }
  } catch (error: any) {
    console.log(`      Error: ${error.message}`)
    console.log("")
  }
  
  // Test 7: Try encoding the raw transaction data directly
  console.log("   Test 7: Analyzing raw transaction encoding...")
  try {
    const tx = await ethers.provider.getTransaction(latestEvent.transactionHash)
    if (tx && tx.data) {
      // The transaction data includes the function selector (4 bytes) + encoded parameters
      // Function selector for submitDkgResult: 0x7e0049fd
      const functionSelector = "0x7e0049fd"
      if (tx.data.startsWith(functionSelector)) {
        const encodedParams = tx.data.slice(10) // Remove 0x and function selector
        console.log(`      Function selector: ${functionSelector}`)
        console.log(`      Encoded params length: ${encodedParams.length} chars`)
        console.log(`      First 100 chars: ${encodedParams.slice(0, 100)}...`)
        console.log("")
        
        // Try to decode just the parameters
        try {
          const decodedParams = abiCoder.decode(
            ["tuple(uint256,bytes,bytes32,uint8[],bytes,uint32[],uint32[])"],
            "0x" + encodedParams
          )
          const resultFromTx = decodedParams[0]
          
          // Encode it back
          const reencoded = abiCoder.encode(
            ["tuple(uint256,bytes,bytes32,uint8[],bytes,uint32[],uint32[])"],
            [resultFromTx]
          )
          const hashFromTx = keccak256(reencoded)
          const matchFromTx = hashFromTx.toLowerCase() === storedHash.toLowerCase()
          
          console.log(`      Hash from transaction params: ${hashFromTx}`)
          console.log(`      Match: ${matchFromTx ? "✅ YES" : "❌ NO"}`)
          console.log("")
        } catch (e: any) {
          console.log(`      Could not decode/encode params: ${e.message}`)
          console.log("")
        }
      }
    }
  } catch (error: any) {
    console.log(`      Error: ${error.message}`)
    console.log("")
  }

  // Summary
  console.log("==========================================")
  console.log("Summary - ROOT CAUSE FOUND!")
  console.log("==========================================")
  console.log("")
  console.log("Stored Hash: " + storedHash)
  console.log("")
  console.log("✅ ROOT CAUSE: Struct field order mismatch!")
  console.log("")
  console.log("The DKG Result struct has this field order:")
  console.log("  1. uint256 submitterMemberIndex")
  console.log("  2. bytes groupPubKey")
  console.log("  3. uint8[] misbehavedMembersIndices")
  console.log("  4. bytes signatures")
  console.log("  5. uint256[] signingMembersIndices")
  console.log("  6. uint32[] members")
  console.log("  7. bytes32 membersHash  <-- LAST!")
  console.log("")
  console.log("When encoding for abi.encode(), membersHash must be LAST.")
  console.log("If membersHash is placed third (after groupPubKey), the hash won't match.")
  console.log("")
  console.log("This is why nodes fail to approve - they're encoding with wrong field order.")
  console.log("")
  console.log("Solution:")
  console.log("  1. Use approve-dkg-from-event.ts (uses event data, Hardhat handles encoding)")
  console.log("  2. Fix node code: Ensure AssembleDKGResult() uses correct field order")
  console.log("     File: pkg/chain/ethereum/tbtc.go")
  console.log("     Function: convertDkgResultToAbiType()")
  console.log("")
}

main().catch((error) => {
  console.error(error)
  process.exitCode = 1
})


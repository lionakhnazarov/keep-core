import { ethers } from "hardhat";

async function main() {
  const txHash = process.argv[2];

  if (!txHash) {
    console.error("Usage: npx hardhat run scripts/check-transaction-receipt.ts --network <network> <tx-hash>");
    console.error("Example: npx hardhat run scripts/check-transaction-receipt.ts --network development 0x1234...");
    process.exit(1);
  }

  // Validate hash format
  if (!/^0x[0-9a-fA-F]{64}$/.test(txHash)) {
    console.error(`Invalid transaction hash format: ${txHash}`);
    console.error("Expected format: 0x followed by 64 hex characters");
    process.exit(1);
  }

  console.log("==========================================");
  console.log(`Transaction: ${txHash}`);
  console.log("==========================================");
  console.log("");

  const provider = ethers.provider;

  try {
    // Get transaction receipt
    const receipt = await provider.getTransactionReceipt(txHash);

    if (!receipt) {
      console.log("⏳ Status: PENDING");
      console.log("Transaction not yet mined or hash not found");
      
      // Try to get transaction to see if it's pending
      const tx = await provider.getTransaction(txHash);
      if (tx) {
        console.log("Transaction found in mempool (pending)");
        console.log(`  From: ${tx.from}`);
        console.log(`  To: ${tx.to || "Contract Creation"}`);
        console.log(`  Value: ${ethers.formatEther(tx.value)} ETH`);
        console.log(`  Gas Limit: ${tx.gasLimit.toString()}`);
        console.log(`  Gas Price: ${ethers.formatEther(tx.gasPrice || 0n)} ETH`);
        console.log(`  Nonce: ${tx.nonce}`);
      } else {
        console.log("Transaction not found in mempool or blockchain");
      }
      return;
    }

    // Transaction was mined
    const status = receipt.status === 1 ? "SUCCESS" : "FAILED";
    const statusIcon = receipt.status === 1 ? "✓" : "✗";
    const statusColor = receipt.status === 1 ? "\x1b[32m" : "\x1b[31m";
    const resetColor = "\x1b[0m";

    console.log(`${statusColor}${statusIcon} Status: ${status}${resetColor}`);
    console.log(`Block Number: ${receipt.blockNumber}`);
    console.log(`Block Hash: ${receipt.blockHash}`);
    console.log(`Gas Used: ${receipt.gasUsed.toString()}`);
    console.log(`Cumulative Gas Used: ${receipt.cumulativeGasUsed.toString()}`);
    
    // Get transaction details for additional info
    const tx = await provider.getTransaction(txHash);
    if (tx) {
      console.log(`From: ${tx.from}`);
      console.log(`To: ${tx.to || "Contract Creation"}`);
      console.log(`Value: ${ethers.formatEther(tx.value)} ETH`);
      console.log(`Gas Limit: ${tx.gasLimit.toString()}`);
      if (tx.gasPrice) {
        console.log(`Gas Price: ${ethers.formatEther(tx.gasPrice)} ETH`);
      }
      if (receipt.gasPrice) {
        console.log(`Effective Gas Price: ${ethers.formatEther(receipt.gasPrice)} ETH`);
      }
      console.log(`Nonce: ${tx.nonce}`);
    }

    console.log(`Transaction Hash: ${receipt.hash}`);
    console.log(`Transaction Index: ${receipt.index}`);
    console.log(`Events (Logs): ${receipt.logs.length}`);

    // Show logs if any
    if (receipt.logs.length > 0) {
      console.log("");
      console.log("Events:");
      for (let i = 0; i < receipt.logs.length; i++) {
        const log = receipt.logs[i];
        console.log(`  [${i}] Address: ${log.address}`);
        console.log(`      Topics: ${log.topics.length}`);
        if (log.topics.length > 0) {
          console.log(`      Topic[0]: ${log.topics[0]}`);
        }
        console.log(`      Data: ${log.data.substring(0, 66)}...`);
      }
    }

    if (receipt.status === 0) {
      console.log("");
      console.log("⚠ Transaction reverted!");
      console.log("Check the transaction on-chain for revert reason.");
    }

  } catch (error: any) {
    console.error("Error checking transaction:", error.message);
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });


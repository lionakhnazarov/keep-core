import { ethers } from "hardhat";

async function main() {
  const Bridge = await ethers.getContractAt(
    "BridgeStub",
    "0xFdfce6c5030Cc243fB2F228df19C0facAbC04832"
  );

  const walletPubKeyHash = "0x9850b965a0ef404ce03dd88691201cc537beaefd";
  const redeemerOutputScript = "0x00147966c178f466b060aaeb2b91e9149a5fb2ec9c53";
  const amount = 200000n;

  console.log("Submitting redemption request...");
  const tx = await Bridge.requestRedemption(
    walletPubKeyHash,
    redeemerOutputScript,
    amount
  );
  console.log(`Transaction hash: ${tx.hash}`);
  const receipt = await tx.wait();
  console.log(`Block number: ${receipt?.blockNumber}`);
  console.log("Redemption requested successfully!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

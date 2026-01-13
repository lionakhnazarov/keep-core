#!/bin/bash
# Script to register an emulated deposit transaction with the mock Bitcoin chain
# This allows DepositSweep to find deposits even if they're emulated

set -e

if [ ! -f "deposit-data/funding-tx-info.json" ]; then
  echo "❌ Deposit data not found. Run: ./scripts/emulate-deposit.sh"
  exit 1
fi

FUNDING_TX_HASH=$(cat deposit-data/funding-tx-info.json | jq -r '.txHash' 2>/dev/null || echo "")

if [ -z "$FUNDING_TX_HASH" ] || [ "$FUNDING_TX_HASH" = "null" ]; then
  echo "❌ Could not read funding TX hash from deposit data"
  exit 1
fi

echo "=========================================="
echo "Registering Emulated Deposit"
echo "=========================================="
echo ""
echo "Funding TX Hash: $FUNDING_TX_HASH"
echo ""
echo "Note: This script creates a Go file that registers the transaction"
echo "      with the mock Bitcoin chain. You'll need to rebuild the binary."
echo ""

# Create a registration file that can be imported
cat > pkg/bitcoin/mock_chain_init.go << REGEOF
package bitcoin

import "sync"

var (
	mockChainInstance     *MockChain
	mockChainInstanceOnce sync.Once
)

// GetMockChainInstance returns a singleton instance of MockChain.
// This allows registering transactions before the chain is used.
func GetMockChainInstance() *MockChain {
	mockChainInstanceOnce.Do(func() {
		mockChainInstance = NewMockChain()
		// Register emulated deposit transactions
		initEmulatedDeposits(mockChainInstance)
	})
	return mockChainInstance
}

func initEmulatedDeposits(mc *MockChain) {
	// Register emulated deposit transaction with confirmations
	fundingTxHash, err := NewHashFromString("$FUNDING_TX_HASH", ReversedByteOrder)
	if err == nil {
		mc.SetTransactionConfirmations(fundingTxHash, 10)
	}
}
REGOEF

echo "✓ Created pkg/bitcoin/mock_chain_init.go"
echo ""
echo "Next steps:"
echo "  1. Rebuild the binary: make build"
echo "  2. Restart nodes"
echo "  3. DepositSweep should now find the deposit"

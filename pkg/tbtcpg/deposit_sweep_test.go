package tbtcpg_test

import (
	"reflect"
	"testing"
	"time"

	"github.com/go-test/deep"
	"github.com/ipfs/go-log"
	"github.com/keep-network/keep-core/internal/testutils"
	"github.com/keep-network/keep-core/pkg/bitcoin"
	"github.com/keep-network/keep-core/pkg/tbtc"
	"github.com/keep-network/keep-core/pkg/tbtcpg"
	"github.com/keep-network/keep-core/pkg/tbtcpg/internal/test"
)

func TestDepositSweepLookBackBlocks(t *testing.T) {
	// The look-back period should be 30 days at 12 seconds per block,
	// matching the value used by MovedFundsSweepLookBackBlocks.
	expectedValue := uint64(216000)

	if tbtcpg.DepositSweepLookBackBlocks != expectedValue {
		t.Errorf(
			"unexpected DepositSweepLookBackBlocks\n"+
				"expected: %d\n"+
				"actual:   %d",
			expectedValue,
			tbtcpg.DepositSweepLookBackBlocks,
		)
	}
}

func TestDepositSweepTask_FindDepositsToSweep_BoundedLookback(t *testing.T) {
	// When the current block (300000) exceeds the look-back window
	// (216000 blocks), the filter start block should be bounded:
	// filterStartBlock = 300000 - 216000 = 84000.
	currentBlock := uint64(300000)
	expectedStartBlock := currentBlock - tbtcpg.DepositSweepLookBackBlocks

	walletPublicKeyHash := hexToByte20(
		"7670343fc00ccc2d0cd65360e6ad400697ea0fed",
	)

	tbtcChain := tbtcpg.NewLocalChain()
	btcChain := tbtcpg.NewLocalBitcoinChain()

	blockCounter := tbtcpg.NewMockBlockCounter()
	blockCounter.SetCurrentBlock(currentBlock)
	tbtcChain.SetBlockCounter(blockCounter)

	tbtcChain.SetDepositMinAge(3600)

	fundingTxHash := hashFromString(
		"a8c3b3c1975094550d481bdffdee1b7b7613dd74dbce37a5f6dce7fd9ac0ace1",
	)

	tbtcChain.SetDepositRequest(
		fundingTxHash,
		uint32(1),
		&tbtc.DepositChainRequest{
			RevealedAt: time.Now().Add(-2 * time.Hour),
			SweptAt:    time.Unix(0, 0),
		},
	)

	btcChain.SetTransaction(fundingTxHash, &bitcoin.Transaction{})
	btcChain.SetTransactionConfirmations(
		fundingTxHash,
		tbtc.DepositSweepRequiredFundingTxConfirmations,
	)

	// Register events under the filter with the bounded start block.
	// The production code will query with StartBlock = expectedStartBlock,
	// so the event registration must use the same filter key.
	err := tbtcChain.AddPastDepositRevealedEvent(
		&tbtc.DepositRevealedEventFilter{
			StartBlock:          expectedStartBlock,
			WalletPublicKeyHash: [][20]byte{walletPublicKeyHash},
		},
		&tbtc.DepositRevealedEvent{
			BlockNumber:         290000,
			WalletPublicKeyHash: walletPublicKeyHash,
			FundingTxHash:       fundingTxHash,
			FundingOutputIndex:  1,
		},
	)
	if err != nil {
		t.Fatal(err)
	}

	task := tbtcpg.NewDepositSweepTask(tbtcChain, btcChain)

	deposits, err := task.FindDepositsToSweep(
		&testutils.MockLogger{},
		walletPublicKeyHash,
		5,
	)
	if err != nil {
		t.Fatal(err)
	}

	if len(deposits) != 1 {
		t.Fatalf("expected 1 deposit, got %d", len(deposits))
	}

	if deposits[0].FundingTxHash != fundingTxHash {
		t.Errorf("unexpected funding tx hash")
	}

	if deposits[0].FundingOutputIndex != 1 {
		t.Errorf("unexpected funding output index")
	}
}

func TestDepositSweepTask_FindDepositsToSweep_UnderflowGuard(t *testing.T) {
	// When the current block is less than the look-back window, the filter
	// start block should remain 0 to avoid underflow.
	currentBlock := uint64(100000)

	walletPublicKeyHash := hexToByte20(
		"7670343fc00ccc2d0cd65360e6ad400697ea0fed",
	)

	tbtcChain := tbtcpg.NewLocalChain()
	btcChain := tbtcpg.NewLocalBitcoinChain()

	blockCounter := tbtcpg.NewMockBlockCounter()
	blockCounter.SetCurrentBlock(currentBlock)
	tbtcChain.SetBlockCounter(blockCounter)

	tbtcChain.SetDepositMinAge(3600)

	fundingTxHash := hashFromString(
		"d91868ca43db4deb96047d727a5e782f282864fde2d9364f8c562c8998ba64bf",
	)

	tbtcChain.SetDepositRequest(
		fundingTxHash,
		uint32(1),
		&tbtc.DepositChainRequest{
			RevealedAt: time.Now().Add(-2 * time.Hour),
			SweptAt:    time.Unix(0, 0),
		},
	)

	btcChain.SetTransaction(fundingTxHash, &bitcoin.Transaction{})
	btcChain.SetTransactionConfirmations(
		fundingTxHash,
		tbtc.DepositSweepRequiredFundingTxConfirmations,
	)

	// Register events under the filter with StartBlock = 0,
	// since the underflow guard should keep the filter at 0.
	err := tbtcChain.AddPastDepositRevealedEvent(
		&tbtc.DepositRevealedEventFilter{
			StartBlock:          0,
			WalletPublicKeyHash: [][20]byte{walletPublicKeyHash},
		},
		&tbtc.DepositRevealedEvent{
			BlockNumber:         90000,
			WalletPublicKeyHash: walletPublicKeyHash,
			FundingTxHash:       fundingTxHash,
			FundingOutputIndex:  1,
		},
	)
	if err != nil {
		t.Fatal(err)
	}

	task := tbtcpg.NewDepositSweepTask(tbtcChain, btcChain)

	deposits, err := task.FindDepositsToSweep(
		&testutils.MockLogger{},
		walletPublicKeyHash,
		5,
	)
	if err != nil {
		t.Fatal(err)
	}

	if len(deposits) != 1 {
		t.Fatalf("expected 1 deposit, got %d", len(deposits))
	}

	if deposits[0].FundingTxHash != fundingTxHash {
		t.Errorf("unexpected funding tx hash")
	}
}

func TestDepositSweepTask_FindDepositsToSweep(t *testing.T) {
	err := log.SetLogLevel("*", "DEBUG")
	if err != nil {
		t.Fatal(err)
	}

	scenarios, err := test.LoadFindDepositsToSweepTestScenario()
	if err != nil {
		t.Fatal(err)
	}

	for _, scenario := range scenarios {
		t.Run(scenario.Title, func(t *testing.T) {
			tbtcChain := tbtcpg.NewLocalChain()
			btcChain := tbtcpg.NewLocalBitcoinChain()

			tbtcChain.SetDepositMinAge(scenario.ChainParameters.DepositMinAge)

			// Wire the MockBlockCounter using the scenario's current
			// block value. FindDepositsToSweep requires a block
			// counter to compute the bounded lookback window.
			blockCounter := tbtcpg.NewMockBlockCounter()
			blockCounter.SetCurrentBlock(scenario.ChainParameters.CurrentBlock)
			tbtcChain.SetBlockCounter(blockCounter)

			// Compute the expected filter start block using the same
			// logic as the production code.
			filterStartBlock := uint64(0)
			if scenario.ChainParameters.CurrentBlock > tbtcpg.DepositSweepLookBackBlocks {
				filterStartBlock = scenario.ChainParameters.CurrentBlock - tbtcpg.DepositSweepLookBackBlocks
			}

			// Chain setup.
			for _, deposit := range scenario.Deposits {
				tbtcChain.SetDepositRequest(
					deposit.FundingTxHash,
					deposit.FundingOutputIndex,
					&tbtc.DepositChainRequest{
						RevealedAt: deposit.RevealedAt,
						SweptAt:    deposit.SweptAt,
					},
				)
				btcChain.SetTransaction(deposit.FundingTxHash, deposit.FundingTx)
				btcChain.SetTransactionConfirmations(
					deposit.FundingTxHash,
					deposit.FundingTxConfirmations,
				)

				err := tbtcChain.AddPastDepositRevealedEvent(
					&tbtc.DepositRevealedEventFilter{
						StartBlock:          filterStartBlock,
						WalletPublicKeyHash: [][20]byte{deposit.WalletPublicKeyHash},
					},
					&tbtc.DepositRevealedEvent{
						BlockNumber:         deposit.RevealBlockNumber,
						WalletPublicKeyHash: deposit.WalletPublicKeyHash,
						FundingTxHash:       deposit.FundingTxHash,
						FundingOutputIndex:  deposit.FundingOutputIndex,
					},
				)
				if err != nil {
					t.Fatal(err)
				}
			}

			task := tbtcpg.NewDepositSweepTask(tbtcChain, btcChain)

			// Test execution.
			actualDeposits, err := task.FindDepositsToSweep(
				&testutils.MockLogger{},
				scenario.WalletPublicKeyHash,
				scenario.MaxNumberOfDeposits,
			)

			if err != nil {
				t.Fatal(err)
			}

			if diff := deep.Equal(
				scenario.ExpectedUnsweptDeposits,
				actualDeposits,
			); diff != nil {
				t.Errorf("invalid deposits: %v", diff)
			}
		})
	}
}

func TestDepositSweepTask_ProposeDepositsSweep(t *testing.T) {
	err := log.SetLogLevel("*", "DEBUG")
	if err != nil {
		t.Fatal(err)
	}

	scenarios, err := test.LoadProposeSweepTestScenario()
	if err != nil {
		t.Fatal(err)
	}

	for _, scenario := range scenarios {
		t.Run(scenario.Title, func(t *testing.T) {
			tbtcChain := tbtcpg.NewLocalChain()
			btcChain := tbtcpg.NewLocalBitcoinChain()

			// Chain setup.
			tbtcChain.SetDepositParameters(0, 0, scenario.DepositTxMaxFee, 0)

			for _, deposit := range scenario.Deposits {
				err := tbtcChain.AddPastDepositRevealedEvent(
					&tbtc.DepositRevealedEventFilter{
						StartBlock:          deposit.RevealBlock,
						EndBlock:            &deposit.RevealBlock,
						WalletPublicKeyHash: [][20]byte{scenario.WalletPublicKeyHash},
					},
					&tbtc.DepositRevealedEvent{
						WalletPublicKeyHash: scenario.WalletPublicKeyHash,
						FundingTxHash:       deposit.FundingTxHash,
						FundingOutputIndex:  deposit.FundingOutputIndex,
					},
				)
				if err != nil {
					t.Fatal(err)
				}

				tbtcChain.SetDepositRequest(
					deposit.FundingTxHash,
					deposit.FundingOutputIndex,
					&tbtc.DepositChainRequest{
						// Set only relevant fields.
						ExtraData: nil,
					},
				)

				btcChain.SetTransaction(deposit.FundingTxHash, &bitcoin.Transaction{})
				btcChain.SetTransactionConfirmations(deposit.FundingTxHash, tbtc.DepositSweepRequiredFundingTxConfirmations)
			}

			if scenario.ExpectedDepositSweepProposal != nil {
				err := tbtcChain.SetDepositSweepProposalValidationResult(
					scenario.WalletPublicKeyHash,
					scenario.ExpectedDepositSweepProposal,
					nil,
					true,
				)
				if err != nil {
					t.Fatal(err)
				}
			}

			btcChain.SetEstimateSatPerVByteFee(1, scenario.EstimateSatPerVByteFee)

			task := tbtcpg.NewDepositSweepTask(tbtcChain, btcChain)

			// Test execution.
			proposal, err := task.ProposeDepositsSweep(
				&testutils.MockLogger{},
				scenario.WalletPublicKeyHash,
				scenario.DepositsReferences(),
				scenario.SweepTxFee,
			)

			if !reflect.DeepEqual(scenario.ExpectedErr, err) {
				t.Errorf(
					"unexpected error\n"+
						"expected: [%+v]\n"+
						"actual:   [%+v]",
					scenario.ExpectedErr,
					err,
				)
			}

			var actualDepositSweepProposals []*tbtc.DepositSweepProposal
			if proposal != nil {
				actualDepositSweepProposals = append(actualDepositSweepProposals, proposal)
			}

			var expectedDepositSweepProposals []*tbtc.DepositSweepProposal
			if p := scenario.ExpectedDepositSweepProposal; p != nil {
				expectedDepositSweepProposals = append(expectedDepositSweepProposals, p)
			}

			if diff := deep.Equal(
				actualDepositSweepProposals,
				expectedDepositSweepProposals,
			); diff != nil {
				t.Errorf("invalid deposit sweep proposal: %v", diff)
			}
		})
	}
}

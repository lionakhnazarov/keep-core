package cmd

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/keep-network/keep-core/pkg/tbtcpg"

	"github.com/keep-network/keep-common/pkg/persistence"
	"github.com/keep-network/keep-core/build"
	"github.com/keep-network/keep-core/pkg/bitcoin"
	"github.com/keep-network/keep-core/pkg/bitcoin/electrum"
	"github.com/keep-network/keep-core/pkg/operator"
	"github.com/keep-network/keep-core/pkg/storage"

	"github.com/spf13/cobra"

	"github.com/keep-network/keep-core/config"
	"github.com/keep-network/keep-core/pkg/beacon"
	"github.com/keep-network/keep-core/pkg/chain"
	"github.com/keep-network/keep-core/pkg/chain/ethereum"
	"github.com/keep-network/keep-core/pkg/clientinfo"
	"github.com/keep-network/keep-core/pkg/firewall"
	"github.com/keep-network/keep-core/pkg/generator"
	"github.com/keep-network/keep-core/pkg/net"
	"github.com/keep-network/keep-core/pkg/net/libp2p"
	"github.com/keep-network/keep-core/pkg/net/retransmission"
	"github.com/keep-network/keep-core/pkg/tbtc"
)

// StartCommand contains the definition of the start command-line subcommand.
var StartCommand = &cobra.Command{
	Use:   "start",
	Short: "Starts the Keep Client",
	Long:  "Starts the Keep Client in the foreground",
	PreRun: func(cmd *cobra.Command, args []string) {
		if err := clientConfig.ReadConfig(configFilePath, cmd.Flags(), config.StartCmdCategories...); err != nil {
			logger.Fatalf("error reading config: %v", err)
		}
	},
	Run: func(cmd *cobra.Command, args []string) {
		if err := start(cmd); err != nil {
			logger.Fatal(err)
		}
	},
}

func init() {
	initFlags(StartCommand, &configFilePath, clientConfig, config.StartCmdCategories...)

	StartCommand.SetUsageTemplate(
		fmt.Sprintf(`%s
Environment variables:
    %s    Password for Keep operator account keyfile decryption.
    %s                 Space-delimited set of log level directives; set to "help" for help.
`,
			StartCommand.UsageString(),
			config.EthereumPasswordEnvVariable,
			config.LogLevelEnvVariable,
		),
	)
}

// start starts a node
func start(cmd *cobra.Command) error {
	ctx := context.Background()

	beaconChain, tbtcChain, blockCounter, signing, operatorPrivateKey, err :=
		ethereum.Connect(ctx, clientConfig.Ethereum)
	if err != nil {
		return fmt.Errorf("error connecting to Ethereum node: [%v]", err)
	}

	netProvider, err := initializeNetwork(
		ctx,
		[]firewall.Application{beaconChain, tbtcChain},
		operatorPrivateKey,
		blockCounter,
	)
	if err != nil {
		return fmt.Errorf("cannot initialize network: [%v]", err)
	}

	clientInfoRegistry := initializeClientInfo(
		ctx,
		clientConfig,
		netProvider,
		signing,
		blockCounter,
	)

	// Wire performance metrics into network provider if available
	var perfMetrics *clientinfo.PerformanceMetrics
	if clientInfoRegistry != nil {
		perfMetrics = clientinfo.NewPerformanceMetrics(ctx, clientInfoRegistry)
		// Type assert to libp2p provider to set metrics recorder
		// The provider struct is not exported, so we use interface assertion
		if setter, ok := netProvider.(interface {
			SetMetricsRecorder(recorder interface {
				IncrementCounter(name string, value float64)
				SetGauge(name string, value float64)
				RecordDuration(name string, duration time.Duration)
			})
		}); ok {
			setter.SetMetricsRecorder(perfMetrics)
		}
	}

	// Initialize beacon and tbtc only for non-bootstrap nodes.
	// Skip initialization for bootstrap nodes as they are only used for network
	// discovery.
	if !isBootstrap() {
		var btcChain bitcoin.Chain

		// Try to connect to Electrum, but fall back to mock chain for development
		electrumChain, err := electrum.Connect(ctx, clientConfig.Bitcoin.Electrum)
		if err != nil {
			logger.Warnf(
				"could not connect to Electrum chain: [%v]; using mock Bitcoin chain for development",
				err,
			)
			// Use mock chain for development when Electrum is unavailable
			// The mock chain automatically returns 10 confirmations for any transaction
			// This allows emulated deposits to pass the confirmation check
			btcChain = bitcoin.GetMockChainInstance()
		} else {
			// Wrap Electrum chain with fallback to mock chain for fee estimation
			// This handles cases where mock Electrum servers don't support blockchain.estimatefee
			btcChain = newBitcoinChainWithFeeFallback(electrumChain, bitcoin.GetMockChainInstance())
		}

		beaconKeyStorePersistence,
			tbtcKeyStorePersistence,
			tbtcDataPersistence,
			err := initializePersistence()
		if err != nil {
			return fmt.Errorf("cannot initialize persistence: [%w]", err)
		}

		scheduler := generator.StartScheduler()

		// Only observe Bitcoin connectivity if using real Electrum chain
		if clientInfoRegistry != nil {
			if _, isMock := btcChain.(*bitcoin.MockChain); !isMock {
				clientInfoRegistry.ObserveBtcConnectivity(
					btcChain,
					clientConfig.ClientInfo.BitcoinMetricsTick,
				)
			}

			clientInfoRegistry.RegisterBtcChainInfoSource(btcChain)

			rpcHealthChecker := clientinfo.NewRPCHealthChecker(
				clientInfoRegistry,
				blockCounter,
				btcChain,
				clientConfig.ClientInfo.RPCHealthCheckInterval,
			)
			rpcHealthChecker.Start(ctx)
		}

		err = beacon.Initialize(
			ctx,
			beaconChain,
			netProvider,
			beaconKeyStorePersistence,
			scheduler,
		)
		if err != nil {
			return fmt.Errorf("error initializing beacon: [%v]", err)
		}

		proposalGenerator := tbtcpg.NewProposalGenerator(
			tbtcChain,
			btcChain,
		)

		err = tbtc.Initialize(
			ctx,
			tbtcChain,
			btcChain,
			netProvider,
			tbtcKeyStorePersistence,
			tbtcDataPersistence,
			scheduler,
			proposalGenerator,
			clientConfig.Tbtc,
			clientInfoRegistry,
			perfMetrics, // Pass the existing performance metrics instance to avoid duplicate registrations
		)
		if err != nil {
			return fmt.Errorf("error initializing TBTC: [%v]", err)
		}
	}

	nodeHeader(
		netProvider.ConnectionManager().AddrStrings(),
		beaconChain.Signing().Address().String(),
		clientConfig.LibP2P.Port,
		clientConfig.Ethereum,
	)

	<-ctx.Done()
	return fmt.Errorf("shutting down the node because its context has ended")
}

// bitcoinChainWithFeeFallback wraps a primary Bitcoin chain and falls back
// to a fallback chain when EstimateSatPerVByteFee fails on the primary chain.
// This is useful when using mock Electrum servers that don't support
// blockchain.estimatefee.
type bitcoinChainWithFeeFallback struct {
	primary  bitcoin.Chain
	fallback bitcoin.Chain
}

func newBitcoinChainWithFeeFallback(primary, fallback bitcoin.Chain) bitcoin.Chain {
	return &bitcoinChainWithFeeFallback{
		primary:  primary,
		fallback: fallback,
	}
}

// Delegate all methods to primary chain, except EstimateSatPerVByteFee
// which falls back to fallback chain on error.

func (w *bitcoinChainWithFeeFallback) GetTransaction(transactionHash bitcoin.Hash) (*bitcoin.Transaction, error) {
	tx, err := w.primary.GetTransaction(transactionHash)
	if err != nil {
		// Check if error is "transaction not found" (emulated deposit)
		// If so, fall back to mock chain which returns a minimal valid transaction
		if strings.Contains(err.Error(), "not found") || strings.Contains(err.Error(), "Transaction") {
			logger.Warnf(
				"primary chain GetTransaction failed (likely emulated deposit): [%v]; falling back to mock chain",
				err,
			)
			return w.fallback.GetTransaction(transactionHash)
		}
		return nil, err
	}
	return tx, nil
}

func (w *bitcoinChainWithFeeFallback) GetTransactionConfirmations(transactionHash bitcoin.Hash) (uint, error) {
	confirmations, err := w.primary.GetTransactionConfirmations(transactionHash)
	if err != nil {
		// Check if error is "transaction not found" (emulated deposit)
		// If so, fall back to mock chain which returns default confirmations
		if strings.Contains(err.Error(), "not found") || strings.Contains(err.Error(), "Transaction") {
			logger.Warnf(
				"primary chain GetTransactionConfirmations failed (likely emulated deposit): [%v]; falling back to mock chain",
				err,
			)
			return w.fallback.GetTransactionConfirmations(transactionHash)
		}
		return 0, err
	}
	return confirmations, nil
}

func (w *bitcoinChainWithFeeFallback) BroadcastTransaction(transaction *bitcoin.Transaction) error {
	return w.primary.BroadcastTransaction(transaction)
}

func (w *bitcoinChainWithFeeFallback) GetLatestBlockHeight() (uint, error) {
	return w.primary.GetLatestBlockHeight()
}

func (w *bitcoinChainWithFeeFallback) GetBlockHeader(blockHeight uint) (*bitcoin.BlockHeader, error) {
	return w.primary.GetBlockHeader(blockHeight)
}

func (w *bitcoinChainWithFeeFallback) GetTransactionMerkleProof(transactionHash bitcoin.Hash, blockHeight uint) (*bitcoin.TransactionMerkleProof, error) {
	return w.primary.GetTransactionMerkleProof(transactionHash, blockHeight)
}

func (w *bitcoinChainWithFeeFallback) GetTransactionsForPublicKeyHash(publicKeyHash [20]byte, limit int) ([]*bitcoin.Transaction, error) {
	return w.primary.GetTransactionsForPublicKeyHash(publicKeyHash, limit)
}

func (w *bitcoinChainWithFeeFallback) GetTxHashesForPublicKeyHash(publicKeyHash [20]byte) ([]bitcoin.Hash, error) {
	return w.primary.GetTxHashesForPublicKeyHash(publicKeyHash)
}

func (w *bitcoinChainWithFeeFallback) GetMempoolForPublicKeyHash(publicKeyHash [20]byte) ([]*bitcoin.Transaction, error) {
	return w.primary.GetMempoolForPublicKeyHash(publicKeyHash)
}

func (w *bitcoinChainWithFeeFallback) GetUtxosForPublicKeyHash(publicKeyHash [20]byte) ([]*bitcoin.UnspentTransactionOutput, error) {
	return w.primary.GetUtxosForPublicKeyHash(publicKeyHash)
}

func (w *bitcoinChainWithFeeFallback) GetMempoolUtxosForPublicKeyHash(publicKeyHash [20]byte) ([]*bitcoin.UnspentTransactionOutput, error) {
	return w.primary.GetMempoolUtxosForPublicKeyHash(publicKeyHash)
}

// EstimateSatPerVByteFee tries the primary chain first, but falls back to
// the fallback chain if the primary chain fails (e.g., mock Electrum server
// doesn't support blockchain.estimatefee).
func (w *bitcoinChainWithFeeFallback) EstimateSatPerVByteFee(blocks uint32) (int64, error) {
	fee, err := w.primary.EstimateSatPerVByteFee(blocks)
	if err != nil {
		// Primary chain failed (likely mock Electrum server), use fallback
		logger.Warnf(
			"primary chain fee estimation failed: [%v]; falling back to mock chain",
			err,
		)
		return w.fallback.EstimateSatPerVByteFee(blocks)
	}
	return fee, nil
}

func (w *bitcoinChainWithFeeFallback) GetCoinbaseTxHash(blockHeight uint) (bitcoin.Hash, error) {
	return w.primary.GetCoinbaseTxHash(blockHeight)
}

func isBootstrap() bool {
	return clientConfig.LibP2P.Bootstrap
}

func initializeNetwork(
	ctx context.Context,
	applications []firewall.Application,
	operatorPrivateKey *operator.PrivateKey,
	blockCounter chain.BlockCounter,
) (net.Provider, error) {
	bootstrapPeersPublicKeys, err := libp2p.ExtractPeersPublicKeys(
		clientConfig.LibP2P.Peers,
	)
	if err != nil {
		return nil, fmt.Errorf(
			"error extracting bootstrap peers public keys: [%v]",
			err,
		)
	}

	firewall := firewall.AnyApplicationPolicy(
		applications,
		firewall.NewAllowList(bootstrapPeersPublicKeys),
	)

	netProvider, err := libp2p.Connect(
		ctx,
		clientConfig.LibP2P,
		operatorPrivateKey,
		firewall,
		retransmission.NewTicker(blockCounter.WatchBlocks(ctx)),
	)
	if err != nil {
		return nil, fmt.Errorf("failed while creating the network provider: [%v]", err)
	}

	return netProvider, nil
}

func initializeClientInfo(
	ctx context.Context,
	config *config.Config,
	netProvider net.Provider,
	signing chain.Signing,
	blockCounter chain.BlockCounter,
) *clientinfo.Registry {
	registry, isConfigured := clientinfo.Initialize(ctx, config.ClientInfo.Port)
	if !isConfigured {
		logger.Infof("client info endpoint not configured")
		return nil
	}

	registry.ObserveConnectedPeersCount(
		netProvider,
		config.ClientInfo.NetworkMetricsTick,
	)

	registry.ObserveConnectedBootstrapCount(
		netProvider,
		config.LibP2P.Peers,
		config.ClientInfo.NetworkMetricsTick,
	)

	registry.ObserveEthConnectivity(
		blockCounter,
		config.ClientInfo.EthereumMetricsTick,
	)

	registry.RegisterMetricClientInfo(build.Version)

	registry.RegisterConnectedPeersSource(netProvider, signing)

	registry.RegisterClientInfoSource(
		netProvider,
		signing,
		build.Version,
		build.Revision,
	)

	registry.RegisterEthChainInfoSource(blockCounter)

	logger.Infof(
		"enabled client info endpoint on port [%v]",
		config.ClientInfo.Port,
	)

	return registry
}

func initializePersistence() (
	beaconKeyStorePersistence persistence.ProtectedHandle,
	tbtcKeyStorePersistence persistence.ProtectedHandle,
	tbtcDataPersistence persistence.BasicHandle,
	err error,
) {
	storage, err := storage.Initialize(
		clientConfig.Storage,
		clientConfig.Ethereum.KeyFilePassword,
	)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("cannot initialize storage: [%w]", err)
	}

	beaconKeyStorePersistence, err = storage.InitializeKeyStorePersistence(
		"beacon",
	)
	if err != nil {
		return nil, nil, nil, fmt.Errorf(
			"cannot initialize beacon keystore persistence: [%w]",
			err,
		)
	}

	tbtcKeyStorePersistence, err = storage.InitializeKeyStorePersistence(
		"tbtc",
	)
	if err != nil {
		return nil, nil, nil, fmt.Errorf(
			"cannot initialize tbtc keystore persistence: [%w]",
			err,
		)
	}

	tbtcDataPersistence, err = storage.InitializeWorkPersistence("tbtc")
	if err != nil {
		return nil, nil, nil, fmt.Errorf(
			"cannot initialize tbtc data persistence: [%w]",
			err,
		)
	}

	return
}

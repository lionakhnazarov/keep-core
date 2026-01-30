// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title BridgeStub
 * @notice Minimal stub implementation of Bridge contract for local development
 */
contract BridgeStub {
    address public bank;
    address public relay;
    address public ecdsaWalletRegistry;
    address public reimbursementPool;

    // Redemption request structure (matches real Bridge)
    struct RedemptionRequest {
        address redeemer;
        uint64 requestedAmount;
        uint64 treasuryFee;
        uint64 txMaxFee;
        uint32 requestedAt;
    }

    // Wallet structure for tracking state
    struct Wallet {
        bytes32 ecdsaWalletID;
        bytes32 mainUtxoHash;
        uint64 pendingRedemptionsValue;
        uint32 createdAt;
        uint32 movingFundsRequestedAt;
        uint32 closingStartedAt;
        uint32 state; // 0=Unknown, 1=Live, 2=MovingFunds, etc.
    }

    // Storage for pending redemptions: redemptionKey => RedemptionRequest
    mapping(uint256 => RedemptionRequest) public pendingRedemptions;
    
    // Storage for wallets: walletPubKeyHash => Wallet
    mapping(bytes20 => Wallet) public wallets;

    // Events matching real Bridge
    // Note: The Go ABI expects 6 parameters (without requestedAt), matching the real Bridge contract
    event RedemptionRequested(
        bytes20 indexed walletPubKeyHash,
        bytes redeemerOutputScript,
        address indexed redeemer,
        uint64 requestedAmount,
        uint64 treasuryFee,
        uint64 txMaxFee
    );

    constructor(
        address _bank,
        address _relay,
        address _ecdsaWalletRegistry,
        address _reimbursementPool
    ) {
        bank = _bank;
        relay = _relay;
        ecdsaWalletRegistry = _ecdsaWalletRegistry;
        reimbursementPool = _reimbursementPool;
    }

    function contractReferences()
        external
        view
        returns (
            address _bank,
            address _relay,
            address _ecdsaWalletRegistry,
            address _reimbursementPool
        )
    {
        return (bank, relay, ecdsaWalletRegistry, reimbursementPool);
    }

    function getRedemptionWatchtower()
        external
        pure
        returns (address)
    {
        return address(0);
    }

    /// @notice For development: Allows calling requestNewWallet on WalletRegistry
    function requestNewWallet() external {
        IWalletRegistry(ecdsaWalletRegistry).requestNewWallet();
    }
    
    /// @notice For development: Allows anyone to trigger requestNewWallet
    function devRequestNewWallet() external {
        (bool success, ) = ecdsaWalletRegistry.call(
            abi.encodeWithSignature("requestNewWallet()")
        );
        require(success, "requestNewWallet call failed");
    }

    /// @notice Callback function executed when a new wallet is created
    /// @dev For now, this is a stub that does nothing. Wallets need to be
    ///      manually registered using registerWallet() function.
    ///      TODO: Implement automatic registration when crypto libraries are available
    function __ecdsaWalletCreatedCallback(
        bytes32 walletID,
        bytes32 publicKeyX,
        bytes32 publicKeyY
    ) external {
        // Stub implementation - wallets must be registered manually via registerWallet()
        // This is because calculating walletPubKeyHash requires RIPEMD160 which is not
        // available as a built-in Solidity function. The registerWallet() function
        // should be called externally with the pre-calculated walletPubKeyHash.
    }

    /// @notice Callback function executed when wallet heartbeat fails
    function __ecdsaWalletHeartbeatFailedCallback(
        bytes32 walletID,
        bytes32 publicKeyX,
        bytes32 publicKeyY
    ) external {
        // Stub implementation - just accept the callback
    }

    // ============ Redemption Functions (for testing) ============

    /// @notice Request a redemption (simplified for testing)
    /// @param walletPubKeyHash 20-byte wallet public key hash
    /// @param redeemerOutputScript Bitcoin script for redemption output
    /// @param amount Amount in satoshis to redeem
    function requestRedemption(
        bytes20 walletPubKeyHash,
        bytes calldata redeemerOutputScript,
        uint64 amount
    ) external {
        require(wallets[walletPubKeyHash].state == 1, "Wallet not live");
        require(amount > 0, "Amount must be positive");

        uint64 treasuryFee = amount / 500; // 0.2% fee
        uint64 txMaxFee = 20000; // Fixed max fee for testing
        uint32 requestedAt = uint32(block.timestamp);

        // Calculate redemption key (matches real Bridge)
        // The real Bridge uses: keccak256(keccak256(CompactSizeUint-prefixed script) + walletPKH)
        // CompactSizeUint encoding: for length <= 252, prefix is single byte
        bytes memory prefixedScript;
        if (redeemerOutputScript.length <= 252) {
            prefixedScript = abi.encodePacked(uint8(redeemerOutputScript.length), redeemerOutputScript);
        } else {
            // For longer scripts, use 0xfd + 2 bytes little-endian (simplified - only handles <= 252 for now)
            revert("Script too long for stub");
        }
        bytes32 scriptHash = keccak256(prefixedScript);
        uint256 redemptionKey = uint256(keccak256(abi.encodePacked(
            scriptHash,
            walletPubKeyHash
        )));

        // Store pending redemption
        pendingRedemptions[redemptionKey] = RedemptionRequest({
            redeemer: msg.sender,
            requestedAmount: amount,
            treasuryFee: treasuryFee,
            txMaxFee: txMaxFee,
            requestedAt: requestedAt
        });

        // Update wallet pending value
        wallets[walletPubKeyHash].pendingRedemptionsValue += amount;

        emit RedemptionRequested(
            walletPubKeyHash,
            redeemerOutputScript,
            msg.sender,
            amount,
            treasuryFee,
            txMaxFee
        );
    }

    /// @notice Register a wallet (for testing - called after DKG)
    /// @param walletPubKeyHash 20-byte wallet public key hash  
    /// @param ecdsaWalletID 32-byte ECDSA wallet ID
    function registerWallet(
        bytes20 walletPubKeyHash,
        bytes32 ecdsaWalletID
    ) external {
        wallets[walletPubKeyHash] = Wallet({
            ecdsaWalletID: ecdsaWalletID,
            mainUtxoHash: bytes32(0),
            pendingRedemptionsValue: 0,
            createdAt: uint32(block.timestamp),
            movingFundsRequestedAt: 0,
            closingStartedAt: 0,
            state: 1 // Live
        });
    }

    /// @notice Get wallet data
    function getWallet(bytes20 walletPubKeyHash) 
        external 
        view 
        returns (Wallet memory) 
    {
        return wallets[walletPubKeyHash];
    }

    /// @notice Get pending redemption request
    function getPendingRedemption(uint256 redemptionKey)
        external
        view
        returns (RedemptionRequest memory)
    {
        return pendingRedemptions[redemptionKey];
    }

    /// @notice Calculate redemption key (helper)
    /// Matches Go code: keccak256(keccak256(CompactSizeUint-prefixed script) + walletPKH)
    function calculateRedemptionKey(
        bytes20 walletPubKeyHash,
        bytes calldata redeemerOutputScript
    ) external pure returns (uint256) {
        // CompactSizeUint encoding: for length <= 252, prefix is single byte
        bytes memory prefixedScript;
        if (redeemerOutputScript.length <= 252) {
            prefixedScript = abi.encodePacked(uint8(redeemerOutputScript.length), redeemerOutputScript);
        } else {
            revert("Script too long for stub");
        }
        bytes32 scriptHash = keccak256(prefixedScript);
        return uint256(keccak256(abi.encodePacked(
            scriptHash,
            walletPubKeyHash
        )));
    }

    // ============ Redemption Parameters (for development) ============

    /// @notice Get redemption parameters (matches real Bridge interface)
    /// @dev Returns default values suitable for local development
    function redemptionParameters()
        external
        pure
        returns (
            uint64 redemptionDustThreshold,
            uint64 redemptionTreasuryFeeDivisor,
            uint64 redemptionTxMaxFee,
            uint64 redemptionTxMaxTotalFee,
            uint32 redemptionTimeout,
            uint96 redemptionTimeoutSlashingAmount,
            uint32 redemptionTimeoutNotifierRewardMultiplier
        )
    {
        // Default values for local development:
        // - redemptionTimeout: 86400 seconds (24 hours) - matches test data
        // - Other values set to reasonable defaults
        return (
            546,                    // redemptionDustThreshold (0.00000546 BTC)
            500,                    // redemptionTreasuryFeeDivisor (0.2% fee)
            20000,                  // redemptionTxMaxFee (satoshis)
            200000,                 // redemptionTxMaxTotalFee (satoshis)
            86400,                  // redemptionTimeout (24 hours in seconds)
            0,                      // redemptionTimeoutSlashingAmount (no slashing in dev)
            0                       // redemptionTimeoutNotifierRewardMultiplier (no reward in dev)
        );
    }

    /// @notice Get redemption request minimum age (for development)
    /// @dev Returns a default value suitable for local development
    function redemptionRequestMinAge() external pure returns (uint32) {
        return 3600; // 1 hour in seconds - matches test data
    }
}

interface IWalletRegistry {
    function requestNewWallet() external;
}

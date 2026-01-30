// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./BridgeStub.sol";

/**
 * @title WalletProposalValidatorStub
 * @notice Minimal stub implementation of WalletProposalValidator contract for local development
 */
contract WalletProposalValidatorStub {
    BridgeStub public bridge;

    constructor(address _bridge) {
        bridge = BridgeStub(_bridge);
    }

    // Constants matching real WalletProposalValidator
    uint32 public constant DEPOSIT_MIN_AGE = 0;
    uint32 public constant DEPOSIT_REFUND_SAFETY_MARGIN = 0;
    uint16 public constant DEPOSIT_SWEEP_MAX_SIZE = 20;
    uint16 public constant REDEMPTION_MAX_SIZE = 20;
    uint32 public constant REDEMPTION_REQUEST_MIN_AGE = 600; // 10 minutes
    uint32 public constant REDEMPTION_REQUEST_TIMEOUT_SAFETY_MARGIN = 0;

    /**
     * @notice Validate redemption proposal
     * @param walletPubKeyHash The wallet public key hash
     * @param redeemersOutputScripts Array of redeemer output scripts
     * @param redemptionTxFee The redemption transaction fee
     * @return true if valid, reverts if invalid
     */
    function validateRedemptionProposal(
        bytes20 walletPubKeyHash,
        bytes[] calldata redeemersOutputScripts,
        uint256 redemptionTxFee
    ) external view returns (bool) {
        // Check wallet state - must be Live (1) or MovingFunds (2)
        // wallets mapping returns a tuple, we need to extract the state field
        // The mapping returns: (bytes32, bytes32, uint64, uint32, uint32, uint32, uint32)
        // We only need the last field (state)
        (,,,,,, uint32 state) = bridge.wallets(walletPubKeyHash);
        require(
            state == 1 || state == 2,
            "Wallet is not in Live or MovingFunds state"
        );

        // Basic validations
        require(redeemersOutputScripts.length > 0, "No redemption scripts provided");
        require(redeemersOutputScripts.length <= REDEMPTION_MAX_SIZE, "Too many redemption scripts");
        require(redemptionTxFee > 0, "Redemption fee must be positive");

        return true;
    }

    // Other validation functions - minimal stubs that return true
    function validateDepositSweepProposal(
        bytes20 walletPubKeyHash,
        bytes20[] calldata depositsPubKeys,
        uint256 sweepTxFee,
        uint16 depositsRevealBlocks,
        bytes calldata depositsExtraInfo
    ) external view returns (bool) {
        (,,,,,, uint32 state) = bridge.wallets(walletPubKeyHash);
        require(
            state == 1 || state == 2,
            "Wallet is not in Live or MovingFunds state"
        );
        return true;
    }

    function validateHeartbeatProposal(
        bytes20 walletPubKeyHash,
        bytes32 heartbeatTxHash,
        uint256 heartbeatTxFee
    ) external view returns (bool) {
        (,,,,,, uint32 state) = bridge.wallets(walletPubKeyHash);
        require(
            state == 1 || state == 2,
            "Wallet is not in Live or MovingFunds state"
        );
        return true;
    }

    function validateMovingFundsProposal(
        bytes20 walletPubKeyHash,
        bytes20[] calldata targetWallets,
        uint256 movingFundsTxFee,
        bytes32 mainUtxoHash,
        uint32 mainUtxoOutputIndex,
        uint64 mainUtxoValue
    ) external view returns (bool) {
        (,,,,,, uint32 state) = bridge.wallets(walletPubKeyHash);
        require(
            state == 1 || state == 2,
            "Wallet is not in Live or MovingFunds state"
        );
        return true;
    }

    function validateMovedFundsSweepProposal(
        bytes20 walletPubKeyHash,
        bytes32 movingFundsTxHash,
        uint32 movingFundsTxOutputIndex,
        uint256 sweepTxFee
    ) external view returns (bool) {
        return true;
    }
}


// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "../api/IWalletOwner.sol";

/// @title Simple Wallet Owner
/// @notice A simple implementation of IWalletOwner interface for testing/development
contract SimpleWalletOwner is IWalletOwner {
    event WalletCreated(
        bytes32 indexed walletID,
        bytes32 publicKeyX,
        bytes32 publicKeyY
    );

    event WalletHeartbeatFailed(
        bytes32 indexed walletID,
        bytes32 publicKeyX,
        bytes32 publicKeyY
    );

    /// @notice Callback function executed once a new wallet is created.
    /// @dev Should be callable only by the Wallet Registry.
    function __ecdsaWalletCreatedCallback(
        bytes32 walletID,
        bytes32 publicKeyX,
        bytes32 publicKeyY
    ) external override {
        emit WalletCreated(walletID, publicKeyX, publicKeyY);
        // No-op: just emit event
    }

    /// @notice Callback function executed once a wallet heartbeat failure is detected.
    /// @dev Should be callable only by the Wallet Registry.
    function __ecdsaWalletHeartbeatFailedCallback(
        bytes32 walletID,
        bytes32 publicKeyX,
        bytes32 publicKeyY
    ) external override {
        emit WalletHeartbeatFailed(walletID, publicKeyX, publicKeyY);
        // No-op: just emit event
    }
}

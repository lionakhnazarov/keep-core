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
    /// @dev This is a convenience function for local development
    ///      In production, only the walletOwner should be able to call this
    function requestNewWallet() external {
        IWalletRegistry(ecdsaWalletRegistry).requestNewWallet();
    }
    
    /// @notice For development: Allows anyone to trigger requestNewWallet
    /// @dev This bypasses the walletOwner check - USE ONLY IN DEVELOPMENT
    ///      This function calls WalletRegistry.requestNewWallet() directly,
    ///      but since it's called from Bridge (the walletOwner), it will succeed
    function devRequestNewWallet() external {
        // This will work because msg.sender will be Bridge (the walletOwner)
        // when called from an external account, but we need to call as Bridge
        // So we use a low-level call to WalletRegistry
        (bool success, ) = ecdsaWalletRegistry.call(
            abi.encodeWithSignature("requestNewWallet()")
        );
        require(success, "requestNewWallet call failed");
    }

    /// @notice Callback function executed when a new wallet is created
    /// @dev Required by IWalletOwner interface for WalletRegistry
    /// @param walletID Wallet's unique identifier
    /// @param publicKeyX Wallet's public key's X coordinate
    /// @param publicKeyY Wallet's public key's Y coordinate
    function __ecdsaWalletCreatedCallback(
        bytes32 walletID,
        bytes32 publicKeyX,
        bytes32 publicKeyY
    ) external {
        // Stub implementation - just accept the callback
        // In production, Bridge would register the wallet and handle it
        // For development, we just need this to not revert
    }

    /// @notice Callback function executed when wallet heartbeat fails
    /// @dev Required by IWalletOwner interface for WalletRegistry
    /// @param walletID Wallet's unique identifier
    /// @param publicKeyX Wallet's public key's X coordinate
    /// @param publicKeyY Wallet's public key's Y coordinate
    function __ecdsaWalletHeartbeatFailedCallback(
        bytes32 walletID,
        bytes32 publicKeyX,
        bytes32 publicKeyY
    ) external {
        // Stub implementation - just accept the callback
        // In production, Bridge would handle heartbeat failures
        // For development, we just need this to not revert
    }
}

interface IWalletRegistry {
    function requestNewWallet() external;
}


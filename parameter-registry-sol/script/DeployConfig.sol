// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { AssetConfigs } from "./AssetConfigs.sol";

/// @title DeployConfig
/// @notice Configuration contract for deployment parameters across different networks
/// @dev This contract provides centralized configuration for deploying ParameterRegistry
contract DeployConfig {
    AssetConfigs internal assetConfigs;

    /// @notice Deployment configuration structure
    struct Config {
        address owner;
        address updater;
        address pendingOwner; // For two-step ownership transfer
        address pendingUpdater; // For updater transfer after setup
        string networkName;
    }

    constructor() {
        assetConfigs = new AssetConfigs();
    }

    // ============================================
    // NETWORK CONFIGURATIONS
    // ============================================

    /// @notice Returns configuration for Ethereum mainnet
    /// @return config The deployment configuration
    function getMainnetConfig() public pure returns (Config memory) {
        return Config({
            owner: 0x0000000000000000000000000000000000000000, // TODO: Set deployer address (initial owner)
            updater: 0x0000000000000000000000000000000000000000, // TODO: Set deployer address (initial updater)
            pendingOwner: 0xE6ec1f0Ae6Cd023bd0a9B4d0253BDC755103253c,
            pendingUpdater: 0xE6ec1f0Ae6Cd023bd0a9B4d0253BDC755103253c,
            networkName: "mainnet"
        });
    }

    /// @notice Returns configuration for Sepolia testnet
    /// @return config The deployment configuration
    function getSepoliaConfig() public pure returns (Config memory) {
        return Config({
            owner: 0xb0AD0E3A19490E9145bE9Ad45F7B285eb71756F6,
            updater: 0xb0AD0E3A19490E9145bE9Ad45F7B285eb71756F6,
            pendingOwner: 0xb0AD0E3A19490E9145bE9Ad45F7B285eb71756F6, // TODO: Set final owner if different
            pendingUpdater: 0xb0AD0E3A19490E9145bE9Ad45F7B285eb71756F6, // TODO: Set final updater if different
            networkName: "sepolia"
        });
    }

    /// @notice Returns configuration for local Anvil network
    /// @return config The deployment configuration
    function getAnvilConfig() public pure returns (Config memory) {
        // Default test addresses for local development
        // Using same account for both owner and updater for easier testing
        return Config({
            owner: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, // Anvil account 0
            updater: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, // Anvil account 0 (same as owner for testing)
            pendingOwner: address(0),
            pendingUpdater: address(0),
            networkName: "anvil"
        });
    }

    /// @notice Returns configuration based on chain ID
    /// @param chainId The chain ID of the target network
    /// @return config The deployment configuration
    function getConfigByChainId(uint256 chainId) public pure returns (Config memory) {
        if (chainId == 1) {
            // Ethereum mainnet
            return getMainnetConfig();
        } else if (chainId == 11_155_111) {
            // Sepolia testnet
            return getSepoliaConfig();
        } else if (chainId == 31_337) {
            // Anvil local network
            return getAnvilConfig();
        } else {
            revert("DeployConfig: Unsupported chain ID");
        }
    }

    // ============================================
    // ASSET CONFIGURATION DELEGATION
    // ============================================

    /// @notice Returns asset configurations for Ethereum mainnet
    /// @return assets Array of asset configurations
    function getMainnetAssets() public view returns (AssetConfigs.AssetConfig[] memory) {
        return assetConfigs.getMainnetAssets();
    }

    /// @notice Returns asset configurations for Sepolia testnet
    /// @return assets Array of asset configurations
    function getSepoliaAssets() public view returns (AssetConfigs.AssetConfig[] memory) {
        return assetConfigs.getSepoliaAssets();
    }

    /// @notice Returns asset configurations for Anvil local network
    /// @return assets Array of asset configurations
    function getAnvilAssets() public view returns (AssetConfigs.AssetConfig[] memory) {
        return assetConfigs.getAnvilAssets();
    }

    /// @notice Returns asset configurations based on chain ID
    /// @param chainId The chain ID of the target network
    /// @return assets Array of asset configurations
    function getAssetsByChainId(uint256 chainId) public view returns (AssetConfigs.AssetConfig[] memory) {
        return assetConfigs.getAssetsByChainId(chainId);
    }

    /// @notice Check if a chain has asset configurations
    /// @param chainId The chain ID to check
    /// @return True if the chain has configurations, false otherwise
    function hasAssetsForChain(uint256 chainId) public view returns (bool) {
        return assetConfigs.hasAssetsForChain(chainId);
    }
}

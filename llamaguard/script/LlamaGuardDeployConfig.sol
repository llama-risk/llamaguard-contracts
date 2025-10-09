// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title LlamaGuardDeployConfig
/// @notice Configuration contract for deployment parameters across different networks
/// @dev This contract provides centralized configuration for deploying LlamaGuardOracle
contract LlamaGuardDeployConfig {
    /// @notice Deployment configuration structure
    struct Config {
        address expectedAuthor; // CRE workflow author address
        bytes10 expectedWorkflowName; // CRE workflow name
        uint8 decimals; // Price feed decimals
        string description; // Oracle description
        uint256 version; // Oracle version
        address pendingOwner; // For two-step ownership transfer
        string networkName;
    }

    // ============================================
    // NETWORK CONFIGURATIONS
    // ============================================

    /// @notice Returns configuration for Ethereum mainnet
    /// @return config The deployment configuration
    function getMainnetConfig() public pure returns (Config memory) {
        return Config({
            expectedAuthor: address(0), // TODO: Set CRE workflow author
            expectedWorkflowName: bytes10(0), // TODO: Set CRE workflow name
            decimals: 8,
            description: "LlamaGuard Oracle - Mainnet",
            version: 1,
            pendingOwner: address(0), // TODO: Set final owner address
            networkName: "mainnet"
        });
    }

    /// @notice Returns configuration for Sepolia testnet
    /// @return config The deployment configuration
    function getSepoliaConfig() public pure returns (Config memory) {
        return Config({
            expectedAuthor: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, // Dummy value (checks disabled in contract)
            expectedWorkflowName: bytes10("TEST_FLOW"), // Dummy value (checks disabled in contract)
            decimals: 8,
            description: "LlamaGuard Oracle - Sepolia",
            version: 1,
            pendingOwner: address(0), // Set final owner if different from deployer
            networkName: "sepolia"
        });
    }

    /// @notice Returns configuration for local Anvil network
    /// @return config The deployment configuration
    function getAnvilConfig() public pure returns (Config memory) {
        // Default test addresses for local development
        return Config({
            expectedAuthor: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, // Anvil account 0
            expectedWorkflowName: bytes10("TEST_FLOW"),
            decimals: 8,
            description: "LlamaGuard Oracle - Anvil",
            version: 1,
            pendingOwner: address(0), // No ownership transfer for local testing
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
}


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title LlamaGuardDeployConfig
/// @notice Configuration contract for deployment parameters across different networks
/// @dev This contract provides centralized configuration for deploying LlamaGuardOracle
contract LlamaGuardDeployConfig {
    /// @notice Deployment configuration structure
    struct Config {
        address expectedAuthor; // CRE workflow author address
        address expectedForwarder; // CRE forwarder contract expected to call onReport
        bytes10 expectedWorkflowName; // CRE workflow name
        bytes32 expectedWorkflowId; // CRE workflow id (32 bytes)
        uint8 decimals; // Price feed decimals
        string description; // Oracle description
        uint256 version; // Oracle version
        address oracleAdmin; // Final DEFAULT_ADMIN_ROLE holder for oracle (optional)
        address proxyOwner; // Final owner for oracle proxy (optional)
        address aggregatorOwner; // Optional owner for Chainlink-style aggregator proxy
        bool revokeBroadcasterAdmin; // Whether broadcaster should renounce DEFAULT_ADMIN_ROLE after hand-off
        bool deployEacAggregator; // Whether to deploy EACAggregatorProxy wrapper alongside oracle
        bool deactivateSecurity; // Disable proxy security checks post-deploy
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
            expectedForwarder: address(0), // TODO: Set expected forwarder
            expectedWorkflowName: bytes10(0), // TODO: Set CRE workflow name
            expectedWorkflowId: bytes32(0), // TODO: Set CRE workflow id
            decimals: 8,
            description: "LlamaGuard Oracle - Mainnet",
            version: 1,
            oracleAdmin: address(0),
            proxyOwner: address(0),
            aggregatorOwner: address(0),
            revokeBroadcasterAdmin: false,
            deployEacAggregator: false,
            deactivateSecurity: true,
            networkName: "mainnet"
        });
    }

    /// @notice Returns configuration for Sepolia testnet
    /// @return config The deployment configuration
    function getSepoliaConfig() public pure returns (Config memory) {
        return Config({
            expectedAuthor: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, // Dummy
            expectedForwarder: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, // Dummy
            expectedWorkflowName: bytes10("TEST_FLOW"), // Dummy
            expectedWorkflowId: bytes32(uint256(0x544553545f57464c4f575f49445f3031)), // "TEST_WFLOW_ID_01"
            decimals: 8,
            description: "LlamaGuard Oracle - Sepolia",
            version: 1,
            oracleAdmin: address(0),
            proxyOwner: address(0),
            aggregatorOwner: address(0),
            revokeBroadcasterAdmin: false,
            deployEacAggregator: false,
            deactivateSecurity: true,
            networkName: "sepolia"
        });
    }

    /// @notice Returns configuration for local Anvil network
    /// @return config The deployment configuration
    function getAnvilConfig() public pure returns (Config memory) {
        // Default test addresses for local development
        return Config({
            expectedAuthor: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, // Anvil account 0
            expectedForwarder: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, // Anvil account 0
            expectedWorkflowName: bytes10("TEST_FLOW"),
            expectedWorkflowId: bytes32(uint256(0x414e56494c5f57464c4f575f49445f3031)), // "ANVIL_WFLOW_ID_01"
            decimals: 8,
            description: "LlamaGuard Oracle - Anvil",
            version: 1,
            oracleAdmin: address(0),
            proxyOwner: address(0),
            aggregatorOwner: address(0),
            revokeBroadcasterAdmin: false,
            deployEacAggregator: false,
            deactivateSecurity: false,
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
            revert("LlamaGuardDeployConfig: Unsupported chain ID");
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

/// @title LlamaGuardOracleConfig
/// @notice Centralized oracle and proxy configuration for all networks
/// @dev This contract provides all oracle/proxy configurations for different chains
contract LlamaGuardOracleConfig {
    /// @notice Error thrown when an unsupported chain ID is provided
    error UnsupportedChainId();

    // ═══════════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Configuration for LlamaGuardOracle deployment
    struct OracleConfig {
        string name; // Identifier for this oracle (e.g., "PRIMARY", "USDC")
        uint8 decimals;
        string description;
        uint256 version;
        string[] updateTypes;
        address[] authorizedMarkets;
    }

    /// @notice Configuration for LlamaGuardOracleProxy deployment
    /// @dev Chainlink CRE (Cross-chain Relayer Engine) parameters
    struct ProxyConfig {
        string name; // Identifier matching the oracle name
        bytes32 workflowId;
        address expectedForwarder;
        address expectedAuthor;
        bytes10 expectedWorkflowName;
        string description;
    }

    /// @notice Combined deployment configuration for a single oracle+proxy pair
    struct DeploymentConfig {
        OracleConfig oracle;
        ProxyConfig proxy;
        address pendingOwner; // For two-step ownership transfer after deployment
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ETHEREUM MAINNET CONFIGURATIONS (Chain ID: 1)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Returns oracle/proxy configurations for Ethereum mainnet
    /// @return configs Array of deployment configurations
    function getMainnetConfigs() public pure returns (DeploymentConfig[] memory) {
        // TODO: Update the number of configs as you add more oracles
        DeploymentConfig[] memory configs = new DeploymentConfig[](1);

        // ─────────────────────────────────────────────────────────────────────
        // Config 0: Primary Oracle
        // TODO: Fill in Chainlink CRE parameters before mainnet deployment
        // ─────────────────────────────────────────────────────────────────────
        string[] memory updateTypes0 = new string[](2);
        updateTypes0[0] = "boundedNAV"; // TODO: Confirm update types
        updateTypes0[1] = "boundedNAV"; // TODO: Confirm update types

        address[] memory markets0 = new address[](0); // TODO: Add authorized markets

        configs[0] = DeploymentConfig({
            oracle: OracleConfig({
                name: "PRIMARY",
                decimals: 8, // TODO: Confirm decimals
                description: "LlamaGuard Risk Oracle",
                version: 1,
                updateTypes: updateTypes0,
                authorizedMarkets: markets0
            }),
            proxy: ProxyConfig({
                name: "PRIMARY",
                workflowId: bytes32(0), // TODO: Set from Chainlink
                expectedForwarder: address(0), // TODO: Set from Chainlink
                expectedAuthor: address(0), // TODO: Set from Chainlink
                expectedWorkflowName: bytes10(0), // TODO: Set from Chainlink
                description: "LlamaGuard Oracle Proxy"
            }),
            pendingOwner: address(0) // TODO: Set if ownership transfer needed
        });

        // ─────────────────────────────────────────────────────────────────────
        // Config 1: Add more oracles here as needed
        // ─────────────────────────────────────────────────────────────────────
        // string[] memory updateTypes1 = new string[](2);
        // updateTypes1[0] = "bounded";
        // updateTypes1[1] = "AV";
        // address[] memory markets1 = new address[](0);
        //
        // configs[1] = DeploymentConfig({
        //     oracle: OracleConfig({
        //         name: "SECONDARY",
        //         decimals: 8,
        //         description: "LlamaGuard Risk Oracle 2",
        //         version: 1,
        //         updateTypes: updateTypes1,
        //         authorizedMarkets: markets1
        //     }),
        //     proxy: ProxyConfig({
        //         name: "SECONDARY",
        //         workflowId: bytes32(0),
        //         expectedForwarder: address(0),
        //         expectedAuthor: address(0),
        //         expectedWorkflowName: bytes10(0),
        //         description: "LlamaGuard Oracle Proxy 2"
        //     }),
        //     pendingOwner: address(0)
        // });

        return configs;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SEPOLIA TESTNET CONFIGURATIONS (Chain ID: 11155111)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Returns oracle/proxy configurations for Sepolia testnet
    /// @return configs Array of deployment configurations
    function getSepoliaConfigs() public pure returns (DeploymentConfig[] memory) {
        DeploymentConfig[] memory configs = new DeploymentConfig[](1);

        // ─────────────────────────────────────────────────────────────────────
        // Config 0: Test Oracle
        // TODO: Set Chainlink CRE parameters for Sepolia testing
        // ─────────────────────────────────────────────────────────────────────
        string[] memory updateTypes0 = new string[](2);
        updateTypes0[0] = "boundedNAV"; // TODO: Finalize the update types
        updateTypes0[1] = "boundedNAV"; // TODO: Finalize the update types

        address[] memory markets0 = new address[](0);

        configs[0] = DeploymentConfig({
            oracle: OracleConfig({
                name: "TEST",
                decimals: 8,
                description: "LlamaGuard Risk Oracle (Sepolia)",
                version: 1,
                updateTypes: updateTypes0,
                authorizedMarkets: markets0
            }),
            proxy: ProxyConfig({
                name: "TEST",
                workflowId: bytes32(0), // TODO: Set for Sepolia
                expectedForwarder: address(0), // TODO: Set for Sepolia
                expectedAuthor: address(0), // TODO: Set for Sepolia
                expectedWorkflowName: bytes10(0), // TODO: Set for Sepolia
                description: "LlamaGuard Oracle Proxy (Sepolia)"
            }),
            pendingOwner: address(0)
        });

        return configs;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ANVIL LOCAL CONFIGURATIONS (Chain ID: 31337)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Returns oracle/proxy configurations for Anvil local network
    /// @return configs Array of deployment configurations
    function getAnvilConfigs() public pure returns (DeploymentConfig[] memory) {
        DeploymentConfig[] memory configs = new DeploymentConfig[](2);

        // ─────────────────────────────────────────────────────────────────────
        // Config 0: Test Oracle 1
        // ─────────────────────────────────────────────────────────────────────
        string[] memory updateTypes0 = new string[](2);
        updateTypes0[0] = "bounded";
        updateTypes0[1] = "AV";

        address[] memory markets0 = new address[](0);

        configs[0] = DeploymentConfig({
            oracle: OracleConfig({
                name: "TEST1",
                decimals: 8,
                description: "LlamaGuard Risk Oracle 1 (Local)",
                version: 1,
                updateTypes: updateTypes0,
                authorizedMarkets: markets0
            }),
            proxy: ProxyConfig({
                name: "TEST1",
                workflowId: keccak256("test-workflow-1"),
                expectedForwarder: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266, // Anvil account 0
                expectedAuthor: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
                expectedWorkflowName: bytes10("testwork01"),
                description: "LlamaGuard Oracle Proxy 1 (Local)"
            }),
            pendingOwner: address(0)
        });

        // ─────────────────────────────────────────────────────────────────────
        // Config 1: Test Oracle 2
        // ─────────────────────────────────────────────────────────────────────
        string[] memory updateTypes1 = new string[](2);
        updateTypes1[0] = "bounded";
        updateTypes1[1] = "AV";

        address[] memory markets1 = new address[](0);

        configs[1] = DeploymentConfig({
            oracle: OracleConfig({
                name: "TEST2",
                decimals: 18,
                description: "LlamaGuard Risk Oracle 2 (Local)",
                version: 1,
                updateTypes: updateTypes1,
                authorizedMarkets: markets1
            }),
            proxy: ProxyConfig({
                name: "TEST2",
                workflowId: keccak256("test-workflow-2"),
                expectedForwarder: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8, // Anvil account 1
                expectedAuthor: 0x70997970C51812dc3A010C7d01b50e0d17dc79C8,
                expectedWorkflowName: bytes10("testwork02"),
                description: "LlamaGuard Oracle Proxy 2 (Local)"
            }),
            pendingOwner: address(0)
        });

        return configs;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Returns deployment configurations based on chain ID
    /// @param chainId The chain ID of the target network
    /// @return configs Array of deployment configurations
    function getConfigsByChainId(uint256 chainId) public pure returns (DeploymentConfig[] memory) {
        if (chainId == 1) {
            return getMainnetConfigs();
        } else if (chainId == 11_155_111) {
            return getSepoliaConfigs();
        } else if (chainId == 31_337) {
            return getAnvilConfigs();
        } else {
            revert UnsupportedChainId();
        }
    }

    /// @notice Check if a chain has oracle configurations
    /// @param chainId The chain ID to check
    /// @return True if the chain has configurations, false otherwise
    function hasConfigsForChain(uint256 chainId) public pure returns (bool) {
        return chainId == 1 || chainId == 11_155_111 || chainId == 31_337;
    }

    /// @notice Returns the number of deployment configurations for a chain
    /// @param chainId The chain ID of the target network
    /// @return count The number of configurations
    function getConfigCount(uint256 chainId) public pure returns (uint256) {
        return getConfigsByChainId(chainId).length;
    }

    /// @notice Returns a single deployment config by index
    /// @param chainId The chain ID of the target network
    /// @param index The index of the configuration to return
    /// @return config The deployment configuration at the specified index
    function getConfigByIndex(uint256 chainId, uint256 index) public pure returns (DeploymentConfig memory) {
        DeploymentConfig[] memory configs = getConfigsByChainId(chainId);
        require(index < configs.length, "LlamaGuardOracleConfig: Index out of bounds");
        return configs[index];
    }

    /// @notice Validates that all mainnet configurations are ready for deployment
    /// @dev Checks that all TODO placeholders have been filled for all configs
    /// @return isValid True if all configurations are valid for deployment
    /// @return message Validation message describing any issues
    function validateMainnetConfigs() public pure returns (bool isValid, string memory message) {
        DeploymentConfig[] memory configs = getMainnetConfigs();

        for (uint256 i = 0; i < configs.length; i++) {
            ProxyConfig memory proxy = configs[i].proxy;

            if (proxy.workflowId == bytes32(0)) {
                return (false, string.concat("Config ", configs[i].oracle.name, ": workflowId not set"));
            }
            if (proxy.expectedForwarder == address(0)) {
                return (false, string.concat("Config ", configs[i].oracle.name, ": expectedForwarder not set"));
            }
            if (proxy.expectedAuthor == address(0)) {
                return (false, string.concat("Config ", configs[i].oracle.name, ": expectedAuthor not set"));
            }
            if (proxy.expectedWorkflowName == bytes10(0)) {
                return (false, string.concat("Config ", configs[i].oracle.name, ": expectedWorkflowName not set"));
            }
        }

        return (true, "All configurations valid");
    }

    /// @notice Validates a single configuration by index
    /// @param chainId The chain ID of the target network
    /// @param index The index of the configuration to validate
    /// @return isValid True if configuration is valid for deployment
    /// @return message Validation message describing any issues
    function validateConfigByIndex(
        uint256 chainId,
        uint256 index
    )
        public
        pure
        returns (bool isValid, string memory message)
    {
        DeploymentConfig memory config = getConfigByIndex(chainId, index);
        ProxyConfig memory proxy = config.proxy;

        if (proxy.workflowId == bytes32(0)) {
            return (false, "workflowId not set");
        }
        if (proxy.expectedForwarder == address(0)) {
            return (false, "expectedForwarder not set");
        }
        if (proxy.expectedAuthor == address(0)) {
            return (false, "expectedAuthor not set");
        }
        if (proxy.expectedWorkflowName == bytes10(0)) {
            return (false, "expectedWorkflowName not set");
        }

        return (true, "Configuration valid");
    }
}

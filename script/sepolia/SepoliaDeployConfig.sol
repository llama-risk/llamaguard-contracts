// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

/// @title SepoliaDeployConfig
/// @author LlamaRisk
/// @notice Centralized configuration for Sepolia aggregate deployment
/// @dev Contains all configuration for ParameterRegistry, Oracles, Proxies, and seeding
contract SepoliaDeployConfig {
    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error IndexOutOfBounds();

    // ═══════════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Configuration for ParameterRegistry deployment
    struct RegistryConfig {
        address pendingOwner;
        address pendingUpdater;
    }

    /// @notice Asset configuration for ParameterRegistry
    struct AssetConfig {
        address assetAddress;
        string assetName;
        uint256 oracleIndex; // Index into getOracleConfigs() array - EACAggregatorProxy will be used
        uint64 maxExpectedApy;
        uint32 upperBoundTolerance;
        uint32 lowerBoundTolerance;
        uint32 maxDiscount;
        uint80 lookbackWindowSize;
        bool isUpperBoundEnabled;
        bool isLowerBoundEnabled;
        bool isActionTakingEnabled;
    }

    /// @notice Configuration for LlamaGuardOracle deployment
    struct OracleConfig {
        string name;
        uint8 decimals;
        string description;
        uint256 version;
        string[] updateTypes;
        address[] authorizedMarkets;
    }

    /// @notice Configuration for LlamaGuardOracleProxy deployment
    struct ProxyConfig {
        bytes32 workflowId;
        address expectedForwarder;
        address expectedAuthor;
        bytes10 expectedWorkflowName;
        string description;
    }

    /// @notice Configuration for seeding initial oracle data
    struct SeedConfig {
        address sourceOracle; // AggregatorV3Interface address to read price from
        string updateType; // Update type string for the oracle
        string referenceId; // Reference ID for the update
        bool enabled; // Whether to seed this oracle
    }

    /// @notice Complete configuration for a single oracle deployment
    struct OracleDeploymentConfig {
        OracleConfig oracle;
        ProxyConfig proxy;
        SeedConfig seed;
        address pendingOwner; // For ownership transfer after deployment
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PARAMETER REGISTRY CONFIGURATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Returns ParameterRegistry configuration for Sepolia
    /// @return config The registry configuration
    function getRegistryConfig() public pure returns (RegistryConfig memory config) {
        config = RegistryConfig({
            pendingOwner: 0xb0AD0E3A19490E9145bE9Ad45F7B285eb71756F6,
            pendingUpdater: 0xb0AD0E3A19490E9145bE9Ad45F7B285eb71756F6
        });
    }

    /// @notice Returns asset configurations for ParameterRegistry
    /// @dev Each asset references an oracleIndex which maps to getOracleConfigs()
    ///      The deployment script will use the EACAggregatorProxy address from that oracle deployment
    /// @return assets Array of asset configurations
    function getAssetConfigs() public pure returns (AssetConfig[] memory assets) {
        assets = new AssetConfig[](2);

        // ─────────────────────────────────────────────────────────────────────
        // Asset 0: USCC - linked to Oracle Config 0 (USCC Oracle)
        // ─────────────────────────────────────────────────────────────────────
        assets[0] = AssetConfig({
            assetAddress: 0x862776CC41B728c43D9375Abc65c9CEda6547E28,
            assetName: "USCC",
            oracleIndex: 0, // References USCC oracle in getOracleConfigs()[0]
            maxExpectedApy: 2500, // 25% max APY
            upperBoundTolerance: 50, // 0.5% tolerance
            lowerBoundTolerance: 10, // 0.1% tolerance
            maxDiscount: 40, // 0.4% max discount
            lookbackWindowSize: 7,
            isUpperBoundEnabled: true,
            isLowerBoundEnabled: true,
            isActionTakingEnabled: false
        });

        // ─────────────────────────────────────────────────────────────────────
        // Asset 1: USTB - linked to Oracle Config 1 (USTB Oracle)
        // TODO: Update assetAddress with actual USTB token address on Sepolia
        // ─────────────────────────────────────────────────────────────────────
        assets[1] = AssetConfig({
            assetAddress: address(0x39727692cF58137Bd8c401eFE87Cc8A190D62ead), // TODO: Set USTB token address on
            // Sepolia
            assetName: "USTB",
            oracleIndex: 1, // References USTB oracle in getOracleConfigs()[1]
            maxExpectedApy: 415, // 4.15% max APY
            upperBoundTolerance: 15, // 0.15% tolerance
            lowerBoundTolerance: 5, // 0.05% tolerance
            maxDiscount: 10, // 0.1% max discount
            lookbackWindowSize: 4,
            isUpperBoundEnabled: true,
            isLowerBoundEnabled: true,
            isActionTakingEnabled: false
        });
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ORACLE DEPLOYMENT CONFIGURATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Returns all oracle deployment configurations for Sepolia
    /// @return configs Array of oracle deployment configurations
    function getOracleConfigs() public pure returns (OracleDeploymentConfig[] memory configs) {
        configs = new OracleDeploymentConfig[](2);

        // ─────────────────────────────────────────────────────────────────────
        // Config 0: USCC Oracle
        // ─────────────────────────────────────────────────────────────────────
        string[] memory updateTypes0 = new string[](1);
        updateTypes0[0] = "boundedNAV";

        address[] memory markets0 = new address[](0);

        configs[0] = OracleDeploymentConfig({
            oracle: OracleConfig({
                name: "USCC",
                decimals: 8,
                description: "LlamaGuard USCC Risk Oracle (Sepolia)",
                version: 1,
                updateTypes: updateTypes0,
                authorizedMarkets: markets0
            }),
            proxy: ProxyConfig({
                workflowId: bytes32(0), // TODO: Set Chainlink CRE workflow ID
                expectedForwarder: address(0), // TODO: Set Chainlink CRE forwarder
                expectedAuthor: address(0), // TODO: Set Chainlink CRE author
                expectedWorkflowName: bytes10(0), // TODO: Set workflow name
                description: "LlamaGuard USCC Oracle Proxy (Sepolia)"
            }),
            seed: SeedConfig({
                sourceOracle: 0xE38b0917888d0d5d8d03B7371d5214A1aF8e1892, // Existing USCC oracle
                updateType: "boundedNAV",
                referenceId: "sepolia-seed-v1",
                enabled: true // Set to true to seed from source oracle
            }),
            pendingOwner: address(0) // Keep deployer as owner
        });

        // ─────────────────────────────────────────────────────────────────────
        // Config 1: USTB Oracle
        // ─────────────────────────────────────────────────────────────────────
        string[] memory updateTypes1 = new string[](1);
        updateTypes1[0] = "boundedNAV";

        address[] memory markets1 = new address[](0);

        configs[1] = OracleDeploymentConfig({
            oracle: OracleConfig({
                name: "USTB",
                decimals: 8,
                description: "LlamaGuard USTB Risk Oracle (Sepolia)",
                version: 1,
                updateTypes: updateTypes1,
                authorizedMarkets: markets1
            }),
            proxy: ProxyConfig({
                workflowId: bytes32(0), // TODO: Set Chainlink CRE workflow ID
                expectedForwarder: address(0), // TODO: Set Chainlink CRE forwarder
                expectedAuthor: address(0), // TODO: Set Chainlink CRE author
                expectedWorkflowName: bytes10(0), // TODO: Set workflow name
                description: "LlamaGuard USTB Oracle Proxy (Sepolia)"
            }),
            seed: SeedConfig({
                sourceOracle: 0x732d3C7515356eAB22E3F3DcA183c5c65102d518, // TODO: Set source oracle if seeding needed
                updateType: "boundedNAV",
                referenceId: "sepolia-seed-v1",
                enabled: true // Set to true and provide sourceOracle to enable seeding
            }),
            pendingOwner: address(0) // Keep deployer as owner
        });
    }

    /// @notice Get a single oracle config by index
    /// @param index The index of the configuration
    /// @return config The oracle deployment configuration
    function getOracleConfigByIndex(uint256 index) public pure returns (OracleDeploymentConfig memory config) {
        OracleDeploymentConfig[] memory configs = getOracleConfigs();
        require(index < configs.length, IndexOutOfBounds());
        return configs[index];
    }

    /// @notice Get the number of oracle configurations
    /// @return count The number of configurations
    function getOracleConfigCount() public pure returns (uint256 count) {
        return getOracleConfigs().length;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DEPLOYMENT FLAGS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Returns deployment flags
    /// @return deployRegistry Whether to deploy ParameterRegistry
    /// @return deployOracles Whether to deploy oracles
    /// @return configureAssets Whether to configure assets in registry
    /// @return seedOracles Whether to seed oracles with initial data
    function getDeploymentFlags()
        public
        pure
        returns (bool deployRegistry, bool deployOracles, bool configureAssets, bool seedOracles)
    {
        deployRegistry = true;
        deployOracles = true;
        configureAssets = true; // Only works if oracle addresses are set in getAssetConfigs()
        seedOracles = true; // Will seed oracles where seed.enabled = true
    }
}

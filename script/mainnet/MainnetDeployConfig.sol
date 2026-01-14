// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

/// @title MainnetDeployConfig
/// @author LlamaRisk
/// @notice Centralized configuration for Mainnet aggregate deployment
/// @dev Contains all configuration for LlamaGuard Oracles and Proxies
///      ParameterRegistry is already deployed at 0x69d55d504bc9556e377b340d19818e736bbb318b
contract MainnetDeployConfig {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Already deployed ParameterRegistry address on mainnet
    address public constant PARAMETER_REGISTRY = 0x69D55D504BC9556E377b340D19818E736bbB318b;

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error IndexOutOfBounds();

    // ═══════════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Configuration for LlamaGuardOracle deployment
    struct OracleConfig {
        string name;
        uint8 decimals; // Oracle decimals (from existing oracle)
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

    /// @notice Complete configuration for a single oracle deployment
    struct OracleDeploymentConfig {
        OracleConfig oracle;
        ProxyConfig proxy;
        address pendingOwner; // For ownership transfer after deployment
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ORACLE DEPLOYMENT CONFIGURATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Returns all oracle deployment configurations for Mainnet
    /// @dev Oracle decimals are taken from existing deployed oracles in AssetConfigs
    /// @return configs Array of oracle deployment configurations
    function getOracleConfigs() public pure returns (OracleDeploymentConfig[] memory configs) {
        configs = new OracleDeploymentConfig[](6);

        // ─────────────────────────────────────────────────────────────────────
        // Config 0: JAAA Oracle
        // Asset: 0x5a0F93D040De44e78F251b03c43be9CF317Dcf64
        // Existing Oracle: 0x1E41Ef40AC148706c114534E8192Ca608f80fC48
        // ─────────────────────────────────────────────────────────────────────
        string[] memory updateTypes0 = new string[](1);
        updateTypes0[0] = "boundedNAV";

        address[] memory markets0 = new address[](0);

        configs[0] = OracleDeploymentConfig({
            oracle: OracleConfig({
                name: "JAAA",
                decimals: 6,
                description: "LlamaGuard JAAA Risk Oracle",
                version: 1,
                updateTypes: updateTypes0,
                authorizedMarkets: markets0
            }),
            proxy: ProxyConfig({
                workflowId: bytes32(0), // TODO: Set Chainlink CRE workflow ID
                expectedForwarder: address(0), // TODO: Set Chainlink CRE forwarder
                expectedAuthor: address(0), // TODO: Set Chainlink CRE author
                expectedWorkflowName: bytes10(0), // TODO: Set workflow name
                description: "LlamaGuard JAAA Oracle Proxy"
            }),
            pendingOwner: address(0) // TODO: Set pending owner for ownership transfer
        });

        // ─────────────────────────────────────────────────────────────────────
        // Config 1: USTB Oracle
        // Asset: 0x43415eB6ff9DB7E26A15b704e7A3eDCe97d31C4e
        // Existing Oracle: 0xde49c7B5C0E54b1624ED21C7D88bA6593d444Aa0
        // ─────────────────────────────────────────────────────────────────────
        string[] memory updateTypes1 = new string[](1);
        updateTypes1[0] = "boundedNAV";

        address[] memory markets1 = new address[](0);

        configs[1] = OracleDeploymentConfig({
            oracle: OracleConfig({
                name: "USTB",
                decimals: 6,
                description: "LlamaGuard USTB Risk Oracle",
                version: 1,
                updateTypes: updateTypes1,
                authorizedMarkets: markets1
            }),
            proxy: ProxyConfig({
                workflowId: bytes32(0), // TODO: Set Chainlink CRE workflow ID
                expectedForwarder: address(0), // TODO: Set Chainlink CRE forwarder
                expectedAuthor: address(0), // TODO: Set Chainlink CRE author
                expectedWorkflowName: bytes10(0), // TODO: Set workflow name
                description: "LlamaGuard USTB Oracle Proxy"
            }),
            pendingOwner: address(0) // TODO: Set pending owner for ownership transfer
        });

        // ─────────────────────────────────────────────────────────────────────
        // Config 2: JTRSY Oracle
        // Asset: 0x8c213ee79581Ff4984583C6a801e5263418C4b86
        // Existing Oracle: 0x23adce82907D20c509101E2Af0723A9e16224EFb
        // ─────────────────────────────────────────────────────────────────────
        string[] memory updateTypes2 = new string[](1);
        updateTypes2[0] = "boundedNAV";

        address[] memory markets2 = new address[](0);

        configs[2] = OracleDeploymentConfig({
            oracle: OracleConfig({
                name: "JTRSY",
                decimals: 6,
                description: "LlamaGuard JTRSY Risk Oracle",
                version: 1,
                updateTypes: updateTypes2,
                authorizedMarkets: markets2
            }),
            proxy: ProxyConfig({
                workflowId: bytes32(0), // TODO: Set Chainlink CRE workflow ID
                expectedForwarder: address(0), // TODO: Set Chainlink CRE forwarder
                expectedAuthor: address(0), // TODO: Set Chainlink CRE author
                expectedWorkflowName: bytes10(0), // TODO: Set workflow name
                description: "LlamaGuard JTRSY Oracle Proxy"
            }),
            pendingOwner: address(0) // TODO: Set pending owner for ownership transfer
        });

        // ─────────────────────────────────────────────────────────────────────
        // Config 3: USCC Oracle
        // Asset: 0x14d60E7FDC0D71d8611742720E4C50E7a974020c
        // Existing Oracle: 0x19e2d716288751c5A59deaB61af012D5DF895962
        // ─────────────────────────────────────────────────────────────────────
        string[] memory updateTypes3 = new string[](1);
        updateTypes3[0] = "boundedNAV";

        address[] memory markets3 = new address[](0);

        configs[3] = OracleDeploymentConfig({
            oracle: OracleConfig({
                name: "USCC",
                decimals: 6,
                description: "LlamaGuard USCC Risk Oracle",
                version: 1,
                updateTypes: updateTypes3,
                authorizedMarkets: markets3
            }),
            proxy: ProxyConfig({
                workflowId: bytes32(0), // TODO: Set Chainlink CRE workflow ID
                expectedForwarder: address(0), // TODO: Set Chainlink CRE forwarder
                expectedAuthor: address(0), // TODO: Set Chainlink CRE author
                expectedWorkflowName: bytes10(0), // TODO: Set workflow name
                description: "LlamaGuard USCC Oracle Proxy"
            }),
            pendingOwner: address(0) // TODO: Set pending owner for ownership transfer
        });

        // ─────────────────────────────────────────────────────────────────────
        // Config 4: USYC Oracle
        // Asset: 0x136471a34f6ef19fE571EFFC1CA711fdb8E49f2b
        // Existing Oracle: 0xE8E65Fb9116875012F5990Ecaab290B3531DbeB9
        // ─────────────────────────────────────────────────────────────────────
        string[] memory updateTypes4 = new string[](1);
        updateTypes4[0] = "boundedNAV";

        address[] memory markets4 = new address[](0);

        configs[4] = OracleDeploymentConfig({
            oracle: OracleConfig({
                name: "USYC",
                decimals: 8,
                description: "LlamaGuard USYC Risk Oracle",
                version: 1,
                updateTypes: updateTypes4,
                authorizedMarkets: markets4
            }),
            proxy: ProxyConfig({
                workflowId: bytes32(0), // TODO: Set Chainlink CRE workflow ID
                expectedForwarder: address(0), // TODO: Set Chainlink CRE forwarder
                expectedAuthor: address(0), // TODO: Set Chainlink CRE author
                expectedWorkflowName: bytes10(0), // TODO: Set workflow name
                description: "LlamaGuard USYC Oracle Proxy"
            }),
            pendingOwner: address(0) // TODO: Set pending owner for ownership transfer
        });

        // ─────────────────────────────────────────────────────────────────────
        // Config 5: vBILL Oracle (NEW - not in existing AssetConfigs)
        // Asset: 0x2255718832bC9fD3bE1CaF75084F4803DA14FF01
        // Existing Oracle: 0x5ed77a9D9b7cc80E9d0D7711024AF38C2643C1c4
        // ─────────────────────────────────────────────────────────────────────
        string[] memory updateTypes5 = new string[](1);
        updateTypes5[0] = "boundedNAV";

        address[] memory markets5 = new address[](0);

        configs[5] = OracleDeploymentConfig({
            oracle: OracleConfig({
                name: "vBILL",
                decimals: 8,
                description: "LlamaGuard vBILL Risk Oracle",
                version: 1,
                updateTypes: updateTypes5,
                authorizedMarkets: markets5
            }),
            proxy: ProxyConfig({
                workflowId: bytes32(0), // TODO: Set Chainlink CRE workflow ID
                expectedForwarder: address(0), // TODO: Set Chainlink CRE forwarder
                expectedAuthor: address(0), // TODO: Set Chainlink CRE author
                expectedWorkflowName: bytes10(0), // TODO: Set workflow name
                description: "LlamaGuard vBILL Oracle Proxy"
            }),
            pendingOwner: address(0) // TODO: Set pending owner for ownership transfer
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
    /// @return deployOracles Whether to deploy oracles
    function getDeploymentFlags() public pure returns (bool deployOracles) {
        deployOracles = true;
    }
}

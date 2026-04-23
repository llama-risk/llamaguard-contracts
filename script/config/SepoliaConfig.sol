// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { DeployStructs } from "./DeployStructs.sol";
import { Addresses } from "./Addresses.sol";

/// @title SepoliaConfig
/// @notice Consolidated Sepolia configuration for oracles, agents, and asset registry
/// @dev Consolidates SepoliaDeployConfig. Same interface as MainnetConfig.
contract SepoliaConfig {
    error UnknownAsset();

    // ═══════════════════════════════════════════════════════════════════════════
    // ORACLE CONFIGURATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Get oracle deployment config for a named asset
    function getOracleConfig(string memory assetName)
        public
        pure
        returns (DeployStructs.OracleDeploymentConfig memory)
    {
        bytes32 key = keccak256(abi.encodePacked(assetName));

        if (key == keccak256("USCC")) return _usccOracleConfig();
        if (key == keccak256("USTB")) return _ustbOracleConfig();

        revert UnknownAsset();
    }

    /// @notice Get USTB oracle config (convenience for single-asset deploy)
    function getUstbOracleConfig() public pure returns (DeployStructs.OracleDeploymentConfig memory) {
        return _ustbOracleConfig();
    }

    /// @notice Get all oracle deployment configs for Sepolia
    function getAllOracleConfigs() public pure returns (DeployStructs.OracleDeploymentConfig[] memory configs) {
        configs = new DeployStructs.OracleDeploymentConfig[](2);
        configs[0] = _usccOracleConfig();
        configs[1] = _ustbOracleConfig();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SEED CONFIGURATIONS (Sepolia only)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Get seed config for a named asset
    function getSeedConfig(string memory assetName) public pure returns (DeployStructs.SeedConfig memory) {
        bytes32 key = keccak256(abi.encodePacked(assetName));

        if (key == keccak256("USCC")) {
            return DeployStructs.SeedConfig({
                sourceOracle: Addresses.SEPOLIA_USCC_SOURCE_ORACLE,
                updateType: "boundedNAV",
                referenceId: "sepolia-seed-v1",
                enabled: true
            });
        }

        if (key == keccak256("USTB")) {
            return DeployStructs.SeedConfig({
                sourceOracle: Addresses.SEPOLIA_USTB_SOURCE_ORACLE,
                updateType: "boundedNAV",
                referenceId: "sepolia-seed-v1",
                enabled: true
            });
        }

        revert UnknownAsset();
    }

    /// @notice Get USTB seed config (convenience for single-asset deploy)
    function getUstbSeedConfig() public pure returns (DeployStructs.SeedConfig memory) {
        return getSeedConfig("USTB");
    }

    /// @notice Get all seed configs
    function getAllSeedConfigs() public pure returns (DeployStructs.SeedConfig[] memory configs) {
        configs = new DeployStructs.SeedConfig[](2);
        configs[0] = getSeedConfig("USCC");
        configs[1] = getSeedConfig("USTB");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // AGENT REGISTRATION CONFIGURATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Get agent registration config for a named asset
    /// @dev agentAddress and riskOracle must be set by the caller after deployment
    function getAgentConfig(string memory assetName)
        public
        pure
        returns (DeployStructs.AgentRegistrationConfig memory config)
    {
        bytes32 key = keccak256(abi.encodePacked(assetName));
        address token;

        if (key == keccak256("USCC")) token = Addresses.SEPOLIA_USCC;
        else if (key == keccak256("USTB")) token = Addresses.SEPOLIA_USTB;
        else revert UnknownAsset();

        address[] memory markets = new address[](1);
        markets[0] = token;

        address[] memory senders = new address[](1);
        senders[0] = Addresses.SEPOLIA_DEPLOYER;

        config = DeployStructs.AgentRegistrationConfig({
            agentAddress: address(0), // Set after deployment
            riskOracle: address(0), // Set after deployment
            admin: Addresses.SEPOLIA_DEPLOYER,
            poolConfigurator: Addresses.SEPOLIA_AAVE_HORIZON_POOL_CONFIGURATOR,
            expirationPeriod: 1 days,
            minimumDelay: 0,
            updateType: "boundedNAV",
            allowedMarkets: markets,
            isAgentPermissioned: true,
            permissionedSenders: senders
        });
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ASSET CONFIGS (ParameterRegistry)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Get all asset configs for Sepolia ParameterRegistry
    function getAllAssetConfigs() public pure returns (DeployStructs.AssetConfig[] memory assets) {
        assets = new DeployStructs.AssetConfig[](2);

        assets[0] = DeployStructs.AssetConfig({
            assetAddress: Addresses.SEPOLIA_USCC,
            assetName: "USCC",
            oracle: address(0), // Set to EACAggregatorProxy after deployment
            maxExpectedApy: 2500,
            upperBoundTolerance: 50,
            lowerBoundTolerance: 10,
            maxDiscount: 40,
            lookbackWindowSize: 7,
            isUpperBoundEnabled: true,
            isLowerBoundEnabled: true,
            isActionTakingEnabled: false
        });

        assets[1] = DeployStructs.AssetConfig({
            assetAddress: Addresses.SEPOLIA_USTB,
            assetName: "USTB",
            oracle: address(0), // Set to EACAggregatorProxy after deployment
            maxExpectedApy: 415,
            upperBoundTolerance: 15,
            lowerBoundTolerance: 5,
            maxDiscount: 10,
            lookbackWindowSize: 4,
            isUpperBoundEnabled: true,
            isLowerBoundEnabled: true,
            isActionTakingEnabled: false
        });
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REGISTRY OWNERSHIP
    // ═══════════════════════════════════════════════════════════════════════════

    function getRegistryPendingOwner() public pure returns (address) {
        return Addresses.SEPOLIA_DEPLOYER;
    }

    function getRegistryPendingUpdater() public pure returns (address) {
        return Addresses.SEPOLIA_DEPLOYER;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL ORACLE CONFIGS
    // ═══════════════════════════════════════════════════════════════════════════

    function _makeUpdateTypes() internal pure returns (string[] memory types) {
        types = new string[](1);
        types[0] = "boundedNAV";
    }

    function _emptyMarkets() internal pure returns (address[] memory) {
        return new address[](0);
    }

    function _usccOracleConfig() internal pure returns (DeployStructs.OracleDeploymentConfig memory) {
        return DeployStructs.OracleDeploymentConfig({
            oracle: DeployStructs.OracleConfig({
                name: "USCC",
                decimals: 8,
                description: "LlamaGuard USCC Risk Oracle (Sepolia)",
                version: 1,
                updateTypes: _makeUpdateTypes(),
                authorizedMarkets: _emptyMarkets()
            }),
            proxy: DeployStructs.ProxyConfig({
                workflowId: bytes32(0), // TODO: Set for Sepolia
                expectedForwarder: address(0), // TODO: Set for Sepolia
                expectedAuthor: address(0), // TODO: Set for Sepolia
                expectedWorkflowName: bytes10(0), // TODO: Set for Sepolia
                description: "LlamaGuard USCC Oracle Proxy (Sepolia)"
            }),
            pendingOwner: address(0)
        });
    }

    function _ustbOracleConfig() internal pure returns (DeployStructs.OracleDeploymentConfig memory) {
        return DeployStructs.OracleDeploymentConfig({
            oracle: DeployStructs.OracleConfig({
                name: "USTB",
                decimals: 8,
                description: "LlamaGuard USTB Risk Oracle (Sepolia)",
                version: 1,
                updateTypes: _makeUpdateTypes(),
                authorizedMarkets: _emptyMarkets()
            }),
            proxy: DeployStructs.ProxyConfig({
                workflowId: 0x00a9cf308e875f62fb6df1f6e1a55dd7db46384876e4059c35abd54125a9c1af,
                expectedForwarder: Addresses.SEPOLIA_CRE_FORWARDER,
                expectedAuthor: Addresses.SEPOLIA_CRE_AUTHOR,
                expectedWorkflowName: _creWorkflowName("llamaguard_nav_ustb_dev"),
                description: "LlamaGuard USTB Oracle Proxy (Sepolia)"
            }),
            pendingOwner: address(0)
        });
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CRE WORKFLOW NAME DERIVATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Derive CRE workflow name from human-readable name
    /// @dev Chainlink CRE workflow name derivation:
    ///      1. SHA-256 hash of the workflow name string
    ///      2. Hex-encode the hash
    ///      3. Take first 10 hex characters
    ///      4. Store as bytes10 (ASCII)
    function _creWorkflowName(string memory workflowName) internal pure returns (bytes10) {
        bytes32 hash = sha256(bytes(workflowName));
        bytes memory hexChars = "0123456789abcdef";
        bytes memory result = new bytes(10);
        for (uint256 i = 0; i < 5; i++) {
            uint8 b = uint8(hash[i]);
            result[i * 2] = hexChars[b >> 4];
            result[i * 2 + 1] = hexChars[b & 0x0f];
        }
        return bytes10(bytes(result));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { DeployStructs } from "./DeployStructs.sol";
import { Addresses } from "./Addresses.sol";

/// @title MainnetConfig
/// @notice Consolidated mainnet configuration for oracles, agents, and asset registry
/// @dev Consolidates MainnetDeployConfig + AssetConfigs + LlamaGuardOracleConfig (mainnet)
contract MainnetConfig {
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

        if (key == keccak256("USTB")) return _ustbOracleConfig();
        if (key == keccak256("USCC")) return _usccOracleConfig();
        if (key == keccak256("USYC")) return _usycOracleConfig();
        if (key == keccak256("JTRSY")) return _jtrsyOracleConfig();
        if (key == keccak256("JAAA")) return _jaaaOracleConfig();
        if (key == keccak256("ACRED")) return _acredOracleConfig();
        if (key == keccak256("vBILL")) return _vbillOracleConfig();

        revert UnknownAsset();
    }

    /// @notice Get all oracle deployment configs
    function getAllOracleConfigs() public pure returns (DeployStructs.OracleDeploymentConfig[] memory configs) {
        configs = new DeployStructs.OracleDeploymentConfig[](7);
        configs[0] = _ustbOracleConfig();
        configs[1] = _usccOracleConfig();
        configs[2] = _usycOracleConfig();
        configs[3] = _jtrsyOracleConfig();
        configs[4] = _jaaaOracleConfig();
        configs[5] = _acredOracleConfig();
        configs[6] = _vbillOracleConfig();
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

        if (key == keccak256("USTB")) token = Addresses.USTB;
        else if (key == keccak256("USCC")) token = Addresses.USCC;
        else if (key == keccak256("USYC")) token = Addresses.USYC;
        else if (key == keccak256("JTRSY")) token = Addresses.JTRSY;
        else if (key == keccak256("JAAA")) token = Addresses.JAAA;
        else if (key == keccak256("ACRED")) token = Addresses.ACRED;
        else revert UnknownAsset();

        address[] memory markets = new address[](1);
        markets[0] = token;

        address[] memory senders = new address[](1);
        senders[0] = Addresses.LLAMARISK_MULTISIG;

        config = DeployStructs.AgentRegistrationConfig({
            agentAddress: address(0), // Set after deployment
            riskOracle: address(0), // Set after deployment
            admin: Addresses.LLAMARISK_MULTISIG,
            poolConfigurator: Addresses.AAVE_HORIZON_POOL_CONFIGURATOR,
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

    /// @notice Get asset config for ParameterRegistry by name
    function getAssetConfig(string memory assetName) public pure returns (DeployStructs.AssetConfig memory) {
        bytes32 key = keccak256(abi.encodePacked(assetName));

        if (key == keccak256("JAAA")) {
            return DeployStructs.AssetConfig({
                assetAddress: Addresses.JAAA,
                assetName: "JAAA",
                oracle: Addresses.JAAA_ORACLE,
                maxExpectedApy: 520,
                upperBoundTolerance: 50,
                lowerBoundTolerance: 10,
                maxDiscount: 75,
                lookbackWindowSize: 4,
                isUpperBoundEnabled: true,
                isLowerBoundEnabled: true,
                isActionTakingEnabled: false
            });
        }

        if (key == keccak256("USTB")) {
            return DeployStructs.AssetConfig({
                assetAddress: Addresses.USTB,
                assetName: "USTB",
                oracle: Addresses.USTB_ORACLE,
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

        if (key == keccak256("JTRSY")) {
            return DeployStructs.AssetConfig({
                assetAddress: Addresses.JTRSY,
                assetName: "JTRSY",
                oracle: Addresses.JTRSY_ORACLE,
                maxExpectedApy: 390,
                upperBoundTolerance: 15,
                lowerBoundTolerance: 5,
                maxDiscount: 10,
                lookbackWindowSize: 4,
                isUpperBoundEnabled: true,
                isLowerBoundEnabled: true,
                isActionTakingEnabled: false
            });
        }

        if (key == keccak256("USCC")) {
            return DeployStructs.AssetConfig({
                assetAddress: Addresses.USCC,
                assetName: "USCC",
                oracle: Addresses.USCC_ORACLE,
                maxExpectedApy: 2500,
                upperBoundTolerance: 50,
                lowerBoundTolerance: 10,
                maxDiscount: 40,
                lookbackWindowSize: 4,
                isUpperBoundEnabled: true,
                isLowerBoundEnabled: true,
                isActionTakingEnabled: false
            });
        }

        if (key == keccak256("USYC")) {
            return DeployStructs.AssetConfig({
                assetAddress: Addresses.USYC,
                assetName: "USYC",
                oracle: Addresses.USYC_ORACLE,
                maxExpectedApy: 420,
                upperBoundTolerance: 15,
                lowerBoundTolerance: 5,
                maxDiscount: 10,
                lookbackWindowSize: 4,
                isUpperBoundEnabled: true,
                isLowerBoundEnabled: true,
                isActionTakingEnabled: false
            });
        }

        revert UnknownAsset();
    }

    /// @notice Get all asset configs for ParameterRegistry
    function getAllAssetConfigs() public pure returns (DeployStructs.AssetConfig[] memory assets) {
        assets = new DeployStructs.AssetConfig[](5);
        assets[0] = getAssetConfig("JAAA");
        assets[1] = getAssetConfig("USTB");
        assets[2] = getAssetConfig("JTRSY");
        assets[3] = getAssetConfig("USCC");
        assets[4] = getAssetConfig("USYC");
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

    function _ustbOracleConfig() internal pure returns (DeployStructs.OracleDeploymentConfig memory) {
        return DeployStructs.OracleDeploymentConfig({
            oracle: DeployStructs.OracleConfig({
                name: "USTB",
                decimals: 6,
                description: "LlamaGuard USTB Risk Oracle",
                version: 1,
                updateTypes: _makeUpdateTypes(),
                authorizedMarkets: _emptyMarkets()
            }),
            proxy: DeployStructs.ProxyConfig({
                workflowId: bytes32(0), // TODO: Set Chainlink CRE workflow ID
                expectedForwarder: address(0), // TODO: Set Chainlink CRE forwarder
                expectedAuthor: address(0), // TODO: Set Chainlink CRE author
                expectedWorkflowName: bytes10(0), // TODO: Set workflow name
                description: "LlamaGuard USTB Oracle Proxy"
            }),
            pendingOwner: address(0) // TODO: Set pending owner
        });
    }

    function _usccOracleConfig() internal pure returns (DeployStructs.OracleDeploymentConfig memory) {
        return DeployStructs.OracleDeploymentConfig({
            oracle: DeployStructs.OracleConfig({
                name: "USCC",
                decimals: 6,
                description: "LlamaGuard USCC Risk Oracle",
                version: 1,
                updateTypes: _makeUpdateTypes(),
                authorizedMarkets: _emptyMarkets()
            }),
            proxy: DeployStructs.ProxyConfig({
                workflowId: bytes32(0),
                expectedForwarder: address(0),
                expectedAuthor: address(0),
                expectedWorkflowName: bytes10(0),
                description: "LlamaGuard USCC Oracle Proxy"
            }),
            pendingOwner: address(0)
        });
    }

    function _usycOracleConfig() internal pure returns (DeployStructs.OracleDeploymentConfig memory) {
        return DeployStructs.OracleDeploymentConfig({
            oracle: DeployStructs.OracleConfig({
                name: "USYC",
                decimals: 8,
                description: "LlamaGuard USYC Risk Oracle",
                version: 1,
                updateTypes: _makeUpdateTypes(),
                authorizedMarkets: _emptyMarkets()
            }),
            proxy: DeployStructs.ProxyConfig({
                workflowId: bytes32(0),
                expectedForwarder: address(0),
                expectedAuthor: address(0),
                expectedWorkflowName: bytes10(0),
                description: "LlamaGuard USYC Oracle Proxy"
            }),
            pendingOwner: address(0)
        });
    }

    function _jtrsyOracleConfig() internal pure returns (DeployStructs.OracleDeploymentConfig memory) {
        return DeployStructs.OracleDeploymentConfig({
            oracle: DeployStructs.OracleConfig({
                name: "JTRSY",
                decimals: 6,
                description: "LlamaGuard JTRSY Risk Oracle",
                version: 1,
                updateTypes: _makeUpdateTypes(),
                authorizedMarkets: _emptyMarkets()
            }),
            proxy: DeployStructs.ProxyConfig({
                workflowId: bytes32(0),
                expectedForwarder: address(0),
                expectedAuthor: address(0),
                expectedWorkflowName: bytes10(0),
                description: "LlamaGuard JTRSY Oracle Proxy"
            }),
            pendingOwner: address(0)
        });
    }

    function _jaaaOracleConfig() internal pure returns (DeployStructs.OracleDeploymentConfig memory) {
        return DeployStructs.OracleDeploymentConfig({
            oracle: DeployStructs.OracleConfig({
                name: "JAAA",
                decimals: 6,
                description: "LlamaGuard JAAA Risk Oracle",
                version: 1,
                updateTypes: _makeUpdateTypes(),
                authorizedMarkets: _emptyMarkets()
            }),
            proxy: DeployStructs.ProxyConfig({
                workflowId: bytes32(0),
                expectedForwarder: address(0),
                expectedAuthor: address(0),
                expectedWorkflowName: bytes10(0),
                description: "LlamaGuard JAAA Oracle Proxy"
            }),
            pendingOwner: address(0)
        });
    }

    function _acredOracleConfig() internal pure returns (DeployStructs.OracleDeploymentConfig memory) {
        return DeployStructs.OracleDeploymentConfig({
            oracle: DeployStructs.OracleConfig({
                name: "ACRED",
                decimals: 8,
                description: "LlamaGuard ACRED Risk Oracle",
                version: 1,
                updateTypes: _makeUpdateTypes(),
                authorizedMarkets: _emptyMarkets()
            }),
            proxy: DeployStructs.ProxyConfig({
                workflowId: bytes32(0),
                expectedForwarder: address(0),
                expectedAuthor: address(0),
                expectedWorkflowName: bytes10(0),
                description: "LlamaGuard ACRED Oracle Proxy"
            }),
            pendingOwner: address(0)
        });
    }

    function _vbillOracleConfig() internal pure returns (DeployStructs.OracleDeploymentConfig memory) {
        return DeployStructs.OracleDeploymentConfig({
            oracle: DeployStructs.OracleConfig({
                name: "vBILL",
                decimals: 8,
                description: "LlamaGuard vBILL Risk Oracle",
                version: 1,
                updateTypes: _makeUpdateTypes(),
                authorizedMarkets: _emptyMarkets()
            }),
            proxy: DeployStructs.ProxyConfig({
                workflowId: bytes32(0),
                expectedForwarder: address(0),
                expectedAuthor: address(0),
                expectedWorkflowName: bytes10(0),
                description: "LlamaGuard vBILL Oracle Proxy"
            }),
            pendingOwner: address(0)
        });
    }
}

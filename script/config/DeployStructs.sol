// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

/// @title DeployStructs
/// @notice Shared struct definitions for all deploy scripts (single source of truth)
library DeployStructs {
    // ═══════════════════════════════════════════════════════════════════════════
    // ORACLE + PROXY DEPLOYMENT
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Configuration for LlamaGuardOracle deployment
    struct OracleConfig {
        string name;
        uint8 decimals;
        string description;
        uint256 version;
        string[] updateTypes;
        address[] authorizedMarkets;
    }

    /// @notice Configuration for LlamaGuardOracleProxy deployment (Chainlink CRE parameters)
    struct ProxyConfig {
        bytes32 workflowId;
        address expectedForwarder;
        address expectedAuthor;
        bytes10 expectedWorkflowName;
        string description;
    }

    /// @notice Combined deployment configuration for a single oracle+proxy pair
    struct OracleDeploymentConfig {
        OracleConfig oracle;
        ProxyConfig proxy;
        address pendingOwner; // For two-step ownership transfer after deployment
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // AGENT HUB REGISTRATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Configuration for registering an agent in HorizonAgentHub
    struct AgentRegistrationConfig {
        address agentAddress;
        address riskOracle;
        address admin;
        address poolConfigurator;
        uint256 expirationPeriod;
        uint256 minimumDelay;
        string updateType;
        address[] allowedMarkets;
        bool isAgentPermissioned;
        address[] permissionedSenders;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PARAMETER REGISTRY
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Asset configuration for ParameterRegistry
    struct AssetConfig {
        address assetAddress;
        string assetName;
        address oracle;
        uint64 maxExpectedApy;
        uint32 upperBoundTolerance;
        uint32 lowerBoundTolerance;
        uint32 maxDiscount;
        uint80 lookbackWindowSize;
        bool isUpperBoundEnabled;
        bool isLowerBoundEnabled;
        bool isActionTakingEnabled;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CHAINLINK CRE WORKFLOW
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Configuration for Chainlink CRE workflow on an oracle proxy
    struct CreWorkflowConfig {
        address proxyAddress;
        bytes32 workflowId;
        address expectedForwarder;
        address expectedAuthor;
        bytes10 expectedWorkflowName;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SEPOLIA SEEDING
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Configuration for seeding initial oracle data (Sepolia only)
    struct SeedConfig {
        address sourceOracle;
        string updateType;
        string referenceId;
        bool enabled;
    }
}

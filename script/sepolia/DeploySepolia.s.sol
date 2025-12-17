// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { ParameterRegistry } from "../../src/ParameterRegistry.sol";
import { LlamaGuardOracle } from "../../src/LlamaGuardOracle.sol";
import { LlamaGuardOracleProxy } from "../../src/LlamaGuardOracleProxy.sol";
import { ILlamaGuardOracle } from "../../src/interfaces/ILlamaGuardOracle.sol";
import { EACAggregatorProxy } from "../../src/sepolia/EACAggregatorProxy.sol";
import { BaseScript } from "../Base.s.sol";
import { SepoliaDeployConfig } from "./SepoliaDeployConfig.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { console2 } from "forge-std/console2.sol";

/// @title DeploySepolia
/// @author LlamaRisk
/// @notice Aggregate deployment script for Sepolia testnet
/// @dev Deploys based on configuration in SepoliaDeployConfig:
///      1. ParameterRegistry with asset configurations
///      2. LlamaGuardOracle + LlamaGuardOracleProxy pairs
///      3. EACAggregatorProxy for each oracle
///      4. Seeds initial oracle data from existing AggregatorV3 sources
contract DeploySepolia is BaseScript {
    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error NotOnSepolia();
    error InvalidOracleIndex();
    error ArrayLengthMismatch();

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════════

    SepoliaDeployConfig internal config;

    /// @notice Struct to hold all deployed contract addresses
    struct DeployedContracts {
        address parameterRegistry;
        OracleDeployment[] oracles;
    }

    /// @notice Struct to hold oracle deployment addresses
    struct OracleDeployment {
        string name;
        address oracle;
        address proxy;
        address eacProxy;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SETUP
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Initialize the deployment configuration
    function setUp() public {
        config = new SepoliaDeployConfig();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MAIN DEPLOYMENT FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Deploy everything for Sepolia based on configuration
    /// @return deployed Struct containing all deployed contract addresses
    function run() public broadcast returns (DeployedContracts memory deployed) {
        if (block.chainid != 11_155_111) revert NotOnSepolia();

        (bool deployRegistry, bool deployOracles, bool configureAssets, bool seedOracles) = config.getDeploymentFlags();

        console2.log("=========================================");
        console2.log("Sepolia Aggregate Deployment");
        console2.log("=========================================");
        console2.log("Chain ID:", block.chainid);
        console2.log("Broadcaster:", broadcaster);
        console2.log("");
        console2.log("Deployment Flags:");
        console2.log("  Deploy Registry:", deployRegistry);
        console2.log("  Deploy Oracles:", deployOracles);
        console2.log("  Configure Assets:", configureAssets);
        console2.log("  Seed Oracles:", seedOracles);
        console2.log("=========================================");

        // Step 1: Deploy Oracles first (so we have EAC addresses for registry)
        if (deployOracles) {
            deployed.oracles = _deployAllOracles(seedOracles);
        }

        // Step 2: Deploy ParameterRegistry
        if (deployRegistry) {
            deployed.parameterRegistry = address(_deployParameterRegistry(configureAssets, deployed.oracles));
        }

        _logDeploymentSummary(deployed);
    }

    /// @notice Deploy only ParameterRegistry
    /// @return parameterRegistry The deployed registry
    function deployRegistryOnly() public broadcast returns (ParameterRegistry parameterRegistry) {
        if (block.chainid != 11_155_111) revert NotOnSepolia();

        OracleDeployment[] memory emptyOracles;
        return _deployParameterRegistry(true, emptyOracles);
    }

    /// @notice Deploy only oracles (without ParameterRegistry)
    /// @return oracles Array of oracle deployments
    function deployOraclesOnly() public broadcast returns (OracleDeployment[] memory oracles) {
        if (block.chainid != 11_155_111) revert NotOnSepolia();

        (,,, bool seedOracles) = config.getDeploymentFlags();
        return _deployAllOracles(seedOracles);
    }

    /// @notice Deploy a single oracle set by index
    /// @param index The index of the oracle configuration to deploy
    /// @return deployment The oracle deployment addresses
    function deploySingleOracle(uint256 index) public broadcast returns (OracleDeployment memory deployment) {
        if (block.chainid != 11_155_111) revert NotOnSepolia();

        SepoliaDeployConfig.OracleDeploymentConfig memory oracleConfig = config.getOracleConfigByIndex(index);
        (,,, bool seedOracles) = config.getDeploymentFlags();

        deployment = _deploySingleOracleSet(oracleConfig, seedOracles);

        console2.log("");
        console2.log("=========================================");
        console2.log("Single Oracle Deployment Complete");
        console2.log("=========================================");
        console2.log("Name:", deployment.name);
        console2.log("Oracle:", deployment.oracle);
        console2.log("Proxy:", deployment.proxy);
        console2.log("EAC Proxy:", deployment.eacProxy);
        console2.log("=========================================");
    }

    /// @notice Seed data on existing deployed oracles
    /// @param proxyAddresses Array of LlamaGuardOracleProxy addresses to seed
    function seedExistingOracles(address[] calldata proxyAddresses) public broadcast {
        if (block.chainid != 11_155_111) revert NotOnSepolia();

        SepoliaDeployConfig.OracleDeploymentConfig[] memory configs = config.getOracleConfigs();
        if (proxyAddresses.length != configs.length) revert ArrayLengthMismatch();

        console2.log("");
        console2.log("-----------------------------------------");
        console2.log("Seeding Existing Oracles");
        console2.log("-----------------------------------------");

        for (uint256 i = 0; i < configs.length; ++i) {
            if (configs[i].seed.enabled && configs[i].seed.sourceOracle != address(0)) {
                _seedSingleOracle(proxyAddresses[i], configs[i].seed);
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL DEPLOYMENT FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Deploy ParameterRegistry with configuration
    /// @param configureAssets Whether to configure assets
    /// @param oracles Deployed oracle addresses (for asset oracle configuration)
    /// @return parameterRegistry The deployed registry
    function _deployParameterRegistry(
        bool configureAssets,
        OracleDeployment[] memory oracles
    )
        internal
        returns (ParameterRegistry parameterRegistry)
    {
        console2.log("");
        console2.log("-----------------------------------------");
        console2.log("Deploying ParameterRegistry");
        console2.log("-----------------------------------------");

        // Deploy with broadcaster as initial owner/updater
        parameterRegistry = new ParameterRegistry(broadcaster, broadcaster);
        console2.log("  [OK] Deployed at:", address(parameterRegistry));

        // Configure assets if requested
        if (configureAssets) {
            _configureAssets(parameterRegistry, oracles);
        }

        // Transfer roles if needed
        SepoliaDeployConfig.RegistryConfig memory registryConfig = config.getRegistryConfig();

        if (registryConfig.pendingUpdater != address(0) && registryConfig.pendingUpdater != broadcaster) {
            parameterRegistry.setUpdater(registryConfig.pendingUpdater);
            console2.log("  [OK] Updater transferred to:", registryConfig.pendingUpdater);
        }

        if (registryConfig.pendingOwner != address(0) && registryConfig.pendingOwner != broadcaster) {
            parameterRegistry.transferOwnership(registryConfig.pendingOwner);
            console2.log("  [OK] Ownership transfer initiated to:", registryConfig.pendingOwner);
        }
    }

    /// @notice Configure assets in the ParameterRegistry
    /// @param parameterRegistry The deployed registry
    /// @param oracles Deployed oracle addresses (to get EACAggregatorProxy addresses)
    function _configureAssets(ParameterRegistry parameterRegistry, OracleDeployment[] memory oracles) internal {
        SepoliaDeployConfig.AssetConfig[] memory assets = config.getAssetConfigs();
        console2.log("  Configuring", assets.length, "assets...");

        for (uint256 i = 0; i < assets.length; ++i) {
            SepoliaDeployConfig.AssetConfig memory asset = assets[i];

            // Skip if asset address not set
            if (asset.assetAddress == address(0)) {
                console2.log("    - Skipping", asset.assetName, "(no asset address)");
                continue;
            }

            // Get EAC proxy address from deployed oracles using oracleIndex
            address oracleAddress;
            if (asset.oracleIndex < oracles.length) {
                oracleAddress = oracles[asset.oracleIndex].eacProxy;
            }

            // Skip if no oracle address available
            if (oracleAddress == address(0)) {
                console2.log("    - Skipping", asset.assetName, "(no oracle deployed)");
                continue;
            }

            console2.log("    -", asset.assetName, "oracle:", oracleAddress);

            parameterRegistry.setParametersForAsset(
                asset.assetAddress,
                asset.assetName,
                oracleAddress,
                asset.maxExpectedApy,
                asset.upperBoundTolerance,
                asset.lowerBoundTolerance,
                asset.maxDiscount,
                asset.lookbackWindowSize,
                asset.isUpperBoundEnabled,
                asset.isLowerBoundEnabled,
                asset.isActionTakingEnabled
            );
        }
        console2.log("  [OK] Assets configured");
    }

    /// @notice Deploy all oracle configurations
    /// @param seedOracles Whether to seed oracles with initial data
    /// @return deployments Array of oracle deployments
    function _deployAllOracles(bool seedOracles) internal returns (OracleDeployment[] memory deployments) {
        SepoliaDeployConfig.OracleDeploymentConfig[] memory configs = config.getOracleConfigs();

        console2.log("");
        console2.log("-----------------------------------------");
        console2.log("Deploying", configs.length, "Oracle Sets");
        console2.log("-----------------------------------------");

        deployments = new OracleDeployment[](configs.length);

        for (uint256 i = 0; i < configs.length; ++i) {
            deployments[i] = _deploySingleOracleSet(configs[i], seedOracles);
        }
    }

    /// @notice Deploy a single oracle set (Oracle + Proxy + EAC)
    /// @param oracleConfig The oracle deployment configuration
    /// @param seedOracle Whether to seed this oracle
    /// @return deployment The deployed addresses
    function _deploySingleOracleSet(
        SepoliaDeployConfig.OracleDeploymentConfig memory oracleConfig,
        bool seedOracle
    )
        internal
        returns (OracleDeployment memory deployment)
    {
        console2.log("");
        console2.log("  Deploying:", oracleConfig.oracle.name);

        // 1. Deploy LlamaGuardOracle
        LlamaGuardOracle oracle = new LlamaGuardOracle(
            oracleConfig.oracle.decimals,
            oracleConfig.oracle.description,
            oracleConfig.oracle.version,
            oracleConfig.oracle.updateTypes,
            oracleConfig.oracle.authorizedMarkets
        );
        console2.log("    [OK] LlamaGuardOracle:", address(oracle));

        // 2. Deploy LlamaGuardOracleProxy
        LlamaGuardOracleProxy proxy = new LlamaGuardOracleProxy(
            address(oracle),
            oracleConfig.proxy.workflowId,
            oracleConfig.proxy.expectedForwarder,
            oracleConfig.proxy.expectedAuthor,
            oracleConfig.proxy.expectedWorkflowName,
            oracleConfig.proxy.description
        );
        console2.log("    [OK] LlamaGuardOracleProxy:", address(proxy));

        // 3. Grant WRITER_ROLE to proxy
        bytes32 writerRole = oracle.WRITER_ROLE();
        oracle.grantRole(writerRole, address(proxy));
        console2.log("    [OK] WRITER_ROLE granted to proxy");

        // 4. Seed oracle data if enabled
        if (seedOracle && oracleConfig.seed.enabled && oracleConfig.seed.sourceOracle != address(0)) {
            _seedSingleOracle(address(proxy), oracleConfig.seed);
        }

        // 5. Deploy EACAggregatorProxy pointing to oracle
        EACAggregatorProxy eacProxy = new EACAggregatorProxy(address(oracle));
        console2.log("    [OK] EACAggregatorProxy:", address(eacProxy));

        // 6. Transfer ownership if configured
        if (oracleConfig.pendingOwner != address(0) && oracleConfig.pendingOwner != broadcaster) {
            _transferOracleOwnership(oracle, proxy, eacProxy, oracleConfig.pendingOwner);
        }

        deployment = OracleDeployment({
            name: oracleConfig.oracle.name, oracle: address(oracle), proxy: address(proxy), eacProxy: address(eacProxy)
        });
    }

    /// @notice Transfer ownership of oracle contracts
    /// @param oracle The LlamaGuardOracle
    /// @param proxy The LlamaGuardOracleProxy
    /// @param eacProxy The EACAggregatorProxy
    /// @param newOwner The new owner address
    function _transferOracleOwnership(
        LlamaGuardOracle oracle,
        LlamaGuardOracleProxy proxy,
        EACAggregatorProxy eacProxy,
        address newOwner
    )
        internal
    {
        // Grant admin to new owner on oracle
        bytes32 adminRole = oracle.DEFAULT_ADMIN_ROLE();
        oracle.grantRole(adminRole, newOwner);
        console2.log("    [OK] DEFAULT_ADMIN_ROLE granted to:", newOwner);

        // Transfer proxy ownership (two-step)
        proxy.transferOwnership(newOwner);
        console2.log("    [OK] Proxy ownership transfer initiated");

        // Transfer EAC proxy ownership
        eacProxy.transferOwnership(newOwner);
        console2.log("    [OK] EAC proxy ownership transferred");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ORACLE DATA SEEDING
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Seed a single oracle with data from source
    /// @param proxyAddress The LlamaGuardOracleProxy address
    /// @param seedConfig The seed configuration
    function _seedSingleOracle(address proxyAddress, SepoliaDeployConfig.SeedConfig memory seedConfig) internal {
        console2.log("    Seeding from:", seedConfig.sourceOracle);

        // Read latest price from source oracle
        AggregatorV3Interface sourceOracle = AggregatorV3Interface(seedConfig.sourceOracle);
        (, int256 price,,,) = sourceOracle.latestRoundData();

        console2.log("    Source price:", price > 0 ? uint256(price) : uint256(-price));

        // Create UpdateInput struct for the proxy
        ILlamaGuardOracle.UpdateInput memory input = ILlamaGuardOracle.UpdateInput({
            referenceId: seedConfig.referenceId,
            newValue: abi.encode(price),
            updateType: seedConfig.updateType,
            additionalData: abi.encode(uint256(0), price, uint256(0)) // (supply, price, state) - using 0 for supply and
            // state
        });

        bytes memory report = abi.encode(input);

        // Call onReport on the proxy (isReportWriteSecured is false by default)
        LlamaGuardOracleProxy proxy = LlamaGuardOracleProxy(proxyAddress);
        proxy.onReport(bytes(""), report);

        console2.log("    [OK] Oracle seeded");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LOGGING HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Log deployment summary
    /// @param deployed The deployed contracts
    function _logDeploymentSummary(DeployedContracts memory deployed) internal pure {
        console2.log("");
        console2.log("=========================================");
        console2.log("DEPLOYMENT SUMMARY");
        console2.log("=========================================");

        if (deployed.parameterRegistry != address(0)) {
            console2.log("");
            console2.log("ParameterRegistry:", deployed.parameterRegistry);
        }

        for (uint256 i = 0; i < deployed.oracles.length; ++i) {
            OracleDeployment memory o = deployed.oracles[i];
            console2.log("");
            console2.log("Oracle Set:", o.name);
            console2.log("  LlamaGuardOracle:", o.oracle);
            console2.log("  LlamaGuardOracleProxy:", o.proxy);
            console2.log("  EACAggregatorProxy:", o.eacProxy);
        }

        console2.log("");
        console2.log("=========================================");
    }
}

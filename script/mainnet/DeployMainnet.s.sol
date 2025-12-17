// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { LlamaGuardOracle } from "../../src/LlamaGuardOracle.sol";
import { LlamaGuardOracleProxy } from "../../src/LlamaGuardOracleProxy.sol";
import { BaseScript } from "../Base.s.sol";
import { MainnetDeployConfig } from "./MainnetDeployConfig.sol";
import { console2 } from "forge-std/console2.sol";

/// @title DeployMainnet
/// @author LlamaRisk
/// @notice Aggregate deployment script for Ethereum Mainnet
/// @dev Deploys LlamaGuardOracle + LlamaGuardOracleProxy pairs based on MainnetDeployConfig
///      ParameterRegistry is already deployed at 0x69d55d504bc9556e377b340d19818e736bbb318b
contract DeployMainnet is BaseScript {
    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error NotOnMainnet();
    error InvalidOracleIndex();

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════════

    MainnetDeployConfig internal config;

    /// @notice Struct to hold all deployed contract addresses
    struct DeployedContracts {
        OracleDeployment[] oracles;
    }

    /// @notice Struct to hold oracle deployment addresses
    struct OracleDeployment {
        string name;
        address oracle;
        address proxy;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SETUP
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Initialize the deployment configuration
    function setUp() public {
        config = new MainnetDeployConfig();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MAIN DEPLOYMENT FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Deploy all oracles for Mainnet based on configuration
    /// @return deployed Struct containing all deployed contract addresses
    function run() public broadcast returns (DeployedContracts memory deployed) {
        if (block.chainid != 1) revert NotOnMainnet();

        bool deployOracles = config.getDeploymentFlags();

        console2.log("=========================================");
        console2.log("Mainnet Oracle Deployment");
        console2.log("=========================================");
        console2.log("Chain ID:", block.chainid);
        console2.log("Broadcaster:", broadcaster);
        console2.log("");
        console2.log("Existing ParameterRegistry:", config.PARAMETER_REGISTRY());
        console2.log("");
        console2.log("Deployment Flags:");
        console2.log("  Deploy Oracles:", deployOracles);
        console2.log("=========================================");

        if (deployOracles) {
            deployed.oracles = _deployAllOracles();
        }

        _logDeploymentSummary(deployed);
    }

    /// @notice Deploy a single oracle set by index
    /// @param index The index of the oracle configuration to deploy
    /// @return deployment The oracle deployment addresses
    function deploySingleOracle(uint256 index) public broadcast returns (OracleDeployment memory deployment) {
        if (block.chainid != 1) revert NotOnMainnet();

        MainnetDeployConfig.OracleDeploymentConfig memory oracleConfig = config.getOracleConfigByIndex(index);

        deployment = _deploySingleOracleSet(oracleConfig);

        console2.log("");
        console2.log("=========================================");
        console2.log("Single Oracle Deployment Complete");
        console2.log("=========================================");
        console2.log("Name:", deployment.name);
        console2.log("Oracle:", deployment.oracle);
        console2.log("Proxy:", deployment.proxy);
        console2.log("=========================================");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL DEPLOYMENT FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Deploy all oracle configurations
    /// @return deployments Array of oracle deployments
    function _deployAllOracles() internal returns (OracleDeployment[] memory deployments) {
        MainnetDeployConfig.OracleDeploymentConfig[] memory configs = config.getOracleConfigs();

        console2.log("");
        console2.log("-----------------------------------------");
        console2.log("Deploying", configs.length, "Oracle Sets");
        console2.log("-----------------------------------------");

        deployments = new OracleDeployment[](configs.length);

        for (uint256 i = 0; i < configs.length; ++i) {
            deployments[i] = _deploySingleOracleSet(configs[i]);
        }
    }

    /// @notice Deploy a single oracle set (Oracle + Proxy)
    /// @param oracleConfig The oracle deployment configuration
    /// @return deployment The deployed addresses
    function _deploySingleOracleSet(MainnetDeployConfig.OracleDeploymentConfig memory oracleConfig)
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

        // 4. Transfer ownership if configured
        if (oracleConfig.pendingOwner != address(0) && oracleConfig.pendingOwner != broadcaster) {
            _transferOracleOwnership(oracle, proxy, oracleConfig.pendingOwner);
        }

        deployment =
            OracleDeployment({ name: oracleConfig.oracle.name, oracle: address(oracle), proxy: address(proxy) });
    }

    /// @notice Transfer ownership of oracle contracts
    /// @param oracle The LlamaGuardOracle
    /// @param proxy The LlamaGuardOracleProxy
    /// @param newOwner The new owner address
    function _transferOracleOwnership(LlamaGuardOracle oracle, LlamaGuardOracleProxy proxy, address newOwner) internal {
        // Grant admin to new owner on oracle
        bytes32 adminRole = oracle.DEFAULT_ADMIN_ROLE();
        oracle.grantRole(adminRole, newOwner);
        console2.log("    [OK] DEFAULT_ADMIN_ROLE granted to:", newOwner);

        // Transfer proxy ownership (two-step)
        proxy.transferOwnership(newOwner);
        console2.log("    [OK] Proxy ownership transfer initiated");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // LOGGING HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Log deployment summary
    /// @param deployed The deployed contracts
    function _logDeploymentSummary(DeployedContracts memory deployed) internal view {
        console2.log("");
        console2.log("=========================================");
        console2.log("DEPLOYMENT SUMMARY");
        console2.log("=========================================");
        console2.log("");
        console2.log("ParameterRegistry (existing):", config.PARAMETER_REGISTRY());

        for (uint256 i = 0; i < deployed.oracles.length; ++i) {
            OracleDeployment memory o = deployed.oracles[i];
            console2.log("");
            console2.log("Oracle Set:", o.name);
            console2.log("  LlamaGuardOracle:", o.oracle);
            console2.log("  LlamaGuardOracleProxy:", o.proxy);
        }

        console2.log("");
        console2.log("=========================================");
    }
}

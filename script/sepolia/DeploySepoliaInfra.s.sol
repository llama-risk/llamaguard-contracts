// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { ParameterRegistry } from "../../src/ParameterRegistry.sol";
import { LlamaGuardOracle } from "../../src/LlamaGuardOracle.sol";
import { LlamaGuardOracleProxy } from "../../src/LlamaGuardOracleProxy.sol";
import { HorizonAgentHub } from "../../src/horizon-response/HorizonAgentHub.sol";
import { HorizonFreezeAgent } from "../../src/horizon-response/agents/HorizonFreezeAgent.sol";
import { AgentHub } from "chaos-agents/contracts/AgentHub.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ILlamaGuardOracle } from "../../src/interfaces/ILlamaGuardOracle.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { EACAggregatorProxy } from "./EACAggregatorProxy.sol";
import { BaseScript } from "../Base.s.sol";
import { DeployStructs } from "../config/DeployStructs.sol";
import { SepoliaConfig } from "../config/SepoliaConfig.sol";
import { Addresses } from "../config/Addresses.sol";
import { console2 } from "forge-std/console2.sol";

/// @title DeploySepoliaInfra
/// @notice Deploys full Sepolia infrastructure — oracles, proxies, AgentHub, FreezeAgent, EAC proxies
/// @dev Deploys:
///      1. LlamaGuardOracle + LlamaGuardOracleProxy for USCC, USTB
///      2. Grant WRITER_ROLE for each pair
///      3. Deploy EACAggregatorProxy for each oracle
///      4. Seed oracles from existing Chainlink sources
///      5. Deploy HorizonAgentHub (behind proxy + initialize)
///      6. Deploy HorizonFreezeAgent(agentHub, pool)
///      7. (Optional) Deploy ParameterRegistry + configure assets
contract DeploySepoliaInfra is BaseScript {
    SepoliaConfig internal config;

    struct OracleDeployment {
        string name;
        address oracle;
        address proxy;
        address eacProxy;
    }

    struct DeployedContracts {
        OracleDeployment[] oracles;
        address agentHub;
        address freezeAgent;
        address parameterRegistry;
    }

    function setUp() public {
        config = new SepoliaConfig();
    }

    /// @notice Deploy everything for Sepolia
    function run() public broadcast returns (DeployedContracts memory deployed) {
        require(block.chainid == 11_155_111, "Not on Sepolia");
        return _deploy(true, true);
    }

    /// @notice Deploy on any network (for testing)
    function runAnyNetwork() public broadcast returns (DeployedContracts memory deployed) {
        return _deploy(true, true);
    }

    /// @notice Deploy without ParameterRegistry
    function runOraclesOnly() public broadcast returns (DeployedContracts memory deployed) {
        require(block.chainid == 11_155_111, "Not on Sepolia");
        return _deploy(true, false);
    }

    function _deploy(bool seedOracles, bool deployRegistry) internal returns (DeployedContracts memory deployed) {
        console2.log("=========================================");
        console2.log("Sepolia Infrastructure Deployment");
        console2.log("=========================================");
        console2.log("Chain ID:", block.chainid);
        console2.log("Broadcaster:", broadcaster);
        console2.log("Seed Oracles:", seedOracles);
        console2.log("Deploy Registry:", deployRegistry);
        console2.log("=========================================");

        // 1-4. Deploy oracle infrastructure
        deployed.oracles = _deployAllOracles(seedOracles);

        // 5. Deploy HorizonAgentHub (behind TransparentUpgradeableProxy)
        HorizonAgentHub hubImplementation = new HorizonAgentHub();
        HorizonAgentHub agentHub = HorizonAgentHub(
            address(
                new TransparentUpgradeableProxy(
                    address(hubImplementation),
                    broadcaster,
                    abi.encodeWithSelector(AgentHub.initialize.selector, broadcaster)
                )
            )
        );
        deployed.agentHub = address(agentHub);
        console2.log("[OK] HorizonAgentHub (proxy):", deployed.agentHub);

        // 6. Deploy HorizonFreezeAgent
        HorizonFreezeAgent freezeAgent = new HorizonFreezeAgent(address(agentHub), Addresses.SEPOLIA_AAVE_HORIZON_POOL);
        deployed.freezeAgent = address(freezeAgent);
        console2.log("[OK] HorizonFreezeAgent:", deployed.freezeAgent);

        // 7. (Optional) Deploy ParameterRegistry
        if (deployRegistry) {
            deployed.parameterRegistry = address(_deployParameterRegistry(deployed.oracles));
        }

        _logSummary(deployed);
    }

    function _deployAllOracles(bool seedOracles) internal returns (OracleDeployment[] memory deployments) {
        DeployStructs.OracleDeploymentConfig[] memory oracleConfigs = config.getAllOracleConfigs();
        DeployStructs.SeedConfig[] memory seedConfigs = config.getAllSeedConfigs();

        deployments = new OracleDeployment[](oracleConfigs.length);

        for (uint256 i = 0; i < oracleConfigs.length; ++i) {
            deployments[i] = _deploySingleOracle(oracleConfigs[i], seedConfigs[i], seedOracles);
        }
    }

    function _deploySingleOracle(
        DeployStructs.OracleDeploymentConfig memory oracleConfig,
        DeployStructs.SeedConfig memory seedConfig,
        bool seedOracle
    )
        internal
        returns (OracleDeployment memory deployment)
    {
        console2.log("");
        console2.log("Deploying:", oracleConfig.oracle.name);

        // 1. Deploy LlamaGuardOracle
        LlamaGuardOracle oracle = new LlamaGuardOracle(
            oracleConfig.oracle.decimals,
            oracleConfig.oracle.description,
            oracleConfig.oracle.version,
            oracleConfig.oracle.updateTypes,
            oracleConfig.oracle.authorizedMarkets
        );
        console2.log("  [OK] LlamaGuardOracle:", address(oracle));

        // 2. Deploy LlamaGuardOracleProxy
        LlamaGuardOracleProxy proxy = new LlamaGuardOracleProxy(
            address(oracle),
            oracleConfig.proxy.workflowId,
            oracleConfig.proxy.expectedForwarder,
            oracleConfig.proxy.expectedAuthor,
            oracleConfig.proxy.expectedWorkflowName,
            oracleConfig.proxy.description
        );
        console2.log("  [OK] LlamaGuardOracleProxy:", address(proxy));

        // 3. Grant WRITER_ROLE
        oracle.grantRole(oracle.WRITER_ROLE(), address(proxy));
        console2.log("  [OK] WRITER_ROLE granted");

        // 4. Seed oracle data if enabled
        if (seedOracle && seedConfig.enabled && seedConfig.sourceOracle != address(0)) {
            _seedOracle(address(proxy), oracleConfig.proxy, seedConfig);
        }

        // 5. Deploy EACAggregatorProxy
        EACAggregatorProxy eacProxy = new EACAggregatorProxy(address(oracle));
        console2.log("  [OK] EACAggregatorProxy:", address(eacProxy));

        deployment = OracleDeployment({
            name: oracleConfig.oracle.name, oracle: address(oracle), proxy: address(proxy), eacProxy: address(eacProxy)
        });
    }

    function _seedOracle(
        address proxyAddress,
        DeployStructs.ProxyConfig memory proxyConfig,
        DeployStructs.SeedConfig memory seedConfig
    )
        internal
    {
        console2.log("  Seeding from:", seedConfig.sourceOracle);

        AggregatorV3Interface sourceOracle = AggregatorV3Interface(seedConfig.sourceOracle);
        (, int256 price,,,) = sourceOracle.latestRoundData();

        console2.log("  Source price:", price > 0 ? uint256(price) : uint256(-price));

        ILlamaGuardOracle.UpdateInput memory input = ILlamaGuardOracle.UpdateInput({
            referenceId: seedConfig.referenceId,
            newValue: abi.encode(price),
            updateType: seedConfig.updateType,
            additionalData: abi.encode(uint256(0), price, uint256(0)),
            deadline: block.timestamp + 1 hours
        });

        bytes memory report = abi.encode(input);
        bytes memory metadata =
            abi.encodePacked(proxyConfig.workflowId, proxyConfig.expectedWorkflowName, proxyConfig.expectedAuthor);

        LlamaGuardOracleProxy proxy = LlamaGuardOracleProxy(proxyAddress);
        vm.prank(proxyConfig.expectedForwarder);
        proxy.onReport(metadata, report);

        console2.log("  [OK] Oracle seeded");
    }

    function _deployParameterRegistry(OracleDeployment[] memory oracles)
        internal
        returns (ParameterRegistry parameterRegistry)
    {
        console2.log("");
        console2.log("Deploying ParameterRegistry...");

        parameterRegistry = new ParameterRegistry(broadcaster, broadcaster);
        console2.log("  [OK] ParameterRegistry:", address(parameterRegistry));

        // Configure assets using EAC proxy addresses
        DeployStructs.AssetConfig[] memory assets = config.getAllAssetConfigs();

        for (uint256 i = 0; i < assets.length; ++i) {
            address oracleAddr = i < oracles.length ? oracles[i].eacProxy : address(0);
            if (oracleAddr == address(0)) {
                console2.log("  [SKIP]", assets[i].assetName, "(no oracle)");
                continue;
            }

            parameterRegistry.setParametersForAsset(
                assets[i].assetAddress,
                assets[i].assetName,
                oracleAddr,
                assets[i].maxExpectedApy,
                assets[i].upperBoundTolerance,
                assets[i].lowerBoundTolerance,
                assets[i].maxDiscount,
                assets[i].lookbackWindowSize,
                assets[i].isUpperBoundEnabled,
                assets[i].isLowerBoundEnabled,
                assets[i].isActionTakingEnabled
            );
            console2.log("  [OK] Configured:", assets[i].assetName);
        }

        // Transfer roles if needed
        address pendingOwner = config.getRegistryPendingOwner();
        if (pendingOwner != address(0) && pendingOwner != broadcaster) {
            parameterRegistry.transferOwnership(pendingOwner);
            console2.log("  [OK] Ownership transfer initiated to:", pendingOwner);
        }

        address pendingUpdater = config.getRegistryPendingUpdater();
        if (pendingUpdater != address(0) && pendingUpdater != broadcaster) {
            parameterRegistry.setUpdater(pendingUpdater);
            console2.log("  [OK] Updater transferred to:", pendingUpdater);
        }
    }

    function _logSummary(DeployedContracts memory deployed) internal pure {
        console2.log("");
        console2.log("=========================================");
        console2.log("SEPOLIA DEPLOYMENT SUMMARY");
        console2.log("=========================================");

        for (uint256 i = 0; i < deployed.oracles.length; ++i) {
            console2.log("");
            console2.log(deployed.oracles[i].name, "Oracle Set:");
            console2.log("  Oracle:", deployed.oracles[i].oracle);
            console2.log("  Proxy:", deployed.oracles[i].proxy);
            console2.log("  EAC:", deployed.oracles[i].eacProxy);
        }

        console2.log("");
        console2.log("AgentHub:", deployed.agentHub);
        console2.log("FreezeAgent:", deployed.freezeAgent);

        if (deployed.parameterRegistry != address(0)) {
            console2.log("ParameterRegistry:", deployed.parameterRegistry);
        }

        console2.log("=========================================");
    }
}

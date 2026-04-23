// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { LlamaGuardOracle } from "../src/LlamaGuardOracle.sol";
import { LlamaGuardOracleProxy } from "../src/LlamaGuardOracleProxy.sol";
import { HorizonAgentHub } from "../src/horizon-response/HorizonAgentHub.sol";
import { HorizonFreezeAgent } from "../src/horizon-response/agents/HorizonFreezeAgent.sol";
import { AgentHub } from "chaos-agents/contracts/AgentHub.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { BaseScript } from "./Base.s.sol";
import { DeployStructs } from "./config/DeployStructs.sol";
import { MainnetConfig } from "./config/MainnetConfig.sol";
import { Addresses } from "./config/Addresses.sol";
import { console2 } from "forge-std/console2.sol";

/// @title DeployUstbInfrastructure
/// @notice Stage 1: Deploy all contracts for USTB pilot. Nothing activated.
/// @dev Deploys:
///      1. LlamaGuardOracle(USTB)
///      2. LlamaGuardOracleProxy(USTB)
///      3. Grants WRITER_ROLE to proxy on oracle
///      4. Adds USTB token as authorized market
///      5. HorizonAgentHub (behind TransparentUpgradeableProxy + initialize)
///      6. HorizonFreezeAgent(agentHub, pool)
///
///      Does NOT: register agents, activate workflows, or transfer ownership
contract DeployUstbInfrastructure is BaseScript {
    MainnetConfig internal config;

    struct DeployedContracts {
        address oracle;
        address oracleProxy;
        address agentHub;
        address agentHubImplementation;
        address agentHubProxyAdmin;
        address freezeAgent;
    }

    function setUp() public {
        config = new MainnetConfig();
    }

    /// @notice Deploy everything on mainnet
    function run() public broadcast returns (DeployedContracts memory deployed) {
        require(block.chainid == 1, "Not on mainnet");
        return _deploy();
    }

    /// @notice Deploy on any network (for testing)
    function runAnyNetwork() public broadcast returns (DeployedContracts memory deployed) {
        return _deploy();
    }

    function _deploy() internal returns (DeployedContracts memory deployed) {
        console2.log("=========================================");
        console2.log("Stage 1: Deploy USTB Infrastructure");
        console2.log("=========================================");
        console2.log("Chain ID:", block.chainid);
        console2.log("Broadcaster:", broadcaster);
        console2.log("=========================================");

        // 1. Deploy LlamaGuardOracle(USTB)
        DeployStructs.OracleDeploymentConfig memory ustbConfig = config.getOracleConfig("USTB");

        LlamaGuardOracle oracle = new LlamaGuardOracle(
            ustbConfig.oracle.decimals,
            ustbConfig.oracle.description,
            ustbConfig.oracle.version,
            ustbConfig.oracle.updateTypes,
            ustbConfig.oracle.authorizedMarkets
        );
        console2.log("[OK] LlamaGuardOracle(USTB):", address(oracle));

        // 2. Deploy LlamaGuardOracleProxy(USTB)
        LlamaGuardOracleProxy oracleProxy = new LlamaGuardOracleProxy(
            address(oracle),
            ustbConfig.proxy.workflowId,
            ustbConfig.proxy.expectedForwarder,
            ustbConfig.proxy.expectedAuthor,
            ustbConfig.proxy.expectedWorkflowName,
            ustbConfig.proxy.description
        );
        console2.log("[OK] LlamaGuardOracleProxy(USTB):", address(oracleProxy));

        // 3. Grant WRITER_ROLE to proxy on oracle
        oracle.grantRole(oracle.WRITER_ROLE(), address(oracleProxy));
        require(oracle.hasWriteAccess(address(oracleProxy)), "WRITER_ROLE not granted");
        console2.log("[OK] WRITER_ROLE granted to proxy");

        // 4. Add USTB token as authorized market
        oracle.addAuthorizedMarket(Addresses.USTB);
        require(oracle.isAuthorizedMarket(Addresses.USTB), "Market not authorized");
        console2.log("[OK] USTB token authorized as market");

        // 5. Deploy HorizonAgentHub (behind TransparentUpgradeableProxy)
        HorizonAgentHub hubImplementation = new HorizonAgentHub();
        HorizonAgentHub agentHub = HorizonAgentHub(
            address(
                new TransparentUpgradeableProxy(
                    address(hubImplementation),
                    broadcaster, // proxy admin
                    abi.encodeWithSelector(AgentHub.initialize.selector, broadcaster)
                )
            )
        );
        // Read the ProxyAdmin address from ERC1967 admin slot
        bytes32 adminSlot = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
        address proxyAdmin = address(uint160(uint256(vm.load(address(agentHub), adminSlot))));
        console2.log("[OK] HorizonAgentHub (proxy):", address(agentHub));
        console2.log("     Implementation:", address(hubImplementation));
        console2.log("     ProxyAdmin:", proxyAdmin);

        // 6. Deploy HorizonFreezeAgent
        HorizonFreezeAgent freezeAgent = new HorizonFreezeAgent(address(agentHub), Addresses.AAVE_HORIZON_POOL);
        console2.log("[OK] HorizonFreezeAgent:", address(freezeAgent));

        deployed = DeployedContracts({
            oracle: address(oracle),
            oracleProxy: address(oracleProxy),
            agentHub: address(agentHub),
            agentHubImplementation: address(hubImplementation),
            agentHubProxyAdmin: proxyAdmin,
            freezeAgent: address(freezeAgent)
        });

        _logSummary(deployed);
    }

    function _logSummary(DeployedContracts memory deployed) internal pure {
        console2.log("");
        console2.log("=========================================");
        console2.log("DEPLOYMENT SUMMARY");
        console2.log("=========================================");
        console2.log("LlamaGuardOracle(USTB):", deployed.oracle);
        console2.log("LlamaGuardOracleProxy(USTB):", deployed.oracleProxy);
        console2.log("HorizonAgentHub:", deployed.agentHub);
        console2.log("HorizonAgentHub impl:", deployed.agentHubImplementation);
        console2.log("HorizonAgentHub ProxyAdmin:", deployed.agentHubProxyAdmin);
        console2.log("HorizonFreezeAgent:", deployed.freezeAgent);
        console2.log("");
        console2.log("NEXT: Run 2_ActivateUstbPilot with these addresses");
        console2.log("=========================================");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { LlamaGuardOracle } from "../../src/LlamaGuardOracle.sol";
import { LlamaGuardOracleProxy } from "../../src/LlamaGuardOracleProxy.sol";
import { HorizonAgentHub } from "../../src/horizon-response/HorizonAgentHub.sol";
import { HorizonFreezeAgent } from "../../src/horizon-response/agents/HorizonFreezeAgent.sol";
import { AgentHub } from "chaos-agents/contracts/AgentHub.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ILlamaGuardOracle } from "../../src/interfaces/ILlamaGuardOracle.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { EACAggregatorProxy } from "./EACAggregatorProxy.sol";
import { RawNAVOracle } from "./RawNAVOracle.sol";
import { BaseScript } from "../Base.s.sol";
import { DeployStructs } from "../config/DeployStructs.sol";
import { SepoliaConfig } from "../config/SepoliaConfig.sol";
import { Addresses } from "../config/Addresses.sol";
import { console2 } from "forge-std/console2.sol";

/// @title DeploySepoliaUstb
/// @notice Deploy USTB oracle infrastructure on Sepolia for CRE integration testing with Horizon
/// @dev Deploys:
///      1. LlamaGuardOracle(USTB) with config from SepoliaConfig
///      2. LlamaGuardOracleProxy(USTB) with full CRE params
///      3. Grants WRITER_ROLE to proxy AND deployer (deployer for initial seeding)
///      4. Adds SEPOLIA_USTB as authorized market
///      5. Seeds oracle directly via oracle.updateLatestRiskRoundData()
///      6. EACAggregatorProxy pointing to LlamaGuardOracle
///      7. RawNAVOracle — writable NAV source for CRE cron job
///      8. HorizonAgentHub (behind TransparentUpgradeableProxy + initialize)
///      9. HorizonFreezeAgent(agentHub, SEPOLIA_AAVE_HORIZON_POOL)
contract DeploySepoliaUstb is BaseScript {
    SepoliaConfig internal config;

    struct DeployedContracts {
        address oracle;
        address oracleProxy;
        address eacProxy;
        address rawNAVOracle;
        address agentHub;
        address agentHubImplementation;
        address agentHubProxyAdmin;
        address freezeAgent;
    }

    function setUp() public {
        config = new SepoliaConfig();
    }

    /// @notice Deploy everything on Sepolia
    function run() public broadcast returns (DeployedContracts memory deployed) {
        require(block.chainid == 11_155_111, "Not on Sepolia");
        return _deploy();
    }

    /// @notice Deploy on any network (for testing)
    function runAnyNetwork() public broadcast returns (DeployedContracts memory deployed) {
        return _deploy();
    }

    function _deploy() internal returns (DeployedContracts memory deployed) {
        console2.log("=========================================");
        console2.log("Sepolia USTB Integration Deployment");
        console2.log("=========================================");
        console2.log("Chain ID:", block.chainid);
        console2.log("Broadcaster:", broadcaster);
        console2.log("=========================================");

        // 1. Deploy LlamaGuardOracle(USTB)
        DeployStructs.OracleDeploymentConfig memory ustbConfig = config.getUstbOracleConfig();

        LlamaGuardOracle oracle = new LlamaGuardOracle(
            ustbConfig.oracle.decimals,
            ustbConfig.oracle.description,
            ustbConfig.oracle.version,
            ustbConfig.oracle.updateTypes,
            ustbConfig.oracle.authorizedMarkets
        );
        deployed.oracle = address(oracle);
        console2.log("[OK] LlamaGuardOracle(USTB):", deployed.oracle);

        // 2. Deploy LlamaGuardOracleProxy(USTB) with full CRE params
        LlamaGuardOracleProxy oracleProxy = new LlamaGuardOracleProxy(
            address(oracle),
            ustbConfig.proxy.workflowId,
            ustbConfig.proxy.expectedForwarder,
            ustbConfig.proxy.expectedAuthor,
            ustbConfig.proxy.expectedWorkflowName,
            ustbConfig.proxy.description
        );
        deployed.oracleProxy = address(oracleProxy);
        console2.log("[OK] LlamaGuardOracleProxy(USTB):", deployed.oracleProxy);

        // 3. Grant WRITER_ROLE to both proxy AND deployer
        oracle.grantRole(oracle.WRITER_ROLE(), address(oracleProxy));
        require(oracle.hasWriteAccess(address(oracleProxy)), "WRITER_ROLE not granted to proxy");
        console2.log("[OK] WRITER_ROLE granted to proxy");

        oracle.grantRole(oracle.WRITER_ROLE(), broadcaster);
        require(oracle.hasWriteAccess(broadcaster), "WRITER_ROLE not granted to deployer");
        console2.log("[OK] WRITER_ROLE granted to deployer");

        // 4. Add SEPOLIA_USTB as authorized market
        oracle.addAuthorizedMarket(Addresses.SEPOLIA_USTB);
        require(oracle.isAuthorizedMarket(Addresses.SEPOLIA_USTB), "Market not authorized");
        console2.log("[OK] SEPOLIA_USTB authorized as market");

        // 5. Seed oracle directly via updateLatestRiskRoundData
        int256 seedPrice = _readSourcePrice();
        console2.log("[OK] Source price read:", seedPrice > 0 ? uint256(seedPrice) : uint256(-seedPrice));

        oracle.updateLatestRiskRoundData(
            ILlamaGuardOracle.UpdateInput({
                referenceId: "sepolia-ustb-seed-v1",
                newValue: abi.encode(seedPrice),
                updateType: "boundedNAV",
                additionalData: abi.encode(uint256(0), seedPrice, uint256(0)),
                deadline: block.timestamp + 1 hours
            })
        );
        console2.log("[OK] Oracle seeded with price");

        // 6. Deploy EACAggregatorProxy pointing to LlamaGuardOracle
        EACAggregatorProxy eacProxy = new EACAggregatorProxy(address(oracle));
        deployed.eacProxy = address(eacProxy);
        console2.log("[OK] EACAggregatorProxy:", deployed.eacProxy);

        // 7. Deploy RawNAVOracle — writable NAV source for CRE
        RawNAVOracle rawNav = new RawNAVOracle(8, "USTB Raw NAV (Sepolia)", 1, seedPrice);
        deployed.rawNAVOracle = address(rawNav);
        console2.log("[OK] RawNAVOracle:", deployed.rawNAVOracle);

        // 8. Deploy HorizonAgentHub (behind TransparentUpgradeableProxy)
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
        deployed.agentHubImplementation = address(hubImplementation);

        // Read the ProxyAdmin address from ERC1967 admin slot
        bytes32 adminSlot = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
        deployed.agentHubProxyAdmin = address(uint160(uint256(vm.load(address(agentHub), adminSlot))));
        console2.log("[OK] HorizonAgentHub (proxy):", deployed.agentHub);
        console2.log("     Implementation:", deployed.agentHubImplementation);
        console2.log("     ProxyAdmin:", deployed.agentHubProxyAdmin);

        // 9. Deploy HorizonFreezeAgent
        HorizonFreezeAgent freezeAgent = new HorizonFreezeAgent(address(agentHub), Addresses.SEPOLIA_AAVE_HORIZON_POOL);
        deployed.freezeAgent = address(freezeAgent);
        console2.log("[OK] HorizonFreezeAgent:", deployed.freezeAgent);

        _logSummary(deployed);
    }

    function _readSourcePrice() internal view returns (int256) {
        AggregatorV3Interface sourceOracle = AggregatorV3Interface(Addresses.SEPOLIA_USTB_SOURCE_ORACLE);
        (, int256 price,,,) = sourceOracle.latestRoundData();
        return price;
    }

    function _logSummary(DeployedContracts memory deployed) internal pure {
        console2.log("");
        console2.log("=========================================");
        console2.log("SEPOLIA USTB DEPLOYMENT SUMMARY");
        console2.log("=========================================");
        console2.log("LlamaGuardOracle(USTB):", deployed.oracle);
        console2.log("LlamaGuardOracleProxy(USTB):", deployed.oracleProxy);
        console2.log("EACAggregatorProxy:", deployed.eacProxy);
        console2.log("RawNAVOracle:", deployed.rawNAVOracle);
        console2.log("HorizonAgentHub:", deployed.agentHub);
        console2.log("HorizonAgentHub impl:", deployed.agentHubImplementation);
        console2.log("HorizonAgentHub ProxyAdmin:", deployed.agentHubProxyAdmin);
        console2.log("HorizonFreezeAgent:", deployed.freezeAgent);
        console2.log("");
        console2.log("NEXT STEPS:");
        console2.log("  1. Share EACAggregatorProxy with Horizon");
        console2.log("  2. Share RawNAVOracle with Chainlink CRE");
        console2.log("  3. Horizon grants RISK_ADMIN to FreezeAgent");
        console2.log("  4. Register FreezeAgent in AgentHub");
        console2.log("  5. Start cron job writing to RawNAVOracle");
        console2.log("=========================================");
    }
}

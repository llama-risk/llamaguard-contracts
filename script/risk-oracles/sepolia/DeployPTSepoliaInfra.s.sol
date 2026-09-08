// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { BaseScript } from "../Base.s.sol";
import { PTParameterRegistry } from "../../../src/PTParameterRegistry.sol";
import { LlamaguardRiskOracleRouter } from "../../../src/LlamaguardRiskOracleRouter.sol";
import { StagingLlamaguardOracleReceiver } from "./StagingLlamaguardOracleReceiver.sol";
import { StagingRiskOracleReceiver } from "./StagingRiskOracleReceiver.sol";
import { LlamaGuardOracle } from "llamaguard-contracts/src/LlamaGuardOracle.sol";
import { RiskOracle } from "aave-v3-risk-stewards/contracts/dependencies/RiskOracle.sol";
import { AgentHub } from "chaos-agents/contracts/AgentHub.sol";
import { IAgentConfigurator } from "chaos-agents/interfaces/IAgentConfigurator.sol";
import { IRangeValidationModule } from "chaos-agents/interfaces/IRangeValidationModule.sol";
import { RangeValidationModule } from "chaos-agents/contracts/modules/RangeValidationModule.sol";
import { AaveDiscountRateAgent } from "aave-risk-agents/src/contracts/agent/AaveDiscountRateAgent.sol";
import { AaveEModeAgent } from "aave-risk-agents/src/contracts/agent/AaveEModeAgent.sol";
import { AaveSepoliaAddresses } from "../config/AaveSepoliaAddresses.sol";
import { RouterSelectors } from "../RouterSelectors.sol";

contract DeployPTSepoliaInfra is BaseScript {
    address internal constant MOCK_FORWARDER = 0x15fC6ae953E024d975e77382eEeC56A9101f9F88;
    address internal constant PT_ASSET = 0x619D75E3b790eBC21c289f2805Bb7177A7D732E2;

    string internal constant TYPE_EMA = "EmaImpliedRateUpdate";
    string internal constant TYPE_DISCOUNT = "PendleDiscountRateUpdate";
    string internal constant TYPE_EMODE = "EModeCategoryUpdate";
    string internal constant TYPE_EMODE_LTV = "EModeLTV";
    string internal constant TYPE_EMODE_LT = "EModeLiquidationThreshold";
    string internal constant TYPE_EMODE_LB = "EModeLiquidationBonus";

    uint32 internal constant EMA_SPAN = 48;
    uint64 internal constant EMA_FRESHNESS_SECONDS = 14_400;
    uint64 internal constant DISCOUNT_THRESHOLD_BPS = 30;
    uint64 internal constant DISCOUNT_MAX_STEP_BPS = 100;
    uint64 internal constant DISCOUNT_MIN_DELAY_SECONDS = 1 days;
    uint64 internal constant EMODE_AGENT_MIN_DELAY_SECONDS = 3 days;
    uint64 internal constant EMODE_LT_MAX_CHANGE_BPS = 50;
    uint64 internal constant EMODE_LTV_MAX_CHANGE_BPS = 50;
    uint64 internal constant EMODE_LB_MAX_CHANGE_BPS = 100;
    uint64 internal constant K_REFERENCE_ENDPOINT = 25_000;

    struct Deployment {
        address riskOracle;
        address emaOracle;
        address emaReceiver;
        address ptParameterRegistry;
        address router;
        address singleReceiver;
        address bulkReceiver;
        address agentHub;
        address rangeValidationModule;
        address discountAgent;
        uint256 discountAgentId;
        address eModeAgent;
        uint256 eModeAgentId;
    }

    function run() public broadcast returns (Deployment memory deployed) {
        require(block.chainid == 11_155_111, "Not on Sepolia");

        console2.log("=========================================");
        console2.log("PT Sepolia Infrastructure Deployment");
        console2.log("=========================================");
        console2.log("Broadcaster:", broadcaster);

        deployed = _deployCoreContracts();
        _configureRegistry(PTParameterRegistry(deployed.ptParameterRegistry));
        _authorizeSenders(RiskOracle(deployed.riskOracle), deployed);
        _configureEmaOracle(LlamaGuardOracle(deployed.emaOracle), deployed.emaReceiver);
        (deployed.agentHub, deployed.rangeValidationModule) = _deployAutomationSurface();
        (deployed.discountAgent, deployed.discountAgentId, deployed.eModeAgent, deployed.eModeAgentId) =
            _deployAndRegisterAgents(AgentHub(deployed.agentHub), deployed.riskOracle, deployed.rangeValidationModule);
        _configureRangeValidationModule(RangeValidationModule(deployed.rangeValidationModule), deployed);

        _logSummary(deployed);
    }

    function _deployCoreContracts() internal returns (Deployment memory deployed) {
        string[] memory updateTypes = new string[](3);
        updateTypes[0] = TYPE_EMA;
        updateTypes[1] = TYPE_DISCOUNT;
        updateTypes[2] = TYPE_EMODE;

        string[] memory emaUpdateTypes = new string[](1);
        emaUpdateTypes[0] = TYPE_EMA;

        address[] memory emaMarkets = new address[](1);
        emaMarkets[0] = PT_ASSET;

        address[] memory initialSenders = new address[](0);

        RiskOracle riskOracle = new RiskOracle("LlamaRisk PT Risk Oracle (Sepolia)", initialSenders, updateTypes);
        LlamaGuardOracle emaOracle =
            new LlamaGuardOracle(18, "PT EMA Implied Rate (Pendle, Sepolia)", 1, emaUpdateTypes, emaMarkets);
        PTParameterRegistry registry = new PTParameterRegistry(broadcaster, broadcaster);
        LlamaguardRiskOracleRouter router = new LlamaguardRiskOracleRouter(broadcaster);
        router.setUpdater(broadcaster);
        StagingLlamaguardOracleReceiver emaReceiver =
            new StagingLlamaguardOracleReceiver(MOCK_FORWARDER, address(emaOracle), "PT EMA staging receiver");
        StagingRiskOracleReceiver singleReceiver = new StagingRiskOracleReceiver(
            MOCK_FORWARDER,
            address(riskOracle),
            RouterSelectors.PUBLISH_SINGLE_SELECTOR,
            "PT staging single-update receiver"
        );
        StagingRiskOracleReceiver bulkReceiver = new StagingRiskOracleReceiver(
            MOCK_FORWARDER,
            address(riskOracle),
            RouterSelectors.PUBLISH_BULK_SELECTOR,
            "PT staging bulk-update receiver"
        );

        deployed.riskOracle = address(riskOracle);
        deployed.emaOracle = address(emaOracle);
        deployed.emaReceiver = address(emaReceiver);
        deployed.ptParameterRegistry = address(registry);
        deployed.router = address(router);
        deployed.singleReceiver = address(singleReceiver);
        deployed.bulkReceiver = address(bulkReceiver);

        return deployed;
    }

    function _configureRegistry(PTParameterRegistry registry) internal {
        uint16[] memory emodeCategoryIds = new uint16[](2);
        emodeCategoryIds[0] = 38;
        emodeCategoryIds[1] = 39;

        registry.setPtMarketParams(
            PT_ASSET,
            PTParameterRegistry.PtMarketParams({
                enabled: true,
                modelVersion: 1,
                emaSpan: EMA_SPAN,
                emaFreshnessSeconds: EMA_FRESHNESS_SECONDS,
                thresholdBps: DISCOUNT_THRESHOLD_BPS,
                kReferenceEndpoint: K_REFERENCE_ENDPOINT,
                emodeCategoryIds: emodeCategoryIds
            })
        );
    }

    function _authorizeSenders(RiskOracle riskOracle, Deployment memory deployed) internal {
        riskOracle.addAuthorizedSender(deployed.router);
        riskOracle.addAuthorizedSender(deployed.singleReceiver);
        riskOracle.addAuthorizedSender(deployed.bulkReceiver);
    }

    function _configureEmaOracle(LlamaGuardOracle emaOracle, address emaReceiver) internal {
        emaOracle.grantRole(emaOracle.WRITER_ROLE(), emaReceiver);
    }

    function _deployAutomationSurface() internal returns (address agentHubProxy, address rangeValidationModule) {
        AgentHub hubImplementation = new AgentHub();
        AgentHub agentHub = AgentHub(
            address(
                new TransparentUpgradeableProxy(
                    address(hubImplementation),
                    broadcaster,
                    abi.encodeWithSelector(AgentHub.initialize.selector, broadcaster)
                )
            )
        );
        agentHub.setMaxBatchSize(16);

        RangeValidationModule rangeModule = new RangeValidationModule();

        return (address(agentHub), address(rangeModule));
    }

    function _configureRangeValidationModule(RangeValidationModule rangeModule, Deployment memory deployed) internal {
        rangeModule.setRangeConfigByMarket(
            deployed.agentHub,
            deployed.discountAgentId,
            PT_ASSET,
            TYPE_DISCOUNT,
            IRangeValidationModule.RangeConfig({
                maxIncrease: uint120((uint256(1e18) * DISCOUNT_MAX_STEP_BPS) / 10_000),
                maxDecrease: uint120((uint256(1e18) * DISCOUNT_MAX_STEP_BPS) / 10_000),
                isIncreaseRelative: false,
                isDecreaseRelative: false
            })
        );

        // Absolute caps, mirroring the mainnet Edge Risk Steward (isChangeRelative = false) for
        // eMode LTV/LT/LB. A relative cap would collapse toward zero at small current values.
        _setRiskParamRangeConfig(rangeModule, deployed, TYPE_EMODE_LTV, EMODE_LTV_MAX_CHANGE_BPS, false);
        _setRiskParamRangeConfig(rangeModule, deployed, TYPE_EMODE_LT, EMODE_LT_MAX_CHANGE_BPS, false);
        _setRiskParamRangeConfig(rangeModule, deployed, TYPE_EMODE_LB, EMODE_LB_MAX_CHANGE_BPS, false);
    }

    function _setRiskParamRangeConfig(
        RangeValidationModule rangeModule,
        Deployment memory deployed,
        string memory updateType,
        uint64 maxChangeBps,
        bool isRelative
    )
        internal
    {
        rangeModule.setDefaultRangeConfig(
            deployed.agentHub,
            deployed.eModeAgentId,
            updateType,
            IRangeValidationModule.RangeConfig({
                maxIncrease: uint120(maxChangeBps),
                maxDecrease: uint120(maxChangeBps),
                isIncreaseRelative: isRelative,
                isDecreaseRelative: isRelative
            })
        );
    }

    function _deployAndRegisterAgents(
        AgentHub agentHub,
        address riskOracle,
        address rangeValidationModule
    )
        internal
        returns (address discountAgent, uint256 discountAgentId, address eModeAgent, uint256 eModeAgentId)
    {
        discountAgent = address(
            new AaveDiscountRateAgent(
                address(agentHub), rangeValidationModule, "", AaveSepoliaAddresses.POOL, AaveSepoliaAddresses.ORACLE
            )
        );
        eModeAgent =
            address(new AaveEModeAgent(address(agentHub), rangeValidationModule, "", AaveSepoliaAddresses.POOL));

        discountAgentId = agentHub.registerAgent(_discountAgentConfig(riskOracle, discountAgent));
        eModeAgentId = agentHub.registerAgent(_eModeAgentConfig(riskOracle, eModeAgent));
    }

    function _discountAgentConfig(
        address riskOracle,
        address agentAddress
    )
        internal
        pure
        returns (IAgentConfigurator.AgentRegistrationInput memory input)
    {
        address[] memory allowedMarkets = new address[](1);
        allowedMarkets[0] = PT_ASSET;

        input = IAgentConfigurator.AgentRegistrationInput({
            admin: address(0),
            riskOracle: riskOracle,
            isAgentEnabled: false,
            isAgentPermissioned: false,
            isMarketsFromAgentEnabled: false,
            agentAddress: agentAddress,
            expirationPeriod: 1 days,
            minimumDelay: DISCOUNT_MIN_DELAY_SECONDS,
            updateType: TYPE_DISCOUNT,
            agentContext: bytes(""),
            allowedMarkets: allowedMarkets,
            restrictedMarkets: new address[](0),
            permissionedSenders: new address[](0)
        });
    }

    function _eModeAgentConfig(
        address riskOracle,
        address agentAddress
    )
        internal
        pure
        returns (IAgentConfigurator.AgentRegistrationInput memory input)
    {
        address[] memory allowedMarkets = new address[](2);
        allowedMarkets[0] = address(uint160(38));
        allowedMarkets[1] = address(uint160(39));

        input = IAgentConfigurator.AgentRegistrationInput({
            admin: address(0),
            riskOracle: riskOracle,
            isAgentEnabled: false,
            isAgentPermissioned: false,
            isMarketsFromAgentEnabled: false,
            agentAddress: agentAddress,
            expirationPeriod: 1 days,
            minimumDelay: EMODE_AGENT_MIN_DELAY_SECONDS,
            updateType: TYPE_EMODE,
            agentContext: abi.encode(address(0)),
            allowedMarkets: allowedMarkets,
            restrictedMarkets: new address[](0),
            permissionedSenders: new address[](0)
        });
    }

    function _logSummary(Deployment memory deployed) internal pure {
        console2.log("RiskOracle:", deployed.riskOracle);
        console2.log("LlamaGuardOracle (EMA):", deployed.emaOracle);
        console2.log("LlamaGuard EMA staging receiver:", deployed.emaReceiver);
        console2.log("PTParameterRegistry:", deployed.ptParameterRegistry);
        console2.log("LlamaguardRiskOracleRouter:", deployed.router);
        console2.log("Single staging receiver:", deployed.singleReceiver);
        console2.log("Bulk staging receiver:", deployed.bulkReceiver);
        console2.log("AgentHub:", deployed.agentHub);
        console2.log("RangeValidationModule:", deployed.rangeValidationModule);
        console2.log("AaveDiscountRateAgent:", deployed.discountAgent);
        console2.log("AaveDiscountRateAgent ID:", deployed.discountAgentId);
        console2.log("AaveEModeAgent:", deployed.eModeAgent);
        console2.log("AaveEModeAgent ID:", deployed.eModeAgentId);
        console2.log("Note: both Aave agents are registered disabled for this publication-only milestone.");
        console2.log("Simulation forwarder:", MOCK_FORWARDER);
        console2.log("Configured PT asset:", PT_ASSET);
    }
}

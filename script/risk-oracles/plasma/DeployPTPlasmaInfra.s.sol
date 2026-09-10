// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { BaseScript } from "../Base.s.sol";
import { PTParameterRegistry } from "../../../src/PTParameterRegistry.sol";
import { LlamaguardRiskOracleRouter } from "../../../src/LlamaguardRiskOracleRouter.sol";
import { StagingLlamaguardOracleReceiver } from "../sepolia/StagingLlamaguardOracleReceiver.sol";
import { StagingRiskOracleReceiver } from "../sepolia/StagingRiskOracleReceiver.sol";
import { LlamaGuardOracle } from "llamaguard-contracts/src/LlamaGuardOracle.sol";
import { RiskOracle } from "aave-v3-risk-stewards/contracts/dependencies/RiskOracle.sol";
import { RouterSelectors } from "../RouterSelectors.sol";

/// @title DeployPTPlasmaInfra
/// @notice Shadow-deployment infra for Plasma PT sUSDe (chainId 9745). Publish-only:
///         deploys the full self-contained stack (dummy RiskOracle, EMA LlamaGuardOracle,
///         PTParameterRegistry, LlamaguardRiskOracleRouter, 3 staging receivers), grants the
///         Router write access to both oracles, and registers the PT market params.
/// @dev    Forked from DeployPTSepoliaInfra. Differences vs the Sepolia script:
///         (1) chainId guard 9745; (2) the AgentHub / RangeValidationModule / Aave agents block
///         is intentionally omitted — routes are registered publish-only; (3) the Router (not the
///         staging EMA receiver) is granted WRITER_ROLE on the EMA oracle, because the shadow
///         path is CRE -> Router -> oracle; (4) eMode ids 25/26 and Plasma registry values.
///         Deployed addresses are emitted as `OUTPUT:KEY=0x...` lines for the makefile to capture.
contract DeployPTPlasmaInfra is BaseScript {
    uint256 internal constant PLASMA_CHAIN_ID = 9745;

    // PT sUSDe 22OCT2026 reserve on Plasma (onboarding doc).
    address internal constant PT_ASSET = 0xf7fB83435F455Bd970F2D9f943f4eECE1941b3e9;

    // Forwarder baked into the staging receivers (optional direct-write debug path). The active
    // shadow path runs through the Router, whose per-route forwarder is set at route registration.
    // Overridable so the receivers can be wired to the real Plasma CRE/DON forwarder if needed.
    address internal constant MOCK_FORWARDER = 0x000000000000000000000000000000000000dEaD;

    string internal constant TYPE_EMA = "EmaImpliedRateUpdate";
    string internal constant TYPE_DISCOUNT = "PendleDiscountRateUpdate";
    string internal constant TYPE_EMODE = "EModeCategoryUpdate";

    // Registry PtMarketParams (Plasma PT sUSDe 22OCT2026, onboarding doc).
    uint32 internal constant EMA_SPAN = 48;
    uint64 internal constant EMA_FRESHNESS_SECONDS = 14_400;
    uint64 internal constant DISCOUNT_THRESHOLD_BPS = 30;
    uint64 internal constant K_REFERENCE_ENDPOINT = 25_000;

    uint16 internal constant EMODE_STABLECOINS = 25;
    uint16 internal constant EMODE_USDE = 26;

    struct Deployment {
        address riskOracle;
        address emaOracle;
        address emaReceiver;
        address ptParameterRegistry;
        address router;
        address singleReceiver;
        address bulkReceiver;
    }

    function run() public broadcast returns (Deployment memory deployed) {
        require(block.chainid == PLASMA_CHAIN_ID, "Not on Plasma");

        address forwarder = vm.envOr({ name: "PLASMA_STAGING_FORWARDER", defaultValue: MOCK_FORWARDER });

        console2.log("=========================================");
        console2.log("PT Plasma Shadow Infrastructure Deployment");
        console2.log("=========================================");
        console2.log("Broadcaster:", broadcaster);
        console2.log("Staging-receiver forwarder:", forwarder);

        deployed = _deployCoreContracts(forwarder);
        _configureRegistry(PTParameterRegistry(deployed.ptParameterRegistry));
        _wirePermissions(deployed);

        _logSummary(deployed);
    }

    function _deployCoreContracts(address forwarder) internal returns (Deployment memory deployed) {
        string[] memory updateTypes = new string[](3);
        updateTypes[0] = TYPE_EMA;
        updateTypes[1] = TYPE_DISCOUNT;
        updateTypes[2] = TYPE_EMODE;

        string[] memory emaUpdateTypes = new string[](1);
        emaUpdateTypes[0] = TYPE_EMA;

        address[] memory emaMarkets = new address[](1);
        emaMarkets[0] = PT_ASSET;

        address[] memory initialSenders = new address[](0);

        RiskOracle riskOracle = new RiskOracle("LlamaRisk PT Risk Oracle (Plasma shadow)", initialSenders, updateTypes);
        LlamaGuardOracle emaOracle =
            new LlamaGuardOracle(18, "PT EMA Implied Rate (Pendle, Plasma shadow)", 1, emaUpdateTypes, emaMarkets);
        PTParameterRegistry registry = new PTParameterRegistry(broadcaster, broadcaster);
        LlamaguardRiskOracleRouter router = new LlamaguardRiskOracleRouter(broadcaster);
        router.setUpdater(broadcaster);
        StagingLlamaguardOracleReceiver emaReceiver =
            new StagingLlamaguardOracleReceiver(forwarder, address(emaOracle), "PT EMA staging receiver");
        StagingRiskOracleReceiver singleReceiver = new StagingRiskOracleReceiver(
            forwarder, address(riskOracle), RouterSelectors.PUBLISH_SINGLE_SELECTOR, "PT staging single-update receiver"
        );
        StagingRiskOracleReceiver bulkReceiver = new StagingRiskOracleReceiver(
            forwarder, address(riskOracle), RouterSelectors.PUBLISH_BULK_SELECTOR, "PT staging bulk-update receiver"
        );

        deployed.riskOracle = address(riskOracle);
        deployed.emaOracle = address(emaOracle);
        deployed.emaReceiver = address(emaReceiver);
        deployed.ptParameterRegistry = address(registry);
        deployed.router = address(router);
        deployed.singleReceiver = address(singleReceiver);
        deployed.bulkReceiver = address(bulkReceiver);
    }

    function _configureRegistry(PTParameterRegistry registry) internal {
        uint16[] memory emodeCategoryIds = new uint16[](2);
        emodeCategoryIds[0] = EMODE_STABLECOINS;
        emodeCategoryIds[1] = EMODE_USDE;

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

    /// @dev Router must be able to write to both oracles for the CRE -> Router -> oracle path.
    ///      The staging receivers are also granted write access for the optional direct-write path.
    function _wirePermissions(Deployment memory deployed) internal {
        RiskOracle riskOracle = RiskOracle(deployed.riskOracle);
        riskOracle.addAuthorizedSender(deployed.router);
        riskOracle.addAuthorizedSender(deployed.singleReceiver);
        riskOracle.addAuthorizedSender(deployed.bulkReceiver);

        LlamaGuardOracle emaOracle = LlamaGuardOracle(deployed.emaOracle);
        emaOracle.grantRole(emaOracle.WRITER_ROLE(), deployed.router);
        emaOracle.grantRole(emaOracle.WRITER_ROLE(), deployed.emaReceiver);
    }

    function _logSummary(Deployment memory deployed) internal pure {
        console2.log("--- Deployed (Plasma shadow) ---");
        console2.log(string.concat("OUTPUT:PT_PARAMETER_REGISTRY=", vm.toString(deployed.ptParameterRegistry)));
        console2.log(string.concat("OUTPUT:ROUTER_ADDRESS=", vm.toString(deployed.router)));
        console2.log(string.concat("OUTPUT:LLAMAGUARD_ORACLE_ADDRESS=", vm.toString(deployed.emaOracle)));
        console2.log(string.concat("OUTPUT:RISK_ORACLE_ADDRESS=", vm.toString(deployed.riskOracle)));
        console2.log(string.concat("OUTPUT:EMA_RECEIVER_ADDRESS=", vm.toString(deployed.emaReceiver)));
        console2.log(string.concat("OUTPUT:SINGLE_RECEIVER_ADDRESS=", vm.toString(deployed.singleReceiver)));
        console2.log(string.concat("OUTPUT:BULK_RECEIVER_ADDRESS=", vm.toString(deployed.bulkReceiver)));
    }
}

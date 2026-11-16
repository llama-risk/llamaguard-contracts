// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ILlamaGuardOracle } from "llamaguard-contracts/src/interfaces/ILlamaGuardOracle.sol";
import { LlamaGuardOracle } from "llamaguard-contracts/src/LlamaGuardOracle.sol";
import { LlamaguardRiskOracleRouter } from "../../../../src/LlamaguardRiskOracleRouter.sol";
import { PTParameterRegistry } from "../../../../src/PTParameterRegistry.sol";
import {
    ActivatePTsUSDE28JAN2027
} from "../../../../script/risk-oracles/plasma/production/2_ActivatePTsUSDE28JAN2027.s.sol";
import { PlasmaCoreConfig } from "../../../../script/risk-oracles/plasma/production/PlasmaCoreConfig.sol";
import { PlasmaCoreDeployed } from "../../../../script/risk-oracles/plasma/production/PlasmaCoreDeployed.sol";
import { PTsUSDE28JAN2027 } from "../../../../script/risk-oracles/plasma/production/assets/PTsUSDE28JAN2027.sol";
import { SafeTx } from "../../../../script/risk-oracles/ethereum/production/SafeTx.sol";

interface IPendleMarket {
    function readTokens() external view returns (address sy, address pt, address yt);
    function expiry() external view returns (uint256);
}

interface IPendlePt {
    function expiry() external view returns (uint256);
}

interface IPriceCapAdapter {
    function PENDLE_PRINCIPAL_TOKEN() external view returns (address);
    function MATURITY() external view returns (uint256);
    function MAX_DISCOUNT_RATE_PER_YEAR() external view returns (uint256);
}

interface IAgentHub {
    function getAgentAddress(uint256 agentId) external view returns (address);
    function isAgentEnabled(uint256 agentId) external view returns (bool);
}

/// @notice Phase 2 against live Plasma: the literals, the live stack it builds on, and what the
///         script and the safe's registry write leave behind.
/// @dev    Skips unless `PLASMA_RPC_URL` is set:
///
///           PLASMA_RPC_URL=... forge test --match-path "tests/risk-oracles/script/plasma-production/*"
contract PlasmaAssetForkTest is Test {
    /// @dev Pinned so the same commit cannot pass and fail on different days.
    uint256 internal constant FORK_BLOCK = 37_902_093;

    ActivatePTsUSDE28JAN2027 internal step2;
    bool internal forked;

    function setUp() public {
        string memory rpc = vm.envOr("PLASMA_RPC_URL", string(""));
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc, FORK_BLOCK);
        forked = true;
        step2 = new ActivatePTsUSDE28JAN2027();
    }

    modifier onlyForked() {
        if (!forked) vm.skip(true);
        _;
    }

    // ============================================================================================
    // Literals
    // ============================================================================================

    function test_theAssetLiteralsMatchTheChain() public onlyForked {
        assertEq(IERC20Metadata(PTsUSDE28JAN2027.PT_ASSET).symbol(), "PT-sUSDE-28JAN2027", "PT symbol");
        assertEq(IERC20Metadata(PTsUSDE28JAN2027.PT_ASSET).decimals(), 18, "PT decimals");
        assertEq(IPendlePt(PTsUSDE28JAN2027.PT_ASSET).expiry(), PTsUSDE28JAN2027.PT_MATURITY, "PT expiry");

        (, address pt,) = IPendleMarket(PTsUSDE28JAN2027.PENDLE_MARKET).readTokens();
        assertEq(pt, PTsUSDE28JAN2027.PT_ASSET, "market PT");
        assertEq(IPendleMarket(PTsUSDE28JAN2027.PENDLE_MARKET).expiry(), PTsUSDE28JAN2027.PT_MATURITY, "market expiry");

        IPriceCapAdapter adapter = IPriceCapAdapter(PTsUSDE28JAN2027.PT_PRICE_ADAPTER);
        assertEq(adapter.PENDLE_PRINCIPAL_TOKEN(), PTsUSDE28JAN2027.PT_ASSET, "adapter PT");
        assertEq(adapter.MATURITY(), PTsUSDE28JAN2027.PT_MATURITY, "adapter maturity");
        assertEq(
            adapter.MAX_DISCOUNT_RATE_PER_YEAR(), PTsUSDE28JAN2027.MAX_DISCOUNT_RATE_PER_YEAR, "adapter max discount"
        );
    }

    function test_theLiveStackIsHeldByTheSafe() public onlyForked {
        assertEq(
            LlamaguardRiskOracleRouter(PlasmaCoreDeployed.ROUTER).owner(),
            PlasmaCoreConfig.LLAMARISK_SAFE,
            "router owner"
        );
        assertEq(
            PTParameterRegistry(PlasmaCoreDeployed.PT_PARAMETER_REGISTRY).updater(),
            PlasmaCoreConfig.REGISTRY_UPDATER,
            "registry updater"
        );
    }

    function test_theAgentIdsMatchTheHub() public onlyForked {
        IAgentHub hub = IAgentHub(PlasmaCoreDeployed.AGENT_HUB);
        assertEq(
            hub.getAgentAddress(PlasmaCoreDeployed.DISCOUNT_AGENT_ID),
            PlasmaCoreDeployed.DISCOUNT_RATE_AGENT,
            "discount"
        );
        assertEq(hub.getAgentAddress(PlasmaCoreDeployed.EMODE_AGENT_ID), PlasmaCoreDeployed.EMODE_AGENT, "eMode");
        assertTrue(hub.isAgentEnabled(PlasmaCoreDeployed.DISCOUNT_AGENT_ID), "discount agent disabled");
        assertTrue(hub.isAgentEnabled(PlasmaCoreDeployed.EMODE_AGENT_ID), "eMode agent disabled");
    }

    // ============================================================================================
    // Phase 2
    // ============================================================================================

    function test_phase2LeavesTheEmaOracleWritableOnlyByTheRouter() public onlyForked {
        LlamaGuardOracle emaOracle = LlamaGuardOracle(_deploy());

        assertTrue(ILlamaGuardOracle(address(emaOracle)).hasWriteAccess(PlasmaCoreDeployed.ROUTER), "Router not writer");
        assertFalse(emaOracle.hasRole(0x00, address(step2)), "deployer still holds DEFAULT_ADMIN_ROLE");
        assertTrue(emaOracle.hasRole(0x00, PlasmaCoreConfig.LLAMARISK_SAFE), "safe is not the admin");
        assertEq(emaOracle.decimals(), PTsUSDE28JAN2027.EMA_ORACLE_DECIMALS, "decimals");
        assertEq(emaOracle.description(), PTsUSDE28JAN2027.EMA_ORACLE_DESCRIPTION, "description");
    }

    /// @dev Same stance as Ethereum: the guard ships off until the methodology gives a number.
    function test_theEmaOracleShipsWithItsDeviationGuardOff() public onlyForked {
        assertEq(LlamaGuardOracle(_deploy()).maxPriceDeviation(), 0, "a deviation was set without a decision");
    }

    function test_theSafeBatchRegistersTheAsset() public onlyForked {
        PTParameterRegistry registry = PTParameterRegistry(PlasmaCoreDeployed.PT_PARAMETER_REGISTRY);
        assertFalse(registry.marketExists(PTsUSDE28JAN2027.PT_ASSET), "already registered");

        SafeTx.Call[] memory calls = step2.registryCalls(address(registry));
        for (uint256 i = 0; i < calls.length; i++) {
            vm.prank(PlasmaCoreConfig.LLAMARISK_SAFE);
            (bool ok,) = calls[i].to.call(calls[i].data);
            assertTrue(ok, calls[i].label);
        }

        PTParameterRegistry.PtMarketParams memory params = registry.getPtMarketParams(PTsUSDE28JAN2027.PT_ASSET);
        assertTrue(params.enabled, "not enabled");
        assertEq(params.modelVersion, PTsUSDE28JAN2027.MODEL_VERSION, "model version");
        assertEq(params.emaSpan, PTsUSDE28JAN2027.EMA_SPAN, "ema span");
        assertEq(params.emaFreshnessSeconds, PTsUSDE28JAN2027.EMA_FRESHNESS_SECONDS, "ema freshness");
        assertEq(params.thresholdBps, PTsUSDE28JAN2027.DISCOUNT_THRESHOLD_BPS, "threshold");
        assertEq(params.kReferenceEndpoint, PTsUSDE28JAN2027.K_REFERENCE_ENDPOINT, "K");
        assertEq(params.emodeCategoryIds.length, 1, "eMode ids");
        assertEq(params.emodeCategoryIds[0], PTsUSDE28JAN2027.EMODE_STABLECOINS, "eMode id");
    }

    function _deploy() internal returns (address) {
        return step2.deploy(address(step2), PlasmaCoreDeployed.ROUTER, PlasmaCoreConfig.acl()).emaOracle;
    }
}

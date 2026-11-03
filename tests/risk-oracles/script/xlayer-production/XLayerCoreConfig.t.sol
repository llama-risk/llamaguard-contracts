// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";
import { LlamaguardRiskOracleRouter } from "../../../../src/LlamaguardRiskOracleRouter.sol";
import { XLayerCoreConfig } from "../../../../script/risk-oracles/xlayer/production/XLayerCoreConfig.sol";
import { PTUSDG25FEB2027 } from "../../../../script/risk-oracles/xlayer/production/assets/PTUSDG25FEB2027.sol";

/// @notice Config correctness that needs no fork, and therefore runs in the ordinary test job.
/// @dev    `XLayerCoreConfig` mirrors three `LlamaguardRiskOracleRouter` bounds because the Router
///         declares them `internal` and they cannot be read through the contract type. A mirror that
///         goes stale does not error, it quietly loosens the validation in that file.
contract XLayerCoreConfigTest is Test {
    LlamaguardRiskOracleRouter internal router;

    function setUp() public {
        router = new LlamaguardRiskOracleRouter(address(this));
        router.setUpdater(address(this));
    }

    // ============================================================================================
    // Router bound mirrors
    // ============================================================================================

    function test_minReportAgeMirrorMatchesTheRouter() public view {
        assertEq(
            router.MIN_REPORT_AGE_SECONDS(),
            XLayerCoreConfig.ROUTER_MIN_REPORT_AGE_SECONDS,
            "ROUTER_MIN_REPORT_AGE_SECONDS no longer mirrors the Router"
        );
    }

    function test_maxStepOffMirrorMatchesTheRouter() public view {
        assertEq(
            router.MAX_STEP_OFF(),
            XLayerCoreConfig.ROUTER_MAX_STEP_OFF,
            "ROUTER_MAX_STEP_OFF no longer mirrors the Router"
        );
    }

    /// @dev `MAX_BPS` is `internal` with no getter, so it is asserted through the behaviour it
    ///      governs: the largest accepted step, and the first rejected one.
    function test_maxBpsMirrorMatchesTheRouter() public {
        bytes32 workflowId = bytes32(uint256(1));
        router.addRoute(
            workflowId,
            address(0xF0),
            address(0xA0),
            bytes10("0123456789"),
            address(router), // any contract satisfies the `_isContract` check
            bytes4(0x12345678),
            address(0),
            new uint256[](0),
            0
        );

        router.setRouteThrottle(workflowId, 0, XLayerCoreConfig.ROUTER_MAX_BPS);

        uint64 justOver = XLayerCoreConfig.ROUTER_MAX_BPS + 1;
        vm.expectRevert(abi.encodeWithSelector(LlamaguardRiskOracleRouter.BpsTooHigh.selector, justOver));
        router.setRouteThrottle(workflowId, 0, justOver);
    }

    /// @dev A nonzero report age below the Router minimum expires every report before it can be
    ///      delivered, which bricks the route as surely as a wire-format mismatch.
    function test_theConfiguredReportAgeClearsTheRouterMinimum() public view {
        assertGe(
            XLayerCoreConfig.MAX_REPORT_AGE_SECONDS,
            router.MIN_REPORT_AGE_SECONDS(),
            "MAX_REPORT_AGE_SECONDS is below the Router minimum"
        );
    }

    /// @dev The discount route's step guard is registered off, so the value has to be the Router
    ///      sentinel and not a bps number: anything in `[0, MAX_BPS]` is a live relative cap.
    function test_theDiscountRouteStepGuardIsOff() public view {
        assertEq(
            PTUSDG25FEB2027.DISCOUNT_ROUTER_MAX_STEP,
            router.MAX_STEP_OFF(),
            "the discount route no longer registers the step guard off"
        );
    }

    // ============================================================================================
    // Launch risk parameters
    // ============================================================================================
    // Asserted per value, so a copy-paste from another chain's set cannot pass unnoticed.

    function test_theDiscountRatesAreTheExpectedValues() public pure {
        assertEq(PTUSDG25FEB2027.INITIAL_DISCOUNT_RATE_PER_YEAR, 0.02953e18, "initial discount rate is not 2.953%");
        assertEq(PTUSDG25FEB2027.MAX_DISCOUNT_RATE_PER_YEAR, 0.0791e18, "max discount rate is not 7.910%");
    }

    /// @dev The adapter rejects a seed above its own ceiling, so an inverted pair bricks phase 2 of
    ///      the listing rather than erring on the safe side.
    function test_theInitialDiscountRateIsBelowTheMax() public pure {
        assertLt(
            PTUSDG25FEB2027.INITIAL_DISCOUNT_RATE_PER_YEAR,
            PTUSDG25FEB2027.MAX_DISCOUNT_RATE_PER_YEAR,
            "initial discount rate is not below the max"
        );
    }

    function test_theEmodeParametersAreTheExpectedValues() public pure {
        assertEq(PTUSDG25FEB2027.EMODE_LTV_BPS, 9148, "eMode LTV is not 91.48%");
        assertEq(PTUSDG25FEB2027.EMODE_LT_BPS, 9348, "eMode LT is not 93.48%");
        assertEq(PTUSDG25FEB2027.EMODE_LB_BPS, 262, "eMode LB is not 2.62%");
    }

    /// @dev Aave requires LTV strictly below LT; equal values make every position instantly
    ///      liquidatable at open.
    function test_theEmodeLtvIsBelowTheLiquidationThreshold() public pure {
        assertLt(PTUSDG25FEB2027.EMODE_LTV_BPS, PTUSDG25FEB2027.EMODE_LT_BPS, "eMode LTV is not below LT");
    }

    /// @dev LT + LB must stay at or under 100% or a liquidation can take more than the position.
    function test_theLiquidationThresholdAndBonusCannotExceedParity() public pure {
        assertLe(
            uint256(PTUSDG25FEB2027.EMODE_LT_BPS) + uint256(PTUSDG25FEB2027.EMODE_LB_BPS),
            10_000,
            "LT + LB exceeds 100%"
        );
    }

    // ============================================================================================
    // Asset identity
    // ============================================================================================

    /// @dev Pinned exactly; the fork test checks it against the live PT.
    function test_theMaturityIs25February2027() public pure {
        assertEq(PTUSDG25FEB2027.PT_MATURITY, 1_803_513_600, "maturity is not 25 Feb 2027 00:00:00 UTC");
    }

    /// @dev One eMode category here; the registry write and the risk-params workflow both iterate
    ///      this list. Category 9 per the LlamaRisk recommendation, not the #7 proposed elsewhere.
    function test_thereIsExactlyOneEmodeCategory() public pure {
        uint16[] memory ids = PTUSDG25FEB2027.emodeCategoryIds();
        assertEq(ids.length, 1, "expected exactly one eMode category on X Layer");
        assertEq(ids[0], 9, "eMode id is not 9");
        assertEq(ids[0], PTUSDG25FEB2027.EMODE_STABLECOINS, "eMode id is not the stablecoins category");
        assertEq(PTUSDG25FEB2027.emodeMarkets().length, 1, "eMode market list disagrees with the id list");
    }

    /// @dev Pinned exactly; the fork test checks both against the live chain.
    function test_theIdentityIsTheXLayerMarket() public pure {
        assertEq(PTUSDG25FEB2027.PT_ASSET, 0x5eA1F184af5Ced57725213D8267B5c4C834557D4, "PT address");
        assertEq(PTUSDG25FEB2027.PENDLE_MARKET, 0xB70be417526707c8EBf5F1a79E4876557639B01d, "Pendle market");
    }

    /// @dev Phase 3 hashes these into the route names, so a name copied from another chain would
    ///      register routes no X Layer workflow can ever match.
    function test_theWorkflowNamesAreTheXLayerOnes() public pure {
        assertEq(PTUSDG25FEB2027.EMA_WORKFLOW_NAME, "pt-ema-xlayer-usdg-25feb27-production");
        assertEq(PTUSDG25FEB2027.DISCOUNT_WORKFLOW_NAME, "pt-dro-xlayer-usdg-25feb27-production");
        assertEq(PTUSDG25FEB2027.RISK_PARAMS_WORKFLOW_NAME, "pt-rpo-xlayer-usdg-25feb27-production");
    }

    function test_theRegistryParamsCarryTheEmodeIds() public pure {
        assertEq(
            PTUSDG25FEB2027.ptMarketParams().emodeCategoryIds.length,
            PTUSDG25FEB2027.emodeCategoryIds().length,
            "registry params and the id list disagree"
        );
        assertTrue(PTUSDG25FEB2027.ptMarketParams().enabled, "registry params are not enabled");
    }
}

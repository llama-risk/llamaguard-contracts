// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";
import { LlamaguardRiskOracleRouter } from "../../../../src/LlamaguardRiskOracleRouter.sol";
import { MonadCoreConfig } from "../../../../script/risk-oracles/monad/production/MonadCoreConfig.sol";
import { PTAUSD17DEC2026 } from "../../../../script/risk-oracles/monad/production/assets/PTAUSD17DEC2026.sol";

/// @notice Config correctness that needs no fork, and therefore runs in the ordinary test job.
/// @dev    `MonadCoreConfig` mirrors three `LlamaguardRiskOracleRouter` bounds because the Router
///         declares them `internal` and they cannot be read through the contract type. A mirror that
///         goes stale does not error, it quietly loosens the validation in that file.
contract MonadCoreConfigTest is Test {
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
            MonadCoreConfig.ROUTER_MIN_REPORT_AGE_SECONDS,
            "ROUTER_MIN_REPORT_AGE_SECONDS no longer mirrors the Router"
        );
    }

    function test_maxStepOffMirrorMatchesTheRouter() public view {
        assertEq(
            router.MAX_STEP_OFF(),
            MonadCoreConfig.ROUTER_MAX_STEP_OFF,
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

        router.setRouteThrottle(workflowId, 0, MonadCoreConfig.ROUTER_MAX_BPS);

        uint64 justOver = MonadCoreConfig.ROUTER_MAX_BPS + 1;
        vm.expectRevert(abi.encodeWithSelector(LlamaguardRiskOracleRouter.BpsTooHigh.selector, justOver));
        router.setRouteThrottle(workflowId, 0, justOver);
    }

    /// @dev A nonzero report age below the Router minimum expires every report before it can be
    ///      delivered, which bricks the route as surely as a wire-format mismatch.
    function test_theConfiguredReportAgeClearsTheRouterMinimum() public view {
        assertGe(
            MonadCoreConfig.MAX_REPORT_AGE_SECONDS,
            router.MIN_REPORT_AGE_SECONDS(),
            "MAX_REPORT_AGE_SECONDS is below the Router minimum"
        );
    }

    /// @dev The discount route's step guard is registered off, so the value has to be the Router
    ///      sentinel and not a bps number: anything in `[0, MAX_BPS]` is a live relative cap.
    function test_theDiscountRouteStepGuardIsOff() public view {
        assertEq(
            PTAUSD17DEC2026.DISCOUNT_ROUTER_MAX_STEP,
            router.MAX_STEP_OFF(),
            "the discount route no longer registers the step guard off"
        );
    }

    // ============================================================================================
    // Launch risk parameters
    // ============================================================================================
    // Asserted per value, so a copy-paste from another chain's set cannot pass unnoticed.

    function test_theDiscountRatesAreTheExpectedValues() public pure {
        assertEq(PTAUSD17DEC2026.INITIAL_DISCOUNT_RATE_PER_YEAR, 0.05745e18, "initial discount rate is not 5.745%");
        assertEq(PTAUSD17DEC2026.MAX_DISCOUNT_RATE_PER_YEAR, 0.08804e18, "max discount rate is not 8.804%");
    }

    /// @dev The adapter rejects a seed above its own ceiling, so an inverted pair bricks phase 2 of
    ///      the listing rather than erring on the safe side.
    function test_theInitialDiscountRateIsBelowTheMax() public pure {
        assertLt(
            PTAUSD17DEC2026.INITIAL_DISCOUNT_RATE_PER_YEAR,
            PTAUSD17DEC2026.MAX_DISCOUNT_RATE_PER_YEAR,
            "initial discount rate is not below the max"
        );
    }

    function test_theEmodeParametersAreTheExpectedValues() public pure {
        assertEq(PTAUSD17DEC2026.EMODE_LTV_BPS, 9300, "eMode LTV is not 93.00%");
        assertEq(PTAUSD17DEC2026.EMODE_LT_BPS, 9500, "eMode LT is not 95.00%");
        assertEq(PTAUSD17DEC2026.EMODE_LB_BPS, 262, "eMode LB is not 2.62%");
    }

    /// @dev Aave requires LTV strictly below LT; equal values make every position instantly
    ///      liquidatable at open.
    function test_theEmodeLtvIsBelowTheLiquidationThreshold() public pure {
        assertLt(PTAUSD17DEC2026.EMODE_LTV_BPS, PTAUSD17DEC2026.EMODE_LT_BPS, "eMode LTV is not below LT");
    }

    /// @dev LT + LB must stay at or under 100% or a liquidation can take more than the position.
    function test_theLiquidationThresholdAndBonusCannotExceedParity() public pure {
        assertLe(
            uint256(PTAUSD17DEC2026.EMODE_LT_BPS) + uint256(PTAUSD17DEC2026.EMODE_LB_BPS),
            10_000,
            "LT + LB exceeds 100%"
        );
    }

    /// @dev These are specific to this market and differ from other chains', so a later "align the
    ///      chains" change has to be deliberate.
    function test_theCapsAreTheExpectedValues() public pure {
        assertEq(PTAUSD17DEC2026.LT_CAP_BPS, 9500, "LT cap is not 0.95");
        assertEq(PTAUSD17DEC2026.LB_FLOOR_BPS, 200, "LB floor is not 2.0 pp");
    }

    /// @dev The LT cap bounds what the eMode agent may steer LT to, so a cap below the launch LT
    ///      would have the agent pulling LT down from its own starting value on the first run.
    function test_theLaunchThresholdDoesNotExceedTheCap() public pure {
        assertLe(PTAUSD17DEC2026.EMODE_LT_BPS, PTAUSD17DEC2026.LT_CAP_BPS, "launch LT is above the LT cap");
    }

    /// @dev Likewise the floor: a launch LB below it would be raised on the first run.
    function test_theLaunchBonusIsAtOrAboveTheFloor() public pure {
        assertGe(PTAUSD17DEC2026.EMODE_LB_BPS, PTAUSD17DEC2026.LB_FLOOR_BPS, "launch LB is below the LB floor");
    }

    // ============================================================================================
    // Asset identity
    // ============================================================================================

    /// @dev Pinned exactly; the fork test checks it against the live PT.
    function test_theMaturityIs17December2026() public pure {
        assertEq(PTAUSD17DEC2026.PT_MATURITY, 1_797_465_600, "maturity is not 17 Dec 2026 00:00:00 UTC");
    }

    /// @dev One eMode category here; the registry write and the risk-params workflow both iterate
    ///      this list.
    function test_thereIsExactlyOneEmodeCategory() public pure {
        uint16[] memory ids = PTAUSD17DEC2026.emodeCategoryIds();
        assertEq(ids.length, 1, "expected exactly one eMode category on Monad");
        assertEq(ids[0], PTAUSD17DEC2026.EMODE_STABLECOINS, "eMode id is not the stablecoins category");
        assertEq(PTAUSD17DEC2026.emodeMarkets().length, 1, "eMode market list disagrees with the id list");
    }

    function test_theRegistryParamsCarryTheEmodeIds() public pure {
        assertEq(
            PTAUSD17DEC2026.ptMarketParams().emodeCategoryIds.length,
            PTAUSD17DEC2026.emodeCategoryIds().length,
            "registry params and the id list disagree"
        );
        assertTrue(PTAUSD17DEC2026.ptMarketParams().enabled, "registry params are not enabled");
    }
}

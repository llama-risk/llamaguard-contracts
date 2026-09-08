// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";
import { LlamaguardRiskOracleRouter } from "../../../../src/LlamaguardRiskOracleRouter.sol";
import { EthereumCoreConfig } from "../../../../script/risk-oracles/ethereum/production/EthereumCoreConfig.sol";
import { PTsrUSDe22OCT2026 } from "../../../../script/risk-oracles/ethereum/production/assets/PTsrUSDe22OCT2026.sol";

/// @notice Config correctness that needs no fork, and therefore runs in the ordinary test job.
/// @dev    Two things live here, both of which fail silently in production if they drift.
///
///         `EthereumCoreConfig` mirrors three `LlamaguardRiskOracleRouter` bounds because the Router
///         declares them `internal` and they cannot be read through the contract type. A mirror that
///         goes stale does not error, it quietly loosens the validation in that file, so these
///         assertions are what the config's own comment promises.
///
///         The workflow-name derivation has no onchain correction: `addRoute` accepts any wrong
///         `bytes10` and only rejects zero, there is no setter, and a mistake surfaces when the first
///         live report is rejected.
contract EthereumCoreConfigTest is Test {
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
            EthereumCoreConfig.ROUTER_MIN_REPORT_AGE_SECONDS,
            "ROUTER_MIN_REPORT_AGE_SECONDS no longer mirrors the Router"
        );
    }

    function test_maxStepOffMirrorMatchesTheRouter() public view {
        assertEq(
            router.MAX_STEP_OFF(),
            EthereumCoreConfig.ROUTER_MAX_STEP_OFF,
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

        router.setRouteThrottle(workflowId, 0, EthereumCoreConfig.ROUTER_MAX_BPS);

        uint64 justOver = EthereumCoreConfig.ROUTER_MAX_BPS + 1;
        vm.expectRevert(abi.encodeWithSelector(LlamaguardRiskOracleRouter.BpsTooHigh.selector, justOver));
        router.setRouteThrottle(workflowId, 0, justOver);
    }

    /// @dev A nonzero report age below the Router minimum expires every report before it can be
    ///      delivered, which bricks the route as surely as a wire-format mismatch.
    function test_theConfiguredReportAgeClearsTheRouterMinimum() public view {
        assertGe(
            EthereumCoreConfig.MAX_REPORT_AGE_SECONDS,
            router.MIN_REPORT_AGE_SECONDS(),
            "MAX_REPORT_AGE_SECONDS is below the Router minimum"
        );
    }

    /// @dev The discount route's step guard is registered off, so the value has to be the Router
    ///      sentinel and not a bps number: anything in `[0, MAX_BPS]` is a live relative cap.
    function test_theDiscountRouteStepGuardIsOff() public view {
        assertEq(
            PTsrUSDe22OCT2026.DISCOUNT_ROUTER_MAX_STEP,
            router.MAX_STEP_OFF(),
            "the discount route no longer registers the step guard off"
        );
    }

    // ============================================================================================
    // Workflow name derivation
}

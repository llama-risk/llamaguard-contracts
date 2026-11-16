// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";
import { PlasmaCoreConfig } from "../../../../script/risk-oracles/plasma/production/PlasmaCoreConfig.sol";
import { PTsUSDE28JAN2027 } from "../../../../script/risk-oracles/plasma/production/assets/PTsUSDE28JAN2027.sol";

/// @notice Config correctness that needs no fork. Values are asserted one by one so a copy from
///         another PT's set cannot pass unnoticed.
contract PlasmaCoreConfigTest is Test {
    function validate(address broadcaster) external view {
        PlasmaCoreConfig.validate(broadcaster);
    }

    // ============================================================================================
    // validate
    // ============================================================================================

    function test_validatePassesOnPlasmaWithTheDeployer() public {
        vm.chainId(PlasmaCoreConfig.PLASMA_CHAIN_ID);
        this.validate(PlasmaCoreConfig.DEPLOYER);
        this.validate(address(0));
    }

    function test_validateRejectsAnotherChain() public {
        vm.chainId(1);
        vm.expectRevert("PlasmaCoreConfig: not on Plasma mainnet");
        this.validate(PlasmaCoreConfig.DEPLOYER);
    }

    function test_validateRejectsAnotherBroadcaster() public {
        vm.chainId(PlasmaCoreConfig.PLASMA_CHAIN_ID);
        vm.expectRevert("PlasmaCoreConfig: broadcaster is not DEPLOYER");
        this.validate(address(0xBEEF));
    }

    // ============================================================================================
    // Launch risk parameters
    // ============================================================================================

    function test_theDiscountRatesAreTheExpectedValues() public pure {
        assertEq(PTsUSDE28JAN2027.INITIAL_DISCOUNT_RATE_PER_YEAR, 0.04399e18, "initial discount rate is not 4.399%");
        assertEq(PTsUSDE28JAN2027.MAX_DISCOUNT_RATE_PER_YEAR, 0.09047e18, "max discount rate is not 9.047%");
        assertLt(
            PTsUSDE28JAN2027.INITIAL_DISCOUNT_RATE_PER_YEAR,
            PTsUSDE28JAN2027.MAX_DISCOUNT_RATE_PER_YEAR,
            "initial discount rate is not below the max"
        );
    }

    function test_theEmodeParametersAreTheExpectedValues() public pure {
        assertEq(PTsUSDE28JAN2027.EMODE_LTV_BPS, 9000, "eMode LTV is not 90.00%");
        assertEq(PTsUSDE28JAN2027.EMODE_LT_BPS, 9200, "eMode LT is not 92.00%");
        assertEq(PTsUSDE28JAN2027.EMODE_LB_BPS, 495, "eMode LB is not 4.95%");
        assertLt(PTsUSDE28JAN2027.EMODE_LTV_BPS, PTsUSDE28JAN2027.EMODE_LT_BPS, "eMode LTV is not below LT");
        assertLe(
            uint256(PTsUSDE28JAN2027.EMODE_LT_BPS) + uint256(PTsUSDE28JAN2027.EMODE_LB_BPS),
            10_000,
            "LT + LB exceeds 100%"
        );
    }

    function test_theCapsAreTheExpectedValues() public pure {
        assertEq(PTsUSDE28JAN2027.LT_CAP_BPS, 9200, "LT cap is not 0.92");
        assertEq(PTsUSDE28JAN2027.LB_FLOOR_BPS, 400, "LB floor is not 4.0 pp");
        assertLe(PTsUSDE28JAN2027.EMODE_LT_BPS, PTsUSDE28JAN2027.LT_CAP_BPS, "launch LT is above the LT cap");
        assertGe(PTsUSDE28JAN2027.EMODE_LB_BPS, PTsUSDE28JAN2027.LB_FLOOR_BPS, "launch LB is below the LB floor");
    }

    // ============================================================================================
    // Registry params
    // ============================================================================================

    function test_theRegistryParamsAreTheExpectedValues() public pure {
        assertTrue(PTsUSDE28JAN2027.ptMarketParams().enabled, "registry params are not enabled");
        assertEq(PTsUSDE28JAN2027.MODEL_VERSION, 1, "model version");
        assertEq(PTsUSDE28JAN2027.EMA_SPAN, 48, "ema span");
        assertEq(PTsUSDE28JAN2027.EMA_FRESHNESS_SECONDS, 14_400, "ema freshness");
        assertEq(PTsUSDE28JAN2027.DISCOUNT_THRESHOLD_BPS, 30, "discount threshold");
        assertEq(PTsUSDE28JAN2027.K_REFERENCE_ENDPOINT, 25_000, "K reference endpoint");
    }

    function test_thereIsExactlyOneEmodeCategory() public pure {
        uint16[] memory ids = PTsUSDE28JAN2027.ptMarketParams().emodeCategoryIds;
        assertEq(ids.length, 1, "expected exactly one eMode category");
        assertEq(ids[0], 27, "eMode id is not 27");
        assertEq(PTsUSDE28JAN2027.emodeMarkets().length, 1, "eMode market list disagrees with the id list");
    }

    function test_theMaturityIs28January2027() public pure {
        assertEq(PTsUSDE28JAN2027.PT_MATURITY, 1_801_094_400, "maturity is not 28 Jan 2027 00:00:00 UTC");
    }
}

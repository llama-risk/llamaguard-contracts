// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { PTParameterRegistry } from "../../../../../src/PTParameterRegistry.sol";

/// @title PTsUSDE28JAN2027
/// @notice Everything per-asset about the PT-sUSDE-28JAN2027 reserve on Plasma.
/// @dev    Literals until the address book carries the asset. The fork test re-reads each one.
library PTsUSDE28JAN2027 {
    /// @notice The PT. `symbol()` is "PT-sUSDE-28JAN2027", `decimals()` is 18.
    address internal constant PT_ASSET = 0x257561233419039BeC3a28be717d14B4f490883D;

    /// @notice The Pendle market the EMA and risk-params workflows read.
    address internal constant PENDLE_MARKET = 0xDb96B529D19FF4a7d711E6E082172c77cfe88ed8;

    /// @notice 28 January 2027 00:00:00 UTC, the PT and market `expiry()`.
    uint256 internal constant PT_MATURITY = 1_801_094_400;

    /// @notice Discount adapter from the listing AIP; the discount agent calls `setDiscountRatePerYear` on it.
    address internal constant PT_PRICE_ADAPTER = 0x94b31Cd097c4Ec98F9CaD1c82be2cdA3215b527f;

    /// @notice eMode `sUSDe_PT_sUSDe_28JAN2027__Stablecoins`, created by the listing AIP.
    /// @dev    The first free id at the time of writing. Confirm onchain after the AIP executes;
    ///         if it differs, update this and re-send the registry write.
    uint16 internal constant EMODE_STABLECOINS = 27;

    // LlamaGuardOracle (EMA), deployed per asset by phase 2.
    uint8 internal constant EMA_ORACLE_DECIMALS = 18;
    uint256 internal constant EMA_ORACLE_VERSION = 1;
    string internal constant EMA_ORACLE_DESCRIPTION = "PT-sUSDE-28JAN2027 EMA Implied Rate (Pendle, Plasma)";

    // Registry market params.
    uint32 internal constant MODEL_VERSION = 1;
    uint32 internal constant EMA_SPAN = 48;
    uint64 internal constant EMA_FRESHNESS_SECONDS = 14_400;
    uint64 internal constant DISCOUNT_THRESHOLD_BPS = 30;
    uint64 internal constant K_REFERENCE_ENDPOINT = 25_000;

    // CRE workflow names, as in each workflow.yaml.
    string internal constant EMA_WORKFLOW_NAME = "pt-ema-plasma-susde-28jan27-production";
    string internal constant DISCOUNT_WORKFLOW_NAME = "pt-dro-plasma-susde-28jan27-production";
    string internal constant RISK_PARAMS_WORKFLOW_NAME = "pt-rpo-plasma-susde-28jan27-production";

    // Launch risk parameters. `PlasmaCoreConfig.t.sol` asserts each value.
    uint256 internal constant INITIAL_DISCOUNT_RATE_PER_YEAR = 0.04399e18;
    uint256 internal constant MAX_DISCOUNT_RATE_PER_YEAR = 0.09047e18;
    uint16 internal constant EMODE_LTV_BPS = 9000;
    uint16 internal constant EMODE_LT_BPS = 9200;
    /// @dev Bonus only; the configurator value is 10_495.
    uint16 internal constant EMODE_LB_BPS = 495;
    uint64 internal constant LT_CAP_BPS = 9200;
    uint64 internal constant LB_FLOOR_BPS = 400;

    function ptMarketParams() internal pure returns (PTParameterRegistry.PtMarketParams memory) {
        return PTParameterRegistry.PtMarketParams({
            enabled: true,
            modelVersion: MODEL_VERSION,
            emaSpan: EMA_SPAN,
            emaFreshnessSeconds: EMA_FRESHNESS_SECONDS,
            thresholdBps: DISCOUNT_THRESHOLD_BPS,
            kReferenceEndpoint: K_REFERENCE_ENDPOINT,
            emodeCategoryIds: emodeCategoryIds()
        });
    }

    function emodeCategoryIds() internal pure returns (uint16[] memory ids) {
        ids = new uint16[](1);
        ids[0] = EMODE_STABLECOINS;
    }

    function emaAuthorizedMarkets() internal pure returns (address[] memory markets) {
        markets = new address[](1);
        markets[0] = PT_ASSET;
    }

    /// @notice eMode ids as the AgentHub encodes them: widened into addresses.
    function emodeMarkets() internal pure returns (address[] memory markets) {
        markets = new address[](1);
        markets[0] = address(uint160(EMODE_STABLECOINS));
    }
}

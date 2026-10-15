// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { PTParameterRegistry } from "../../../../../src/PTParameterRegistry.sol";
import { XLayerCoreConfig } from "../XLayerCoreConfig.sol";

/// @title PTUSDG25FEB2027
/// @notice Everything per-asset about the PT-USDG-25FEB2027 reserve on X Layer. One file per PT.
/// @dev    Addresses are literals rather than `aave-address-book` constants: no published version of
///         the book carries this asset. Replace them with book constants once it does. The fork
///         test re-reads each one from X Layer mainnet, since nothing else can check a literal.
///
///         Two things are deliberately absent until they exist: `PT_PRICE_ADAPTER`, which the
///         listing AIP deploys, and `LT_CAP_BPS` / `LB_FLOOR_BPS`, which come from RND-48.
library PTUSDG25FEB2027 {
    /// @notice The PT reserve. `symbol()` is "PT-USDG-25FEB2027", `decimals()` is 6.
    address internal constant PT_ASSET = 0x5eA1F184af5Ced57725213D8267B5c4C834557D4;

    /// @notice The Pendle market the EMA and risk-params workflows read.
    address internal constant PENDLE_MARKET = 0xB70be417526707c8EBf5F1a79E4876557639B01d;

    /// @notice 25 February 2027 00:00:00 UTC, matching both the PT and the market `expiry()`.
    uint256 internal constant PT_MATURITY = 1_803_513_600;

    /// @notice eMode category for this PT: "PT-USDG-25FEB2027 Stablecoins", created by the listing.
    /// @dev    One category, so `emodeCategoryIds` has length 1. 9 per LlamaRisk's recommendation.
    uint16 internal constant EMODE_STABLECOINS = 9;

    // LlamaGuardOracle (EMA), deployed per asset by phase 2.
    uint8 internal constant EMA_ORACLE_DECIMALS = 18;
    uint256 internal constant EMA_ORACLE_VERSION = 1;
    string internal constant EMA_ORACLE_DESCRIPTION = "PT-USDG-25FEB2027 EMA Implied Rate (Pendle, X Layer)";

    // Registry market params.
    uint32 internal constant MODEL_VERSION = 1;
    uint32 internal constant EMA_SPAN = 48;
    uint64 internal constant EMA_FRESHNESS_SECONDS = 14_400;
    uint64 internal constant DISCOUNT_THRESHOLD_BPS = 30;
    uint64 internal constant K_REFERENCE_ENDPOINT = 25_000;

    /// @notice Router min delay on the discount route; matches the agent's hub `minimumDelay`.
    uint64 internal constant DISCOUNT_MIN_DELAY_SECONDS = 172_800;

    /// @notice Step cap off; the per-injection bound is `DISCOUNT_RANGE_ABS` at the RVM.
    uint64 internal constant DISCOUNT_ROUTER_MAX_STEP = XLayerCoreConfig.ROUTER_MAX_STEP_OFF;

    // CRE workflow names as in each workflow.yaml; phase 3 hashes them into the bytes10.
    string internal constant EMA_WORKFLOW_NAME = "pt-ema-xlayer-usdg-25feb27-production";
    string internal constant DISCOUNT_WORKFLOW_NAME = "pt-dro-xlayer-usdg-25feb27-production";
    string internal constant RISK_PARAMS_WORKFLOW_NAME = "pt-rpo-xlayer-usdg-25feb27-production";

    // AgentHub registration values, consumed by the AIP rather than by any script here.
    uint256 internal constant DISCOUNT_AGENT_MINIMUM_DELAY = 172_800;
    uint256 internal constant DISCOUNT_AGENT_EXPIRATION_PERIOD = 172_800;
    uint256 internal constant EMODE_AGENT_MINIMUM_DELAY = 259_200;
    uint256 internal constant EMODE_AGENT_EXPIRATION_PERIOD = 259_200;

    /// @notice Absolute per-injection bound on the discount rate, 100 bps in 1e18 units.
    uint120 internal constant DISCOUNT_RANGE_ABS = 1e16;

    /// @notice Absolute per-injection bound on each eMode field, in bps.
    uint120 internal constant EMODE_RANGE_ABS_BPS = 50;

    // ============================================================================================
    // Launch risk parameters
    // ============================================================================================
    // Per-maturity, so not interchangeable with another PT's set on this chain. LlamaRisk's listing
    // recommendation of 8 Oct 2026 (governance.aave.com/t/25733/2). `XLayerCoreConfig.t.sol` asserts
    // each value.

    /// @notice initialDiscountRatePerYear, in 1e18 units: 2.953%.
    uint256 internal constant INITIAL_DISCOUNT_RATE_PER_YEAR = 0.02953e18;

    /// @notice maxDiscountRatePerYear, in 1e18 units: 7.910%.
    uint256 internal constant MAX_DISCOUNT_RATE_PER_YEAR = 0.0791e18;

    /// @notice eMode LTV, in bps: 91.48%.
    uint16 internal constant EMODE_LTV_BPS = 9148;

    /// @notice eMode liquidation threshold, in bps: 93.48%.
    uint16 internal constant EMODE_LT_BPS = 9348;

    /// @notice eMode liquidation bonus, in bps of bonus: 2.62%.
    /// @dev    Aave encodes this as 10_000 + bonus, so the configurator value is 10_262.
    uint16 internal constant EMODE_LB_BPS = 262;

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

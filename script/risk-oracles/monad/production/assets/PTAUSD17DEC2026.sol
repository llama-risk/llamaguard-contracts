// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { PTParameterRegistry } from "../../../../../src/PTParameterRegistry.sol";
import { MonadCoreConfig } from "../MonadCoreConfig.sol";

/// @title PTAUSD17DEC2026
/// @notice Everything per-asset about the PT-AUSD-17DEC2026 reserve on Monad. One file per PT.
/// @dev    Addresses are literals rather than `aave-address-book` constants: no published version of
///         the book carries this asset. Replace them with book constants once it does. The fork
///         tests re-read each one from Monad mainnet, since nothing else can check a literal.
library PTAUSD17DEC2026 {
    /// @notice The PT reserve. `symbol()` is "PT-AUSD-17DEC2026", `decimals()` is 6.
    address internal constant PT_ASSET = 0x8B562578b2f9Aa8C14cCda3c5d6CBCEaD3B06a57;

    /// @notice The Pendle market the EMA and risk-params workflows read.
    address internal constant PENDLE_MARKET = 0x9CBc42eff240AD2E43BbDc3C0562A9b4Ce842a5a;

    /// @notice 17 December 2026 00:00:00 UTC, matching both the PT and the market `expiry()`.
    uint256 internal constant PT_MATURITY = 1_797_465_600;

    /// @notice The adapter the discount agent calls `setDiscountRatePerYear` on.
    /// @dev    One adapter per maturity, with `MATURITY` immutable; the fork test asserts it.
    ///         Re-check this against the listing payload before phase 3: the adapter is redeployable
    ///         independently of this repo, and a stale address here points the agent at a dead one.
    address internal constant PT_PRICE_ADAPTER = 0x4dc9Ee8d739411242303f7F78C6610d5B0371a2C;

    /// @notice eMode category for this PT.
    /// @dev    One category, so `emodeCategoryIds` has length 1.
    uint16 internal constant EMODE_STABLECOINS = 6;

    // LlamaGuardOracle (EMA), deployed per asset by phase 2.
    uint8 internal constant EMA_ORACLE_DECIMALS = 18;
    uint256 internal constant EMA_ORACLE_VERSION = 1;
    string internal constant EMA_ORACLE_DESCRIPTION = "PT-AUSD-17DEC2026 EMA Implied Rate (Pendle, Monad)";

    // Registry market params.
    uint32 internal constant MODEL_VERSION = 1;
    uint32 internal constant EMA_SPAN = 48;
    uint64 internal constant EMA_FRESHNESS_SECONDS = 14_400;
    uint64 internal constant DISCOUNT_THRESHOLD_BPS = 30;
    uint64 internal constant K_REFERENCE_ENDPOINT = 25_000;

    /// @notice Router min delay on the discount route; matches the agent's hub `minimumDelay`.
    uint64 internal constant DISCOUNT_MIN_DELAY_SECONDS = 172_800;

    /// @notice Step cap off; the per-injection bound is `DISCOUNT_RANGE_ABS` at the RVM.
    uint64 internal constant DISCOUNT_ROUTER_MAX_STEP = MonadCoreConfig.ROUTER_MAX_STEP_OFF;

    // CRE workflow names as in each workflow.yaml; phase 3 hashes them into the bytes10.
    string internal constant EMA_WORKFLOW_NAME = "pt-ema-monad-ausd-17dec26-production";
    string internal constant DISCOUNT_WORKFLOW_NAME = "pt-dro-monad-ausd-17dec26-production";
    string internal constant RISK_PARAMS_WORKFLOW_NAME = "pt-rpo-monad-ausd-17dec26-production";

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
    // Per-maturity, so not interchangeable with another PT's set on this chain. `MonadCoreConfig.t.sol`
    // asserts each value.

    /// @notice initialDiscountRatePerYear, in 1e18 units: 5.745%.
    uint256 internal constant INITIAL_DISCOUNT_RATE_PER_YEAR = 0.05745e18;

    /// @notice maxDiscountRatePerYear, in 1e18 units: 8.804%.
    uint256 internal constant MAX_DISCOUNT_RATE_PER_YEAR = 0.08804e18;

    /// @notice eMode LTV, in bps: 93.00%.
    uint16 internal constant EMODE_LTV_BPS = 9300;

    /// @notice eMode liquidation threshold, in bps: 95.00%.
    uint16 internal constant EMODE_LT_BPS = 9500;

    /// @notice eMode liquidation bonus, in bps of bonus: 2.62%.
    /// @dev    Aave encodes this as 10_000 + bonus, so the configurator value is 10_262.
    uint16 internal constant EMODE_LB_BPS = 262;

    /// @notice LT cap, in bps: 0.95.
    uint64 internal constant LT_CAP_BPS = 9500;

    /// @notice LB floor (L_unet), in bps: 2.0 pp.
    uint64 internal constant LB_FLOOR_BPS = 200;

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

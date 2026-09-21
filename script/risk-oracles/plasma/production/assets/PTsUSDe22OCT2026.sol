// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { AaveV3PlasmaAssets, AaveV3PlasmaEModes } from "aave-address-book/AaveV3Plasma.sol";
import { PTParameterRegistry } from "../../../../../src/PTParameterRegistry.sol";
import { PlasmaCoreConfig } from "../PlasmaCoreConfig.sol";

/// @title PTsUSDe22OCT2026
/// @notice Everything about the PT-sUSDe-22OCT2026 reserve on Aave V3 Plasma that the chain-scoped
///         half of the deployment does not know. Phase 2 and phase 3 read this file; phase 1 never
///         does.
/// @dev    One of these per PT asset; the layout and the per-asset-EMA-oracle reasoning are
///         documented in the Ethereum counterpart and hold unchanged.
///
///         The address book carries the reserve, its price adapter and both eMode ids, so they are
///         read from it rather than copied: the AIP payload names the same constants, and a literal
///         here is how the two repositories drift after a book correction. The Pendle market and
///         the maturity have no book entry and stay literals; both verified onchain against the
///         shadow deployment's reads on chain 9745.
library PTsUSDe22OCT2026 {
    // ============================================================================================
    // The reserve
    // ============================================================================================

    /// @notice The PT reserve, id 17 on Plasma. Registry key, EMA oracle authorized market, and the
    ///         discount agent's single allowed market.
    address internal constant PT_ASSET = AaveV3PlasmaAssets.PT_sUSDE_22OCT2026_UNDERLYING;

    /// @notice The Pendle market the EMA and risk-params workflows read.
    address internal constant PENDLE_MARKET = 0x14c3fc8096cB5B34C2780C6a5977A3d354b9E961;

    /// @notice PT maturity, 22 October 2026. Same instrument date as the Ethereum PT-srUSDe;
    ///         read back from the live adapter's `MATURITY()`.
    uint256 internal constant PT_MATURITY = 1_792_627_200;

    /// @notice The `PendlePriceCapAdapter` the Aave oracle resolves for this PT, and therefore the
    ///         contract the discount agent calls `setDiscountRatePerYear` on. It gates that call on
    ///         `isRiskAdmin || isPoolAdmin`, which is why the AIP grants RISK_ADMIN to the agent.
    address internal constant PT_PRICE_ADAPTER = AaveV3PlasmaAssets.PT_sUSDE_22OCT2026_ORACLE;

    /// @notice eMode categories this PT is collateral in, ids 25 and 26 on Plasma. Stored as ids in
    ///         the registry and encoded as addresses at AgentHub registration, following the
    ///         chaos-agents convention.
    uint16 internal constant EMODE_STABLECOINS = AaveV3PlasmaEModes.sUSDe_PT_sUSDE_22OCT2026__USDT0_USDe_GHO;
    uint16 internal constant EMODE_USDE = AaveV3PlasmaEModes.sUSDe_PT_sUSDE_22OCT2026__USDe;

    // ============================================================================================
    // LlamaGuardOracle (EMA), deployed per asset by phase 2
    // ============================================================================================

    uint8 internal constant EMA_ORACLE_DECIMALS = 18;
    uint256 internal constant EMA_ORACLE_VERSION = 1;
    string internal constant EMA_ORACLE_DESCRIPTION = "PT-sUSDe-22OCT2026 EMA Implied Rate (Pendle, Plasma)";

    // ============================================================================================
    // Registry market params
    // ============================================================================================

    /// @dev The methodology is asset agnostic, so these do not vary by PT; they match the values
    ///      the shadow registry has run with since June and the Ethereum production registry.
    ///      What varies per deployment is the eMode ids.
    uint32 internal constant MODEL_VERSION = 1;
    uint32 internal constant EMA_SPAN = 48;
    uint64 internal constant EMA_FRESHNESS_SECONDS = 14_400;
    uint64 internal constant DISCOUNT_THRESHOLD_BPS = 30;
    uint64 internal constant K_REFERENCE_ENDPOINT = 25_000;

    // ============================================================================================
    // Route policy, phase 3
    // ============================================================================================

    /// @notice Minimum seconds between discount rate publishes, enforced at the Router. Matches the
    ///         `minimumDelay` the AIP registers on the discount agent, so the two gates agree.
    uint64 internal constant DISCOUNT_MIN_DELAY_SECONDS = 172_800;

    /// @notice Router max-step for the discount route, registered off. The per-injection bound on
    ///         the discount rate is `DISCOUNT_RANGE_ABS`, checked by the `RangeValidationModule`
    ///         when the agent injects. Freezing a route outright means `setRouteEnabled(false)`,
    ///         not a zero step.
    uint64 internal constant DISCOUNT_ROUTER_MAX_STEP = PlasmaCoreConfig.ROUTER_MAX_STEP_OFF;

    // ============================================================================================
    // CRE workflow names
    // ============================================================================================

    /// @notice The names as they appear in each `workflow.yaml`. Phase 3 hashes these into the
    ///         `bytes10` the Router compares against, rather than taking the hash as an input,
    ///         because `addRoute` accepts any wrong name and there is no setter to correct one.
    string internal constant EMA_WORKFLOW_NAME = "pt-ema-plasma-susde-22oct26-production";
    string internal constant DISCOUNT_WORKFLOW_NAME = "pt-dro-plasma-susde-22oct26-production";
    string internal constant RISK_PARAMS_WORKFLOW_NAME = "pt-rpo-plasma-susde-22oct26-production";

    // ============================================================================================
    // AgentHub registration, consumed by the AIP rather than by any script here
    // ============================================================================================

    /// @dev Recorded here so the payload and this repo cannot drift. Nothing in `script/` calls the
    ///      hub: `registerAgent` is `onlyOwner` and the owner is the Aave Executor.
    uint256 internal constant DISCOUNT_AGENT_MINIMUM_DELAY = 172_800;
    uint256 internal constant DISCOUNT_AGENT_EXPIRATION_PERIOD = 172_800;
    uint256 internal constant EMODE_AGENT_MINIMUM_DELAY = 259_200;
    uint256 internal constant EMODE_AGENT_EXPIRATION_PERIOD = 259_200;

    /// @notice Absolute per-injection bound on the discount rate, in the adapter's 1e18 units,
    ///         100 bps. The only delta bound the route carries.
    uint120 internal constant DISCOUNT_RANGE_ABS = 1e16;

    /// @notice Absolute per-injection bound on each eMode field, in bps. Applies to `EModeLTV`,
    ///         `EModeLiquidationThreshold` and `EModeLiquidationBonus` alike.
    uint120 internal constant EMODE_RANGE_ABS_BPS = 50;

    // ============================================================================================
    // Derived views
    // ============================================================================================

    /// @notice Registry params for this reserve, exactly as phase 2 hands them to the safe.
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

    /// @notice eMode category ids for this reserve, in registry order.
    function emodeCategoryIds() internal pure returns (uint16[] memory ids) {
        ids = new uint16[](2);
        ids[0] = EMODE_STABLECOINS;
        ids[1] = EMODE_USDE;
    }

    /// @notice The single authorized market on the EMA oracle.
    function emaAuthorizedMarkets() internal pure returns (address[] memory markets) {
        markets = new address[](1);
        markets[0] = PT_ASSET;
    }

    /// @notice The eMode categories as the AgentHub encodes them: an id widened into an address.
    function emodeMarkets() internal pure returns (address[] memory markets) {
        markets = new address[](2);
        markets[0] = address(uint160(EMODE_STABLECOINS));
        markets[1] = address(uint160(EMODE_USDE));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { AaveV3PlasmaAssets, AaveV3PlasmaEModes } from "aave-address-book/AaveV3Plasma.sol";
import { PTParameterRegistry } from "../../../../../src/PTParameterRegistry.sol";
import { PlasmaCoreConfig } from "../PlasmaCoreConfig.sol";

/// @title PTsUSDe22OCT2026
/// @notice Everything per-asset about the PT-sUSDe-22OCT2026 reserve on Plasma. One file per PT;
///         book constants wherever the book carries them.
library PTsUSDe22OCT2026 {
    /// @notice The PT reserve, id 17 on Plasma.
    address internal constant PT_ASSET = AaveV3PlasmaAssets.PT_sUSDE_22OCT2026_UNDERLYING;

    /// @notice The Pendle market the EMA and risk-params workflows read.
    address internal constant PENDLE_MARKET = 0x14c3fc8096cB5B34C2780C6a5977A3d354b9E961;

    /// @notice 22 October 2026, read back from the live adapter's `MATURITY()`.
    uint256 internal constant PT_MATURITY = 1_792_627_200;

    /// @notice The adapter the discount agent calls `setDiscountRatePerYear` on.
    address internal constant PT_PRICE_ADAPTER = AaveV3PlasmaAssets.PT_sUSDE_22OCT2026_ORACLE;

    /// @notice eMode categories this PT is collateral in: 25 and 26.
    uint16 internal constant EMODE_STABLECOINS = AaveV3PlasmaEModes.sUSDe_PT_sUSDE_22OCT2026__USDT0_USDe_GHO;
    uint16 internal constant EMODE_USDE = AaveV3PlasmaEModes.sUSDe_PT_sUSDE_22OCT2026__USDe;

    // LlamaGuardOracle (EMA), deployed per asset by phase 2.
    uint8 internal constant EMA_ORACLE_DECIMALS = 18;
    uint256 internal constant EMA_ORACLE_VERSION = 1;
    string internal constant EMA_ORACLE_DESCRIPTION = "PT-sUSDe-22OCT2026 EMA Implied Rate (Pendle, Plasma)";

    // Registry market params; methodology defaults, matching the shadow registry and Ethereum.
    uint32 internal constant MODEL_VERSION = 1;
    uint32 internal constant EMA_SPAN = 48;
    uint64 internal constant EMA_FRESHNESS_SECONDS = 14_400;
    uint64 internal constant DISCOUNT_THRESHOLD_BPS = 30;
    uint64 internal constant K_REFERENCE_ENDPOINT = 25_000;

    /// @notice Router min delay on the discount route; matches the agent's hub `minimumDelay`.
    uint64 internal constant DISCOUNT_MIN_DELAY_SECONDS = 172_800;

    /// @notice Step cap off; the per-injection bound is `DISCOUNT_RANGE_ABS` at the RVM.
    uint64 internal constant DISCOUNT_ROUTER_MAX_STEP = PlasmaCoreConfig.ROUTER_MAX_STEP_OFF;

    // CRE workflow names as in each workflow.yaml; phase 3 hashes them into the bytes10.
    string internal constant EMA_WORKFLOW_NAME = "pt-ema-plasma-susde-22oct26-production";
    string internal constant DISCOUNT_WORKFLOW_NAME = "pt-dro-plasma-susde-22oct26-production";
    string internal constant RISK_PARAMS_WORKFLOW_NAME = "pt-rpo-plasma-susde-22oct26-production";

    // AgentHub registration values, consumed by the AIP rather than by any script here.
    uint256 internal constant DISCOUNT_AGENT_MINIMUM_DELAY = 172_800;
    uint256 internal constant DISCOUNT_AGENT_EXPIRATION_PERIOD = 172_800;
    uint256 internal constant EMODE_AGENT_MINIMUM_DELAY = 259_200;
    uint256 internal constant EMODE_AGENT_EXPIRATION_PERIOD = 259_200;

    /// @notice Absolute per-injection bound on the discount rate, 100 bps in 1e18 units.
    uint120 internal constant DISCOUNT_RANGE_ABS = 1e16;

    /// @notice Absolute per-injection bound on each eMode field, in bps.
    uint120 internal constant EMODE_RANGE_ABS_BPS = 50;

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
        ids = new uint16[](2);
        ids[0] = EMODE_STABLECOINS;
        ids[1] = EMODE_USDE;
    }

    function emaAuthorizedMarkets() internal pure returns (address[] memory markets) {
        markets = new address[](1);
        markets[0] = PT_ASSET;
    }

    /// @notice eMode ids as the AgentHub encodes them: widened into addresses.
    function emodeMarkets() internal pure returns (address[] memory markets) {
        markets = new address[](2);
        markets[0] = address(uint160(EMODE_STABLECOINS));
        markets[1] = address(uint160(EMODE_USDE));
    }
}

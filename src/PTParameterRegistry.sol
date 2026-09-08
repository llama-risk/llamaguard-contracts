// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { Ownable, Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title PTParameterRegistry
/// @notice Per-market tuning knobs consumed by the three PT CRE workflows (EMA, discount-rate, risk-params).
/// @dev Schema follows `docs/architecture.md` §6 (`PtMarketParams`). Hardcoded `LB_floor` / `LT_cap`
///      tables are intentionally NOT stored here — those live in CRE `pendle_common` per
///      `docs/spec-risk-parameters.md`. Access control mirrors `contracts/lib/llamaguard-contracts`
///      `ParameterRegistry`: `Ownable2Step` owner plus a separate `updater` role for day-to-day setters.
contract PTParameterRegistry is Ownable2Step {
    /// @notice Cap on any basis-point input (100% = 10_000 bps).
    uint64 public constant MAX_BPS = 10_000;
    /// @notice Fixed-point scale for the risk-params reference-proportion multiplier K.
    uint64 public constant K_FACTOR_SCALE = 10_000;

    struct PtMarketParams {
        // shared
        bool enabled;
        uint32 modelVersion;
        // EMA slice
        uint32 emaSpan;
        uint64 emaFreshnessSeconds;
        // Discount-rate slice
        uint64 thresholdBps; // deviation threshold for update gating (0.30% = 30 bps)
        // Risk-params slice
        uint64 kReferenceEndpoint; // K parameter for p_star calculation (scaled by K_FACTOR_SCALE)
        uint16[] emodeCategoryIds; // eMode categories this PT is listed in
    }

    address public updater;
    mapping(address market => PtMarketParams) private _ptParams;
    mapping(address market => bool) private _exists;

    event UpdaterChanged(address indexed previousUpdater, address indexed newUpdater);
    event PtMarketParamsSet(address indexed market, PtMarketParams params);
    event EnabledSet(address indexed market, bool enabled);
    event ModelVersionSet(address indexed market, uint32 modelVersion);
    event EmaSpanSet(address indexed market, uint32 emaSpan);
    event EmaFreshnessSecondsSet(address indexed market, uint64 emaFreshnessSeconds);
    event DeviationThresholdBpsSet(address indexed market, uint64 thresholdBps);
    event KReferenceEndpointSet(address indexed market, uint64 kReferenceEndpoint);
    event EmodeCategoryIdsSet(address indexed market, uint16[] emodeCategoryIds);
    event MarketDeleted(address indexed market);

    error OnlyUpdater();
    error MarketNotFound();
    error ZeroAddress();
    error InvalidEmaSpan();
    error InvalidEmaFreshness();
    error InvalidKReferenceEndpoint();
    error BpsTooHigh(uint64 value);
    error EmptyEmodeCategoryIds();

    modifier onlyUpdater() {
        if (msg.sender != updater) revert OnlyUpdater();
        _;
    }

    constructor(address _owner, address _updater) Ownable(_owner) {
        if (_updater == address(0)) revert ZeroAddress();
        updater = _updater;
        emit UpdaterChanged(address(0), _updater);
    }

    // ============================================================================================
    // Owner functions
    // ============================================================================================

    function setUpdater(address _updater) external onlyOwner {
        if (_updater == address(0)) revert ZeroAddress();
        address previous = updater;
        updater = _updater;
        emit UpdaterChanged(previous, _updater);
    }

    // ============================================================================================
    // Updater functions
    // ============================================================================================

    function setPtMarketParams(address market, PtMarketParams calldata p) external onlyUpdater {
        if (market == address(0)) revert ZeroAddress();
        _validateParams(p);

        _ptParams[market] = p;
        _exists[market] = true;

        emit PtMarketParamsSet(market, p);
    }

    function setEnabled(address market, bool enabled_) external onlyUpdater {
        if (!_exists[market]) revert MarketNotFound();
        _ptParams[market].enabled = enabled_;
        emit EnabledSet(market, enabled_);
    }

    function setModelVersion(address market, uint32 modelVersion) external onlyUpdater {
        if (!_exists[market]) revert MarketNotFound();
        _ptParams[market].modelVersion = modelVersion;
        emit ModelVersionSet(market, modelVersion);
    }

    function setEmaSpan(address market, uint32 emaSpan) external onlyUpdater {
        if (!_exists[market]) revert MarketNotFound();
        if (emaSpan == 0) revert InvalidEmaSpan();
        _ptParams[market].emaSpan = emaSpan;
        emit EmaSpanSet(market, emaSpan);
    }

    function setEmaFreshnessSeconds(address market, uint64 emaFreshnessSeconds) external onlyUpdater {
        if (!_exists[market]) revert MarketNotFound();
        if (emaFreshnessSeconds == 0) revert InvalidEmaFreshness();
        _ptParams[market].emaFreshnessSeconds = emaFreshnessSeconds;
        emit EmaFreshnessSecondsSet(market, emaFreshnessSeconds);
    }

    /// @notice Set the deviation threshold for discount-rate update gating.
    /// @param market PT market address
    /// @param thresholdBps Deviation threshold in basis points (e.g., 30 = 0.30%)
    function setDeviationThresholdBps(address market, uint64 thresholdBps) external onlyUpdater {
        if (!_exists[market]) revert MarketNotFound();
        if (thresholdBps > MAX_BPS) revert BpsTooHigh(thresholdBps);
        _ptParams[market].thresholdBps = thresholdBps;
        emit DeviationThresholdBpsSet(market, thresholdBps);
    }

    /// @notice Set the K reference endpoint for risk-params p_star calculation.
    /// @param market PT market address
    /// @param kReferenceEndpoint K parameter scaled by K_FACTOR_SCALE (10000)
    function setKReferenceEndpoint(address market, uint64 kReferenceEndpoint) external onlyUpdater {
        if (!_exists[market]) revert MarketNotFound();
        if (kReferenceEndpoint == 0) revert InvalidKReferenceEndpoint();
        _ptParams[market].kReferenceEndpoint = kReferenceEndpoint;
        emit KReferenceEndpointSet(market, kReferenceEndpoint);
    }

    function setEmodeCategoryIds(address market, uint16[] calldata ids) external onlyUpdater {
        if (!_exists[market]) revert MarketNotFound();
        if (ids.length == 0) revert EmptyEmodeCategoryIds();
        _ptParams[market].emodeCategoryIds = ids;
        emit EmodeCategoryIdsSet(market, ids);
    }

    function deleteMarket(address market) external onlyUpdater {
        if (!_exists[market]) revert MarketNotFound();
        delete _ptParams[market];
        _exists[market] = false;
        emit MarketDeleted(market);
    }

    // ============================================================================================
    // Views
    // ============================================================================================

    function getPtMarketParams(address market) external view returns (PtMarketParams memory) {
        if (!_exists[market]) revert MarketNotFound();
        return _ptParams[market];
    }

    function marketExists(address market) external view returns (bool) {
        return _exists[market];
    }

    function getEmodeCategoryIds(address market) external view returns (uint16[] memory) {
        if (!_exists[market]) revert MarketNotFound();
        return _ptParams[market].emodeCategoryIds;
    }

    // ============================================================================================
    // Internal
    // ============================================================================================

    function _validateParams(PtMarketParams calldata p) internal pure {
        _validateTiming(p);
        _validateBps(p);
        if (p.emodeCategoryIds.length == 0) revert EmptyEmodeCategoryIds();
    }

    function _validateTiming(PtMarketParams calldata p) internal pure {
        if (p.emaSpan == 0) revert InvalidEmaSpan();
        if (p.emaFreshnessSeconds == 0) revert InvalidEmaFreshness();
        if (p.kReferenceEndpoint == 0) revert InvalidKReferenceEndpoint();
    }

    function _validateBps(PtMarketParams calldata p) internal pure {
        if (p.thresholdBps > MAX_BPS) revert BpsTooHigh(p.thresholdBps);
    }
}

// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { Ownable, Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { ICapsParameterRegistry } from "./interfaces/ICapsParameterRegistry.sol";
import { ICapsRangeValidationModule } from "./interfaces/ICapsRangeValidationModule.sol";

/// @title CapsParameterRegistry
/// @notice Parameters of the offchain rate limiter workflow: the market list, the work list per market, the max
///         base fee per market, and triggerBps, the raise margin and the `enabled` switch per (market, asset, kind)
///         with a market-wide default. Nothing onchain reads this contract for a cap decision: the RVM has no
///         pointer to it, and the hold lives in the RVM.
/// @dev Access model of PTParameterRegistry: `Ownable2Step` owner (LlamaRisk Safe) appoints the updater, and the
///      updater (Risk Council Safe at deploy) writes every parameter. `kind` uses the RVM
///      numbering (0 = BORROW, 1 = SUPPLY). Any non-zero asset address can be added.
///      The RVM interface is imported for the ABI of the RVM reads in `getReservesRaiseData`, which reads the
///      market's `MarketParams.rvm` (one RVM per Pool) through the keyed raise preview. The
///      registry does not read AgentHub. The asset-list mismatch check runs in the monitoring stack.
contract CapsParameterRegistry is ICapsParameterRegistry, Ownable2Step {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /// @notice Cap on any basis-point input (100% = 10_000 bps).
    uint16 public constant MAX_BPS = 10_000;
    /// @notice Highest valid `kind` (SUPPLY). Append-only with the RVM `CapKind`.
    uint8 public constant MAX_KIND = 1;

    /// @inheritdoc ICapsParameterRegistry
    address public updater;

    EnumerableSet.AddressSet private _markets;
    mapping(address market => MarketParams) private _marketParams;
    /// @dev Work list per market. Each item packs (asset, kind) as `uint256(uint160(asset)) << 8 | kind`.
    mapping(address market => EnumerableSet.Bytes32Set) private _reserves;
    mapping(address market => mapping(address asset => mapping(uint8 kind => ReserveOverride))) private _overrides;

    modifier onlyUpdater() {
        if (msg.sender != updater) revert OnlyUpdater();
        _;
    }

    /// @param owner_ registry owner (LlamaRisk Safe), `Ownable2Step`
    /// @param updater_ parameter writer (Risk Council Safe at deploy)
    constructor(address owner_, address updater_) Ownable(owner_) {
        if (updater_ == address(0)) revert ZeroAddress();
        updater = updater_;
        emit UpdaterChanged(address(0), updater_);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // OWNER
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc ICapsParameterRegistry
    function setUpdater(address updater_) external onlyOwner {
        if (updater_ == address(0)) revert ZeroAddress();
        address previous = updater;
        updater = updater_;
        emit UpdaterChanged(previous, updater_);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UPDATER: MARKETS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc ICapsParameterRegistry
    function addMarket(address market, MarketParams calldata params) external onlyUpdater {
        if (market == address(0)) revert ZeroAddress();
        _validateMarketParams(market, params);
        if (!_markets.add(market)) revert MarketAlreadyExists(market);
        _marketParams[market] = params;
        emit MarketAdded(market, params);
    }

    /// @inheritdoc ICapsParameterRegistry
    function setMarketParams(address market, MarketParams calldata params) external onlyUpdater {
        _requireMarket(market);
        _validateMarketParams(market, params);
        _marketParams[market] = params;
        emit MarketParamsSet(market, params);
    }

    /// @inheritdoc ICapsParameterRegistry
    function removeMarket(address market) external onlyUpdater {
        _requireMarket(market);
        if (_reserves[market].length() != 0) revert MarketNotEmpty(market);
        _markets.remove(market);
        delete _marketParams[market];
        emit MarketRemoved(market);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UPDATER: WORK LIST
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc ICapsParameterRegistry
    function addReserve(
        address market,
        address asset,
        uint8 kind,
        ReserveOverride calldata params
    )
        external
        onlyUpdater
    {
        // A zero asset is never an Aave
        // reserve, so it is rejected with the existing ZeroAddress error.
        if (asset == address(0)) revert ZeroAddress();
        _requireMarket(market);
        _validateKind(kind);
        _validateOverride(params);
        if (!_reserves[market].add(_packKey(asset, kind))) revert ReserveAlreadyListed(market, asset, kind);
        _overrides[market][asset][kind] = params;
        emit ReserveAdded(market, asset, kind, params);
    }

    /// @inheritdoc ICapsParameterRegistry
    function setReserveOverride(
        address market,
        address asset,
        uint8 kind,
        ReserveOverride calldata params
    )
        external
        onlyUpdater
    {
        _requireKey(market, asset, kind);
        _validateOverride(params);
        _overrides[market][asset][kind] = params;
        emit ReserveOverrideSet(market, asset, kind, params);
    }

    /// @inheritdoc ICapsParameterRegistry
    function setEnabled(address market, address asset, uint8 kind, EnabledOverride enabled) external onlyUpdater {
        _requireKey(market, asset, kind);
        _overrides[market][asset][kind].enabled = enabled;
        emit EnabledSet(market, asset, kind, enabled);
    }

    /// @inheritdoc ICapsParameterRegistry
    function removeReserve(address market, address asset, uint8 kind) external onlyUpdater {
        _requireKey(market, asset, kind);
        _reserves[market].remove(_packKey(asset, kind));
        delete _overrides[market][asset][kind];
        emit ReserveRemoved(market, asset, kind);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GETTERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc ICapsParameterRegistry
    function getMarkets() external view returns (address[] memory) {
        return _markets.values();
    }

    /// @inheritdoc ICapsParameterRegistry
    /// @dev Reverts MarketNotFound for an unknown market, so a
    ///      reader cannot mistake a missing market for one with the gas gate off and every default at 0.
    function getMarketParams(address market) external view returns (MarketParams memory) {
        _requireMarket(market);
        return _marketParams[market];
    }

    /// @inheritdoc ICapsParameterRegistry
    /// @dev Reverts MarketNotFound for an unknown market, as getMarketParams.
    function getReservesList(address market) public view returns (ReserveKey[] memory keys) {
        _requireMarket(market);
        EnumerableSet.Bytes32Set storage set = _reserves[market];
        uint256 keyCount = set.length();
        keys = new ReserveKey[](keyCount);
        for (uint256 i = 0; i < keyCount; i++) {
            (keys[i].asset, keys[i].kind) = _unpackKey(set.at(i));
        }
    }

    /// @inheritdoc ICapsParameterRegistry
    /// @dev Reverts MarketNotFound for an unknown market, as getReservesList. Two passes: count, then fill.
    function getReservesListByKind(address market, uint8 kind) external view returns (ReserveKey[] memory keys) {
        _requireMarket(market);
        _validateKind(kind);
        EnumerableSet.Bytes32Set storage set = _reserves[market];
        uint256 keyCount = set.length();
        uint256 count;
        for (uint256 i = 0; i < keyCount; i++) {
            if (uint8(uint256(set.at(i))) == kind) count++;
        }
        keys = new ReserveKey[](count);
        uint256 writeIndex;
        for (uint256 i = 0; i < keyCount; i++) {
            bytes32 key = set.at(i);
            if (uint8(uint256(key)) == kind) {
                (keys[writeIndex].asset, keys[writeIndex].kind) = _unpackKey(key);
                writeIndex++;
            }
        }
    }

    /// @inheritdoc ICapsParameterRegistry
    /// @dev All zero (every field "use the market default") for a key that is not listed.
    function getReserveOverride(
        address market,
        address asset,
        uint8 kind
    )
        external
        view
        returns (ReserveOverride memory)
    {
        return _overrides[market][asset][kind];
    }

    /// @inheritdoc ICapsParameterRegistry
    function getEffectiveParams(
        address market,
        address asset,
        uint8 kind
    )
        external
        view
        returns (WorkflowParams memory)
    {
        _requireKey(market, asset, kind);
        return _effectiveParams(market, asset, kind);
    }

    /// @inheritdoc ICapsParameterRegistry
    function isListed(address market, address asset, uint8 kind) public view returns (bool) {
        return _reserves[market].contains(_packKey(asset, kind));
    }

    /// @inheritdoc ICapsParameterRegistry
    /// @dev An unknown market has no stored params, so its RVM reads as 0 and every row has `found` false.
    function getReservesRaiseData(
        address market,
        uint8 kind,
        address[] calldata assets
    )
        external
        view
        returns (ReserveRaiseData[] memory rows)
    {
        rows = new ReserveRaiseData[](assets.length);
        address rvm_ = _marketParams[market].rvm;
        // kind is checked before the enum conversion, so an invalid kind gives `found` false on every row.
        bool readable = rvm_ != address(0) && kind <= MAX_KIND;
        for (uint256 i = 0; i < assets.length; i++) {
            rows[i].asset = assets[i];
            if (!readable || !isListed(market, assets[i], kind)) continue;
            _fillRaiseRow(rows[i], ICapsRangeValidationModule(rvm_), market, kind);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Each override field, else the market default. The caller checks that the key is listed.
    function _effectiveParams(
        address market,
        address asset,
        uint8 kind
    )
        internal
        view
        returns (WorkflowParams memory params)
    {
        WorkflowParams memory defaults = _marketParams[market].defaultParams;
        ReserveOverride memory reserveOverride = _overrides[market][asset][kind];

        if (reserveOverride.enabled == EnabledOverride.INHERIT) params.enabled = defaults.enabled;
        else params.enabled = reserveOverride.enabled == EnabledOverride.ON;
        params.triggerBps = reserveOverride.triggerBps != 0 ? reserveOverride.triggerBps : defaults.triggerBps;
        params.marginBps = reserveOverride.marginBps != 0 ? reserveOverride.marginBps : defaults.marginBps;
        params.minMarginTokens =
            reserveOverride.minMarginTokens != 0 ? reserveOverride.minMarginTokens : defaults.minMarginTokens;
    }

    /// @dev Fills one listed row of getReservesRaiseData with two RVM reads keyed by (asset, kind):
    ///      `getReserveState` and `previewRaise`. The market's RVM serves that market's Pool. Leaves `found`
    ///      false if the state read reverts, which covers a key with no rate limit config.
    function _fillRaiseRow(
        ReserveRaiseData memory row,
        ICapsRangeValidationModule rvm,
        address market,
        uint8 kind
    )
        internal
        view
    {
        ICapsRangeValidationModule.CapKind capKind = ICapsRangeValidationModule.CapKind(kind);
        try rvm.getReserveState(row.asset, capKind) returns (
            ICapsRangeValidationModule.ReserveState memory reserveState
        ) {
            row.cap = reserveState.cap;
            row.usage = reserveState.usage;
            row.supplyBound = reserveState.supplyBound;
            row.headroomTarget = reserveState.headroomTarget;
            row.raiseBlocked = reserveState.raiseBlocked;
            row.maxCap = reserveState.maxCap;
        } catch {
            return;
        }
        row.found = true;
        row.params = _effectiveParams(market, row.asset, kind);
        (row.allowed,, row.newCap) = rvm.previewRaise(row.asset, capKind);
    }

    function _requireMarket(address market) internal view {
        if (!_markets.contains(market)) revert MarketNotFound(market);
    }

    function _requireKey(address market, address asset, uint8 kind) internal view {
        _validateKind(kind);
        if (!isListed(market, asset, kind)) revert ReserveNotFound(market, asset, kind);
    }

    function _validateKind(uint8 kind) internal pure {
        if (kind > MAX_KIND) revert InvalidKind(kind);
    }

    /// @dev Market default: triggerBps in 1..10_000 (0 never triggers), marginBps <= 10_000.
    ///      A non-zero RVM must serve `market` (`POOL() == market`).
    function _validateMarketParams(address market, MarketParams calldata params) internal view {
        uint16 trigger = params.defaultParams.triggerBps;
        if (trigger == 0 || trigger > MAX_BPS) revert InvalidBps(trigger);
        if (params.defaultParams.marginBps > MAX_BPS) revert InvalidBps(params.defaultParams.marginBps);
        if (params.rvm != address(0) && ICapsRangeValidationModule(params.rvm).POOL() != market) {
            revert InvalidRvm(params.rvm);
        }
    }

    /// @dev Override: 0 means "use the market default", so only the upper bound applies.
    function _validateOverride(ReserveOverride calldata params) internal pure {
        if (params.triggerBps > MAX_BPS) revert InvalidBps(params.triggerBps);
        if (params.marginBps > MAX_BPS) revert InvalidBps(params.marginBps);
    }

    function _packKey(address asset, uint8 kind) internal pure returns (bytes32) {
        return bytes32((uint256(uint160(asset)) << 8) | kind);
    }

    function _unpackKey(bytes32 key) internal pure returns (address asset, uint8 kind) {
        asset = address(uint160(uint256(key) >> 8));
        kind = uint8(uint256(key));
    }
}

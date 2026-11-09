// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {
    IAaveV3ConfigEngine as IEngine
} from "aave-v3-origin/src/contracts/extensions/v3-config-engine/IAaveV3ConfigEngine.sol";
import { EngineFlags } from "aave-v3-origin/src/contracts/extensions/v3-config-engine/EngineFlags.sol";
import { MockPoolV3 } from "./MockPoolV3.sol";

/// @title MockRiskSteward
/// @notice Stand-in for Aave's `RiskSteward.updateCaps` (aave-v3-risk-stewards RiskSteward.sol:81), for the
///         CapsBorrowForwarder tests. Same behaviour on the points the forwarder depends on:
///         - `onlyRiskCouncil`: reverts `InvalidCaller` unless `msg.sender == RISK_COUNCIL` (line 55-58).
///         - Validates every update before any write (`_validateCapsUpdate`, line 181), then sets the
///           timelocks and writes the caps (`_updateCaps`, line 508).
///         - A restricted asset reverts `AssetIsRestricted` (line 187), checked before the zero check.
///         - A cap of 0 reverts `InvalidUpdateToZero` (line 188).
///         - `KEEP_CURRENT` skips the check and the debounce (line 490).
///         - Debounce per parameter: reverts `DebounceNotRespected` if `block.timestamp - lastUpdated < minDelay`
///           (line 492-493). Default minDelay is 36 h (129,600 s) for both caps.
///         - Range per parameter, relative: reverts `UpdateNotInRange` if `|to - from| > maxPercentChange * from
///           / 10_000` (line 693-709). Default 100% for both caps.
///         It writes the cap on the MockPoolV3 (`setBorrowCap`, `setSupplyCap`), not through a config engine.
contract MockRiskSteward {
    error InvalidCaller();
    error DebounceNotRespected();
    error UpdateNotInRange();
    error InvalidUpdateToZero();
    error NoZeroUpdates();
    error AssetIsRestricted();

    /// @dev Same shape as IRiskSteward.RiskParamConfig.
    struct RiskParamConfig {
        uint40 minDelay;
        uint256 maxPercentChange;
    }

    uint256 internal constant BPS_MAX = 10_000;

    address public immutable RISK_COUNCIL;
    MockPoolV3 public immutable POOL;

    RiskParamConfig public supplyCapConfig = RiskParamConfig({ minDelay: 36 hours, maxPercentChange: 10_000 });
    RiskParamConfig public borrowCapConfig = RiskParamConfig({ minDelay: 36 hours, maxPercentChange: 10_000 });

    mapping(address asset => uint40) public borrowCapLastUpdated;
    mapping(address asset => uint40) public supplyCapLastUpdated;
    mapping(address asset => bool) public isAddressRestricted;

    /// @notice Last call arguments, for assertions on what the forwarder sent.
    uint256 public updateCapsCalls;
    address public lastAsset;
    uint256 public lastSupplyCap;
    uint256 public lastBorrowCap;

    constructor(address riskCouncil, MockPoolV3 pool) {
        RISK_COUNCIL = riskCouncil;
        POOL = pool;
    }

    /// @notice Sets the same minDelay and maxPercentChange on both caps.
    function setLimits(uint40 minDelay_, uint256 maxPercentChange_) external {
        supplyCapConfig = RiskParamConfig(minDelay_, maxPercentChange_);
        borrowCapConfig = RiskParamConfig(minDelay_, maxPercentChange_);
    }

    function setCapConfig(RiskParamConfig calldata supplyCap, RiskParamConfig calldata borrowCap) external {
        supplyCapConfig = supplyCap;
        borrowCapConfig = borrowCap;
    }

    function setAddressRestricted(address asset, bool isRestricted) external {
        isAddressRestricted[asset] = isRestricted;
    }

    function updateCaps(IEngine.CapsUpdate[] calldata capsUpdate) external {
        if (msg.sender != RISK_COUNCIL) revert InvalidCaller();
        if (capsUpdate.length == 0) revert NoZeroUpdates();

        for (uint256 i = 0; i < capsUpdate.length; i++) {
            address asset = capsUpdate[i].asset;
            if (isAddressRestricted[asset]) revert AssetIsRestricted();
            if (capsUpdate[i].supplyCap == 0 || capsUpdate[i].borrowCap == 0) revert InvalidUpdateToZero();

            (uint256 currentBorrowCap, uint256 currentSupplyCap) = POOL.getReserveCaps(asset);
            _validate(currentSupplyCap, capsUpdate[i].supplyCap, supplyCapLastUpdated[asset], supplyCapConfig);
            _validate(currentBorrowCap, capsUpdate[i].borrowCap, borrowCapLastUpdated[asset], borrowCapConfig);
        }

        for (uint256 i = 0; i < capsUpdate.length; i++) {
            address asset = capsUpdate[i].asset;
            uint256 supplyCap = capsUpdate[i].supplyCap;
            uint256 borrowCap = capsUpdate[i].borrowCap;
            if (supplyCap != EngineFlags.KEEP_CURRENT) {
                supplyCapLastUpdated[asset] = uint40(block.timestamp);
                POOL.setSupplyCap(asset, supplyCap);
            }
            if (borrowCap != EngineFlags.KEEP_CURRENT) {
                borrowCapLastUpdated[asset] = uint40(block.timestamp);
                POOL.setBorrowCap(asset, borrowCap);
            }

            updateCapsCalls++;
            lastAsset = asset;
            lastSupplyCap = supplyCap;
            lastBorrowCap = borrowCap;
        }
    }

    function _validate(uint256 from, uint256 to, uint40 lastUpdated, RiskParamConfig memory c) internal view {
        if (to == EngineFlags.KEEP_CURRENT) return;
        if (block.timestamp - lastUpdated < c.minDelay) revert DebounceNotRespected();
        uint256 diff = from > to ? from - to : to - from;
        if (diff > c.maxPercentChange * from / BPS_MAX) revert UpdateNotInRange();
    }
}

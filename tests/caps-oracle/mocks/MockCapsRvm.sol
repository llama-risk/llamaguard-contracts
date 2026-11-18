// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ICapsRangeValidationModule } from "../../../src/caps-oracle/interfaces/ICapsRangeValidationModule.sol";

/// @title MockCapsRvm
/// @notice Minimal RVM for testing CapsReducerOracle in isolation. It implements only the one read that the
///         oracle makes (the keyed `previewCut(asset, kind)`) with settable results, plus a stored entry for
///         the registry independence tests, a settable `POOL()` for the registry RVM check, and settable update
///         type hashes (default: the Core borrow and supply update types) that the oracle reads at construction.
contract MockCapsRvm {
    address public POOL;

    bytes32 public BORROW_UPDATE_TYPE_HASH = keccak256("BorrowCapUpdate_Core");
    bytes32 public SUPPLY_UPDATE_TYPE_HASH = keccak256("SupplyCapUpdate_Core");

    struct CutResult {
        bool due;
        uint256 currentCap;
        uint256 newCap;
    }

    mapping(address asset => mapping(ICapsRangeValidationModule.CapKind kind => CutResult)) internal _cuts;

    mapping(
        address asset => mapping(ICapsRangeValidationModule.CapKind kind => ICapsRangeValidationModule.RateLimitConfig)
    ) internal _rateLimitConfigs;

    function setPool(address pool) external {
        POOL = pool;
    }

    function setUpdateTypeHashes(bytes32 borrowHash, bytes32 supplyHash) external {
        BORROW_UPDATE_TYPE_HASH = borrowHash;
        SUPPLY_UPDATE_TYPE_HASH = supplyHash;
    }

    function setCut(
        address asset,
        ICapsRangeValidationModule.CapKind kind,
        bool due,
        uint256 currentCap,
        uint256 newCap
    )
        external
    {
        _cuts[asset][kind] = CutResult(due, currentCap, newCap);
    }

    function previewCut(
        address asset,
        ICapsRangeValidationModule.CapKind kind
    )
        external
        view
        returns (bool due, uint256 currentCap, uint256 newCap)
    {
        CutResult memory c = _cuts[asset][kind];
        return (c.due, c.currentCap, c.newCap);
    }

    function setRateLimitConfig(
        address asset,
        ICapsRangeValidationModule.CapKind kind,
        ICapsRangeValidationModule.RateLimitConfig calldata rateLimitConfig
    )
        external
    {
        _rateLimitConfigs[asset][kind] = rateLimitConfig;
    }

    /// @dev The stored entry as a KeyState, with no hold and no increase time.
    function getKeyState(
        address asset,
        ICapsRangeValidationModule.CapKind kind
    )
        external
        view
        returns (ICapsRangeValidationModule.KeyState memory s)
    {
        ICapsRangeValidationModule.RateLimitConfig memory c = _rateLimitConfigs[asset][kind];
        s.maxCap = c.maxCap;
        s.maxHeadroom = c.maxHeadroom;
        s.alphaBps = c.alphaBps;
        s.cutBandBps = c.cutBandBps;
    }

    function getRateLimitConfig(
        address asset,
        ICapsRangeValidationModule.CapKind kind
    )
        external
        view
        returns (ICapsRangeValidationModule.RateLimitConfig memory)
    {
        return _rateLimitConfigs[asset][kind];
    }
}

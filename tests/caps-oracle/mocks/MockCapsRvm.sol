// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ICapsRangeValidationModule } from "../../../src/caps-oracle/interfaces/ICapsRangeValidationModule.sol";

/// @title MockCapsRvm
/// @notice Minimal RVM for testing CapsReducerOracle in isolation. It implements only the one read that the
///         oracle makes (the keyed `previewCut(asset, kind)`) with settable results, plus a stored entry for
///         the registry independence tests and a settable `POOL()` for the registry RVM check.
contract MockCapsRvm {
    address public POOL;

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

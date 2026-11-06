// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

/// @title IAaveCapAgent
/// @notice The subset of the Aave risk agents (BaseAaveAgent) the RVM reads.
/// @dev The reads of an Aave cap agent the RVM makes at registration.
interface IAaveCapAgent {
    function POOL() external view returns (address);

    function RANGE_VALIDATION_MODULE() external view returns (address);
}

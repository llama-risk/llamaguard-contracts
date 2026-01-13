// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IPoolConfigurator
 * @notice Minimal interface for Aave V3 PoolConfigurator freeze functionality
 */
interface IPoolConfigurator {
    /**
     * @notice Freeze or unfreeze a reserve. A frozen reserve doesn't allow any new supply, borrow
     * or rate swap but allows repayments, liquidations, rate rebalances and withdrawals.
     * @param asset The address of the underlying asset of the reserve
     * @param freeze True if the reserve needs to be frozen, false otherwise
     */
    function setReserveFreeze(address asset, bool freeze) external;
}

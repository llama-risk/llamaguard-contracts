// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IPoolConfigurator } from "../../src/horizon-response/interfaces/IPoolConfigurator.sol";

/**
 * @title MockPoolConfigurator
 * @notice Mock implementation of IPoolConfigurator for testing HorizonFreezeAgent
 */
contract MockPoolConfigurator is IPoolConfigurator {
    /// @notice Mapping of asset address to frozen state
    mapping(address => bool) public frozenReserves;

    /// @notice Counter for tracking number of freeze calls
    uint256 public freezeCallCount;

    /// @notice Last asset that was frozen/unfrozen
    address public lastFreezeAsset;

    /// @notice Last freeze state that was set
    bool public lastFreezeState;

    /// @notice Event emitted when setReserveFreeze is called
    event ReserveFreezeSet(address indexed asset, bool freeze);

    /// @inheritdoc IPoolConfigurator
    function setReserveFreeze(address asset, bool freeze) external override {
        frozenReserves[asset] = freeze;
        lastFreezeAsset = asset;
        lastFreezeState = freeze;
        freezeCallCount++;

        emit ReserveFreezeSet(asset, freeze);
    }

    /// @notice Check if a reserve is frozen
    function isFrozen(address asset) external view returns (bool) {
        return frozenReserves[asset];
    }

    /// @notice Reset the mock state for clean testing
    function reset() external {
        freezeCallCount = 0;
        lastFreezeAsset = address(0);
        lastFreezeState = false;
    }
}

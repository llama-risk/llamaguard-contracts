// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IPoolDataProvider } from "../../src/horizon-response/interfaces/IPoolDataProvider.sol";

/**
 * @title MockPoolDataProvider
 * @notice Mock implementation of IPoolDataProvider for testing HorizonFreezeAgent
 */
contract MockPoolDataProvider is IPoolDataProvider {
    /// @notice Mapping of asset address to frozen state
    mapping(address => bool) public frozenReserves;

    /// @inheritdoc IPoolDataProvider
    function getReserveConfigurationData(address asset)
        external
        view
        override
        returns (
            uint256 decimals,
            uint256 ltv,
            uint256 liquidationThreshold,
            uint256 liquidationBonus,
            uint256 reserveFactor,
            bool usageAsCollateralEnabled,
            bool borrowingEnabled,
            bool stableBorrowRateEnabled,
            bool isActive,
            bool isFrozen
        )
    {
        bool frozen = frozenReserves[asset];
        // Return defaults with isFrozen from our mapping
        decimals = 18;
        ltv = 0;
        liquidationThreshold = 0;
        liquidationBonus = 0;
        reserveFactor = 0;
        usageAsCollateralEnabled = false;
        borrowingEnabled = false;
        stableBorrowRateEnabled = false;
        isActive = true;
        isFrozen = frozen;
    }

    /// @notice Set the frozen state for an asset (for testing)
    /// @param asset The asset address
    /// @param frozen Whether the asset should be frozen
    function setFrozen(address asset, bool frozen) external {
        frozenReserves[asset] = frozen;
    }
}

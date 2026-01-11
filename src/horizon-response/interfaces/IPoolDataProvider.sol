// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title IPoolDataProvider
 * @notice Minimal interface for Aave V3 PoolDataProvider to query reserve configuration
 */
interface IPoolDataProvider {
    /**
     * @notice Returns the configuration data of the reserve
     * @param asset The address of the underlying asset
     * @return decimals The decimals of the asset
     * @return ltv The loan to value
     * @return liquidationThreshold The liquidation threshold
     * @return liquidationBonus The liquidation bonus
     * @return reserveFactor The reserve factor
     * @return usageAsCollateralEnabled Whether the asset is used as collateral
     * @return borrowingEnabled Whether borrowing is enabled
     * @return stableBorrowRateEnabled Whether stable borrow rate is enabled
     * @return isActive Whether the reserve is active
     * @return isFrozen Whether the reserve is frozen
     */
    function getReserveConfigurationData(address asset)
        external
        view
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
        );
}

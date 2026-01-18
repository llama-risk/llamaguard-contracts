// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { DataTypes } from "aave-v3-horizon/src/contracts/protocol/libraries/types/DataTypes.sol";
import {
    ReserveConfiguration
} from "aave-v3-horizon/src/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";

/**
 * @title MockPool
 * @notice Mock implementation of IPool for testing HorizonFreezeAgent
 * @dev Implements getReservesList() and getConfiguration() for testing
 */
contract MockPool {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    address[] internal _reserves;
    mapping(address => DataTypes.ReserveConfigurationMap) internal _configurations;

    // ═══════════════════════════════════════════════════════════════════════════
    // IPool INTERFACE METHODS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Returns the list of the underlying assets of all the initialized reserves
     * @return The addresses of the underlying assets of the initialized reserves
     */
    function getReservesList() external view returns (address[] memory) {
        return _reserves;
    }

    /**
     * @notice Returns the configuration of the reserve
     * @param asset The address of the underlying asset of the reserve
     * @return The configuration of the reserve
     */
    function getConfiguration(address asset) external view returns (DataTypes.ReserveConfigurationMap memory) {
        return _configurations[asset];
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TEST HELPER METHODS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Add a reserve to the list
     * @param reserve The address of the reserve to add
     */
    function addReserve(address reserve) external {
        _reserves.push(reserve);
    }

    /**
     * @notice Set the entire reserves list
     * @param reserves The addresses of reserves to set
     */
    function setReservesList(address[] calldata reserves) external {
        delete _reserves;
        for (uint256 i = 0; i < reserves.length; i++) {
            _reserves.push(reserves[i]);
        }
    }

    /**
     * @notice Clear all reserves
     */
    function clearReserves() external {
        delete _reserves;
    }

    /**
     * @notice Get the count of reserves
     * @return The number of reserves
     */
    function getReservesCount() external view returns (uint256) {
        return _reserves.length;
    }

    /**
     * @notice Set the frozen status of a reserve
     * @param asset The address of the reserve
     * @param frozen Whether the reserve should be frozen
     */
    function setFrozen(address asset, bool frozen) external {
        // Read from storage into memory, modify, and write back
        DataTypes.ReserveConfigurationMap memory config = _configurations[asset];
        config.setFrozen(frozen);
        _configurations[asset] = config;
    }

    /**
     * @notice Check if a reserve is frozen
     * @param asset The address of the reserve
     * @return Whether the reserve is frozen
     */
    function isFrozen(address asset) external view returns (bool) {
        return _configurations[asset].getFrozen();
    }

    /**
     * @notice Set the full configuration for a reserve
     * @param asset The address of the reserve
     * @param config The configuration to set
     */
    function setConfiguration(address asset, DataTypes.ReserveConfigurationMap memory config) external {
        _configurations[asset] = config;
    }

    /**
     * @notice Reset the mock state
     */
    function reset() external {
        delete _reserves;
    }
}

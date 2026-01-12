// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BaseHorizonAgent } from "./BaseHorizonAgent.sol";
import { ILlamaGuardOracle } from "../../interfaces/ILlamaGuardOracle.sol";
import { IPoolConfigurator } from "../interfaces/IPoolConfigurator.sol";
import { DataTypes } from "aave-v3-origin/src/contracts/protocol/libraries/types/DataTypes.sol";
import {
    ReserveConfiguration
} from "aave-v3-origin/src/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title HorizonFreezeAgent
 * @notice Agent responsible for freezing markets in the Horizon protocol based on LlamaGuard oracle state
 * @dev Decodes additionalData as (int256 lowerBound, int256 upperBound, uint256 state)
 *      If state == 1, the reserve is frozen. Unfreezing requires manual multisig intervention.
 */
contract HorizonFreezeAgent is BaseHorizonAgent {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using Address for address;

    /// @notice State value indicating the reserve should be frozen
    uint256 public constant FROZEN_STATE = 1;

    /// @notice Emitted when a reserve freeze state is updated
    event ReserveFreezeUpdated(address indexed market, bool frozen, uint256 state);

    /// @notice Error thrown when validation fails during injection
    error ValidationFailed();

    /**
     * @param agentHub The address of the HorizonAgentHub
     * @param pool The address of the Aave V3 Pool contract
     */
    constructor(address agentHub, address pool) BaseHorizonAgent(agentHub, pool) { }

    /// @dev Overrides base inject to add re-validation before processing (defense-in-depth)
    function inject(
        uint256 agentId,
        bytes calldata agentContext,
        ILlamaGuardOracle.RiskParameterUpdate calldata update
    )
        external
        override
        onlyAgentHub
    {
        if (!_validateInternal(agentId, agentContext, update)) {
            revert ValidationFailed();
        }
        _processUpdate(agentId, agentContext, update);
    }

    /// @inheritdoc BaseHorizonAgent
    function _validateInternal(
        uint256,
        bytes calldata,
        ILlamaGuardOracle.RiskParameterUpdate memory update
    )
        internal
        view
        override
        returns (bool)
    {
        (,, uint256 state) = _decodeAdditionalData(update.additionalData);

        // Only allow freeze (state == 1), never unfreeze
        // Unfreezing requires manual multisig intervention
        if (state != FROZEN_STATE) {
            return false;
        }

        // Query current reserve config using POOL.getConfiguration()
        bool isFrozen = POOL.getConfiguration(update.market).getFrozen();

        // Only freeze if NOT already frozen
        return !isFrozen;
    }

    /// @inheritdoc BaseHorizonAgent
    function _processUpdate(
        uint256,
        bytes calldata agentContext,
        ILlamaGuardOracle.RiskParameterUpdate calldata update
    )
        internal
        override
    {
        // Decode pool configurator address from agent context
        address poolConfigurator = abi.decode(agentContext, (address));

        // Decode additionalData: (lowerBound, upperBound, state)
        (,, uint256 state) = _decodeAdditionalData(update.additionalData);

        // Determine freeze state: state == 1 means freeze
        bool shouldFreeze = state == FROZEN_STATE;

        // Execute freeze on the pool configurator using functionCall pattern
        poolConfigurator.functionCall(
            abi.encodeWithSelector(IPoolConfigurator.setReserveFreeze.selector, update.market, shouldFreeze)
        );

        emit ReserveFreezeUpdated(update.market, shouldFreeze, state);
    }

    /**
     * @notice Decodes the additionalData bytes into its components
     * @param additionalData ABI-encoded tuple (int256 lowerBound, int256 upperBound, uint256 state)
     * @return lowerBound The lower bound value
     * @return upperBound The upper bound value
     * @return state The state value (1 = frozen)
     */
    function _decodeAdditionalData(bytes memory additionalData)
        internal
        pure
        returns (int256 lowerBound, int256 upperBound, uint256 state)
    {
        (lowerBound, upperBound, state) = abi.decode(additionalData, (int256, int256, uint256));
    }
}

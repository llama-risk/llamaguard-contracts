// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BaseHorizonAgent } from "./BaseHorizonAgent.sol";
import { ILlamaGuardOracle } from "../../interfaces/ILlamaGuardOracle.sol";
import { IPoolConfigurator } from "../interfaces/IPoolConfigurator.sol";
import { IPoolDataProvider } from "../interfaces/IPoolDataProvider.sol";

/**
 * @title HorizonFreezeAgent
 * @notice Agent responsible for freezing markets in the Horizon protocol based on LlamaGuard oracle state
 * @dev Decodes additionalData as (int256 lowerBound, int256 upperBound, uint256 state)
 *      If state == 1, the reserve is frozen. Unfreezing requires manual multisig intervention.
 */
contract HorizonFreezeAgent is BaseHorizonAgent {
    /// @notice State value indicating the reserve should be frozen
    uint256 public constant FROZEN_STATE = 1;

    /// @notice Emitted when a reserve freeze state is updated
    event ReserveFreezeUpdated(address indexed market, bool frozen, uint256 state);

    /// @notice Error thrown when validation fails during injection
    error ValidationFailed();

    /**
     * @param agentHub The address of the HorizonAgentHub
     */
    constructor(address agentHub) BaseHorizonAgent(agentHub) { }

    /// @inheritdoc BaseHorizonAgent
    function validate(
        uint256,
        bytes calldata agentContext,
        ILlamaGuardOracle.RiskParameterUpdate calldata update
    )
        external
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

        // Decode poolDataProvider address from agentContext
        (, address poolDataProvider) = abi.decode(agentContext, (address, address));

        // Query current reserve config - isFrozen is the 10th return value
        (,,,,,,,,, bool isFrozen) = IPoolDataProvider(poolDataProvider).getReserveConfigurationData(update.market);

        // Only freeze if NOT already frozen
        return !isFrozen;
    }

    /// @inheritdoc BaseHorizonAgent
    function getMarkets(uint256) external pure override returns (address[] memory) {
        // Markets are determined by the oracle updates, return empty array
        return new address[](0);
    }

    /// @inheritdoc BaseHorizonAgent
    /// @dev Overrides base to add re-validation before processing (defense-in-depth)
    function inject(
        uint256 agentId,
        bytes calldata agentContext,
        ILlamaGuardOracle.RiskParameterUpdate calldata update
    )
        external
        override
        onlyAgentHub
    {
        if (!this.validate(agentId, agentContext, update)) {
            revert ValidationFailed();
        }
        _processUpdate(agentId, agentContext, update);
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
        // Decode pool configurator address from agent context (ignore poolDataProvider - used only in validate)
        (address poolConfigurator,) = abi.decode(agentContext, (address, address));

        // Decode additionalData: (lowerBound, upperBound, state)
        (,, uint256 state) = _decodeAdditionalData(update.additionalData);

        // Determine freeze state: state == 1 means freeze
        bool shouldFreeze = state == FROZEN_STATE;

        // Execute freeze on the pool configurator
        IPoolConfigurator(poolConfigurator).setReserveFreeze(update.market, shouldFreeze);

        emit ReserveFreezeUpdated(update.market, shouldFreeze, state);
    }

    /**
     * @notice Decodes the additionalData bytes into its components
     * @param additionalData ABI-encoded tuple (int256 lowerBound, int256 upperBound, uint256 state)
     * @return lowerBound The lower bound value
     * @return upperBound The upper bound value
     * @return state The state value (1 = frozen)
     */
    function _decodeAdditionalData(bytes calldata additionalData)
        internal
        pure
        returns (int256 lowerBound, int256 upperBound, uint256 state)
    {
        (lowerBound, upperBound, state) = abi.decode(additionalData, (int256, int256, uint256));
    }
}

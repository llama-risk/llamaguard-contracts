// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { BaseHorizonAgent } from "./BaseHorizonAgent.sol";
import { ILlamaGuardOracle } from "../../interfaces/ILlamaGuardOracle.sol";
import { IPoolConfigurator } from "../interfaces/IPoolConfigurator.sol";

/**
 * @title HorizonFreezeAgent
 * @notice Agent responsible for freezing markets in the Horizon protocol based on LlamaGuard oracle state
 * @dev Decodes additionalData as (int256 lowerBound, int256 upperBound, uint256 state, uint256 supply)
 *      If state == 1, the reserve is frozen; if state == 0, the reserve is unfrozen
 */
contract HorizonFreezeAgent is BaseHorizonAgent {
    /// @notice State value indicating the reserve should be frozen
    uint256 public constant FROZEN_STATE = 1;

    /// @notice Emitted when a reserve freeze state is updated
    event ReserveFreezeUpdated(address indexed market, bool frozen, uint256 state);

    /**
     * @param agentHub The address of the HorizonAgentHub
     */
    constructor(address agentHub) BaseHorizonAgent(agentHub) { }

    /// @inheritdoc BaseHorizonAgent
    function validate(
        uint256,
        bytes calldata,
        ILlamaGuardOracle.RiskParameterUpdate calldata update
    )
        external
        pure
        override
        returns (bool)
    {
        // Decode additionalData to extract state
        (,, uint256 state,) = _decodeAdditionalData(update.additionalData);

        // Only validate as true if state indicates a freeze action (state == 1)
        // or unfreeze action (state == 0)
        // For now, we accept both freeze and unfreeze states
        return state <= 1;
    }

    /// @inheritdoc BaseHorizonAgent
    function getMarkets(uint256) external pure override returns (address[] memory) {
        // Markets are determined by the oracle updates, return empty array
        return new address[](0);
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

        // Decode additionalData: (lowerBound, upperBound, state, supply)
        (,, uint256 state,) = _decodeAdditionalData(update.additionalData);

        // Determine freeze state: state == 1 means freeze, state == 0 means unfreeze
        bool shouldFreeze = state == FROZEN_STATE;

        // Execute freeze/unfreeze on the pool configurator
        IPoolConfigurator(poolConfigurator).setReserveFreeze(update.market, shouldFreeze);

        emit ReserveFreezeUpdated(update.market, shouldFreeze, state);
    }

    /**
     * @notice Decodes the additionalData bytes into its components
     * @param additionalData ABI-encoded tuple (int256 lowerBound, int256 upperBound, uint256 state, uint256 supply)
     * @return lowerBound The lower bound value
     * @return upperBound The upper bound value
     * @return state The state value (1 = frozen, 0 = unfrozen)
     * @return supply The supply value
     */
    function _decodeAdditionalData(bytes calldata additionalData)
        internal
        pure
        returns (int256 lowerBound, int256 upperBound, uint256 state, uint256 supply)
    {
        (lowerBound, upperBound, state, supply) = abi.decode(additionalData, (int256, int256, uint256, uint256));
    }
}

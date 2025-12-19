// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ILlamaGuardOracle } from "../../interfaces/ILlamaGuardOracle.sol";

/**
 * @title BaseHorizonAgent
 * @notice Abstract base contract for Horizon agents using ILlamaGuardOracle
 */
abstract contract BaseHorizonAgent {
    /// @notice The address of the AgentHub that can call this agent
    address public immutable AGENT_HUB;

    /// @notice Error thrown when caller is not the AgentHub
    error OnlyAgentHub(address caller);

    /**
     * @param agentHub The address of the HorizonAgentHub
     */
    constructor(address agentHub) {
        AGENT_HUB = agentHub;
    }

    modifier onlyAgentHub() {
        if (msg.sender != AGENT_HUB) revert OnlyAgentHub(msg.sender);
        _;
    }

    /**
     * @notice Method called by the AgentHub to inject updates from LlamaGuard oracle into the protocol
     * @param agentId The id of the agent for which to do injection
     * @param agentContext Contains custom config bytes data for the agent (e.g., pool configurator address)
     * @param update Risk parameter update to be injected
     */
    function inject(
        uint256 agentId,
        bytes calldata agentContext,
        ILlamaGuardOracle.RiskParameterUpdate calldata update
    )
        external
        virtual
        onlyAgentHub
    {
        _processUpdate(agentId, agentContext, update);
    }

    /**
     * @notice Method to perform agent-specific validation for a risk parameter update
     * @param agentId The id of the agent being validated
     * @param agentContext Contains custom config bytes data for the agent
     * @param update Risk parameter update to be validated
     * @return True if the update is valid for the specified agent
     */
    function validate(
        uint256 agentId,
        bytes calldata agentContext,
        ILlamaGuardOracle.RiskParameterUpdate calldata update
    )
        external
        view
        virtual
        returns (bool);

    /**
     * @notice Method to get all the market addresses to be used by the agent hub
     * @param agentId The id of the agent
     * @return The list of markets for the agent
     */
    function getMarkets(uint256 agentId) external view virtual returns (address[] memory);

    /**
     * @notice Processes injection of the risk parameter update for a specific agent
     * @param agentId The id of the agent for which to process injection
     * @param agentContext Contains custom config bytes data for the agent
     * @param update Risk parameter update to be injected
     */
    function _processUpdate(
        uint256 agentId,
        bytes calldata agentContext,
        ILlamaGuardOracle.RiskParameterUpdate calldata update
    )
        internal
        virtual;
}

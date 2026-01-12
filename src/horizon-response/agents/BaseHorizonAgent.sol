// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ILlamaGuardOracle } from "../../interfaces/ILlamaGuardOracle.sol";
import { IPool } from "aave-v3-origin/src/contracts/interfaces/IPool.sol";

/**
 * @title BaseHorizonAgent
 * @notice Abstract base contract for Horizon agents compatible with AgentHub
 * @dev Uses ILlamaGuardOracle.RiskParameterUpdate for risk parameter updates.
 *      The struct layout is designed to be ABI-compatible with the AgentHub interface.
 */
abstract contract BaseHorizonAgent {
    /// @notice The caller account is not the AgentHub contract
    error OnlyAgentHub(address account);

    /// @notice The address of the AgentHub that can call this agent
    address public immutable AGENT_HUB;

    /// @notice The Aave V3 Pool contract for reserve operations
    IPool public immutable POOL;

    /**
     * @param agentHub The address of the HorizonAgentHub
     * @param pool The address of the Aave V3 Pool contract
     */
    constructor(address agentHub, address pool) {
        AGENT_HUB = agentHub;
        POOL = IPool(pool);
    }

    modifier onlyAgentHub() {
        if (msg.sender != AGENT_HUB) revert OnlyAgentHub(msg.sender);
        _;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // AGENT INTERFACE
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Inject a risk parameter update into the protocol
     * @dev Called by AgentHub. ABI-compatible with IBaseAgent.inject()
     * @param agentId The id of the agent for which to do injection
     * @param agentContext Contains custom config bytes data for the agent
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
     * @notice Validate a risk parameter update
     * @dev Called by AgentHub. ABI-compatible with IBaseAgent.validate()
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
        returns (bool)
    {
        return _validateInternal(agentId, agentContext, update);
    }

    /**
     * @notice Get markets for this agent
     * @dev Called by AgentHub when isMarketsFromAgentEnabled is true.
     *      Returns all reserves from the Aave V3 Pool.
     * @return The list of markets for this agent
     */
    function getMarkets(uint256) external view virtual returns (address[] memory) {
        return POOL.getReservesList();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL INTERFACE
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Internal validation method to be implemented by inheriting contracts
     * @param agentId The id of the agent being validated
     * @param agentContext Contains custom config bytes data for the agent
     * @param update Risk parameter update to be validated
     * @return True if the update is valid for the specified agent
     */
    function _validateInternal(
        uint256 agentId,
        bytes calldata agentContext,
        ILlamaGuardOracle.RiskParameterUpdate memory update
    )
        internal
        view
        virtual
        returns (bool);

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

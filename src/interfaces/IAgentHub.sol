// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

/// @title IAgentHub
/// @notice Minimal local interface to the BGD `AgentHub` (chaos-agents). The router only needs
///         `check` to discover the current action set against freshly-published oracle updates
///         and `execute` to inject them; the full AgentHub configuration surface stays out of
///         the router build to avoid pulling chaos-agents' transitive deps.
/// @dev Struct + signatures match `node_modules/chaos-agents/src/interfaces/IAgentHub.sol`
///      (MIT-licensed). This file is a thin re-declaration; it carries no novel IP.
interface IAgentHub {
    struct ActionData {
        uint256 agentId;
        address[] markets;
    }

    function check(uint256[] memory agentIds) external view returns (bool shouldExecute, ActionData[] memory actions);

    function execute(ActionData[] memory actions) external;
}

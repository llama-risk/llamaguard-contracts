// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IRiskOracle } from "chaos-agents/contracts/dependencies/IRiskOracle.sol";

/// @title MockCutAgent
/// @notice Stand-in for AaveBorrowCapAgent behind a real AgentHub, for the CapsReducerOracle tests. It accepts
///         every update in `validate` and records each `inject`, so a test can count cuts per block (CAP-ST-16).
/// @dev Only the selectors AgentHub calls on an agent (`validate`, `inject`, `getMarkets`, `AGENT_HUB`).
contract MockCutAgent {
    address public immutable AGENT_HUB;

    uint256 public injectCount;
    uint256 public lastNewCap;
    uint256 public lastUpdateId;

    constructor(address agentHub) {
        AGENT_HUB = agentHub;
    }

    function validate(uint256, bytes calldata, IRiskOracle.RiskParameterUpdate calldata) external pure returns (bool) {
        return true;
    }

    function inject(uint256, bytes calldata, IRiskOracle.RiskParameterUpdate calldata update) external {
        require(msg.sender == AGENT_HUB, "only hub");
        injectCount++;
        lastNewCap = abi.decode(update.newValue, (uint256));
        lastUpdateId = update.updateId;
    }

    function getMarkets(uint256) external pure returns (address[] memory) {
        return new address[](0);
    }
}

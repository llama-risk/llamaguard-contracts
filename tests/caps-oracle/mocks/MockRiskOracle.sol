// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IRiskOracle } from "chaos-agents/contracts/dependencies/IRiskOracle.sol";

/// @title MockRiskOracle
/// @notice Risk oracle stand-in for the raise agentIds: the rate limiter workflow publishes a raise, and
///         AgentHub reads the latest one per (updateType, market). Reverts when no update exists, as the real
///         Chaos risk oracle does (AgentHub skips the market).
/// @dev `publish` is open: tests stand in for the CRE workflow. Each update gets the next updateId and the
///      current timestamp.
contract MockRiskOracle {
    error NoUpdate(string updateType, address market);

    uint256 public updateCounter;
    mapping(bytes32 key => IRiskOracle.RiskParameterUpdate) internal _latest;

    function publish(
        string calldata updateType,
        address market,
        uint256 newValue,
        uint256 previousValue
    )
        external
        returns (uint256 updateId)
    {
        updateId = ++updateCounter;
        IRiskOracle.RiskParameterUpdate storage u = _latest[keccak256(abi.encode(updateType, market))];
        u.timestamp = block.timestamp;
        u.newValue = abi.encode(newValue);
        u.previousValue = abi.encode(previousValue);
        u.updateType = updateType;
        u.updateId = updateId;
        u.market = market;
    }

    function getLatestUpdateByParameterAndMarket(
        string calldata updateType,
        address market
    )
        external
        view
        returns (IRiskOracle.RiskParameterUpdate memory u)
    {
        u = _latest[keccak256(abi.encode(updateType, market))];
        if (u.updateId == 0) revert NoUpdate(updateType, market);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { HorizonFreezeAgent } from "../../src/horizon-response/agents/HorizonFreezeAgent.sol";
import { BaseHorizonAgent } from "../../src/horizon-response/agents/BaseHorizonAgent.sol";
import { ILlamaGuardOracle } from "../../src/interfaces/ILlamaGuardOracle.sol";
import { MockPoolConfigurator } from "../mocks/MockPoolConfigurator.sol";
import { MockPool } from "../mocks/MockPool.sol";

/// @title HorizonFreezeAgentTestBase
/// @notice Shared base contract for HorizonFreezeAgent unit tests
abstract contract HorizonFreezeAgentTestBase is Test {
    HorizonFreezeAgent internal agent;
    MockPoolConfigurator internal poolConfigurator;
    MockPool internal pool;

    address internal agentHub;
    address internal market;
    address internal nonAgentHub;

    event ReserveFreezeUpdated(address indexed market, bool frozen, uint256 state);

    string internal constant UPDATE_TYPE_STR = "boundedNAV";

    function setUp() public virtual {
        agentHub = makeAddr("agentHub");
        market = makeAddr("market");
        nonAgentHub = makeAddr("nonAgentHub");

        pool = new MockPool();
        poolConfigurator = new MockPoolConfigurator();
        agent = new HorizonFreezeAgent(agentHub, address(pool));

        // Add market to pool reserves
        pool.addReserve(market);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Encode additionalData as (lowerBound, upperBound, state)
    function _encodeAdditionalData(
        int256 lowerBound,
        int256 upperBound,
        uint256 state
    )
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(lowerBound, upperBound, state);
    }

    /// @dev Create a RiskParameterUpdate struct for testing
    function _createUpdate(
        address marketAddr,
        uint256 state,
        int256 lowerBound,
        int256 upperBound
    )
        internal
        view
        returns (ILlamaGuardOracle.RiskParameterUpdate memory)
    {
        return ILlamaGuardOracle.RiskParameterUpdate({
            timestamp: block.timestamp,
            newValue: abi.encode(int256(100)), // price
            referenceId: "test-ref",
            previousValue: "",
            updateType: UPDATE_TYPE_STR,
            updateId: 1,
            market: marketAddr,
            additionalData: _encodeAdditionalData(lowerBound, upperBound, state)
        });
    }

    /// @dev Encode agent context with pool configurator address
    function _encodeAgentContext(address poolConfiguratorAddr) internal pure returns (bytes memory) {
        return abi.encode(poolConfiguratorAddr);
    }
}

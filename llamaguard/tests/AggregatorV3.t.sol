// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { AggregatorV3 } from "../src/AggregatorV3.sol";

/// @notice Test helper contract that exposes internal methods for testing
contract TestableAggregatorV3 is AggregatorV3 {
    constructor(
        uint8 decimals_,
        string memory description_,
        uint256 version_
    )
        AggregatorV3(decimals_, description_, version_)
    { }

    /// @dev Expose internal method for testing
    function updateLatestRoundDataPublic(int256 answer) external {
        updateLatestRoundData(answer);
    }
}

contract AggregatorV3Test is Test {
    TestableAggregatorV3 internal aggregator;

    function setUp() public {
        aggregator = new TestableAggregatorV3(8, "Mock Feed", 1);
    }

    function testInitialValues() public view {
        assertEq(aggregator.decimals(), 8);
        assertEq(aggregator.description(), "Mock Feed");
        assertEq(aggregator.version(), 1);

        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            aggregator.latestRoundData();
        assertEq(roundId, 1);
        assertEq(answer, 0);
        assertGt(startedAt, 0);
        assertGt(updatedAt, 0);
        assertEq(answeredInRound, 1);
        assertEq(aggregator.getLatestRoundId(), 1);
    }

    function testUpdateLatestRoundData() public {
        aggregator.updateLatestRoundDataPublic(123);

        (uint80 roundId, int256 answer,,, uint80 answeredInRound) = aggregator.latestRoundData();
        assertEq(answer, 123);
        assertEq(roundId, 2);
        assertEq(answeredInRound, 2);
        assertEq(aggregator.getLatestRoundId(), 2);
    }

    function testGetRoundDataRevertsForMissing() public {
        vm.expectRevert(bytes("Round not found"));
        aggregator.getRoundData(99);
    }

    function testMultipleRoundUpdates() public {
        aggregator.updateLatestRoundDataPublic(100);
        aggregator.updateLatestRoundDataPublic(200);
        aggregator.updateLatestRoundDataPublic(300);

        (uint80 roundId, int256 answer,,,) = aggregator.latestRoundData();
        assertEq(answer, 300);
        assertEq(roundId, 4); // Initial + 3 updates
        assertEq(aggregator.getLatestRoundId(), 4);
    }
}

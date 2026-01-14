// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { LlamaGuardOracleTestBase } from "./LlamaGuardOracleTestBase.sol";
import { ILlamaGuardOracle } from "../src/interfaces/ILlamaGuardOracle.sol";

/// @title LlamaGuardOracleRoundDataTest
/// @notice Round data, aggregator integration, and fuzz tests for LlamaGuardOracle
contract LlamaGuardOracleRoundDataTest is LlamaGuardOracleTestBase {
    // ═══════════════════════════════════════════════════════════════════════════
    // LATESTROUND DATA TESTS (BACKWARD COMPATIBILITY)
    // ═══════════════════════════════════════════════════════════════════════════

    function testLatestRoundDataInitialState() public view {
        (, int256 answer, uint256 startedAt,,) = oracle.latestRoundData();
        assertEq(answer, 0);
        // Initial round (0) has startedAt = 0, which is the expected initial state
        assertEq(startedAt, 0);
    }

    function testLatestRoundDataAfterUpdate() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        uint256 beforeTs = block.timestamp;
        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 2500, PRICE_TYPE, 5000, 7));
        (, int256 answer, uint256 startedAt,,) = oracle.latestRoundData();
        assertEq(answer, 2500);
        assertGe(startedAt, beforeTs);
    }

    function testLatestRoundDataCallableByAnyone() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_TYPE, 1000, 2));

        vm.prank(nonWriter);
        (, int256 p1,,,) = oracle.latestRoundData();
        vm.prank(admin);
        (, int256 p2,,,) = oracle.latestRoundData();
        vm.prank(address(0xABCD));
        (, int256 p3,,,) = oracle.latestRoundData();

        assertEq(p1, 500);
        assertEq(p2, 500);
        assertEq(p3, 500);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // AGGREGATOR INTEGRATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testAggregatorRoundIdIncreases() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        uint80 initialId = oracle.getLatestRoundId();
        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_TYPE, 1000, 2));
        uint80 newId = oracle.getLatestRoundId();
        assertEq(newId, initialId + 1);
    }

    function testAggregatorStoresMultipleRounds() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        vm.startPrank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 50, PRICE_TYPE, 100, 1));
        uint80 r1 = oracle.getLatestRoundId();
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", 75, PRICE_TYPE, 200, 2));
        uint80 r2 = oracle.getLatestRoundId();
        vm.stopPrank();

        (, int256 p1,,,) = oracle.getRoundData(r1);
        (, int256 p2,,,) = oracle.getRoundData(r2);
        assertEq(p1, 50);
        assertEq(p2, 75);
    }

    function testOracleIsChainlinkAggregator() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_TYPE, 1000, 2));
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracle.latestRoundData();
        assertEq(answer, 500);
        assertGt(roundId, 0);
        assertGt(startedAt, 0);
        assertGt(updatedAt, 0);
        assertGt(answeredInRound, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // getRoundData(0) EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_getRoundData_Round0_ReturnsZerosBeforeAnyUpdate() public view {
        // Round 0 should return all zeros before any updates
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracle.getRoundData(0);

        assertEq(roundId, 0);
        assertEq(answer, 0);
        assertEq(startedAt, 0);
        assertEq(updatedAt, 0);
        assertEq(answeredInRound, 0);
    }

    function test_getRoundData_Round0_ReturnsZerosAfterSingleUpdate() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_TYPE, 1000, 2));

        // After update, round 1 exists but round 0 should still return zeros
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracle.getRoundData(0);

        assertEq(roundId, 0);
        assertEq(answer, 0);
        assertEq(startedAt, 0);
        assertEq(updatedAt, 0);
        assertEq(answeredInRound, 0);

        // Verify round 1 has actual data
        (uint80 r1Id, int256 r1Answer,,,) = oracle.getRoundData(1);
        assertEq(r1Id, 1);
        assertEq(r1Answer, 500);
    }

    function test_getRoundData_Round0_ReturnsZerosAfterMultipleUpdates() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.startPrank(writer);
        for (uint256 i = 1; i <= 5; i++) {
            oracle.updateLatestRiskRoundData(
                _createUpdateInput(
                    string(abi.encodePacked("ref-", vm.toString(i))), int256(i * 100), PRICE_TYPE, i * 50, i
                )
            );

            // After each update, round 0 should still return zeros
            (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
                oracle.getRoundData(0);

            assertEq(roundId, 0, "roundId should be 0");
            assertEq(answer, 0, "answer should be 0");
            assertEq(startedAt, 0, "startedAt should be 0");
            assertEq(updatedAt, 0, "updatedAt should be 0");
            assertEq(answeredInRound, 0, "answeredInRound should be 0");
        }
        vm.stopPrank();

        // Verify rounds 1-5 have actual data
        for (uint80 i = 1; i <= 5; i++) {
            (uint80 rId, int256 rAnswer,,,) = oracle.getRoundData(i);
            assertEq(rId, i);
            assertEq(rAnswer, int256(uint256(i) * 100));
        }
    }

    function testFuzz_getRoundData_Round0_AlwaysReturnsZeros(uint8 numUpdates) public {
        // Bound to reasonable range (1-50 updates)
        numUpdates = uint8(bound(numUpdates, 1, 50));

        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.startPrank(writer);
        for (uint256 i = 1; i <= numUpdates; i++) {
            oracle.updateLatestRiskRoundData(
                _createUpdateInput(
                    string(abi.encodePacked("ref-", vm.toString(i))), int256(i * 100), PRICE_TYPE, i * 50, i
                )
            );
        }
        vm.stopPrank();

        // After any number of updates, round 0 should still return zeros
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracle.getRoundData(0);

        assertEq(roundId, 0, "roundId should be 0");
        assertEq(answer, 0, "answer should be 0");
        assertEq(startedAt, 0, "startedAt should be 0");
        assertEq(updatedAt, 0, "updatedAt should be 0");
        assertEq(answeredInRound, 0, "answeredInRound should be 0");
    }

    function test_getRoundData_NonExistentFutureRound_ReturnsZeros() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_TYPE, 1000, 2));

        // Query a round that doesn't exist (999)
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracle.getRoundData(999);

        assertEq(roundId, 0);
        assertEq(answer, 0);
        assertEq(startedAt, 0);
        assertEq(updatedAt, 0);
        assertEq(answeredInRound, 0);
    }

    function test_getRoundData_Round0_IndependentOfLatestRoundData() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);

        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 500, PRICE_TYPE, 1000, 2));

        // latestRoundData should return round 1 with actual values
        (
            uint80 latestRoundId,
            int256 latestAnswer,
            uint256 latestStartedAt,
            uint256 latestUpdatedAt,
            uint80 latestAnsweredInRound
        ) = oracle.latestRoundData();

        assertEq(latestRoundId, 1);
        assertEq(latestAnswer, 500);
        assertGt(latestStartedAt, 0);
        assertGt(latestUpdatedAt, 0);
        assertEq(latestAnsweredInRound, 1);

        // getRoundData(0) should still return all zeros
        (
            uint80 round0Id,
            int256 round0Answer,
            uint256 round0StartedAt,
            uint256 round0UpdatedAt,
            uint80 round0AnsweredInRound
        ) = oracle.getRoundData(0);

        assertEq(round0Id, 0);
        assertEq(round0Answer, 0);
        assertEq(round0StartedAt, 0);
        assertEq(round0UpdatedAt, 0);
        assertEq(round0AnsweredInRound, 0);
    }

    function testSequentialUpdatesInSameTransaction() public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        vm.startPrank(writer);
        for (uint256 i = 1; i <= 10; i++) {
            oracle.updateLatestRiskRoundData(
                _createUpdateInput(
                    string(abi.encodePacked("ref-", vm.toString(i))), int256(i * 50), PRICE_TYPE, i * 100, i
                )
            );
        }
        vm.stopPrank();

        // Verify via latestRoundData
        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, 500);

        // Verify full data via getUpdateById - decode from additionalData for full bundle
        ILlamaGuardOracle.RiskParameterUpdate memory update = oracle.getUpdateById(10); // 10th update, roundId starts
        // at 1
        (uint256 supply, int256 price, uint256 state) = abi.decode(update.additionalData, (uint256, int256, uint256));
        assertEq(supply, 1000);
        assertEq(state, 10);
        assertEq(price, 500);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // FUZZ TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function testFuzzUpdateData(uint256 _supply, int256 _price, uint256 _state) public {
        oracle.grantRole(oracle.WRITER_ROLE(), writer);
        vm.prank(writer);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", _price, PRICE_TYPE, _supply, _state));

        // Verify price via latestRoundData
        (, int256 answer,,,) = oracle.latestRoundData();
        assertEq(answer, _price);

        // Verify full data via getUpdateById - decode from additionalData for full bundle
        ILlamaGuardOracle.RiskParameterUpdate memory update = oracle.getUpdateById(1);
        (uint256 supply, int256 price, uint256 state) = abi.decode(update.additionalData, (uint256, int256, uint256));
        assertEq(supply, _supply);
        assertEq(state, _state);
        assertEq(price, _price);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29;

import { IAggregatorV3 } from "../../src/interfaces/IAggregatorV3.sol";

contract MockAggregatorV3 is IAggregatorV3 {
    struct RoundData {
        int256 answer;
        uint256 timestamp;
        uint256 startedAt;
        uint80 answeredInRound;
    }

    uint8 public decimals;
    string public description;
    uint256 public version;

    uint80 public latestRound;
    mapping(uint80 => RoundData) public rounds;

    constructor(uint8 _decimals, string memory _description) {
        decimals = _decimals;
        description = _description;
        version = 3;
        latestRound = 1;
    }

    function setRoundData(
        uint80 _roundId,
        int256 _answer,
        uint256 _timestamp,
        uint256 _startedAt,
        uint80 _answeredInRound
    )
        external
    {
        rounds[_roundId] = RoundData({
            answer: _answer,
            timestamp: _timestamp,
            startedAt: _startedAt,
            answeredInRound: _answeredInRound
        });

        if (_roundId > latestRound) {
            latestRound = _roundId;
        }
    }

    function setMultipleRounds(
        uint80[] memory _roundIds,
        int256[] memory _answers,
        uint256[] memory _timestamps
    )
        external
    {
        require(_roundIds.length == _answers.length && _answers.length == _timestamps.length, "Array length mismatch");

        for (uint256 i = 0; i < _roundIds.length; i++) {
            rounds[_roundIds[i]] = RoundData({
                answer: _answers[i],
                timestamp: _timestamps[i],
                startedAt: _timestamps[i],
                answeredInRound: _roundIds[i]
            });

            if (_roundIds[i] > latestRound) {
                latestRound = _roundIds[i];
            }
        }
    }

    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        RoundData memory round = rounds[_roundId];
        require(round.timestamp > 0, "No data present");

        return (_roundId, round.answer, round.startedAt, round.timestamp, round.answeredInRound);
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        RoundData memory round = rounds[latestRound];
        require(round.timestamp > 0, "No data present");

        return (latestRound, round.answer, round.startedAt, round.timestamp, round.answeredInRound);
    }
}

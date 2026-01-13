// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.26 <0.9.0;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract MockAggregatorV3 is AggregatorV3Interface {
    struct RoundData {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    mapping(uint80 => RoundData) private _roundData;
    uint80 private _latestRoundId;

    error RoundNotFound(uint80 roundId);

    function setRoundData(
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    )
        external
    {
        _roundData[roundId] = RoundData({
            roundId: roundId,
            answer: answer,
            startedAt: startedAt,
            updatedAt: updatedAt,
            answeredInRound: answeredInRound
        });

        if (roundId > _latestRoundId) {
            _latestRoundId = roundId;
        }
    }

    function decimals() external pure override returns (uint8) {
        return 8;
    }

    function description() external pure override returns (string memory) {
        return "Mock Price Feed";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80 roundId) external view override returns (uint80, int256, uint256, uint256, uint80) {
        if (_roundData[roundId].roundId == 0 && roundId != 0) revert RoundNotFound(roundId);
        RoundData memory data = _roundData[roundId];
        return (data.roundId, data.answer, data.startedAt, data.updatedAt, data.answeredInRound);
    }

    function latestRoundData() external view override returns (uint80, int256, uint256, uint256, uint80) {
        RoundData memory data = _roundData[_latestRoundId];
        return (data.roundId, data.answer, data.startedAt, data.updatedAt, data.answeredInRound);
    }
}

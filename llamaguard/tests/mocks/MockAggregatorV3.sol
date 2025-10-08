// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.26 <0.9.0;

contract MockAggregatorV3 {
    mapping(uint80 => RoundData) public rounds;
    uint80 public latestRound;

    struct RoundData {
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    function setRoundData(
        uint80 _roundId,
        int256 _answer,
        uint256 _startedAt,
        uint256 _updatedAt,
        uint80 _answeredInRound
    )
        external
    {
        rounds[_roundId] = RoundData({
            answer: _answer,
            startedAt: _startedAt,
            updatedAt: _updatedAt,
            answeredInRound: _answeredInRound
        });

        if (_roundId > latestRound) {
            latestRound = _roundId;
        }
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        RoundData memory data = rounds[latestRound];
        return (latestRound, data.answer, data.startedAt, data.updatedAt, data.answeredInRound);
    }

    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        RoundData memory data = rounds[_roundId];
        return (_roundId, data.answer, data.startedAt, data.updatedAt, data.answeredInRound);
    }
}

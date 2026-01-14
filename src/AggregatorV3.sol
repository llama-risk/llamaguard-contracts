// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title AggregatorV3
 * @notice Implementation of Chainlink's AggregatorV3Interface
 *
 * Security Model:
 * - _updateLatestRoundData() is internal - only callable by derived contracts
 * - Derived contracts MUST implement proper access control (e.g., LlamaGuardOracle.onlyProxy)
 * - Historical round data is immutable once created
 *
 * Usage:
 * This contract should be inherited by oracle implementations that control data updates.
 * Do NOT deploy directly - it has no access control on its own.
 */
contract AggregatorV3 is AggregatorV3Interface {
    uint8 private immutable _decimals;
    string private _description;
    uint256 private immutable _version;

    /// @notice Structure for storing round data
    struct RoundData {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    // Storage for round data
    mapping(uint80 => RoundData) private _roundData;
    uint80 private _latestRoundId;

    // Events
    event RoundDataUpdated(uint80 indexed roundId, int256 answer, uint256 startedAt, uint256 updatedAt);

    // Errors
    error RoundNotFound(uint80 roundId);

    /**
     * @dev Constructor to initialize the aggregator
     * @param decimals_ Number of decimals for the price feed
     * @param description_ Description of the price feed
     * @param version_ Version of the aggregator
     */
    constructor(uint8 decimals_, string memory description_, uint256 version_) {
        _decimals = decimals_;
        _description = description_;
        _version = version_;

        // Initialize with a default round
        _roundData[0] = RoundData({ roundId: 0, answer: 0, startedAt: 0, updatedAt: 0, answeredInRound: 0 });
    }

    /**
     * @dev Returns the number of decimals used to get its user representation
     */
    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    /**
     * @dev Returns the description of the price feed
     */
    function description() external view override returns (string memory) {
        return _description;
    }

    /**
     * @dev Returns the version of the aggregator
     */
    function version() external view override returns (uint256) {
        return _version;
    }

    /**
     * @dev Get data from a specific round
     * @param _roundId The round ID to get data for
     * @return roundId The round ID
     * @return answer The price answer
     * @return startedAt Timestamp when the round started
     * @return updatedAt Timestamp when the round was updated
     * @return answeredInRound The round ID in which the answer was computed
     */
    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        if (_roundData[_roundId].roundId == 0) revert RoundNotFound(_roundId);

        RoundData memory data = _roundData[_roundId];
        return (data.roundId, data.answer, data.startedAt, data.updatedAt, data.answeredInRound);
    }

    /**
     * @dev Get the latest round data
     * @return roundId The round ID
     * @return answer The price answer
     * @return startedAt Timestamp when the round started
     * @return updatedAt Timestamp when the round was updated
     * @return answeredInRound The round ID in which the answer was computed
     */
    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        RoundData memory data = _roundData[_latestRoundId];
        return (data.roundId, data.answer, data.startedAt, data.updatedAt, data.answeredInRound);
    }

    /**
     * @dev Get the latest round ID
     */
    function getLatestRoundId() external view returns (uint80) {
        return _latestRoundId;
    }

    /**
     * @notice Update the latest round data
     * @dev Internal function - only callable by derived contracts that implement proper access control
     * @param answer The new price answer
     */
    function _updateLatestRoundData(int256 answer) internal {
        _latestRoundId++;

        _roundData[_latestRoundId] = RoundData({
            roundId: _latestRoundId,
            answer: answer,
            startedAt: block.timestamp,
            updatedAt: block.timestamp,
            answeredInRound: _latestRoundId
        });

        emit RoundDataUpdated(_latestRoundId, answer, block.timestamp, block.timestamp);
    }
}

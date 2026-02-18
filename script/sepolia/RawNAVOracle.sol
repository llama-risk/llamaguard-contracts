// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title RawNAVOracle
/// @notice Writable AggregatorV3-compatible oracle for Sepolia integration testing
/// @dev The deployer (owner) pushes raw NAV values. CRE listens to the emitted events.
///      Used by a cron job (real prices) and manually (bad values for fire drills).
contract RawNAVOracle is Ownable, AggregatorV3Interface {
    uint8 private immutable _decimals;
    string private _description;
    uint256 private immutable _version;

    uint80 private _latestRoundId;
    int256 private _latestAnswer;
    uint256 private _latestStartedAt;
    uint256 private _latestUpdatedAt;

    /// @notice Emitted when new round data is pushed — CRE listens to this
    event RoundDataUpdated(uint80 indexed roundId, int256 answer, uint256 startedAt, uint256 updatedAt);

    /// @param decimals_ Number of decimals for the oracle (e.g., 8)
    /// @param description_ Human-readable description (e.g., "USTB Raw NAV (Sepolia)")
    /// @param version_ Oracle version number
    /// @param initialAnswer Initial price to seed latestRoundData with valid data immediately
    constructor(
        uint8 decimals_,
        string memory description_,
        uint256 version_,
        int256 initialAnswer
    )
        Ownable(msg.sender)
    {
        _decimals = decimals_;
        _description = description_;
        _version = version_;

        _latestRoundId = 1;
        _latestAnswer = initialAnswer;
        _latestStartedAt = block.timestamp;
        _latestUpdatedAt = block.timestamp;

        emit RoundDataUpdated(1, initialAnswer, block.timestamp, block.timestamp);
    }

    /// @notice Push a new price value — only callable by owner (deployer / cron job)
    /// @param answer The new NAV price (8 decimals)
    function updateLatestRoundData(int256 answer) external onlyOwner {
        _latestRoundId++;
        _latestAnswer = answer;
        _latestStartedAt = block.timestamp;
        _latestUpdatedAt = block.timestamp;

        emit RoundDataUpdated(_latestRoundId, answer, block.timestamp, block.timestamp);
    }

    /// @inheritdoc AggregatorV3Interface
    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    /// @inheritdoc AggregatorV3Interface
    function description() external view override returns (string memory) {
        return _description;
    }

    /// @inheritdoc AggregatorV3Interface
    function version() external view override returns (uint256) {
        return _version;
    }

    /// @inheritdoc AggregatorV3Interface
    function getRoundData(uint80)
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        // Only latest round is stored; return it for any query
        return (_latestRoundId, _latestAnswer, _latestStartedAt, _latestUpdatedAt, _latestRoundId);
    }

    /// @inheritdoc AggregatorV3Interface
    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_latestRoundId, _latestAnswer, _latestStartedAt, _latestUpdatedAt, _latestRoundId);
    }
}

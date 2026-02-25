// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { AggregatorV2V3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV2V3Interface.sol";
import { AggregatorInterface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorInterface.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title EACAggregatorProxy
 * @notice Proxy contract for Chainlink-style aggregators (Ethereum Aggregator Contract Abstraction)
 * @dev This proxy allows upgrading the underlying aggregator implementation while maintaining the same address
 *
 * Based on Chainlink's EACAggregatorProxy pattern:
 * - Consumers always interact with the proxy address
 * - Owner can update the underlying aggregator
 * - Maintains backward compatibility with AggregatorV2V3Interface
 */
contract EACAggregatorProxy is Ownable, AggregatorV2V3Interface {
    /// @notice The current aggregator implementation
    AggregatorV2V3Interface public aggregator;

    /// @notice Emitted when the aggregator is updated
    event AggregatorUpdated(address indexed oldAggregator, address indexed newAggregator);

    error InvalidAggregator();

    /**
     * @notice Constructor
     * @param _aggregator Address of the initial aggregator implementation
     */
    constructor(address _aggregator) Ownable(msg.sender) {
        require(_aggregator != address(0), InvalidAggregator());
        aggregator = AggregatorV2V3Interface(_aggregator);
    }

    /**
     * @notice Update the aggregator implementation
     * @param _aggregator Address of the new aggregator
     */
    function proposeAggregator(address _aggregator) external onlyOwner {
        require(_aggregator != address(0), InvalidAggregator());
        address oldAggregator = address(aggregator);
        aggregator = AggregatorV2V3Interface(_aggregator);
        emit AggregatorUpdated(oldAggregator, _aggregator);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // AggregatorV3Interface
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc AggregatorV3Interface
    function decimals() external view override returns (uint8) {
        return aggregator.decimals();
    }

    /// @inheritdoc AggregatorV3Interface
    function description() external view override returns (string memory) {
        return aggregator.description();
    }

    /// @inheritdoc AggregatorV3Interface
    function version() external view override returns (uint256) {
        return aggregator.version();
    }

    /// @inheritdoc AggregatorV3Interface
    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return aggregator.getRoundData(_roundId);
    }

    /// @inheritdoc AggregatorV3Interface
    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return aggregator.latestRoundData();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // AggregatorInterface (V2)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc AggregatorInterface
    function latestAnswer() external view override returns (int256) {
        return aggregator.latestAnswer();
    }

    /// @inheritdoc AggregatorInterface
    function latestTimestamp() external view override returns (uint256) {
        return aggregator.latestTimestamp();
    }

    /// @inheritdoc AggregatorInterface
    function latestRound() external view override returns (uint256) {
        return aggregator.latestRound();
    }

    /// @inheritdoc AggregatorInterface
    function getAnswer(uint256 roundId) external view override returns (int256) {
        return aggregator.getAnswer(roundId);
    }

    /// @inheritdoc AggregatorInterface
    function getTimestamp(uint256 roundId) external view override returns (uint256) {
        return aggregator.getTimestamp(roundId);
    }

    /**
     * @notice Get the address of the current aggregator
     * @return The aggregator address
     */
    function phaseAggregators(uint16) external view returns (address) {
        return address(aggregator);
    }
}

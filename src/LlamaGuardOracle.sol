// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { AggregatorV2V3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV2V3Interface.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { AggregatorInterface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorInterface.sol";
import { ILlamaGuardOracle } from "./interfaces/ILlamaGuardOracle.sol";
import { AbstractReadWriteAccessController } from "./abstracts/AbstractReadWriteAccessController.sol";

/**
 * @title LlamaGuardOracle
 * @notice Chainlink-compatible oracle with risk parameter tracking
 * @dev Implements AggregatorV2V3Interface for full Chainlink compatibility (V2 + V3 methods).
 *      Historical round data is immutable once created. Access control via WRITER_ROLE.
 */
contract LlamaGuardOracle is AggregatorV2V3Interface, ILlamaGuardOracle, AbstractReadWriteAccessController {
    // ═══════════════════════════════════════════════════════════════════════════
    // AGGREGATOR STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc AggregatorV3Interface
    uint8 public immutable override decimals;

    /// @inheritdoc AggregatorV3Interface
    uint256 public immutable override version;

    /// @inheritdoc AggregatorV3Interface
    string public override description;

    /// @notice Structure for storing round data
    struct RoundData {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    /// @notice Storage for round data
    mapping(uint80 roundId => RoundData data) private _roundData;

    /// @notice Latest round ID
    uint80 private _latestRoundId;

    // ═══════════════════════════════════════════════════════════════════════════
    // RISK PARAMETER STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Array of all valid update type strings
    /// @dev This public array provides transparency for integrators and off-chain systems
    ///      to discover which update types are supported by this oracle. Individual elements
    ///      can be accessed via updateTypes(index), and the length via updateTypes.length.
    ///      Use isValidUpdateType() for O(1) validation of specific update types.
    string[] public updateTypes;

    /// @notice Mapping for O(1) validation of update types
    mapping(bytes32 updateTypeHash => bool isValid) private _validUpdateTypes;

    /// @notice Mapping from updateId (roundId) to RiskParameterUpdate struct
    mapping(uint256 updateId => RiskParameterUpdate update) public updateHistory;

    /// @notice Mapping to track latest updateId for each updateType
    /// @dev Enables O(1) lookups via getLatestUpdateByParameterAndMarket()
    mapping(bytes32 updateTypeHash => uint256 updateId) private _latestUpdateIdByType;

    /// @notice Mapping of authorized market addresses
    /// @dev O(1) lookup for market authorization checks
    mapping(address market => bool isAuthorized) private _authorizedMarkets;

    /// @notice Maximum allowed price deviation in basis points (0 = disabled)
    /// @dev When non-zero, new prices must be within this deviation from the previous price
    uint256 public maxPriceDeviation;

    /// @notice Sentinel value indicating no additionalData length validation
    uint256 public constant ADDITIONAL_DATA_LENGTH_NOT_SET = type(uint256).max;

    /// @notice Expected byte length for additionalData per update type
    /// @dev type(uint256).max = no validation, 0 = must be empty, N = must be exactly N bytes
    mapping(bytes32 updateTypeHash => uint256 expectedLength) private _updateTypeExpectedLength;

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Emitted when round data is updated
    event RoundDataUpdated(uint80 indexed roundId, int256 answer, uint256 startedAt, uint256 updatedAt);

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Initialize the oracle with configuration and initial update types
    /// @param decimals_ The number of decimals for price values
    /// @param description_ Human-readable description of the oracle feed
    /// @param version_ Version number of the oracle
    /// @param initialUpdateTypes Array of initial valid update type strings
    /// @param initialAuthorizedMarkets Array of initially authorized market addresses
    constructor(
        uint8 decimals_,
        string memory description_,
        uint256 version_,
        string[] memory initialUpdateTypes,
        address[] memory initialAuthorizedMarkets
    )
        AbstractReadWriteAccessController(msg.sender)
    {
        // Initialize aggregator state
        decimals = decimals_;
        description = description_;
        version = version_;

        // Initialize update types (no length validation by default)
        for (uint256 i = 0; i < initialUpdateTypes.length; i++) {
            _addUpdateType(initialUpdateTypes[i], ADDITIONAL_DATA_LENGTH_NOT_SET);
        }

        // Initialize authorized markets
        for (uint256 i = 0; i < initialAuthorizedMarkets.length; i++) {
            _addAuthorizedMarket(initialAuthorizedMarkets[i]);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // AGGREGATOR V3 INTERFACE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc AggregatorV3Interface
    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        RoundData memory data = _roundData[_roundId];
        return (data.roundId, data.answer, data.startedAt, data.updatedAt, data.answeredInRound);
    }

    /// @inheritdoc AggregatorV3Interface
    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        RoundData memory data = _roundData[_latestRoundId];
        return (data.roundId, data.answer, data.startedAt, data.updatedAt, data.answeredInRound);
    }

    /// @notice Get the latest round ID
    /// @return The latest round ID
    function getLatestRoundId() external view returns (uint80) {
        return _latestRoundId;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // AGGREGATOR V2 INTERFACE (LEGACY)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc AggregatorInterface
    function latestAnswer() external view override returns (int256) {
        return _roundData[_latestRoundId].answer;
    }

    /// @inheritdoc AggregatorInterface
    function latestTimestamp() external view override returns (uint256) {
        return _roundData[_latestRoundId].updatedAt;
    }

    /// @inheritdoc AggregatorInterface
    function latestRound() external view override returns (uint256) {
        return uint256(_latestRoundId);
    }

    /// @inheritdoc AggregatorInterface
    function getAnswer(uint256 roundId) external view override returns (int256) {
        return _roundData[uint80(roundId)].answer;
    }

    /// @inheritdoc AggregatorInterface
    function getTimestamp(uint256 roundId) external view override returns (uint256) {
        return _roundData[uint80(roundId)].updatedAt;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Update the latest round data
    /// @dev Emits RoundDataUpdated, AnswerUpdated (V2), and NewRound (V2) events
    /// @param answer The new price answer
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

        // V2 AggregatorInterface events
        emit AnswerUpdated(answer, uint256(_latestRoundId), block.timestamp);
        emit NewRound(uint256(_latestRoundId), msg.sender, block.timestamp);
    }

    /// @notice Calculate the deviation between two prices in basis points
    /// @param previousPrice The previous price value
    /// @param newPrice The new price value
    /// @return The deviation in basis points (10000 = 100%)
    function _calculateDeviation(int256 previousPrice, int256 newPrice) internal pure returns (uint256) {
        if (previousPrice == 0) return 0;

        // Calculate absolute difference
        int256 diff = newPrice > previousPrice ? newPrice - previousPrice : previousPrice - newPrice;
        uint256 absDiff = diff >= 0 ? uint256(diff) : uint256(-diff);

        // Calculate absolute previous price for denominator
        uint256 absPreviousPrice = previousPrice >= 0 ? uint256(previousPrice) : uint256(-previousPrice);

        // Return deviation in basis points
        return (absDiff * 10_000) / absPreviousPrice;
    }

    /// @notice Internal helper to add a new update type
    /// @param updateType The update type string to add
    /// @param expectedLength Expected additionalData byte length (type(uint256).max = no validation, 0 = must be empty)
    function _addUpdateType(string memory updateType, uint256 expectedLength) internal {
        // Validate string length
        require(bytes(updateType).length != 0 && bytes(updateType).length <= 64, InvalidUpdateTypeString(updateType));

        // Check for duplicates
        bytes32 typeHash = keccak256(bytes(updateType));
        require(!_validUpdateTypes[typeHash], UpdateTypeAlreadyExists(updateType));

        // Add the new type
        _validUpdateTypes[typeHash] = true;
        _updateTypeExpectedLength[typeHash] = expectedLength;
        updateTypes.push(updateType);

        emit UpdateTypeAdded(updateType, expectedLength);
    }

    /// @notice Internal helper to remove an update type
    /// @param updateType The update type string to remove
    function _removeUpdateType(string memory updateType) internal {
        bytes32 typeHash = keccak256(bytes(updateType));
        require(_validUpdateTypes[typeHash], UpdateTypeNotFound(updateType));

        _validUpdateTypes[typeHash] = false;

        // Remove from array by swap-and-pop
        uint256 length = updateTypes.length;
        for (uint256 i = 0; i < length; i++) {
            if (keccak256(bytes(updateTypes[i])) == typeHash) {
                updateTypes[i] = updateTypes[length - 1];
                updateTypes.pop();
                break;
            }
        }

        emit UpdateTypeRemoved(updateType);
    }

    /// @notice Internal helper to add an authorized market
    /// @param market The market address to authorize
    function _addAuthorizedMarket(address market) internal {
        require(market != address(0), InvalidMarketAddress(market));
        require(!_authorizedMarkets[market], MarketAlreadyAuthorized(market));

        _authorizedMarkets[market] = true;
        emit AuthorizedMarketAdded(market);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MUTATORS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc ILlamaGuardOracle
    function updateLatestRiskRoundData(UpdateInput calldata input) external onlyRole(WRITER_ROLE) {
        // Compute hash for internal lookups
        bytes32 updateTypeHash = keccak256(bytes(input.updateType));

        // Validate update type
        require(_validUpdateTypes[updateTypeHash], UnauthorizedUpdateType(input.updateType));

        // Validate additionalData length if configured
        uint256 expectedLength = _updateTypeExpectedLength[updateTypeHash];
        if (expectedLength != ADDITIONAL_DATA_LENGTH_NOT_SET) {
            require(
                input.additionalData.length == expectedLength,
                InvalidAdditionalDataLength(input.additionalData.length, expectedLength)
            );
        }

        // Get previous value from history (empty for first update)
        bytes memory previousValue = updateHistory[_latestRoundId].newValue;

        // Decode price from newValue and update round data for AggregatorV3 compatibility
        // newValue contains only the price (int256), while additionalData contains the full bundle
        {
            int256 price = abi.decode(input.newValue, (int256));

            // Validate price deviation if enabled and there's a previous price
            if (maxPriceDeviation > 0 && _latestRoundId > 0) {
                int256 previousPrice = _roundData[_latestRoundId].answer;
                if (previousPrice != 0) {
                    uint256 deviation = _calculateDeviation(previousPrice, price);
                    require(
                        deviation <= maxPriceDeviation,
                        PriceDeviationExceeded(previousPrice, price, deviation, maxPriceDeviation)
                    );
                }
            }

            _updateLatestRoundData(price);
        }

        // Get new roundId as updateId and store in history
        // _latestRoundId was incremented by _updateLatestRoundData
        uint256 updateId = _latestRoundId;

        // Store in history (market is set to address(0) for global updates)
        updateHistory[updateId] = RiskParameterUpdate({
            timestamp: block.timestamp,
            newValue: input.newValue,
            referenceId: input.referenceId,
            previousValue: previousValue,
            updateType: input.updateType,
            updateId: updateId,
            market: address(0),
            additionalData: input.additionalData
        });

        // Update the latest update index for this updateType
        _latestUpdateIdByType[updateTypeHash] = updateId;

        emit ParameterUpdated(
            input.referenceId,
            input.newValue,
            previousValue,
            block.timestamp,
            input.updateType,
            updateId,
            input.additionalData
        );
    }

    /// @inheritdoc ILlamaGuardOracle
    function addUpdateType(
        string calldata newUpdateType,
        uint256 expectedAdditionalDataLength
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _addUpdateType(newUpdateType, expectedAdditionalDataLength);
    }

    /// @inheritdoc ILlamaGuardOracle
    function removeUpdateType(string calldata updateType) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _removeUpdateType(updateType);
    }

    /// @notice Set the maximum allowed price deviation
    /// @dev Set to 0 to disable price deviation checks. Value is in basis points (10000 = 100%).
    /// @param newMaxDeviation The new maximum price deviation in basis points
    function setMaxPriceDeviation(uint256 newMaxDeviation) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 previousValue = maxPriceDeviation;
        maxPriceDeviation = newMaxDeviation;
        emit MaxPriceDeviationUpdated(previousValue, newMaxDeviation);
    }

    /// @inheritdoc ILlamaGuardOracle
    function setExpectedAdditionalDataLength(
        string calldata updateType,
        uint256 expectedLength
    )
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        bytes32 typeHash = keccak256(bytes(updateType));
        require(_validUpdateTypes[typeHash], UpdateTypeNotFound(updateType));

        _updateTypeExpectedLength[typeHash] = expectedLength;
        emit ExpectedAdditionalDataLengthUpdated(updateType, expectedLength);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEWS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc ILlamaGuardOracle
    function getUpdateById(uint256 updateId) external view returns (RiskParameterUpdate memory) {
        require(updateId != 0 && updateId <= _latestRoundId, InvalidUpdateId(updateId));

        RiskParameterUpdate memory update = updateHistory[updateId];
        require(update.timestamp != 0, InvalidUpdateId(updateId));

        return update;
    }

    /// @inheritdoc ILlamaGuardOracle
    function isValidUpdateType(string calldata updateType) external view returns (bool) {
        return _validUpdateTypes[keccak256(bytes(updateType))];
    }

    /// @inheritdoc ILlamaGuardOracle
    function getExpectedAdditionalDataLength(string calldata updateType) external view returns (uint256) {
        return _updateTypeExpectedLength[keccak256(bytes(updateType))];
    }

    /// @inheritdoc ILlamaGuardOracle
    function hasWriteAccess(address account) public view returns (bool) {
        return hasRole(WRITER_ROLE, account);
    }

    /// @inheritdoc ILlamaGuardOracle
    function getLatestUpdateByParameterAndMarket(
        string calldata updateType,
        address market
    )
        external
        view
        returns (RiskParameterUpdate memory)
    {
        return _getLatestUpdateByParameterAndMarket(keccak256(bytes(updateType)), market);
    }

    /// @notice Internal implementation for getLatestUpdateByParameterAndMarket
    /// @param updateTypeHash The keccak256 hash of the parameter type identifier
    /// @param market The market address to be written to the returned RiskParameterUpdate.market field
    /// @return The most recent RiskParameterUpdate for the specified updateTypeHash
    function _getLatestUpdateByParameterAndMarket(
        bytes32 updateTypeHash,
        address market
    )
        internal
        view
        returns (RiskParameterUpdate memory)
    {
        require(_authorizedMarkets[market], UnauthorizedMarket(market));

        uint256 updateId = _latestUpdateIdByType[updateTypeHash];

        // Strict validation: revert if no update exists
        require(updateId != 0, InvalidUpdateId(updateId));

        RiskParameterUpdate memory update = updateHistory[updateId];
        // Rewrite the input market to the returned RiskParameterUpdate
        update.market = market;
        return update;
    }

    /// @inheritdoc ILlamaGuardOracle
    function isAuthorizedMarket(address market) public view returns (bool) {
        return _authorizedMarkets[market];
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARKET AUTHORIZATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc ILlamaGuardOracle
    function addAuthorizedMarket(address market) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _addAuthorizedMarket(market);
    }

    /// @inheritdoc ILlamaGuardOracle
    function removeAuthorizedMarket(address market) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(market != address(0), InvalidMarketAddress(market));
        require(_authorizedMarkets[market], MarketNotFound(market));

        _authorizedMarkets[market] = false;
        emit AuthorizedMarketRemoved(market);
    }
}

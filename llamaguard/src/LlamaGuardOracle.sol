// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { AggregatorV3 } from "./AggregatorV3.sol";
import { ILlamaGuardOracle } from "./interfaces/ILlamaGuardOracle.sol";
import { AbstractReadWriteAccessController } from "./abstracts/AbstractReadWriteAccessController.sol";

contract LlamaGuardOracle is AggregatorV3, ILlamaGuardOracle, AbstractReadWriteAccessController {
    // ═══════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Array of all valid update type strings
    string[] public updateTypes;

    /// @notice Mapping for O(1) validation of update types
    mapping(string => bool) private validUpdateTypes;

    /// @notice Mapping from updateId (roundId) to RiskParameterUpdate struct
    mapping(uint256 => RiskParameterUpdate) public updateHistory;

    /// @notice Mapping to track latest updateId for each updateType
    /// @dev Enables O(1) lookups via getLatestUpdateByParameterAndMarket()
    mapping(string => uint256) private latestUpdateIdByType;

    /// @notice Mapping of authorized market addresses
    /// @dev O(1) lookup for market authorization checks
    mapping(address => bool) private authorizedMarkets;

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Initialize the oracle with configuration and initial update types
    /// @param decimals The number of decimals for price values
    /// @param description Human-readable description of the oracle feed
    /// @param version Version number of the oracle
    /// @param initialUpdateTypes Array of initial valid update type strings
    /// @param initialAuthorizedMarkets Array of initially authorized market addresses
    constructor(
        uint8 decimals,
        string memory description,
        uint256 version,
        string[] memory initialUpdateTypes,
        address[] memory initialAuthorizedMarkets
    )
        AbstractReadWriteAccessController(msg.sender)
        AggregatorV3(decimals, description, version)
    {
        // Initialize update types
        for (uint256 i = 0; i < initialUpdateTypes.length; i++) {
            string memory updateType = initialUpdateTypes[i];
            if (bytes(updateType).length == 0 || bytes(updateType).length > 64) {
                revert InvalidUpdateTypeString(updateType);
            }
            if (!validUpdateTypes[updateType]) {
                validUpdateTypes[updateType] = true;
                updateTypes.push(updateType);
            }
        }

        // Initialize authorized markets
        for (uint256 i = 0; i < initialAuthorizedMarkets.length; i++) {
            address market = initialAuthorizedMarkets[i];
            if (market == address(0)) {
                revert InvalidMarketAddress(market);
            }
            if (!authorizedMarkets[market]) {
                authorizedMarkets[market] = true;
                emit AuthorizedMarketAdded(market);
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MUTATORS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc ILlamaGuardOracle
    function updateData(
        string calldata referenceId,
        bytes calldata newValue,
        string calldata updateType,
        bytes calldata additionalData
    )
        external
        onlyRole(WRITER_ROLE)
    {
        // Validate update type
        if (!validUpdateTypes[updateType]) {
            revert UnauthorizedUpdateType(updateType);
        }

        // Get previous value from history (empty for first update)
        bytes memory previousValue = updateHistory[this.getLatestRoundId()].newValue;

        // Decode new value to extract price for AggregatorV3 and update round data
        {
            (, int256 price,) = abi.decode(newValue, (uint256, int256, uint256));
            updateLatestRoundData(price);
        }

        // Get new roundId as updateId and store in history
        uint256 updateId = this.getLatestRoundId();

        // Store in history (market is set to address(0) as per requirements)
        updateHistory[updateId] = RiskParameterUpdate({
            timestamp: block.timestamp,
            newValue: newValue,
            referenceId: referenceId,
            previousValue: previousValue,
            updateType: updateType,
            updateId: updateId,
            market: address(0),
            additionalData: additionalData
        });

        // Update the latest update index for this updateType
        latestUpdateIdByType[updateType] = updateId;

        emit ParameterUpdated(
            referenceId, newValue, previousValue, block.timestamp, updateType, updateId, additionalData
        );
    }

    /// @inheritdoc ILlamaGuardOracle
    function addUpdateType(string calldata newUpdateType) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Validate string length
        if (bytes(newUpdateType).length == 0 || bytes(newUpdateType).length > 64) {
            revert InvalidUpdateTypeString(newUpdateType);
        }

        // Check for duplicates
        if (validUpdateTypes[newUpdateType]) {
            revert UpdateTypeAlreadyExists(newUpdateType);
        }

        // Add the new type
        validUpdateTypes[newUpdateType] = true;
        updateTypes.push(newUpdateType);

        emit UpdateTypeAdded(newUpdateType);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEWS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc ILlamaGuardOracle
    function getUpdateById(uint256 updateId) external view returns (RiskParameterUpdate memory) {
        uint80 latestRound = this.getLatestRoundId();
        if (updateId == 0 || updateId > latestRound) {
            revert InvalidUpdateId(updateId);
        }

        RiskParameterUpdate memory update = updateHistory[updateId];
        if (update.timestamp == 0) {
            revert InvalidUpdateId(updateId);
        }

        return update;
    }

    /// @inheritdoc ILlamaGuardOracle
    function getAllUpdateTypes() external view returns (string[] memory) {
        return updateTypes;
    }

    /// @inheritdoc ILlamaGuardOracle
    function isValidUpdateType(string calldata updateType) external view returns (bool) {
        return validUpdateTypes[updateType];
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
        uint256 updateId = latestUpdateIdByType[updateType];

        // Return empty struct if no update exists (updateId == 0)
        // This is intentional - we do NOT revert per spec FR-004 and FR-005
        if (updateId == 0) {
            return RiskParameterUpdate({
                timestamp: 0,
                newValue: "",
                referenceId: "",
                previousValue: "",
                updateType: "",
                updateId: 0,
                market: address(0),
                additionalData: ""
            });
        }

        RiskParameterUpdate memory update = updateHistory[updateId];
        // Rewrite the input market to the returned RiskParameterUpdate
        update.market = market;
        return update;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MARKET AUTHORIZATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc ILlamaGuardOracle
    function addAuthorizedMarket(address market) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (market == address(0)) {
            revert InvalidMarketAddress(market);
        }
        if (authorizedMarkets[market]) {
            revert MarketAlreadyAuthorized(market);
        }

        authorizedMarkets[market] = true;
        emit AuthorizedMarketAdded(market);
    }

    /// @inheritdoc ILlamaGuardOracle
    function removeAuthorizedMarket(address market) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (market == address(0)) {
            revert InvalidMarketAddress(market);
        }
        if (!authorizedMarkets[market]) {
            revert MarketNotFound(market);
        }

        authorizedMarkets[market] = false;
        emit AuthorizedMarketRemoved(market);
    }

    /// @inheritdoc ILlamaGuardOracle
    function isAuthorizedMarket(address market) public view returns (bool) {
        return authorizedMarkets[market];
    }
}

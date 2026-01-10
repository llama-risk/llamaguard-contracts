// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { AggregatorV3 } from "./AggregatorV3.sol";
import { ILlamaGuardOracle } from "./interfaces/ILlamaGuardOracle.sol";
import { AbstractReadWriteAccessController } from "./abstracts/AbstractReadWriteAccessController.sol";

contract LlamaGuardOracle is AggregatorV3, ILlamaGuardOracle, AbstractReadWriteAccessController {
    // ═══════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
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
    mapping(uint256 => RiskParameterUpdate) public updateHistory;

    /// @notice Mapping to track latest updateId for each updateType
    /// @dev Enables O(1) lookups via getLatestUpdateByParameterAndMarket()
    mapping(bytes32 updateTypeHash => uint256 updateId) private _latestUpdateIdByType;

    /// @notice Mapping of authorized market addresses
    /// @dev O(1) lookup for market authorization checks
    mapping(address market => bool isAuthorized) private _authorizedMarkets;

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
            _addUpdateType(initialUpdateTypes[i]);
        }

        // Initialize authorized markets
        for (uint256 i = 0; i < initialAuthorizedMarkets.length; i++) {
            _addAuthorizedMarket(initialAuthorizedMarkets[i]);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INTERNAL HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Internal helper to add a new update type
    /// @param updateType The update type string to add
    function _addUpdateType(string memory updateType) internal {
        // Validate string length
        if (bytes(updateType).length == 0 || bytes(updateType).length > 64) {
            revert InvalidUpdateTypeString(updateType);
        }

        // Check for duplicates
        bytes32 typeHash = keccak256(bytes(updateType));
        if (_validUpdateTypes[typeHash]) {
            revert UpdateTypeAlreadyExists(updateType);
        }

        // Add the new type
        _validUpdateTypes[typeHash] = true;
        updateTypes.push(updateType);

        emit UpdateTypeAdded(updateType);
    }

    /// @notice Internal helper to add an authorized market
    /// @param market The market address to authorize
    function _addAuthorizedMarket(address market) internal {
        if (market == address(0)) {
            revert InvalidMarketAddress(market);
        }
        if (_authorizedMarkets[market]) {
            revert MarketAlreadyAuthorized(market);
        }

        _authorizedMarkets[market] = true;
        emit AuthorizedMarketAdded(market);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MUTATORS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc ILlamaGuardOracle
    function updateLatestRiskRoundData(UpdateInput calldata input) external onlyRole(WRITER_ROLE) {
        // Validate update type hash
        if (!_validUpdateTypes[input.updateTypeHash]) {
            revert UnauthorizedUpdateType(input.updateTypeHash);
        }

        // Get previous value from history (empty for first update)
        bytes memory previousValue = updateHistory[this.getLatestRoundId()].newValue;

        // Decode price from newValue and update round data for AggregatorV3 compatibility
        // newValue contains only the price (int256), while additionalData contains the full bundle
        {
            int256 price = abi.decode(input.newValue, (int256));
            _updateLatestRoundData(price);
        }

        // Get new roundId as updateId and store in history
        uint256 updateId = this.getLatestRoundId();

        // Store in history (market is set to address(0) for global updates)
        updateHistory[updateId] = RiskParameterUpdate({
            timestamp: block.timestamp,
            newValue: input.newValue,
            referenceId: input.referenceId,
            previousValue: previousValue,
            updateTypeHash: input.updateTypeHash,
            updateId: updateId,
            market: address(0),
            additionalData: input.additionalData
        });

        // Update the latest update index for this updateType
        _latestUpdateIdByType[input.updateTypeHash] = updateId;

        emit ParameterUpdated(
            input.referenceId,
            input.newValue,
            previousValue,
            block.timestamp,
            input.updateTypeHash,
            updateId,
            input.additionalData
        );
    }

    /// @inheritdoc ILlamaGuardOracle
    function addUpdateType(string calldata newUpdateType) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _addUpdateType(newUpdateType);
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
    function isValidUpdateType(string calldata updateType) external view returns (bool) {
        return _validUpdateTypes[keccak256(bytes(updateType))];
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

    /// @inheritdoc ILlamaGuardOracle
    function getLatestUpdateByParameterAndMarket(
        bytes32 updateTypeHash,
        address market
    )
        external
        view
        returns (RiskParameterUpdate memory)
    {
        return _getLatestUpdateByParameterAndMarket(updateTypeHash, market);
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
        uint256 updateId = _latestUpdateIdByType[updateTypeHash];

        // Strict validation: revert if no update exists
        if (updateId == 0) {
            revert InvalidUpdateId(updateId);
        }

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
        if (market == address(0)) {
            revert InvalidMarketAddress(market);
        }
        if (!_authorizedMarkets[market]) {
            revert MarketNotFound(market);
        }

        _authorizedMarkets[market] = false;
        emit AuthorizedMarketRemoved(market);
    }
}

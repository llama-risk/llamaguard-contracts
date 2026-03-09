// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ILlamaGuardOracle } from "../../src/interfaces/ILlamaGuardOracle.sol";

/**
 * @title MockLlamaGuardOracle
 * @notice Mock oracle implementing ILlamaGuardOracle for testing hub integration
 * @dev Implements ILlamaGuardOracle interface for testing with HorizonAgentHub
 */
contract MockLlamaGuardOracle is ILlamaGuardOracle {
    // ═══════════════════════════════════════════════════════════════════════════
    // STORAGE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Storage for updates by updateType hash (matches real oracle behavior)
    mapping(bytes32 updateTypeHash => RiskParameterUpdate) internal _latestUpdates;

    /// @notice Storage for updates by updateId
    mapping(uint256 => RiskParameterUpdate) internal _updatesById;

    /// @notice Current round ID (matches AggregatorV3 style)
    uint80 internal _roundId;

    /// @notice List of authorized update types
    string[] internal _updateTypes;
    mapping(bytes32 => bool) internal _isAuthorizedType;

    /// @notice Authorized markets
    mapping(address => bool) internal _authorizedMarkets;

    /// @notice Flag to control whether oracle should revert
    bool public shouldRevert;
    string public revertReason;

    /// @notice Flag to control whether oracle returns empty/invalid data
    bool public returnEmptyUpdate;

    // ═══════════════════════════════════════════════════════════════════════════
    // MARKET AUTHORIZATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc ILlamaGuardOracle
    function addAuthorizedMarket(address market) external override {
        require(market != address(0), InvalidMarketAddress(market));
        require(!_authorizedMarkets[market], MarketAlreadyAuthorized(market));

        _authorizedMarkets[market] = true;
        emit AuthorizedMarketAdded(market);
    }

    /// @inheritdoc ILlamaGuardOracle
    function removeAuthorizedMarket(address market) external override {
        require(_authorizedMarkets[market], MarketNotFound(market));

        _authorizedMarkets[market] = false;
        emit AuthorizedMarketRemoved(market);
    }

    /// @inheritdoc ILlamaGuardOracle
    function isAuthorizedMarket(address market) external view override returns (bool) {
        return _authorizedMarkets[market];
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UPDATE TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc ILlamaGuardOracle
    function addUpdateType(string calldata newUpdateType, uint256 expectedAdditionalDataLength) external override {
        bytes memory typeBytes = bytes(newUpdateType);
        require(typeBytes.length > 0 && typeBytes.length <= 64, InvalidUpdateTypeString(newUpdateType));

        bytes32 typeHash = keccak256(typeBytes);
        require(!_isAuthorizedType[typeHash], UpdateTypeAlreadyExists(newUpdateType));

        _isAuthorizedType[typeHash] = true;
        _updateTypes.push(newUpdateType);
        emit UpdateTypeAdded(newUpdateType, expectedAdditionalDataLength);
    }

    /// @inheritdoc ILlamaGuardOracle
    function isValidUpdateType(string calldata updateType) external view override returns (bool) {
        return _isAuthorizedType[keccak256(bytes(updateType))];
    }

    /// @inheritdoc ILlamaGuardOracle
    function getExpectedAdditionalDataLength(string calldata) external pure override returns (uint256) {
        return type(uint256).max; // Mock: no validation
    }

    /// @inheritdoc ILlamaGuardOracle
    function setExpectedAdditionalDataLength(string calldata, uint256) external override {
        // Mock: no-op
    }

    /// @inheritdoc ILlamaGuardOracle
    function removeUpdateType(string calldata updateType) external override {
        bytes32 typeHash = keccak256(bytes(updateType));
        require(_isAuthorizedType[typeHash], UpdateTypeNotFound(updateType));

        _isAuthorizedType[typeHash] = false;

        // Remove from array by swap-and-pop
        uint256 length = _updateTypes.length;
        for (uint256 i = 0; i < length; i++) {
            if (keccak256(bytes(_updateTypes[i])) == typeHash) {
                _updateTypes[i] = _updateTypes[length - 1];
                _updateTypes.pop();
                break;
            }
        }

        emit UpdateTypeRemoved(updateType);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DATA UPDATES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc ILlamaGuardOracle
    function updateLatestRiskRoundData(UpdateInput calldata input) external override {
        bytes32 typeHash = keccak256(bytes(input.updateType));
        require(_isAuthorizedType[typeHash], UnauthorizedUpdateType(input.updateType));

        ++_roundId;

        RiskParameterUpdate memory update = RiskParameterUpdate({
            timestamp: block.timestamp,
            newValue: input.newValue,
            referenceId: input.referenceId,
            previousValue: "",
            updateType: input.updateType,
            updateId: _roundId,
            market: address(0), // Market is rewritten in getLatestUpdateByParameterAndMarket
            additionalData: input.additionalData
        });

        _latestUpdates[typeHash] = update;
        _updatesById[_roundId] = update;

        emit ParameterUpdated(
            input.referenceId, input.newValue, "", block.timestamp, input.updateType, _roundId, input.additionalData
        );
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEWS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc ILlamaGuardOracle
    function getLatestUpdateByParameterAndMarket(
        string calldata updateType,
        address market
    )
        external
        view
        override
        returns (RiskParameterUpdate memory)
    {
        if (shouldRevert) {
            revert(revertReason);
        }

        if (returnEmptyUpdate) {
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

        bytes32 typeHash = keccak256(bytes(updateType));
        RiskParameterUpdate memory update = _latestUpdates[typeHash];

        // Rewrite market to the requested market (as per ILlamaGuardOracle behavior)
        update.market = market;

        return update;
    }

    /// @inheritdoc ILlamaGuardOracle
    function getUpdateById(uint256 updateId) external view override returns (RiskParameterUpdate memory) {
        if (shouldRevert) {
            revert(revertReason);
        }
        require(updateId > 0 && updateId <= _roundId, InvalidUpdateId(updateId));
        return _updatesById[updateId];
    }

    /// @inheritdoc ILlamaGuardOracle
    function hasWriteAccess(address) external pure override returns (bool) {
        // Mock always returns true - no actual role checking
        return true;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TEST HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Get the latest round ID (for test helpers)
    function getLatestRoundId() external view returns (uint80) {
        return _roundId;
    }

    /// @notice Set the update directly for testing (bypasses updateLatestRiskRoundData)
    function setUpdate(
        string memory updateType,
        address market,
        uint256 timestamp,
        bytes memory newValue,
        uint256 updateId,
        bytes memory additionalData
    )
        external
    {
        RiskParameterUpdate memory update = RiskParameterUpdate({
            timestamp: timestamp,
            newValue: newValue,
            referenceId: "test-ref",
            previousValue: "",
            updateType: updateType,
            updateId: updateId,
            market: market,
            additionalData: additionalData
        });

        bytes32 typeHash = keccak256(bytes(updateType));
        _latestUpdates[typeHash] = update;
        _updatesById[updateId] = update;

        if (updateId > _roundId) {
            _roundId = uint80(updateId);
        }
    }

    /// @notice Set whether the oracle should revert on queries
    function setShouldRevert(bool _shouldRevert, string memory _revertReason) external {
        shouldRevert = _shouldRevert;
        revertReason = _revertReason;
    }

    /// @notice Set whether to return empty update
    function setReturnEmptyUpdate(bool _returnEmpty) external {
        returnEmptyUpdate = _returnEmpty;
    }

    /// @notice Reset all state for clean testing
    function reset() external {
        _roundId = 0;
        shouldRevert = false;
        revertReason = "";
        returnEmptyUpdate = false;
    }
}

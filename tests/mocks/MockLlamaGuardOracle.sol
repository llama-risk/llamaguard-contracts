// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IRiskOracle } from "chaos-agents/contracts/dependencies/IRiskOracle.sol";

/**
 * @title MockLlamaGuardOracle
 * @notice Mock oracle implementing IRiskOracle for testing hub integration
 * @dev Implements IRiskOracle to be compatible with chaos-agents AgentHub
 */
contract MockLlamaGuardOracle is IRiskOracle {
    /// @notice Storage for updates by (updateType, market) key
    mapping(bytes32 => RiskParameterUpdate) internal _latestUpdates;

    /// @notice Storage for updates by updateId
    mapping(uint256 => RiskParameterUpdate) internal _updatesById;

    /// @notice Counter for update IDs
    uint256 public override updateCounter;

    /// @notice List of authorized update types
    string[] internal _updateTypes;
    mapping(bytes32 => bool) internal _isAuthorizedType;

    /// @notice List of authorized senders
    mapping(address => bool) internal _authorizedSenders;

    /// @notice Flag to control whether oracle should revert
    bool public shouldRevert;
    string public revertReason;

    /// @notice Flag to control whether oracle returns empty/invalid data
    bool public returnEmptyUpdate;

    /// @inheritdoc IRiskOracle
    function addAuthorizedSender(address sender) external override {
        _authorizedSenders[sender] = true;
        emit AuthorizedSenderAdded(sender);
    }

    /// @inheritdoc IRiskOracle
    function removeAuthorizedSender(address sender) external override {
        _authorizedSenders[sender] = false;
        emit AuthorizedSenderRemoved(sender);
    }

    /// @inheritdoc IRiskOracle
    function addUpdateType(string memory newUpdateType) external override {
        bytes32 typeHash = keccak256(bytes(newUpdateType));
        if (!_isAuthorizedType[typeHash]) {
            _isAuthorizedType[typeHash] = true;
            _updateTypes.push(newUpdateType);
            emit UpdateTypeAdded(newUpdateType);
        }
    }

    /// @inheritdoc IRiskOracle
    function publishRiskParameterUpdate(
        string memory referenceId,
        bytes memory newValue,
        string memory updateType,
        address market,
        bytes memory additionalData
    )
        external
        override
    {
        updateCounter++;

        RiskParameterUpdate memory update = RiskParameterUpdate({
            timestamp: block.timestamp,
            newValue: newValue,
            referenceId: referenceId,
            previousValue: "",
            updateType: updateType,
            updateId: updateCounter,
            market: market,
            additionalData: additionalData
        });

        bytes32 key = keccak256(abi.encode(updateType, market));
        _latestUpdates[key] = update;
        _updatesById[updateCounter] = update;

        emit ParameterUpdated(
            referenceId, newValue, "", block.timestamp, updateType, updateCounter, market, additionalData
        );
    }

    /// @inheritdoc IRiskOracle
    function publishBulkRiskParameterUpdates(
        string[] memory referenceIds,
        bytes[] memory newValues,
        string[] memory updateTypes,
        address[] memory markets,
        bytes[] memory additionalData
    )
        external
        override
    {
        for (uint256 i = 0; i < referenceIds.length; i++) {
            updateCounter++;

            RiskParameterUpdate memory update = RiskParameterUpdate({
                timestamp: block.timestamp,
                newValue: newValues[i],
                referenceId: referenceIds[i],
                previousValue: "",
                updateType: updateTypes[i],
                updateId: updateCounter,
                market: markets[i],
                additionalData: additionalData[i]
            });

            bytes32 key = keccak256(abi.encode(updateTypes[i], markets[i]));
            _latestUpdates[key] = update;
            _updatesById[updateCounter] = update;

            emit ParameterUpdated(
                referenceIds[i],
                newValues[i],
                "",
                block.timestamp,
                updateTypes[i],
                updateCounter,
                markets[i],
                additionalData[i]
            );
        }
    }

    /// @inheritdoc IRiskOracle
    function getAllUpdateTypes() external view override returns (string[] memory) {
        return _updateTypes;
    }

    /// @inheritdoc IRiskOracle
    function getLatestUpdateByParameterAndMarket(
        string memory updateType,
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

        bytes32 key = keccak256(abi.encode(updateType, market));
        RiskParameterUpdate memory update = _latestUpdates[key];

        // Rewrite market to the requested market (as per ILlamaGuardOracle behavior)
        update.market = market;

        return update;
    }

    /// @inheritdoc IRiskOracle
    function getUpdateById(uint256 updateId) external view override returns (RiskParameterUpdate memory) {
        if (shouldRevert) {
            revert(revertReason);
        }
        return _updatesById[updateId];
    }

    /// @inheritdoc IRiskOracle
    function isAuthorized(address sender) external view override returns (bool) {
        return _authorizedSenders[sender];
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TEST HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Set the update directly for testing (bypasses publishRiskParameterUpdate)
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

        bytes32 key = keccak256(abi.encode(updateType, market));
        _latestUpdates[key] = update;
        _updatesById[updateId] = update;

        if (updateId > updateCounter) {
            updateCounter = updateId;
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
        updateCounter = 0;
        shouldRevert = false;
        revertReason = "";
        returnEmptyUpdate = false;
    }
}

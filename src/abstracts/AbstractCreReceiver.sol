// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IReceiver } from "@chainlink/contracts/src/v0.8/keystone/interfaces/IReceiver.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title AbstractCreReceiver - Abstract receiver with workflow validation and metadata decoding
/// @notice Supports multiple workflows via a mapping from workflow ID to configuration
abstract contract AbstractCreReceiver is IReceiver {
    /// @notice Configuration for a workflow
    struct WorkflowConfig {
        address expectedForwarder;
        address expectedAuthor;
        bytes10 expectedWorkflowName;
        bool isActive;
    }

    /// @notice Mapping from workflow ID to its configuration
    mapping(bytes32 workflowId => WorkflowConfig) public workflowConfigs;

    /// @notice When true (default), enforce metadata/forwarder checks before processing.
    /// When false, skip validations and process the report directly.
    bool public isReportWriteSecured = true;

    // Custom errors
    error InvalidAuthor(address received, address expected);
    error InvalidWorkflowName(bytes10 received, bytes10 expected);
    error InvalidWorkflowId(bytes32 workflowId);
    error InvalidForwarder(address received, address expected);
    error WorkflowNotActive(bytes32 workflowId);

    // Events
    event WorkflowConfigUpdated(
        bytes32 indexed workflowId,
        address expectedForwarder,
        address expectedAuthor,
        bytes10 expectedWorkflowName,
        bool isActive
    );

    constructor(bytes32 workflowId, address expectedForwarder, address expectedAuthor, bytes10 expectedWorkflowName) {
        workflowConfigs[workflowId] = WorkflowConfig({
            expectedForwarder: expectedForwarder,
            expectedAuthor: expectedAuthor,
            expectedWorkflowName: expectedWorkflowName,
            isActive: true
        });

        emit WorkflowConfigUpdated(workflowId, expectedForwarder, expectedAuthor, expectedWorkflowName, true);
    }

    /// @inheritdoc IReceiver
    function onReport(bytes calldata metadata, bytes calldata report) external override {
        if (isReportWriteSecured) {
            (bytes32 workflowId, address workflowOwner, bytes10 workflowName) = _getWorkflowMetaData(metadata);

            WorkflowConfig storage config = workflowConfigs[workflowId];

            // Check if workflow exists and is active
            if (!config.isActive) {
                revert WorkflowNotActive(workflowId);
            }

            if (msg.sender != config.expectedForwarder) {
                revert InvalidForwarder(msg.sender, config.expectedForwarder);
            }

            if (workflowOwner != config.expectedAuthor) {
                revert InvalidAuthor(workflowOwner, config.expectedAuthor);
            }

            if (workflowName != config.expectedWorkflowName) {
                revert InvalidWorkflowName(workflowName, config.expectedWorkflowName);
            }
        }

        _processReport(report);
    }

    /// @notice Extracts the workflow name and the workflow owner from the metadata parameter of onReport
    /// @param metadata The metadata in bytes format
    /// @return workflowId The id of the workflow
    /// @return workflowOwner The owner of the workflow
    /// @return workflowName  The name of the workflow
    function _getWorkflowMetaData(bytes memory metadata)
        internal
        pure
        returns (bytes32 workflowId, address workflowOwner, bytes10 workflowName)
    {
        assembly {
            workflowId := mload(add(metadata, 32))
            workflowName := mload(add(metadata, 64))
            workflowOwner := shr(96, mload(add(metadata, 74)))
        }
    }

    /// @notice Get workflow configuration by ID
    /// @param workflowId The workflow ID to query
    /// @return config The workflow configuration
    function getWorkflowConfig(bytes32 workflowId) external view returns (WorkflowConfig memory) {
        return workflowConfigs[workflowId];
    }

    /// @notice Check if a workflow is active
    /// @param workflowId The workflow ID to check
    /// @return True if the workflow is active
    function isWorkflowActive(bytes32 workflowId) external view returns (bool) {
        return workflowConfigs[workflowId].isActive;
    }

    /// @notice Abstract function to process the report
    /// @param report The report calldata
    function _processReport(bytes calldata report) internal virtual;

    function supportsInterface(bytes4 interfaceId) public pure virtual override returns (bool) {
        return interfaceId == type(IReceiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}

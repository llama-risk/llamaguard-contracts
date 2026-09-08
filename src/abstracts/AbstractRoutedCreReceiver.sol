// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { IReceiver } from "@chainlink/contracts/src/v0.8/keystone/interfaces/IReceiver.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title AbstractRoutedCreReceiver
/// @notice Abstract receiver with workflow validation and metadata decoding.
/// @dev Fork of `./AbstractCreReceiver.sol` with the single change of
///      passing the validated `workflowId` through to `_processReport`. Downstream routers need the workflow
///      key to look up route configuration without re-decoding metadata.
abstract contract AbstractRoutedCreReceiver is IReceiver {
    struct WorkflowConfig {
        address expectedForwarder;
        address expectedAuthor;
        bytes10 expectedWorkflowName;
        bool isActive;
    }

    /// @notice Mapping from workflow ID to its configuration
    mapping(bytes32 workflowId => WorkflowConfig) public workflowConfigs;

    /// @notice Always enforce metadata/forwarder checks before processing.
    bool public constant isReportWriteSecured = true;

    error InvalidAuthor(address received, address expected);
    error InvalidWorkflowName(bytes10 received, bytes10 expected);
    error InvalidWorkflowId(bytes32 workflowId);
    error InvalidForwarder(address received, address expected);
    error WorkflowNotActive(bytes32 workflowId);

    event WorkflowConfigUpdated(
        bytes32 indexed workflowId,
        address expectedForwarder,
        address expectedAuthor,
        bytes10 expectedWorkflowName,
        bool isActive
    );

    /// @inheritdoc IReceiver
    function onReport(bytes calldata metadata, bytes calldata report) external override {
        (bytes32 workflowId, address workflowOwner, bytes10 workflowName) = _getWorkflowMetaData(metadata);

        if (isReportWriteSecured) {
            WorkflowConfig storage config = workflowConfigs[workflowId];

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

        _processReport(workflowId, report);
    }

    /// @notice Extracts the workflow id, owner, and name from the metadata payload.
    function _getWorkflowMetaData(bytes memory metadata)
        internal
        pure
        returns (bytes32 workflowId, address workflowOwner, bytes10 workflowName)
    {
        // Encoded layout:
        //   bytes32 workflowId           // offset 0
        //   bytes10 workflowName         // offset 32, occupies the high 10 bytes of word starting at 32
        //   address workflowOwner        // offset 42 (10 bytes after workflowName), 20 bytes
        // The reads below mirror the audited LlamaGuard receiver exactly.
        // solhint-disable-next-line no-inline-assembly
        assembly {
            workflowId := mload(add(metadata, 32))
            workflowName := mload(add(metadata, 64))
            workflowOwner := shr(96, mload(add(metadata, 74)))
        }
    }

    function getWorkflowConfig(bytes32 workflowId) external view returns (WorkflowConfig memory) {
        return workflowConfigs[workflowId];
    }

    function isWorkflowActive(bytes32 workflowId) external view returns (bool) {
        return workflowConfigs[workflowId].isActive;
    }

    /// @notice Process the validated report. Receives the workflow id so downstream
    ///         routers can dispatch without re-decoding metadata.
    function _processReport(bytes32 workflowId, bytes calldata report) internal virtual;

    function supportsInterface(bytes4 interfaceId) public pure virtual override returns (bool) {
        return interfaceId == type(IReceiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}

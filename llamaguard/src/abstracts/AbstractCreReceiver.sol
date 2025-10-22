// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IReceiver } from "@chainlink/contracts/src/v0.8/keystone/interfaces/IReceiver.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title IReceiverTemplate - Abstract receiver with workflow validation and metadata decoding
abstract contract AbstractCreReceiver is IReceiver {
    // Immutable expected values
    address public EXPECTED_AUTHOR;
    address public EXPECTED_FORWARDER;
    bytes10 public EXPECTED_WORKFLOW_NAME;
    bytes32 public EXPECTED_WORKFLOW_ID;

    /// @notice When true (default), enforce metadata/forwarder checks before processing.
    /// When false, skip validations and process the report directly.
    bool public isReportWriteSecured = true;

    // Custom errors
    error InvalidAuthor(address received, address expected);
    error InvalidWorkflowName(bytes10 received, bytes10 expected);
    error InvalidWorkflowId(bytes32 received, bytes32 expected);
    error InvalidForwarder(address received, address expected);

    constructor(
        address expectedAuthor,
        address expectedForwarder,
        bytes10 expectedWorkflowName,
        bytes32 expectedWorkflowId
    ) {
        EXPECTED_AUTHOR = expectedAuthor;
        EXPECTED_FORWARDER = expectedForwarder;
        EXPECTED_WORKFLOW_NAME = expectedWorkflowName;
        EXPECTED_WORKFLOW_ID = expectedWorkflowId;
    }

    /// @inheritdoc IReceiver
    // solhint-disable-next-line no-unused-vars
    function onReport(bytes calldata metadata, bytes calldata report) external override {
        if (isReportWriteSecured) {
            (bytes32 workflowId, address workflowOwner, bytes10 workflowName) = _getWorkflowMetaData(metadata);

            if (workflowId != EXPECTED_WORKFLOW_ID) {
                revert InvalidWorkflowId(workflowId, EXPECTED_WORKFLOW_ID);
            }

            if (msg.sender != EXPECTED_FORWARDER) {
                revert InvalidForwarder(msg.sender, EXPECTED_FORWARDER);
            }

            if (workflowOwner != EXPECTED_AUTHOR) {
                revert InvalidAuthor(workflowOwner, EXPECTED_AUTHOR);
            }
            if (workflowName != EXPECTED_WORKFLOW_NAME) {
                revert InvalidWorkflowName(workflowName, EXPECTED_WORKFLOW_NAME);
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

    /// @notice Abstract function to process the report
    /// @param report The report calldata
    function _processReport(bytes calldata report) internal virtual;

    function supportsInterface(bytes4 interfaceId) public pure virtual override returns (bool) {
        return interfaceId == type(IReceiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}

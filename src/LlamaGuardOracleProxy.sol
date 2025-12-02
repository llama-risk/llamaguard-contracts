// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ILlamaGuardOracle } from "./interfaces/ILlamaGuardOracle.sol";
import { AbstractCreReceiver } from "./abstracts/AbstractCreReceiver.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";

contract LlamaGuardOracleProxy is Ownable2Step, AbstractCreReceiver {
    ILlamaGuardOracle public llamaguardOracle;
    string public description;

    error InvalidLlamaGuardOracle();

    constructor(
        address llamaGuardOracleAddress,
        address expectedAuthor,
        address expectedForwarder,
        bytes10 expectedWorkflowName,
        bytes32 expectedWorkflowId,
        string memory _description
    )
        Ownable(msg.sender)
        AbstractCreReceiver(expectedAuthor, expectedForwarder, expectedWorkflowName, expectedWorkflowId)
    {
        if (llamaGuardOracleAddress == address(0)) revert InvalidLlamaGuardOracle();

        llamaguardOracle = ILlamaGuardOracle(llamaGuardOracleAddress);
        description = _description;
    }

    /// @inheritdoc AbstractCreReceiver
    function _processReport(bytes calldata report) internal override {
        // Decode the report to extract all parameters for the new updateData signature
        (string memory referenceId, bytes memory newValue, string memory updateType, bytes memory additionalData) =
            abi.decode(report, (string, bytes, string, bytes));

        llamaguardOracle.updateData(referenceId, newValue, updateType, additionalData);
    }

    function setLlamaGuardOracle(address newLlamaGuardOracle) external onlyOwner {
        ILlamaGuardOracle newLlamaguardOracle = ILlamaGuardOracle(newLlamaGuardOracle);
        if (newLlamaguardOracle.hasWriteAccess(address(this)) == false) revert InvalidLlamaGuardOracle();
        llamaguardOracle = newLlamaguardOracle;
    }

    function setIsReportWriteSecured(bool enabled) external onlyOwner {
        isReportWriteSecured = enabled;
    }

    /// @notice Set the expected author
    function setExpectedAuthor(address newExpectedAuthor) external onlyOwner {
        EXPECTED_AUTHOR = newExpectedAuthor;
    }

    /// @notice Set the expected forwarder
    function setExpectedForwarder(address newExpectedForwarder) external onlyOwner {
        EXPECTED_FORWARDER = newExpectedForwarder;
    }

    /// @notice Set the expected workflow name
    function setExpectedWorkflowName(bytes10 newExpectedWorkflowName) external onlyOwner {
        EXPECTED_WORKFLOW_NAME = newExpectedWorkflowName;
    }

    /// @notice Set the expected workflow ID
    function setExpectedWorkflowId(bytes32 newExpectedWorkflowId) external onlyOwner {
        EXPECTED_WORKFLOW_ID = newExpectedWorkflowId;
    }

    /// @notice Set all expected values at once
    function setExpectedValues(
        address newExpectedAuthor,
        address newExpectedForwarder,
        bytes10 newExpectedWorkflowName,
        bytes32 newExpectedWorkflowId
    )
        external
        onlyOwner
    {
        EXPECTED_AUTHOR = newExpectedAuthor;
        EXPECTED_FORWARDER = newExpectedForwarder;
        EXPECTED_WORKFLOW_NAME = newExpectedWorkflowName;
        EXPECTED_WORKFLOW_ID = newExpectedWorkflowId;
    }
}

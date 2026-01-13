// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { ILlamaGuardOracle } from "./interfaces/ILlamaGuardOracle.sol";
import { AbstractCreReceiver } from "./abstracts/AbstractCreReceiver.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";

contract LlamaGuardOracleProxy is Ownable2Step, AbstractCreReceiver {
    ILlamaGuardOracle public llamaguardOracle;
    string public description;

    error InvalidLlamaGuardOracle();

    constructor(
        address llamaGuardOracleAddress,
        bytes32 workflowId,
        address expectedForwarder,
        address expectedAuthor,
        bytes10 expectedWorkflowName,
        string memory _description
    )
        Ownable(msg.sender)
        AbstractCreReceiver(workflowId, expectedForwarder, expectedAuthor, expectedWorkflowName)
    {
        if (llamaGuardOracleAddress == address(0)) revert InvalidLlamaGuardOracle();

        llamaguardOracle = ILlamaGuardOracle(llamaGuardOracleAddress);
        description = _description;
    }

    /// @inheritdoc AbstractCreReceiver
    function _processReport(bytes calldata report) internal override {
        // Decode the report directly into UpdateInput struct
        ILlamaGuardOracle.UpdateInput memory input = abi.decode(report, (ILlamaGuardOracle.UpdateInput));

        llamaguardOracle.updateLatestRiskRoundData(input);
    }

    function setLlamaGuardOracle(address newLlamaGuardOracle) external onlyOwner {
        ILlamaGuardOracle newLlamaguardOracle = ILlamaGuardOracle(newLlamaGuardOracle);
        if (newLlamaguardOracle.hasWriteAccess(address(this)) == false) revert InvalidLlamaGuardOracle();
        llamaguardOracle = newLlamaguardOracle;
    }

    function setIsReportWriteSecured(bool enabled) external onlyOwner {
        isReportWriteSecured = enabled;
    }

    /// @notice Set or update workflow configuration
    /// @param workflowId The workflow ID to configure
    /// @param expectedForwarder The expected forwarder address
    /// @param expectedAuthor The expected author address
    /// @param expectedWorkflowName The expected workflow name
    /// @param isActive Whether the workflow is active
    function setWorkflowConfig(
        bytes32 workflowId,
        address expectedForwarder,
        address expectedAuthor,
        bytes10 expectedWorkflowName,
        bool isActive
    )
        external
        onlyOwner
    {
        workflowConfigs[workflowId] = WorkflowConfig({
            expectedForwarder: expectedForwarder,
            expectedAuthor: expectedAuthor,
            expectedWorkflowName: expectedWorkflowName,
            isActive: isActive
        });

        emit WorkflowConfigUpdated(workflowId, expectedForwarder, expectedAuthor, expectedWorkflowName, isActive);
    }

    /// @notice Activate or deactivate a workflow
    /// @param workflowId The workflow ID to update
    /// @param isActive Whether the workflow should be active
    function setWorkflowActive(bytes32 workflowId, bool isActive) external onlyOwner {
        WorkflowConfig storage config = workflowConfigs[workflowId];
        config.isActive = isActive;

        emit WorkflowConfigUpdated(
            workflowId, config.expectedForwarder, config.expectedAuthor, config.expectedWorkflowName, isActive
        );
    }
}

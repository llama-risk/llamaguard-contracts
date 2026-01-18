// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import { ILlamaGuardOracle } from "./interfaces/ILlamaGuardOracle.sol";
import { AbstractCreReceiver } from "./abstracts/AbstractCreReceiver.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title LlamaGuardOracleProxy
 * @notice Proxy contract that receives Chainlink CRE workflow reports and forwards them to LlamaGuardOracle
 * @dev Extends AbstractCreReceiver for workflow validation and Ownable2Step for secure ownership management.
 *      Acts as an intermediary between Chainlink CRE workflows and the LlamaGuardOracle, decoding incoming
 *      reports and calling updateLatestRiskRoundData on the oracle.
 */
contract LlamaGuardOracleProxy is Ownable2Step, AbstractCreReceiver {
    // ═══════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice The LlamaGuard oracle instance that receives decoded risk parameter updates
    ILlamaGuardOracle public llamaguardOracle;

    /// @notice Human-readable description of this proxy instance
    string public description;

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Thrown when the provided LlamaGuard oracle address is invalid or lacks write access for this proxy
    error InvalidLlamaGuardOracle();

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Initializes the proxy with oracle address and workflow configuration
     * @param llamaGuardOracleAddress Address of the LlamaGuardOracle contract (must be non-zero)
     * @param workflowId The Chainlink CRE workflow ID to accept reports from
     * @param expectedForwarder The expected forwarder address for workflow validation
     * @param expectedAuthor The expected author address for workflow validation
     * @param expectedWorkflowName The expected workflow name for validation
     * @param _description Human-readable description of this proxy instance
     */
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
        require(llamaGuardOracleAddress != address(0), InvalidLlamaGuardOracle());

        llamaguardOracle = ILlamaGuardOracle(llamaGuardOracleAddress);
        description = _description;
    }

    /// @inheritdoc AbstractCreReceiver
    function _processReport(bytes calldata report) internal override {
        // Decode the report directly into UpdateInput struct
        ILlamaGuardOracle.UpdateInput memory input = abi.decode(report, (ILlamaGuardOracle.UpdateInput));

        llamaguardOracle.updateLatestRiskRoundData(input);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ADMIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Updates the LlamaGuard oracle address
     * @dev The new oracle must grant WRITER_ROLE to this proxy before calling this function
     * @param newLlamaGuardOracle Address of the new LlamaGuardOracle contract
     */
    function setLlamaGuardOracle(address newLlamaGuardOracle) external onlyOwner {
        ILlamaGuardOracle newLlamaguardOracle = ILlamaGuardOracle(newLlamaGuardOracle);
        require(newLlamaguardOracle.hasWriteAccess(address(this)), InvalidLlamaGuardOracle());
        llamaguardOracle = newLlamaguardOracle;
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

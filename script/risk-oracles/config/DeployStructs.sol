// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

library DeployStructs {
    struct RegistryDeployConfig {
        address owner;
        address updater;
    }

    /// @dev If `initialWorkflowId == bytes32(0)`, the DeployAnyChain script skips the initial
    ///      `addRoute` call. The route can be added later via a separate transaction.
    struct RouterDeployConfig {
        address owner;
        address updater;
        bytes32 initialWorkflowId;
        address initialForwarder;
        address initialAuthor;
        bytes10 initialWorkflowName;
        address initialRiskOracle;
        bytes4 initialPublishSelector;
        address initialAgentHub;
        uint256[] initialAgentIds;
        // Replay-guard age for the optional initial route. 0 registers it unguarded (bare
        // payload); any value >= LlamaguardRiskOracleRouter.MIN_REPORT_AGE_SECONDS registers it
        // expecting the signed-timestamp envelope.
        uint64 initialMaxReportAgeSeconds;
    }
}

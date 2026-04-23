// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { LlamaGuardOracleProxy } from "../src/LlamaGuardOracleProxy.sol";
import { BaseScript } from "./Base.s.sol";
import { DeployStructs } from "./config/DeployStructs.sol";
import { CreConfig } from "./config/CreConfig.sol";
import { console2 } from "forge-std/console2.sol";

/// @title ConfigureCreWorkflow
/// @notice Stage 1a: Configure Chainlink CRE workflow details on deployed oracle proxies
/// @dev Called after Stage 1 once Chainlink provides the CRE workflow parameters.
///      Reads CRE config from CreConfig.sol (single source of truth).
///
///      The proxy was deployed in Stage 1 with placeholder (zero) CRE params.
///      This script sets the real workflow ID, forwarder, author, and workflow name.
contract ConfigureCreWorkflow is BaseScript {
    CreConfig internal creConfig;

    function setUp() public {
        creConfig = new CreConfig();
    }

    /// @notice Validate CRE workflow config for a single asset (dry-run, no state changes)
    /// @param assetName The asset name (e.g. "USTB", "USCC")
    function validate(string calldata assetName) public {
        creConfig = new CreConfig();
        DeployStructs.CreWorkflowConfig memory cfg = creConfig.getCreConfig(assetName);
        _printConfig(assetName, cfg);
    }

    /// @notice Configure CRE workflow for a single asset by name (mainnet)
    /// @param assetName The asset name (e.g. "USTB", "USCC")
    function run(string calldata assetName) public broadcast {
        require(block.chainid == 1, "Not on mainnet");
        _configureSingle(assetName);
    }

    /// @notice Configure CRE workflows for all assets (mainnet)
    function runAll() public broadcast {
        require(block.chainid == 1, "Not on mainnet");
        _configureAll();
    }

    /// @notice Configure single asset on any network (for testing)
    function runAnyNetwork(string calldata assetName) public broadcast {
        _configureSingle(assetName);
    }

    /// @notice Configure all assets on any network (for testing)
    function runAllAnyNetwork() public broadcast {
        _configureAll();
    }

    function _configureSingle(string memory assetName) internal {
        console2.log("=========================================");
        console2.log("Stage 1a: Configure CRE Workflow");
        console2.log("=========================================");

        DeployStructs.CreWorkflowConfig memory cfg = creConfig.getCreConfig(assetName);
        _applyConfig(assetName, cfg);

        console2.log("=========================================");
    }

    function _configureAll() internal {
        console2.log("=========================================");
        console2.log("Stage 1a: Configure All CRE Workflows");
        console2.log("=========================================");

        DeployStructs.CreWorkflowConfig[] memory configs = creConfig.getAllCreConfigs();
        string[6] memory names = ["USTB", "USCC", "USYC", "JTRSY", "JAAA", "ACRED"];

        uint256 configured;
        for (uint256 i = 0; i < configs.length; ++i) {
            if (configs[i].proxyAddress == address(0)) {
                console2.log("[SKIP]", names[i], "- proxy address not set");
                continue;
            }
            _applyConfig(names[i], configs[i]);
            configured++;
        }

        console2.log("");
        console2.log("Configured:", configured, "/ ", configs.length);
        console2.log("=========================================");
    }

    function _printConfig(string memory assetName, DeployStructs.CreWorkflowConfig memory cfg) internal view {
        require(cfg.proxyAddress != address(0), "Proxy address not set");
        require(cfg.workflowId != bytes32(0), "Workflow ID not set");
        require(cfg.expectedForwarder != address(0), "Forwarder not set");
        require(cfg.expectedAuthor != address(0), "Author not set");

        LlamaGuardOracleProxy proxy = LlamaGuardOracleProxy(cfg.proxyAddress);

        console2.log("");
        console2.log("-----------------------------------------");
        console2.log("Asset:          ", assetName);
        console2.log("Proxy:          ", cfg.proxyAddress);
        console2.log("Description:    ", proxy.description());
        console2.log("Workflow ID:    ", vm.toString(cfg.workflowId));
        console2.log("Forwarder:      ", cfg.expectedForwarder);
        console2.log("Author:         ", cfg.expectedAuthor);
        console2.log("Workflow Name:  ", vm.toString(cfg.expectedWorkflowName));
        console2.log("Activate:        true");
        console2.log("-----------------------------------------");
    }

    function _applyConfig(string memory assetName, DeployStructs.CreWorkflowConfig memory cfg) internal {
        _printConfig(assetName, cfg);

        LlamaGuardOracleProxy proxy = LlamaGuardOracleProxy(cfg.proxyAddress);

        proxy.setWorkflowConfig(
            cfg.workflowId, cfg.expectedForwarder, cfg.expectedAuthor, cfg.expectedWorkflowName, true
        );

        console2.log("  [OK] CRE workflow configured and activated");
    }
}

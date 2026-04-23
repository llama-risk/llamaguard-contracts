// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { HorizonAgentHub } from "../src/horizon-response/HorizonAgentHub.sol";
import { IAgentConfigurator } from "chaos-agents/interfaces/IAgentConfigurator.sol";
import { BaseScript } from "./Base.s.sol";
import { DeployStructs } from "./config/DeployStructs.sol";
import { MainnetConfig } from "./config/MainnetConfig.sol";
import { console2 } from "forge-std/console2.sol";

/// @title ActivateAllAssets
/// @notice Stage 4: Register remaining 5 assets in AgentHub
/// @dev For each of USCC, USYC, JTRSY, JAAA, ACRED:
///      1. Register FreezeAgent in AgentHub (same permissioned config as USTB)
///
///      Note: Chainlink separately switches their proxies
contract ActivateAllAssets is BaseScript {
    MainnetConfig internal config;

    function setUp() public {
        config = new MainnetConfig();
    }

    /// @notice Activate all remaining assets on mainnet
    /// @param agentHub The deployed HorizonAgentHub proxy address
    /// @param freezeAgent The deployed HorizonFreezeAgent address (shared across all assets)
    /// @param riskOracles Array of 5 LlamaGuardOracle addresses [USCC, USYC, JTRSY, JAAA, ACRED]
    /// @return agentIds Array of registered agent IDs
    function run(
        address agentHub,
        address freezeAgent,
        address[5] calldata riskOracles
    )
        public
        broadcast
        returns (uint256[] memory agentIds)
    {
        require(block.chainid == 1, "Not on mainnet");
        return _activateAll(agentHub, freezeAgent, riskOracles);
    }

    /// @notice Activate on any network (for testing)
    function runAnyNetwork(
        address agentHub,
        address freezeAgent,
        address[5] calldata riskOracles
    )
        public
        broadcast
        returns (uint256[] memory agentIds)
    {
        return _activateAll(agentHub, freezeAgent, riskOracles);
    }

    function _activateAll(
        address agentHub,
        address freezeAgent,
        address[5] calldata riskOracles
    )
        internal
        returns (uint256[] memory agentIds)
    {
        console2.log("=========================================");
        console2.log("Stage 4: Activate All Assets");
        console2.log("=========================================");
        console2.log("AgentHub:", agentHub);
        console2.log("FreezeAgent:", freezeAgent);
        console2.log("=========================================");

        string[5] memory assetNames = ["USCC", "USYC", "JTRSY", "JAAA", "ACRED"];

        HorizonAgentHub hub = HorizonAgentHub(agentHub);
        agentIds = new uint256[](5);

        for (uint256 i = 0; i < 5; ++i) {
            agentIds[i] = _registerSingleAsset(hub, freezeAgent, riskOracles[i], assetNames[i]);
        }

        _logSummary(assetNames, agentIds);
    }

    function _registerSingleAsset(
        HorizonAgentHub hub,
        address freezeAgent,
        address riskOracle,
        string memory assetName
    )
        internal
        returns (uint256 agentId)
    {
        console2.log("");
        console2.log("Registering:", assetName);

        DeployStructs.AgentRegistrationConfig memory agentConfig = config.getAgentConfig(assetName);
        agentConfig.agentAddress = freezeAgent;
        agentConfig.riskOracle = riskOracle;

        agentId = hub.registerAgent(
            IAgentConfigurator.AgentRegistrationInput({
                agentAddress: agentConfig.agentAddress,
                riskOracle: agentConfig.riskOracle,
                admin: agentConfig.admin,
                agentContext: abi.encode(agentConfig.poolConfigurator),
                isAgentEnabled: true,
                isAgentPermissioned: agentConfig.isAgentPermissioned,
                isMarketsFromAgentEnabled: false,
                expirationPeriod: agentConfig.expirationPeriod,
                minimumDelay: agentConfig.minimumDelay,
                updateType: agentConfig.updateType,
                allowedMarkets: agentConfig.allowedMarkets,
                restrictedMarkets: new address[](0),
                permissionedSenders: agentConfig.permissionedSenders
            })
        );

        console2.log("  [OK] Agent registered with ID:", agentId);
    }

    function _logSummary(string[5] memory assetNames, uint256[] memory agentIds) internal pure {
        console2.log("");
        console2.log("=========================================");
        console2.log("ACTIVATION SUMMARY");
        console2.log("=========================================");

        for (uint256 i = 0; i < 5; ++i) {
            console2.log(assetNames[i], "-> agentId:", agentIds[i]);
        }

        console2.log("");
        console2.log("NEXT: Run 5_TransferOwnership");
        console2.log("=========================================");
    }
}

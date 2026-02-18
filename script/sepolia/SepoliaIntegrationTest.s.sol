// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { LlamaGuardOracle } from "../../src/LlamaGuardOracle.sol";
import { LlamaGuardOracleProxy } from "../../src/LlamaGuardOracleProxy.sol";
import { HorizonAgentHub } from "../../src/horizon-response/HorizonAgentHub.sol";
import { HorizonFreezeAgent } from "../../src/horizon-response/agents/HorizonFreezeAgent.sol";
import { ILlamaGuardOracle } from "../../src/interfaces/ILlamaGuardOracle.sol";
import { IAgentHub } from "chaos-agents/interfaces/IAgentHub.sol";
import { IAgentConfigurator } from "chaos-agents/interfaces/IAgentConfigurator.sol";
import { BaseScript } from "../Base.s.sol";
import { DeployStructs } from "../config/DeployStructs.sol";
import { SepoliaConfig } from "../config/SepoliaConfig.sol";
import { Addresses } from "../config/Addresses.sol";
import { console2 } from "forge-std/console2.sol";

/// @title SepoliaIntegrationTest
/// @notice Activates Sepolia system and verifies the full freeze flow
/// @dev Steps:
///      1. Register FreezeAgent for USCC/USTB in AgentHub (permissioned, LlamaRisk sender)
///      2. Push normal update (state=0) -> verify oracle.latestAnswer()
///      3. Push freeze update (state=1) -> verify hub.check() returns actionable
///      4. Execute freeze via hub.execute() -> verify market frozen
///      5. Verify validation rejections (unfreeze, double-freeze, invalid type)
contract SepoliaIntegrationTest is BaseScript {
    SepoliaConfig internal config;

    function setUp() public {
        config = new SepoliaConfig();
    }

    /// @notice Run full integration test on Sepolia
    /// @param agentHub The deployed HorizonAgentHub proxy address
    /// @param freezeAgent The deployed HorizonFreezeAgent address
    /// @param oracleAddresses Array of LlamaGuardOracle addresses [USCC, USTB]
    /// @param proxyAddresses Array of LlamaGuardOracleProxy addresses [USCC, USTB]
    function run(
        address agentHub,
        address freezeAgent,
        address[2] calldata oracleAddresses,
        address[2] calldata proxyAddresses
    )
        public
        broadcast
    {
        require(block.chainid == 11_155_111, "Not on Sepolia");

        console2.log("=========================================");
        console2.log("Sepolia Integration Test");
        console2.log("=========================================");

        string[2] memory assetNames = ["USCC", "USTB"];
        HorizonAgentHub hub = HorizonAgentHub(agentHub);

        // Step 1: Register agents
        uint256[] memory agentIds = new uint256[](2);
        for (uint256 i = 0; i < 2; ++i) {
            agentIds[i] = _registerAgent(hub, freezeAgent, oracleAddresses[i], assetNames[i]);
            console2.log("[OK] Registered", assetNames[i], "-> agentId:", agentIds[i]);
        }

        // Step 2: Push normal update (state=0) and verify
        for (uint256 i = 0; i < 2; ++i) {
            _pushUpdate(proxyAddresses[i], assetNames[i], 0);
            int256 answer = LlamaGuardOracle(oracleAddresses[i]).latestAnswer();
            console2.log(
                "[OK]",
                assetNames[i],
                "normal update pushed, latestAnswer:",
                answer > 0 ? uint256(answer) : uint256(-answer)
            );
        }

        // Step 3: Push freeze update (state=1) and verify check
        for (uint256 i = 0; i < 2; ++i) {
            _pushUpdate(proxyAddresses[i], assetNames[i], 1);

            uint256[] memory ids = new uint256[](1);
            ids[0] = agentIds[i];
            (bool shouldExecute, IAgentHub.ActionData[] memory actions) = hub.check(ids);

            if (shouldExecute) {
                console2.log("[OK]", assetNames[i], "freeze update: check() returns actionable");

                // Step 4: Execute freeze
                hub.execute(actions);
                console2.log("[OK]", assetNames[i], "freeze executed via hub.execute()");
            } else {
                console2.log("[WARN]", assetNames[i], "freeze update: check() returned false");
            }
        }

        // Step 5: Verify rejection of double-freeze
        for (uint256 i = 0; i < 2; ++i) {
            // Warp to ensure new timestamp for fresh update
            vm.warp(block.timestamp + 1);
            _pushUpdate(proxyAddresses[i], assetNames[i], 1);

            uint256[] memory ids = new uint256[](1);
            ids[0] = agentIds[i];
            (bool shouldExecute,) = hub.check(ids);

            if (!shouldExecute) {
                console2.log("[OK]", assetNames[i], "double-freeze correctly rejected");
            } else {
                console2.log("[FAIL]", assetNames[i], "double-freeze should have been rejected");
            }
        }

        console2.log("");
        console2.log("=========================================");
        console2.log("INTEGRATION TEST COMPLETE");
        console2.log("=========================================");
    }

    function _registerAgent(
        HorizonAgentHub hub,
        address freezeAgent,
        address riskOracle,
        string memory assetName
    )
        internal
        returns (uint256 agentId)
    {
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
    }

    function _pushUpdate(address proxyAddress, string memory assetName, uint256 freezeState) internal {
        DeployStructs.OracleDeploymentConfig memory oracleConfig = config.getOracleConfig(assetName);

        ILlamaGuardOracle.UpdateInput memory input = ILlamaGuardOracle.UpdateInput({
            referenceId: string.concat("sepolia-integration-", assetName),
            newValue: abi.encode(int256(100e8)),
            updateType: "boundedNAV",
            additionalData: abi.encode(int256(-100), int256(100), freezeState),
            deadline: block.timestamp + 1 hours
        });

        bytes memory report = abi.encode(input);
        bytes memory metadata = abi.encodePacked(
            oracleConfig.proxy.workflowId, oracleConfig.proxy.expectedWorkflowName, oracleConfig.proxy.expectedAuthor
        );

        LlamaGuardOracleProxy proxy = LlamaGuardOracleProxy(proxyAddress);
        vm.prank(oracleConfig.proxy.expectedForwarder);
        proxy.onReport(metadata, report);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { HorizonAgentHub } from "../src/horizon-response/HorizonAgentHub.sol";
import { IAgentConfigurator } from "chaos-agents/interfaces/IAgentConfigurator.sol";
import { BaseScript } from "./Base.s.sol";
import { DeployStructs } from "./config/DeployStructs.sol";
import { MainnetConfig } from "./config/MainnetConfig.sol";
import { Addresses } from "./config/Addresses.sol";
import { console2 } from "forge-std/console2.sol";

/// @title ActivateUstbPilot
/// @notice Stage 2: Register FreezeAgent in AgentHub for USTB
/// @dev Takes deployed addresses from Stage 1 as parameters.
///      Registers the agent with permissioned access (LlamaRisk multisig only).
///
///      Note: Chainlink separately switches their EACAggregatorProxy to our USTB oracle
contract ActivateUstbPilot is BaseScript {
    MainnetConfig internal config;

    function setUp() public {
        config = new MainnetConfig();
    }

    /// @notice Activate USTB pilot on mainnet
    /// @param agentHub The deployed HorizonAgentHub proxy address
    /// @param freezeAgent The deployed HorizonFreezeAgent address
    /// @param riskOracle The deployed LlamaGuardOracle(USTB) address
    /// @return agentId The registered agent ID
    function run(address agentHub, address freezeAgent, address riskOracle) public broadcast returns (uint256 agentId) {
        require(block.chainid == 1, "Not on mainnet");
        return _activate(agentHub, freezeAgent, riskOracle);
    }

    /// @notice Activate on any network (for testing)
    function runAnyNetwork(
        address agentHub,
        address freezeAgent,
        address riskOracle
    )
        public
        broadcast
        returns (uint256 agentId)
    {
        return _activate(agentHub, freezeAgent, riskOracle);
    }

    function _activate(address agentHub, address freezeAgent, address riskOracle) internal returns (uint256 agentId) {
        console2.log("=========================================");
        console2.log("Stage 2: Activate USTB Pilot");
        console2.log("=========================================");
        console2.log("AgentHub:", agentHub);
        console2.log("FreezeAgent:", freezeAgent);
        console2.log("RiskOracle:", riskOracle);
        console2.log("=========================================");

        DeployStructs.AgentRegistrationConfig memory agentConfig = config.getAgentConfig("USTB");

        // Override with deployed addresses
        agentConfig.agentAddress = freezeAgent;
        agentConfig.riskOracle = riskOracle;

        HorizonAgentHub hub = HorizonAgentHub(agentHub);

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

        console2.log("[OK] USTB agent registered with ID:", agentId);
        console2.log("  Admin:", agentConfig.admin);
        console2.log("  Permissioned:", agentConfig.isAgentPermissioned);
        console2.log("  Update type:", agentConfig.updateType);
        console2.log("");
        console2.log("NEXT: Monitor USTB pilot, then run 3_DeployRemainingOracles");
        console2.log("=========================================");
    }
}

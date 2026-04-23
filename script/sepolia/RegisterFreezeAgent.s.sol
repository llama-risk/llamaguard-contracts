// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { HorizonAgentHub } from "../../src/horizon-response/HorizonAgentHub.sol";
import { IAgentConfigurator } from "chaos-agents/interfaces/IAgentConfigurator.sol";
import { BaseScript } from "../Base.s.sol";
import { Addresses } from "../config/Addresses.sol";
import { console2 } from "forge-std/console2.sol";

/// @title RegisterFreezeAgent
/// @notice Register the USTB HorizonFreezeAgent in the AgentHub on Sepolia
/// @dev Prerequisites:
///      - AgentHub (0x1DcD) must be owned by broadcaster
///      - FreezeAgent (0xC363) must already be deployed
///      - Horizon must grant RISK_ADMIN to FreezeAgent on ACL Manager (separate step)
contract RegisterFreezeAgent is BaseScript {
    /// @notice Register on Sepolia only
    function run() public broadcast returns (uint256 agentId) {
        require(block.chainid == 11_155_111, "Not on Sepolia");
        return _register();
    }

    /// @notice Register on any network (for testing)
    function runAnyNetwork() public broadcast returns (uint256 agentId) {
        return _register();
    }

    function _register() internal returns (uint256 agentId) {
        console2.log("=========================================");
        console2.log("Register FreezeAgent in AgentHub");
        console2.log("=========================================");
        console2.log("Chain ID:", block.chainid);
        console2.log("Broadcaster:", broadcaster);
        console2.log("=========================================");

        HorizonAgentHub hub = HorizonAgentHub(Addresses.SEPOLIA_HORIZON_AGENT_HUB);

        // Verify ownership
        require(hub.owner() == broadcaster, "Broadcaster is not AgentHub owner");
        console2.log("[OK] AgentHub owner verified");

        // USTB market
        address[] memory allowedMarkets = new address[](1);
        allowedMarkets[0] = Addresses.SEPOLIA_USTB;

        // Only hot wallet can call execute()
        address[] memory permissionedSenders = new address[](1);
        permissionedSenders[0] = Addresses.SEPOLIA_HOT_WALLET;

        agentId = hub.registerAgent(
            IAgentConfigurator.AgentRegistrationInput({
                agentAddress: Addresses.SEPOLIA_USTB_FREEZE_AGENT,
                riskOracle: Addresses.SEPOLIA_USTB_LLAMAGUARD_ORACLE,
                admin: Addresses.SEPOLIA_HOT_WALLET,
                agentContext: abi.encode(Addresses.SEPOLIA_AAVE_HORIZON_POOL_CONFIGURATOR),
                isAgentEnabled: true,
                isAgentPermissioned: true,
                isMarketsFromAgentEnabled: false,
                expirationPeriod: 1 days,
                minimumDelay: 0,
                updateType: "boundedNAV",
                allowedMarkets: allowedMarkets,
                restrictedMarkets: new address[](0),
                permissionedSenders: permissionedSenders
            })
        );
        console2.log("[OK] FreezeAgent registered, agentId:", agentId);

        _logSummary(agentId);
    }

    function _logSummary(uint256 agentId) internal pure {
        console2.log("");
        console2.log("=========================================");
        console2.log("REGISTRATION SUMMARY");
        console2.log("=========================================");
        console2.log("AgentHub:", Addresses.SEPOLIA_HORIZON_AGENT_HUB);
        console2.log("FreezeAgent:", Addresses.SEPOLIA_USTB_FREEZE_AGENT);
        console2.log("RiskOracle:", Addresses.SEPOLIA_USTB_LLAMAGUARD_ORACLE);
        console2.log("Agent ID:", agentId);
        console2.log("Admin:", Addresses.SEPOLIA_HOT_WALLET);
        console2.log("Permissioned sender:", Addresses.SEPOLIA_HOT_WALLET);
        console2.log("Market:", Addresses.SEPOLIA_USTB);
        console2.log("Pool Configurator:", Addresses.SEPOLIA_AAVE_HORIZON_POOL_CONFIGURATOR);
        console2.log("");
        console2.log("REMAINING STEPS:");
        console2.log("  1. Horizon grants RISK_ADMIN to FreezeAgent on ACL Manager");
        console2.log("     ACL Manager:", Addresses.SEPOLIA_AAVE_HORIZON_ACL_MANAGER);
        console2.log("=========================================");
    }
}

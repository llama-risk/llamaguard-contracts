// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { HorizonFreezeAgent } from "../../src/horizon-response/agents/HorizonFreezeAgent.sol";
import { BaseScript } from "../Base.s.sol";
import { Addresses } from "../config/Addresses.sol";
import { console2 } from "forge-std/console2.sol";

/// @title RedeployFreezeAgent
/// @notice Deploy a new HorizonFreezeAgent pointing to the redeployed Horizon Pool
/// @dev Horizon redeployed their Sepolia contracts, changing the Pool address.
///      The existing FreezeAgent has the old Pool as an immutable, so we redeploy.
///      Registration in AgentHub is a separate step (see RegisterFreezeAgent.s.sol).
contract RedeployFreezeAgent is BaseScript {
    /// @notice Deploy on Sepolia only
    function run() public broadcast returns (address freezeAgent) {
        require(block.chainid == 11_155_111, "Not on Sepolia");
        return _deploy();
    }

    /// @notice Deploy on any network (for testing)
    function runAnyNetwork() public broadcast returns (address freezeAgent) {
        return _deploy();
    }

    function _deploy() internal returns (address freezeAgent) {
        console2.log("=========================================");
        console2.log("Redeploy HorizonFreezeAgent");
        console2.log("=========================================");
        console2.log("Chain ID:", block.chainid);
        console2.log("Broadcaster:", broadcaster);
        console2.log("=========================================");

        HorizonFreezeAgent agent =
            new HorizonFreezeAgent(Addresses.SEPOLIA_HORIZON_AGENT_HUB, Addresses.SEPOLIA_AAVE_HORIZON_POOL);
        freezeAgent = address(agent);
        console2.log("[OK] HorizonFreezeAgent:", freezeAgent);

        _logSummary(freezeAgent);
    }

    function _logSummary(address freezeAgent) internal pure {
        console2.log("");
        console2.log("=========================================");
        console2.log("REDEPLOY SUMMARY");
        console2.log("=========================================");
        console2.log("New FreezeAgent:", freezeAgent);
        console2.log("AgentHub:", Addresses.SEPOLIA_HORIZON_AGENT_HUB);
        console2.log("Pool:", Addresses.SEPOLIA_AAVE_HORIZON_POOL);
        console2.log("");
        console2.log("REMAINING STEPS:");
        console2.log("  1. Update SEPOLIA_USTB_FREEZE_AGENT in Addresses.sol");
        console2.log("  2. Register in AgentHub via RegisterFreezeAgent.s.sol");
        console2.log("  3. Horizon grants RISK_ADMIN to new FreezeAgent on ACL Manager");
        console2.log("     ACL Manager:", Addresses.SEPOLIA_AAVE_HORIZON_ACL_MANAGER);
        console2.log("=========================================");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { AgentHub } from "chaos-agents/contracts/AgentHub.sol";
import { IPool } from "aave-v3-origin/src/contracts/interfaces/IPool.sol";
import { ShadowPool } from "../../../src/staging/ShadowPool.sol";
import { CapsConfig } from "./CapsConfig.sol";
import { CapsDeployment } from "./CapsDeployment.sol";
import { CapsScript } from "./CapsScript.sol";

/// @title DeployShadow
/// @notice Step 0, shadow deployments only: our own AgentHub and a ShadowPool in front of the real Pool. Every
///         later step points the caps stack at these two instead of Aave's.
///
///           CAPS_DEPLOYMENT=arbitrum-core-staging forge script script/risk-oracles/caps/0_DeployShadow.s.sol \
///             --rpc-url $ARBITRUM_RPC_URL --account <keystore> --sender "$ETH_FROM" [--broadcast --verify]
contract DeployShadow is CapsScript {
    function run() external {
        (string memory label, CapsConfig.Config memory config, CapsDeployment.Deployment memory deployment) = _context();
        _save(label, deployShadow(config, deployment, broadcaster));
    }

    function deployShadow(
        CapsConfig.Config memory config,
        CapsDeployment.Deployment memory deployment,
        address sender
    )
        public
        returns (CapsDeployment.Deployment memory)
    {
        require(config.market.shadow, "DeployShadow: not a shadow deployment");
        require(deployment.agentHub == address(0), "DeployShadow: already deployed");

        _begin(sender);
        deployment.agentHub = address(
            new ERC1967Proxy(address(new AgentHub()), abi.encodeCall(AgentHub.initialize, (config.roles.agentHubOwner)))
        );
        deployment.shadowPool = address(new ShadowPool(IPool(config.market.pool), config.roles.shadowPoolOwner));
        _end("Step 0: shadow AgentHub and ShadowPool");

        console2.log("AgentHub:  ", deployment.agentHub);
        console2.log("ShadowPool:", deployment.shadowPool);
        return deployment;
    }
}

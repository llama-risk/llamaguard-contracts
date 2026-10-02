// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { PlasmaCoreConfig } from "./PlasmaCoreConfig.sol";
import { SafeTx } from "../../ethereum/production/SafeTx.sol";
import { WirePlasmaCoreRoutesBase } from "./WirePlasmaCoreRoutesBase.sol";

/// @title WireAgentRoutes
/// @notice Phase 3b: the discount and risk-params routes. Runs AFTER the AIP and AFTER
///         `cre workflow deploy`; `requireTheAipLanded` checks the payload onchain first.
contract WireAgentRoutes is WirePlasmaCoreRoutesBase {
    function run() public view {
        PlasmaCoreConfig.validate(address(0));

        Context memory ctx = _context();
        requireTheAipLanded(ctx);

        console2.log("=============================================");
        console2.log("Plasma PT oracle activation - phase 3b");
        console2.log("=============================================");
        console2.log("Router:", ctx.router);
        console2.log("RiskOracle:", ctx.riskOracle);
        console2.log("AgentHub:", ctx.agentHub);
        console2.log("Discount agent id:", ctx.discountAgentId);
        console2.log("eMode agent id:", ctx.emodeAgentId);

        SafeTx.batch("phase 3b, register the agent routes", PlasmaCoreConfig.ROUTER_OWNER, agentCalls(ctx));
    }
}

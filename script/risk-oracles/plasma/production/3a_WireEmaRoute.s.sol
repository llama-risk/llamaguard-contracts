// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { PlasmaCoreConfig } from "./PlasmaCoreConfig.sol";
import { SafeTx } from "../../ethereum/production/SafeTx.sol";
import { WirePlasmaCoreRoutesBase } from "./WirePlasmaCoreRoutesBase.sol";

/// @title WireEmaRoute
/// @notice Phase 3a of the PT oracle activation on Plasma: the EMA route alone, wired without
///         waiting on the AIP.
/// @dev    The EMA workflow carries no `agentId` and writes to the per-asset LlamaGuardOracle
///         rather than through the AgentHub, so nothing about its route depends on registration.
///         Its workflow id is final as soon as `cre workflow deploy` runs.
///
///         Separate from phase 3b because the AIP checks belong only to the routes that inject.
///         Wiring the EMA leg first lets it accumulate: the discount and risk-params workflows
///         read the EMA and skip while it is stale, so a warm EMA is worth having before they go
///         live.
contract WireEmaRoute is WirePlasmaCoreRoutesBase {
    function run() public view {
        PlasmaCoreConfig.validate(address(0));

        Context memory ctx = _emaContext();

        console2.log("=============================================");
        console2.log("Plasma PT oracle activation - phase 3a");
        console2.log("=============================================");
        console2.log("Router:", ctx.router);
        console2.log("EMA oracle:", ctx.emaOracle);

        SafeTx.batch("phase 3a, register the EMA route", PlasmaCoreConfig.ROUTER_OWNER, emaCalls(ctx));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { PlasmaCoreConfig } from "./PlasmaCoreConfig.sol";
import { SafeTx } from "../../ethereum/production/SafeTx.sol";
import { WirePlasmaCoreRoutesBase } from "./WirePlasmaCoreRoutesBase.sol";

/// @title WireEmaRoute
/// @notice Phase 3a: the EMA route alone, wired without waiting on the AIP. Wiring it first lets
///         the EMA warm up before the routes that read it go live.
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

// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { EthereumCoreConfig } from "./EthereumCoreConfig.sol";
import { SafeTx } from "./SafeTx.sol";
import { WireEthereumCoreRoutesBase } from "./WireEthereumCoreRoutesBase.sol";

/// @title WireEmaRoute
/// @notice Phase 3a of the PT oracle activation: the EMA route alone, wired without waiting on the
///         AIP.
/// @dev    The EMA workflow carries no `agentId` and writes to the per-asset LlamaGuardOracle rather
///         than through the AgentHub, so nothing about its route depends on registration. Its
///         workflow id is final as soon as `cre workflow deploy` runs, while the other two ids stay
///         a prediction until the hub assigns the agent ids their configs carry.
///
///         Separate from phase 3b because the AIP checks belong only to the routes that inject.
///         Wiring the EMA leg first lets it accumulate: the discount and risk-params workflows read
///         the EMA and skip while it is stale, so a warm EMA is worth having before they go live.
contract WireEmaRoute is WireEthereumCoreRoutesBase {
    function run() public view {
        EthereumCoreConfig.validate(address(0));

        Context memory ctx = _emaContext();

        console2.log("=============================================");
        console2.log("Ethereum Core PT oracle activation - phase 3a");
        console2.log("=============================================");
        console2.log("Router:", ctx.router);
        console2.log("EMA oracle:", ctx.emaOracle);

        SafeTx.batch("phase 3a, register the EMA route", EthereumCoreConfig.ROUTER_OWNER, emaCalls(ctx));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { EthereumCoreConfig } from "./EthereumCoreConfig.sol";
import { SafeTx } from "./SafeTx.sol";
import { WireEthereumCoreRoutesBase } from "./WireEthereumCoreRoutesBase.sol";

/// @title WireAgentRoutes
/// @notice Phase 3b of the PT oracle activation: the discount and risk-params routes, after the AIP
///         has executed.
/// @dev    Runs AFTER the AIP and AFTER `cre workflow deploy`, because it needs both the agent ids
///         the hub assigned and the workflow ids CRE minted. Neither can be known earlier: ids come
///         from `agentCount++`, and a workflow id hashes the wasm together with the config, which
///         itself carries the agent id.
///
///         It also needs phase 1's handover to be complete. `acceptOwnership` is the last step of
///         phase 1, and until it lands the Router owner is still the deploy key, so this batch would
///         revert from the safe.
///
///         These are the routes that inject through the AgentHub, so `requireTheAipLanded` runs
///         first: every way the payload can be wrong fails silently once the routes are live.
contract WireAgentRoutes is WireEthereumCoreRoutesBase {
    function run() public view {
        EthereumCoreConfig.validate(address(0));

        Context memory ctx = _context();
        requireTheAipLanded(ctx);

        console2.log("=============================================");
        console2.log("Ethereum Core PT oracle activation - phase 3b");
        console2.log("=============================================");
        console2.log("Router:", ctx.router);
        console2.log("RiskOracle:", ctx.riskOracle);
        console2.log("AgentHub:", ctx.agentHub);
        console2.log("Discount agent id:", ctx.discountAgentId);
        console2.log("eMode agent id:", ctx.emodeAgentId);

        SafeTx.batch("phase 3b, register the agent routes", EthereumCoreConfig.ROUTER_OWNER, agentCalls(ctx));
    }
}

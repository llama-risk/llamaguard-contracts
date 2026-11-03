// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { MonadCoreConfig } from "./MonadCoreConfig.sol";
import { SafeTx } from "../../ethereum/production/SafeTx.sol";
import { WireMonadCoreRoutesBase } from "./WireMonadCoreRoutesBase.sol";

/// @title WireRoutes
/// @notice Phase 3: all three routes — EMA, discount and risk-params — in one batch, wired before
///         the AIP rather than around it.
/// @dev    Monad departs from the Ethereum and Plasma shape, which split this into 3a (EMA, early)
///         and 3b (agents, gated on `requireTheAipLanded`). Here every route is registered up front
///         and the stack then comes alive on its own as its dependencies land:
///
///         - `addRoute` does not require the agents to be registered. It checks only that
///           `riskOracle` has code and that a non-zero hub arrives with a non-empty `agentIds`, so
///           the agent routes register fine against ids the AIP has not assigned yet.
///         - Until the hub is deployed and the AIP registers the agents, the workflows read an
///           unregistered agent and skip. Nothing is published and nothing reverts.
///         - Once the AIP lands, the same routes start carrying injections with no second batch and
///           no further safe transaction.
///
///         What this trades away is `requireTheAipLanded`: the onchain assertion that the payload
///         did what it claimed. That check cannot run before the AIP exists, so it moves to a
///         post-AIP verification rather than being a precondition of wiring. Phase 3 therefore
///         asserts what it still can — the agent ids, which must be the ones the AIP will use.
contract WireRoutes is WireMonadCoreRoutesBase {
    function run() public view {
        MonadCoreConfig.validate(address(0));
        MonadCoreConfig.validateAgentDependencies();

        Context memory ctx = _context();

        console2.log("=============================================");
        console2.log("Monad PT oracle activation - phase 3");
        console2.log("=============================================");
        console2.log("Router:", ctx.router);
        console2.log("RiskOracle:", ctx.riskOracle);
        console2.log("EMA oracle:", ctx.emaOracle);
        console2.log("AgentHub:", ctx.agentHub);
        console2.log("Discount agent id:", ctx.discountAgentId);
        console2.log("eMode agent id:", ctx.emodeAgentId);
        console2.log("");

        SafeTx.batch("phase 3, register all routes", MonadCoreConfig.ROUTER_OWNER, allCalls(ctx));
    }

    /// @notice The EMA route followed by the two agent routes, as one batch of six calls.
    /// @dev    Order matters only in that the EMA route is registered first, keeping the warm-up
    ///         leg ahead of the routes that read it.
    function allCalls(Context memory ctx) public pure returns (SafeTx.Call[] memory calls) {
        SafeTx.Call[] memory ema = emaCalls(ctx);
        SafeTx.Call[] memory agents = agentCalls(ctx);

        calls = new SafeTx.Call[](ema.length + agents.length);
        for (uint256 i = 0; i < ema.length; i++) {
            calls[i] = ema[i];
        }
        for (uint256 i = 0; i < agents.length; i++) {
            calls[ema.length + i] = agents[i];
        }
    }

    function allCallsFromDeployed() public pure returns (SafeTx.Call[] memory) {
        return allCalls(_context());
    }
}

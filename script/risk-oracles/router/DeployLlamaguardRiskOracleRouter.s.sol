// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { BaseScript } from "../Base.s.sol";
import { LlamaguardRiskOracleRouter } from "../../../src/LlamaguardRiskOracleRouter.sol";

/// @notice Stand-alone router deploy. Owner defaults to broadcaster, updater is wired via a
///         follow-up `setUpdater` call (also from this script) so the router is fully usable
///         on exit.
contract DeployLlamaguardRiskOracleRouter is BaseScript {
    function run() public broadcast returns (LlamaguardRiskOracleRouter router) {
        address owner = vm.envOr({ name: "ROUTER_OWNER", defaultValue: broadcaster });
        address updater = vm.envOr({ name: "ROUTER_UPDATER", defaultValue: broadcaster });
        router = new LlamaguardRiskOracleRouter(owner);
        if (owner == broadcaster) {
            router.setUpdater(updater);
        }
    }
}

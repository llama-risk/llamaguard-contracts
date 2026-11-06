// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {
    IAaveV3ConfigEngine as IEngine
} from "aave-v3-origin/src/contracts/extensions/v3-config-engine/IAaveV3ConfigEngine.sol";
import { EngineFlags } from "aave-v3-origin/src/contracts/extensions/v3-config-engine/EngineFlags.sol";
import { MockPoolV3 } from "./MockPoolV3.sol";

/// @title MockCapsEngine
/// @notice Stand-in for the Aave V3 config engine `updateCaps` that `AaveBorrowCapAgent` and
///         `AaveSupplyCapAgent` delegatecall in `_processUpdate` (the engine address is the agent context).
///         It writes the caps on MockPoolV3 with no check, as `PoolConfigurator.setBorrowCap` and
///         `setSupplyCap` do. `KEEP_CURRENT` leaves a cap as it is.
/// @dev Runs in the agent's context by delegatecall, so it reads only its immutable `POOL` and no storage.
contract MockCapsEngine {
    MockPoolV3 public immutable POOL;

    constructor(MockPoolV3 pool) {
        POOL = pool;
    }

    function updateCaps(IEngine.CapsUpdate[] calldata updates) external {
        for (uint256 i = 0; i < updates.length; i++) {
            if (updates[i].borrowCap != EngineFlags.KEEP_CURRENT) {
                POOL.setBorrowCap(updates[i].asset, updates[i].borrowCap);
            }
            if (updates[i].supplyCap != EngineFlags.KEEP_CURRENT) {
                POOL.setSupplyCap(updates[i].asset, updates[i].supplyCap);
            }
        }
    }
}

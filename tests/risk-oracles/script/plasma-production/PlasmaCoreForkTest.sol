// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";

/// @title PlasmaCoreForkTest
/// @notice Shared setup for the Plasma production fork tests: two preconditions, both of which skip
///         rather than fail when unmet.
/// @dev    The first is an RPC, `PLASMA_RPC_URL`.
///
///         The second is the `fork` profile. The default profile pins `evm_version = "shanghai"` so
///         `src/` keeps compiling to the bytecode it has always compiled to, but Aave's live config
///         engine uses opcodes from a later fork. The `fork` profile exists to run these:
///
///           FOUNDRY_PROFILE=fork forge test --match-path "tests/risk-oracles/script/plasma-production/*"
abstract contract PlasmaCoreForkTest is Test {
    /// @notice The block these tests fork from.
    /// @dev    Pinned rather than latest: these assert how phase 3 wires itself, so the same commit
    ///         should not pass and fail on different days. The trade is that the Aave state read
    ///         here is frozen, so a guardian rotation would leave these green while
    ///         `ROUTER_GUARDIAN` went stale.
    uint256 internal constant FORK_BLOCK = 33_644_200;

    /// @notice True when both preconditions hold and the assertions in this folder mean something.
    bool internal forked;

    function _setUpFork() internal {
        if (!_isForkProfile()) return;

        string memory rpc = vm.envOr("PLASMA_RPC_URL", string(""));
        if (bytes(rpc).length == 0) return;

        vm.createSelectFork(rpc, FORK_BLOCK);
        forked = true;
    }

    function _skipUnlessForked() internal {
        if (!forked) {
            vm.skip(true);
        }
    }

    function _isForkProfile() private view returns (bool) {
        string memory profile = vm.envOr("FOUNDRY_PROFILE", string(""));
        return keccak256(bytes(profile)) == keccak256(bytes("fork"));
    }
}

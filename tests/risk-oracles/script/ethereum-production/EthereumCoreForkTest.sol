// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";

/// @title EthereumCoreForkTest
/// @notice Shared setup for the Ethereum Core production fork tests: two preconditions, both of
///         which skip rather than fail when unmet.
/// @dev    The first is an RPC, `MAINNET_RPC_URL`.
///
///         The second is the `fork` profile. The default profile pins `evm_version = "shanghai"` so
///         `src/` keeps compiling to the bytecode it has always compiled to, but Aave's live config
///         engine uses opcodes from a later fork, and under shanghai the injection path dies with
///         `NotActivated` well before it reaches anything this folder is trying to assert. The
///         `fork` profile exists to run these:
///
///           FOUNDRY_PROFILE=fork forge test --match-path "tests/script/ethereum-production/*"
///
///         Gating on the profile name rather than probing the EVM is deliberate. The obvious canary,
///         a read off the live Pool, answers the wrong question: `getEModeCategoryLabel` succeeds
///         under shanghai, and only the engine's internals fail, so a probe built on it reports the
///         EVM as new enough and the tests then fail anyway. A probe that is accurate would have to
///         execute a post-shanghai opcode from hand-written bytecode, which is more machinery than
///         one environment check deserves.
abstract contract EthereumCoreForkTest is Test {
    /// @notice The block these tests fork from.
    /// @dev    Pinned rather than latest: these assert what phase 1 deploys and how it wires itself,
    ///         so the same commit should not pass and fail on different days. The trade is that the
    ///         Aave state read here is frozen, so a guardian rotation would leave these green while
    ///         `ROUTER_GUARDIAN` went stale.
    uint256 internal constant FORK_BLOCK = 25_802_596;

    /// @notice True when both preconditions hold and the assertions in this folder mean something.
    bool internal forked;

    function _setUpFork() internal {
        if (!_isForkProfile()) return;

        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
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

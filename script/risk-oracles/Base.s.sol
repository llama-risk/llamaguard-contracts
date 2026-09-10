// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { Script } from "forge-std/Script.sol";

abstract contract BaseScript is Script {
    /// @dev Test mnemonic so the script compiles without a real $MNEMONIC.
    string internal constant TEST_MNEMONIC = "test test test test test test test test test test test junk";

    /// @dev The address of the transaction broadcaster.
    address internal broadcaster;

    /// @dev Derived only when $ETH_FROM is not set.
    string internal mnemonic;

    constructor() {
        address from = vm.envOr({ name: "ETH_FROM", defaultValue: address(0) });
        if (from != address(0)) {
            broadcaster = from;
        } else {
            mnemonic = vm.envOr({ name: "MNEMONIC", defaultValue: TEST_MNEMONIC });
            (broadcaster,) = deriveRememberKey({ mnemonic: mnemonic, index: 0 });
        }
    }

    modifier broadcast() {
        vm.startBroadcast(broadcaster);
        _;
        vm.stopBroadcast();
    }
}

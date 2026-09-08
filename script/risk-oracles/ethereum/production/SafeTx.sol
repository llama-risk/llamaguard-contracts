// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

/// @title SafeTx
/// @notice Prints the calls the deployer cannot make, in a shape that can be pasted straight into
///         the Safe transaction builder.
/// @dev    Some calls in this deployment cannot originate from the deployer EOA, because the
///         contract in question is owned by a safe or by the Aave Executor rather than by the deploy
///         key. In phase 1 that is exactly one call, `router.acceptOwnership()`: the Router is handed
///         over with `Ownable2Step`, and only the incoming owner can complete it.
///
///         Rather than leave such calls as prose in a runbook, each script encodes them and prints
///         them here. The encoding is therefore produced by the same constants the deploy used, and
///         the fork test executes the very array the script returns, so the batch that reaches the
///         safe cannot disagree with the stack that was deployed.
///
///         Every call is `value: 0`. None of these functions is payable.
library SafeTx {
    struct Call {
        /// @dev Human label, printed above the call so a signer can tell the entries apart.
        string label;
        address to;
        bytes data;
    }

    function call(string memory label, address to, bytes memory data) internal pure returns (Call memory) {
        return Call({ label: label, to: to, data: data });
    }

    /// @notice Prints a whole batch under one heading.
    /// @param title What this batch achieves, so the runbook step and the printed block match.
    /// @param signer The safe expected to execute it. Printed rather than enforced: nothing here
    ///        sends a transaction, so this is a label for the operator, not a guard.
    function batch(string memory title, address signer, Call[] memory calls) internal pure {
        console2.log("");
        console2.log("---------------------------------------------------------------");
        console2.log("SAFE BATCH:", title);
        console2.log("  execute from:", signer);
        console2.log("  calls:", calls.length);
        console2.log("---------------------------------------------------------------");
        for (uint256 i = 0; i < calls.length; i++) {
            _one(calls[i], i + 1);
        }
        console2.log("");
    }

    function _one(Call memory c, uint256 position) private pure {
        console2.log("");
        console2.log(string.concat("  [", Strings.toString(position), "] "), c.label);
        console2.log("      to    :", c.to);
        console2.log("      value : 0");
        console2.log("      data  :");
        console2.logBytes(c.data);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title MockSafe
/// @notice Minimal Safe stand-in that can delegatecall a target, for the CapsBorrowForwarder tests. A real
///         Safe runs `execTransaction(..., operation = DelegateCall)`; this mock exposes the same effect
///         with no signatures. Anyone can call it, since it is a test helper.
/// @dev It has one storage slot (`nonce`), which `execDelegatecall` increments. The CapsBorrowForwarder must
///      not write any other slot (CAP-ACL-13), and tests can compare storage before and after.
contract MockSafe {
    uint256 public nonce;

    /// @notice Delegatecall `target` with `data`. Bubbles up a revert with the original return data.
    function execDelegatecall(address target, bytes calldata data) external returns (bytes memory ret) {
        nonce++;
        bool ok;
        (ok, ret) = target.delegatecall(data);
        if (!ok) {
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }
    }

    /// @notice Plain call, for setup steps that must come from the Safe address (for example
    ///         `RVM.setRateLimitConfig` as the Risk Council).
    function execCall(address target, bytes calldata data) external returns (bytes memory ret) {
        nonce++;
        bool ok;
        (ok, ret) = target.call(data);
        if (!ok) {
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }
    }
}

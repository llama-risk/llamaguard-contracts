// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

/// @notice Test sink that captures any incoming call. Optionally reverts on demand.
contract MockRiskOracleSink {
    bool public shouldRevert;
    bytes public revertReason;
    bytes public lastCalldata;
    bytes4 public lastSelector;
    uint256 public callCount;

    function setShouldRevert(bool flag, bytes calldata reason) external {
        shouldRevert = flag;
        revertReason = reason;
    }

    fallback() external payable {
        if (shouldRevert) {
            bytes memory r = revertReason;
            // solhint-disable-next-line no-inline-assembly
            assembly {
                revert(add(r, 32), mload(r))
            }
        }
        lastCalldata = msg.data;
        lastSelector = msg.sig;
        callCount += 1;
    }

    receive() external payable { }
}

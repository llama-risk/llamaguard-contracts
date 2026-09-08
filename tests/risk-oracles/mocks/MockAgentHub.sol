// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { IAgentHub } from "../../../src/interfaces/IAgentHub.sol";

/// @notice Test double for AgentHub. Lets a test program the (shouldExecute, actions) tuple
///         returned by `check()` and capture / fail `execute()` calls.
contract MockAgentHub is IAgentHub {
    bool public checkShouldExecute;
    ActionData[] internal _checkActions;
    bool public checkShouldRevert;
    bytes public checkRevertReason;

    bool public executeShouldRevert;
    bytes public executeRevertReason;
    uint256 public executeCallCount;
    ActionData[] internal _lastExecuteActions;

    /// @notice Program the `check()` return value. `actions` is copied to storage so a single
    ///         call to `setCheckReturn` can be reused across multiple `check()` invocations.
    function setCheckReturn(bool shouldExecute, ActionData[] memory actions) external {
        checkShouldExecute = shouldExecute;
        delete _checkActions;
        for (uint256 i; i < actions.length; i++) {
            _checkActions.push(actions[i]);
        }
    }

    function setCheckShouldRevert(bool flag, bytes calldata reason) external {
        checkShouldRevert = flag;
        checkRevertReason = reason;
    }

    function setExecuteShouldRevert(bool flag, bytes calldata reason) external {
        executeShouldRevert = flag;
        executeRevertReason = reason;
    }

    function check(uint256[] memory) external view override returns (bool shouldExecute, ActionData[] memory actions) {
        if (checkShouldRevert) {
            bytes memory r = checkRevertReason;
            // solhint-disable-next-line no-inline-assembly
            assembly {
                revert(add(r, 32), mload(r))
            }
        }
        actions = new ActionData[](_checkActions.length);
        for (uint256 i; i < _checkActions.length; i++) {
            actions[i] = _checkActions[i];
        }
        return (checkShouldExecute, actions);
    }

    function execute(ActionData[] memory actions) external override {
        if (executeShouldRevert) {
            bytes memory r = executeRevertReason;
            // solhint-disable-next-line no-inline-assembly
            assembly {
                revert(add(r, 32), mload(r))
            }
        }
        delete _lastExecuteActions;
        for (uint256 i; i < actions.length; i++) {
            _lastExecuteActions.push(actions[i]);
        }
        executeCallCount += 1;
    }

    function lastExecuteActionCount() external view returns (uint256) {
        return _lastExecuteActions.length;
    }

    function lastExecuteAgentId(uint256 i) external view returns (uint256) {
        return _lastExecuteActions[i].agentId;
    }
}

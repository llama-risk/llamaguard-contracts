// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { VmSafe } from "forge-std/Vm.sol";
import { BaseScript } from "../Base.s.sol";
import { SafeTx } from "../ethereum/production/SafeTx.sol";
import { CapsConfig } from "./CapsConfig.sol";
import { CapsDeployment } from "./CapsDeployment.sol";

/// @title CapsScript
/// @notice Shared by the caps deployment steps. Each step's `run` works on the deployment named by
///         `$CAPS_DEPLOYMENT`; its core function takes the config and deployment explicitly, so a fork test runs it
///         without files.
/// @dev Send or print: a call whose signer is the broadcaster is sent; any other is printed at the end as a Safe
///      batch per signer, in order. On staging the broadcaster holds every role, so everything is sent; on
///      production the same steps print what the Safes and the AIP must execute.
abstract contract CapsScript is BaseScript {
    struct Pending {
        address signer;
        SafeTx.Call call;
    }

    address private _sender;
    Pending[] private _pending;

    /// @dev The deployment named by `$CAPS_DEPLOYMENT`: its config and the deployment so far. Checks the chain and
    ///      that the broadcaster is the configured deployer.
    function _context()
        internal
        view
        returns (string memory label, CapsConfig.Config memory config, CapsDeployment.Deployment memory deployment)
    {
        label = vm.envString("CAPS_DEPLOYMENT");
        config = CapsConfig.load(label);
        require(block.chainid == config.market.chainId, "CapsScript: wrong chain");
        require(broadcaster == config.roles.deployer, "CapsScript: broadcaster is not the configured deployer");
        deployment = CapsDeployment.read(label);
    }

    /// @dev Starts sending as `sender`.
    function _begin(address sender) internal {
        _sender = sender;
        delete _pending;
        vm.startBroadcast(sender);
    }

    /// @dev Stops sending and prints what the broadcaster could not send.
    function _end(string memory title) internal {
        vm.stopBroadcast();
        for (uint256 i; i < _pending.length; ++i) {
            address signer = _pending[i].signer;
            if (_printedBefore(i, signer)) continue;
            SafeTx.batch(title, signer, _callsOf(signer));
        }
    }

    /// @dev Sends `data` to `target` when the broadcaster is `signer`, and returns the result; otherwise queues it.
    function _call(
        string memory label,
        address signer,
        address target,
        bytes memory data
    )
        internal
        returns (bool sent, bytes memory result)
    {
        if (signer != _sender) {
            _pending.push(Pending({ signer: signer, call: SafeTx.call(label, target, data) }));
            return (false, "");
        }
        bool ok;
        (ok, result) = target.call(data);
        if (!ok) {
            assembly ("memory-safe") {
                revert(add(result, 32), mload(result))
            }
        }
        sent = true;
    }

    /// @dev The Pool the caps stack reads: the ShadowPool on a shadow deployment, else the real Pool.
    function _stackPool(
        CapsConfig.Market memory market,
        CapsDeployment.Deployment memory deployment
    )
        internal
        pure
        returns (address)
    {
        return market.shadow ? deployment.shadowPool : market.pool;
    }

    function _agentHub(
        CapsConfig.Market memory market,
        CapsDeployment.Deployment memory deployment
    )
        internal
        pure
        returns (address)
    {
        return market.shadow ? deployment.agentHub : market.agentHub;
    }

    /// @dev Where the agents write caps: the ShadowPool on a shadow deployment, else Aave's config engine.
    function _agentContext(
        CapsConfig.Market memory market,
        CapsDeployment.Deployment memory deployment
    )
        internal
        pure
        returns (address)
    {
        return market.shadow ? deployment.shadowPool : market.configEngine;
    }

    /// @dev Writes the deployment file on a real broadcast only: dry-run addresses are simulated.
    function _save(string memory label, CapsDeployment.Deployment memory deployment) internal {
        bool broadcasting =
            vm.isContext(VmSafe.ForgeContext.ScriptBroadcast) || vm.isContext(VmSafe.ForgeContext.ScriptResume);
        if (broadcasting) {
            CapsDeployment.write(label, deployment);
            console2.log("Deployment written:", CapsDeployment.path(label));
        } else {
            console2.log("Dry run: the addresses above are simulated and the deployment file is unchanged.");
        }
    }

    function _printedBefore(uint256 index, address signer) private view returns (bool) {
        for (uint256 i; i < index; ++i) {
            if (_pending[i].signer == signer) return true;
        }
        return false;
    }

    function _callsOf(address signer) private view returns (SafeTx.Call[] memory calls) {
        uint256 count;
        for (uint256 i; i < _pending.length; ++i) {
            if (_pending[i].signer == signer) ++count;
        }
        calls = new SafeTx.Call[](count);
        count = 0;
        for (uint256 i; i < _pending.length; ++i) {
            if (_pending[i].signer == signer) calls[count++] = _pending[i].call;
        }
    }
}

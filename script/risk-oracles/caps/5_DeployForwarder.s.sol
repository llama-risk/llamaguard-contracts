// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { CapsBorrowForwarder } from "../../../src/caps-oracle/CapsBorrowForwarder.sol";
import { CapsConfig } from "./CapsConfig.sol";
import { CapsDeployment } from "./CapsDeployment.sol";
import { CapsScript } from "./CapsScript.sol";

/// @title DeployForwarder
/// @notice Step 5, production only: the CapsBorrowForwarder on the real Pool, owned by `forwarder.owner` with
///         `forwarder.caller` allowed. It needs RISK_ADMIN, which the activation AIP grants.
/// @dev Usage:
///        CAPS_DEPLOYMENT=<label> forge script script/risk-oracles/caps/5_DeployForwarder.s.sol \
///          --rpc-url "$ARBITRUM_RPC_URL" --account <keystore> --sender "$ETH_FROM" --broadcast --verify
contract DeployForwarder is CapsScript {
    function run() external {
        (string memory label, CapsConfig.Config memory config, CapsDeployment.Deployment memory deployment) = _context();
        _save(label, deployForwarder(config, CapsConfig.loadForwarder(label), deployment, broadcaster));
    }

    function deployForwarder(
        CapsConfig.Config memory config,
        CapsConfig.Forwarder memory forwarder,
        CapsDeployment.Deployment memory deployment,
        address sender
    )
        public
        returns (CapsDeployment.Deployment memory)
    {
        require(!config.market.shadow, "DeployForwarder: production only");
        require(deployment.rvm != address(0), "DeployForwarder: run step 1 first");
        require(deployment.forwarder == address(0), "DeployForwarder: already deployed");

        _begin(sender);
        deployment.forwarder = address(
            new CapsBorrowForwarder(
                forwarder.owner,
                config.market.pool,
                config.market.configEngine,
                deployment.rvm,
                forwarder.caller,
                forwarder.maxRaiseBuffers,
                forwarder.minRaiseDelay
            )
        );
        _end("Step 5: forwarder");

        console2.log("Forwarder:", deployment.forwarder);
        return deployment;
    }
}

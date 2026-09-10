// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { LlamaGuardOracle } from "llamaguard-contracts/src/LlamaGuardOracle.sol";
import { LlamaGuardOracleProxy } from "llamaguard-contracts/src/LlamaGuardOracleProxy.sol";
import { PTEmaConfig } from "../config/PTEmaConfig.sol";

/// @notice Shared deploy logic for the PT EMA oracle pipeline. Both the
///         standalone `DeployPTEmaOracle.s.sol` script and the multi-chain
///         `DeployAnyChain.s.sol` dispatcher delegate here so there is a
///         single source of truth for the deploy sequence and its invariants.
library PTEmaDeployer {
    struct Deployed {
        address oracle;
        address oracleProxy;
    }

    /// @notice Thrown when a CRE workflow parameter required for the
    ///         receiver-proxy to function is left at its zero default.
    error MissingWorkflowParam(string param);

    /// @notice Deploys the PT EMA oracle and its CRE receiver-proxy, then
    ///         grants `WRITER_ROLE` to the receiver-proxy when the broadcaster
    ///         currently holds admin on the oracle.
    /// @param cfg          Resolved per-chain deploy configuration.
    /// @param broadcaster  The address `vm.startBroadcast` is running under.
    ///                     Used to decide whether the script can grant
    ///                     `WRITER_ROLE` inline or must defer to the multisig.
    function deploy(
        PTEmaConfig.PTEmaDeployConfig memory cfg,
        address broadcaster
    )
        internal
        returns (Deployed memory deployed)
    {
        _assertWorkflowConfigured(cfg);

        LlamaGuardOracle oracle = new LlamaGuardOracle(
            cfg.oracleDecimals,
            cfg.oracleDescription,
            cfg.oracleVersion,
            cfg.initialUpdateTypes,
            cfg.initialAuthorizedMarkets
        );
        console2.log("[OK] LlamaGuardOracle:", address(oracle));

        LlamaGuardOracleProxy receiverProxy = new LlamaGuardOracleProxy(
            address(oracle),
            cfg.emaWorkflowId,
            cfg.emaWorkflowForwarder,
            cfg.emaWorkflowAuthor,
            cfg.emaWorkflowName,
            cfg.proxyDescription
        );
        console2.log("[OK] LlamaGuardOracleProxy:", address(receiverProxy));

        if (cfg.owner == address(0) || cfg.owner == broadcaster) {
            oracle.grantRole(oracle.WRITER_ROLE(), address(receiverProxy));
            require(oracle.hasWriteAccess(address(receiverProxy)), "PTEmaDeployer: WRITER_ROLE not granted");
            console2.log("[OK] WRITER_ROLE granted to LlamaGuardOracleProxy");
        } else {
            console2.log(
                "PTEmaDeployer: owner != broadcaster; WRITER_ROLE grant SKIPPED."
                " Owner must call oracle.grantRole(WRITER_ROLE, receiverProxy)"
            );
        }

        deployed = Deployed({ oracle: address(oracle), oracleProxy: address(receiverProxy) });
    }

    function _assertWorkflowConfigured(PTEmaConfig.PTEmaDeployConfig memory cfg) private pure {
        if (cfg.emaWorkflowForwarder == address(0)) revert MissingWorkflowParam("emaWorkflowForwarder");
        if (cfg.emaWorkflowAuthor == address(0)) revert MissingWorkflowParam("emaWorkflowAuthor");
        if (cfg.emaWorkflowName == bytes10(0)) revert MissingWorkflowParam("emaWorkflowName");
    }
}

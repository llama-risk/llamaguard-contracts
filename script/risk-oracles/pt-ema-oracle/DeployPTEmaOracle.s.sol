// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { BaseScript } from "../Base.s.sol";
import { Addresses } from "../config/Addresses.sol";
import { PTEmaConfig } from "../config/PTEmaConfig.sol";
import { PTEmaDeployer } from "./PTEmaDeployer.sol";

/// @notice Deploys the PT EMA on-chain oracle pipeline on the current chain
///         via the shared `PTEmaDeployer` library.
contract DeployPTEmaOracle is BaseScript {
    error UnsupportedChain(uint256 chainId);

    struct Deployed {
        address oracle;
        address oracleProxy;
    }

    function run() public broadcast returns (Deployed memory deployed) {
        PTEmaConfig.PTEmaDeployConfig memory cfg = _resolveConfig();

        console2.log("=========================================");
        console2.log("Deploy PT EMA Oracle");
        console2.log("=========================================");
        console2.log("Chain ID:", block.chainid);
        console2.log("Broadcaster:", broadcaster);
        console2.log("Owner (configured):", cfg.owner);
        console2.log("=========================================");

        PTEmaDeployer.Deployed memory d = PTEmaDeployer.deploy(cfg, broadcaster);

        deployed = Deployed({ oracle: d.oracle, oracleProxy: d.oracleProxy });

        console2.log("");
        console2.log("=========================================");
        console2.log("DEPLOY SUMMARY (PT EMA)");
        console2.log("=========================================");
        console2.log("LlamaGuardOracle:        ", deployed.oracle);
        console2.log("LlamaGuardOracleProxy:   ", deployed.oracleProxy);
        console2.log("=========================================");
    }

    /// @dev Exposed as `internal` so tests can re-use the dispatch without
    ///      going through `run()` (which starts a broadcast).
    function _resolveConfig() internal view returns (PTEmaConfig.PTEmaDeployConfig memory) {
        uint256 chainId = block.chainid;
        if (chainId == Addresses.PLASMA) {
            return PTEmaConfig.getPlasmaConfig();
        }
        if (chainId == Addresses.SEPOLIA) {
            return PTEmaConfig.getSepoliaConfig(broadcaster);
        }
        revert UnsupportedChain(chainId);
    }
}

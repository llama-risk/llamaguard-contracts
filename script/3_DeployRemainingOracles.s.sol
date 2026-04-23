// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { LlamaGuardOracle } from "../src/LlamaGuardOracle.sol";
import { LlamaGuardOracleProxy } from "../src/LlamaGuardOracleProxy.sol";
import { BaseScript } from "./Base.s.sol";
import { DeployStructs } from "./config/DeployStructs.sol";
import { MainnetConfig } from "./config/MainnetConfig.sol";
import { Addresses } from "./config/Addresses.sol";
import { console2 } from "forge-std/console2.sol";

/// @title DeployRemainingOracles
/// @notice Stage 3: Deploy oracle infrastructure for remaining 5 assets
/// @dev For each of USCC, USYC, JTRSY, JAAA, ACRED:
///      1. Deploy LlamaGuardOracle
///      2. Deploy LlamaGuardOracleProxy
///      3. Grant WRITER_ROLE to proxy on oracle
///      4. Add token as authorized market
contract DeployRemainingOracles is BaseScript {
    MainnetConfig internal config;

    struct OracleDeployment {
        string name;
        address oracle;
        address proxy;
    }

    function setUp() public {
        config = new MainnetConfig();
    }

    /// @notice Deploy all remaining oracles on mainnet
    function run() public broadcast returns (OracleDeployment[] memory deployments) {
        require(block.chainid == 1, "Not on mainnet");
        return _deployAll();
    }

    /// @notice Deploy on any network (for testing)
    function runAnyNetwork() public broadcast returns (OracleDeployment[] memory deployments) {
        return _deployAll();
    }

    function _deployAll() internal returns (OracleDeployment[] memory deployments) {
        console2.log("=========================================");
        console2.log("Stage 3: Deploy Remaining Oracles");
        console2.log("=========================================");
        console2.log("Chain ID:", block.chainid);
        console2.log("Broadcaster:", broadcaster);
        console2.log("=========================================");

        string[5] memory assetNames = ["USCC", "USYC", "JTRSY", "JAAA", "ACRED"];

        address[5] memory tokenAddresses =
            [Addresses.USCC, Addresses.USYC, Addresses.JTRSY, Addresses.JAAA, Addresses.ACRED];

        deployments = new OracleDeployment[](5);

        for (uint256 i = 0; i < 5; ++i) {
            deployments[i] = _deploySingleOracle(assetNames[i], tokenAddresses[i]);
        }

        _logSummary(deployments);
    }

    function _deploySingleOracle(
        string memory assetName,
        address tokenAddress
    )
        internal
        returns (OracleDeployment memory deployment)
    {
        console2.log("");
        console2.log("-----------------------------------------");
        console2.log("Deploying:", assetName);
        console2.log("-----------------------------------------");

        DeployStructs.OracleDeploymentConfig memory oracleConfig = config.getOracleConfig(assetName);

        // 1. Deploy LlamaGuardOracle
        LlamaGuardOracle oracle = new LlamaGuardOracle(
            oracleConfig.oracle.decimals,
            oracleConfig.oracle.description,
            oracleConfig.oracle.version,
            oracleConfig.oracle.updateTypes,
            oracleConfig.oracle.authorizedMarkets
        );
        console2.log("  [OK] LlamaGuardOracle:", address(oracle));

        // 2. Deploy LlamaGuardOracleProxy
        LlamaGuardOracleProxy proxy = new LlamaGuardOracleProxy(
            address(oracle),
            oracleConfig.proxy.workflowId,
            oracleConfig.proxy.expectedForwarder,
            oracleConfig.proxy.expectedAuthor,
            oracleConfig.proxy.expectedWorkflowName,
            oracleConfig.proxy.description
        );
        console2.log("  [OK] LlamaGuardOracleProxy:", address(proxy));

        // 3. Grant WRITER_ROLE to proxy
        oracle.grantRole(oracle.WRITER_ROLE(), address(proxy));
        require(oracle.hasWriteAccess(address(proxy)), "WRITER_ROLE not granted");
        console2.log("  [OK] WRITER_ROLE granted");

        // 4. Add token as authorized market
        if (tokenAddress != address(0)) {
            oracle.addAuthorizedMarket(tokenAddress);
            require(oracle.isAuthorizedMarket(tokenAddress), "Market not authorized");
            console2.log("  [OK] Token authorized as market");
        } else {
            console2.log("  [SKIP] Token address is zero, market not added");
        }

        deployment = OracleDeployment({ name: assetName, oracle: address(oracle), proxy: address(proxy) });
    }

    function _logSummary(OracleDeployment[] memory deployments) internal pure {
        console2.log("");
        console2.log("=========================================");
        console2.log("DEPLOYMENT SUMMARY");
        console2.log("=========================================");

        for (uint256 i = 0; i < deployments.length; ++i) {
            console2.log("");
            console2.log(deployments[i].name);
            console2.log("  Oracle:", deployments[i].oracle);
            console2.log("  Proxy:", deployments[i].proxy);
        }

        console2.log("");
        console2.log("NEXT: Run 4_ActivateAllAssets with these addresses");
        console2.log("=========================================");
    }
}

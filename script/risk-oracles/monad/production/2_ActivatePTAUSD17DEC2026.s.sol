// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { BaseScript } from "../../Base.s.sol";
import { PTParameterRegistry } from "../../../../src/PTParameterRegistry.sol";
import { LlamaGuardOracle } from "llamaguard-contracts/src/LlamaGuardOracle.sol";
import { MonadCoreConfig } from "./MonadCoreConfig.sol";
import { MonadCoreDeployed } from "./MonadCoreDeployed.sol";
import { PTAUSD17DEC2026 } from "./assets/PTAUSD17DEC2026.sol";
import { SafeTx } from "../../ethereum/production/SafeTx.sol";

/// @title ActivatePTAUSD17DEC2026
/// @notice Phase 2: deploys the per-asset EMA oracle, grants the Router `WRITER_ROLE`, hands
///         admin to the safe, and prints the registry write. Needs no governance. Mirror of
///         `ActivatePTsrUSDe22OCT2026`, which documents the reasoning (including why
///         `maxPriceDeviation` is not set here).
/// @dev    Runnable before the PT reserve is listed on Aave: the EMA oracle reads the Pendle market,
///         not the Aave reserve, and the registry write only names the PT address. The discount
///         adapter (`PTAUSD17DEC2026.PT_PRICE_ADAPTER`) is the listing AIP's to deploy and is not
///         touched here.
contract ActivatePTAUSD17DEC2026 is BaseScript {
    struct Deployment {
        address emaOracle;
    }

    function run() public broadcast returns (Deployment memory deployed) {
        MonadCoreConfig.validate(broadcaster);

        address router = MonadCoreDeployed.ROUTER;
        address registry = MonadCoreDeployed.PT_PARAMETER_REGISTRY;
        require(router != address(0), "ActivatePTAUSD17DEC2026: MonadCoreDeployed.ROUTER unset");
        require(registry != address(0), "ActivatePTAUSD17DEC2026: MonadCoreDeployed.PT_PARAMETER_REGISTRY unset");

        console2.log("=============================================");
        console2.log("Monad PT oracle activation - phase 2");
        console2.log("=============================================");
        console2.log("Asset:", PTAUSD17DEC2026.PT_ASSET);
        console2.log("Pendle market:", PTAUSD17DEC2026.PENDLE_MARKET);
        console2.log("Router:", router);
        console2.log("Registry:", registry);

        deployed = deploy(broadcaster, router, MonadCoreConfig.acl());

        _logSummary(deployed);
        _printSafeBatch(registry, MonadCoreConfig.acl());
    }

    function deploy(
        address deployer,
        address router,
        MonadCoreConfig.Acl memory acl
    )
        public
        returns (Deployment memory deployed)
    {
        LlamaGuardOracle emaOracle = _deployOracle();
        deployed.emaOracle = address(emaOracle);

        _wirePermissions(emaOracle, router, acl);
        _handOver(emaOracle, deployer, acl);
        _verify(emaOracle, router, deployer, acl);
    }

    function _deployOracle() internal returns (LlamaGuardOracle) {
        string[] memory updateTypes = new string[](1);
        updateTypes[0] = MonadCoreConfig.TYPE_EMA;

        return new LlamaGuardOracle(
            PTAUSD17DEC2026.EMA_ORACLE_DECIMALS,
            PTAUSD17DEC2026.EMA_ORACLE_DESCRIPTION,
            PTAUSD17DEC2026.EMA_ORACLE_VERSION,
            updateTypes,
            PTAUSD17DEC2026.emaAuthorizedMarkets()
        );
    }

    function _wirePermissions(LlamaGuardOracle emaOracle, address router, MonadCoreConfig.Acl memory acl) internal {
        require(router != address(0), "ActivatePTAUSD17DEC2026: router is zero");
        emaOracle.grantRole(emaOracle.WRITER_ROLE(), router);
        for (uint256 i = 0; i < acl.extraEmaOracleWriters.length; i++) {
            emaOracle.grantRole(emaOracle.WRITER_ROLE(), acl.extraEmaOracleWriters[i]);
        }
    }

    /// @dev Grant then renounce, never the other way round.
    function _handOver(LlamaGuardOracle emaOracle, address deployer, MonadCoreConfig.Acl memory acl) internal {
        require(acl.emaOracleAdmin != address(0), "ActivatePTAUSD17DEC2026: emaOracleAdmin is zero");
        if (acl.emaOracleAdmin == deployer) return;

        bytes32 adminRole = emaOracle.DEFAULT_ADMIN_ROLE();
        emaOracle.grantRole(adminRole, acl.emaOracleAdmin);
        require(emaOracle.hasRole(adminRole, acl.emaOracleAdmin), "ActivatePTAUSD17DEC2026: admin grant did not take");
        emaOracle.renounceRole(adminRole, deployer);
    }

    function _verify(
        LlamaGuardOracle emaOracle,
        address router,
        address deployer,
        MonadCoreConfig.Acl memory acl
    )
        internal
        view
    {
        bytes32 adminRole = emaOracle.DEFAULT_ADMIN_ROLE();
        bytes32 writerRole = emaOracle.WRITER_ROLE();

        require(emaOracle.hasRole(writerRole, router), "ActivatePTAUSD17DEC2026: Router missing WRITER_ROLE");
        require(emaOracle.hasRole(adminRole, acl.emaOracleAdmin), "ActivatePTAUSD17DEC2026: admin not held by safe");
        require(
            acl.emaOracleAdmin == deployer || !emaOracle.hasRole(adminRole, deployer),
            "ActivatePTAUSD17DEC2026: deployer still admin"
        );
        require(!emaOracle.hasRole(writerRole, deployer), "ActivatePTAUSD17DEC2026: deployer holds WRITER_ROLE");
    }

    function _logSummary(Deployment memory deployed) internal pure {
        console2.log("");
        console2.log("--- phase 2 deployed, paste into MonadCoreDeployed.sol ---");
        console2.log("OUTPUT:EMA_ORACLE_PT_AUSD_17DEC2026=%s", deployed.emaOracle);
    }

    /// @dev Until this registry write lands, all three workflows read an unconfigured market and
    ///      publish nothing.
    function _printSafeBatch(address registry, MonadCoreConfig.Acl memory acl) internal pure {
        SafeTx.Call[] memory calls = new SafeTx.Call[](1);
        calls[0] = SafeTx.call(
            "registry.setPtMarketParams(PT-AUSD-17DEC2026)",
            registry,
            abi.encodeCall(
                PTParameterRegistry.setPtMarketParams, (PTAUSD17DEC2026.PT_ASSET, PTAUSD17DEC2026.ptMarketParams())
            )
        );
        SafeTx.batch("phase 2, register the asset", acl.registryUpdater, calls);
    }
}

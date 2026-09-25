// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { BaseScript } from "../../Base.s.sol";
import { PTParameterRegistry } from "../../../../src/PTParameterRegistry.sol";
import { LlamaGuardOracle } from "llamaguard-contracts/src/LlamaGuardOracle.sol";
import { PlasmaCoreConfig } from "./PlasmaCoreConfig.sol";
import { PlasmaCoreDeployed } from "./PlasmaCoreDeployed.sol";
import { PTsUSDe22OCT2026 } from "./assets/PTsUSDe22OCT2026.sol";
import { SafeTx } from "../../ethereum/production/SafeTx.sol";

/// @title ActivatePTsUSDe22OCT2026
/// @notice Phase 2: deploys the per-asset EMA oracle, grants the Router `WRITER_ROLE`, hands
///         admin to the safe, and prints the registry write. Needs no governance. Mirror of
///         `ActivatePTsrUSDe22OCT2026`, which documents the reasoning (including why
///         `maxPriceDeviation` is not set here).
contract ActivatePTsUSDe22OCT2026 is BaseScript {
    struct Deployment {
        address emaOracle;
    }

    function run() public broadcast returns (Deployment memory deployed) {
        PlasmaCoreConfig.validate(broadcaster);

        address router = PlasmaCoreDeployed.ROUTER;
        address registry = PlasmaCoreDeployed.PT_PARAMETER_REGISTRY;
        require(router != address(0), "ActivatePTsUSDe22OCT2026: PlasmaCoreDeployed.ROUTER unset");
        require(registry != address(0), "ActivatePTsUSDe22OCT2026: PlasmaCoreDeployed.PT_PARAMETER_REGISTRY unset");

        console2.log("=============================================");
        console2.log("Plasma PT oracle activation - phase 2");
        console2.log("=============================================");
        console2.log("Asset:", PTsUSDe22OCT2026.PT_ASSET);
        console2.log("Router:", router);
        console2.log("Registry:", registry);

        deployed = deploy(broadcaster, router, PlasmaCoreConfig.acl());

        _logSummary(deployed);
        _printSafeBatch(registry, PlasmaCoreConfig.acl());
    }

    function deploy(
        address deployer,
        address router,
        PlasmaCoreConfig.Acl memory acl
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
        updateTypes[0] = PlasmaCoreConfig.TYPE_EMA;

        return new LlamaGuardOracle(
            PTsUSDe22OCT2026.EMA_ORACLE_DECIMALS,
            PTsUSDe22OCT2026.EMA_ORACLE_DESCRIPTION,
            PTsUSDe22OCT2026.EMA_ORACLE_VERSION,
            updateTypes,
            PTsUSDe22OCT2026.emaAuthorizedMarkets()
        );
    }

    function _wirePermissions(LlamaGuardOracle emaOracle, address router, PlasmaCoreConfig.Acl memory acl) internal {
        require(router != address(0), "ActivatePTsUSDe22OCT2026: router is zero");
        emaOracle.grantRole(emaOracle.WRITER_ROLE(), router);
        for (uint256 i = 0; i < acl.extraEmaOracleWriters.length; i++) {
            emaOracle.grantRole(emaOracle.WRITER_ROLE(), acl.extraEmaOracleWriters[i]);
        }
    }

    /// @dev Grant then renounce, never the other way round.
    function _handOver(LlamaGuardOracle emaOracle, address deployer, PlasmaCoreConfig.Acl memory acl) internal {
        require(acl.emaOracleAdmin != address(0), "ActivatePTsUSDe22OCT2026: emaOracleAdmin is zero");
        if (acl.emaOracleAdmin == deployer) return;

        bytes32 adminRole = emaOracle.DEFAULT_ADMIN_ROLE();
        emaOracle.grantRole(adminRole, acl.emaOracleAdmin);
        require(emaOracle.hasRole(adminRole, acl.emaOracleAdmin), "ActivatePTsUSDe22OCT2026: admin grant did not take");
        emaOracle.renounceRole(adminRole, deployer);
    }

    function _verify(
        LlamaGuardOracle emaOracle,
        address router,
        address deployer,
        PlasmaCoreConfig.Acl memory acl
    )
        internal
        view
    {
        bytes32 adminRole = emaOracle.DEFAULT_ADMIN_ROLE();
        bytes32 writerRole = emaOracle.WRITER_ROLE();

        require(emaOracle.hasRole(writerRole, router), "ActivatePTsUSDe22OCT2026: Router missing WRITER_ROLE");
        require(emaOracle.hasRole(adminRole, acl.emaOracleAdmin), "ActivatePTsUSDe22OCT2026: admin not held by safe");
        require(
            acl.emaOracleAdmin == deployer || !emaOracle.hasRole(adminRole, deployer),
            "ActivatePTsUSDe22OCT2026: deployer still admin"
        );
        require(!emaOracle.hasRole(writerRole, deployer), "ActivatePTsUSDe22OCT2026: deployer holds WRITER_ROLE");
    }

    function _logSummary(Deployment memory deployed) internal pure {
        console2.log("");
        console2.log("--- phase 2 deployed, paste into PlasmaCoreDeployed.sol ---");
        console2.log("OUTPUT:EMA_ORACLE_PT_SUSDE_22OCT2026=%s", deployed.emaOracle);
    }

    /// @dev Until this registry write lands, all three workflows read an unconfigured market and
    ///      publish nothing.
    function _printSafeBatch(address registry, PlasmaCoreConfig.Acl memory acl) internal pure {
        SafeTx.Call[] memory calls = new SafeTx.Call[](1);
        calls[0] = SafeTx.call(
            "registry.setPtMarketParams(PT-sUSDe-22OCT2026)",
            registry,
            abi.encodeCall(
                PTParameterRegistry.setPtMarketParams, (PTsUSDe22OCT2026.PT_ASSET, PTsUSDe22OCT2026.ptMarketParams())
            )
        );
        SafeTx.batch("phase 2, register the asset", acl.registryUpdater, calls);
    }
}

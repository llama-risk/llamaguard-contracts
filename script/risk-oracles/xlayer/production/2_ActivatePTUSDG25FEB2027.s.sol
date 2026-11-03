// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { BaseScript } from "../../Base.s.sol";
import { PTParameterRegistry } from "../../../../src/PTParameterRegistry.sol";
import { LlamaGuardOracle } from "llamaguard-contracts/src/LlamaGuardOracle.sol";
import { XLayerCoreConfig } from "./XLayerCoreConfig.sol";
import { XLayerCoreDeployed } from "./XLayerCoreDeployed.sol";
import { PTUSDG25FEB2027 } from "./assets/PTUSDG25FEB2027.sol";
import { SafeTx } from "../../ethereum/production/SafeTx.sol";

/// @title ActivatePTUSDG25FEB2027
/// @notice Phase 2: deploys the per-asset EMA oracle, grants the Router `WRITER_ROLE`, hands
///         admin to the safe, and prints the registry write. Needs no governance. Mirror of
///         `ActivatePTsrUSDe22OCT2026`, which documents the reasoning (including why
///         `maxPriceDeviation` is not set here).
/// @dev    Runnable before the PT reserve is listed on Aave: the EMA oracle reads the Pendle market,
///         not the Aave reserve, and the registry write only names the PT address. The discount
///         adapter is the listing AIP's to deploy; it is not touched here, and `PTUSDG25FEB2027`
///         does not record it until it exists.
contract ActivatePTUSDG25FEB2027 is BaseScript {
    struct Deployment {
        address emaOracle;
    }

    function run() public broadcast returns (Deployment memory deployed) {
        XLayerCoreConfig.validate(broadcaster);

        address router = XLayerCoreDeployed.ROUTER;
        address registry = XLayerCoreDeployed.PT_PARAMETER_REGISTRY;
        require(router != address(0), "ActivatePTUSDG25FEB2027: XLayerCoreDeployed.ROUTER unset");
        require(registry != address(0), "ActivatePTUSDG25FEB2027: XLayerCoreDeployed.PT_PARAMETER_REGISTRY unset");

        console2.log("=============================================");
        console2.log("X Layer PT oracle activation - phase 2");
        console2.log("=============================================");
        console2.log("Asset:", PTUSDG25FEB2027.PT_ASSET);
        console2.log("Pendle market:", PTUSDG25FEB2027.PENDLE_MARKET);
        console2.log("Router:", router);
        console2.log("Registry:", registry);

        deployed = deploy(broadcaster, router, XLayerCoreConfig.acl());

        _logSummary(deployed);
        _printSafeBatch(registry, XLayerCoreConfig.acl());
    }

    function deploy(
        address deployer,
        address router,
        XLayerCoreConfig.Acl memory acl
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
        updateTypes[0] = XLayerCoreConfig.TYPE_EMA;

        return new LlamaGuardOracle(
            PTUSDG25FEB2027.EMA_ORACLE_DECIMALS,
            PTUSDG25FEB2027.EMA_ORACLE_DESCRIPTION,
            PTUSDG25FEB2027.EMA_ORACLE_VERSION,
            updateTypes,
            PTUSDG25FEB2027.emaAuthorizedMarkets()
        );
    }

    function _wirePermissions(LlamaGuardOracle emaOracle, address router, XLayerCoreConfig.Acl memory acl) internal {
        require(router != address(0), "ActivatePTUSDG25FEB2027: router is zero");
        emaOracle.grantRole(emaOracle.WRITER_ROLE(), router);
        for (uint256 i = 0; i < acl.extraEmaOracleWriters.length; i++) {
            emaOracle.grantRole(emaOracle.WRITER_ROLE(), acl.extraEmaOracleWriters[i]);
        }
    }

    /// @dev Grant then renounce, never the other way round.
    function _handOver(LlamaGuardOracle emaOracle, address deployer, XLayerCoreConfig.Acl memory acl) internal {
        require(acl.emaOracleAdmin != address(0), "ActivatePTUSDG25FEB2027: emaOracleAdmin is zero");
        if (acl.emaOracleAdmin == deployer) return;

        bytes32 adminRole = emaOracle.DEFAULT_ADMIN_ROLE();
        emaOracle.grantRole(adminRole, acl.emaOracleAdmin);
        require(emaOracle.hasRole(adminRole, acl.emaOracleAdmin), "ActivatePTUSDG25FEB2027: admin grant did not take");
        emaOracle.renounceRole(adminRole, deployer);
    }

    function _verify(
        LlamaGuardOracle emaOracle,
        address router,
        address deployer,
        XLayerCoreConfig.Acl memory acl
    )
        internal
        view
    {
        bytes32 adminRole = emaOracle.DEFAULT_ADMIN_ROLE();
        bytes32 writerRole = emaOracle.WRITER_ROLE();

        require(emaOracle.hasRole(writerRole, router), "ActivatePTUSDG25FEB2027: Router missing WRITER_ROLE");
        require(emaOracle.hasRole(adminRole, acl.emaOracleAdmin), "ActivatePTUSDG25FEB2027: admin not held by safe");
        require(
            acl.emaOracleAdmin == deployer || !emaOracle.hasRole(adminRole, deployer),
            "ActivatePTUSDG25FEB2027: deployer still admin"
        );
        require(!emaOracle.hasRole(writerRole, deployer), "ActivatePTUSDG25FEB2027: deployer holds WRITER_ROLE");
    }

    function _logSummary(Deployment memory deployed) internal pure {
        console2.log("");
        console2.log("--- phase 2 deployed, paste into XLayerCoreDeployed.sol ---");
        console2.log("OUTPUT:EMA_ORACLE_PT_USDG_25FEB2027=%s", deployed.emaOracle);
    }

    /// @dev Until this registry write lands, all three workflows read an unconfigured market and
    ///      publish nothing.
    function _printSafeBatch(address registry, XLayerCoreConfig.Acl memory acl) internal pure {
        SafeTx.Call[] memory calls = new SafeTx.Call[](1);
        calls[0] = SafeTx.call(
            "registry.setPtMarketParams(PT-USDG-25FEB2027)",
            registry,
            abi.encodeCall(
                PTParameterRegistry.setPtMarketParams, (PTUSDG25FEB2027.PT_ASSET, PTUSDG25FEB2027.ptMarketParams())
            )
        );
        SafeTx.batch("phase 2, register the asset", acl.registryUpdater, calls);
    }
}

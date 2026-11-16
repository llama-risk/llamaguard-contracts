// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { BaseScript } from "../../Base.s.sol";
import { PTParameterRegistry } from "../../../../src/PTParameterRegistry.sol";
import { LlamaGuardOracle } from "llamaguard-contracts/src/LlamaGuardOracle.sol";
import { PlasmaCoreConfig } from "./PlasmaCoreConfig.sol";
import { PlasmaCoreDeployed } from "./PlasmaCoreDeployed.sol";
import { PTsUSDE28JAN2027 } from "./assets/PTsUSDE28JAN2027.sol";
import { SafeTx } from "../../ethereum/production/SafeTx.sol";

/// @title ActivatePTsUSDE28JAN2027
/// @notice Phase 2: deploys the per-asset EMA oracle, grants the Router `WRITER_ROLE`, hands
///         admin to the safe, and prints the registry write. Needs no governance. Mirror of
///         `ActivatePTsrUSDe22OCT2026`, which documents why `maxPriceDeviation` is not set here.
/// @dev    Runnable before the listing AIP executes: the EMA oracle reads the Pendle market, not
///         the Aave reserve.
contract ActivatePTsUSDE28JAN2027 is BaseScript {
    struct Deployment {
        address emaOracle;
    }

    function run() public broadcast returns (Deployment memory deployed) {
        PlasmaCoreConfig.validate(broadcaster);

        address router = PlasmaCoreDeployed.ROUTER;
        address registry = PlasmaCoreDeployed.PT_PARAMETER_REGISTRY;

        console2.log("=============================================");
        console2.log("Plasma PT oracle activation - phase 2");
        console2.log("=============================================");
        console2.log("Asset:", PTsUSDE28JAN2027.PT_ASSET);
        console2.log("Pendle market:", PTsUSDE28JAN2027.PENDLE_MARKET);
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

    /// @notice The registry write the safe makes after phase 2. Also used by the fork test, so the
    ///         batch and the tested call cannot disagree.
    function registryCalls(address registry) public pure returns (SafeTx.Call[] memory calls) {
        calls = new SafeTx.Call[](1);
        calls[0] = SafeTx.call(
            "registry.setPtMarketParams(PT-sUSDE-28JAN2027)",
            registry,
            abi.encodeCall(
                PTParameterRegistry.setPtMarketParams, (PTsUSDE28JAN2027.PT_ASSET, PTsUSDE28JAN2027.ptMarketParams())
            )
        );
    }

    function _deployOracle() internal returns (LlamaGuardOracle) {
        string[] memory updateTypes = new string[](1);
        updateTypes[0] = PlasmaCoreConfig.TYPE_EMA;

        return new LlamaGuardOracle(
            PTsUSDE28JAN2027.EMA_ORACLE_DECIMALS,
            PTsUSDE28JAN2027.EMA_ORACLE_DESCRIPTION,
            PTsUSDE28JAN2027.EMA_ORACLE_VERSION,
            updateTypes,
            PTsUSDE28JAN2027.emaAuthorizedMarkets()
        );
    }

    function _wirePermissions(LlamaGuardOracle emaOracle, address router, PlasmaCoreConfig.Acl memory acl) internal {
        require(router != address(0), "ActivatePTsUSDE28JAN2027: router is zero");
        emaOracle.grantRole(emaOracle.WRITER_ROLE(), router);
        for (uint256 i = 0; i < acl.extraEmaOracleWriters.length; i++) {
            emaOracle.grantRole(emaOracle.WRITER_ROLE(), acl.extraEmaOracleWriters[i]);
        }
    }

    function _handOver(LlamaGuardOracle emaOracle, address deployer, PlasmaCoreConfig.Acl memory acl) internal {
        require(acl.emaOracleAdmin != address(0), "ActivatePTsUSDE28JAN2027: emaOracleAdmin is zero");
        if (acl.emaOracleAdmin == deployer) return;

        bytes32 adminRole = emaOracle.DEFAULT_ADMIN_ROLE();
        emaOracle.grantRole(adminRole, acl.emaOracleAdmin);
        require(emaOracle.hasRole(adminRole, acl.emaOracleAdmin), "ActivatePTsUSDE28JAN2027: admin grant did not take");
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

        require(emaOracle.hasRole(writerRole, router), "ActivatePTsUSDE28JAN2027: Router missing WRITER_ROLE");
        require(emaOracle.hasRole(adminRole, acl.emaOracleAdmin), "ActivatePTsUSDE28JAN2027: admin not held by safe");
        require(
            acl.emaOracleAdmin == deployer || !emaOracle.hasRole(adminRole, deployer),
            "ActivatePTsUSDE28JAN2027: deployer still admin"
        );
        require(!emaOracle.hasRole(writerRole, deployer), "ActivatePTsUSDE28JAN2027: deployer holds WRITER_ROLE");
    }

    function _logSummary(Deployment memory deployed) internal pure {
        console2.log("");
        console2.log("--- phase 2 deployed, paste into PlasmaCoreDeployed.sol ---");
        console2.log("OUTPUT:EMA_ORACLE_PT_sUSDE_28JAN2027=%s", deployed.emaOracle);
    }

    function _printSafeBatch(address registry, PlasmaCoreConfig.Acl memory acl) internal pure {
        SafeTx.batch("phase 2, register the asset", acl.registryUpdater, registryCalls(registry));
    }
}

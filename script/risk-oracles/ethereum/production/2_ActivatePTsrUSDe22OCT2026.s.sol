// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { BaseScript } from "../../Base.s.sol";
import { PTParameterRegistry } from "../../../../src/PTParameterRegistry.sol";
import { LlamaGuardOracle } from "llamaguard-contracts/src/LlamaGuardOracle.sol";
import { EthereumCoreConfig } from "./EthereumCoreConfig.sol";
import { EthereumCoreDeployed } from "./EthereumCoreDeployed.sol";
import { PTsrUSDe22OCT2026 } from "./assets/PTsrUSDe22OCT2026.sol";
import { SafeTx } from "./SafeTx.sol";

/// @title ActivatePTsrUSDe22OCT2026
/// @notice Phase 2 of the PT oracle activation on Aave V3 Ethereum Core: deploys the EMA oracle for
///         PT-srUSDe-22OCT2026, gives the Router write access to it, hands it to the operations
///         safe, and prints the registry write the safe has to make.
/// @dev    This is the per-asset phase. It reuses the RiskOracle, registry and Router that phase 1
///         deployed and reads them from `EthereumCoreDeployed`, so phase 1 has to be recorded there
///         before this runs. Onboarding a second PT means a second file under `assets/` and a second
///         copy of this script, not a second phase 1.
///
///         Touches no Aave state and needs no governance, so it can run alongside the AIP rather
///         than after it. The agents are the payload's to deploy and register; nothing here refers
///         to them.
///
///         One thing this script deliberately does NOT set: `maxPriceDeviation` on the EMA oracle.
///         `LlamaGuardOracle` gates the guard on `maxPriceDeviation > 0`, and the constructor takes
///         no value for it, so the oracle ships with it off. That is the current state of the EMA
///         leg's bounding, and it is worth being explicit about, because the Router adds nothing on
///         top: the EMA route carries no replay envelope, no min delay and no step cap, and
///         `updateLatestRiskRoundData` is a selector the Router cannot decode. Setting a deviation
///         is a `DEFAULT_ADMIN_ROLE` call on the safe, so it needs no redeploy, but it needs a
///         number from the methodology first.
///
///         The EMA oracle is deployed per asset rather than shared because `decimals`, `description`
///         and `version` are immutable, it keeps one Chainlink round series, and its latest update
///         index is keyed by update type rather than by market. Two PTs in one instance would
///         return the same answer for both, and the max-deviation guard would fire across them.
///
///         The role calls have to happen in this order. `renounceRole` clears exactly one role for
///         exactly one account, so renouncing before granting leaves a contract with no admin at
///         all and no way to add one.
contract ActivatePTsrUSDe22OCT2026 is BaseScript {
    struct Deployment {
        address emaOracle;
    }

    function run() public broadcast returns (Deployment memory deployed) {
        EthereumCoreConfig.validate(broadcaster);

        address router = EthereumCoreDeployed.ROUTER;
        address registry = EthereumCoreDeployed.PT_PARAMETER_REGISTRY;
        require(router != address(0), "ActivatePTsrUSDe22OCT2026: EthereumCoreDeployed.ROUTER unset");
        require(registry != address(0), "ActivatePTsrUSDe22OCT2026: EthereumCoreDeployed.PT_PARAMETER_REGISTRY unset");

        console2.log("=============================================");
        console2.log("Ethereum Core PT oracle activation - phase 2");
        console2.log("=============================================");
        console2.log("Asset:", PTsrUSDe22OCT2026.PT_ASSET);
        console2.log("Router:", router);
        console2.log("Registry:", registry);

        deployed = deploy(broadcaster, router, EthereumCoreConfig.acl());

        _logSummary(deployed);
        _printSafeBatch(registry, EthereumCoreConfig.acl());
    }

    /// @notice The whole of phase 2, parameterised by its principals so the handover can be
    ///         asserted in tests against addresses other than the production safe.
    /// @param deployer The account every call in here originates from, and therefore the temporary
    ///        `DEFAULT_ADMIN_ROLE` holder on the oracle it deploys.
    function deploy(
        address deployer,
        address router,
        EthereumCoreConfig.Acl memory acl
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

    /// @dev The single update type and the single authorized market are both set at construction,
    ///      so a correctly deployed oracle needs no follow-up admin call other than the handover.
    function _deployOracle() internal returns (LlamaGuardOracle) {
        string[] memory updateTypes = new string[](1);
        updateTypes[0] = EthereumCoreConfig.TYPE_EMA;

        return new LlamaGuardOracle(
            PTsrUSDe22OCT2026.EMA_ORACLE_DECIMALS,
            PTsrUSDe22OCT2026.EMA_ORACLE_DESCRIPTION,
            PTsrUSDe22OCT2026.EMA_ORACLE_VERSION,
            updateTypes,
            PTsrUSDe22OCT2026.emaAuthorizedMarkets()
        );
    }

    /// @dev The Router is the only writer the EMA oracle needs, because the EMA workflow reaches it
    ///      through the Router like every other leg. Granted before the handover, while the
    ///      deployer still holds admin.
    function _wirePermissions(LlamaGuardOracle emaOracle, address router, EthereumCoreConfig.Acl memory acl) internal {
        require(router != address(0), "ActivatePTsrUSDe22OCT2026: router is zero");
        emaOracle.grantRole(emaOracle.WRITER_ROLE(), router);
        for (uint256 i = 0; i < acl.extraEmaOracleWriters.length; i++) {
            emaOracle.grantRole(emaOracle.WRITER_ROLE(), acl.extraEmaOracleWriters[i]);
        }
    }

    /// @dev Grant then renounce, never the other way round. The grant is checked before the
    ///      renounce runs, so a failed grant cannot strand the oracle without an admin.
    function _handOver(LlamaGuardOracle emaOracle, address deployer, EthereumCoreConfig.Acl memory acl) internal {
        require(acl.emaOracleAdmin != address(0), "ActivatePTsrUSDe22OCT2026: emaOracleAdmin is zero");
        if (acl.emaOracleAdmin == deployer) return;

        bytes32 adminRole = emaOracle.DEFAULT_ADMIN_ROLE();
        emaOracle.grantRole(adminRole, acl.emaOracleAdmin);
        require(emaOracle.hasRole(adminRole, acl.emaOracleAdmin), "ActivatePTsrUSDe22OCT2026: admin grant did not take");
        emaOracle.renounceRole(adminRole, deployer);
    }

    function _verify(
        LlamaGuardOracle emaOracle,
        address router,
        address deployer,
        EthereumCoreConfig.Acl memory acl
    )
        internal
        view
    {
        bytes32 adminRole = emaOracle.DEFAULT_ADMIN_ROLE();
        bytes32 writerRole = emaOracle.WRITER_ROLE();

        require(emaOracle.hasRole(writerRole, router), "ActivatePTsrUSDe22OCT2026: Router missing WRITER_ROLE");
        require(emaOracle.hasRole(adminRole, acl.emaOracleAdmin), "ActivatePTsrUSDe22OCT2026: admin not held by safe");
        require(
            acl.emaOracleAdmin == deployer || !emaOracle.hasRole(adminRole, deployer),
            "ActivatePTsrUSDe22OCT2026: deployer still admin"
        );
        require(!emaOracle.hasRole(writerRole, deployer), "ActivatePTsrUSDe22OCT2026: deployer holds WRITER_ROLE");
    }

    function _logSummary(Deployment memory deployed) internal pure {
        console2.log("");
        console2.log("--- phase 2 deployed, paste into EthereumCoreDeployed.sol ---");
        console2.log("OUTPUT:EMA_ORACLE_PT_SRUSDE_22OCT2026=%s", deployed.emaOracle);
    }

    /// @notice The registry write, which the deployer cannot make: `setPtMarketParams` is
    ///         `onlyUpdater` and the updater is the safe from the registry's first block.
    /// @dev    Until this lands, all three workflows read an unconfigured market and publish
    ///         nothing. It is the gate on the CRE phase, not an afterthought.
    function _printSafeBatch(address registry, EthereumCoreConfig.Acl memory acl) internal pure {
        SafeTx.Call[] memory calls = new SafeTx.Call[](1);
        calls[0] = SafeTx.call(
            "registry.setPtMarketParams(PT-srUSDe-22OCT2026)",
            registry,
            abi.encodeCall(
                PTParameterRegistry.setPtMarketParams, (PTsrUSDe22OCT2026.PT_ASSET, PTsrUSDe22OCT2026.ptMarketParams())
            )
        );
        SafeTx.batch("phase 2, register the asset", acl.registryUpdater, calls);
    }
}

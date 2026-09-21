// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { BaseScript } from "../../Base.s.sol";
import { PTParameterRegistry } from "../../../../src/PTParameterRegistry.sol";
import { LlamaguardRiskOracleRouter } from "../../../../src/LlamaguardRiskOracleRouter.sol";
import { RiskOracle } from "aave-v3-risk-stewards/contracts/dependencies/RiskOracle.sol";
import { PlasmaCoreConfig } from "./PlasmaCoreConfig.sol";
import { PlasmaCoreExternalAddresses } from "./PlasmaCoreExternalAddresses.sol";
import { SafeTx } from "../../ethereum/production/SafeTx.sol";

/// @title ActivatePlasmaCore
/// @notice Phase 1 of the PT oracle activation on Aave V3 Plasma: deploys the three chain-scoped
///         contracts, authorises the Router to publish, sets the Router's updater and guardian,
///         and starts both ownership handovers.
/// @dev    Structural mirror of `ActivateEthereumCore`; the three-ownership-primitives model and
///         the deployer-owned-Router window are documented there and hold unchanged. Deploys
///         nothing per asset and touches no Aave state, so it needs no governance authority and
///         can run before the AIP exists. Run once ever: a second PT on Plasma starts at phase 2.
///
///         **This is the phase the AIP waits on.** The payload names the RiskOracle deployed here
///         as `LLAMARISK_RISK_ORACLE`, so the constant cannot be filled until this has run.
///
///         All ACL values come from `PlasmaCoreConfig`; nothing is read from env. Deployed
///         addresses are emitted as `OUTPUT:KEY=0x...` lines for capture into `PlasmaCoreDeployed`.
contract ActivatePlasmaCore is BaseScript {
    struct Deployment {
        address riskOracle;
        address ptParameterRegistry;
        address router;
    }

    function run() public broadcast returns (Deployment memory deployed) {
        PlasmaCoreConfig.validate(broadcaster);

        console2.log("=============================================");
        console2.log("Plasma PT oracle activation - phase 1");
        console2.log("=============================================");
        console2.log("Broadcaster:", broadcaster);
        console2.log("LlamaRisk safe:", PlasmaCoreConfig.LLAMARISK_SAFE);
        console2.log("Aave Executor:", PlasmaCoreExternalAddresses.AAVE_EXECUTOR);
        console2.log("Router guardian (Aave protocol guardian):", PlasmaCoreConfig.ROUTER_GUARDIAN);

        deployed = deploy(broadcaster, PlasmaCoreConfig.acl());

        _logSummary(deployed);
        _printSafeBatch(deployed, PlasmaCoreConfig.acl());
    }

    /// @notice The whole of phase 1, parameterised by its principals so the wiring can be asserted
    ///         in tests against addresses other than the production safe.
    function deploy(address deployer, PlasmaCoreConfig.Acl memory acl) public returns (Deployment memory deployed) {
        deployed = _deployContracts(deployer, acl);
        _wirePermissions(deployed, acl);
        _handOver(deployed, deployer, acl);
        _verify(deployed, deployer, acl);
    }

    /// @dev The registry is constructed straight into final ownership. The RiskOracle passes
    ///      through the deployer because it hardcodes `msg.sender`, and the Router because it has
    ///      settings only its owner can apply.
    function _deployContracts(
        address deployer,
        PlasmaCoreConfig.Acl memory acl
    )
        internal
        returns (Deployment memory deployed)
    {
        RiskOracle riskOracle = new RiskOracle(
            PlasmaCoreConfig.RISK_ORACLE_DESCRIPTION, new address[](0), PlasmaCoreConfig.riskOracleUpdateTypes()
        );
        PTParameterRegistry registry = new PTParameterRegistry(acl.registryOwner, acl.registryUpdater);
        LlamaguardRiskOracleRouter router = new LlamaguardRiskOracleRouter(deployer);

        deployed.riskOracle = address(riskOracle);
        deployed.ptParameterRegistry = address(registry);
        deployed.router = address(router);
    }

    /// @dev Everything the deployer can apply while it still holds both contracts. The write path
    ///      is CRE forwarder -> Router -> RiskOracle, so the Router is the only sender the oracle
    ///      needs; anything beyond it is an explicit break-glass entry in the config.
    function _wirePermissions(Deployment memory deployed, PlasmaCoreConfig.Acl memory acl) internal {
        RiskOracle riskOracle = RiskOracle(deployed.riskOracle);
        riskOracle.addAuthorizedSender(deployed.router);
        for (uint256 i = 0; i < acl.extraRiskOracleSenders.length; i++) {
            riskOracle.addAuthorizedSender(acl.extraRiskOracleSenders[i]);
        }

        LlamaguardRiskOracleRouter router = LlamaguardRiskOracleRouter(deployed.router);
        router.setUpdater(acl.routerUpdater);
        router.setGuardian(acl.routerGuardian);
    }

    /// @dev Two handovers with different shapes. The RiskOracle transfer is single step and lands
    ///      immediately; the Router transfer only records a pending owner and needs the safe to
    ///      accept. Both are skipped when the target is already the deployer, which only happens
    ///      in tests that keep the stack under their own control.
    function _handOver(Deployment memory deployed, address deployer, PlasmaCoreConfig.Acl memory acl) internal {
        require(acl.riskOracleOwner != address(0), "ActivatePlasmaCore: riskOracleOwner is zero");
        require(acl.routerOwner != address(0), "ActivatePlasmaCore: routerOwner is zero");

        if (acl.riskOracleOwner != deployer) {
            RiskOracle(deployed.riskOracle).transferOwnership(acl.riskOracleOwner);
        }
        if (acl.routerOwner != deployer) {
            LlamaguardRiskOracleRouter(deployed.router).transferOwnership(acl.routerOwner);
        }
    }

    /// @dev Reads the result back rather than trusting the calls above. Every principal this
    ///      script sets is asserted here, so a mistyped one fails the broadcast rather than
    ///      surfacing a phase later.
    function _verify(Deployment memory deployed, address deployer, PlasmaCoreConfig.Acl memory acl) internal view {
        RiskOracle riskOracle = RiskOracle(deployed.riskOracle);
        PTParameterRegistry registry = PTParameterRegistry(deployed.ptParameterRegistry);
        LlamaguardRiskOracleRouter router = LlamaguardRiskOracleRouter(deployed.router);

        require(riskOracle.isAuthorized(deployed.router), "ActivatePlasmaCore: Router is not an authorized sender");
        for (uint256 i = 0; i < acl.extraRiskOracleSenders.length; i++) {
            require(
                riskOracle.isAuthorized(acl.extraRiskOracleSenders[i]),
                "ActivatePlasmaCore: extra sender is not authorized"
            );
        }

        string[] memory updateTypes = riskOracle.getAllUpdateTypes();
        string[] memory expectedTypes = PlasmaCoreConfig.riskOracleUpdateTypes();
        require(updateTypes.length == expectedTypes.length, "ActivatePlasmaCore: update type count mismatch");
        for (uint256 i = 0; i < expectedTypes.length; i++) {
            require(
                keccak256(bytes(updateTypes[i])) == keccak256(bytes(expectedTypes[i])),
                "ActivatePlasmaCore: update type mismatch"
            );
        }

        require(riskOracle.owner() == acl.riskOracleOwner, "ActivatePlasmaCore: RiskOracle owner mismatch");
        require(registry.owner() == acl.registryOwner, "ActivatePlasmaCore: registry owner mismatch");
        require(registry.updater() == acl.registryUpdater, "ActivatePlasmaCore: registry updater mismatch");

        require(router.updater() == acl.routerUpdater, "ActivatePlasmaCore: Router updater mismatch");
        require(router.guardian() == acl.routerGuardian, "ActivatePlasmaCore: Router guardian mismatch");

        // The handover is two step, so until the safe accepts, the deployer is still owner and the
        // safe is only pending. Asserting both halves is what catches a transfer that never fired.
        if (acl.routerOwner == deployer) {
            require(router.owner() == deployer, "ActivatePlasmaCore: Router owner mismatch");
        } else {
            require(router.owner() == deployer, "ActivatePlasmaCore: Router owner left the deployer early");
            require(router.pendingOwner() == acl.routerOwner, "ActivatePlasmaCore: Router handover not started");
        }
    }

    function _logSummary(Deployment memory deployed) internal pure {
        console2.log("");
        console2.log("--- phase 1 deployed, paste into PlasmaCoreDeployed.sol ---");
        console2.log("OUTPUT:RISK_ORACLE=%s", deployed.riskOracle);
        console2.log("OUTPUT:PT_PARAMETER_REGISTRY=%s", deployed.ptParameterRegistry);
        console2.log("OUTPUT:ROUTER=%s", deployed.router);
        console2.log("");
        console2.log("RISK_ORACLE is the AIP payload's LLAMARISK_RISK_ORACLE.");
    }

    /// @notice The batch, as data, so the fork test can execute exactly what the safe will.
    /// @dev    One call: accepting the Router. It is the last step of phase 1, not the first step
    ///         of a later one.
    function safeCalls(address router) public pure returns (SafeTx.Call[] memory calls) {
        calls = new SafeTx.Call[](1);
        calls[0] = SafeTx.call("router.acceptOwnership()", router, abi.encodeCall(Ownable2Step.acceptOwnership, ()));
    }

    function _printSafeBatch(Deployment memory deployed, PlasmaCoreConfig.Acl memory acl) internal pure {
        SafeTx.batch("phase 1, accept the Router", acl.routerOwner, safeCalls(deployed.router));
    }
}

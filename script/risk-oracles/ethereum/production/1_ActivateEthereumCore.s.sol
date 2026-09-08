// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { BaseScript } from "../../Base.s.sol";
import { PTParameterRegistry } from "../../../../src/PTParameterRegistry.sol";
import { LlamaguardRiskOracleRouter } from "../../../../src/LlamaguardRiskOracleRouter.sol";
import { RiskOracle } from "aave-v3-risk-stewards/contracts/dependencies/RiskOracle.sol";
import { EthereumCoreConfig } from "./EthereumCoreConfig.sol";
import { EthereumCoreExternalAddresses } from "./EthereumCoreExternalAddresses.sol";
import { SafeTx } from "./SafeTx.sol";

/// @title ActivateEthereumCore
/// @notice Phase 1 of the PT oracle activation on Aave V3 Ethereum Core: deploys the three chain
///         scoped contracts, authorises the Router to publish, sets the Router's updater and
///         guardian, and starts both ownership handovers.
/// @dev    Deploys nothing per asset and touches no Aave state, so it needs no governance authority
///         and can run before the AIP exists. It is also run once ever: the RiskOracle, the registry
///         and the Router are all multi market, so onboarding a second PT starts later.
///
///         **This is the phase the AIP waits on.** The payload names the RiskOracle deployed here as
///         `LLAMARISK_RISK_ORACLE`, so the constant cannot be filled until this has run. Nothing
///         here calls an Aave contract, and nothing the payload does depends on the registry or the
///         Router, so the drafting can proceed in parallel with everything downstream.
///
///         Three contracts, three different ownership primitives, and the differences decide what
///         this script may do:
///
///         `PTParameterRegistry` takes owner and updater as constructor arguments, so it belongs to
///         the Aave Executor from its first block and the deployer never holds it.
///
///         `RiskOracle` is `Ownable(msg.sender)`, single step. The script authorises the Router
///         while it still can, then transfers. That transfer is immediate and irreversible, so a
///         wrong `RISK_ORACLE_OWNER` is unrecoverable.
///
///         `LlamaguardRiskOracleRouter` is `Ownable2Step`, and is constructed owned by the DEPLOYER
///         rather than by the safe. That is what lets `setUpdater` and `setGuardian` be broadcast
///         here instead of signed. `transferOwnership` then only sets `pendingOwner`, so the
///         deployer stays Router owner until the safe sends the single call this script prints.
///
///         The window that opens is real and bounded by how long that signature takes. Nothing is at
///         risk inside it: no CRE workflow exists yet, so a route the deploy key added would have no
///         author to accept reports from, and the incoming owner can remove it. `setUpdater` and
///         `setGuardian` are applied here precisely so that nothing else has to wait on the safe.
///
///         All ACL values come from `EthereumCoreConfig`; nothing is read from env. Deployed
///         addresses are emitted as `OUTPUT:KEY=0x...` lines for capture into `EthereumCoreDeployed`.
contract ActivateEthereumCore is BaseScript {
    struct Deployment {
        address riskOracle;
        address ptParameterRegistry;
        address router;
    }

    function run() public broadcast returns (Deployment memory deployed) {
        EthereumCoreConfig.validate(broadcaster);

        console2.log("=============================================");
        console2.log("Ethereum Core PT oracle activation - phase 1");
        console2.log("=============================================");
        console2.log("Broadcaster:", broadcaster);
        console2.log("LlamaRisk safe:", EthereumCoreConfig.LLAMARISK_SAFE);
        console2.log("Aave Executor:", EthereumCoreExternalAddresses.AAVE_EXECUTOR);
        console2.log("Router guardian (Aave protocol guardian):", EthereumCoreConfig.ROUTER_GUARDIAN);

        deployed = deploy(broadcaster, EthereumCoreConfig.acl());

        _logSummary(deployed);
        _printSafeBatch(deployed, EthereumCoreConfig.acl());
    }

    /// @notice The whole of phase 1, parameterised by its principals so the wiring can be asserted
    ///         in tests against addresses other than the production safe.
    /// @param deployer The account every call in here originates from, and therefore the temporary
    ///        owner of both the RiskOracle and the Router. Under `forge script` that is the
    ///        broadcaster, because forge re-sends each call from it; called directly from a test it
    ///        is the script contract itself. Pass the wrong one and the Router is constructed owned
    ///        by an account that cannot then set its updater.
    function deploy(address deployer, EthereumCoreConfig.Acl memory acl) public returns (Deployment memory deployed) {
        deployed = _deployContracts(deployer, acl);
        _wirePermissions(deployed, acl);
        _handOver(deployed, deployer, acl);
        _verify(deployed, deployer, acl);
    }

    /// @dev The registry is constructed straight into final ownership. The RiskOracle passes through
    ///      the deployer because it hardcodes `msg.sender`, and the Router because it has settings
    ///      only its owner can apply and we would rather broadcast them than collect signatures.
    function _deployContracts(
        address deployer,
        EthereumCoreConfig.Acl memory acl
    )
        internal
        returns (Deployment memory deployed)
    {
        RiskOracle riskOracle = new RiskOracle(
            EthereumCoreConfig.RISK_ORACLE_DESCRIPTION, new address[](0), EthereumCoreConfig.riskOracleUpdateTypes()
        );
        PTParameterRegistry registry = new PTParameterRegistry(acl.registryOwner, acl.registryUpdater);
        LlamaguardRiskOracleRouter router = new LlamaguardRiskOracleRouter(deployer);

        deployed.riskOracle = address(riskOracle);
        deployed.ptParameterRegistry = address(registry);
        deployed.router = address(router);
    }

    /// @dev Everything the deployer can apply while it still holds both contracts.
    ///
    ///      The write path is CRE forwarder -> Router -> RiskOracle, so the Router is the only sender
    ///      the oracle needs; anything beyond it is an explicit break-glass entry in the config.
    ///
    ///      `setUpdater` is not deferrable: every `onlyUpdater` function on the Router reverts until
    ///      it lands, which includes the route throttles a later phase sets. `setGuardian` is the
    ///      Aave protocol guardian, which can pause and cannot unpause.
    function _wirePermissions(Deployment memory deployed, EthereumCoreConfig.Acl memory acl) internal {
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
    ///      accept. Both are skipped when the target is already the deployer, which only happens in
    ///      tests that keep the stack under their own control.
    function _handOver(Deployment memory deployed, address deployer, EthereumCoreConfig.Acl memory acl) internal {
        require(acl.riskOracleOwner != address(0), "ActivateEthereumCore: riskOracleOwner is zero");
        require(acl.routerOwner != address(0), "ActivateEthereumCore: routerOwner is zero");

        if (acl.riskOracleOwner != deployer) {
            RiskOracle(deployed.riskOracle).transferOwnership(acl.riskOracleOwner);
        }
        if (acl.routerOwner != deployer) {
            LlamaguardRiskOracleRouter(deployed.router).transferOwnership(acl.routerOwner);
        }
    }

    /// @dev Reads the result back rather than trusting the calls above. Every principal this script
    ///      sets is asserted here, so a mistyped one fails the broadcast rather than surfacing a
    ///      phase later.
    ///
    ///      The `authorizedSenders` mapping is private, but `isAuthorized` exposes it, so the
    ///      Router's grant is assertable directly and does not need the fork test to observe it by
    ///      publishing. The update types are checked for exact membership and count: an extra type
    ///      is as wrong as a missing one, since nothing publishes a type the agents do not answer to.
    function _verify(Deployment memory deployed, address deployer, EthereumCoreConfig.Acl memory acl) internal view {
        RiskOracle riskOracle = RiskOracle(deployed.riskOracle);
        PTParameterRegistry registry = PTParameterRegistry(deployed.ptParameterRegistry);
        LlamaguardRiskOracleRouter router = LlamaguardRiskOracleRouter(deployed.router);

        require(riskOracle.isAuthorized(deployed.router), "ActivateEthereumCore: Router is not an authorized sender");
        for (uint256 i = 0; i < acl.extraRiskOracleSenders.length; i++) {
            require(
                riskOracle.isAuthorized(acl.extraRiskOracleSenders[i]),
                "ActivateEthereumCore: extra sender is not authorized"
            );
        }

        string[] memory updateTypes = riskOracle.getAllUpdateTypes();
        string[] memory expectedTypes = EthereumCoreConfig.riskOracleUpdateTypes();
        require(updateTypes.length == expectedTypes.length, "ActivateEthereumCore: update type count mismatch");
        for (uint256 i = 0; i < expectedTypes.length; i++) {
            require(
                keccak256(bytes(updateTypes[i])) == keccak256(bytes(expectedTypes[i])),
                "ActivateEthereumCore: update type mismatch"
            );
        }

        require(riskOracle.owner() == acl.riskOracleOwner, "ActivateEthereumCore: RiskOracle owner mismatch");
        require(registry.owner() == acl.registryOwner, "ActivateEthereumCore: registry owner mismatch");
        require(registry.updater() == acl.registryUpdater, "ActivateEthereumCore: registry updater mismatch");

        require(router.updater() == acl.routerUpdater, "ActivateEthereumCore: Router updater mismatch");
        require(router.guardian() == acl.routerGuardian, "ActivateEthereumCore: Router guardian mismatch");

        // The handover is two step, so until the safe accepts, the deployer is still owner and the
        // safe is only pending. Asserting both halves is what catches a transfer that never fired.
        if (acl.routerOwner == deployer) {
            require(router.owner() == deployer, "ActivateEthereumCore: Router owner mismatch");
        } else {
            require(router.owner() == deployer, "ActivateEthereumCore: Router owner left the deployer early");
            require(router.pendingOwner() == acl.routerOwner, "ActivateEthereumCore: Router handover not started");
        }
    }

    function _logSummary(Deployment memory deployed) internal pure {
        console2.log("");
        console2.log("--- phase 1 deployed, paste into EthereumCoreDeployed.sol ---");
        console2.log("OUTPUT:RISK_ORACLE=%s", deployed.riskOracle);
        console2.log("OUTPUT:PT_PARAMETER_REGISTRY=%s", deployed.ptParameterRegistry);
        console2.log("OUTPUT:ROUTER=%s", deployed.router);
        console2.log("");
        console2.log("RISK_ORACLE is the AIP payload's LLAMARISK_RISK_ORACLE.");
    }

    /// @notice The batch, as data, so the fork test can execute exactly what the safe will.
    /// @dev    One call: accepting the Router. Until it lands the deployer is still Router owner, so
    ///         `addRoute` is not yet a safe action and the deploy key retains an authority it is not
    ///         meant to keep. It is the last step of phase 1, not the first step of a later one.
    function safeCalls(address router) public pure returns (SafeTx.Call[] memory calls) {
        calls = new SafeTx.Call[](1);
        calls[0] = SafeTx.call("router.acceptOwnership()", router, abi.encodeCall(Ownable2Step.acceptOwnership, ()));
    }

    function _printSafeBatch(Deployment memory deployed, EthereumCoreConfig.Acl memory acl) internal pure {
        SafeTx.batch("phase 1, accept the Router", acl.routerOwner, safeCalls(deployed.router));
    }
}

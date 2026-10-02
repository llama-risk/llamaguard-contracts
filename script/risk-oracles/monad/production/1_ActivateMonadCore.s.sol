// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { BaseScript } from "../../Base.s.sol";
import { PTParameterRegistry } from "../../../../src/PTParameterRegistry.sol";
import { LlamaguardRiskOracleRouter } from "../../../../src/LlamaguardRiskOracleRouter.sol";
import { RiskOracle } from "aave-v3-risk-stewards/contracts/dependencies/RiskOracle.sol";
import { MonadCoreConfig } from "./MonadCoreConfig.sol";
import { MonadCoreExternalAddresses } from "./MonadCoreExternalAddresses.sol";
import { SafeTx } from "../../ethereum/production/SafeTx.sol";

interface ISafeConfig {
    function getOwners() external view returns (address[] memory);
    function getThreshold() external view returns (uint256);
}

/// @title ActivateMonadCore
/// @notice Phase 1: deploys RiskOracle, PTParameterRegistry and Router, authorises the Router,
///         sets updater and guardian, and starts both handovers. Runs once ever, needs no
///         governance. Mirror of `ActivateEthereumCore`, which documents the reasoning.
/// @dev    Nothing here reads `AGENT_HUB`, so the core can stand up independently of it.
contract ActivateMonadCore is BaseScript {
    struct Deployment {
        address riskOracle;
        address ptParameterRegistry;
        address router;
    }

    function run() public broadcast returns (Deployment memory deployed) {
        MonadCoreConfig.validate(broadcaster);

        console2.log("=============================================");
        console2.log("Monad PT oracle activation - phase 1");
        console2.log("=============================================");
        console2.log("Broadcaster:", broadcaster);
        console2.log("LlamaRisk safe:", MonadCoreConfig.LLAMARISK_SAFE);
        console2.log("Aave Executor:", MonadCoreExternalAddresses.AAVE_EXECUTOR);
        console2.log("Router guardian:", MonadCoreConfig.ROUTER_GUARDIAN);

        _requireTheSafeIsReady();

        deployed = deploy(broadcaster, MonadCoreConfig.acl());

        _logSummary(deployed);
        _printSafeBatch(deployed, MonadCoreConfig.acl());
    }

    function deploy(address deployer, MonadCoreConfig.Acl memory acl) public returns (Deployment memory deployed) {
        deployed = _deployContracts(deployer, acl);
        _wirePermissions(deployed, acl);
        _handOver(deployed, deployer, acl);
        _verify(deployed, deployer, acl);
    }

    function _deployContracts(
        address deployer,
        MonadCoreConfig.Acl memory acl
    )
        internal
        returns (Deployment memory deployed)
    {
        RiskOracle riskOracle = new RiskOracle(
            MonadCoreConfig.RISK_ORACLE_DESCRIPTION, new address[](0), MonadCoreConfig.riskOracleUpdateTypes()
        );
        PTParameterRegistry registry = new PTParameterRegistry(acl.registryOwner, acl.registryUpdater);
        LlamaguardRiskOracleRouter router = new LlamaguardRiskOracleRouter(deployer);

        deployed.riskOracle = address(riskOracle);
        deployed.ptParameterRegistry = address(registry);
        deployed.router = address(router);
    }

    function _wirePermissions(Deployment memory deployed, MonadCoreConfig.Acl memory acl) internal {
        RiskOracle riskOracle = RiskOracle(deployed.riskOracle);
        riskOracle.addAuthorizedSender(deployed.router);
        for (uint256 i = 0; i < acl.extraRiskOracleSenders.length; i++) {
            riskOracle.addAuthorizedSender(acl.extraRiskOracleSenders[i]);
        }

        LlamaguardRiskOracleRouter router = LlamaguardRiskOracleRouter(deployed.router);
        router.setUpdater(acl.routerUpdater);
        router.setGuardian(acl.routerGuardian);
    }

    /// @dev The RiskOracle transfer is single step and immediate; the Router transfer is two step
    ///      and waits on the safe's `acceptOwnership`.
    function _handOver(Deployment memory deployed, address deployer, MonadCoreConfig.Acl memory acl) internal {
        require(acl.riskOracleOwner != address(0), "ActivateMonadCore: riskOracleOwner is zero");
        require(acl.routerOwner != address(0), "ActivateMonadCore: routerOwner is zero");

        if (acl.riskOracleOwner != deployer) {
            RiskOracle(deployed.riskOracle).transferOwnership(acl.riskOracleOwner);
        }
        if (acl.routerOwner != deployer) {
            LlamaguardRiskOracleRouter(deployed.router).transferOwnership(acl.routerOwner);
        }
    }

    /// @dev Reads every principal back rather than trusting the calls above.
    function _verify(Deployment memory deployed, address deployer, MonadCoreConfig.Acl memory acl) internal view {
        RiskOracle riskOracle = RiskOracle(deployed.riskOracle);
        PTParameterRegistry registry = PTParameterRegistry(deployed.ptParameterRegistry);
        LlamaguardRiskOracleRouter router = LlamaguardRiskOracleRouter(deployed.router);

        require(riskOracle.isAuthorized(deployed.router), "ActivateMonadCore: Router is not an authorized sender");
        for (uint256 i = 0; i < acl.extraRiskOracleSenders.length; i++) {
            require(
                riskOracle.isAuthorized(acl.extraRiskOracleSenders[i]),
                "ActivateMonadCore: extra sender is not authorized"
            );
        }

        string[] memory updateTypes = riskOracle.getAllUpdateTypes();
        string[] memory expectedTypes = MonadCoreConfig.riskOracleUpdateTypes();
        require(updateTypes.length == expectedTypes.length, "ActivateMonadCore: update type count mismatch");
        for (uint256 i = 0; i < expectedTypes.length; i++) {
            require(
                keccak256(bytes(updateTypes[i])) == keccak256(bytes(expectedTypes[i])),
                "ActivateMonadCore: update type mismatch"
            );
        }

        require(riskOracle.owner() == acl.riskOracleOwner, "ActivateMonadCore: RiskOracle owner mismatch");
        require(registry.owner() == acl.registryOwner, "ActivateMonadCore: registry owner mismatch");
        require(registry.updater() == acl.registryUpdater, "ActivateMonadCore: registry updater mismatch");

        require(router.updater() == acl.routerUpdater, "ActivateMonadCore: Router updater mismatch");
        require(router.guardian() == acl.routerGuardian, "ActivateMonadCore: Router guardian mismatch");

        if (acl.routerOwner == deployer) {
            require(router.owner() == deployer, "ActivateMonadCore: Router owner mismatch");
        } else {
            require(router.owner() == deployer, "ActivateMonadCore: Router owner left the deployer early");
            require(router.pendingOwner() == acl.routerOwner, "ActivateMonadCore: Router handover not started");
        }
    }

    /// @notice The safe must exist AND carry the final owner set before anything is handed to it.
    /// @dev    Existence alone is not enough: the replay that creates this address reproduces
    ///         threshold 1 with two owners outside the final set, so a safe in that state would take
    ///         ownership of the whole stack while controlled by the wrong signers at a single
    ///         signature. Checked here rather than in `MonadCoreConfig.validate`, which is `pure`
    ///         over constants and cannot read a safe.
    function _requireTheSafeIsReady() internal view {
        address safe = MonadCoreConfig.LLAMARISK_SAFE;
        require(safe.code.length != 0, "ActivateMonadCore: LLAMARISK_SAFE has no code on Monad");

        uint256 threshold = ISafeConfig(safe).getThreshold();
        require(
            threshold == MonadCoreConfig.LLAMARISK_SAFE_THRESHOLD,
            "ActivateMonadCore: LLAMARISK_SAFE threshold is not the expected one"
        );

        address[] memory owners = ISafeConfig(safe).getOwners();
        address[] memory expected = MonadCoreConfig.llamariskSafeOwners();
        require(owners.length == expected.length, "ActivateMonadCore: LLAMARISK_SAFE owner count mismatch");
        for (uint256 i = 0; i < expected.length; i++) {
            require(owners[i] == expected[i], "ActivateMonadCore: LLAMARISK_SAFE owner set mismatch");
        }
    }

    function _logSummary(Deployment memory deployed) internal pure {
        console2.log("");
        console2.log("--- phase 1 deployed, paste into MonadCoreDeployed.sol ---");
        console2.log("OUTPUT:RISK_ORACLE=%s", deployed.riskOracle);
        console2.log("OUTPUT:PT_PARAMETER_REGISTRY=%s", deployed.ptParameterRegistry);
        console2.log("OUTPUT:ROUTER=%s", deployed.router);
        console2.log("");
        console2.log("RISK_ORACLE is the AIP payload's LLAMARISK_RISK_ORACLE.");
    }

    function safeCalls(address router) public pure returns (SafeTx.Call[] memory calls) {
        calls = new SafeTx.Call[](1);
        calls[0] = SafeTx.call("router.acceptOwnership()", router, abi.encodeCall(Ownable2Step.acceptOwnership, ()));
    }

    function _printSafeBatch(Deployment memory deployed, MonadCoreConfig.Acl memory acl) internal pure {
        SafeTx.batch("phase 1, accept the Router", acl.routerOwner, safeCalls(deployed.router));
    }
}

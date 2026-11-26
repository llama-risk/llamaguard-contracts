// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IAgentConfigurator } from "chaos-agents/interfaces/IAgentConfigurator.sol";
import { RiskOracle } from "aave-v3-risk-stewards/contracts/dependencies/RiskOracle.sol";
import { LlamaguardRiskOracleRouter } from "../../../src/LlamaguardRiskOracleRouter.sol";
import { ShadowPool } from "../../../src/staging/ShadowPool.sol";
import { CapsParameterRegistry } from "../../../src/caps-oracle/CapsParameterRegistry.sol";
import { ICapsParameterRegistry } from "../../../src/caps-oracle/interfaces/ICapsParameterRegistry.sol";
import { ICapsRangeValidationModule as IRvm } from "../../../src/caps-oracle/interfaces/ICapsRangeValidationModule.sol";
import { CapsConfig } from "./CapsConfig.sol";
import { CapsDeployment } from "./CapsDeployment.sol";
import { CapsScript } from "./CapsScript.sol";

/// @title WireCaps
/// @notice Step 2: the one-time connections between the step 1 contracts. No per-asset value; those are step 3.
///           - RiskOracle: the Router as sender, the borrow update type.
///           - Router: updater and guardian.
///           - AgentHub: the raise agent (reads our RiskOracle, only the Router may kick it, waits tau) and the cut
///             agent (reads the reducer, anyone may kick it). Both read their markets from the Pool and write
///             through the agent context.
///           - Shadow only: both agents may write the ShadowPool.
///           - RVM: both agents and the borrow bounds.
///           - Registry: the market and its defaults.
///           - Hand-over of the RiskOracle and the Router to their configured owners.
/// @dev Each call is signed by whoever holds the role on chain now, so on production the AgentHub calls print as
///      the AIP's and the Safe calls as their batches. Agent ids are predicted from the hub's agent count, so the
///      RVM batch can be printed before the AIP executes; the AIP must register the raise agent, then the cut agent.
contract WireCaps is CapsScript {
    function run() external {
        (string memory label, CapsConfig.Config memory config, CapsDeployment.Deployment memory deployment) = _context();
        _save(label, wire(config, deployment, broadcaster));
    }

    function wire(
        CapsConfig.Config memory config,
        CapsDeployment.Deployment memory deployment,
        address sender
    )
        public
        returns (CapsDeployment.Deployment memory)
    {
        require(deployment.rvm != address(0), "WireCaps: run step 1 first");
        CapsConfig.Market memory market = config.market;
        address hub = _agentHub(market, deployment);
        uint256 nextAgentId = IAgentConfigurator(hub).getAgentCount();
        deployment.raiseAgentId = nextAgentId;
        deployment.cutAgentId = nextAgentId + 1;

        _begin(sender);
        _wireRiskOracle(market, deployment);
        _wireRouter(config.roles, deployment);
        _registerAgents(config, deployment, hub);
        if (market.shadow) _allowShadowWriters(deployment);
        _wireRvm(market, deployment);
        _addMarket(market, deployment);
        _handOver(config.roles, deployment);
        _end("Step 2: wire");

        console2.log("Raise agent id:", deployment.raiseAgentId);
        console2.log("Cut agent id:  ", deployment.cutAgentId);
        return deployment;
    }

    function _wireRiskOracle(CapsConfig.Market memory market, CapsDeployment.Deployment memory d) private {
        address owner = Ownable(d.riskOracle).owner();
        _call(
            "RiskOracle: Router may publish",
            owner,
            d.riskOracle,
            abi.encodeCall(RiskOracle.addAuthorizedSender, (d.router))
        );
        _call(
            "RiskOracle: borrow update type",
            owner,
            d.riskOracle,
            abi.encodeCall(RiskOracle.addUpdateType, (CapsConfig.borrowUpdateType(market)))
        );
    }

    function _wireRouter(CapsConfig.Roles memory roles, CapsDeployment.Deployment memory d) private {
        address owner = Ownable(d.router).owner();
        _call(
            "Router: updater",
            owner,
            d.router,
            abi.encodeCall(LlamaguardRiskOracleRouter.setUpdater, (roles.routerUpdater))
        );
        _call(
            "Router: guardian",
            owner,
            d.router,
            abi.encodeCall(LlamaguardRiskOracleRouter.setGuardian, (roles.routerGuardian))
        );
    }

    function _registerAgents(CapsConfig.Config memory config, CapsDeployment.Deployment memory d, address hub) private {
        address owner = Ownable(hub).owner();
        address[] memory router = new address[](1);
        router[0] = d.router;
        IAgentConfigurator.AgentRegistrationInput memory raise =
            _agentInput(config, d, d.raiseAgent, d.riskOracle, config.market.tauSeconds, router);
        IAgentConfigurator.AgentRegistrationInput memory cut = _agentInput(config, d, d.cutAgent, d.reducer, 0, router);
        _registerAgent("AgentHub: raise agent", owner, hub, raise, d.raiseAgentId);
        _registerAgent("AgentHub: cut agent", owner, hub, cut, d.cutAgentId);
    }

    /// @dev Both agents are permissioned to the Router, so only a routed workflow report can execute them.
    function _agentInput(
        CapsConfig.Config memory config,
        CapsDeployment.Deployment memory d,
        address agent,
        address oracle,
        uint256 minimumDelay,
        address[] memory permissionedSenders
    )
        private
        pure
        returns (IAgentConfigurator.AgentRegistrationInput memory input)
    {
        input.admin = config.roles.agentAdmin;
        input.riskOracle = oracle;
        input.isAgentEnabled = true;
        input.isAgentPermissioned = permissionedSenders.length != 0;
        input.isMarketsFromAgentEnabled = true;
        input.agentAddress = agent;
        input.expirationPeriod = config.market.expirationSeconds;
        input.minimumDelay = minimumDelay;
        input.updateType = CapsConfig.borrowUpdateType(config.market);
        input.agentContext = abi.encode(_agentContext(config.market, d));
        input.permissionedSenders = permissionedSenders;
    }

    function _registerAgent(
        string memory label,
        address owner,
        address hub,
        IAgentConfigurator.AgentRegistrationInput memory input,
        uint256 expectedId
    )
        private
    {
        (bool sent, bytes memory result) =
            _call(label, owner, hub, abi.encodeCall(IAgentConfigurator.registerAgent, (input)));
        if (sent) require(abi.decode(result, (uint256)) == expectedId, "WireCaps: agent id differs from prediction");
    }

    function _allowShadowWriters(CapsDeployment.Deployment memory d) private {
        address owner = Ownable(d.shadowPool).owner();
        _call(
            "ShadowPool: raise agent writes",
            owner,
            d.shadowPool,
            abi.encodeCall(ShadowPool.setWriter, (d.raiseAgent, true))
        );
        _call(
            "ShadowPool: cut agent writes",
            owner,
            d.shadowPool,
            abi.encodeCall(ShadowPool.setWriter, (d.cutAgent, true))
        );
    }

    function _wireRvm(CapsConfig.Market memory market, CapsDeployment.Deployment memory d) private {
        address owner = Ownable(d.rvm).owner();
        _call("RVM: raise agent", owner, d.rvm, abi.encodeCall(IRvm.setAgent, (d.raiseAgentId, IRvm.Direction.RAISE)));
        _call("RVM: cut agent", owner, d.rvm, abi.encodeCall(IRvm.setAgent, (d.cutAgentId, IRvm.Direction.CUT)));
        _call("RVM: borrow bounds", owner, d.rvm, abi.encodeCall(IRvm.setBounds, (IRvm.CapKind.BORROW, market.bounds)));
    }

    function _addMarket(CapsConfig.Market memory market, CapsDeployment.Deployment memory d) private {
        ICapsParameterRegistry.MarketParams memory params =
            ICapsParameterRegistry.MarketParams({ defaultParams: market.defaults, rvm: d.rvm });
        _call(
            "Registry: market",
            CapsParameterRegistry(d.registry).updater(),
            d.registry,
            abi.encodeCall(ICapsParameterRegistry.addMarket, (_stackPool(market, d), params))
        );
    }

    /// @dev The RiskOracle moves at once; the Router is two step and waits for its new owner's acceptOwnership.
    function _handOver(CapsConfig.Roles memory roles, CapsDeployment.Deployment memory d) private {
        address riskOracleOwner = Ownable(d.riskOracle).owner();
        if (roles.riskOracleOwner != riskOracleOwner) {
            _call(
                "RiskOracle: hand over",
                riskOracleOwner,
                d.riskOracle,
                abi.encodeCall(Ownable.transferOwnership, (roles.riskOracleOwner))
            );
        }
        address routerOwner = Ownable(d.router).owner();
        if (roles.routerOwner != routerOwner) {
            _call(
                "Router: hand over",
                routerOwner,
                d.router,
                abi.encodeCall(Ownable.transferOwnership, (roles.routerOwner))
            );
        }
    }
}

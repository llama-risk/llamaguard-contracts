// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { AgentHub } from "chaos-agents/contracts/AgentHub.sol";
import { IAgentConfigurator } from "chaos-agents/interfaces/IAgentConfigurator.sol";
import { IAgentHub } from "chaos-agents/interfaces/IAgentHub.sol";
import { AaveBorrowCapAgent } from "aave-risk-agents/src/contracts/agent/AaveBorrowCapAgent.sol";
import { AaveSupplyCapAgent } from "aave-risk-agents/src/contracts/agent/AaveSupplyCapAgent.sol";
import { ICapsRangeValidationModule as IRvm } from "../../src/caps-oracle/interfaces/ICapsRangeValidationModule.sol";
import { CapsRangeValidationModuleV3 } from "../../src/caps-oracle/CapsRangeValidationModuleV3.sol";
import { CapsReducerOracle } from "../../src/caps-oracle/CapsReducerOracle.sol";
import { CapsTestBase } from "./CapsTestBase.sol";
import { MockAToken } from "./mocks/MockAToken.sol";
import { MockCapsEngine } from "./mocks/MockCapsEngine.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockRiskOracle } from "./mocks/MockRiskOracle.sol";
import { MockVariableDebtToken } from "./mocks/MockPoolV3.sol";

/// @title CapsSystemBase
/// @notice The Stage 1 system wired end to end on the mock Pool: the real AgentHub (behind an ERC1967 proxy,
///         owner the governance executor), the real `AaveBorrowCapAgent` and `AaveSupplyCapAgent`
///         (aave-risk-agents), CapsRangeValidationModuleV3 and one CapsReducerOracle for both kinds. Four agentIds:
///           borrow raise  - risk oracle MockRiskOracle (the rate limiter workflow), minimumDelay tau
///           borrow cut    - risk oracle the CapsReducerOracle, minimumDelay 0, not permissioned
///           supply raise  - as borrow raise, on the SUPPLY kind
///           supply cut    - risk oracle the same CapsReducerOracle, as borrow cut
///         The agents write caps by delegatecall into MockCapsEngine, which sets the caps on the mock Pool.
/// @dev AgentHub settings follow the assumed Certora settings, so the RVM never checks them
///     .
abstract contract CapsSystemBase is CapsTestBase {
    string internal constant UPDATE_TYPE_SUFFIX = "_Core";

    AgentHub internal hub;
    CapsRangeValidationModuleV3 internal rvm;
    CapsReducerOracle internal reducer; // both kinds
    MockRiskOracle internal raiseOracle;
    MockCapsEngine internal engine;

    AaveBorrowCapAgent internal borrowRaiseAgent;
    AaveBorrowCapAgent internal borrowCutAgent;
    AaveSupplyCapAgent internal supplyRaiseAgent;
    AaveSupplyCapAgent internal supplyCutAgent;

    uint256 internal borrowRaiseId;
    uint256 internal borrowCutId;
    uint256 internal supplyRaiseId;
    uint256 internal supplyCutId;

    mapping(address asset => MockAToken) internal aTokenOf;

    function setUp() public virtual override {
        super.setUp();
        hub = AgentHub(
            address(new ERC1967Proxy(address(new AgentHub()), abi.encodeCall(AgentHub.initialize, (governance))))
        );
        agentHub = address(hub);
        rvm = new CapsRangeValidationModuleV3(
            governance, agentHub, address(pool), riskCouncil, BORROW_UPDATE_TYPE, SUPPLY_UPDATE_TYPE
        );
        // One reducer per Pool, the kind comes from the update type.
        reducer = new CapsReducerOracle(rvm);
        raiseOracle = new MockRiskOracle();
        engine = new MockCapsEngine(pool);

        borrowRaiseAgent = new AaveBorrowCapAgent(agentHub, address(rvm), UPDATE_TYPE_SUFFIX, address(pool));
        borrowCutAgent = new AaveBorrowCapAgent(agentHub, address(rvm), UPDATE_TYPE_SUFFIX, address(pool));
        supplyRaiseAgent = new AaveSupplyCapAgent(agentHub, address(rvm), UPDATE_TYPE_SUFFIX, address(pool));
        supplyCutAgent = new AaveSupplyCapAgent(agentHub, address(rvm), UPDATE_TYPE_SUFFIX, address(pool));

        borrowRaiseId = _registerOnHub(address(borrowRaiseAgent), address(raiseOracle), BORROW_UPDATE_TYPE, TAU);
        borrowCutId = _registerOnHub(address(borrowCutAgent), address(reducer), BORROW_UPDATE_TYPE, 0);
        supplyRaiseId = _registerOnHub(address(supplyRaiseAgent), address(raiseOracle), SUPPLY_UPDATE_TYPE, TAU);
        supplyCutId = _registerOnHub(address(supplyCutAgent), address(reducer), SUPPLY_UPDATE_TYPE, 0);

        vm.startPrank(governance);
        rvm.setAgent(borrowRaiseId, IRvm.Direction.RAISE);
        rvm.setAgent(borrowCutId, IRvm.Direction.CUT);
        rvm.setAgent(supplyRaiseId, IRvm.Direction.RAISE);
        rvm.setAgent(supplyCutId, IRvm.Direction.CUT);
        // TODO(params): global bounds per kind are placeholders. SUPPLY uses the BORROW values.
        rvm.setBounds(IRvm.CapKind.BORROW, _globalBorrowBounds());
        rvm.setBounds(IRvm.CapKind.SUPPLY, _globalBorrowBounds());
        vm.stopPrank();

        _listAToken(address(weth));
        _listAToken(address(usdc));
        _listAToken(address(wbtc));

        // Pool liquidity for borrows.
        weth.mint(address(pool), 1e12 * 1e18);
        usdc.mint(address(pool), 1e12 * 1e6);
        wbtc.mint(address(pool), 1e12 * 1e8);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SETUP HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    function _registerOnHub(
        address agent,
        address oracle,
        string memory updateType,
        uint256 minimumDelay
    )
        internal
        returns (uint256 id)
    {
        IAgentConfigurator.AgentRegistrationInput memory input;
        input.admin = agentAdmin;
        input.riskOracle = oracle;
        input.isAgentEnabled = true;
        input.isAgentPermissioned = false; // cut agent permissioned off
        input.isMarketsFromAgentEnabled = false;
        input.agentAddress = agent;
        input.expirationPeriod = EXPIRATION_PERIOD;
        input.minimumDelay = minimumDelay;
        input.updateType = updateType;
        input.agentContext = abi.encode(address(engine));
        input.allowedMarkets = new address[](3);
        input.allowedMarkets[0] = address(weth);
        input.allowedMarkets[1] = address(usdc);
        input.allowedMarkets[2] = address(wbtc);
        vm.prank(governance);
        id = hub.registerAgent(input);
    }

    function _listAToken(address asset) internal {
        MockAToken a = new MockAToken(MockERC20(asset).decimals());
        aTokenOf[asset] = a;
        pool.setAToken(asset, address(a), 0);
    }

    /// @dev Sets the SUPPLY level of `asset` to `tokens` whole tokens.
    function _setSuppliedTokens(address asset, uint256 tokens) internal {
        MockAToken a = aTokenOf[asset];
        uint256 target = _wei(asset, tokens);
        uint256 cur = a.totalSupply();
        if (target > cur) a.mint(address(this), target - cur);
        else if (target < cur) a.burn(address(this), cur - target);
    }

    /// @dev Owner write, so a fixture can list a new key or set any maxCap.
    function _setRvmRateLimitConfig(address asset, IRvm.CapKind kind, IRvm.RateLimitConfig memory e) internal {
        vm.prank(governance);
        rvm.setRateLimitConfig(asset, kind, e);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // AGENTHUB HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    function _updateType(IRvm.CapKind kind) internal pure returns (string memory) {
        return kind == IRvm.CapKind.BORROW ? BORROW_UPDATE_TYPE : SUPPLY_UPDATE_TYPE;
    }

    function _actions(uint256 agentId, address asset) internal pure returns (IAgentHub.ActionData[] memory a) {
        a = new IAgentHub.ActionData[](1);
        a[0].agentId = agentId;
        a[0].markets = new address[](1);
        a[0].markets[0] = asset;
    }

    /// @dev Live cap of `kind`, whole tokens.
    function _liveCap(address asset, IRvm.CapKind kind) internal view returns (uint256) {
        (uint256 b, uint256 s) = pool.getReserveCaps(asset);
        return kind == IRvm.CapKind.BORROW ? b : s;
    }

    /// @dev The rate limiter workflow publishes a raise to `to`, then a keeper runs AgentHub.execute.
    function _raiseViaHub(address asset, IRvm.CapKind kind, uint256 to) internal returns (bool ok) {
        raiseOracle.publish(_updateType(kind), asset, to, _liveCap(asset, kind));
        uint256 id = kind == IRvm.CapKind.BORROW ? borrowRaiseId : supplyRaiseId;
        try hub.execute(_actions(id, asset)) {
            ok = true;
        } catch { }
    }

    /// @dev A keeper runs AgentHub.execute for the cut agentId. The value comes from CapsReducerOracle.
    function _cutViaHub(address asset, IRvm.CapKind kind) internal returns (bool ok) {
        uint256 id = kind == IRvm.CapKind.BORROW ? borrowCutId : supplyCutId;
        try hub.execute(_actions(id, asset)) {
            ok = true;
        } catch { }
    }

    function _debtToken(address asset) internal view returns (MockVariableDebtToken) {
        return MockVariableDebtToken(pool.getReserveVariableDebtToken(asset));
    }
}

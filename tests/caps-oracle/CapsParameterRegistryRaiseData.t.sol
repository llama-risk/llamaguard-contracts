// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { AaveBorrowCapAgent } from "aave-risk-agents/src/contracts/agent/AaveBorrowCapAgent.sol";
import { CapsSystemBase } from "./CapsSystemBase.sol";
import { CapsParameterRegistry } from "../../src/caps-oracle/CapsParameterRegistry.sol";
import { CapsRangeValidationModuleV3 } from "../../src/caps-oracle/CapsRangeValidationModuleV3.sol";
import { ICapsParameterRegistry as IReg } from "../../src/caps-oracle/interfaces/ICapsParameterRegistry.sol";
import { ICapsRangeValidationModule as IRvm } from "../../src/caps-oracle/interfaces/ICapsRangeValidationModule.sol";
import { MockPoolV3 } from "./mocks/MockPoolV3.sol";

/// @notice `getReservesRaiseData`, the CRE batch view on the registry, against the real RVM and AgentHub.
///         One row per asset in input order. Missing keys give `found` false and never revert. The view reads
///         the RVM stored in the market's params through the keyed preview.
contract CapsParameterRegistryRaiseDataTest is CapsSystemBase {
    uint8 internal constant BORROW = 0;
    uint8 internal constant SUPPLY = 1;

    CapsParameterRegistry internal registry;
    address internal market;

    function _defaultMarketParams(address rvm_) internal pure returns (IReg.MarketParams memory p) {
        p.defaultParams = IReg.WorkflowParams({
            enabled: true, triggerBps: THETA_BPS, marginBps: MARGIN_BPS, minMarginTokens: MIN_MARGIN_TOKENS
        });
        p.rvm = rvm_;
    }

    function setUp() public override {
        super.setUp();
        market = address(pool);
        registry = new CapsParameterRegistry(llamaRiskSafe, riskCouncil);

        IReg.MarketParams memory p = _defaultMarketParams(address(rvm));
        vm.startPrank(riskCouncil);
        registry.addMarket(market, p);
        IReg.ReserveOverride memory none;
        registry.addReserve(market, address(weth), BORROW, none);
        registry.addReserve(market, address(usdc), BORROW, none);
        vm.stopPrank();

        // weth: F1 with the live cap 1,050, below the raise bound 1,100.
        _applyFixture(address(weth), _f1(), 1050);
        _setRvmRateLimitConfig(address(weth), IRvm.CapKind.BORROW, _rateLimitConfigOf(_f1()));
        // usdc: listed in the registry, no RVM rate limit config.
    }

    function _page(address a, address b) internal pure returns (address[] memory list) {
        list = new address[](2);
        list[0] = a;
        list[1] = b;
    }

    function _assertEmpty(IReg.ReserveRaiseData memory r, address asset, string memory why) internal pure {
        assertEq(r.asset, asset, why);
        assertFalse(r.found, why);
        assertFalse(r.params.enabled, why);
        assertEq(r.params.triggerBps, 0, why);
        assertEq(r.cap, 0, why);
        assertEq(r.usage, 0, why);
        assertEq(r.supplyBound, 0, why);
        assertEq(r.headroomTarget, 0, why);
        assertEq(r.maxCap, 0, why);
        assertFalse(r.raiseBlocked, why);
        assertFalse(r.allowed, why);
        assertEq(r.newCap, 0, why);
    }

    function test_Registry_getReservesRaiseData_matchesRvmViews() public view {
        IReg.ReserveRaiseData[] memory rows =
            registry.getReservesRaiseData(market, BORROW, _page(address(weth), address(usdc)));
        assertEq(rows.length, 2);

        IReg.ReserveRaiseData memory r = rows[0];
        assertEq(r.asset, address(weth));
        assertTrue(r.found, "listed key with a config");

        IReg.WorkflowParams memory p = registry.getEffectiveParams(market, address(weth), BORROW);
        assertEq(r.params.enabled, p.enabled);
        assertEq(r.params.triggerBps, p.triggerBps);
        assertEq(r.params.marginBps, p.marginBps);
        assertEq(r.params.minMarginTokens, p.minMarginTokens);

        IRvm.ReserveState memory s = rvm.getReserveState(address(weth), IRvm.CapKind.BORROW);
        assertEq(r.cap, s.cap);
        assertEq(r.usage, s.usage);
        assertEq(r.supplyBound, s.supplyBound);
        assertEq(r.headroomTarget, s.headroomTarget);
        assertEq(r.raiseBlocked, s.raiseBlocked);
        assertEq(r.cap, 1050);
        assertEq(r.usage, F1_DEBT);
        assertEq(r.headroomTarget, F1_L);
        assertEq(r.maxCap, F1_MAX_CAP);

        (bool allowed, uint256 currentCap, uint256 newCap) = rvm.previewRaise(address(weth), IRvm.CapKind.BORROW);
        assertEq(r.allowed, allowed);
        assertEq(r.cap, currentCap);
        assertEq(r.newCap, newCap);
        assertTrue(r.allowed);
        assertEq(r.newCap, F1_RAISE_BOUND);

        _assertEmpty(rows[1], address(usdc), "listed, no RVM config");
    }

    function test_Registry_getReservesRaiseData_missingKeys_foundFalse_noRevert() public {
        address unlisted = address(wbtc);
        _setRvmRateLimitConfig(unlisted, IRvm.CapKind.BORROW, _rateLimitConfigOf(_f1()));

        IReg.ReserveRaiseData[] memory rows =
            registry.getReservesRaiseData(market, BORROW, _page(unlisted, address(weth)));
        _assertEmpty(rows[0], unlisted, "RVM config but not listed in the registry");
        assertTrue(rows[1].found, "input order is kept");

        rows = registry.getReservesRaiseData(makeAddr("unknownMarket"), BORROW, _page(address(weth), unlisted));
        _assertEmpty(rows[0], address(weth), "unknown market");
        _assertEmpty(rows[1], unlisted, "unknown market");

        rows = registry.getReservesRaiseData(market, 7, _page(address(weth), address(usdc)));
        _assertEmpty(rows[0], address(weth), "invalid kind");

        rows = registry.getReservesRaiseData(market, SUPPLY, _page(address(weth), address(usdc)));
        _assertEmpty(rows[0], address(weth), "SUPPLY key not listed");

        rows = registry.getReservesRaiseData(market, BORROW, new address[](0));
        assertEq(rows.length, 0, "empty page");
    }

    function test_Registry_getReservesRaiseData_rvmUnset_foundFalse() public {
        assertTrue(registry.getReservesRaiseData(market, BORROW, _page(address(weth), address(usdc)))[0].found);

        // address(0) means "not set": every row is found = false, and the view does not revert.
        vm.prank(riskCouncil);
        registry.setMarketParams(market, _defaultMarketParams(address(0)));

        IReg.ReserveRaiseData[] memory rows =
            registry.getReservesRaiseData(market, BORROW, _page(address(weth), address(usdc)));
        _assertEmpty(rows[0], address(weth), "no RVM set");
        _assertEmpty(rows[1], address(usdc), "no RVM set");

        // A market added with no RVM gives the same.
        CapsParameterRegistry fresh = new CapsParameterRegistry(llamaRiskSafe, riskCouncil);
        vm.startPrank(riskCouncil);
        fresh.addMarket(market, _defaultMarketParams(address(0)));
        IReg.ReserveOverride memory none;
        fresh.addReserve(market, address(weth), BORROW, none);
        vm.stopPrank();
        _assertEmpty(
            fresh.getReservesRaiseData(market, BORROW, _page(address(weth), address(usdc)))[0],
            address(weth),
            "market added with no RVM"
        );
    }

    /// @notice Two markets on one chain with different RVMs (for example V3 and V4): each row
    ///         reads the RVM of its own market.
    function test_Registry_getReservesRaiseData_twoMarkets_differentRvms() public {
        // Second market: its own Pool, its own RVM, its own raise agent on the same AgentHub.
        MockPoolV3 pool2 = new MockPoolV3();
        pool2.listReserve(address(weth), 18, 0, 0);
        pool2.setTotalDebt(address(weth), _wei(address(weth), 400));
        pool2.setSupplyCap(address(weth), 5000);
        pool2.setBorrowCap(address(weth), 450);
        CapsRangeValidationModuleV3 rvm2 = new CapsRangeValidationModuleV3(
            governance, agentHub, address(pool2), riskCouncil, BORROW_UPDATE_TYPE, SUPPLY_UPDATE_TYPE
        );
        AaveBorrowCapAgent raise2 = new AaveBorrowCapAgent(agentHub, address(rvm2), UPDATE_TYPE_SUFFIX, address(pool2));
        uint256 raise2Id = _registerOnHub(address(raise2), address(raiseOracle), BORROW_UPDATE_TYPE, TAU);
        vm.startPrank(governance);
        rvm2.setAgent(raise2Id, IRvm.Direction.RAISE);
        rvm2.setBounds(IRvm.CapKind.BORROW, _globalBorrowBounds());
        rvm2.setRateLimitConfig(address(weth), IRvm.CapKind.BORROW, _rateLimitConfigOf(_f1()));
        vm.stopPrank();

        address market2 = address(pool2);
        vm.startPrank(riskCouncil);
        registry.addMarket(market2, _defaultMarketParams(address(rvm2)));
        IReg.ReserveOverride memory none;
        registry.addReserve(market2, address(weth), BORROW, none);
        vm.stopPrank();

        assertEq(registry.getMarketParams(market).rvm, address(rvm));
        assertEq(registry.getMarketParams(market2).rvm, address(rvm2));

        IReg.ReserveRaiseData memory r1 =
            registry.getReservesRaiseData(market, BORROW, _page(address(weth), address(usdc)))[0];
        IReg.ReserveRaiseData memory r2 =
            registry.getReservesRaiseData(market2, BORROW, _page(address(weth), address(usdc)))[0];
        assertTrue(r1.found, "market 1 reads rvm");
        assertTrue(r2.found, "market 2 reads rvm2");

        IRvm.ReserveState memory s1 = rvm.getReserveState(address(weth), IRvm.CapKind.BORROW);
        IRvm.ReserveState memory s2 = rvm2.getReserveState(address(weth), IRvm.CapKind.BORROW);
        assertEq(r1.cap, s1.cap);
        assertEq(r1.usage, s1.usage);
        assertEq(r2.cap, s2.cap);
        assertEq(r2.usage, s2.usage);
        assertEq(r1.cap, 1050);
        assertEq(r2.cap, 450);
        assertEq(r2.usage, 400);
        (bool allowed2,, uint256 newCap2) = rvm2.previewRaise(address(weth), IRvm.CapKind.BORROW);
        assertEq(r2.allowed, allowed2);
        assertEq(r2.newCap, newCap2);

        // Each market holds its own RVM: unsetting one leaves the other found.
        vm.prank(riskCouncil);
        registry.setMarketParams(market2, _defaultMarketParams(address(0)));
        assertFalse(registry.getReservesRaiseData(market2, BORROW, _page(address(weth), address(usdc)))[0].found);
        assertTrue(registry.getReservesRaiseData(market, BORROW, _page(address(weth), address(usdc)))[0].found);
    }

    function test_Registry_getReservesRaiseData_noRaiseAgent_stillFound() public {
        // Decision 0031: the row reads the keyed preview and no agentId. A listed key with a config is found
        // even when no RAISE agentId is registered; `validate` rechecks the agentId during inject.
        vm.prank(governance);
        rvm.setAgent(borrowRaiseId, IRvm.Direction.NONE);

        IReg.ReserveRaiseData memory r =
            registry.getReservesRaiseData(market, BORROW, _page(address(weth), address(usdc)))[0];
        assertTrue(r.found, "found without a RAISE agentId");
        (bool allowed, uint256 currentCap, uint256 newCap) = rvm.previewRaise(address(weth), IRvm.CapKind.BORROW);
        assertEq(r.allowed, allowed);
        assertEq(r.cap, currentCap);
        assertEq(r.newCap, newCap);
        assertEq(r.newCap, F1_RAISE_BOUND);
    }

    function test_Registry_getReservesRaiseData_noAgentHubCall() public {
        // Decisions 0031, 0032: the registry reads only the RVM, never AgentHub.
        vm.expectCall(address(hub), bytes(""), 0);
        IReg.ReserveRaiseData[] memory rows =
            registry.getReservesRaiseData(market, BORROW, _page(address(weth), address(usdc)));
        assertTrue(rows[0].found);
    }

    function test_Registry_getReservesRaiseData_maxCapFollowsRvm() public {
        IRvm.RateLimitConfig memory e = _rateLimitConfigOf(_f1());
        e.maxCap = 1080;
        _setRvmRateLimitConfig(address(weth), IRvm.CapKind.BORROW, e);

        IReg.ReserveRaiseData memory r =
            registry.getReservesRaiseData(market, BORROW, _page(address(weth), address(usdc)))[0];
        assertTrue(r.found);
        assertEq(r.maxCap, 1080, "max cap read from the RVM");
        assertEq(r.newCap, 1080, "the max cap binds the raise");
    }

    function test_Registry_getReservesRaiseData_paramsFollowOverride() public {
        IReg.ReserveOverride memory o;
        o.enabled = IReg.EnabledOverride.OFF;
        o.marginBps = 300;
        vm.prank(riskCouncil);
        registry.setReserveOverride(market, address(weth), BORROW, o);

        IReg.ReserveRaiseData memory r =
            registry.getReservesRaiseData(market, BORROW, _page(address(weth), address(usdc)))[0];
        assertTrue(r.found, "a disabled key is still found");
        assertFalse(r.params.enabled);
        assertEq(r.params.marginBps, 300);
        assertEq(r.params.triggerBps, THETA_BPS, "market default");
    }

    function test_Registry_getReservesRaiseData_frozenReserve_raiseBlocked() public {
        pool.setFrozen(address(weth), true);
        IReg.ReserveRaiseData memory r =
            registry.getReservesRaiseData(market, BORROW, _page(address(weth), address(usdc)))[0];
        assertTrue(r.found);
        assertTrue(r.raiseBlocked);
        assertFalse(r.allowed, "no raise on a frozen reserve");
    }

    function test_Registry_getReservesRaiseData_afterRaise_readsNewCap() public {
        assertTrue(_raiseViaHub(address(weth), IRvm.CapKind.BORROW, F1_RAISE_BOUND), "raise lands");

        IReg.ReserveRaiseData memory r =
            registry.getReservesRaiseData(market, BORROW, _page(address(weth), address(usdc)))[0];
        assertEq(r.cap, F1_RAISE_BOUND);
        assertFalse(r.allowed, "cap already at the raise bound");
    }

    function test_Registry_marketRvm_onlyUpdater_event() public {
        // The registry checks RVM.POOL() == market, so the new RVM sits on the same Pool.
        address newRvm = address(
            new CapsRangeValidationModuleV3(
                governance, agentHub, market, riskCouncil, BORROW_UPDATE_TYPE, SUPPLY_UPDATE_TYPE
            )
        );
        IReg.MarketParams memory p = _defaultMarketParams(newRvm);

        vm.prank(attacker);
        vm.expectRevert(IReg.OnlyUpdater.selector);
        registry.setMarketParams(market, p);

        vm.prank(llamaRiskSafe);
        vm.expectRevert(IReg.OnlyUpdater.selector);
        registry.setMarketParams(market, p);

        vm.expectEmit(address(registry));
        emit IReg.MarketParamsSet(market, p);
        vm.prank(riskCouncil);
        registry.setMarketParams(market, p);
        assertEq(registry.getMarketParams(market).rvm, newRvm);
    }
}

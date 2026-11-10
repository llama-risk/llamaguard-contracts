// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { console2 } from "forge-std/console2.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { IRiskOracle } from "chaos-agents/contracts/dependencies/IRiskOracle.sol";
import { ICapsRangeValidationModule as IRvm } from "../../../src/caps-oracle/interfaces/ICapsRangeValidationModule.sol";
import { ICapsParameterRegistry as IReg } from "../../../src/caps-oracle/interfaces/ICapsParameterRegistry.sol";
import { CapsParameterRegistry } from "../../../src/caps-oracle/CapsParameterRegistry.sol";
import { CapsSystemBase } from "../CapsSystemBase.sol";
import { MockAToken } from "../mocks/MockAToken.sol";
import { CapsSystemHandler } from "./CapsSystemHandler.sol";

/// @title CapsSystemInvariantTest
/// @notice Every CAP-INV entry, on the whole Stage 1 system: the real AgentHub,
///         the real AaveBorrowCapAgent and AaveSupplyCapAgent, CapsRangeValidationModuleV3,
///         CapsReducerOracle and CapsParameterRegistry on the mock Pool, driven by CapsSystemHandler. Also the
///         invariant form of CAP-ACL-01, CAP-ACL-04, CAP-ACL-06, CAP-ACL-11 and CAP-ST-28.
/// @dev Start state, per asset (WETH 18 decimals, USDC 6 decimals): F1 on the BORROW key
///      (D = 1,000 with 100 from the handler's borrower, S = supply cap 5,000, cap 1,085) and a SUPPLY key with
///      3,000 supplied and max cap 20,000. Every key is listed in the registry.
/// forge-config: default.invariant.runs = 48
/// forge-config: default.invariant.depth = 60
contract CapsSystemInvariantTest is CapsSystemBase {
    CapsSystemHandler internal handler;
    CapsParameterRegistry internal registry;
    address[2] internal assets;

    function setUp() public override {
        super.setUp();
        assets = [address(weth), address(usdc)];

        registry = new CapsParameterRegistry(governance, llamaRiskSafe);
        IReg.MarketParams memory p;
        // TODO(params): theta, margin and margin floor are placeholders.
        p.defaultParams = IReg.WorkflowParams({
            enabled: true, triggerBps: THETA_BPS, marginBps: MARGIN_BPS, minMarginTokens: MIN_MARGIN_TOKENS
        });
        vm.prank(llamaRiskSafe);
        registry.addMarket(address(pool), p);

        for (uint256 i = 0; i < 2; i++) {
            address a = assets[i];
            pool.setTotalDebt(a, _wei(a, 900));
            pool.setSupplyCap(a, F1_SUPPLY);
            pool.setBorrowCap(a, 1085);
            uint256 own = _wei(a, 100);
            vm.prank(borrower);
            pool.borrow(a, own, 2, 0, borrower);
            _setRvmRateLimitConfig(a, IRvm.CapKind.BORROW, _rateLimitConfigOf(_f1()));

            _setSuppliedTokens(a, 3000);
            IRvm.RateLimitConfig memory supplyRateLimitConfig = _rateLimitConfigOf(_f1());
            supplyRateLimitConfig.maxCap = 20_000;
            _setRvmRateLimitConfig(a, IRvm.CapKind.SUPPLY, supplyRateLimitConfig);

            IReg.ReserveOverride memory none;
            vm.startPrank(llamaRiskSafe);
            registry.addReserve(address(pool), a, 0, none);
            registry.addReserve(address(pool), a, 1, none);
            vm.stopPrank();
        }

        CapsSystemHandler.Deps memory d;
        d.hub = hub;
        d.rvm = rvm;
        d.raiseOracle = raiseOracle;
        d.pool = pool;
        d.registry = registry;
        d.assets = assets;
        d.aTokens = [aTokenOf[assets[0]], aTokenOf[assets[1]]];
        d.ids = [borrowRaiseId, borrowCutId, supplyRaiseId, supplyCutId];
        d.roles = [governance, riskCouncil, updater, agentAdmin, attacker, borrower];
        d.registryUpdater = llamaRiskSafe;
        handler = new CapsSystemHandler(d);

        // The handler's supply and withdraw act on the aTokens it holds. Move the start supply to it.
        for (uint256 i = 0; i < 2; i++) {
            MockAToken t = aTokenOf[assets[i]];
            t.transfer(address(handler), t.balanceOf(address(this)));
        }

        targetContract(address(handler));
        bytes4[] memory s = new bytes4[](18);
        s[0] = CapsSystemHandler.borrow.selector;
        s[1] = CapsSystemHandler.repay.selector;
        s[2] = CapsSystemHandler.accrue.selector;
        s[3] = CapsSystemHandler.supply.selector;
        s[4] = CapsSystemHandler.withdraw.selector;
        s[5] = CapsSystemHandler.setFrozen.selector;
        s[6] = CapsSystemHandler.setPaused.selector;
        s[7] = CapsSystemHandler.warp.selector;
        s[8] = CapsSystemHandler.manualCapWrite.selector;
        s[9] = CapsSystemHandler.raiseViaHub.selector;
        s[10] = CapsSystemHandler.cutViaHub.selector;
        s[11] = CapsSystemHandler.flashRepayCutReborrow.selector;
        s[12] = CapsSystemHandler.setRateLimitConfig.selector;
        s[13] = CapsSystemHandler.setMaxCap.selector;
        s[14] = CapsSystemHandler.setBounds.selector;
        s[15] = CapsSystemHandler.setHold.selector;
        s[16] = CapsSystemHandler.reRegisterAgent.selector;
        s[17] = CapsSystemHandler.registryWrite.selector;
        targetSelector(StdInvariant.FuzzSelector({ addr: address(handler), selectors: s }));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    function _kinds() internal pure returns (IRvm.CapKind[2] memory k) {
        k = [IRvm.CapKind.BORROW, IRvm.CapKind.SUPPLY];
    }

    function _hasRateLimitConfig(address a, IRvm.CapKind k) internal view returns (bool) {
        return rvm.getKeyState(a, k).maxCap != 0;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CAP-INV
    // ═══════════════════════════════════════════════════════════════════════════

    function invariant_CAP_INV_01_agentWriteNeverAboveMaxCap() public view {
        assertFalse(handler.ghostAgentWriteAboveMaxCap());
    }

    /// @dev Both previews against the RVM `validate` and against the real agent's `validate`, which AgentHub
    ///      calls before it injects.
    function invariant_CAP_INV_02_previewImpliesValidate() public view {
        for (uint256 i = 0; i < 2; i++) {
            for (uint256 j = 0; j < 2; j++) {
                _checkPreviewImpliesValidate(assets[i], _kinds()[j]);
            }
        }
    }

    function _checkPreviewImpliesValidate(address a, IRvm.CapKind k) internal view {
        (uint256 raiseId, uint256 cutId) = handler.agentIds(k);
        uint256 cap = handler.liveCap(a, k);
        (bool allowed, uint256 c1, uint256 to1) = rvm.previewRaise(a, k);
        if (allowed) {
            assertEq(c1, cap, "raise preview current cap");
            assertTrue(handler.validateAt(raiseId, a, cap, to1), "raise preview => validate");
            assertTrue(_agentValidates(raiseId, a, k, cap, to1), "raise preview => agent validate");
        }
        (bool due, uint256 c2, uint256 to2) = rvm.previewCut(a, k);
        if (due) {
            assertEq(c2, cap, "cut preview current cap");
            assertTrue(handler.validateAt(cutId, a, cap, to2), "cut preview => validate");
            assertTrue(_agentValidates(cutId, a, k, cap, to2), "cut preview => agent validate");
        }
    }

    function _agentValidates(
        uint256 id,
        address a,
        IRvm.CapKind k,
        uint256 from,
        uint256 to
    )
        internal
        view
        returns (bool)
    {
        IRiskOracle.RiskParameterUpdate memory u;
        u.timestamp = block.timestamp;
        u.newValue = abi.encode(to);
        u.previousValue = abi.encode(from);
        u.updateType = handler.updateType(k);
        u.updateId = 1;
        u.market = a;
        bytes memory ctx = abi.encode(address(engine));
        if (id == borrowRaiseId) return borrowRaiseAgent.validate(id, ctx, u);
        if (id == borrowCutId) return borrowCutAgent.validate(id, ctx, u);
        if (id == supplyRaiseId) return supplyRaiseAgent.validate(id, ctx, u);
        return supplyCutAgent.validate(id, ctx, u);
    }

    function invariant_CAP_INV_03_reducerReturnsPreviewCut() public view {
        for (uint256 i = 0; i < 2; i++) {
            for (uint256 j = 0; j < 2; j++) {
                _checkReducer(assets[i], _kinds()[j]);
            }
        }
    }

    function _checkReducer(address a, IRvm.CapKind k) internal view {
        (bool due, uint256 cur, uint256 to) = rvm.previewCut(a, k);
        try reducer.getLatestUpdateByParameterAndMarket(handler.updateType(k), a) returns (
            IRiskOracle.RiskParameterUpdate memory u
        ) {
            assertTrue(due, "reducer returned a value while previewCut is false");
            assertEq(abi.decode(u.newValue, (uint256)), to, "newValue = previewCut");
            assertEq(abi.decode(u.previousValue, (uint256)), cur, "previousValue = live cap");
            assertEq(u.market, a);
            assertEq(u.updateId, block.timestamp);
            assertEq(u.timestamp, block.timestamp);
            assertEq(u.updateType, handler.updateType(k));
        } catch {
            assertFalse(due, "reducer reverted while previewCut is true");
        }
    }

    function invariant_CAP_INV_04_cutBandWellFormed() public view {
        for (uint256 i = 0; i < 2; i++) {
            for (uint256 j = 0; j < 2; j++) {
                address a = assets[i];
                IRvm.CapKind k = _kinds()[j];
                if (!_hasRateLimitConfig(a, k)) continue;
                IRvm.ReserveState memory s = rvm.getReserveState(a, k);
                assertLe(s.cutFloor, s.cutTrigger, "lo <= hi");
                assertGe(s.cutFloor, _min(s.usage, handler.effectiveMaxCap(a, k)), "lo >= min(D, C-bar)");
            }
        }
    }

    function invariant_CAP_INV_05_headroomTargetInsideBounds() public view {
        for (uint256 i = 0; i < 2; i++) {
            for (uint256 j = 0; j < 2; j++) {
                address a = assets[i];
                IRvm.CapKind k = _kinds()[j];
                if (!_hasRateLimitConfig(a, k)) continue;
                uint256 maxHeadroom = handler.clampedRateLimitConfig(a, k).maxHeadroom;
                IRvm.ReserveState memory s = rvm.getReserveState(a, k);
                assertGe(s.headroomTarget, (maxHeadroom + 24) / 25, "L >= Lmin");
                assertLe(s.headroomTarget, maxHeadroom, "L <= Lmax");
            }
        }
    }

    function invariant_CAP_INV_06_noRateLimitConfigRejectsBoth() public view {
        for (uint256 i = 0; i < 2; i++) {
            for (uint256 j = 0; j < 2; j++) {
                address a = assets[i];
                IRvm.CapKind k = _kinds()[j];
                if (handler.effectiveMaxCap(a, k) != 0) continue;
                (uint256 raiseId, uint256 cutId) = handler.agentIds(k);
                uint256 cap = handler.liveCap(a, k);
                (bool r, uint256 c1, uint256 n1) = rvm.previewRaise(a, k);
                (bool d, uint256 c2, uint256 n2) = rvm.previewCut(a, k);
                assertFalse(r);
                assertFalse(d);
                assertEq(c1 + n1 + c2 + n2, 0, "(false, 0)");
                assertFalse(handler.validateAt(raiseId, a, cap, cap + 1), "raise refused");
                assertFalse(handler.validateAt(cutId, a, cap, cap > 1 ? cap - 1 : 1), "cut refused");
                assertFalse(handler.validateAt(cutId, a, cap, cap / 2 + 1), "cut refused");
            }
        }
    }

    function invariant_CAP_INV_07_capZeroUntouched() public view {
        for (uint256 i = 0; i < 2; i++) {
            for (uint256 j = 0; j < 2; j++) {
                address a = assets[i];
                IRvm.CapKind k = _kinds()[j];
                (uint256 raiseId, uint256 cutId) = handler.agentIds(k);
                uint256 cap = handler.liveCap(a, k);
                assertFalse(handler.validateAt(raiseId, a, 0, cap + 1), "raise from 0");
                assertFalse(handler.validateAt(cutId, a, 0, 1), "cut from 0");
                assertFalse(handler.validateAt(raiseId, a, cap, 0), "raise to 0");
                assertFalse(handler.validateAt(cutId, a, cap, 0), "cut to 0");
                if (cap == 0) {
                    (bool r,,) = rvm.previewRaise(a, k);
                    (bool d,,) = rvm.previewCut(a, k);
                    assertFalse(r, "no raise from an uncapped reserve");
                    assertFalse(d, "no cut from an uncapped reserve");
                }
            }
        }
    }

    function invariant_CAP_INV_08_kindIsolation() public view {
        assertFalse(handler.ghostKindLeak());
    }

    function invariant_CAP_INV_09_registryIndependence() public view {
        assertFalse(handler.ghostRegistryChangedRvm());
    }

    /// @dev Records every storage access while the check path runs: validate, both previews,
    ///      getReserveState and the CapsReducerOracle read, on every key.
    function invariant_CAP_INV_10_checkPathReadOnly() public {
        vm.record();
        for (uint256 i = 0; i < 2; i++) {
            for (uint256 j = 0; j < 2; j++) {
                _runCheckPath(assets[i], _kinds()[j]);
            }
        }
        address[8] memory watched = [
            address(rvm),
            address(reducer),
            address(pool),
            address(hub),
            handler.debtTokenOf(assets[0]),
            handler.debtTokenOf(assets[1]),
            handler.aTokenAt(0),
            handler.aTokenAt(1)
        ];
        for (uint256 i = 0; i < watched.length; i++) {
            (, bytes32[] memory writes) = vm.accesses(watched[i]);
            assertEq(writes.length, 0, "check path wrote storage");
        }
    }

    function _runCheckPath(address a, IRvm.CapKind k) internal view {
        (uint256 raiseId, uint256 cutId) = handler.agentIds(k);
        uint256 cap = handler.liveCap(a, k);
        rvm.previewRaise(a, k);
        rvm.previewCut(a, k);
        handler.validateAt(raiseId, a, cap, cap + 1);
        handler.validateAt(cutId, a, cap, cap > 1 ? cap - 1 : 1);
        if (_hasRateLimitConfig(a, k)) rvm.getReserveState(a, k);
        try reducer.getLatestUpdateByParameterAndMarket(handler.updateType(k), a) { } catch { }
    }

    /// @dev A revert in any of these calls fails the invariant, so making the calls is the check. Extreme
    ///      inputs: to = 2^256 - 1, from = 2^256 - 1, both agentIds of both kinds, an unregistered agentId, and a
    ///      keyed preview on a market with no config.
    function invariant_CAP_INV_11_checkPathNoRevert() public view {
        for (uint256 i = 0; i < 2; i++) {
            for (uint256 j = 0; j < 2; j++) {
                address a = assets[i];
                IRvm.CapKind k = _kinds()[j];
                (uint256 raiseId, uint256 cutId) = handler.agentIds(k);
                uint256 cap = handler.liveCap(a, k);
                rvm.previewRaise(a, k);
                rvm.previewCut(a, k);
                rvm.previewCut(address(0xdead), k); // an asset with no config
                handler.validateAt(raiseId, a, cap, type(uint256).max);
                handler.validateAt(cutId, a, cap, 1);
                handler.validateAt(cutId, a, type(uint256).max, 1);
                handler.validateAt(99, a, cap, cap + 1);
                if (_hasRateLimitConfig(a, k)) rvm.getReserveState(a, k);
            }
        }
    }

    function invariant_CAP_INV_12_configNeverWritesCap() public view {
        assertFalse(handler.ghostConfigWroteCap());
    }

    function invariant_CAP_INV_13_rateLimitConfigInsideEffectiveBounds() public view {
        assertFalse(handler.ghostRateLimitConfigOutOfBounds());
    }

    /// @dev Recomputes L, the raise cap and the band from the clamped entry and compares with the RVM.
    function invariant_CAP_INV_14_validationClampsToBounds() public view {
        for (uint256 i = 0; i < 2; i++) {
            for (uint256 j = 0; j < 2; j++) {
                address a = assets[i];
                IRvm.CapKind k = _kinds()[j];
                if (!_hasRateLimitConfig(a, k)) continue;
                _checkClamp(a, k);
            }
        }
    }

    function _checkClamp(address a, IRvm.CapKind k) internal view {
        IRvm.RateLimitConfig memory e = handler.clampedRateLimitConfig(a, k);
        IRvm.ReserveState memory s = rvm.getReserveState(a, k);
        uint256 d = s.usage;
        uint256 l = _max(_min(e.maxHeadroom, (d * e.alphaBps) / 10_000), (uint256(e.maxHeadroom) + 24) / 25);
        assertEq(s.headroomTarget, l, "L from clamped maxHeadroom and alpha");
        assertEq(s.raiseCap, _min(_min(d + l, e.maxCap), s.supplyBound), "raise target from clamped maxCap");
        uint256 lo = _min(_max(_max(_min(d + l, s.supplyBound), d), 2), e.maxCap);
        uint256 hi = _max(_min(_min(d + l + (l * e.cutBandBps) / 10_000, e.maxCap), s.supplyBound), lo);
        assertEq(s.cutFloor, lo, "lo");
        assertEq(s.cutTrigger, hi, "hi from clamped band");
    }

    /// @dev CAP-INV-15 to 19 check every agent write that lands against the rule recomputed from the state
    ///      just before the write, in the same block.
    function invariant_CAP_INV_15_raiseInsideRule() public view {
        assertFalse(handler.ghostRaiseOutsideRule(), "raise outside (cap, min(D + L, C-bar, S)]");
    }

    function invariant_CAP_INV_16_noRaiseWhileFrozenOrPaused() public view {
        assertFalse(handler.ghostRaiseWhileBlocked(), "raise on a frozen or paused reserve");
    }

    function invariant_CAP_INV_17_cutInsideBand() public view {
        assertFalse(handler.ghostCutOutsideBand(), "cut with cap <= hi or to outside [lo, hi]");
    }

    function invariant_CAP_INV_18_noCutDuringHold() public view {
        assertFalse(handler.ghostCutDuringHold(), "cut during an active hold");
    }

    function invariant_CAP_INV_19_agentNeverWritesZero() public view {
        assertFalse(handler.ghostAgentWroteZero(), "agent wrote cap 0");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ACCESS CONTROL AND CUT GRIEF, IN INVARIANT FORM
    // ═══════════════════════════════════════════════════════════════════════════

    function invariant_CAP_ACL_01_boundsByGovernanceOnly() public view {
        assertFalse(handler.ghostBoundsByNonOwner());
    }

    function invariant_CAP_ACL_04_rateLimitConfigsByRiskCouncilOrOwner() public view {
        assertFalse(handler.ghostRateLimitConfigByNonWriter());
    }

    function invariant_CAP_ACL_06_holdWriters() public view {
        assertFalse(handler.ghostHoldByNonWriter());
    }

    function invariant_CAP_ACL_11_reducerLinkImmutable() public view {
        assertEq(address(reducer.RVM()), address(rvm));
        assertEq(reducer.BORROW_UPDATE_TYPE_HASH(), keccak256(bytes(BORROW_UPDATE_TYPE)));
        assertEq(reducer.SUPPLY_UPDATE_TYPE_HASH(), keccak256(bytes(SUPPLY_UPDATE_TYPE)));
        assertEq(rvm.POOL(), address(pool));
        assertEq(rvm.AGENT_HUB(), agentHub);
    }

    function invariant_riskCouncilRaiseRule() public view {
        assertFalse(handler.ghostRiskCouncilRaiseRuleBroken());
    }

    /// @dev Known issue: every flash repay-cut-reborrow that lands keeps debt unchanged and
    ///      lowers the cap to a value at most the max cap. Reachability is in the integration test.
    function invariant_CAP_ST_28_cutGriefBounded() public view {
        assertFalse(handler.ghostGriefBroke());
    }

    /// @dev The handler reaches every path the invariants depend on: an agent raise, a flash repay-cut-reborrow,
    ///      a cut through CapsReducerOracle, a hold, an entry write, a bounds write and a registry write. Guards
    ///      against a handler that silently never lands an agent write.
    function test_CAP_INV_handler_reachesEveryPath() public {
        handler.raiseViaHub(0, 0, 0, 0); // WETH BORROW: preview raise 1,085 -> 1,100
        assertEq(handler.agentRaises(), 1, "raise");
        handler.flashRepayCutReborrow(0, 50e18 + 1); // x = 50: cut 1,100 -> 1,045
        assertEq(handler.griefs(), 1, "grief");
        assertEq(handler.liveCap(address(weth), IRvm.CapKind.BORROW), 1045);
        handler.manualCapWrite(0, 0, 1200);
        handler.warp(1); // a new second: the reducer updateId is block.timestamp
        handler.cutViaHub(0, 0);
        assertEq(handler.agentCuts(), 2, "cut");
        handler.setHold(0, 0, 2, 3600, false); // updater: no role
        assertEq(handler.holdWrites(), 0, "updater hold refused");
        handler.setHold(0, 0, 1, 3600, false); // Risk Council Safe
        assertEq(handler.holdWrites(), 1, "hold");
        handler.setRateLimitConfig(0, 0, 1, 800, 500, 1000, 1000); // Risk Council Safe, lowering
        assertEq(handler.rateLimitConfigWrites(), 1, "rateLimitConfig");
        handler.setRateLimitConfig(0, 0, 2, 800, 500, 1000, 1000); // updater: refused
        assertEq(handler.rateLimitConfigWrites(), 1, "updater rateLimitConfig refused");
        handler.setBounds(1, 0, 10_000, 10_000, 10_000, 1 days); // governance, SUPPLY
        assertEq(handler.boundsWrites(), 1, "bounds");
        handler.registryWrite(0, 0, 0, 2, 0); // setEnabled OFF
        assertEq(handler.registryWrites(), 1, "registry");

        invariant_CAP_INV_01_agentWriteNeverAboveMaxCap();
        invariant_CAP_INV_08_kindIsolation();
        invariant_CAP_INV_09_registryIndependence();
        invariant_CAP_INV_12_configNeverWritesCap();
        invariant_CAP_INV_13_rateLimitConfigInsideEffectiveBounds();
        invariant_CAP_INV_15_raiseInsideRule();
        invariant_CAP_INV_16_noRaiseWhileFrozenOrPaused();
        invariant_CAP_INV_17_cutInsideBand();
        invariant_CAP_INV_18_noCutDuringHold();
        invariant_CAP_INV_19_agentNeverWritesZero();
        invariant_CAP_ST_28_cutGriefBounded();
    }

    function afterInvariant() public view {
        console2.log("agent raises", handler.agentRaises());
        console2.log("agent cuts", handler.agentCuts());
        console2.log("cut griefs", handler.griefs());
        console2.log("rateLimitConfig writes", handler.rateLimitConfigWrites());
        console2.log("hold writes", handler.holdWrites());
        console2.log("bounds writes", handler.boundsWrites());
        console2.log("registry writes", handler.registryWrites());
    }
}

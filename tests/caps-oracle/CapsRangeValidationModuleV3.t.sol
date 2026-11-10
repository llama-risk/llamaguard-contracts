// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IRangeValidationModule } from "chaos-agents/interfaces/IRangeValidationModule.sol";
import {
    IAaveV3ConfigEngine as IEngine
} from "aave-v3-origin/src/contracts/extensions/v3-config-engine/IAaveV3ConfigEngine.sol";
import { EngineFlags } from "aave-v3-origin/src/contracts/extensions/v3-config-engine/EngineFlags.sol";
import { ICapsRangeValidationModule as IRvm } from "../../src/caps-oracle/interfaces/ICapsRangeValidationModule.sol";
import { CapsRangeValidationModuleV3 } from "../../src/caps-oracle/CapsRangeValidationModuleV3.sol";
import { CapsReducerOracle } from "../../src/caps-oracle/CapsReducerOracle.sol";
import { ICapsReducerOracle } from "../../src/caps-oracle/interfaces/ICapsReducerOracle.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockCapAgent, RvmTestBase } from "./RvmTestBase.sol";

/// @title CapsRangeValidationModuleV3StateTest
/// @notice CAP-ST entries that target the RVM, on the mock Pool, with F1 and F2.
contract CapsRangeValidationModuleV3StateTest is RvmTestBase {
    address internal w;

    function setUp() public override {
        super.setUp();
        w = address(weth);
    }

    // ─── Raise
    // ────────────────────────────────────────────────────────────────

    function test_CAP_ST_01_raise_notAboveCap_rejected() public {
        _useF1(1100);
        assertFalse(_raise(w, 1100), "to == cap");
        assertFalse(_raise(w, 1090), "to < cap");
    }

    function test_CAP_ST_02_raise_aboveDebtPlusHeadroomTarget_rejected() public {
        _useF1(1085);
        assertTrue(_raise(w, F1_RAISE_BOUND), "to D + L");
        assertFalse(_raise(w, F1_RAISE_BOUND + 1), "to D + L + 1");
    }

    /// Headroom ceiling: alpha * D = 1,000 above maxHeadroom 500, so L = 500 (F2).
    function test_headroomCeiling_maxHeadroomBinds() public {
        Fixture memory f = _f2();
        f.maxCap = 20_000;
        f.supply = 0;
        _useFixture(w, f, 10_400);
        IRvm.ReserveState memory s = _state(w);
        assertEq(s.headroomTarget, F2_L, "L = maxHeadroom");
        assertEq(s.cutTrigger, F2_DEBT + F2_L + F2_L * CUT_CUT_BAND_BPS / 10_000);
        assertTrue(_raise(w, F2_RAISE_BOUND));
        assertFalse(_raise(w, F2_RAISE_BOUND + 1));
    }

    /// Headroom floor: alpha * D = 10 below maxHeadroom / 25 = 20, so L = 20. At D = 0, L is still 20.
    function test_headroomFloor_maxHeadroomOver25() public {
        Fixture memory f = _f1();
        f.debt = 100;
        _useFixture(w, f, 110);
        IRvm.ReserveState memory s = _state(w);
        assertEq(s.headroomTarget, F1_LMIN, "L = maxHeadroom / 25");
        assertEq(s.raiseCap, 120);
        assertTrue(_raise(w, 120));
        assertFalse(_raise(w, 121));

        f.debt = 0;
        _useFixture(w, f, 1200);
        s = _state(w);
        assertEq(s.headroomTarget, F1_LMIN, "floor at D = 0");
        (bool due,, uint256 newCap) = _previewCut(w);
        assertTrue(due);
        assertEq(newCap, F1_LMIN, "cut to Lmin on an unused reserve");
    }

    /// @dev Fuzz: an accepted raise is never above min(D + L, C-bar, S), computed here from the entry.
    function test_CAP_ST_02_fuzz_raiseAtMostBound(
        uint256 debt,
        uint256 cap,
        uint64 maxCap,
        uint256 supply,
        uint16 alphaBps,
        uint64 maxHeadroom,
        uint256 to
    )
        public
    {
        debt = bound(debt, 0, 10_000_000);
        cap = bound(cap, 1, MAX_AAVE_CAP);
        maxCap = uint64(bound(maxCap, 1, 5_000_000));
        supply = bound(supply, 0, MAX_AAVE_CAP);
        alphaBps = uint16(bound(alphaBps, 100, 5000));
        maxHeadroom = uint64(bound(maxHeadroom, 100, 2000));
        to = bound(to, 1, MAX_AAVE_CAP);

        Fixture memory f = Fixture(debt, maxCap, maxHeadroom, alphaBps, CUT_CUT_BAND_BPS, supply);
        _useFixture(w, f, cap);

        uint256 l = (debt * alphaBps) / 10_000;
        if (l > maxHeadroom) l = maxHeadroom;
        l = _max(l, (uint256(maxHeadroom) + 24) / 25);
        uint256 s = supply == 0 ? MAX_AAVE_CAP : supply;
        uint256 bound_ = debt + l;
        if (maxCap < bound_) bound_ = maxCap;
        if (s < bound_) bound_ = s;

        bool ok = _raise(w, to);
        if (ok) {
            assertLe(to, bound_, "raise above min(D + L, C-bar, S)");
            assertGt(to, cap, "raise not up");
        }
        assertEq(ok, cap > 1 && to > cap && to <= bound_, "raise iff cap > 1 and cap < to <= bound");
    }

    function test_CAP_ST_03_raise_aboveMaxCap_rejected() public {
        Fixture memory f = _f1();
        f.maxCap = 1050;
        _useFixture(w, f, 1020);
        assertTrue(_raise(w, 1050));
        assertFalse(_raise(w, 1051));
    }

    function test_CAP_ST_04_raise_aboveSupply_rejected() public {
        Fixture memory f = _f1();
        f.supply = 1060;
        _useFixture(w, f, 1020);
        assertTrue(_raise(w, 1060));
        assertFalse(_raise(w, 1061));
    }

    function test_CAP_ST_05_previewRaise_returnsBound() public {
        _useF1(1085);
        (bool allowed, uint256 currentCap, uint256 newCap) = _previewRaise(w);
        assertTrue(allowed);
        assertEq(currentCap, 1085);
        assertEq(newCap, F1_RAISE_BOUND);

        pool.setBorrowCap(w, 1100);
        (allowed, currentCap, newCap) = _previewRaise(w);
        assertFalse(allowed);
        assertEq(currentCap, 1100);
        assertEq(newCap, 0);
    }

    // ─── Cut
    // ──────────────────────────────────────────────────────────────────

    function test_CAP_ST_06_cut_insideBand_rejected() public {
        _useF1(F1_CUT_TRIGGER);
        assertFalse(_cut(w, F1_CUT_FLOOR), "cap == hi");
        pool.setBorrowCap(w, F1_CUT_TRIGGER + 1);
        assertTrue(_cut(w, F1_CUT_FLOOR), "cap == hi + 1");
    }

    function test_CAP_ST_07_cut_outsideBand_rejected() public {
        _useF1(1200);
        assertTrue(_cut(w, 1100), "lo");
        assertTrue(_cut(w, 1110), "hi");
        assertFalse(_cut(w, 1099), "lo - 1");
        assertFalse(_cut(w, 1111), "hi + 1");
    }

    /// @dev Fuzz: an accepted cut lands in [lo, hi] and only when cap > hi, with lo and hi from the glossary.
    function test_CAP_ST_07_fuzz_cutLandsInBand(
        uint256 debt,
        uint256 cap,
        uint64 maxCap,
        uint256 supply,
        uint16 cutBandBps,
        uint256 to
    )
        public
    {
        debt = bound(debt, 0, 10_000_000);
        cap = bound(cap, 1, MAX_AAVE_CAP);
        maxCap = uint64(bound(maxCap, 1, 5_000_000));
        supply = bound(supply, 0, MAX_AAVE_CAP);
        cutBandBps = uint16(bound(cutBandBps, 100, 5000));
        to = bound(to, 1, MAX_AAVE_CAP);
        Fixture memory f = Fixture(debt, maxCap, MAX_HEADROOM, ALPHA_BPS, cutBandBps, supply);
        _useFixture(w, f, cap);

        uint256 l = (debt * ALPHA_BPS) / 10_000;
        if (l > MAX_HEADROOM) l = MAX_HEADROOM;
        l = _max(l, (uint256(MAX_HEADROOM) + 24) / 25);
        uint256 s = supply == 0 ? MAX_AAVE_CAP : supply;
        uint256 lo = _min(_max(_max(_min(debt + l, s), debt), 2), maxCap);
        uint256 hi = _max(_min(_min(debt + l + (l * cutBandBps) / 10_000, maxCap), s), lo);

        assertEq(_cut(w, to), cap > hi && lo != 0 && to >= lo && to <= hi, "cut iff cap > hi and lo <= to <= hi");
    }

    function test_CAP_ST_08_cut_belowDebt_rejected() public {
        Fixture memory f = _f1();
        f.supply = 900;
        _useFixture(w, f, 1200);
        assertEq(_state(w).cutFloor, 1000, "lo = D");
        assertTrue(_cut(w, 1000));
        assertFalse(_cut(w, 999));
        assertFalse(_cut(w, 900));
    }

    function test_CAP_ST_09_cut_maxCapBelowDebt_setsMaxCap() public {
        Fixture memory f = _f1();
        f.maxCap = 800;
        _useFixture(w, f, 1200);
        IRvm.ReserveState memory s = _state(w);
        assertEq(s.cutFloor, 800);
        assertEq(s.cutTrigger, 800);
        assertTrue(_cut(w, 800));
        assertFalse(_cut(w, 799));
        assertFalse(_cut(w, 801));
    }

    function test_CAP_ST_10_cut_notBelowCap_rejected() public {
        _useF1(1200);
        assertFalse(_cut(w, 1200));
        assertFalse(_cut(w, 1300));
    }

    function test_CAP_ST_11_raise_viaCutAgent_rejected() public {
        _useF1(1085);
        assertFalse(_cut(w, 1100));
        (bool due,,) = _previewCut(w);
        assertFalse(due);
    }

    function test_CAP_ST_12_cut_viaRaiseAgent_rejected() public {
        _useF1(1200);
        assertFalse(_raise(w, 1100));
        (bool allowed,,) = _previewRaise(w);
        assertFalse(allowed);
    }

    function test_CAP_ST_13_validate_staleFrom_rejected() public {
        _useF1(1085);
        assertFalse(_validate(RAISE_AGENT_ID, w, 1080, 1100), "raise, stale from");
        assertTrue(_validate(RAISE_AGENT_ID, w, 1085, 1100), "raise, live from");
        pool.setBorrowCap(w, 1200);
        assertFalse(_validate(CUT_AGENT_ID, w, 1199, 1100), "cut, stale from");
        assertTrue(_validate(CUT_AGENT_ID, w, 1200, 1100), "cut, live from");
    }

    function test_validate_batch_alwaysFalse() public {
        _useF1(1085);
        assertTrue(_raise(w, 1100), "single validate accepts");
        IRangeValidationModule.RangeValidationInput[] memory inputs =
            new IRangeValidationModule.RangeValidationInput[](1);
        inputs[0] = _input(1085, 1100);
        assertFalse(rvm.validate(agentHub, RAISE_AGENT_ID, w, inputs), "batch rejected");
        assertFalse(
            rvm.validate(agentHub, RAISE_AGENT_ID, w, new IRangeValidationModule.RangeValidationInput[](0)), "empty"
        );
    }

    // ─── Hold
    // ─────────────────────────────────────────────────────────────────

    function test_CAP_ST_17_cut_duringHold_rejected() public {
        _useF1(1200);
        uint40 until = uint40(block.timestamp + 3600);
        _setHold(w, IRvm.CapKind.BORROW, until);
        assertEq(_state(w).holdUntil, until);
        assertFalse(_cut(w, 1100));
        (bool due,, uint256 newCap) = _previewCut(w);
        assertFalse(due);
        assertEq(newCap, 0);
    }

    function test_CAP_ST_18_raise_duringHold_unaffected() public {
        _useF1(1085);
        (bool allowedBefore,, uint256 capBefore) = _previewRaise(w);
        _setHold(w, IRvm.CapKind.BORROW, uint40(block.timestamp + 3600));
        assertTrue(_raise(w, 1100));
        (bool allowed,, uint256 newCap) = _previewRaise(w);
        assertEq(allowed, allowedBefore);
        assertEq(newCap, capBefore);
    }

    function test_CAP_ST_19_setHold_beyond24h_reverts() public {
        _useF1(1200);
        uint256 t = block.timestamp;
        _setHold(w, IRvm.CapKind.BORROW, uint40(t + MAX_HOLD_DURATION));
        assertEq(_keyState(w).holdUntil, t + MAX_HOLD_DURATION);
        assertEq(rvm.MAX_HOLD_DURATION(), MAX_HOLD_DURATION);

        vm.expectRevert(
            abi.encodeWithSelector(IRvm.HoldTooLong.selector, uint40(t + MAX_HOLD_DURATION + 1), t + MAX_HOLD_DURATION)
        );
        _setHold(w, IRvm.CapKind.BORROW, uint40(t + MAX_HOLD_DURATION + 1));
    }

    function test_CAP_ST_19_setHold_noRateLimitConfig_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(IRvm.RateLimitConfigNotFound.selector, w, IRvm.CapKind.BORROW));
        _setHold(w, IRvm.CapKind.BORROW, uint40(block.timestamp + 1));
    }

    function test_CAP_ST_20_cut_afterHoldEnd_accepted() public {
        _useF1(1200);
        uint256 t = block.timestamp + 3600;
        _setHold(w, IRvm.CapKind.BORROW, uint40(t));
        vm.warp(t - 1);
        assertFalse(_cut(w, 1100), "t - 1");
        vm.warp(t);
        assertTrue(_cut(w, 1100), "t");
        (bool due,, uint256 newCap) = _previewCut(w);
        assertTrue(due);
        assertEq(newCap, 1100);

        // until 0 clears a hold at once.
        _setHold(w, IRvm.CapKind.BORROW, uint40(block.timestamp + 3600));
        assertFalse(_cut(w, 1100));
        _setHold(w, IRvm.CapKind.BORROW, 0);
        assertTrue(_cut(w, 1100));
    }

    /// The owner writes the entry fields only: the hold and lastIncreaseAt stay in the slot.
    function test_hold_keptAcrossEntryWrite() public {
        _useF1(1200);
        uint40 until = uint40(block.timestamp + 3600);
        _setHold(w, IRvm.CapKind.BORROW, until);
        _setRateLimitConfig(w, IRvm.CapKind.BORROW, _rateLimitConfigOf(_f1()));
        assertEq(_keyState(w).holdUntil, until);
        assertFalse(_cut(w, 1100));
    }

    // ─── Frozen and paused
    // ────────────────────────────────────

    function test_CAP_ST_21_raise_frozenReserve_rejected() public {
        _useF1(1085);
        pool.setFrozen(w, true);
        assertFalse(_raise(w, 1100));
        (bool allowed,, uint256 newCap) = _previewRaise(w);
        assertFalse(allowed);
        assertEq(newCap, 0);
        assertTrue(_state(w).raiseBlocked);
    }

    function test_CAP_ST_22_raise_pausedReserve_rejected() public {
        _useF1(1085);
        pool.setPaused(w, true);
        assertFalse(_raise(w, 1100));
        (bool allowed,, uint256 newCap) = _previewRaise(w);
        assertFalse(allowed);
        assertEq(newCap, 0);
        assertTrue(_state(w).raiseBlocked);
    }

    function test_raise_capOne_rejected() public {
        _useF1(1);
        assertFalse(_raise(w, 2));
        assertFalse(_raise(w, 1100));
        (bool allowed,, uint256 newCap) = _previewRaise(w);
        assertFalse(allowed);
        assertEq(newCap, 0);
    }

    function test_raise_capTwo_accepted() public {
        _useF1(2);
        (bool allowed,, uint256 newCap) = _previewRaise(w);
        assertTrue(allowed);
        assertTrue(_raise(w, newCap));
    }

    function test_CAP_ST_23_cut_frozenOrPaused_accepted() public {
        _useF1(1200);
        pool.setFrozen(w, true);
        assertTrue(_cut(w, 1100), "frozen");
        (bool due,, uint256 newCap) = _previewCut(w);
        assertTrue(due);
        assertEq(newCap, 1100);
        pool.setFrozen(w, false);
        pool.setPaused(w, true);
        assertTrue(_cut(w, 1100), "paused");
        (due,, newCap) = _previewCut(w);
        assertTrue(due);
        assertEq(newCap, 1100);
    }

    // ─── Manual cut
    // ───────────────────────────────────────────

    function _manualCut(uint256 newCap) internal {
        IEngine.CapsUpdate[] memory u = new IEngine.CapsUpdate[](1);
        u[0] = IEngine.CapsUpdate({ asset: w, supplyCap: EngineFlags.KEEP_CURRENT, borrowCap: newCap });
        vm.prank(riskCouncil);
        steward.updateCaps(u);
    }

    /// @dev Unit version on the mock Risk Steward; a fork version is planned too.
    function test_CAP_ST_24_manualCut_withMaxCap_noRaiseAbove() public {
        Fixture memory f = _f1();
        f.debt = 1150; // L = 115
        _useFixture(w, f, 1500);
        // One Safe batch: Risk Steward cap 1,500 -> 1,200 and max cap 1,200.
        _manualCut(1200);
        _setMaxCap(w, 1200);
        assertEq(_liveBorrowCap(w), 1200);
        (bool allowed,,) = _previewRaise(w);
        assertFalse(allowed);
        assertFalse(_raise(w, 1201));
        vm.warp(block.timestamp + TAU);
        (allowed,,) = _previewRaise(w);
        assertFalse(allowed, "after tau");
    }

    function test_CAP_ST_25_manualCut_withoutMaxCap_raiseRestores() public {
        Fixture memory f = _f1();
        f.debt = 1150;
        _useFixture(w, f, 1500);
        _manualCut(1200);
        (bool allowed, uint256 currentCap, uint256 newCap) = _previewRaise(w);
        assertTrue(allowed);
        assertEq(currentCap, 1200);
        assertEq(newCap, 1265);
        assertTrue(_raise(w, 1265));
    }

    /// @dev Unit version of the known issue: repay x, cut, borrow x back. Debt ends unchanged, the cap
    ///      at D - x + L(D - x), never below the debt, and every bound holds.
    function test_CAP_ST_28_cutGrief_flashRepayCutBorrow_bounded() public {
        _useF1(1100);
        _setDebt(w, 950, 0); // flash repay of x = 50
        IRvm.ReserveState memory s = _state(w);
        assertEq(s.headroomTarget, 95);
        assertEq(s.cutTrigger, 1054);
        assertTrue(_cut(w, 1045));
        pool.setBorrowCap(w, 1045); // the agent write
        _setDebt(w, 1000, 0); // borrow x back
        s = _state(w);
        assertEq(s.usage, 1000);
        assertEq(_liveBorrowCap(w) - s.usage, 45, "headroom L(D - x) - x");
        assertLe(_liveBorrowCap(w), F1_RAISE_BOUND);
        (bool allowed,, uint256 newCap) = _previewRaise(w);
        assertTrue(allowed, "the raise restores the headroomTarget");
        assertEq(newCap, F1_RAISE_BOUND);
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
}

/// @title CapsRangeValidationModuleV3AccessTest
/// @notice CAP-ACL entries that target the RVM.
contract CapsRangeValidationModuleV3AccessTest is RvmTestBase {
    address internal w;

    function setUp() public override {
        super.setUp();
        w = address(weth);
    }

    function _unauthorized(address account) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, account);
    }

    function test_CAP_ACL_01_setBounds_notGovernance_reverts() public {
        IRvm.Bounds memory b = _globalBorrowBounds();
        b.alphaBpsLimit = 1000;
        address[3] memory callers = [riskCouncil, updater, attacker];
        for (uint256 i = 0; i < callers.length; ++i) {
            vm.prank(callers[i]);
            vm.expectRevert(_unauthorized(callers[i]));
            rvm.setBounds(IRvm.CapKind.BORROW, b);
        }
        assertEq(rvm.getBounds(IRvm.CapKind.BORROW).alphaBpsLimit, 5000, "unchanged");

        vm.expectEmit(address(rvm));
        emit IRvm.BoundsSet(IRvm.CapKind.BORROW, b);
        vm.prank(governance);
        rvm.setBounds(IRvm.CapKind.BORROW, b);
        IRvm.Bounds memory stored = rvm.getBounds(IRvm.CapKind.BORROW);
        assertEq(stored.alphaBpsLimit, 1000);
        assertEq(stored.cutBandBpsLimit, 5000);
        assertEq(stored.maxIncreaseBps, MAX_INCREASE_BPS);
        assertEq(stored.cooldown, COOLDOWN);
    }

    function test_CAP_ACL_02_setAgent_notOwner_reverts() public {
        _newAgent(7, "BorrowCapUpdate_Prime");
        vm.prank(agentAdmin);
        vm.expectRevert(_unauthorized(agentAdmin));
        rvm.setAgent(7, IRvm.Direction.RAISE);
        assertEq(uint8(rvm.getAgent(7).direction), uint8(IRvm.Direction.NONE));
    }

    function test_CAP_ACL_03_setAgent_invalidAgent_reverts() public {
        vm.startPrank(governance);

        // Agent built on another RVM.
        MockCapAgent other = new MockCapAgent(address(pool), address(0xB0B), agentHub);
        hub.setAgentAddress(7, address(other));
        _setHubUpdateType(7, BORROW_UPDATE_TYPE);
        vm.expectRevert(abi.encodeWithSelector(IRvm.InvalidAgent.selector, 7));
        rvm.setAgent(7, IRvm.Direction.RAISE);

        // Agent on another AgentHub.
        other = new MockCapAgent(address(pool), address(rvm), address(0xBEEF));
        hub.setAgentAddress(8, address(other));
        _setHubUpdateType(8, BORROW_UPDATE_TYPE);
        vm.expectRevert(abi.encodeWithSelector(IRvm.InvalidAgent.selector, 8));
        rvm.setAgent(8, IRvm.Direction.RAISE);

        // Agent on another Pool.
        other = new MockCapAgent(address(0x9a1), address(rvm), agentHub);
        hub.setAgentAddress(9, address(other));
        _setHubUpdateType(9, BORROW_UPDATE_TYPE);
        vm.expectRevert(abi.encodeWithSelector(IRvm.InvalidAgent.selector, 9));
        rvm.setAgent(9, IRvm.Direction.RAISE);

        // Update type of no cap kind.
        other = new MockCapAgent(address(pool), address(rvm), agentHub);
        hub.setAgentAddress(10, address(other));
        _setHubUpdateType(10, "EModeCategoryUpdate_Core");
        vm.expectRevert(abi.encodeWithSelector(IRvm.InvalidAgent.selector, 10));
        rvm.setAgent(10, IRvm.Direction.RAISE);

        // An address with no code.
        hub.setAgentAddress(11, address(0xC0DE));
        _setHubUpdateType(11, BORROW_UPDATE_TYPE);
        vm.expectRevert(abi.encodeWithSelector(IRvm.InvalidAgent.selector, 11));
        rvm.setAgent(11, IRvm.Direction.RAISE);

        // Unknown agentId.
        vm.expectRevert(abi.encodeWithSelector(IRvm.InvalidAgent.selector, 99));
        rvm.setAgent(99, IRvm.Direction.RAISE);
        vm.stopPrank();
    }

    function test_setAgent_updateTypeSuffixMismatch_reverts() public {
        // A Prime update type on a Core RVM: same prefix, different suffix, no match.
        _newAgent(7, "BorrowCapUpdate_Prime");
        _newAgent(8, "SupplyCapUpdate_Prime");
        // Prefix only, or the full type with extra bytes, does not match either.
        _newAgent(9, "BorrowCapUpdate");
        _newAgent(10, "BorrowCapUpdate_Core2");
        _newAgent(11, "");
        vm.startPrank(governance);
        for (uint256 id = 7; id <= 11; ++id) {
            vm.expectRevert(abi.encodeWithSelector(IRvm.InvalidAgent.selector, id));
            rvm.setAgent(id, IRvm.Direction.CUT);
        }
        vm.stopPrank();
    }

    function test_setAgent_kindByExactMatch() public {
        assertEq(rvm.BORROW_UPDATE_TYPE_HASH(), keccak256(bytes(BORROW_UPDATE_TYPE)));
        assertEq(rvm.SUPPLY_UPDATE_TYPE_HASH(), keccak256(bytes(SUPPLY_UPDATE_TYPE)));
        _newAgent(SUPPLY_CUT_AGENT_ID, SUPPLY_UPDATE_TYPE);
        _newAgent(9, BORROW_UPDATE_TYPE);
        vm.startPrank(governance);
        rvm.setAgent(SUPPLY_CUT_AGENT_ID, IRvm.Direction.CUT);
        rvm.setAgent(9, IRvm.Direction.CUT);
        vm.stopPrank();
        assertEq(uint8(rvm.getAgent(SUPPLY_CUT_AGENT_ID).kind), uint8(IRvm.CapKind.SUPPLY));
        assertEq(uint8(rvm.getAgent(9).kind), uint8(IRvm.CapKind.BORROW));
    }

    function test_setAgent_kindDerivedFromUpdateType() public {
        _newAgent(SUPPLY_RAISE_AGENT_ID, SUPPLY_UPDATE_TYPE);
        vm.expectEmit(address(rvm));
        emit IRvm.AgentSet(SUPPLY_RAISE_AGENT_ID, IRvm.Direction.RAISE, IRvm.CapKind.SUPPLY);
        vm.prank(governance);
        rvm.setAgent(SUPPLY_RAISE_AGENT_ID, IRvm.Direction.RAISE);
        IRvm.AgentConfig memory a = rvm.getAgent(SUPPLY_RAISE_AGENT_ID);
        assertEq(uint8(a.direction), uint8(IRvm.Direction.RAISE));
        assertEq(uint8(a.kind), uint8(IRvm.CapKind.SUPPLY));

        IRvm.AgentConfig memory b = rvm.getAgent(RAISE_AGENT_ID);
        assertEq(uint8(b.kind), uint8(IRvm.CapKind.BORROW));
        assertEq(uint8(rvm.getAgent(CUT_AGENT_ID).direction), uint8(IRvm.Direction.CUT));
    }

    function test_CAP_ACL_04_setRateLimitConfig_notRiskCouncilOrOwner_reverts() public {
        _useF1(1100);
        IRvm.RateLimitConfig memory e = _rateLimitConfigOf(_f1());
        e.maxCap = 800;
        address[3] memory callers = [updater, agentAdmin, attacker];
        for (uint256 i = 0; i < callers.length; ++i) {
            vm.prank(callers[i]);
            vm.expectRevert(abi.encodeWithSelector(IRvm.OnlyRiskCouncilOrOwner.selector, callers[i]));
            rvm.setRateLimitConfig(w, IRvm.CapKind.BORROW, e);
        }
        assertEq(_keyState(w).maxCap, F1_MAX_CAP);

        vm.expectEmit(address(rvm));
        emit IRvm.RateLimitConfigSet(w, IRvm.CapKind.BORROW, e, riskCouncil);
        vm.prank(riskCouncil);
        rvm.setRateLimitConfig(w, IRvm.CapKind.BORROW, e);
        assertEq(_keyState(w).maxCap, 800);
        vm.prank(governance);
        rvm.setRateLimitConfig(w, IRvm.CapKind.BORROW, _rateLimitConfigOf(_f1()));
        assertEq(_keyState(w).maxCap, F1_MAX_CAP);
    }

    function test_CAP_ACL_06_setHold_notRiskCouncil_reverts() public {
        _useF1(1200);
        address[4] memory callers = [agentAdmin, attacker, governance, updater];
        for (uint256 i = 0; i < callers.length; ++i) {
            vm.prank(callers[i]);
            vm.expectRevert(abi.encodeWithSelector(IRvm.OnlyRiskCouncil.selector, callers[i]));
            rvm.setHold(w, IRvm.CapKind.BORROW, uint40(block.timestamp + 1));
        }
        assertEq(_keyState(w).holdUntil, 0);

        vm.prank(riskCouncil);
        rvm.setHold(w, IRvm.CapKind.BORROW, uint40(block.timestamp + 20));
        assertEq(_keyState(w).holdUntil, block.timestamp + 20);
    }

    function test_CAP_ACL_08_agentHubAdmins_noRvmRole() public {
        _useF1(1200);
        _expectAllSettersRevert(agentAdmin);
        vm.prank(agentAdmin);
        vm.expectRevert(abi.encodeWithSelector(IRvm.OnlyRiskCouncil.selector, agentAdmin));
        rvm.setHold(w, IRvm.CapKind.BORROW, uint40(block.timestamp + 10));
        // The AgentHub contract itself and the old updater address have no role either.
        _expectAllSettersRevert(agentHub);
        _expectAllSettersRevert(updater);
    }

    /// @dev Every setter except setHold reverts for `caller`.
    function _expectAllSettersRevert(address caller) internal {
        IRvm.Bounds memory b = _globalBorrowBounds();
        IRvm.RateLimitConfig memory e = _rateLimitConfigOf(_f1());
        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(IRvm.OnlyRiskCouncilOrOwner.selector, caller));
        rvm.setRateLimitConfig(w, IRvm.CapKind.BORROW, e);
        vm.expectRevert(_unauthorized(caller));
        rvm.setBounds(IRvm.CapKind.BORROW, b);
        vm.expectRevert(_unauthorized(caller));
        rvm.setAgent(RAISE_AGENT_ID, IRvm.Direction.NONE);
        vm.expectRevert(_unauthorized(caller));
        rvm.setRiskCouncil(caller);
        vm.expectRevert(_unauthorized(caller));
        rvm.transferOwnership(caller);
        vm.expectRevert(_unauthorized(caller));
        rvm.renounceOwnership();
        vm.stopPrank();
    }

    function test_CAP_ACL_09_roleSetters_notOwner_reverts() public {
        address newAccount = makeAddr("newAccount");
        vm.prank(riskCouncil);
        vm.expectRevert(_unauthorized(riskCouncil));
        rvm.setRiskCouncil(newAccount);

        vm.startPrank(governance);
        vm.expectRevert(IRvm.ZeroAddress.selector);
        rvm.setRiskCouncil(address(0));
        vm.expectEmit(address(rvm));
        emit IRvm.RiskCouncilChanged(riskCouncil, newAccount);
        rvm.setRiskCouncil(newAccount);
        // renounceOwnership is disabled, so the RVM always has a governance owner.
        vm.expectRevert(IRvm.NotSupported.selector);
        rvm.renounceOwnership();
        vm.stopPrank();
        assertEq(rvm.riskCouncil(), newAccount);
        assertEq(rvm.owner(), governance);

        // Ownable2Step: the new owner must accept.
        address newGov = makeAddr("newGov");
        vm.prank(governance);
        rvm.transferOwnership(newGov);
        assertEq(rvm.owner(), governance);
        vm.prank(newGov);
        rvm.acceptOwnership();
        assertEq(rvm.owner(), newGov);
    }

    function test_CAP_ACL_09_constructor_zeroAddress_reverts() public {
        string memory b = BORROW_UPDATE_TYPE;
        string memory s = SUPPLY_UPDATE_TYPE;
        vm.expectRevert(IRvm.ZeroAddress.selector);
        new CapsRangeValidationModuleV3(governance, address(0), address(pool), riskCouncil, b, s);
        vm.expectRevert(IRvm.ZeroAddress.selector);
        new CapsRangeValidationModuleV3(governance, agentHub, address(0), riskCouncil, b, s);
        vm.expectRevert(IRvm.ZeroAddress.selector);
        new CapsRangeValidationModuleV3(governance, agentHub, address(pool), address(0), b, s);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new CapsRangeValidationModuleV3(address(0), agentHub, address(pool), riskCouncil, b, s);
    }

    function test_constructor_invalidUpdateTypes_reverts() public {
        string memory b = BORROW_UPDATE_TYPE;
        string memory s = SUPPLY_UPDATE_TYPE;
        vm.expectRevert(IRvm.InvalidUpdateTypes.selector);
        new CapsRangeValidationModuleV3(governance, agentHub, address(pool), riskCouncil, "", s);
        vm.expectRevert(IRvm.InvalidUpdateTypes.selector);
        new CapsRangeValidationModuleV3(governance, agentHub, address(pool), riskCouncil, b, "");
        vm.expectRevert(IRvm.InvalidUpdateTypes.selector);
        new CapsRangeValidationModuleV3(governance, agentHub, address(pool), riskCouncil, "", "");
        vm.expectRevert(IRvm.InvalidUpdateTypes.selector);
        new CapsRangeValidationModuleV3(governance, agentHub, address(pool), riskCouncil, b, b);
    }

    function test_CAP_ACL_10_noDependencySetter() public {
        assertEq(rvm.AGENT_HUB(), agentHub);
        assertEq(rvm.POOL(), address(pool));
        string[6] memory setters = [
            "setAgentHub(address)",
            "setPool(address)",
            "setReader(address)",
            "setRegistry(address)",
            "setUpdater(address)",
            "setMarket(address)"
        ];
        vm.startPrank(governance);
        for (uint256 i = 0; i < setters.length; ++i) {
            (bool ok,) = address(rvm).call(abi.encodeWithSignature(setters[i], address(0xdead)));
            assertFalse(ok, setters[i]);
        }
        rvm.setBounds(IRvm.CapKind.BORROW, _globalBorrowBounds());
        rvm.setAgent(RAISE_AGENT_ID, IRvm.Direction.NONE);
        rvm.setRiskCouncil(attacker);
        vm.stopPrank();
        assertEq(rvm.AGENT_HUB(), agentHub);
        assertEq(rvm.POOL(), address(pool));
    }

    function test_CAP_ACL_10_otherAgentHub_rejected() public {
        _useF1(1200);
        IRangeValidationModule.RangeValidationInput memory input = _input(1200, 1100);
        assertTrue(rvm.validate(agentHub, CUT_AGENT_ID, w, input));
        assertFalse(rvm.validate(address(0xBEEF), CUT_AGENT_ID, w, input));
    }

    function test_CAP_ACL_15_views_anyCaller() public {
        _useF1(1200);
        vm.startPrank(attacker);
        (bool due, uint256 currentCap, uint256 newCap) = _previewCut(w);
        assertTrue(due);
        assertEq(currentCap, 1200);
        assertEq(newCap, 1100);
        assertTrue(_cut(w, 1100));
        (bool allowed,,) = _previewRaise(w);
        assertFalse(allowed);
        assertEq(_state(w).cap, 1200);
        vm.stopPrank();
    }

    /// Decision 0033: the RVM keeps no index per (kind, direction), so a second agentId for the same slot
    /// registers without a revert. Both validate under the same rule.
    function test_CAP_ACL_19_setAgent_secondAgentIdSameSlot_accepted() public {
        _useF1(1085);
        _newAgent(9, BORROW_UPDATE_TYPE);
        vm.expectEmit(address(rvm));
        emit IRvm.AgentSet(9, IRvm.Direction.RAISE, IRvm.CapKind.BORROW);
        vm.prank(governance);
        rvm.setAgent(9, IRvm.Direction.RAISE);

        IRvm.AgentConfig memory a = rvm.getAgent(9);
        assertEq(uint8(a.direction), uint8(IRvm.Direction.RAISE));
        assertEq(uint8(a.kind), uint8(IRvm.CapKind.BORROW));
        assertEq(uint8(rvm.getAgent(RAISE_AGENT_ID).direction), uint8(IRvm.Direction.RAISE), "first kept");
        assertTrue(_validate(RAISE_AGENT_ID, w, 1085, 1100), "first raise agentId");
        assertTrue(_validate(9, w, 1085, 1100), "second raise agentId, same rule");
        assertFalse(_validate(9, w, 1085, 1101), "second agentId is still bounded");
    }

    /// Unregistering emits AgentSet with the kind the agentId was registered with.
    function test_CAP_ACL_19_unregister_emitsRegisteredKind() public {
        vm.expectEmit(address(rvm));
        emit IRvm.AgentSet(RAISE_AGENT_ID, IRvm.Direction.NONE, IRvm.CapKind.BORROW);
        vm.prank(governance);
        rvm.setAgent(RAISE_AGENT_ID, IRvm.Direction.NONE);
        assertEq(uint8(rvm.getAgent(RAISE_AGENT_ID).direction), uint8(IRvm.Direction.NONE));
        _useF1(1085);
        assertFalse(_raise(w, 1100), "unregistered agentId rejected");
    }

    function test_setAgent_none_unregistered_noop() public {
        vm.recordLogs();
        vm.prank(governance);
        rvm.setAgent(99, IRvm.Direction.NONE);
        assertEq(vm.getRecordedLogs().length, 0, "no event");
        assertEq(uint8(rvm.getAgent(99).direction), uint8(IRvm.Direction.NONE));
    }

    /// Max cap 0 retires the key: the whole slot clears, both directions are rejected, the previews return
    /// (false, 0, 0) and the reducer reverts NoCutDue. The Risk Council Safe may retire.
    function test_CAP_ACL_20_retire_clearsSlot() public {
        _useF1(1200);
        uint40 until = uint40(block.timestamp + 3600);
        _setHold(w, IRvm.CapKind.BORROW, until);
        (bool due,,) = _previewCut(w);
        assertFalse(due, "held");

        _setMaxCap(w, 0);
        IRvm.KeyState memory k = _keyState(w);
        assertEq(k.maxCap, 0);
        assertEq(k.maxHeadroom, 0);
        assertEq(k.alphaBps, 0);
        assertEq(k.cutBandBps, 0);
        assertEq(k.holdUntil, 0, "hold cleared on retire");
        assertEq(k.lastIncreaseAt, 0);

        (bool ok, uint256 currentCap, uint256 newCap) = _previewCut(w);
        assertFalse(ok);
        assertEq(currentCap, 0);
        assertEq(newCap, 0);
        assertFalse(_cut(w, F1_CUT_FLOOR));
        CapsReducerOracle reducer = new CapsReducerOracle(IRvm(address(rvm)));
        vm.expectRevert(abi.encodeWithSelector(ICapsReducerOracle.NoCutDue.selector, w));
        reducer.getLatestUpdateByParameterAndMarket(BORROW_UPDATE_TYPE, w);
        vm.expectRevert(abi.encodeWithSelector(IRvm.RateLimitConfigNotFound.selector, w, IRvm.CapKind.BORROW));
        rvm.getReserveState(w, IRvm.CapKind.BORROW);

        pool.setBorrowCap(w, 1085);
        (ok,,) = _previewRaise(w);
        assertFalse(ok);
        assertFalse(_raise(w, F1_RAISE_BOUND));

        // Listed again by the owner: no hold.
        _useF1(1200);
        (due,,) = _previewCut(w);
        assertTrue(due, "re-added key starts with no hold");
    }

    /// Max cap 1 is the lowest value that still drives a cut: a cap above it is cut down to 1.
    function test_CAP_ACL_20_maxCapOne_keepsCutLeg() public {
        _useF1(1200);
        _setMaxCap(w, 1);
        (bool due, uint256 currentCap, uint256 newCap) = _previewCut(w);
        assertTrue(due);
        assertEq(currentCap, 1200);
        assertEq(newCap, 1);
        assertTrue(_cut(w, 1));
    }

    /// CAP-ACL-20: the Risk Council Safe can lower the bps fields to 0, and maxCap and maxHeadroom to 1.
    function test_CAP_ACL_20_setRateLimitConfig_lowerToMinimum_succeeds() public {
        _useF1(1200);
        IRvm.RateLimitConfig memory e = _rateLimitConfigOf(_f1());
        e.maxHeadroom = 1;
        vm.prank(riskCouncil);
        rvm.setRateLimitConfig(w, IRvm.CapKind.BORROW, e);
        assertEq(_keyState(w).maxHeadroom, 1);
        e.alphaBps = 0;
        vm.prank(riskCouncil);
        rvm.setRateLimitConfig(w, IRvm.CapKind.BORROW, e);
        assertEq(_keyState(w).alphaBps, 0);
        e.cutBandBps = 0;
        vm.prank(riskCouncil);
        rvm.setRateLimitConfig(w, IRvm.CapKind.BORROW, e);
        assertEq(_keyState(w).cutBandBps, 0);
        e.maxCap = 1;
        vm.prank(riskCouncil);
        rvm.setRateLimitConfig(w, IRvm.CapKind.BORROW, e);
        IRvm.KeyState memory k = _keyState(w);
        assertEq(k.maxCap, 1);
        assertEq(k.maxHeadroom, 1);
        assertEq(k.alphaBps, 0);
        assertEq(k.cutBandBps, 0);
        assertTrue(_cut(w, 1), "the key still drives a cut to the max cap");
    }

    /// CAP-ACL-20: fuzzed, lowering any field from a valid entry never reverts.
    function testFuzz_CAP_ACL_20_lowerAnyField_succeeds(
        uint64 maxHeadroom,
        uint16 alphaBps,
        uint16 cutBandBps,
        uint64 maxCap
    )
        public
    {
        IRvm.Bounds memory g = _globalBorrowBounds();
        _setRateLimitConfig(
            w, IRvm.CapKind.BORROW, IRvm.RateLimitConfig(5_000_000, 2000, g.alphaBpsLimit, g.cutBandBpsLimit)
        );
        maxHeadroom = uint64(bound(maxHeadroom, 1, 2000));
        alphaBps = uint16(bound(alphaBps, 0, g.alphaBpsLimit));
        cutBandBps = uint16(bound(cutBandBps, 0, g.cutBandBpsLimit));
        maxCap = uint64(bound(maxCap, 1, 5_000_000));
        vm.prank(riskCouncil);
        rvm.setRateLimitConfig(w, IRvm.CapKind.BORROW, IRvm.RateLimitConfig(maxCap, maxHeadroom, alphaBps, cutBandBps));
        IRvm.KeyState memory k = _keyState(w);
        assertEq(k.maxCap, maxCap);
        assertEq(k.maxHeadroom, maxHeadroom);
        assertEq(k.alphaBps, alphaBps);
        assertEq(k.cutBandBps, cutBandBps);
        assertEq(k.lastIncreaseAt, 0, "a lowering never starts the cooldown");
    }

    /// CAP-INV-14: a later narrowing of the global bps limits clamps the stored entry at read time.
    function test_CAP_INV_14_globalNarrowing_clampsAtRead() public {
        IRvm.RateLimitConfig memory e = _rateLimitConfigOf(_f1());
        e.alphaBps = 5000; // L = 500
        _applyFixture(w, _f1(), 1085);
        _setRateLimitConfig(w, IRvm.CapKind.BORROW, e);
        assertEq(_state(w).headroomTarget, 500, "L = alpha * D before");

        IRvm.Bounds memory b = _globalBorrowBounds();
        b.alphaBpsLimit = 300;
        b.cutBandBpsLimit = 0;
        vm.prank(governance);
        rvm.setBounds(IRvm.CapKind.BORROW, b);

        IRvm.ReserveState memory s = _state(w);
        assertEq(s.headroomTarget, 30, "alpha clamped to 300 bps");
        assertEq(s.cutTrigger, s.cutFloor, "band clamped to 0");
        assertEq(_keyState(w).alphaBps, 5000, "stored kept");
        assertEq(s.raiseCap, F1_DEBT + 30);

        // A new entry above the narrowed limit reverts.
        vm.expectRevert(IRvm.RateLimitConfigOutOfBounds.selector);
        _setRateLimitConfig(w, IRvm.CapKind.BORROW, e);
    }

    /// CAP-INV-14: the clamp only lowers. Fields below every limit, including bps fields at 0, are used as stored.
    function test_CAP_INV_14_clampOnlyLowers() public {
        IRvm.RateLimitConfig memory e = _rateLimitConfigOf(_f1());
        e.maxHeadroom = 1;
        e.alphaBps = 0;
        e.cutBandBps = 0;
        _applyFixture(w, _f1(), 1200);
        _setRateLimitConfig(w, IRvm.CapKind.BORROW, e);

        IRvm.ReserveState memory s = _state(w);
        assertEq(s.headroomTarget, 1, "alpha 0: L at the floor ceil(1 / 25)");
        assertEq(s.raiseCap, F1_DEBT + 1, "raise target D + 1");
        assertEq(s.cutFloor, F1_DEBT + 1);
        assertEq(s.cutTrigger, F1_DEBT + 1, "band 0: no band");
        assertEq(s.maxCap, F1_MAX_CAP);

        IRvm.Bounds memory b = _globalBorrowBounds();
        b.alphaBpsLimit = 10_000;
        b.cutBandBpsLimit = 10_000;
        vm.prank(governance);
        rvm.setBounds(IRvm.CapKind.BORROW, b);
        s = _state(w);
        assertEq(s.headroomTarget, 1, "widening never lifts a field");
        assertEq(s.cutTrigger, F1_DEBT + 1);
    }
}

/// @title CapsRangeValidationModuleV3WriteRulesTest
/// @notice Entry write rules: the owner writes freely, the Risk Council Safe within the relative raise limit
///         and the cooldown, and never lists a new key. bps fields stay within the global limits for both.
contract CapsRangeValidationModuleV3WriteRulesTest is RvmTestBase {
    address internal w;

    function setUp() public override {
        super.setUp();
        w = address(weth);
        vm.warp(1_750_000_000);
        _useF1(1085); // maxCap 10,000
    }

    function _rcSetMaxCap(uint64 maxCap) internal {
        _setMaxCap(w, maxCap);
    }

    /// @dev The stored entry with maxCap changed. Built before `vm.expectRevert`, which applies to the next call.
    function _cfgMaxCap(uint64 maxCap) internal view returns (IRvm.RateLimitConfig memory e) {
        IRvm.KeyState memory k = _keyState(w);
        e = IRvm.RateLimitConfig(maxCap, k.maxHeadroom, k.alphaBps, k.cutBandBps);
    }

    function _cfgMaxHeadroom(uint64 maxHeadroom) internal view returns (IRvm.RateLimitConfig memory e) {
        IRvm.KeyState memory k = _keyState(w);
        e = IRvm.RateLimitConfig(k.maxCap, maxHeadroom, k.alphaBps, k.cutBandBps);
    }

    function _rcWrite(IRvm.RateLimitConfig memory e) internal {
        vm.prank(riskCouncil);
        rvm.setRateLimitConfig(w, IRvm.CapKind.BORROW, e);
    }

    /// @dev Risk Council write that must revert with `err`.
    function _rcWriteReverts(IRvm.RateLimitConfig memory e, bytes memory err) internal {
        vm.prank(riskCouncil);
        vm.expectRevert(err);
        rvm.setRateLimitConfig(w, IRvm.CapKind.BORROW, e);
    }

    function _limit(uint256 maxCap) internal pure returns (uint256) {
        return maxCap * (10_000 + MAX_INCREASE_BPS) / 10_000;
    }

    function test_riskCouncil_raise_relativeLimit() public {
        uint256 limit = _limit(F1_MAX_CAP); // 20,000
        _rcWriteReverts(
            _cfgMaxCap(uint64(limit + 1)), abi.encodeWithSelector(IRvm.IncreaseTooLarge.selector, limit + 1, limit)
        );

        _rcSetMaxCap(uint64(limit));
        IRvm.KeyState memory k = _keyState(w);
        assertEq(k.maxCap, limit);
        assertEq(k.lastIncreaseAt, block.timestamp, "raise starts the cooldown");
    }

    function testFuzz_riskCouncil_raise_relativeLimit(uint64 maxCap) public {
        maxCap = uint64(bound(maxCap, F1_MAX_CAP + 1, 1_000_000));
        uint256 limit = _limit(F1_MAX_CAP);
        if (maxCap > limit) {
            _rcWriteReverts(_cfgMaxCap(maxCap), abi.encodeWithSelector(IRvm.IncreaseTooLarge.selector, maxCap, limit));
        } else {
            _rcSetMaxCap(maxCap);
            assertEq(_keyState(w).maxCap, maxCap);
        }
    }

    function test_riskCouncil_raise_cooldown() public {
        uint256 t = block.timestamp;
        _rcSetMaxCap(11_000);

        vm.warp(t + COOLDOWN - 1);
        _rcWriteReverts(_cfgMaxCap(11_001), abi.encodeWithSelector(IRvm.CooldownActive.selector, t + COOLDOWN));

        // Lowering and bps changes stay free during the cooldown, and do not move it.
        _rcSetMaxCap(10_500);
        IRvm.RateLimitConfig memory e =
            IRvm.RateLimitConfig({ maxCap: 10_500, maxHeadroom: 400, alphaBps: 500, cutBandBps: 500 });
        vm.prank(riskCouncil);
        rvm.setRateLimitConfig(w, IRvm.CapKind.BORROW, e);
        assertEq(_keyState(w).lastIncreaseAt, t);

        // A raise back to the old value is still a raise.
        _rcWriteReverts(_cfgMaxCap(11_000), abi.encodeWithSelector(IRvm.CooldownActive.selector, t + COOLDOWN));

        vm.warp(t + COOLDOWN);
        _rcSetMaxCap(uint64(_limit(10_500)));
        assertEq(_keyState(w).maxCap, _limit(10_500));
        assertEq(_keyState(w).lastIncreaseAt, t + COOLDOWN);
    }

    function _rcSetMaxHeadroom(uint64 maxHeadroom) internal {
        _rcWrite(_cfgMaxHeadroom(maxHeadroom));
    }

    function test_riskCouncil_raiseMaxHeadroom_relativeLimit() public {
        uint256 limit = _limit(MAX_HEADROOM); // 1,000
        _rcWriteReverts(
            _cfgMaxHeadroom(uint64(limit + 1)), abi.encodeWithSelector(IRvm.IncreaseTooLarge.selector, limit + 1, limit)
        );
        _rcSetMaxHeadroom(uint64(limit));
        IRvm.KeyState memory k = _keyState(w);
        assertEq(k.maxHeadroom, limit);
        assertEq(k.lastIncreaseAt, block.timestamp, "maxHeadroom raise starts the cooldown");

        // maxHeadroom 0 is out of bounds, so the Risk Council can never strand a key at L = 0.
        _rcWriteReverts(_cfgMaxHeadroom(0), abi.encodeWithSelector(IRvm.RateLimitConfigOutOfBounds.selector));
    }

    /// maxCap and maxHeadroom share one cooldown per key; both may rise in the same write.
    function test_riskCouncil_sharedCooldown() public {
        uint256 t = block.timestamp;
        _rcSetMaxCap(11_000);
        _rcWriteReverts(_cfgMaxHeadroom(550), abi.encodeWithSelector(IRvm.CooldownActive.selector, t + COOLDOWN));

        vm.warp(t + COOLDOWN);
        IRvm.KeyState memory k = _keyState(w);
        vm.prank(riskCouncil);
        rvm.setRateLimitConfig(w, IRvm.CapKind.BORROW, IRvm.RateLimitConfig(12_000, 600, k.alphaBps, k.cutBandBps));
        k = _keyState(w);
        assertEq(k.maxCap, 12_000);
        assertEq(k.maxHeadroom, 600);
        assertEq(k.lastIncreaseAt, t + COOLDOWN);

        _rcWriteReverts(
            _cfgMaxCap(12_001), abi.encodeWithSelector(IRvm.CooldownActive.selector, t + 2 * uint256(COOLDOWN))
        );
        _rcSetMaxHeadroom(100); // lowering stays free
    }

    function test_owner_bypassesRelativeLimitAndCooldown() public {
        _rcSetMaxCap(11_000);
        uint40 lastIncreaseAt = _keyState(w).lastIncreaseAt;

        IRvm.RateLimitConfig memory e = _rateLimitConfigOf(_f1());
        e.maxCap = 5_000_000;
        vm.prank(governance);
        rvm.setRateLimitConfig(w, IRvm.CapKind.BORROW, e);
        e.maxCap = uint64(MAX_AAVE_CAP);
        vm.prank(governance);
        rvm.setRateLimitConfig(w, IRvm.CapKind.BORROW, e);

        IRvm.KeyState memory k = _keyState(w);
        assertEq(k.maxCap, MAX_AAVE_CAP);
        assertEq(k.lastIncreaseAt, lastIncreaseAt, "owner writes do not move the cooldown");
        assertEq(_state(w).maxCap, MAX_AAVE_CAP);
    }

    /// A live entry needs maxHeadroom above 0 and maxCap within 36 bits, for the owner and the Risk Council.
    function test_liveEntryBounds_ownerAndRiskCouncil() public {
        address[2] memory callers = [governance, riskCouncil];
        for (uint256 i; i < 2; ++i) {
            IRvm.RateLimitConfig memory e = _rateLimitConfigOf(_f1());
            e.maxHeadroom = 0;
            vm.prank(callers[i]);
            vm.expectRevert(IRvm.RateLimitConfigOutOfBounds.selector);
            rvm.setRateLimitConfig(w, IRvm.CapKind.BORROW, e);

            e = _rateLimitConfigOf(_f1());
            e.maxCap = uint64(MAX_AAVE_CAP + 1);
            vm.prank(callers[i]);
            vm.expectRevert(IRvm.RateLimitConfigOutOfBounds.selector);
            rvm.setRateLimitConfig(w, IRvm.CapKind.BORROW, e);
        }
    }

    function test_owner_acceptsMaxCapAtMaxValidCap() public {
        IRvm.RateLimitConfig memory e = _rateLimitConfigOf(_f1());
        e.maxCap = uint64(MAX_AAVE_CAP);
        vm.prank(governance);
        rvm.setRateLimitConfig(w, IRvm.CapKind.BORROW, e);
        assertEq(_keyState(w).maxCap, MAX_AAVE_CAP);
    }

    /// The Risk Council reaches MAX_VALID_CAP by relative raises from a stored value at least half of it.
    function test_riskCouncil_acceptsMaxCapAtMaxValidCap() public {
        IRvm.RateLimitConfig memory e = _rateLimitConfigOf(_f1());
        e.maxCap = uint64(MAX_AAVE_CAP / 2 + 1);
        _setRateLimitConfig(w, IRvm.CapKind.BORROW, e);
        vm.warp(block.timestamp + COOLDOWN);
        e.maxCap = uint64(MAX_AAVE_CAP);
        vm.prank(riskCouncil);
        rvm.setRateLimitConfig(w, IRvm.CapKind.BORROW, e);
        assertEq(_keyState(w).maxCap, MAX_AAVE_CAP);
    }

    /// A retire (maxCap 0) skips the live-entry bounds, so maxHeadroom 0 is fine there.
    function test_retire_withZeroMaxHeadroom_ownerAndRiskCouncil() public {
        address[2] memory callers = [governance, riskCouncil];
        for (uint256 i; i < 2; ++i) {
            _setRateLimitConfig(w, IRvm.CapKind.BORROW, _rateLimitConfigOf(_f1()));
            vm.prank(callers[i]);
            rvm.setRateLimitConfig(w, IRvm.CapKind.BORROW, IRvm.RateLimitConfig(0, 0, 0, 0));
            assertEq(_keyState(w).maxCap, 0);
        }
    }

    /// A retire of a key with no entry reverts for both callers, also right after a retire.
    function test_retire_missingKey_reverts_ownerAndRiskCouncil() public {
        address[2] memory callers = [governance, riskCouncil];
        for (uint256 i; i < 2; ++i) {
            vm.prank(callers[i]);
            vm.expectRevert(
                abi.encodeWithSelector(IRvm.RateLimitConfigNotFound.selector, address(usdc), IRvm.CapKind.BORROW)
            );
            rvm.setRateLimitConfig(address(usdc), IRvm.CapKind.BORROW, IRvm.RateLimitConfig(0, 0, 0, 0));

            vm.prank(callers[i]);
            vm.expectRevert(abi.encodeWithSelector(IRvm.RateLimitConfigNotFound.selector, w, IRvm.CapKind.SUPPLY));
            rvm.setRateLimitConfig(w, IRvm.CapKind.SUPPLY, IRvm.RateLimitConfig(0, 0, 0, 0));
        }

        address[2] memory retirers = [riskCouncil, governance];
        for (uint256 i; i < 2; ++i) {
            vm.prank(retirers[i]);
            rvm.setRateLimitConfig(w, IRvm.CapKind.BORROW, IRvm.RateLimitConfig(0, 0, 0, 0));
            assertEq(_keyState(w).maxCap, 0, "existing key retired");
            vm.prank(retirers[(i + 1) % 2]);
            vm.expectRevert(abi.encodeWithSelector(IRvm.RateLimitConfigNotFound.selector, w, IRvm.CapKind.BORROW));
            rvm.setRateLimitConfig(w, IRvm.CapKind.BORROW, IRvm.RateLimitConfig(0, 0, 0, 0));
            _setRateLimitConfig(w, IRvm.CapKind.BORROW, _rateLimitConfigOf(_f1()));
        }
    }

    function test_riskCouncil_cannotListNewKey() public {
        IRvm.RateLimitConfig memory e = _rateLimitConfigOf(_f1());
        vm.prank(riskCouncil);
        vm.expectRevert(
            abi.encodeWithSelector(IRvm.RateLimitConfigNotFound.selector, address(usdc), IRvm.CapKind.BORROW)
        );
        rvm.setRateLimitConfig(address(usdc), IRvm.CapKind.BORROW, e);

        vm.prank(riskCouncil);
        vm.expectRevert(abi.encodeWithSelector(IRvm.RateLimitConfigNotFound.selector, w, IRvm.CapKind.SUPPLY));
        rvm.setRateLimitConfig(w, IRvm.CapKind.SUPPLY, e);

        // After a retire the key is new again.
        _rcSetMaxCap(0);
        vm.prank(riskCouncil);
        vm.expectRevert(abi.encodeWithSelector(IRvm.RateLimitConfigNotFound.selector, w, IRvm.CapKind.BORROW));
        rvm.setRateLimitConfig(w, IRvm.CapKind.BORROW, e);

        // The owner lists it.
        vm.prank(governance);
        rvm.setRateLimitConfig(address(usdc), IRvm.CapKind.BORROW, e);
        assertEq(rvm.getKeyState(address(usdc), IRvm.CapKind.BORROW).maxCap, F1_MAX_CAP);
    }

    function test_bpsAboveGlobalLimit_reverts_anyWriter() public {
        address[2] memory writers = [riskCouncil, governance];
        for (uint256 i = 0; i < writers.length; ++i) {
            IRvm.RateLimitConfig memory e = _rateLimitConfigOf(_f1());
            e.alphaBps = 5001;
            vm.prank(writers[i]);
            vm.expectRevert(IRvm.RateLimitConfigOutOfBounds.selector);
            rvm.setRateLimitConfig(w, IRvm.CapKind.BORROW, e);

            e.alphaBps = 5000;
            e.cutBandBps = 5001;
            vm.prank(writers[i]);
            vm.expectRevert(IRvm.RateLimitConfigOutOfBounds.selector);
            rvm.setRateLimitConfig(w, IRvm.CapKind.BORROW, e);

            e.cutBandBps = 5000;
            vm.prank(writers[i]);
            rvm.setRateLimitConfig(w, IRvm.CapKind.BORROW, e);
            assertEq(_keyState(w).alphaBps, 5000);
        }
    }

    function test_setBounds_bpsAbove100Percent_reverts() public {
        vm.startPrank(governance);
        IRvm.Bounds memory b = _globalBorrowBounds();
        b.alphaBpsLimit = 10_001;
        vm.expectRevert(IRvm.InvalidBounds.selector);
        rvm.setBounds(IRvm.CapKind.BORROW, b);
        b = _globalBorrowBounds();
        b.cutBandBpsLimit = 10_001;
        vm.expectRevert(IRvm.InvalidBounds.selector);
        rvm.setBounds(IRvm.CapKind.BORROW, b);
        b = _globalBorrowBounds();
        b.maxIncreaseBps = 10_001;
        vm.expectRevert(IRvm.InvalidBounds.selector);
        rvm.setBounds(IRvm.CapKind.BORROW, b);

        b = IRvm.Bounds({ alphaBpsLimit: 10_000, cutBandBpsLimit: 10_000, maxIncreaseBps: 10_000, cooldown: 1 });
        rvm.setBounds(IRvm.CapKind.BORROW, b);
        vm.stopPrank();

        // maxIncreaseBps 10_000 and cooldown 1: the Risk Council Safe may double maxCap once per second.
        _rcSetMaxCap(20_000);
        vm.warp(block.timestamp + 1);
        _rcSetMaxCap(40_000);
        assertEq(_keyState(w).maxCap, 40_000);
    }

    function test_setBounds_zeroCooldown_reverts() public {
        IRvm.Bounds memory b = _globalBorrowBounds();
        b.cooldown = 0;
        vm.prank(governance);
        vm.expectRevert(IRvm.InvalidBounds.selector);
        rvm.setBounds(IRvm.CapKind.BORROW, b);
        assertEq(rvm.getBounds(IRvm.CapKind.BORROW).cooldown, COOLDOWN, "unchanged");
    }

    /// maxIncreaseBps 0 stops every Risk Council raise but no lowering.
    function test_maxIncreaseBpsZero_blocksRiskCouncilRaise() public {
        IRvm.Bounds memory b = _globalBorrowBounds();
        b.maxIncreaseBps = 0;
        vm.prank(governance);
        rvm.setBounds(IRvm.CapKind.BORROW, b);
        _rcWriteReverts(
            _cfgMaxCap(uint64(F1_MAX_CAP + 1)),
            abi.encodeWithSelector(IRvm.IncreaseTooLarge.selector, F1_MAX_CAP + 1, F1_MAX_CAP)
        );
        _rcSetMaxCap(uint64(F1_MAX_CAP));
        _rcSetMaxCap(uint64(F1_MAX_CAP - 1));
        assertEq(_keyState(w).maxCap, F1_MAX_CAP - 1);
    }
}

/// @title CapsRangeValidationModuleV3UnitsTest
/// @notice CAP-UNIT entries that target the RVM.
contract CapsRangeValidationModuleV3UnitsTest is RvmTestBase {
    address internal w;

    function setUp() public override {
        super.setUp();
        w = address(weth);
    }

    function test_CAP_UNIT_01_debt_roundsUp() public {
        _useF1(1085);
        _setDebt(w, 1000, 1);
        assertEq(_state(w).usage, 1001);
        _setDebt(w, 1000, 0);
        assertEq(_state(w).usage, 1000);
        _setDebt(w, 0, 0);
        assertEq(_state(w).usage, 0);
    }

    function test_CAP_UNIT_02_decimals_sameResult() public {
        _useFixture(address(usdc), _f1(), 1085);
        _setDebt(address(usdc), 1000, 0);
        assertEq(_state(address(usdc)).usage, 1000, "USDC 1e9 units");
        _useFixture(address(wbtc), _f1(), 1085);
        _setDebt(address(wbtc), 1000, 1);
        assertEq(_state(address(wbtc)).usage, 1001, "WBTC 1e11 + 1 units");
    }

    function test_CAP_UNIT_02_fuzz_decimals_sameResult(uint8 decimals, uint256 debt, uint256 cap) public {
        decimals = uint8(bound(decimals, 0, 36)); // decimals range Aave allows
        debt = bound(debt, 0, 1_000_000);
        cap = bound(cap, 1, 2_000_000);
        MockERC20 token = new MockERC20("T", "T", decimals);
        pool.listReserve(address(token), decimals, 0, 0);
        Fixture memory f = _f1();
        f.debt = debt;
        _useFixture(address(token), f, cap);
        _useFixture(w, f, cap);

        (bool a1, uint256 c1, uint256 n1) = _previewRaise(address(token));
        (bool a2, uint256 c2, uint256 n2) = _previewRaise(w);
        assertEq(a1, a2);
        assertEq(c1, c2);
        assertEq(n1, n2);
        (a1, c1, n1) = _previewCut(address(token));
        (a2, c2, n2) = _previewCut(w);
        assertEq(a1, a2);
        assertEq(c1, c2);
        assertEq(n1, n2);
    }

    /// CAP-INV-02: the keyed preview computes what `validate` accepts for the registered agentId.
    function test_CAP_INV_02_keyedPreviewMatchesValidate(uint256 debt, uint256 cap) public {
        Fixture memory f = _f1();
        f.debt = bound(debt, 0, 20_000);
        _useFixture(w, f, bound(cap, 1, 20_000));
        _checkPreviewMatchesValidate();
    }

    /// CAP-INV-02 fixed cases: F1 at cap 1085 offers a raise, F1 at cap 1200 has a cut due.
    function test_CAP_INV_02_keyedPreviewMatchesValidate_fixedCases() public {
        _useF1(1085);
        (bool allowed, bool due) = _checkPreviewMatchesValidate();
        assertTrue(allowed, "F1 at 1085 offers a raise");
        assertFalse(due);

        _useF1(1200);
        (allowed, due) = _checkPreviewMatchesValidate();
        assertFalse(allowed);
        assertTrue(due, "F1 at 1200 has a cut due");
    }

    /// @dev Checks both previews against `validate` with the registered agentIds, in both directions.
    function _checkPreviewMatchesValidate() internal view returns (bool allowed, bool due) {
        uint256 live = _liveBorrowCap(w);
        IRvm.ReserveState memory s = _state(w);

        uint256 cur;
        uint256 next;
        (allowed, cur, next) = _previewRaise(w);
        assertEq(cur, live, "raise preview reads the live cap");
        if (allowed) assertTrue(_validate(RAISE_AGENT_ID, w, live, next), "raise preview passes validate");
        else assertFalse(_validate(RAISE_AGENT_ID, w, live, s.raiseCap), "no raise offered, validate rejects");

        (due, cur, next) = _previewCut(w);
        assertEq(cur, live, "cut preview reads the live cap");
        if (due) assertTrue(_validate(CUT_AGENT_ID, w, live, next), "cut preview passes validate");
        else assertFalse(_validate(CUT_AGENT_ID, w, live, s.cutFloor), "no cut due, validate rejects");
    }

    function test_CAP_UNIT_03_cap_within36Bits() public {
        Fixture memory f = _f1();
        f.maxCap = uint64(1) << 40;
        f.debt = 1 << 36;
        f.supply = 0; // no supply clamp
        _applyFixture(w, f, 1000);
        vm.prank(governance);
        vm.expectRevert(IRvm.RateLimitConfigOutOfBounds.selector);
        rvm.setRateLimitConfig(w, IRvm.CapKind.BORROW, _rateLimitConfigOf(f));

        f.maxCap = uint64(MAX_AAVE_CAP);
        _useFixture(w, f, 1000);
        (bool allowed,, uint256 newCap) = _previewRaise(w);
        assertTrue(allowed);
        assertEq(newCap, MAX_AAVE_CAP, "usage above 36 bits raises to 2^36 - 1");
        assertFalse(_raise(w, MAX_AAVE_CAP + 1));
        IRvm.ReserveState memory s = _state(w);
        assertLe(s.raiseCap, MAX_AAVE_CAP);
        assertLe(s.cutFloor, MAX_AAVE_CAP);
        assertLe(s.cutTrigger, MAX_AAVE_CAP);
    }

    function test_CAP_UNIT_04_raiseCap_roundsDown() public {
        Fixture memory f = _f1();
        f.debt = 1005; // alpha * D = 100.5
        _useFixture(w, f, 1090);
        (bool allowed,, uint256 newCap) = _previewRaise(w);
        assertTrue(allowed);
        assertEq(newCap, 1105);
        assertFalse(_raise(w, 1106));
    }

    function test_CAP_UNIT_05_cut_headroomWithinOneToken() public {
        _useF1(1200);
        uint256 debtWei = 1000.3e18;
        pool.setTotalDebt(w, debtWei);
        IRvm.ReserveState memory s = _state(w);
        assertEq(s.usage, 1001);
        assertEq(s.headroomTarget, 100);
        (bool due,, uint256 newCap) = _previewCut(w);
        assertTrue(due);
        assertEq(newCap, 1101);
        uint256 headroom = newCap * 1e18 - debtWei;
        assertGe(headroom, s.headroomTarget * 1e18);
        assertLt(headroom, (s.headroomTarget + 1) * 1e18);
    }

    function test_CAP_UNIT_06_alphaD_roundsDown() public {
        Fixture memory f = _f1();
        f.debt = 1005;
        _useFixture(w, f, 1090);
        assertEq(_state(w).headroomTarget, 100);
    }

    function test_CAP_UNIT_07_minHeadroom_roundsUp() public {
        Fixture memory f = _f1();
        f.maxHeadroom = 510;
        f.debt = 100; // alpha * D = 10, below Lmin
        _useFixture(w, f, 1000);
        assertEq(_state(w).headroomTarget, 21, "Lmin = 510 / 25 = 20.4 -> 21");
    }

    /// Small maxHeadroom at D = 0: Lmin rounds up to 1, so the key can still raise and cut.
    function test_CAP_UNIT_07_minHeadroom_smallMaxHeadroom_notStuck(uint64 maxHeadroom) public {
        maxHeadroom = uint64(bound(maxHeadroom, 1, 24));
        Fixture memory f = _f1();
        f.maxHeadroom = maxHeadroom;
        f.debt = 0;

        _useFixture(w, f, 1200);
        IRvm.ReserveState memory s = _state(w);
        assertEq(s.headroomTarget, 1, "Lmin = 1");
        // The cut floors at 2, not the manual freeze value 1.
        assertEq(s.cutFloor, 2);
        (bool due,, uint256 newCap) = _previewCut(w);
        assertTrue(due, "cut possible");
        assertEq(newCap, 2);
        assertFalse(_cut(w, 1));
        assertTrue(_cut(w, 2));

        // At cap 2 with D = 0 nothing moves; once D grows to 2, the raise opens.
        assertEq(_state(w).raiseCap, 1);
        f.debt = 2;
        _useFixture(w, f, 2);
        assertEq(_state(w).raiseCap, 3);
        assertTrue(_raise(w, 3), "raise possible");
    }

    function test_capOne_untouched() public {
        _useF1(1);
        (bool allowed,,) = _previewRaise(w);
        (bool due,,) = _previewCut(w);
        assertFalse(allowed);
        assertFalse(due);
        assertFalse(_raise(w, 2));
        assertFalse(_cut(w, 2));
    }

    /// maxHeadroom 0 would pin L to 0 and the cap to D, so a live entry rejects it.
    function test_CAP_UNIT_07_minHeadroom_zeroMaxHeadroom_reverts() public {
        Fixture memory f = _f1();
        f.maxHeadroom = 0;
        f.debt = 0;
        _applyFixture(w, f, 1200);
        vm.prank(governance);
        vm.expectRevert(IRvm.RateLimitConfigOutOfBounds.selector);
        rvm.setRateLimitConfig(w, IRvm.CapKind.BORROW, _rateLimitConfigOf(f));
    }

    /// @dev Fuzz: with alpha * D below the floor, L equals ceilDiv(maxHeadroom, 25).
    function test_CAP_UNIT_07_fuzz_minHeadroom_isCeilDiv(uint64 maxHeadroom) public {
        maxHeadroom = uint64(bound(maxHeadroom, 1, 5_000_000));
        Fixture memory f = _f1();
        f.maxHeadroom = maxHeadroom;
        f.maxCap = 20_000_000;
        f.supply = 0;
        f.debt = 0;
        _useFixture(w, f, 1);
        assertEq(_state(w).headroomTarget, (uint256(maxHeadroom) + 24) / 25, "Lmin == ceilDiv(maxHeadroom, 25)");
    }

    function test_CAP_UNIT_08_bandTop_roundsDown() public {
        Fixture memory f = _f1();
        f.debt = 950; // L = 95, exact band top 1,054.5
        _useFixture(w, f, 1055);
        assertEq(_state(w).cutTrigger, 1054);
        (bool due,,) = _previewCut(w);
        assertTrue(due, "cap 1,055 is above the band");
        pool.setBorrowCap(w, 1054);
        (due,,) = _previewCut(w);
        assertFalse(due);
    }

    function test_CAP_UNIT_09_bps_aboveBound_reverts() public {
        IRvm.RateLimitConfig memory e = _rateLimitConfigOf(_f1());
        e.alphaBps = 10_001;
        vm.prank(governance);
        vm.expectRevert(IRvm.RateLimitConfigOutOfBounds.selector);
        rvm.setRateLimitConfig(w, IRvm.CapKind.BORROW, e);

        IRvm.Bounds memory b = _globalBorrowBounds();
        b.alphaBpsLimit = 10_001;
        vm.prank(governance);
        vm.expectRevert(IRvm.InvalidBounds.selector);
        rvm.setBounds(IRvm.CapKind.BORROW, b);

        b.alphaBpsLimit = 10_000;
        vm.prank(governance);
        rvm.setBounds(IRvm.CapKind.BORROW, b);
        e.alphaBps = 10_000;
        vm.prank(governance);
        rvm.setRateLimitConfig(w, IRvm.CapKind.BORROW, e);
        assertEq(_keyState(w).alphaBps, 10_000);
    }

    function test_CAP_UNIT_11_hold_secondsTimestamp() public {
        _useF1(1200);
        uint40 until = uint40(block.timestamp + 3600);
        vm.expectEmit(address(rvm));
        emit IRvm.HoldSet(w, IRvm.CapKind.BORROW, until);
        _setHold(w, IRvm.CapKind.BORROW, until);
        assertEq(_keyState(w).holdUntil, until);
        assertEq(_state(w).holdUntil, until);
        vm.warp(block.timestamp + 3599);
        assertFalse(_cut(w, 1100), "held at until - 1");
        vm.warp(block.timestamp + 1);
        assertTrue(_cut(w, 1100), "free at until");
    }

    /// @dev Unit version on the mock Pool; a fork version on USDC and WBTC is planned too.
    function test_CAP_UNIT_12_rule_nonEighteenDecimals() public {
        address[2] memory assets = [address(usdc), address(wbtc)];
        for (uint256 i = 0; i < assets.length; ++i) {
            address a = assets[i];
            _useFixture(a, _f1(), 1085);
            _setDebt(a, 1000, 1); // D = 1,001, L = 100
            (bool allowed,, uint256 newCap) = _previewRaise(a);
            assertTrue(allowed);
            assertEq(newCap, 1101, "raise bound");
            assertTrue(_raise(a, 1101));
            assertFalse(_raise(a, 1102));
            pool.setBorrowCap(a, 1200);
            assertTrue(_cut(a, 1101));
            assertTrue(_cut(a, 1111));
            assertFalse(_cut(a, 1100));
            assertFalse(_cut(a, 1112));
        }
    }
}

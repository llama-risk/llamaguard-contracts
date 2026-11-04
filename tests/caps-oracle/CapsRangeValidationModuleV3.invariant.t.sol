// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { IRangeValidationModule } from "chaos-agents/interfaces/IRangeValidationModule.sol";
import { ICapsRangeValidationModule as IRvm } from "../../src/caps-oracle/interfaces/ICapsRangeValidationModule.sol";
import { CapsRangeValidationModuleV3 } from "../../src/caps-oracle/CapsRangeValidationModuleV3.sol";
import { MockPoolV3 } from "./mocks/MockPoolV3.sol";
import { RvmTestBase } from "./RvmTestBase.sol";

/// @title RvmHandler
/// @notice Drives the RVM and the mock Pool for the invariant tests: Pool state (debt, borrow cap, supply cap,
///         frozen, paused, time), RVM configuration by its roles (entries, bounds, holds, agents) and agent
///         writes (a cap write only after `validate` returns true, as AaveBorrowCapAgent does).
/// @dev Ghost flags record a broken property at the moment it happens, for the post-call invariants.
contract RvmHandler is Test {
    uint256 internal constant MAX_CAP = 68_719_476_735;

    CapsRangeValidationModuleV3 internal rvm;
    MockPoolV3 internal pool;
    address internal asset;
    address internal hub;
    address internal governance;
    address internal riskCouncil;
    uint256 internal raiseId;
    uint256 internal cutId;
    bool internal fuzzSupplyCap;

    bool public ghostAgentWriteAboveMaxCap; // CAP-INV-01
    bool public ghostConfigWroteCap; // CAP-INV-12
    bool public ghostRateLimitConfigOutOfBounds; // CAP-INV-13
    bool public ghostRiskCouncilRaiseRuleBroken; // Risk Council raise limit, cooldown, no listing
    uint256 public agentWrites;

    constructor(
        CapsRangeValidationModuleV3 rvm_,
        MockPoolV3 pool_,
        address asset_,
        address[3] memory roles, // hub, governance, riskCouncil
        uint256 raiseId_,
        uint256 cutId_,
        bool fuzzSupplyCap_
    ) {
        rvm = rvm_;
        pool = pool_;
        asset = asset_;
        hub = roles[0];
        governance = roles[1];
        riskCouncil = roles[2];
        raiseId = raiseId_;
        cutId = cutId_;
        fuzzSupplyCap = fuzzSupplyCap_;
    }

    // ─── Pool state
    // ───────────────────────────────────────────────────────────

    function setDebt(uint256 tokens, uint256 extraWei) external {
        tokens = bound(tokens, 0, 100_000_000);
        extraWei = bound(extraWei, 0, 1e18 - 1);
        pool.setTotalDebt(asset, tokens * 1e18 + extraWei);
    }

    function setBorrowCap(uint256 cap) external {
        pool.setBorrowCap(asset, bound(cap, 0, MAX_CAP));
    }

    function setSupplyCap(uint256 cap) external {
        if (!fuzzSupplyCap) return;
        pool.setSupplyCap(asset, bound(cap, 0, MAX_CAP));
    }

    function setFrozen(bool frozen) external {
        pool.setFrozen(asset, frozen);
    }

    function setPaused(bool paused) external {
        pool.setPaused(asset, paused);
    }

    function warp(uint256 dt) external {
        vm.warp(block.timestamp + bound(dt, 0, 2 days));
    }

    // ─── RVM configuration
    // ────────────────────────────────────────────────────

    modifier configDoesNotWriteCap() {
        (uint256 b0, uint256 s0) = pool.getReserveCaps(asset);
        _;
        (uint256 b1, uint256 s1) = pool.getReserveCaps(asset);
        if (b0 != b1 || s0 != s1) ghostConfigWroteCap = true;
    }

    function setRateLimitConfig(
        uint64 maxCap,
        uint64 maxHeadroom,
        uint16 alphaBps,
        uint16 cutBandBps,
        bool asOwner
    )
        external
        configDoesNotWriteCap
    {
        maxCap = uint64(bound(maxCap, 0, 10_000_000));
        maxHeadroom = uint64(bound(maxHeadroom, 0, 3000));
        alphaBps = uint16(bound(alphaBps, 0, 11_000));
        cutBandBps = uint16(bound(cutBandBps, 0, 11_000));
        IRvm.RateLimitConfig memory e = IRvm.RateLimitConfig(maxCap, maxHeadroom, alphaBps, cutBandBps);
        IRvm.KeyState memory before = rvm.getKeyState(asset, IRvm.CapKind.BORROW);
        vm.prank(asOwner ? governance : riskCouncil);
        try rvm.setRateLimitConfig(asset, IRvm.CapKind.BORROW, e) {
            _checkStoredRateLimitConfigInBounds();
            if (!asOwner) _checkRiskCouncilRaiseRule(before);
        } catch { }
    }

    /// @dev Risk Council write of maxCap only, keeping the stored bps fields.
    function setMaxCap(uint64 maxCap) external configDoesNotWriteCap {
        IRvm.KeyState memory before = rvm.getKeyState(asset, IRvm.CapKind.BORROW);
        uint256 hi = before.maxCap == 0 ? 10_000_000 : uint256(before.maxCap) * 2;
        maxCap = uint64(bound(maxCap, 0, hi));
        IRvm.RateLimitConfig memory e =
            IRvm.RateLimitConfig(maxCap, before.maxHeadroom, before.alphaBps, before.cutBandBps);
        vm.prank(riskCouncil);
        try rvm.setRateLimitConfig(asset, IRvm.CapKind.BORROW, e) {
            _checkRiskCouncilRaiseRule(before);
        } catch { }
    }

    function setBounds(
        uint16 alphaMax,
        uint16 bandMax,
        uint16 increaseBps,
        uint40 cooldown
    )
        external
        configDoesNotWriteCap
    {
        IRvm.Bounds memory b;
        b.alphaBpsLimit = uint16(bound(alphaMax, 0, 10_000));
        b.cutBandBpsLimit = uint16(bound(bandMax, 0, 10_000));
        b.maxIncreaseBps = uint16(bound(increaseBps, 0, 10_000));
        b.cooldown = uint40(bound(cooldown, 0, 3 days));
        vm.prank(governance);
        rvm.setBounds(IRvm.CapKind.BORROW, b);
    }

    function setHold(uint256 dt, bool clear) external configDoesNotWriteCap {
        uint40 until = clear ? 0 : uint40(block.timestamp + bound(dt, 0, 86_400));
        vm.prank(riskCouncil);
        try rvm.setHold(asset, IRvm.CapKind.BORROW, until) { } catch { }
    }

    function reRegisterAgents() external configDoesNotWriteCap {
        vm.startPrank(governance);
        rvm.setAgent(cutId, IRvm.Direction.NONE);
        rvm.setAgent(cutId, IRvm.Direction.CUT);
        vm.stopPrank();
    }

    // ─── Agent writes
    // ─────────────────────────────────────────────────────────

    function agentRaise(uint256 to) external {
        (uint256 cap,) = pool.getReserveCaps(asset);
        _agentWrite(raiseId, cap, bound(to, 0, MAX_CAP));
    }

    function agentCut(uint256 to) external {
        (uint256 cap,) = pool.getReserveCaps(asset);
        _agentWrite(cutId, cap, bound(to, 0, MAX_CAP));
    }

    function agentRaiseFromPreview() external {
        (bool allowed, uint256 cap, uint256 newCap) = rvm.previewRaise(asset, IRvm.CapKind.BORROW);
        if (allowed) _agentWrite(raiseId, cap, newCap);
    }

    function agentCutFromPreview() external {
        (bool due, uint256 cap, uint256 newCap) = rvm.previewCut(asset, IRvm.CapKind.BORROW);
        if (due) _agentWrite(cutId, cap, newCap);
    }

    /// @dev AaveBorrowCapAgent: skip 0 and unchanged caps, validate, then write.
    function _agentWrite(uint256 agentId, uint256 from, uint256 to) internal {
        if (from == 0 || to == 0 || from == to) return;
        IRangeValidationModule.RangeValidationInput memory input =
            IRangeValidationModule.RangeValidationInput({ from: from, to: to, updateType: "" });
        if (!rvm.validate(hub, agentId, asset, input)) return;
        pool.setBorrowCap(asset, to);
        ++agentWrites;
        if (to > effectiveMaxCap()) ghostAgentWriteAboveMaxCap = true;
    }

    // ─── Model helpers
    // ────────────────────────────────────────────────────────

    /// @dev min(entry.maxCap, 2^36 - 1), the max cap the RVM uses.
    function effectiveMaxCap() public view returns (uint256 c) {
        c = rvm.getKeyState(asset, IRvm.CapKind.BORROW).maxCap;
        if (MAX_CAP < c) c = MAX_CAP;
    }

    function _checkStoredRateLimitConfigInBounds() internal {
        IRvm.KeyState memory k = rvm.getKeyState(asset, IRvm.CapKind.BORROW);
        if (k.maxCap == 0) return; // retired, always allowed
        IRvm.Bounds memory b = rvm.getBounds(IRvm.CapKind.BORROW);
        if (k.alphaBps > b.alphaBpsLimit || k.cutBandBps > b.cutBandBpsLimit) ghostRateLimitConfigOutOfBounds = true;
    }

    /// @dev After a successful Risk Council write: no new key, and a maxCap or maxHeadroom raise within the
    ///      relative limit and after the shared cooldown.
    function _checkRiskCouncilRaiseRule(IRvm.KeyState memory before) internal {
        IRvm.KeyState memory k = rvm.getKeyState(asset, IRvm.CapKind.BORROW);
        if (k.maxCap == 0) return; // retire
        if (before.maxCap == 0) ghostRiskCouncilRaiseRuleBroken = true;
        if (k.maxCap <= before.maxCap && k.maxHeadroom <= before.maxHeadroom) return;
        IRvm.Bounds memory b = rvm.getBounds(IRvm.CapKind.BORROW);
        uint256 f = 10_000 + b.maxIncreaseBps;
        if (
            k.maxCap > uint256(before.maxCap) * f / 10_000 || k.maxHeadroom > uint256(before.maxHeadroom) * f / 10_000
                || block.timestamp < uint256(before.lastIncreaseAt) + b.cooldown || k.lastIncreaseAt != block.timestamp
        ) ghostRiskCouncilRaiseRuleBroken = true;
    }
}

/// @title CapsRangeValidationModuleV3InvariantTest
/// @notice CAP-INV entries that target the RVM.
contract CapsRangeValidationModuleV3InvariantTest is RvmTestBase {
    RvmHandler internal handler;
    address internal w;

    function setUp() public virtual override {
        super.setUp();
        w = address(weth);
        _useF1(1085);
        handler = _deployHandler(true);
    }

    function _deployHandler(bool fuzzSupplyCap) internal returns (RvmHandler h) {
        h = new RvmHandler(
            rvm, pool, w, [agentHub, governance, riskCouncil], RAISE_AGENT_ID, CUT_AGENT_ID, fuzzSupplyCap
        );
        targetContract(address(h));
    }

    function _hasRateLimitConfig() internal view returns (bool) {
        return _keyState(w).maxCap != 0;
    }

    function invariant_CAP_INV_01_agentWriteNeverAboveMaxCap() public view {
        assertFalse(handler.ghostAgentWriteAboveMaxCap());
    }

    function invariant_CAP_INV_02_previewImpliesValidate() public view {
        uint256 cap = _liveBorrowCap(w);
        (bool allowed, uint256 currentCap, uint256 newCap) = _previewRaise(w);
        if (allowed) {
            assertEq(currentCap, cap);
            assertTrue(_validate(RAISE_AGENT_ID, w, cap, newCap), "raise preview => validate");
        }
        (bool due, uint256 cutCap, uint256 cutTo) = _previewCut(w);
        if (due) {
            assertEq(cutCap, cap);
            assertTrue(_validate(CUT_AGENT_ID, w, cap, cutTo), "cut preview => validate");
        }
    }

    function invariant_CAP_INV_04_cutBandWellFormed() public view {
        if (!_hasRateLimitConfig()) return;
        IRvm.ReserveState memory s = _state(w);
        uint256 c = handler.effectiveMaxCap();
        assertLe(s.cutFloor, s.cutTrigger, "lo <= hi");
        assertGe(s.cutFloor, s.usage < c ? s.usage : c, "lo >= min(D, C-bar)");
    }

    function invariant_CAP_INV_05_headroomTargetInsideBounds() public view {
        if (!_hasRateLimitConfig()) return;
        IRvm.ReserveState memory s = _state(w);
        uint256 maxHeadroom = _keyState(w).maxHeadroom;
        assertGe(s.headroomTarget, maxHeadroom / 25, "L >= Lmin");
        assertLe(s.headroomTarget, maxHeadroom, "L <= Lmax");
    }

    function invariant_CAP_INV_06_noRateLimitConfigRejectsBoth() public view {
        if (handler.effectiveMaxCap() != 0) return;
        uint256 cap = _liveBorrowCap(w);
        (bool a, uint256 c1, uint256 n1) = _previewRaise(w);
        (bool d, uint256 c2, uint256 n2) = _previewCut(w);
        assertFalse(a);
        assertFalse(d);
        assertEq(n1, 0);
        assertEq(n2, 0);
        assertEq(c1, 0);
        assertEq(c2, 0);
        assertFalse(_validate(RAISE_AGENT_ID, w, cap, cap + 1));
        if (cap > 1) assertFalse(_validate(CUT_AGENT_ID, w, cap, cap - 1));
    }

    function invariant_CAP_INV_07_capZeroUntouched() public view {
        uint256 cap = _liveBorrowCap(w);
        for (uint256 id = RAISE_AGENT_ID; id <= CUT_AGENT_ID; ++id) {
            assertFalse(_validate(id, w, 0, 1100), "from 0");
            assertFalse(_validate(id, w, cap, 0), "to 0");
        }
        if (cap == 0) {
            (bool a,,) = _previewRaise(w);
            (bool d,,) = _previewCut(w);
            assertFalse(a);
            assertFalse(d);
        }
    }

    function invariant_CAP_INV_10_checkPathReadOnly() public {
        uint256 cap = _liveBorrowCap(w);
        vm.record();
        _previewRaise(w);
        _previewCut(w);
        _validate(RAISE_AGENT_ID, w, cap, cap + 1);
        _validate(CUT_AGENT_ID, w, cap, cap > 1 ? cap - 1 : 1);
        if (_hasRateLimitConfig()) _state(w);
        (, bytes32[] memory writes) = vm.accesses(address(rvm));
        assertEq(writes.length, 0, "RVM storage written");
        (, writes) = vm.accesses(address(pool));
        assertEq(writes.length, 0, "Pool storage written");
    }

    /// @dev Reverts in any view fail the invariant, so calling them is the check.
    function invariant_CAP_INV_11_checkPathNoRevert() public view {
        uint256 cap = _liveBorrowCap(w);
        _previewRaise(w);
        _previewCut(w);
        _validate(RAISE_AGENT_ID, w, cap, type(uint256).max);
        _validate(CUT_AGENT_ID, w, cap, 1);
        if (_hasRateLimitConfig()) _state(w);
    }

    function invariant_CAP_INV_12_configNeverWritesCap() public view {
        assertFalse(handler.ghostConfigWroteCap());
    }

    function invariant_CAP_INV_13_rateLimitConfigInsideBounds() public view {
        assertFalse(handler.ghostRateLimitConfigOutOfBounds());
    }

    function invariant_riskCouncilRaiseRule() public view {
        assertFalse(handler.ghostRiskCouncilRaiseRuleBroken());
    }

    /// @dev Recomputes L, the raise cap and the band from the clamped entry and compares with the RVM.
    function invariant_CAP_INV_14_validationClampsToBounds() public view {
        if (!_hasRateLimitConfig()) return;
        IRvm.KeyState memory k = _keyState(w);
        IRvm.Bounds memory b = rvm.getBounds(IRvm.CapKind.BORROW);
        uint256 maxCap = handler.effectiveMaxCap();
        uint256 alpha = k.alphaBps < b.alphaBpsLimit ? k.alphaBps : b.alphaBpsLimit;
        uint256 band = k.cutBandBps < b.cutBandBpsLimit ? k.cutBandBps : b.cutBandBpsLimit;
        IRvm.ReserveState memory s = _state(w);
        uint256 d = s.usage;
        uint256 l = (d * alpha) / 10_000;
        if (l > k.maxHeadroom) l = k.maxHeadroom;
        if (l < k.maxHeadroom / 25) l = k.maxHeadroom / 25;
        assertEq(s.headroomTarget, l, "L from maxHeadroom and clamped alpha");
        assertEq(s.maxCap, maxCap, "maxCap the rule uses");
        assertEq(s.raiseCap, _min3(d + l, maxCap, s.supplyBound), "raise target");
        uint256 lo = _min3(_max(_min3(d + l, s.supplyBound, type(uint256).max), d), maxCap, type(uint256).max);
        uint256 hi = _max(_min3(d + l + (l * band) / 10_000, maxCap, s.supplyBound), lo);
        assertEq(s.cutFloor, lo, "lo");
        assertEq(s.cutTrigger, hi, "hi from clamped band");
    }

    function _min3(uint256 a, uint256 b, uint256 c) internal pure returns (uint256 m) {
        m = a < b ? a : b;
        if (c < m) m = c;
    }

    function _max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }
}

/// @title CapsRangeValidationModuleV3KindIsolationTest
/// @notice CAP-INV-08: BORROW writes never change the SUPPLY entry, hold or results of the same asset.
contract CapsRangeValidationModuleV3KindIsolationTest is RvmTestBase {
    RvmHandler internal handler;
    address internal w;

    IRvm.KeyState internal supplyKey;
    bool internal supplyDue;
    uint256 internal supplyCutTo;
    IRvm.Bounds internal supplyBounds;

    function setUp() public override {
        super.setUp();
        w = address(weth);
        _registerSupplyAgents();
        _useF1(1085); // BORROW: D 1,000, cap 1,085, S = supply cap 5,000
        // SUPPLY: supplied 1,000, live supply cap 5,000 (above hi), entry with max cap 20,000.
        _setSupplied(w, 1000);
        IRvm.RateLimitConfig memory e = _rateLimitConfigOf(_f1());
        e.maxCap = 20_000;
        _setRateLimitConfig(w, IRvm.CapKind.SUPPLY, e);

        supplyKey = rvm.getKeyState(w, IRvm.CapKind.SUPPLY);
        supplyBounds = rvm.getBounds(IRvm.CapKind.SUPPLY);
        (supplyDue,, supplyCutTo) = rvm.previewCut(w, IRvm.CapKind.SUPPLY);
        assertTrue(supplyDue, "SUPPLY cut due at start");

        handler = new RvmHandler(rvm, pool, w, [agentHub, governance, riskCouncil], RAISE_AGENT_ID, CUT_AGENT_ID, false);
        // Agent writes change the borrow cap only; the supply cap stays, so SUPPLY results must not move.
        targetContract(address(handler));
    }

    /// @dev Worked example of 05: a BORROW entry write and a BORROW hold leave the SUPPLY side as it was.
    function test_CAP_INV_08_kindIsolation_example() public {
        IRvm.RateLimitConfig memory e = _rateLimitConfigOf(_f1());
        e.maxCap = 800;
        _setRateLimitConfig(w, IRvm.CapKind.BORROW, e);
        _setHold(w, IRvm.CapKind.BORROW, uint40(block.timestamp + 3600));
        assertEq(rvm.getKeyState(w, IRvm.CapKind.SUPPLY).maxCap, 20_000);
        assertEq(rvm.getKeyState(w, IRvm.CapKind.SUPPLY).holdUntil, 0);
        (bool due,, uint256 to) = rvm.previewCut(w, IRvm.CapKind.SUPPLY);
        assertTrue(due, "SUPPLY cut still due");
        assertEq(to, 1100);
        // And the reverse: a SUPPLY hold does not block the BORROW cut.
        _setHold(w, IRvm.CapKind.BORROW, 0);
        _setHold(w, IRvm.CapKind.SUPPLY, uint40(block.timestamp + 3600));
        pool.setBorrowCap(w, 1200);
        (due,, to) = _previewCut(w);
        assertTrue(due, "BORROW cut due under a SUPPLY hold");
        assertEq(to, 800);
    }

    function invariant_CAP_INV_08_kindIsolation() public view {
        IRvm.KeyState memory k = rvm.getKeyState(w, IRvm.CapKind.SUPPLY);
        assertEq(k.maxCap, supplyKey.maxCap);
        assertEq(k.maxHeadroom, supplyKey.maxHeadroom);
        assertEq(k.alphaBps, supplyKey.alphaBps);
        assertEq(k.cutBandBps, supplyKey.cutBandBps);
        assertEq(k.holdUntil, supplyKey.holdUntil);
        assertEq(k.lastIncreaseAt, supplyKey.lastIncreaseAt);
        IRvm.Bounds memory b = rvm.getBounds(IRvm.CapKind.SUPPLY);
        assertEq(b.alphaBpsLimit, supplyBounds.alphaBpsLimit);
        assertEq(b.cutBandBpsLimit, supplyBounds.cutBandBpsLimit);
        assertEq(b.maxIncreaseBps, supplyBounds.maxIncreaseBps);
        assertEq(b.cooldown, supplyBounds.cooldown);
        (bool due,, uint256 to) = rvm.previewCut(w, IRvm.CapKind.SUPPLY);
        assertEq(due, supplyDue);
        assertEq(to, supplyCutTo);
    }
}

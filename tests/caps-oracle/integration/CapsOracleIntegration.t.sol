// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AgentHub } from "chaos-agents/contracts/AgentHub.sol";
import { IAgentHub } from "chaos-agents/interfaces/IAgentHub.sol";
import { ICapsRangeValidationModule as IRvm } from "../../../src/caps-oracle/interfaces/ICapsRangeValidationModule.sol";
import { IAgentConfigurator } from "chaos-agents/interfaces/IAgentConfigurator.sol";
import { AaveBorrowCapAgent } from "aave-risk-agents/src/contracts/agent/AaveBorrowCapAgent.sol";
import { CapsReducerOracle } from "../../../src/caps-oracle/CapsReducerOracle.sol";
import { CapsRangeValidationModuleV3 } from "../../../src/caps-oracle/CapsRangeValidationModuleV3.sol";
import { CapsSystemBase } from "../CapsSystemBase.sol";
import { MockCapsEngine } from "../mocks/MockCapsEngine.sol";
import { MockPoolV3 } from "../mocks/MockPoolV3.sol";

/// @title CutGriefer
/// @notice The CAP-ST-28 attacker: a borrower with debt x that, in one transaction, repays x (with flash-loaned
///         tokens), runs the permissionless cut through AgentHub, borrows x back and repays the flash loan.
contract CutGriefer {
    MockPoolV3 internal immutable POOL;
    AgentHub internal immutable HUB;

    constructor(MockPoolV3 pool, AgentHub hub) {
        POOL = pool;
        HUB = hub;
    }

    function openDebt(address asset, uint256 amount) external {
        POOL.borrow(asset, amount, 2, 0, address(this));
    }

    /// @param lender receives `x` back at the end (the flash loan). The caller sent `x` before the call.
    function run(address asset, uint256 x, uint256 cutAgentId, address lender) external {
        IERC20(asset).approve(address(POOL), x);
        POOL.repay(asset, x, 2, address(this));

        IAgentHub.ActionData[] memory a = new IAgentHub.ActionData[](1);
        a[0].agentId = cutAgentId;
        a[0].markets = new address[](1);
        a[0].markets[0] = asset;
        HUB.execute(a);

        POOL.borrow(asset, x, 2, 0, address(this));
        IERC20(asset).transfer(lender, x);
    }
}

/// @title CapsOracleIntegrationTest
/// @notice Local integration of Stage 1: the real AgentHub, the real AaveBorrowCapAgent (raise and cut
///         agentIds), CapsRangeValidationModuleV3, CapsReducerOracle and the mock Pool. Runs a raise, a
///         cut, a hold that blocks a cut, and the cut grief (CAP-ST-28) as a documented known issue.
/// @dev State is F1: D = 1,000 WETH (950 from other borrowers, 50 from the griefer), S = 5,000,
///      entry max cap 10,000, alpha 10%, band 10%. Live borrow cap 1,085.
contract CapsOracleIntegrationTest is CapsSystemBase {
    CutGriefer internal griefer;
    address internal w;
    address internal flashLender = makeAddr("flashLender");

    function setUp() public override {
        super.setUp();
        w = address(weth);
        griefer = new CutGriefer(pool, hub);

        pool.setTotalDebt(w, 950e18);
        pool.setSupplyCap(w, F1_SUPPLY);
        pool.setBorrowCap(w, 1085);
        griefer.openDebt(w, 50e18);
        _setRvmRateLimitConfig(w, IRvm.CapKind.BORROW, _rateLimitConfigOf(_f1()));

        assertEq(_debtToken(w).totalSupply(), 1000e18, "D = 1,000");
    }

    function _execute(uint256 agentId) internal {
        hub.execute(_actions(agentId, w));
    }

    /// @dev CAP-ST-02 through AgentHub: the workflow's raise to 1,101 is refused by the RVM, so AgentHub
    ///      performs no action; the raise to the preview value 1,100 lands.
    function test_CAP_ST_02_integration_raiseThroughAgentHub() public {
        (bool allowed, uint256 cap, uint256 to) = rvm.previewRaise(w, IRvm.CapKind.BORROW);
        assertTrue(allowed);
        assertEq(cap, 1085);
        assertEq(to, F1_RAISE_BOUND);

        raiseOracle.publish(BORROW_UPDATE_TYPE, w, 1101, 1085);
        vm.expectRevert(IAgentHub.NoActionCanBePerformed.selector);
        _execute(borrowRaiseId);
        assertEq(_liveCap(w, IRvm.CapKind.BORROW), 1085, "refused raise leaves the cap");

        assertTrue(_raiseViaHub(w, IRvm.CapKind.BORROW, 1100), "raise to the preview lands");
        assertEq(_liveCap(w, IRvm.CapKind.BORROW), 1100);

        // CAP-ST-14: the next raise waits tau (AgentHub minimumDelay), even when it is valid.
        pool.setTotalDebt(w, 1100e18);
        assertFalse(_raiseViaHub(w, IRvm.CapKind.BORROW, 1210), "inside tau");
        vm.warp(block.timestamp + TAU);
        assertTrue(_raiseViaHub(w, IRvm.CapKind.BORROW, 1210), "after tau");
        assertEq(_liveCap(w, IRvm.CapKind.BORROW), 1210);
    }

    /// @dev CAP-ST-14, F1 on the real AgentHub with the raise agent minimumDelay tau = 1,800 s (
    ///      assumed setting): raise at t, the next valid raise at t + 1,799 s is skipped, at t + 1,800 s it lands.
    ///      The fork version against the deployed AgentHub is planned.
    function test_CAP_ST_14_raise_withinTau_skipped() public {
        uint256 t = block.timestamp;
        assertTrue(_raiseViaHub(w, IRvm.CapKind.BORROW, 1100), "raise at t");

        pool.setTotalDebt(w, 1100e18); // D = 1,100, so 1,210 is a valid raise
        (bool allowed,, uint256 to) = rvm.previewRaise(w, IRvm.CapKind.BORROW);
        assertTrue(allowed, "the RVM accepts the next raise");
        assertEq(to, 1210);

        vm.warp(t + TAU - 1);
        assertFalse(_raiseViaHub(w, IRvm.CapKind.BORROW, 1210), "t + 1,799 s skipped");
        assertEq(_liveCap(w, IRvm.CapKind.BORROW), 1100);

        vm.warp(t + TAU);
        assertTrue(_raiseViaHub(w, IRvm.CapKind.BORROW, 1210), "t + 1,800 s injected");
        assertEq(_liveCap(w, IRvm.CapKind.BORROW), 1210);
    }

    /// @dev CAP-ST-15, fuzzed borrows on the real AgentHub: from a quiet period (no raise in the last tau),
    ///      borrowers take any part of the headroom at random times and a keeper raises to the preview value
    ///      whenever AgentHub allows. At every step D_T - D_0 <= L * (2 + floor(T / tau)), with T the time since
    ///      the first borrow. D only grows here, so L at the current D is the largest L of the period.
    ///      The fork version is planned.
    function test_CAP_ST_15_growthBound_quietPeriod(uint256 seed) public {
        uint256 t0 = block.timestamp;
        uint256 d0 = F1_DEBT;
        uint256 d = d0;
        for (uint256 i = 0; i < 16; ++i) {
            uint256 r = uint256(keccak256(abi.encode(seed, i)));
            vm.warp(block.timestamp + (r % 1201));
            vm.roll(block.number + 1);

            uint256 cap = _liveCap(w, IRvm.CapKind.BORROW);
            if (cap > d) d += (r >> 16) % (cap - d + 1); // borrow any part of the headroom
            pool.setTotalDebt(w, d * 1e18);

            (bool allowed,, uint256 to) = rvm.previewRaise(w, IRvm.CapKind.BORROW);
            if (allowed && (r >> 128) % 4 != 0) _raiseViaHub(w, IRvm.CapKind.BORROW, to);

            uint256 l = rvm.getReserveState(w, IRvm.CapKind.BORROW).headroomTarget;
            uint256 elapsed = block.timestamp - t0;
            assertLe(d - d0, l * (2 + elapsed / TAU), "growth bound");
            assertLe(d, _liveCap(w, IRvm.CapKind.BORROW), "debt within the cap");
        }
    }

    /// @dev CAP-ST-07 through AgentHub: a cap above the band is cut to lo, with the value read from
    ///      CapsReducerOracle. CAP-ST-16: a second cut in the same block is refused by AgentHub.
    function test_CAP_ST_07_integration_cutThroughReducer() public {
        pool.setBorrowCap(w, 1200); // manual raise, above hi = 1,110

        uint256[] memory ids = new uint256[](1);
        ids[0] = borrowCutId;
        (bool any, IAgentHub.ActionData[] memory ad) = hub.check(ids);
        assertTrue(any, "check reports the cut");
        assertEq(ad[0].markets[0], w);

        hub.execute(ad);
        assertEq(_liveCap(w, IRvm.CapKind.BORROW), F1_CUT_FLOOR, "cut to lo");

        pool.setBorrowCap(w, 1200);
        vm.expectRevert(IAgentHub.NoActionCanBePerformed.selector);
        _execute(borrowCutId);
        assertEq(_liveCap(w, IRvm.CapKind.BORROW), 1200, "one cut per block");

        vm.roll(block.number + 1);
        _execute(borrowCutId);
        assertEq(_liveCap(w, IRvm.CapKind.BORROW), F1_CUT_FLOOR, "next block cuts again");
    }

    /// @dev CAP-ST-17 through AgentHub: while the hold is active, check reports nothing and execute performs no
    ///      action. CAP-ST-18: the hold does not touch raises. CAP-ST-20: at the hold end the cut lands.
    function test_CAP_ST_17_integration_holdBlocksCut() public {
        pool.setBorrowCap(w, 1200);
        uint40 until = uint40(block.timestamp + 3600);
        vm.prank(riskCouncil);
        rvm.setHold(w, IRvm.CapKind.BORROW, until);

        uint256[] memory ids = new uint256[](1);
        ids[0] = borrowCutId;
        (bool any,) = hub.check(ids);
        assertFalse(any, "no cut while held");
        vm.expectRevert(IAgentHub.NoActionCanBePerformed.selector);
        _execute(borrowCutId);
        assertEq(_liveCap(w, IRvm.CapKind.BORROW), 1200);

        vm.warp(until - 1);
        vm.roll(block.number + 1);
        assertFalse(_cutViaHub(w, IRvm.CapKind.BORROW), "one second before the end");

        vm.warp(until);
        assertTrue(_cutViaHub(w, IRvm.CapKind.BORROW), "hold expired");
        assertEq(_liveCap(w, IRvm.CapKind.BORROW), F1_CUT_FLOOR);

        // CAP-ST-18: a raise under an active hold lands as without the hold.
        vm.prank(riskCouncil);
        rvm.setHold(w, IRvm.CapKind.BORROW, uint40(block.timestamp + 3600));
        pool.setBorrowCap(w, 1085);
        assertTrue(_raiseViaHub(w, IRvm.CapKind.BORROW, 1100), "raise under hold");
    }

    /// @notice KNOWN ISSUE: cut grief. The contracts have no guard against it.
    /// @dev F1, cap 1,100, x = 50. In one transaction the griefer repays 50 (D = 950, L = 95), runs the
    ///      permissionless cut (cap 1,100 is above hi = 1,054, so it lands at lo = 1,045), then borrows the 50
    ///      back (D = 1,000). Debt is unchanged and headroom drops from 100 to L(D - x) - x = 45. No bound is
    ///      exceeded: the cut stays inside [lo, hi] of the block, under the max cap and at or above the debt.
    ///      The workflow restores the buffer with the next raise once tau has passed. If a later decision adds
    ///      a guard, this test flips from "reachable" to "refused".
    function test_CAP_ST_28_cutGrief_flashRepayCutBorrow_bounded() public {
        assertTrue(_raiseViaHub(w, IRvm.CapKind.BORROW, 1100));
        (bool due,,) = rvm.previewCut(w, IRvm.CapKind.BORROW);
        assertFalse(due, "no cut due at cap 1,100 (hi 1,110)");

        uint256 x = 50e18;
        weth.mint(address(griefer), x); // flash loan
        griefer.run(w, x, borrowCutId, flashLender);

        uint256 cap = _liveCap(w, IRvm.CapKind.BORROW);
        uint256 debt = _debtToken(w).totalSupply();
        assertEq(debt, 1000e18, "debt unchanged");
        assertEq(cap, 1045, "cap = D - x + L(D - x)");
        assertEq(cap - debt / 1e18, 45, "headroom L(D - x) - x");
        assertLe(cap, F1_MAX_CAP, "under the maxCap");
        assertGe(cap * 1e18, debt, "cap at or above debt");
        assertEq(weth.balanceOf(flashLender), x, "flash loan repaid");

        // After the grief: no further cut is due, and the raise path restores D + L after tau.
        (due,,) = rvm.previewCut(w, IRvm.CapKind.BORROW);
        assertFalse(due);
        assertFalse(_raiseViaHub(w, IRvm.CapKind.BORROW, 1100), "inside tau of the last raise");
        vm.warp(block.timestamp + TAU);
        assertTrue(_raiseViaHub(w, IRvm.CapKind.BORROW, 1100), "headroomTarget restored");
    }

    /// @dev CAP-ACL-22: Core and Prime share one cut update type (`BorrowCapUpdate_Core`). Each Pool has its
    ///      own RVM and CapsReducerOracle, registered as the riskOracle of its own cut agentId, and both cuts
    ///      land through AgentHub in one `execute`.
    ///      Core: F1, cap 1,200, cut to lo 1,100. Prime: D = 2,000 (L = 200, band top 2,220), cap 3,000, cut to
    ///      lo 2,200.
    function test_CAP_ACL_22_twoPools_sharedUpdateType_ownRvmAndReducerEach() public {
        MockPoolV3 prime = new MockPoolV3();
        prime.listReserve(w, 18, 0, 0);
        prime.setTotalDebt(w, 2000e18);
        prime.setSupplyCap(w, F1_SUPPLY);
        prime.setBorrowCap(w, 3000);
        MockCapsEngine primeEngine = new MockCapsEngine(prime);

        CapsRangeValidationModuleV3 primeRvm = new CapsRangeValidationModuleV3(
            governance, agentHub, address(prime), riskCouncil, BORROW_UPDATE_TYPE, SUPPLY_UPDATE_TYPE
        );
        CapsReducerOracle primeReducer = new CapsReducerOracle(primeRvm, IRvm.CapKind.BORROW);
        AaveBorrowCapAgent primeCutAgent =
            new AaveBorrowCapAgent(agentHub, address(primeRvm), UPDATE_TYPE_SUFFIX, address(prime));
        assertEq(primeCutAgent.getUpdateType(), borrowCutAgent.getUpdateType(), "shared update type");

        IAgentConfigurator.AgentRegistrationInput memory input;
        input.admin = agentAdmin;
        input.riskOracle = address(primeReducer);
        input.isAgentEnabled = true;
        input.agentAddress = address(primeCutAgent);
        input.expirationPeriod = EXPIRATION_PERIOD;
        input.updateType = BORROW_UPDATE_TYPE;
        input.agentContext = abi.encode(address(primeEngine));
        input.allowedMarkets = new address[](1);
        input.allowedMarkets[0] = w;
        vm.startPrank(governance);
        uint256 primeCutId = hub.registerAgent(input);
        primeRvm.setAgent(primeCutId, IRvm.Direction.CUT);
        primeRvm.setBounds(IRvm.CapKind.BORROW, _globalBorrowBounds());
        primeRvm.setRateLimitConfig(w, IRvm.CapKind.BORROW, _rateLimitConfigOf(_f1()));
        // The Core RVM refuses the Prime agent: it is built on the Prime RVM and Pool.
        vm.expectRevert(abi.encodeWithSelector(IRvm.InvalidAgent.selector, primeCutId));
        rvm.setAgent(primeCutId, IRvm.Direction.CUT);
        vm.stopPrank();

        pool.setBorrowCap(w, 1200);

        // Same call, same update type, same asset: each reducer answers for its own Pool.
        assertEq(address(reducer.RVM()), address(rvm));
        assertEq(address(primeReducer.RVM()), address(primeRvm));
        assertEq(
            abi.decode(reducer.getLatestUpdateByParameterAndMarket(BORROW_UPDATE_TYPE, w).newValue, (uint256)),
            F1_CUT_FLOOR
        );
        assertEq(
            abi.decode(primeReducer.getLatestUpdateByParameterAndMarket(BORROW_UPDATE_TYPE, w).newValue, (uint256)),
            2200
        );

        uint256[] memory ids = new uint256[](2);
        ids[0] = borrowCutId;
        ids[1] = primeCutId;
        (bool any, IAgentHub.ActionData[] memory ad) = hub.check(ids);
        assertTrue(any, "check reports both cuts");
        hub.execute(ad);

        assertEq(_liveCap(w, IRvm.CapKind.BORROW), F1_CUT_FLOOR, "Core cut to its lo");
        (uint256 primeCap,) = prime.getReserveCaps(w);
        assertEq(primeCap, 2200, "Prime cut to its lo");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Vm as VmFull, VmSafe as Vm } from "forge-std/Vm.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import {
    IAaveV3ConfigEngine as IEngine
} from "aave-v3-origin/src/contracts/extensions/v3-config-engine/IAaveV3ConfigEngine.sol";
import { EngineFlags } from "aave-v3-origin/src/contracts/extensions/v3-config-engine/EngineFlags.sol";
import { CapsTestBase } from "./CapsTestBase.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockPoolV3, MockVariableDebtToken } from "./mocks/MockPoolV3.sol";
import { MockCapsEngine } from "./mocks/MockCapsEngine.sol";
import { MockCapsRvm } from "./mocks/MockCapsRvm.sol";
import { CapsBorrowForwarder } from "../../src/caps-oracle/CapsBorrowForwarder.sol";
import { ICapsBorrowForwarder } from "../../src/caps-oracle/interfaces/ICapsBorrowForwarder.sol";
import { ICapsRangeValidationModule as IRvm } from "../../src/caps-oracle/interfaces/ICapsRangeValidationModule.sol";

/// @title QuirkyERC20
/// @notice ERC20 whose `transfer` misbehaves when sent by one chosen account, to drive the forwarder's
///         transfer and balance checks: it returns `false` to a blocked recipient, moves only half of the
///         amount, or returns no data (USDT style).
contract QuirkyERC20 is MockERC20 {
    address public blockedTo;
    address public halfFrom;
    address public noReturnFrom;
    address public revertFrom;
    address public selfEtchFrom;

    constructor(uint8 decimals_) MockERC20("Quirky", "QRK", decimals_) { }

    function setRevertFrom(address a) external {
        revertFrom = a;
    }

    function setSelfEtchFrom(address a) external {
        selfEtchFrom = a;
    }

    function setBlockedTo(address a) external {
        blockedTo = a;
    }

    function setHalfFrom(address a) external {
        halfFrom = a;
    }

    function setNoReturnFrom(address a) external {
        noReturnFrom = a;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (to == blockedTo) return false;
        if (msg.sender == revertFrom) revert("QuirkyERC20: transfer reverted");
        if (msg.sender == selfEtchFrom) {
            // Remove this token's code during the call: no return data and no code, as for an asset with no code.
            VmFull(address(uint160(uint256(keccak256("hevm cheat code"))))).etch(address(this), "");
            assembly {
                return(0, 0)
            }
        }
        if (msg.sender == halfFrom) {
            _transfer(msg.sender, to, amount / 2);
            return true;
        }
        if (msg.sender == noReturnFrom) {
            _transfer(msg.sender, to, amount);
            assembly {
                return(0, 0)
            }
        }
        return super.transfer(to, amount);
    }
}

/// @title CapsBorrowForwarderTest
/// @notice Unit tests of the standalone CapsBorrowForwarder against MockPoolV3, MockCapsEngine (delegatecall
///         target) and MockCapsRvm. The allowlisted caller is the Risk Council address, by plain call. Covers
///         CAP-ST-26, CAP-ST-27, CAP-ST-29, CAP-ST-30, CAP-ST-31, CAP-ACL-12, CAP-ACL-16 and CAP-UNIT-13, plus
///         the caller allowlist, the per-raise and per-period limits, and the delegation renounce.
contract CapsBorrowForwarderTest is CapsTestBase {
    CapsBorrowForwarder internal fwd;
    MockCapsRvm internal capsRvm;
    MockCapsEngine internal engine;

    uint256 internal constant LIVE_CAP = 1_000_000; // whole USDC
    uint256 internal constant LIVE_DEBT = 900_000; // whole USDC
    uint256 internal constant LIQUIDITY = 100_000_000; // whole tokens per asset in the pool
    /// Default per-raise limit: +100% of the live cap, as the Aave Risk Steward cap rule.
    uint256 internal constant MAX_RAISE_BPS = 10_000;
    /// Default per-period limit: the 1 second minimum. The limit tests set their own.
    uint256 internal constant MIN_RAISE_DELAY = 1;
    /// RVM borrow maxCap of every asset unless a test sets another.
    uint64 internal constant RVM_MAX_CAP = 100_000_000_000;

    function setUp() public override {
        super.setUp();
        vm.warp(1_700_000_000);
        capsRvm = new MockCapsRvm();
        capsRvm.setPool(address(pool));
        engine = new MockCapsEngine(pool);
        fwd = _deploy(MAX_RAISE_BPS, MIN_RAISE_DELAY);

        usdc.mint(address(pool), _wei(address(usdc), LIQUIDITY));
        weth.mint(address(pool), _wei(address(weth), LIQUIDITY));
        wbtc.mint(address(pool), _wei(address(wbtc), LIQUIDITY));

        _setRvmMaxCap(address(usdc), RVM_MAX_CAP);
        _setRvmMaxCap(address(weth), RVM_MAX_CAP);
        _setRvmMaxCap(address(wbtc), RVM_MAX_CAP);

        pool.setBorrowCap(address(usdc), LIVE_CAP);
        _setDebt(address(usdc), LIVE_DEBT, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    function _deploy(uint256 bps, uint256 delay) internal returns (CapsBorrowForwarder) {
        return new CapsBorrowForwarder(
            governance, address(pool), address(engine), address(capsRvm), riskCouncil, bps, delay
        );
    }

    function _debtToken(address asset) internal view returns (MockVariableDebtToken) {
        return MockVariableDebtToken(pool.getReserveVariableDebtToken(asset));
    }

    function _delegate(address asset, uint256 amount) internal {
        MockVariableDebtToken vdt = _debtToken(asset);
        vm.prank(borrower);
        vdt.approveDelegation(address(fwd), amount);
    }

    function _run(address asset, uint256 amount) internal {
        vm.prank(riskCouncil);
        fwd.raiseCapAndBorrow(asset, amount, borrower);
    }

    function _setRvmMaxCap(address asset, uint64 maxCap) internal {
        IRvm.RateLimitConfig memory c =
            IRvm.RateLimitConfig({ maxCap: maxCap, maxHeadroom: 1, alphaBps: 0, cutBandBps: 0 });
        capsRvm.setRateLimitConfig(asset, IRvm.CapKind.BORROW, c);
    }

    function _setLimits(uint256 bps, uint256 delay) internal {
        vm.prank(governance);
        fwd.setLimits(bps, delay);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR, IMMUTABLES AND OWNERSHIP
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CapsBorrowForwarder_immutables() public view {
        assertEq(fwd.POOL(), address(pool));
        assertEq(fwd.CONFIG_ENGINE(), address(engine));
        assertEq(fwd.RVM(), address(capsRvm));
        assertEq(fwd.owner(), governance, "owner is the AgentHub owner");
        assertTrue(fwd.isCaller(riskCouncil), "Risk Council allowlisted");
        assertFalse(fwd.isCaller(borrower));
        assertEq(fwd.maxRaiseBps(), MAX_RAISE_BPS);
        assertEq(fwd.minRaiseDelay(), MIN_RAISE_DELAY);
        assertEq(fwd.lastRaiseAt(address(usdc)), 0);
    }

    /// The constructor emits CallerSet for the initial caller and one LimitsSet.
    function test_CapsBorrowForwarder_constructor_emitsEvents() public {
        vm.expectEmit(true, false, false, true);
        emit ICapsBorrowForwarder.CallerSet(riskCouncil, true);
        vm.expectEmit(false, false, false, true);
        emit ICapsBorrowForwarder.LimitsSet(2500, 1 days);
        CapsBorrowForwarder f = new CapsBorrowForwarder(
            governance, address(pool), address(engine), address(capsRvm), riskCouncil, 2500, 1 days
        );
        assertTrue(f.isCaller(riskCouncil));
        assertFalse(f.isCaller(updater));
        assertEq(f.maxRaiseBps(), 2500);
        assertEq(f.minRaiseDelay(), 1 days);
    }

    function test_CapsBorrowForwarder_constructor_zeroAddress_reverts() public {
        address c = riskCouncil;
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new CapsBorrowForwarder(address(0), address(pool), address(engine), address(capsRvm), c, 1, 1);
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        new CapsBorrowForwarder(governance, address(0), address(engine), address(capsRvm), c, 1, 1);
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        new CapsBorrowForwarder(governance, address(pool), address(0), address(capsRvm), c, 1, 1);
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        new CapsBorrowForwarder(governance, address(pool), address(engine), address(0), c, 1, 1);

        // A zero initial caller.
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        new CapsBorrowForwarder(governance, address(pool), address(engine), address(capsRvm), address(0), 1, 1);
    }

    /// maxRaiseBps 0 would block every raise: refused at deploy.
    function test_CapsBorrowForwarder_constructor_zeroMaxRaiseBps_reverts() public {
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        new CapsBorrowForwarder(governance, address(pool), address(engine), address(capsRvm), riskCouncil, 0, 1 days);
    }

    /// minRaiseDelay 0 would switch the delay off: refused at deploy, as the RVM refuses a cooldown of 0.
    function test_CapsBorrowForwarder_constructor_zeroMinRaiseDelay_reverts() public {
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        new CapsBorrowForwarder(governance, address(pool), address(engine), address(capsRvm), riskCouncil, 1, 0);
    }

    /// An RVM of another Pool is refused: its maxCap would not bound this Pool's caps.
    function test_CapsBorrowForwarder_constructor_rvmPoolMismatch_reverts() public {
        MockCapsRvm otherRvm = new MockCapsRvm();
        otherRvm.setPool(address(new MockPoolV3()));
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        new CapsBorrowForwarder(governance, address(pool), address(engine), address(otherRvm), riskCouncil, 1, 1);
    }

    /// A config engine of another Pool is refused: it would write caps on a Pool the bounds are not read from.
    function test_CapsBorrowForwarder_constructor_enginePoolMismatch_reverts() public {
        MockCapsEngine otherEngine = new MockCapsEngine(new MockPoolV3());
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        new CapsBorrowForwarder(governance, address(pool), address(otherEngine), address(capsRvm), riskCouncil, 1, 1);
    }

    /// Cap 1 is a manual freeze of borrowing: the forwarder does not lift it, whatever the limits allow.
    function test_CapsBorrowForwarder_raiseCapAndBorrow_frozenCap_reverts() public {
        pool.setBorrowCap(address(usdc), 1);
        _delegate(address(usdc), 5000e6);

        vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.BorrowCapFrozen.selector, address(usdc)));
        _run(address(usdc), 5000e6);
        assertEq(_liveBorrowCap(address(usdc)), 1);
        assertEq(_debtToken(address(usdc)).balanceOf(borrower), 0);
    }

    /// An engine with the right Pool but another PoolConfigurator is refused.
    function test_CapsBorrowForwarder_constructor_engineConfiguratorMismatch_reverts() public {
        vm.mockCall(address(engine), abi.encodeWithSignature("POOL_CONFIGURATOR()"), abi.encode(address(0xBEEF)));
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        new CapsBorrowForwarder(governance, address(pool), address(engine), address(capsRvm), riskCouncil, 1, 1);
    }

    function test_CapsBorrowForwarder_renounceOwnership_reverts() public {
        vm.prank(governance);
        vm.expectRevert(ICapsBorrowForwarder.NotSupported.selector);
        fwd.renounceOwnership();
        assertEq(fwd.owner(), governance);

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        fwd.renounceOwnership();
    }

    /// Two-step ownership transfer: the new owner holds the admin functions only after accepting.
    function test_CapsBorrowForwarder_transferOwnership_twoStep() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(governance);
        fwd.transferOwnership(newOwner);
        assertEq(fwd.owner(), governance);
        assertEq(fwd.pendingOwner(), newOwner);

        vm.prank(newOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, newOwner));
        fwd.setCaller(attacker, true);

        vm.prank(newOwner);
        fwd.acceptOwnership();
        assertEq(fwd.owner(), newOwner);
        vm.prank(newOwner);
        fwd.setCaller(updater, true);
        assertTrue(fwd.isCaller(updater));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CALLER ALLOWLIST (CAP-ACL-12)
    // ═══════════════════════════════════════════════════════════════════════════

    /// CAP-ACL-12: a borrower, an attacker, the owner or the forwarder itself calls raiseCapAndBorrow: NotCaller.
    /// No cap change and no borrow, the delegation stays unused.
    function test_CAP_ACL_12_raiseCapAndBorrow_notCaller_reverts() public {
        _delegate(address(usdc), 5000e6);
        address[4] memory who = [borrower, attacker, governance, address(fwd)];
        for (uint256 i = 0; i < who.length; i++) {
            vm.prank(who[i]);
            vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.NotCaller.selector, who[i]));
            fwd.raiseCapAndBorrow(address(usdc), 5000e6, borrower);
        }
        assertEq(_liveBorrowCap(address(usdc)), LIVE_CAP);
        assertEq(_debtToken(address(usdc)).balanceOf(borrower), 0);
        assertEq(_debtToken(address(usdc)).borrowAllowance(borrower, address(fwd)), 5000e6, "delegation unused");
    }

    /// CAP-ACL-12 fuzzed over the caller.
    function testFuzz_CAP_ACL_12_raiseCapAndBorrow_notCaller_reverts(address caller) public {
        vm.assume(caller != riskCouncil);
        _delegate(address(usdc), 5000e6);
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.NotCaller.selector, caller));
        fwd.raiseCapAndBorrow(address(usdc), 5000e6, borrower);
    }

    /// setCaller is owner only; it adds and removes callers and emits CallerSet.
    function test_setCaller_ownerOnly_addsAndRemoves() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        fwd.setCaller(attacker, true);
        // An allowlisted caller is not an admin either.
        vm.prank(riskCouncil);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, riskCouncil));
        fwd.setCaller(updater, true);

        vm.expectEmit(true, false, false, true, address(fwd));
        emit ICapsBorrowForwarder.CallerSet(updater, true);
        vm.prank(governance);
        fwd.setCaller(updater, true);
        assertTrue(fwd.isCaller(updater));

        // The new caller can raise.
        _delegate(address(usdc), 5000e6);
        vm.prank(updater);
        fwd.raiseCapAndBorrow(address(usdc), 5000e6, borrower);
        assertEq(usdc.balanceOf(borrower), 5000e6);

        // Removed: the Risk Council can no longer raise.
        vm.expectEmit(true, false, false, true, address(fwd));
        emit ICapsBorrowForwarder.CallerSet(riskCouncil, false);
        vm.prank(governance);
        fwd.setCaller(riskCouncil, false);
        assertFalse(fwd.isCaller(riskCouncil));
        _delegate(address(usdc), 5000e6);
        vm.prank(riskCouncil);
        vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.NotCaller.selector, riskCouncil));
        fwd.raiseCapAndBorrow(address(usdc), 5000e6, borrower);
    }

    function test_setCaller_zeroAddress_reverts() public {
        vm.prank(governance);
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        fwd.setCaller(address(0), true);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INPUT CHECKS
    // ═══════════════════════════════════════════════════════════════════════════

    /// Zero amount, and a borrower that is the zero address, the forwarder or the caller itself: InvalidInput.
    function test_CapsBorrowForwarder_invalidInput_reverts() public {
        _delegate(address(usdc), type(uint256).max);
        vm.startPrank(riskCouncil);
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        fwd.raiseCapAndBorrow(address(usdc), 0, borrower);
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        fwd.raiseCapAndBorrow(address(usdc), 5000e6, address(0));
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        fwd.raiseCapAndBorrow(address(usdc), 5000e6, address(fwd));
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        fwd.raiseCapAndBorrow(address(usdc), 5000e6, riskCouncil);
        vm.stopPrank();
        assertEq(_liveBorrowCap(address(usdc)), LIVE_CAP);
    }

    /// A caller that is the borrower of its own raise is refused even when it delegated credit to the forwarder.
    function test_raiseCapAndBorrow_callerAsBorrower_reverts() public {
        vm.prank(riskCouncil);
        _debtToken(address(usdc)).approveDelegation(address(fwd), 5000e6);
        vm.prank(riskCouncil);
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        fwd.raiseCapAndBorrow(address(usdc), 5000e6, riskCouncil);
        assertEq(_debtToken(address(usdc)).balanceOf(riskCouncil), 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BATCH
    // ═══════════════════════════════════════════════════════════════════════════

    function _delegateFrom(address who, address asset, uint256 amount) internal {
        MockVariableDebtToken vdt = _debtToken(asset);
        vm.prank(who);
        vdt.approveDelegation(address(fwd), amount);
    }

    function _requests(uint256 a, uint256 b) internal view returns (ICapsBorrowForwarder.BorrowRequest[] memory r) {
        r = new ICapsBorrowForwarder.BorrowRequest[](2);
        r[0] = ICapsBorrowForwarder.BorrowRequest({ onBehalfOf: borrower, amount: a });
        r[1] = ICapsBorrowForwarder.BorrowRequest({ onBehalfOf: updater, amount: b });
    }

    /// Two borrowers in one call: one cap raise for the sum (+1 buffer), each gets its own tokens and debt.
    function test_raiseCapAndBorrowBatch_oneRaise_eachBorrowerPaid() public {
        _setLimits(MAX_RAISE_BPS, 1 days);
        _delegateFrom(borrower, address(usdc), 5000e6);
        _delegateFrom(updater, address(usdc), 3000e6);
        MockVariableDebtToken vdt = _debtToken(address(usdc));

        vm.expectEmit(true, true, false, true, address(fwd));
        emit ICapsBorrowForwarder.CapRaisedAndBorrowed(address(usdc), borrower, 5000e6, LIVE_CAP, LIVE_CAP + 8001);
        vm.expectEmit(true, true, false, true, address(fwd));
        emit ICapsBorrowForwarder.CapRaisedAndBorrowed(address(usdc), updater, 3000e6, LIVE_CAP, LIVE_CAP + 8001);
        vm.prank(riskCouncil);
        fwd.raiseCapAndBorrowBatch(address(usdc), _requests(5000e6, 3000e6));

        assertEq(_liveBorrowCap(address(usdc)), LIVE_CAP + 8001, "one raise for the sum");
        assertEq(usdc.balanceOf(borrower), 5000e6);
        assertEq(usdc.balanceOf(updater), 3000e6);
        assertEq(vdt.balanceOf(borrower), 5000e6);
        assertEq(vdt.balanceOf(updater), 3000e6);
        assertEq(vdt.borrowAllowance(borrower, address(fwd)), 0);
        assertEq(vdt.borrowAllowance(updater, address(fwd)), 0);
        assertEq(usdc.balanceOf(address(fwd)), 0, "forwarder keeps nothing");
        assertEq(usdc.balanceOf(riskCouncil), 0, "caller keeps nothing");
        assertEq(fwd.lastRaiseAt(address(usdc)), block.timestamp, "one raise recorded");
    }

    /// The cap rounds the sum up once: 0.5 + 0.5 USDC adds 1 token, plus the buffer.
    function test_raiseCapAndBorrowBatch_roundsTheSum() public {
        _delegateFrom(borrower, address(usdc), 500_000);
        _delegateFrom(updater, address(usdc), 500_000);
        vm.prank(riskCouncil);
        fwd.raiseCapAndBorrowBatch(address(usdc), _requests(500_000, 500_000));
        assertEq(_liveBorrowCap(address(usdc)), LIVE_CAP + 2);
    }

    /// One failed borrow (second delegation 1 USDC short) reverts the whole batch: no cap change, no borrow.
    function test_raiseCapAndBorrowBatch_oneFails_revertsAll() public {
        _setLimits(MAX_RAISE_BPS, 1 days);
        _delegateFrom(borrower, address(usdc), 5000e6);
        _delegateFrom(updater, address(usdc), 2999e6);

        vm.expectRevert(
            abi.encodeWithSelector(
                MockVariableDebtToken.InsufficientBorrowAllowance.selector, address(fwd), 2999e6, 3000e6
            )
        );
        vm.prank(riskCouncil);
        fwd.raiseCapAndBorrowBatch(address(usdc), _requests(5000e6, 3000e6));

        assertEq(_liveBorrowCap(address(usdc)), LIVE_CAP, "cap raise rolled back");
        assertEq(usdc.balanceOf(borrower), 0, "first borrow rolled back");
        assertEq(_debtToken(address(usdc)).borrowAllowance(borrower, address(fwd)), 5000e6, "delegation kept");
        assertEq(fwd.lastRaiseAt(address(usdc)), 0, "timer rolled back");
    }

    /// The per-raise limit applies to the sum: each request fits 1% of the cap, the sum does not.
    function test_raiseCapAndBorrowBatch_limitOnSum() public {
        _setLimits(100, 1); // max +10,000
        _delegateFrom(borrower, address(usdc), 6000e6);
        _delegateFrom(updater, address(usdc), 6000e6);

        vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.RaiseAboveLimit.selector, 12_001, 10_000));
        vm.prank(riskCouncil);
        fwd.raiseCapAndBorrowBatch(address(usdc), _requests(6000e6, 6000e6));

        vm.prank(riskCouncil);
        fwd.raiseCapAndBorrowBatch(address(usdc), _requests(6000e6, 3999e6));
        assertEq(_liveBorrowCap(address(usdc)), LIVE_CAP + 10_000, "sum exactly at the limit passes");
    }

    /// The RVM maxCap bounds the sum.
    function test_raiseCapAndBorrowBatch_aboveRvmMaxCap_reverts() public {
        _delegateFrom(borrower, address(usdc), 5000e6);
        _delegateFrom(updater, address(usdc), 3000e6);
        _setRvmMaxCap(address(usdc), 1_008_000);

        vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.NewCapAboveMaxCap.selector, 1_008_001, 1_008_000));
        vm.prank(riskCouncil);
        fwd.raiseCapAndBorrowBatch(address(usdc), _requests(5000e6, 3000e6));
        assertEq(_liveBorrowCap(address(usdc)), LIVE_CAP);
    }

    /// A batch counts as one raise for the delay.
    function test_raiseCapAndBorrowBatch_sharesTheDelay() public {
        _setLimits(MAX_RAISE_BPS, 1 days);
        _delegateFrom(borrower, address(usdc), 5000e6);
        _delegateFrom(updater, address(usdc), 3000e6);
        vm.prank(riskCouncil);
        fwd.raiseCapAndBorrowBatch(address(usdc), _requests(5000e6, 3000e6));

        _delegateFrom(borrower, address(usdc), 1000e6);
        vm.expectRevert(
            abi.encodeWithSelector(ICapsBorrowForwarder.RaiseTooSoon.selector, address(usdc), block.timestamp + 1 days)
        );
        _run(address(usdc), 1000e6);
    }

    /// Only an allowlisted caller; 1 to 20 requests; every request is checked like a single borrow.
    function test_raiseCapAndBorrowBatch_inputChecks() public {
        _delegateFrom(borrower, address(usdc), 5000e6);
        _delegateFrom(updater, address(usdc), 3000e6);

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.NotCaller.selector, attacker));
        fwd.raiseCapAndBorrowBatch(address(usdc), _requests(5000e6, 3000e6));

        vm.startPrank(riskCouncil);
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        fwd.raiseCapAndBorrowBatch(address(usdc), new ICapsBorrowForwarder.BorrowRequest[](0));

        ICapsBorrowForwarder.BorrowRequest[] memory tooMany = new ICapsBorrowForwarder.BorrowRequest[](21);
        for (uint256 i; i < 21; ++i) {
            tooMany[i] = ICapsBorrowForwarder.BorrowRequest({ onBehalfOf: borrower, amount: 1 });
        }
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        fwd.raiseCapAndBorrowBatch(address(usdc), tooMany);

        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        fwd.raiseCapAndBorrowBatch(address(usdc), _requests(5000e6, 0));

        ICapsBorrowForwarder.BorrowRequest[] memory bad = _requests(5000e6, 3000e6);
        bad[1].onBehalfOf = riskCouncil;
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        fwd.raiseCapAndBorrowBatch(address(usdc), bad);
        bad[1].onBehalfOf = address(fwd);
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        fwd.raiseCapAndBorrowBatch(address(usdc), bad);
        bad[1].onBehalfOf = address(0);
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        fwd.raiseCapAndBorrowBatch(address(usdc), bad);
        vm.stopPrank();

        assertEq(_liveBorrowCap(address(usdc)), LIVE_CAP);
    }

    /// The same borrower twice: the first borrow renounces the delegation, so the second fails and all reverts.
    function test_raiseCapAndBorrowBatch_duplicateBorrower_reverts() public {
        _delegateFrom(borrower, address(usdc), 8000e6);
        ICapsBorrowForwarder.BorrowRequest[] memory r = _requests(5000e6, 3000e6);
        r[1].onBehalfOf = borrower;

        vm.expectRevert(
            abi.encodeWithSelector(MockVariableDebtToken.InsufficientBorrowAllowance.selector, address(fwd), 0, 3000e6)
        );
        vm.prank(riskCouncil);
        fwd.raiseCapAndBorrowBatch(address(usdc), r);
        assertEq(_liveBorrowCap(address(usdc)), LIVE_CAP);
        assertEq(usdc.balanceOf(borrower), 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE TRANSITIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// CAP-ST-26: raiseCapAndBorrow(USDC, 5,000e6, borrower): borrower debt +5,000, borrower USDC
    /// +5,000, caller and forwarder USDC +0, no other account keeps tokens. The event carries old and new cap.
    function test_CAP_ST_26_raiseCapAndBorrow_tokensOnlyToBorrower() public {
        uint256 amount = 5000e6;
        _delegate(address(usdc), amount);
        MockVariableDebtToken vdt = _debtToken(address(usdc));

        uint256 debtBefore = vdt.balanceOf(borrower);
        uint256 totalDebtBefore = vdt.totalSupply();
        uint256 poolBefore = usdc.balanceOf(address(pool));

        vm.expectEmit(true, true, false, true, address(fwd));
        emit ICapsBorrowForwarder.CapRaisedAndBorrowed(address(usdc), borrower, amount, LIVE_CAP, LIVE_CAP + 5001);
        _run(address(usdc), amount);

        assertEq(vdt.balanceOf(borrower) - debtBefore, amount, "borrower debt +amount");
        assertEq(vdt.totalSupply() - totalDebtBefore, amount, "total debt +amount");
        assertEq(usdc.balanceOf(borrower), amount, "borrower tokens +amount");
        assertEq(usdc.balanceOf(riskCouncil), 0, "caller keeps nothing");
        assertEq(usdc.balanceOf(address(fwd)), 0, "forwarder keeps nothing");
        assertEq(poolBefore - usdc.balanceOf(address(pool)), amount, "pool paid out exactly amount");
        assertEq(vdt.balanceOf(riskCouncil), 0, "caller carries no debt");
        assertEq(vdt.balanceOf(address(fwd)), 0, "forwarder carries no debt");
        assertEq(vdt.borrowAllowance(borrower, address(fwd)), 0, "delegation used up");
        assertEq(fwd.lastRaiseAt(address(usdc)), block.timestamp, "raise recorded");
    }

    /// CAP-ST-26 fuzzed over amount and the three decimals.
    function testFuzz_CAP_ST_26_raiseCapAndBorrow_tokensOnlyToBorrower(uint256 seed, uint256 amount) public {
        MockERC20[3] memory assets = [weth, usdc, wbtc];
        address asset = address(assets[seed % 3]);
        pool.setBorrowCap(asset, LIVE_CAP);
        amount = bound(amount, 1, _wei(asset, LIVE_CAP / 2));
        _delegate(asset, amount);

        _run(asset, amount);

        assertEq(_debtToken(asset).balanceOf(borrower), amount);
        assertEq(IERC20(asset).balanceOf(borrower), amount);
        assertEq(IERC20(asset).balanceOf(riskCouncil), 0);
        assertEq(IERC20(asset).balanceOf(address(fwd)), 0);
        assertEq(_debtToken(asset).borrowAllowance(borrower, address(fwd)), 0, "delegation used up");
    }

    /// CAP-ST-27: the forwarder's and the caller's token balances are the same before and after
    /// raiseCapAndBorrow, also when they already hold some of the asset.
    function test_CAP_ST_27_raiseCapAndBorrow_noResidualBalance() public {
        usdc.mint(riskCouncil, 777e6);
        usdc.mint(address(fwd), 55e6);
        _delegate(address(usdc), 5000e6);

        _run(address(usdc), 5000e6);

        assertEq(usdc.balanceOf(riskCouncil), 777e6, "caller balance unchanged");
        assertEq(usdc.balanceOf(address(fwd)), 55e6, "forwarder balance unchanged");
        assertEq(usdc.balanceOf(borrower), 5000e6);
    }

    /// CAP-ST-29: live cap 1,000,000 USDC, amount 5,000.5 USDC: new cap 1,005,002, written by the engine with
    /// the supply cap kept.
    function test_CAP_ST_29_raiseCapAndBorrow_raisesAmountPlusBuffer() public {
        pool.setSupplyCap(address(usdc), 3_000_000);

        uint256 amount = 5_000_500_000; // 5,000.5 USDC
        _delegate(address(usdc), amount);
        _run(address(usdc), amount);

        (uint256 borrowCap, uint256 supplyCap) = pool.getReserveCaps(address(usdc));
        assertEq(borrowCap, 1_005_002, "live cap + ceil(5,000.5) + 1");
        assertEq(supplyCap, 3_000_000, "supply cap kept");
    }

    /// CAP-ST-29 fuzzed: new cap = live cap + ceil(amount / 10^dec) + 1, read at execution.
    function testFuzz_CAP_ST_29_raiseCapAndBorrow_raisesAmountPlusBuffer(
        uint256 seed,
        uint256 liveCap,
        uint256 amount
    )
        public
    {
        MockERC20[3] memory assets = [weth, usdc, wbtc];
        address asset = address(assets[seed % 3]);
        liveCap = bound(liveCap, 10, 1_000_000);
        // Stay inside the default +100% per-raise limit: ceil(amount) + 1 <= liveCap.
        amount = bound(amount, 1, _wei(asset, liveCap / 2));
        pool.setBorrowCap(asset, liveCap);
        _setDebt(asset, 0, 0);
        _delegate(asset, amount);

        uint256 unit = 10 ** MockERC20(asset).decimals();
        uint256 expected = liveCap + (amount + unit - 1) / unit + 1;

        _run(asset, amount);

        assertEq(_liveBorrowCap(asset), expected);
    }

    /// The new cap stays within the RVM borrow maxCap, so the reducer never cuts the cap below the debt:
    /// maxCap 1,005,000 refuses 1,005,001; maxCap 1,005,001 passes. No cap change and no borrow on refusal.
    function test_raiseCapAndBorrow_aboveRvmMaxCap_reverts() public {
        _delegate(address(usdc), 5000e6);
        _setRvmMaxCap(address(usdc), 1_005_000);

        vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.NewCapAboveMaxCap.selector, 1_005_001, 1_005_000));
        _run(address(usdc), 5000e6);
        assertEq(_liveBorrowCap(address(usdc)), LIVE_CAP);
        assertEq(_debtToken(address(usdc)).balanceOf(borrower), 0);

        _setRvmMaxCap(address(usdc), 1_005_001);
        _run(address(usdc), 5000e6);
        assertEq(_liveBorrowCap(address(usdc)), 1_005_001);
    }

    /// An asset with no RVM borrow entry (maxCap 0) cannot be raised by the forwarder.
    function test_raiseCapAndBorrow_noRvmEntry_reverts() public {
        IRvm.RateLimitConfig memory none;
        capsRvm.setRateLimitConfig(address(usdc), IRvm.CapKind.BORROW, none);
        _delegate(address(usdc), 5000e6);
        vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.NewCapAboveMaxCap.selector, 1_005_001, 0));
        _run(address(usdc), 5000e6);
        assertEq(_liveBorrowCap(address(usdc)), LIVE_CAP);
    }

    /// Only the borrow entry bounds the forwarder: a supply maxCap below the new cap does not.
    function test_raiseCapAndBorrow_supplyMaxCap_ignored() public {
        _delegate(address(usdc), 5000e6);
        IRvm.RateLimitConfig memory c = IRvm.RateLimitConfig({ maxCap: 1, maxHeadroom: 1, alphaBps: 0, cutBandBps: 0 });
        capsRvm.setRateLimitConfig(address(usdc), IRvm.CapKind.SUPPLY, c);
        _run(address(usdc), 5000e6);
        assertEq(_liveBorrowCap(address(usdc)), 1_005_001);
    }

    /// Accrued interest pushed the debt above the cap: 1,000,500.000001 USDC of debt against a 1,000,000 cap.
    /// The new cap starts from the debt rounded up (1,000,501), so the 5,000 borrow fits:
    /// 1,000,501 + 5,000 + 1 = 1,005,502. Starting from the cap (1,005,001) the borrow would exceed it.
    function test_raiseCapAndBorrow_debtAboveCap_startsFromDebt() public {
        _setDebt(address(usdc), 1_000_500, 1);
        _delegate(address(usdc), 5000e6);
        _run(address(usdc), 5000e6);
        assertEq(_liveBorrowCap(address(usdc)), 1_005_502);
        assertEq(usdc.balanceOf(borrower), 5000e6);
    }

    /// Debt below the cap: the new cap still starts from the cap.
    function test_raiseCapAndBorrow_debtBelowCap_startsFromCap() public {
        _delegate(address(usdc), 5000e6);
        _run(address(usdc), 5000e6);
        assertEq(_liveBorrowCap(address(usdc)), LIVE_CAP + 5001);
    }

    /// CAP-ST-30: the forwarder does not set a first cap.
    function test_CAP_ST_30_raiseCapAndBorrow_uncapped_reverts() public {
        pool.setBorrowCap(address(usdc), 0);
        _delegate(address(usdc), 5000e6);

        vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.BorrowCapNotSet.selector, address(usdc)));
        _run(address(usdc), 5000e6);
        assertEq(_liveBorrowCap(address(usdc)), 0);
        assertEq(_debtToken(address(usdc)).balanceOf(borrower), 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PER-RAISE LIMIT (maxRaiseBps of the live cap)
    // ═══════════════════════════════════════════════════════════════════════════

    /// maxRaiseBps 100 (1%) of a 1,000,000 cap: an increase of 10,000 passes, 10,001 reverts with no change.
    function test_maxRaiseBps_boundary() public {
        _setLimits(100, 1);
        _delegate(address(usdc), 10_000e6);

        vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.RaiseAboveLimit.selector, 10_001, 10_000));
        _run(address(usdc), 10_000e6);
        assertEq(_liveBorrowCap(address(usdc)), LIVE_CAP);
        assertEq(_debtToken(address(usdc)).balanceOf(borrower), 0);

        _run(address(usdc), 9999e6);
        assertEq(_liveBorrowCap(address(usdc)), LIVE_CAP + 10_000, "exactly at the limit passes");
    }

    /// The limit floors: 1% of a 999 cap is 9 tokens, so +9 passes and +10 reverts.
    function test_maxRaiseBps_floors() public {
        pool.setBorrowCap(address(weth), 999);
        _setLimits(100, 1);
        _delegate(address(weth), 10e18);

        vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.RaiseAboveLimit.selector, 10, 9));
        _run(address(weth), 9e18);

        _run(address(weth), 8e18);
        assertEq(_liveBorrowCap(address(weth)), 1008);
    }

    /// The increase counts from the live cap, so a debt overshoot above the cap counts toward the limit.
    function test_maxRaiseBps_countsDebtOvershoot() public {
        _setDebt(address(usdc), 1_000_500, 1); // ceil = 1,000,501
        _setLimits(100, 1); // max +10,000
        _delegate(address(usdc), 9500e6);
        // 1,000,501 + 9,499 + 1 = 1,010,001: increase 10,001 over the cap.
        vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.RaiseAboveLimit.selector, 10_001, 10_000));
        _run(address(usdc), 9499e6);
        _run(address(usdc), 9498e6);
        assertEq(_liveBorrowCap(address(usdc)), LIVE_CAP + 10_000);
    }

    /// Fuzzed: the raise passes iff the increase is at most floor(oldCap * bps / 10,000).
    function testFuzz_maxRaiseBps(uint256 bps, uint256 amountTokens) public {
        bps = bound(bps, 1, 20_000);
        amountTokens = bound(amountTokens, 1, 1_000_000);
        _setLimits(bps, 1);
        uint256 amount = _wei(address(usdc), amountTokens);
        _delegate(address(usdc), amount);

        uint256 increase = amountTokens + 1; // the rounding buffer
        uint256 maxIncrease = LIVE_CAP * bps / 10_000;
        vm.prank(riskCouncil);
        (bool ok,) =
            address(fwd).call(abi.encodeCall(ICapsBorrowForwarder.raiseCapAndBorrow, (address(usdc), amount, borrower)));
        assertEq(ok, increase <= maxIncrease, "passes iff within the limit");
        assertEq(_liveBorrowCap(address(usdc)), ok ? LIVE_CAP + increase : LIVE_CAP);
    }

    /// setLimits is owner only, emits LimitsSet, refuses maxRaiseBps 0, and the new value applies to the next raise.
    function test_setLimits_ownerOnly_andApplies() public {
        vm.prank(riskCouncil);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, riskCouncil));
        fwd.setLimits(1, 1);
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        fwd.setLimits(20_000, 1);

        vm.prank(governance);
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        fwd.setLimits(0, 1);
        vm.prank(governance);
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        fwd.setLimits(1, 0);

        vm.expectEmit(false, false, false, true, address(fwd));
        emit ICapsBorrowForwarder.LimitsSet(50, 2 days);
        _setLimits(50, 2 days);
        assertEq(fwd.maxRaiseBps(), 50);
        assertEq(fwd.minRaiseDelay(), 2 days);

        // 0.5% of 1,000,000 = 5,000: 5,000 + 1 is now above it.
        _delegate(address(usdc), 5000e6);
        vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.RaiseAboveLimit.selector, 5001, 5000));
        _run(address(usdc), 5000e6);
        _run(address(usdc), 4999e6);
        assertEq(_liveBorrowCap(address(usdc)), LIVE_CAP + 5000);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PER-PERIOD LIMIT (minRaiseDelay per asset)
    // ═══════════════════════════════════════════════════════════════════════════

    /// minRaiseDelay 1 day: a second raise of the same asset at +1 day - 1 s reverts RaiseTooSoon with nothing
    /// changed; at exactly +1 day it passes.
    function test_minRaiseDelay_boundary() public {
        _setLimits(MAX_RAISE_BPS, 1 days);
        uint256 t0 = block.timestamp;
        _delegate(address(usdc), 5000e6);
        _run(address(usdc), 5000e6);
        uint256 capAfterFirst = _liveBorrowCap(address(usdc));

        vm.warp(t0 + 1 days - 1);
        _delegate(address(usdc), 5000e6);
        vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.RaiseTooSoon.selector, address(usdc), t0 + 1 days));
        _run(address(usdc), 5000e6);
        assertEq(_liveBorrowCap(address(usdc)), capAfterFirst, "cap unchanged");
        assertEq(_debtToken(address(usdc)).balanceOf(borrower), 5000e6, "debt unchanged");
        assertEq(fwd.lastRaiseAt(address(usdc)), t0, "timer not reset by the failed raise");

        vm.warp(t0 + 1 days);
        _run(address(usdc), 5000e6);
        assertEq(_debtToken(address(usdc)).balanceOf(borrower), 10_000e6);
        assertEq(fwd.lastRaiseAt(address(usdc)), t0 + 1 days);
    }

    /// The delay is per asset: a raise of USDC does not delay WETH.
    function test_minRaiseDelay_perAsset() public {
        _setLimits(MAX_RAISE_BPS, 1 days);
        pool.setBorrowCap(address(weth), 1000);
        _delegate(address(usdc), 5000e6);
        _run(address(usdc), 5000e6);
        _delegate(address(weth), 5e18);
        _run(address(weth), 5e18);
        assertEq(_liveBorrowCap(address(weth)), 1006);
    }

    /// A raise that fails after the delay check (here the RVM maxCap) does not start the delay.
    function test_minRaiseDelay_failedRaiseDoesNotStartTimer() public {
        _setLimits(MAX_RAISE_BPS, 1 days);
        _setRvmMaxCap(address(usdc), 1);
        _delegate(address(usdc), 5000e6);
        vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.NewCapAboveMaxCap.selector, 1_005_001, 1));
        _run(address(usdc), 5000e6);
        assertEq(fwd.lastRaiseAt(address(usdc)), 0);

        _setRvmMaxCap(address(usdc), RVM_MAX_CAP);
        _run(address(usdc), 5000e6);
        assertEq(usdc.balanceOf(borrower), 5000e6);
    }

    /// An owner update of minRaiseDelay applies at once against the stored lastRaiseAt: shortening it lets the
    /// next raise through, lengthening it pushes the next raise out.
    function test_minRaiseDelay_ownerUpdateApplies() public {
        _setLimits(MAX_RAISE_BPS, 1 days);
        uint256 t0 = block.timestamp;
        _delegate(address(usdc), 5000e6);
        _run(address(usdc), 5000e6);

        vm.warp(t0 + 1 hours);
        _delegate(address(usdc), 1000e6);
        vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.RaiseTooSoon.selector, address(usdc), t0 + 1 days));
        _run(address(usdc), 1000e6);

        _setLimits(MAX_RAISE_BPS, 1 hours);
        _run(address(usdc), 1000e6);
        uint256 t1 = block.timestamp;

        _setLimits(MAX_RAISE_BPS, 3 days);
        vm.warp(t1 + 1 days);
        _delegate(address(usdc), 1000e6);
        vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.RaiseTooSoon.selector, address(usdc), t1 + 3 days));
        _run(address(usdc), 1000e6);
    }

    /// The 1 second minimum: a second raise in the same block reverts, the next second passes.
    function test_minRaiseDelay_minimum_blocksSameBlock() public {
        _delegate(address(usdc), 5000e6);
        _run(address(usdc), 5000e6);
        _delegate(address(usdc), 5000e6);
        vm.expectRevert(
            abi.encodeWithSelector(ICapsBorrowForwarder.RaiseTooSoon.selector, address(usdc), block.timestamp + 1)
        );
        _run(address(usdc), 5000e6);

        skip(1);
        _run(address(usdc), 5000e6);
        assertEq(_debtToken(address(usdc)).balanceOf(borrower), 10_000e6);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DELEGATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// After a raise the borrower's remaining delegation to the forwarder is renounced: a larger delegation is
    /// not kept, and a second raise needs a fresh approveDelegation.
    function test_raiseCapAndBorrow_renouncesDelegation() public {
        _delegate(address(usdc), 20_000e6);
        _run(address(usdc), 5000e6);
        assertEq(_debtToken(address(usdc)).borrowAllowance(borrower, address(fwd)), 0, "rest renounced");

        skip(1);
        vm.expectRevert(
            abi.encodeWithSelector(MockVariableDebtToken.InsufficientBorrowAllowance.selector, address(fwd), 0, 5000e6)
        );
        _run(address(usdc), 5000e6);

        _delegate(address(usdc), 5000e6);
        _run(address(usdc), 5000e6);
        assertEq(_debtToken(address(usdc)).balanceOf(borrower), 10_000e6);
    }

    /// A delegation to the caller does not let the forwarder borrow: the Pool sees the forwarder as delegatee.
    function test_raiseCapAndBorrow_delegationToCaller_reverts() public {
        vm.prank(borrower);
        _debtToken(address(usdc)).approveDelegation(riskCouncil, 5000e6);
        vm.expectRevert(
            abi.encodeWithSelector(MockVariableDebtToken.InsufficientBorrowAllowance.selector, address(fwd), 0, 5000e6)
        );
        _run(address(usdc), 5000e6);
        assertEq(_liveBorrowCap(address(usdc)), LIVE_CAP, "cap raise rolled back");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ATOMICITY (CAP-ST-31)
    // ═══════════════════════════════════════════════════════════════════════════

    /// CAP-ST-31: the borrow fails (delegation 1 USDC short): the cap raise and the raise timestamp roll back.
    function test_CAP_ST_31_raiseCapAndBorrow_borrowFails_revertsAll() public {
        _setLimits(MAX_RAISE_BPS, 1 days);
        _delegate(address(usdc), 4999e6);
        vm.expectRevert(
            abi.encodeWithSelector(
                MockVariableDebtToken.InsufficientBorrowAllowance.selector, address(fwd), 4999e6, 5000e6
            )
        );
        _run(address(usdc), 5000e6);
        assertEq(_liveBorrowCap(address(usdc)), LIVE_CAP, "cap raise rolled back");
        assertEq(_debtToken(address(usdc)).balanceOf(borrower), 0);
        assertEq(_debtToken(address(usdc)).borrowAllowance(borrower, address(fwd)), 4999e6, "delegation kept");
        assertEq(fwd.lastRaiseAt(address(usdc)), 0, "timer rolled back");
    }

    /// Aave's own rounding: debt of exactly 1,000,000 USDC at a borrow index other than 1 ray. The scaled sum
    /// rounds the new debt to 1,005,000.000001 USDC, 1 unit above 1,005,000. The 1-token buffer covers it.
    function test_raiseCapAndBorrow_aaveDebtRounding_coveredByBuffer() public {
        pool.setIndex(address(usdc), 1_039_061_234_472_907_871_979_912_753);
        pool.setScaledDebt(address(usdc), 962_407_187_202);
        assertEq(_debtToken(address(usdc)).totalSupply(), 1_000_000e6, "debt exactly on whole tokens");
        _delegate(address(usdc), 5000e6);

        _run(address(usdc), 5000e6);
        assertEq(_liveBorrowCap(address(usdc)), 1_005_001);
        assertEq(usdc.balanceOf(borrower), 5000e6);
    }

    /// CAP-ST-31: the transfer to the borrower fails (returns false, as for a blocklisted borrower).
    function test_CAP_ST_31_raiseCapAndBorrow_transferFails_revertsAll() public {
        QuirkyERC20 q = _listQuirky();
        q.setBlockedTo(borrower);
        _delegate(address(q), 5000e6);

        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(q)));
        _run(address(q), 5000e6);
        assertEq(_liveBorrowCap(address(q)), LIVE_CAP);
        assertEq(_debtToken(address(q)).balanceOf(borrower), 0);
        assertEq(q.balanceOf(riskCouncil), 0);
        assertEq(q.balanceOf(address(fwd)), 0);
        assertEq(_debtToken(address(q)).borrowAllowance(borrower, address(fwd)), 5000e6, "delegation unused");
    }

    /// The token's transfer reverts: the revert bubbles up and nothing changes.
    function test_CapsBorrowForwarder_transferReverts_revertsAll() public {
        QuirkyERC20 q = _listQuirky();
        q.setRevertFrom(address(fwd));
        _delegate(address(q), 5000e6);

        vm.expectRevert("QuirkyERC20: transfer reverted");
        _run(address(q), 5000e6);
        assertEq(_liveBorrowCap(address(q)), LIVE_CAP);
        assertEq(_debtToken(address(q)).balanceOf(borrower), 0);
    }

    /// The asset has no code (and no return data) when the transfer runs: reverts SafeERC20FailedOperation.
    function test_CapsBorrowForwarder_assetWithNoCode_reverts() public {
        QuirkyERC20 q = _listQuirky();
        q.setSelfEtchFrom(address(fwd));
        _delegate(address(q), 5000e6);

        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(q)));
        _run(address(q), 5000e6);
    }

    /// CAP-ST-31: the forwarder balance differs after the transfer (token moved only half): reverts.
    function test_CAP_ST_31_raiseCapAndBorrow_balanceChanged_revertsAll() public {
        QuirkyERC20 q = _listQuirky();
        q.setHalfFrom(address(fwd));
        _delegate(address(q), 5000e6);

        vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.ForwarderBalanceChanged.selector, 0, 2500e6));
        _run(address(q), 5000e6);
        assertEq(_liveBorrowCap(address(q)), LIVE_CAP);
        assertEq(_debtToken(address(q)).balanceOf(borrower), 0);
        assertEq(q.balanceOf(borrower), 0);
    }

    /// A token with no return value on `transfer` (USDT style) is accepted.
    function test_CapsBorrowForwarder_noReturnValueToken_succeeds() public {
        QuirkyERC20 q = _listQuirky();
        q.setNoReturnFrom(address(fwd));
        _delegate(address(q), 5000e6);

        _run(address(q), 5000e6);
        assertEq(q.balanceOf(borrower), 5000e6);
        assertEq(q.balanceOf(riskCouncil), 0);
        assertEq(q.balanceOf(address(fwd)), 0);
    }

    function _listQuirky() internal returns (QuirkyERC20 q) {
        q = new QuirkyERC20(6);
        pool.listReserve(address(q), 6, LIVE_CAP, 0);
        q.mint(address(pool), _wei(address(q), LIQUIDITY));
        _setRvmMaxCap(address(q), RVM_MAX_CAP);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CALL SURFACE (CAP-ACL-16)
    // ═══════════════════════════════════════════════════════════════════════════

    /// CAP-ACL-16: in raiseCapAndBorrow the forwarder makes only these calls: POOL.getConfiguration(asset),
    /// POOL.getReserveData(asset) (twice), the debt token's totalSupply, RVM.getKeyState(asset, BORROW), one
    /// delegatecall CONFIG_ENGINE.updateCaps([{asset, KEEP_CURRENT, newCap}]), and from the engine code
    /// POOL.setBorrowCap(asset, newCap), then POOL.borrow(asset, amount, 2, 0, borrower),
    /// asset.balanceOf(forwarder) (twice), asset.transfer(borrower, amount) and
    /// debtToken.renounceDelegation(borrower).
    function test_CAP_ACL_16_raiseCapAndBorrow_onlyExpectedCalls() public {
        uint256 amount = 5000e6;
        uint256 newCap = LIVE_CAP + 5001;
        _delegate(address(usdc), amount);

        vm.startStateDiffRecording();
        _run(address(usdc), amount);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();

        // 0 delegatecall, 1 getConfiguration, 2 getReserveData, 3 setBorrowCap, 4 borrow, 5 totalSupply,
        // 6 renounceDelegation, 7 getKeyState, 8 balanceOf, 9 transfer
        uint256[10] memory n;
        for (uint256 i = 0; i < acc.length; i++) {
            Vm.AccountAccess memory a = acc[i];
            if (a.kind == Vm.AccountAccessKind.Resume) continue;
            // Checked across the whole trace: the only delegatecall is the forwarder into the engine.
            if (a.kind == Vm.AccountAccessKind.DelegateCall) {
                assertEq(a.account, address(engine), "only delegatecall is into the config engine");
                IEngine.CapsUpdate[] memory u = new IEngine.CapsUpdate[](1);
                u[0] = IEngine.CapsUpdate({
                    asset: address(usdc), supplyCap: EngineFlags.KEEP_CURRENT, borrowCap: newCap
                });
                assertEq(a.data, abi.encodeCall(MockCapsEngine.updateCaps, (u)), "engine calldata");
                n[0]++;
                continue;
            }
            if (a.accessor != address(fwd)) continue;
            _countForwarderCall(a, amount, newCap, n);
        }
        assertEq(n[0], 1, "one delegatecall");
        assertEq(n[1], 1, "one getConfiguration");
        assertEq(n[2], 2, "two getReserveData");
        assertEq(n[3], 1, "one setBorrowCap");
        assertEq(n[4], 1, "one borrow");
        assertEq(n[5], 1, "one debt totalSupply");
        assertEq(n[6], 1, "one renounceDelegation");
        assertEq(n[7], 1, "one RVM key read");
        assertEq(n[8], 2, "two forwarder balance reads");
        assertEq(n[9], 1, "one transfer");
    }

    /// @dev CAP-ACL-16: one access made in the forwarder's context, checked against its exact calldata.
    function _countForwarderCall(
        Vm.AccountAccess memory a,
        uint256 amount,
        uint256 newCap,
        uint256[10] memory n
    )
        private
        view
    {
        address vdt = address(_debtToken(address(usdc)));
        if (a.kind == Vm.AccountAccessKind.Extcodesize) {
            assertTrue(
                a.account == address(usdc) || a.account == address(pool) || a.account == vdt
                    || a.account == address(capsRvm) || a.account == address(engine),
                "code-size check on an expected account only"
            );
            return;
        }
        assertTrue(
            a.kind == Vm.AccountAccessKind.Call || a.kind == Vm.AccountAccessKind.StaticCall, "call or staticcall"
        );
        bytes32 h = keccak256(a.data);
        if (a.account == address(pool)) {
            if (h == keccak256(abi.encodeCall(MockPoolV3.getConfiguration, (address(usdc))))) n[1]++;
            else if (h == keccak256(abi.encodeCall(MockPoolV3.getReserveData, (address(usdc))))) n[2]++;
            else if (h == keccak256(abi.encodeCall(MockPoolV3.setBorrowCap, (address(usdc), newCap)))) n[3]++;
            else if (h == keccak256(abi.encodeCall(MockPoolV3.borrow, (address(usdc), amount, 2, 0, borrower)))) n[4]++;
            else revert("unexpected Pool call");
        } else if (a.account == vdt) {
            if (h == keccak256(abi.encodeCall(IERC20.totalSupply, ()))) n[5]++;
            else if (h == keccak256(abi.encodeCall(MockVariableDebtToken.renounceDelegation, (borrower)))) n[6]++;
            else revert("unexpected debt token call");
        } else if (a.account == address(capsRvm)) {
            if (h == keccak256(abi.encodeCall(MockCapsRvm.getKeyState, (address(usdc), IRvm.CapKind.BORROW)))) n[7]++;
            else revert("unexpected RVM call");
        } else if (a.account == address(usdc)) {
            if (h == keccak256(abi.encodeCall(IERC20.balanceOf, (address(fwd))))) n[8]++;
            else if (h == keccak256(abi.encodeCall(IERC20.transfer, (borrower, amount)))) n[9]++;
            else revert("unexpected asset call");
        } else {
            revert("unexpected account called from the forwarder");
        }
    }

    /// A raise changes exactly one forwarder storage slot, lastRaiseAt[asset] (the reentrancy status returns to
    /// its value), and no admin state.
    function test_raiseCapAndBorrow_onlyLastRaiseAtChanges() public {
        _delegate(address(usdc), 5000e6);
        vm.startStateDiffRecording();
        _run(address(usdc), 5000e6);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();

        bytes32[] memory slots = new bytes32[](64);
        bytes32[] memory before = new bytes32[](64);
        uint256 k;
        for (uint256 i = 0; i < acc.length; i++) {
            for (uint256 j = 0; j < acc[i].storageAccesses.length; j++) {
                Vm.StorageAccess memory s = acc[i].storageAccesses[j];
                if (s.account != address(fwd) || !s.isWrite || s.reverted) continue;
                bool seen;
                for (uint256 m = 0; m < k; m++) {
                    if (slots[m] == s.slot) seen = true;
                }
                if (!seen) {
                    slots[k] = s.slot;
                    before[k] = s.previousValue;
                    k++;
                }
            }
        }
        uint256 changed;
        for (uint256 m = 0; m < k; m++) {
            bytes32 nowValue = vm.load(address(fwd), slots[m]);
            if (nowValue != before[m]) {
                changed++;
                assertEq(uint256(nowValue), block.timestamp, "the changed slot holds the raise timestamp");
            }
        }
        assertEq(changed, 1, "only lastRaiseAt changed");
        assertEq(fwd.lastRaiseAt(address(usdc)), block.timestamp);
        assertEq(fwd.owner(), governance);
        assertTrue(fwd.isCaller(riskCouncil));
        assertEq(fwd.maxRaiseBps(), MAX_RAISE_BPS);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UNITS
    // ═══════════════════════════════════════════════════════════════════════════

    /// CAP-UNIT-13: USDC amount 5,000,000,001 units (5,000.000001 USDC) adds 5,001 tokens to the cap, plus
    /// the 1-token rounding buffer.
    function test_CAP_UNIT_13_raiseCapAndBorrow_amountRoundsUp() public {
        _delegate(address(usdc), type(uint256).max);
        _run(address(usdc), 5_000_000_001);
        assertEq(_liveBorrowCap(address(usdc)), LIVE_CAP + 5002);

        // WBTC (8 decimals), exact whole amount: no round-up.
        pool.setBorrowCap(address(wbtc), 1000);
        _delegate(address(wbtc), type(uint256).max);
        _run(address(wbtc), 5e8);
        assertEq(_liveBorrowCap(address(wbtc)), 1006);

        // WETH (18 decimals), 1 wei adds a whole token.
        pool.setBorrowCap(address(weth), 1000);
        _delegate(address(weth), type(uint256).max);
        _run(address(weth), 1);
        assertEq(_liveBorrowCap(address(weth)), 1002);
    }

    /// CAP-UNIT-13 fuzzed: cap increase * 10^dec >= amount and the increase is the least such whole number.
    function testFuzz_CAP_UNIT_13_raiseCapAndBorrow_amountRoundsUp(uint256 seed, uint256 amount) public {
        MockERC20[3] memory assets = [weth, usdc, wbtc];
        address asset = address(assets[seed % 3]);
        pool.setBorrowCap(asset, LIVE_CAP);
        amount = bound(amount, 1, _wei(asset, LIVE_CAP / 2));
        _delegate(asset, amount);

        _run(asset, amount);

        uint256 unit = 10 ** MockERC20(asset).decimals();
        // Less the 1-token rounding buffer.
        uint256 increase = _liveBorrowCap(asset) - LIVE_CAP - 1;
        assertGe(increase * unit, amount, "raise covers the borrow");
        assertLt((increase - 1) * unit, amount, "raise is the least whole-token cover");
    }
}

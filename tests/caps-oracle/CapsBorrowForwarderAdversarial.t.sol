// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { CapsTestBase } from "./CapsTestBase.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockPoolV3, MockVariableDebtToken } from "./mocks/MockPoolV3.sol";
import { MockCapsEngine } from "./mocks/MockCapsEngine.sol";
import { MockCapsRvm } from "./mocks/MockCapsRvm.sol";
import { CapsBorrowForwarder } from "../../src/caps-oracle/CapsBorrowForwarder.sol";
import { ICapsBorrowForwarder } from "../../src/caps-oracle/interfaces/ICapsBorrowForwarder.sol";
import { ICapsRangeValidationModule as IRvm } from "../../src/caps-oracle/interfaces/ICapsRangeValidationModule.sol";

/// @title ReentrantERC20
/// @notice ERC20 that, once armed, runs one arbitrary call after a `transfer` sent by `hookFrom` (and to `hookTo`,
///         when set). The call can bubble its revert or be swallowed, with the result recorded.
contract ReentrantERC20 is MockERC20 {
    address public hookFrom;
    address public hookTo;
    address public target;
    bytes public data;
    bool public bubble;
    bool public armed;
    bool public lastOk;
    bytes public lastRet;
    uint256 public fired;

    constructor(uint8 decimals_) MockERC20("Reentrant", "RNT", decimals_) { }

    function arm(address from, address to, address target_, bytes calldata data_, bool bubble_) external {
        hookFrom = from;
        hookTo = to;
        target = target_;
        data = data_;
        bubble = bubble_;
        armed = true;
    }

    /// @dev Moves `amount` from `from` to `to` with no approval: a hostile token can move any balance.
    function steal(address from, address to, uint256 amount) external {
        _transfer(from, to, amount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        bool ok = super.transfer(to, amount);
        if (armed && msg.sender == hookFrom && (hookTo == address(0) || to == hookTo)) {
            armed = false;
            fired++;
            (bool s, bytes memory r) = target.call(data);
            lastOk = s;
            lastRet = r;
            if (!s && bubble) {
                assembly {
                    revert(add(r, 32), mload(r))
                }
            }
        }
        return ok;
    }
}

/// @title FeeOnPoolERC20
/// @notice ERC20 that delivers only half of a `transfer` sent by `halfFrom` (a fee on the Pool's payout).
contract FeeOnPoolERC20 is MockERC20 {
    address public halfFrom;

    constructor(uint8 decimals_) MockERC20("Fee", "FEE", decimals_) { }

    function setHalfFrom(address a) external {
        halfFrom = a;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (msg.sender == halfFrom) {
            _transfer(msg.sender, to, amount / 2);
            return true;
        }
        return super.transfer(to, amount);
    }
}

/// @title CallerContract
/// @notice A contract caller (for example a Safe module or a malicious borrower's contract that got allowlisted)
///         that forwards any call. Used to re-enter the forwarder as an allowlisted caller.
contract CallerContract {
    function exec(address target, bytes calldata data) external returns (bytes memory ret) {
        bool ok;
        (ok, ret) = target.call(data);
        if (!ok) {
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }
    }
}

/// @notice Adversarial tests of the forwarder borrow path: fuzzed callers, donations, re-entrant tokens and
///         re-entrant callers. Goal under test: borrowed tokens only ever reach the borrower that carries the
///         debt, and only a borrower that delegated credit to the forwarder carries debt.
abstract contract AdversarialBase is CapsTestBase {
    CapsBorrowForwarder internal fwd;
    MockCapsRvm internal capsRvm;
    MockCapsEngine internal engine;

    uint256 internal constant LIVE_CAP = 1_000_000;
    uint256 internal constant LIVE_DEBT = 900_000;
    uint256 internal constant LIQUIDITY = 100_000_000;
    uint64 internal constant RVM_MAX_CAP = 100_000_000_000;

    function setUp() public virtual override {
        super.setUp();
        vm.warp(1_700_000_000);
        capsRvm = new MockCapsRvm();
        capsRvm.setPool(address(pool));
        engine = new MockCapsEngine(pool);
        fwd = new CapsBorrowForwarder(governance, address(pool), address(engine), address(capsRvm), riskCouncil, 1, 1);

        usdc.mint(address(pool), _wei(address(usdc), LIQUIDITY));
        weth.mint(address(pool), _wei(address(weth), LIQUIDITY));
        wbtc.mint(address(pool), _wei(address(wbtc), LIQUIDITY));
        _setRvmMaxCap(address(usdc));
        _setRvmMaxCap(address(weth));
        _setRvmMaxCap(address(wbtc));

        pool.setBorrowCap(address(usdc), LIVE_CAP);
        _setDebt(address(usdc), LIVE_DEBT, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    function _setRvmMaxCap(address asset) internal {
        IRvm.RateLimitConfig memory c =
            IRvm.RateLimitConfig({ maxCap: RVM_MAX_CAP, maxHeadroom: 1, alphaBps: 0, cutBandBps: 0 });
        capsRvm.setRateLimitConfig(asset, IRvm.CapKind.BORROW, c);
        // One buffer of LIVE_CAP: the forwarder allows +LIVE_CAP per raise.
        capsRvm.setHeadroomTarget(asset, LIVE_CAP);
    }

    function _debtToken(address asset) internal view returns (MockVariableDebtToken) {
        return MockVariableDebtToken(pool.getReserveVariableDebtToken(asset));
    }

    function _delegate(address who, address asset, uint256 amount) internal {
        MockVariableDebtToken vdt = _debtToken(asset);
        vm.prank(who);
        vdt.approveDelegation(address(fwd), amount);
    }

    function _raiseCall(address asset, uint256 amount, address to) internal pure returns (bytes memory) {
        return abi.encodeCall(ICapsBorrowForwarder.raiseCapAndBorrow, (asset, amount, to));
    }

    function _raise(address asset, uint256 amount, address to) internal {
        vm.prank(riskCouncil);
        fwd.raiseCapAndBorrow(asset, amount, to);
    }

    function _listToken(MockERC20 t) internal {
        pool.listReserve(address(t), 6, LIVE_CAP, 0);
        t.mint(address(pool), _wei(address(t), LIQUIDITY));
        _setRvmMaxCap(address(t));
    }

    function _listReentrant() internal returns (ReentrantERC20 t) {
        t = new ReentrantERC20(6);
        _listToken(t);
    }

    function _selector(bytes memory ret) internal pure returns (bytes4 sel) {
        if (ret.length < 4) return bytes4(0);
        assembly {
            sel := mload(add(ret, 32))
        }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // (4) STATEFUL INVARIANT
    // ═══════════════════════════════════════════════════════════════════════════

    ForwarderHandler internal handler;

    function _setUpInvariant() internal {
        pool.setBorrowCap(address(weth), LIVE_CAP);
        pool.setBorrowCap(address(wbtc), LIVE_CAP);
        handler = new ForwarderHandler(fwd, pool, riskCouncil, [address(weth), address(usdc), address(wbtc)]);
        // Every delegating account starts with a delegation on every asset; each raise uses it up.
        for (uint256 w = 0; w < 3; w++) {
            for (uint256 a = 0; a < 3; a++) {
                handler.delegate(w, a, type(uint256).max);
            }
        }
        targetContract(address(handler));
        bytes4[] memory sels = new bytes4[](6);
        sels[0] = ForwarderHandler.raiseAndBorrow.selector;
        sels[1] = ForwarderHandler.delegate.selector;
        sels[2] = ForwarderHandler.raiseFromStranger.selector;
        sels[3] = ForwarderHandler.callerBadTarget.selector;
        sels[4] = ForwarderHandler.donate.selector;
        sels[5] = ForwarderHandler.warp.selector;
        targetSelector(StdInvariant.FuzzSelector({ addr: address(handler), selectors: sels }));
    }
}

/// @title CapsBorrowForwarderAdversarialTest
/// @notice Adversarial tests of the forwarder borrow path.
contract CapsBorrowForwarderAdversarialTest is AdversarialBase {
    // ═══════════════════════════════════════════════════════════════════════════
    // (1) FUZZED CALLERS NEVER MOVE DEBT OR TOKENS
    // ═══════════════════════════════════════════════════════════════════════════

    /// Any caller off the allowlist, any amount, any onBehalfOf: raiseCapAndBorrow reverts and no cap, debt,
    /// allowance or token moves, even though the borrower has an unlimited delegation to the forwarder.
    function testFuzz_adv_raise_anyCaller_movesNothing(
        address caller,
        uint256 amount,
        address onBehalfOf,
        bool useBorrower
    )
        public
    {
        vm.assume(caller != riskCouncil);
        amount = bound(amount, 1, _wei(address(usdc), 50_000));
        if (useBorrower) onBehalfOf = borrower;
        _delegate(borrower, address(usdc), type(uint256).max);
        MockVariableDebtToken vdt = _debtToken(address(usdc));

        uint256 totalDebt = vdt.totalSupply();
        uint256 poolBal = usdc.balanceOf(address(pool));
        uint256 debtOf = vdt.balanceOf(onBehalfOf);
        uint256 balOf = usdc.balanceOf(onBehalfOf);

        vm.prank(caller);
        (bool ok, bytes memory ret) = address(fwd).call(_raiseCall(address(usdc), amount, onBehalfOf));
        assertFalse(ok, "non-caller must revert");
        assertEq(_selector(ret), ICapsBorrowForwarder.NotCaller.selector);

        assertEq(_liveBorrowCap(address(usdc)), LIVE_CAP, "cap unchanged");
        assertEq(vdt.totalSupply(), totalDebt, "total debt unchanged");
        assertEq(usdc.balanceOf(address(pool)), poolBal, "pool unchanged");
        assertEq(vdt.balanceOf(onBehalfOf), debtOf, "debt unchanged");
        assertEq(usdc.balanceOf(onBehalfOf), balOf, "balance unchanged");
        assertEq(vdt.borrowAllowance(borrower, address(fwd)), type(uint256).max, "allowance unused");
    }

    /// The allowlisted caller (signers misbehaving) cannot put debt on an account that did not delegate to the
    /// forwarder: any non-delegator reverts, with the cap unchanged.
    function testFuzz_adv_caller_nonDelegator_reverts(address victim, uint256 amount) public {
        vm.assume(victim != address(0) && victim != riskCouncil && victim != address(fwd));
        vm.assume(victim != address(pool));
        amount = bound(amount, 1, _wei(address(usdc), 50_000));
        vm.expectRevert(
            abi.encodeWithSelector(MockVariableDebtToken.InsufficientBorrowAllowance.selector, address(fwd), 0, amount)
        );
        _raise(address(usdc), amount, victim);
        assertEq(_debtToken(address(usdc)).balanceOf(victim), 0);
        assertEq(_liveBorrowCap(address(usdc)), LIVE_CAP);
    }

    /// The caller cannot send the tokens to itself, the forwarder or the zero address.
    function test_adv_caller_cannotBorrowToItselfOrForwarder() public {
        _delegate(borrower, address(usdc), type(uint256).max);
        address[3] memory bad = [riskCouncil, address(fwd), address(0)];
        for (uint256 i = 0; i < bad.length; i++) {
            vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
            _raise(address(usdc), 5000e6, bad[i]);
        }
        assertEq(_liveBorrowCap(address(usdc)), LIVE_CAP);
        assertEq(usdc.balanceOf(riskCouncil) + usdc.balanceOf(address(fwd)), 0);
    }

    /// The caller can borrow at most the delegated allowance, always to the borrower.
    function testFuzz_adv_caller_boundedByAllowance(uint256 allowance, uint256 amount) public {
        allowance = bound(allowance, 1, _wei(address(usdc), 50_000));
        amount = bound(amount, 1, _wei(address(usdc), 90_000));
        _delegate(borrower, address(usdc), allowance);
        vm.prank(riskCouncil);
        (bool ok,) = address(fwd).call(_raiseCall(address(usdc), amount, borrower));
        assertEq(ok, amount <= allowance, "succeeds iff within the delegation");
        uint256 borrowed = ok ? amount : 0;
        assertEq(_debtToken(address(usdc)).balanceOf(borrower), borrowed);
        assertEq(usdc.balanceOf(borrower), borrowed);
        assertEq(usdc.balanceOf(address(fwd)), 0);
        assertEq(usdc.balanceOf(riskCouncil), 0);
        assertEq(_debtToken(address(usdc)).borrowAllowance(borrower, address(fwd)), ok ? 0 : allowance);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // (2) DONATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// Observed behaviour: a donation to the forwarder before the call does NOT make the raise revert, since the
    /// balance check is relative. The borrow still sends exactly `amount` to the borrower, and the donation stays
    /// at the forwarder (there is no sweep function, so it is stuck).
    function test_adv_donationBefore_raiseCapAndBorrow_passes_donationStuck() public {
        usdc.mint(address(fwd), 123e6);
        _delegate(borrower, address(usdc), 5000e6);
        _raise(address(usdc), 5000e6, borrower);
        assertEq(usdc.balanceOf(borrower), 5000e6, "borrower gets exactly amount");
        assertEq(_debtToken(address(usdc)).balanceOf(borrower), 5000e6);
        assertEq(usdc.balanceOf(address(fwd)), 123e6, "donation stays at the forwarder");
        assertEq(usdc.balanceOf(riskCouncil), 0);
    }

    function testFuzz_adv_donationBefore_raise_passes(uint256 donation, uint256 amount) public {
        donation = bound(donation, 1, _wei(address(usdc), 1_000_000));
        amount = bound(amount, 1, _wei(address(usdc), 50_000));
        usdc.mint(address(fwd), donation);
        _delegate(borrower, address(usdc), amount);
        _raise(address(usdc), amount, borrower);
        assertEq(usdc.balanceOf(borrower), amount);
        assertEq(usdc.balanceOf(address(fwd)), donation);
    }

    /// A donation cannot be used to cover a short Pool payout: the Pool pays the forwarder half (a fee), the
    /// donation covers the transfer to the borrower, the forwarder balance drops, and the raise reverts.
    function test_adv_donationCoversShortPayout_reverts() public {
        FeeOnPoolERC20 f = new FeeOnPoolERC20(6);
        _listToken(f);
        f.setHalfFrom(address(pool));
        f.mint(address(fwd), 4000e6);
        _delegate(borrower, address(f), 5000e6);

        vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.ForwarderBalanceChanged.selector, 4000e6, 1500e6));
        _raise(address(f), 5000e6, borrower);
        assertEq(_debtToken(address(f)).balanceOf(borrower), 0);
        assertEq(_liveBorrowCap(address(f)), LIVE_CAP);
    }

    /// A donation to the forwarder in the middle of the call (during the Pool payout) reverts.
    function test_adv_donationDuringBorrow_reverts() public {
        ReentrantERC20 t = _listReentrant();
        t.arm(address(pool), address(fwd), address(t), abi.encodeCall(MockERC20.mint, (address(fwd), 1)), true);
        _delegate(borrower, address(t), 5000e6);
        vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.ForwarderBalanceChanged.selector, 0, 1));
        _raise(address(t), 5000e6, borrower);
        assertEq(_liveBorrowCap(address(t)), LIVE_CAP);
    }

    /// A hostile token pulling the donated balance out of the forwarder during the transfer reverts.
    function test_adv_tokenDrainsForwarderDuringTransfer_reverts() public {
        ReentrantERC20 t = _listReentrant();
        t.mint(address(fwd), 100e6);
        address thief = makeAddr("thief");
        t.arm(address(fwd), borrower, address(t), abi.encodeCall(ReentrantERC20.steal, (address(fwd), thief, 1)), true);
        _delegate(borrower, address(t), 5000e6);
        vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.ForwarderBalanceChanged.selector, 100e6, 100e6 - 1));
        _raise(address(t), 5000e6, borrower);
        assertEq(_liveBorrowCap(address(t)), LIVE_CAP);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // (3) RE-ENTRANCY
    // ═══════════════════════════════════════════════════════════════════════════

    /// During the Pool payout the token calls raiseCapAndBorrow directly: the reentrancy guard refuses it.
    /// Swallowed: the outer call completes with exactly one borrow. Bubbled: everything reverts, cap included.
    function test_adv_reentrant_raise_fromToken_reverts() public {
        ReentrantERC20 t = _listReentrant();
        _delegate(borrower, address(t), 10_000e6);
        t.arm(address(pool), address(fwd), address(fwd), _raiseCall(address(t), 5000e6, borrower), false);

        _raise(address(t), 5000e6, borrower);
        assertEq(t.fired(), 1);
        assertFalse(t.lastOk());
        assertEq(_selector(t.lastRet()), ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        assertEq(_debtToken(address(t)).balanceOf(borrower), 5000e6, "one borrow only");
        assertEq(t.balanceOf(borrower), 5000e6);
        assertEq(t.balanceOf(address(fwd)) + t.balanceOf(riskCouncil), 0);

        // Bubbled, from the transfer to the borrower: the whole call reverts.
        skip(1);
        uint256 cap = _liveBorrowCap(address(t));
        _delegate(borrower, address(t), 5000e6);
        t.arm(address(fwd), borrower, address(fwd), _raiseCall(address(t), 5000e6, borrower), true);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        _raise(address(t), 5000e6, borrower);
        assertEq(_liveBorrowCap(address(t)), cap);
        assertEq(_debtToken(address(t)).balanceOf(borrower), 5000e6);
    }

    /// Worst case: the re-entry comes through an allowlisted caller contract, so the allowlist check would pass.
    /// The token hook (as a borrower-side hook on receipt) calls it during the payout and during the transfer to
    /// the borrower, for a second delegating borrower: the reentrancy guard refuses both and the whole raise
    /// reverts.
    function test_adv_reentrant_viaAllowlistedCaller_reverts() public {
        CallerContract cc = new CallerContract();
        vm.prank(governance);
        fwd.setCaller(address(cc), true);

        ReentrantERC20 t = _listReentrant();
        address borrower2 = makeAddr("borrower2");
        _delegate(borrower, address(t), 5000e6);
        _delegate(borrower2, address(t), 3000e6);
        bytes memory inner =
            abi.encodeCall(CallerContract.exec, (address(fwd), _raiseCall(address(t), 3000e6, borrower2)));

        t.arm(address(pool), address(fwd), address(cc), inner, true);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        _raise(address(t), 5000e6, borrower);

        t.arm(address(fwd), borrower, address(cc), inner, true);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        _raise(address(t), 5000e6, borrower);

        assertEq(_liveBorrowCap(address(t)), LIVE_CAP);
        assertEq(_debtToken(address(t)).balanceOf(borrower), 0);
        assertEq(_debtToken(address(t)).balanceOf(borrower2), 0);
        assertEq(t.balanceOf(borrower) + t.balanceOf(borrower2), 0);
    }

    /// A re-entrant token cannot reach the admin functions either: setCaller and setLimits from the token
    /// revert OwnableUnauthorizedAccount, and swallowing the revert changes nothing.
    function test_adv_reentrant_adminCalls_refused() public {
        ReentrantERC20 t = _listReentrant();
        _delegate(borrower, address(t), 5000e6);
        t.arm(
            address(pool),
            address(fwd),
            address(fwd),
            abi.encodeCall(ICapsBorrowForwarder.setCaller, (attacker, true)),
            false
        );
        _raise(address(t), 5000e6, borrower);
        assertFalse(t.lastOk());
        assertEq(_selector(t.lastRet()), Ownable.OwnableUnauthorizedAccount.selector);
        assertFalse(fwd.isCaller(attacker));
        assertEq(t.balanceOf(borrower), 5000e6);
    }

    /// The forwarder holds the borrower's delegation only for one raise: after it, a stranger who later gets on
    /// the allowlist (or a compromised caller) finds no allowance left to use.
    function test_adv_noStandingDelegationAfterRaise() public {
        _delegate(borrower, address(usdc), type(uint256).max);
        _raise(address(usdc), 5000e6, borrower);
        assertEq(_debtToken(address(usdc)).borrowAllowance(borrower, address(fwd)), 0);

        vm.prank(governance);
        fwd.setCaller(attacker, true);
        skip(1);
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(MockVariableDebtToken.InsufficientBorrowAllowance.selector, address(fwd), 0, 1e6)
        );
        fwd.raiseCapAndBorrow(address(usdc), 1e6, borrower);
    }
}

/// @title CapsBorrowForwarderAdversarialInvariantTest
/// @notice Stateful invariant: after any mix of handler calls the forwarder and the caller hold only donations,
///         carry no debt, and only delegating borrowers carry debt, each holding exactly the tokens it borrowed.
contract CapsBorrowForwarderAdversarialInvariantTest is AdversarialBase {
    function setUp() public override {
        super.setUp();
        _setUpInvariant();
    }

    /// forge-config: default.invariant.runs = 64
    /// forge-config: default.invariant.depth = 60
    function invariant_adv_tokensOnlyToDelegatingBorrowers() public view {
        handler.checkAll();
    }

    /// The handler's success path is live: a delegation and a raise succeed and are recorded, a raise for a
    /// non-delegator reverts and is not, so the invariant is not vacuous.
    function test_adv_handler_successPathsLive() public {
        handler.delegate(0, 1, 10_000e6);
        handler.raiseAndBorrow(1, 0, 5000e6);
        handler.raiseAndBorrow(1, 3, 1000e6); // non-delegator: reverts, not recorded
        assertEq(handler.successes(), 1);
        handler.checkAll();
    }

    /// Runs the handler as a plain fuzz sequence too, so the invariant setup is exercised by forge test.
    function testFuzz_adv_sequence(uint256[24] memory ops) public {
        for (uint256 i = 0; i < ops.length; i++) {
            uint256 op = ops[i] % 6;
            uint256 r = uint256(keccak256(abi.encode(ops[i], i)));
            if (op == 0) handler.raiseAndBorrow(r, r >> 8, r >> 16);
            else if (op == 1) handler.delegate(r, r >> 8, r >> 16);
            else if (op == 2) handler.raiseFromStranger(address(uint160(r >> 64)), r, r >> 8, r >> 16);
            else if (op == 3) handler.callerBadTarget(r, r >> 8, r >> 16);
            else if (op == 4) handler.donate(r, r >> 8, r >> 16);
            else handler.warp(r);
        }
        handler.checkAll();
    }
}

/// @title ForwarderHandler
/// @notice Drives a mix of forwarder calls: allowlisted raise and borrow, fresh delegations, stranger calls,
///         caller calls to bad borrowers, donations and time moves. Accounts 0-2 delegate credit to the
///         forwarder; accounts 3-4 never do.
contract ForwarderHandler is Test {
    CapsBorrowForwarder internal fwd;
    MockPoolV3 internal pool;
    address internal caller;
    address[3] internal assets;
    address[5] internal accts;

    mapping(address asset => uint256) public ghostBorrowed;
    mapping(address who => mapping(address asset => uint256)) public ghostBorrowedBy;
    mapping(address who => mapping(address asset => uint256)) public ghostAllowance;
    mapping(address asset => uint256) public ghostDonatedFwd;
    mapping(address asset => uint256) public ghostDonatedCaller;
    mapping(address asset => uint256) public poolStart;
    bool public badSucceeded;
    uint256 public successes;

    constructor(CapsBorrowForwarder fwd_, MockPoolV3 pool_, address caller_, address[3] memory assets_) {
        fwd = fwd_;
        pool = pool_;
        caller = caller_;
        assets = assets_;
        accts = [
            makeAddr("delegator0"),
            makeAddr("delegator1"),
            makeAddr("delegator2"),
            makeAddr("nonDelegator0"),
            makeAddr("nonDelegator1")
        ];
        for (uint256 i = 0; i < 3; i++) {
            poolStart[assets[i]] = IERC20(assets[i]).balanceOf(address(pool));
        }
    }

    function _unit(address asset) internal view returns (uint256) {
        return 10 ** MockERC20(asset).decimals();
    }

    function _vdt(address asset) internal view returns (MockVariableDebtToken) {
        return MockVariableDebtToken(pool.getReserveVariableDebtToken(asset));
    }

    /// A delegating account (0-2) approves a fresh delegation to the forwarder.
    function delegate(uint256 w, uint256 a, uint256 amount) external {
        address asset = assets[a % 3];
        address who = accts[w % 3];
        amount = bound(amount, 0, 10_000 * _unit(asset));
        MockVariableDebtToken vdt = _vdt(asset);
        vm.prank(who);
        vdt.approveDelegation(address(fwd), amount);
        ghostAllowance[who][asset] = amount;
    }

    function raiseAndBorrow(uint256 a, uint256 w, uint256 amount) external {
        address asset = assets[a % 3];
        address who = accts[w % 5];
        amount = bound(amount, 1, 5000 * _unit(asset));
        vm.prank(caller);
        try fwd.raiseCapAndBorrow(asset, amount, who) {
            ghostBorrowed[asset] += amount;
            ghostBorrowedBy[who][asset] += amount;
            ghostAllowance[who][asset] = 0; // the rest is renounced
            successes++;
        } catch { }
    }

    function raiseFromStranger(address stranger, uint256 a, uint256 w, uint256 amount) external {
        if (stranger == caller) stranger = address(this);
        address asset = assets[a % 3];
        address who = accts[w % 5];
        amount = bound(amount, 1, 5000 * _unit(asset));
        vm.prank(stranger);
        try fwd.raiseCapAndBorrow(asset, amount, who) {
            badSucceeded = true;
        } catch { }
    }

    /// The caller tries to borrow to itself, the forwarder or address(0).
    function callerBadTarget(uint256 a, uint256 k, uint256 amount) external {
        address asset = assets[a % 3];
        address[3] memory bad = [caller, address(fwd), address(0)];
        address to = bad[k % 3];
        amount = bound(amount, 1, 5000 * _unit(asset));
        vm.prank(caller);
        try fwd.raiseCapAndBorrow(asset, amount, to) {
            badSucceeded = true;
        } catch { }
    }

    function donate(uint256 a, uint256 toCaller, uint256 amount) external {
        address asset = assets[a % 3];
        amount = bound(amount, 1, 1000 * _unit(asset));
        if (toCaller % 2 == 0) {
            MockERC20(asset).mint(caller, amount);
            ghostDonatedCaller[asset] += amount;
        } else {
            MockERC20(asset).mint(address(fwd), amount);
            ghostDonatedFwd[asset] += amount;
        }
    }

    function warp(uint256 dt) external {
        vm.warp(block.timestamp + bound(dt, 0, 7 days));
    }

    function checkAll() external view {
        require(!badSucceeded, "a call that must revert succeeded");
        for (uint256 i = 0; i < 3; i++) {
            address asset = assets[i];
            MockVariableDebtToken vdt = _vdt(asset);
            require(IERC20(asset).balanceOf(address(fwd)) == ghostDonatedFwd[asset], "forwarder holds borrowed tokens");
            require(IERC20(asset).balanceOf(caller) == ghostDonatedCaller[asset], "caller holds borrowed tokens");
            require(vdt.balanceOf(address(fwd)) == 0, "forwarder carries debt");
            require(vdt.balanceOf(caller) == 0, "caller carries debt");
            require(
                poolStart[asset] - IERC20(asset).balanceOf(address(pool)) == ghostBorrowed[asset],
                "pool payout != borrowed"
            );
            for (uint256 j = 0; j < 5; j++) {
                address who = accts[j];
                uint256 debt = vdt.balanceOf(who);
                require(debt == ghostBorrowedBy[who][asset], "debt != recorded borrows");
                require(IERC20(asset).balanceOf(who) == debt, "borrower tokens != debt");
                require(vdt.borrowAllowance(who, address(fwd)) == ghostAllowance[who][asset], "allowance drift");
                if (j >= 3) require(debt == 0, "non-delegator carries debt");
            }
        }
    }
}

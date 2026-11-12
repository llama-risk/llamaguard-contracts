// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { CapsTestBase } from "./CapsTestBase.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockSafe } from "./mocks/MockSafe.sol";
import { MockPoolV3, MockVariableDebtToken } from "./mocks/MockPoolV3.sol";
import { MockRiskSteward } from "./mocks/MockRiskSteward.sol";
import { MockCapsRvm } from "./mocks/MockCapsRvm.sol";
import { CapsBorrowForwarder } from "../../src/caps-oracle/CapsBorrowForwarder.sol";
import { ICapsBorrowForwarder } from "../../src/caps-oracle/interfaces/ICapsBorrowForwarder.sol";

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

/// @title CapsBorrowForwarderAdversarialTest
/// @notice Adversarial tests of the forwarder borrow path: fuzzed callers, donations, re-entrant tokens and
///         misbehaving Safe calls. Goal under test: borrowed tokens only ever reach the borrower that carries
///         the debt, and only a borrower that delegated credit to the forwarder carries debt.
abstract contract AdversarialBase is CapsTestBase {
    CapsBorrowForwarder internal fwd;
    MockSafe internal safe;
    MockCapsRvm internal capsRvm;

    uint256 internal constant LIVE_CAP = 1_000_000;
    uint256 internal constant LIVE_DEBT = 900_000;
    uint256 internal constant LIQUIDITY = 100_000_000;

    function setUp() public virtual override {
        super.setUp();
        vm.warp(1_700_000_000);
        _etchSafeAtRiskCouncil();
        safe = MockSafe(riskCouncil);
        capsRvm = new MockCapsRvm();
        capsRvm.setPool(address(pool));
        fwd = new CapsBorrowForwarder(address(pool), address(steward), riskCouncil, address(capsRvm));

        usdc.mint(address(pool), _wei(address(usdc), LIQUIDITY));
        weth.mint(address(pool), _wei(address(weth), LIQUIDITY));
        wbtc.mint(address(pool), _wei(address(wbtc), LIQUIDITY));

        pool.setBorrowCap(address(usdc), LIVE_CAP);
        _setDebt(address(usdc), LIVE_DEBT, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════════════════════════════

    function _debtToken(address asset) internal view returns (MockVariableDebtToken) {
        return MockVariableDebtToken(pool.getReserveVariableDebtToken(asset));
    }

    function _delegate(address who, address asset, uint256 amount) internal {
        MockVariableDebtToken vdt = _debtToken(asset);
        vm.prank(who);
        vdt.approveDelegation(address(fwd), amount);
    }

    function _raiseCall(address asset, uint256 amount, address to) internal pure returns (bytes memory) {
        return abi.encodeCall(ICapsBorrowForwarder.raiseCapAndBorrow, (asset, amount, to, 10, type(uint256).max));
    }

    function _borrowForCall(address asset, uint256 amount, address to) internal pure returns (bytes memory) {
        return abi.encodeCall(ICapsBorrowForwarder.borrowFor, (asset, amount, to));
    }

    function _listReentrant() internal returns (ReentrantERC20 t) {
        t = new ReentrantERC20(6);
        pool.listReserve(address(t), 6, LIVE_CAP, 0);
        t.mint(address(pool), _wei(address(t), LIQUIDITY));
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
        handler = new ForwarderHandler(fwd, safe, pool, [address(weth), address(usdc), address(wbtc)]);
        address[5] memory accts = handler.accounts();
        MockERC20[3] memory assets = [weth, usdc, wbtc];
        for (uint256 i = 0; i < 3; i++) {
            for (uint256 j = 0; j < 3; j++) {
                _delegate(accts[i], address(assets[j]), handler.ALLOWANCE(address(assets[j])));
            }
        }
        targetContract(address(handler));
        bytes4[] memory sels = new bytes4[](7);
        sels[0] = ForwarderHandler.raiseAndBorrow.selector;
        sels[1] = ForwarderHandler.borrowForFromSafe.selector;
        sels[2] = ForwarderHandler.borrowForFromStranger.selector;
        sels[3] = ForwarderHandler.raiseDirect.selector;
        sels[4] = ForwarderHandler.safeBadTarget.selector;
        sels[5] = ForwarderHandler.donate.selector;
        sels[6] = ForwarderHandler.borrowForDelegatecall.selector;
        targetSelector(StdInvariant.FuzzSelector({ addr: address(handler), selectors: sels }));
    }
}

/// @title CapsBorrowForwarderAdversarialTest
/// @notice Adversarial tests of the forwarder borrow path.
contract CapsBorrowForwarderAdversarialTest is AdversarialBase {
    // ═══════════════════════════════════════════════════════════════════════════
    // (1) FUZZED CALLERS NEVER MOVE DEBT OR TOKENS
    // ═══════════════════════════════════════════════════════════════════════════

    /// Any caller other than the Risk Council Safe, any amount, any onBehalfOf: borrowFor reverts and no debt,
    /// allowance or token moves, even though the borrower has an unlimited delegation to the forwarder.
    function testFuzz_adv_borrowFor_anyCaller_movesNothing(
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
        (bool ok,) = address(fwd).call(_borrowForCall(address(usdc), amount, onBehalfOf));
        assertFalse(ok, "non-council caller must revert");

        assertEq(vdt.totalSupply(), totalDebt, "total debt unchanged");
        assertEq(usdc.balanceOf(address(pool)), poolBal, "pool unchanged");
        assertEq(vdt.balanceOf(onBehalfOf), debtOf, "debt unchanged");
        assertEq(usdc.balanceOf(onBehalfOf), balOf, "balance unchanged");
        assertEq(vdt.borrowAllowance(borrower, address(fwd)), type(uint256).max, "allowance unused");
    }

    /// Any direct caller of raiseCapAndBorrow (including the Safe address, by plain call): reverts, no cap,
    /// debt or token change.
    function testFuzz_adv_raiseCapAndBorrow_directCall_movesNothing(address caller, uint256 amount) public {
        amount = bound(amount, 1, _wei(address(usdc), 5000));
        _delegate(borrower, address(usdc), type(uint256).max);
        vm.prank(caller);
        (bool ok,) = address(fwd).call(_raiseCall(address(usdc), amount, borrower));
        assertFalse(ok);
        assertEq(_liveBorrowCap(address(usdc)), LIVE_CAP);
        assertEq(_debtToken(address(usdc)).balanceOf(borrower), 0);
        assertEq(usdc.balanceOf(borrower), 0);
    }

    /// The Safe itself (signers misbehaving) cannot put debt on an account that did not delegate to the
    /// forwarder: borrowFor for any non-delegator reverts.
    function testFuzz_adv_safe_borrowFor_nonDelegator_reverts(address victim, uint256 amount) public {
        vm.assume(victim != address(0) && victim != riskCouncil && victim != address(fwd));
        vm.assume(victim != address(pool));
        amount = bound(amount, 1, _wei(address(usdc), 50_000));
        vm.expectRevert(
            abi.encodeWithSelector(MockVariableDebtToken.InsufficientBorrowAllowance.selector, address(fwd), 0, amount)
        );
        safe.execCall(address(fwd), _borrowForCall(address(usdc), amount, victim));
        assertEq(_debtToken(address(usdc)).balanceOf(victim), 0);
    }

    /// A delegation to the Safe (the old flow) gives the Safe nothing through the forwarder, and a direct
    /// Pool.borrow by the Safe under its own old delegation is the only way to reach tokens: out of the
    /// forwarder's scope. Here: the Safe cannot route its own delegation through borrowFor.
    function test_adv_safe_cannotBorrowToItselfOrForwarder() public {
        _delegate(borrower, address(usdc), type(uint256).max);
        address[3] memory bad = [riskCouncil, address(fwd), address(0)];
        for (uint256 i = 0; i < bad.length; i++) {
            vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
            safe.execCall(address(fwd), _borrowForCall(address(usdc), 5000e6, bad[i]));
        }
        // raiseCapAndBorrow with onBehalfOf = forwarder passes the Safe-side check, then borrowFor refuses it,
        // so the cap raise rolls back.
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        safe.execDelegatecall(address(fwd), _raiseCall(address(usdc), 5000e6, address(fwd)));
        assertEq(_liveBorrowCap(address(usdc)), LIVE_CAP, "cap raise rolled back");
        assertEq(usdc.balanceOf(riskCouncil) + usdc.balanceOf(address(fwd)), 0);
    }

    /// The Safe can borrow at most the delegated allowance, always to the borrower.
    function testFuzz_adv_safe_borrowFor_boundedByAllowance(uint256 allowance, uint256 amount) public {
        allowance = bound(allowance, 1, _wei(address(usdc), 50_000));
        amount = bound(amount, 1, _wei(address(usdc), 90_000));
        _delegate(borrower, address(usdc), allowance);
        (bool ok,) = address(safe)
            .call(abi.encodeCall(MockSafe.execCall, (address(fwd), _borrowForCall(address(usdc), amount, borrower))));
        assertEq(ok, amount <= allowance, "succeeds iff within the delegation");
        uint256 borrowed = ok ? amount : 0;
        assertEq(_debtToken(address(usdc)).balanceOf(borrower), borrowed);
        assertEq(usdc.balanceOf(borrower), borrowed);
        assertEq(usdc.balanceOf(address(fwd)), 0);
        assertEq(usdc.balanceOf(riskCouncil), 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // (2) DONATIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// Observed behaviour: a donation to the forwarder before the call does NOT make borrowFor revert, since the
    /// balance check is relative. The borrow still sends exactly `amount` to the borrower, and the donation stays
    /// at the forwarder (there is no sweep function, so it is stuck).
    function test_adv_donationBefore_raiseCapAndBorrow_passes_donationStuck() public {
        usdc.mint(address(fwd), 123e6);
        _delegate(borrower, address(usdc), 5000e6);
        safe.execDelegatecall(address(fwd), _raiseCall(address(usdc), 5000e6, borrower));
        assertEq(usdc.balanceOf(borrower), 5000e6, "borrower gets exactly amount");
        assertEq(_debtToken(address(usdc)).balanceOf(borrower), 5000e6);
        assertEq(usdc.balanceOf(address(fwd)), 123e6, "donation stays at the forwarder");
        assertEq(usdc.balanceOf(riskCouncil), 0);
    }

    function testFuzz_adv_donationBefore_borrowFor_passes(uint256 donation, uint256 amount) public {
        donation = bound(donation, 1, _wei(address(usdc), 1_000_000));
        amount = bound(amount, 1, _wei(address(usdc), 50_000));
        usdc.mint(address(fwd), donation);
        _delegate(borrower, address(usdc), amount);
        safe.execCall(address(fwd), _borrowForCall(address(usdc), amount, borrower));
        assertEq(usdc.balanceOf(borrower), amount);
        assertEq(usdc.balanceOf(address(fwd)), donation);
    }

    /// A donation cannot be used to cover a short Pool payout: the Pool pays the forwarder half (a fee), the
    /// donation covers the transfer to the borrower, the forwarder balance drops, and borrowFor reverts.
    function test_adv_donationCoversShortPayout_reverts() public {
        FeeOnPoolERC20 f = new FeeOnPoolERC20(6);
        pool.listReserve(address(f), 6, LIVE_CAP, 0);
        f.mint(address(pool), _wei(address(f), LIQUIDITY));
        f.setHalfFrom(address(pool));
        f.mint(address(fwd), 4000e6);
        _delegate(borrower, address(f), 5000e6);

        vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.ForwarderBalanceChanged.selector, 4000e6, 1500e6));
        safe.execCall(address(fwd), _borrowForCall(address(f), 5000e6, borrower));
        assertEq(_debtToken(address(f)).balanceOf(borrower), 0);
    }

    /// A donation to the forwarder in the middle of the call (during the Pool payout) reverts.
    function test_adv_donationDuringBorrow_reverts() public {
        ReentrantERC20 t = _listReentrant();
        t.arm(address(pool), address(fwd), address(t), abi.encodeCall(MockERC20.mint, (address(fwd), 1)), true);
        _delegate(borrower, address(t), 5000e6);
        vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.ForwarderBalanceChanged.selector, 0, 1));
        safe.execDelegatecall(address(fwd), _raiseCall(address(t), 5000e6, borrower));
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
        safe.execCall(address(fwd), _borrowForCall(address(t), 5000e6, borrower));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // (3) RE-ENTRANT TOKEN
    // ═══════════════════════════════════════════════════════════════════════════

    /// During the Pool payout the token calls borrowFor directly: msg.sender is the token, so NotRiskCouncil.
    /// Swallowed: the outer call completes with exactly one borrow. Bubbled: everything reverts.
    function test_adv_reentrant_borrowFor_fromToken_reverts() public {
        ReentrantERC20 t = _listReentrant();
        _delegate(borrower, address(t), 10_000e6);
        t.arm(address(pool), address(fwd), address(fwd), _borrowForCall(address(t), 5000e6, borrower), false);

        safe.execDelegatecall(address(fwd), _raiseCall(address(t), 5000e6, borrower));
        assertEq(t.fired(), 1);
        assertFalse(t.lastOk());
        assertEq(_selector(t.lastRet()), ICapsBorrowForwarder.NotRiskCouncil.selector);
        assertEq(_debtToken(address(t)).balanceOf(borrower), 5000e6, "one borrow only");
        assertEq(t.balanceOf(borrower), 5000e6);
        assertEq(t.balanceOf(address(fwd)) + t.balanceOf(riskCouncil), 0);

        // Bubbled: the whole Safe call reverts, cap included.
        vm.warp(block.timestamp + 36 hours);
        uint256 cap = _liveBorrowCap(address(t));
        t.arm(address(fwd), borrower, address(fwd), _borrowForCall(address(t), 5000e6, borrower), true);
        vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.NotRiskCouncil.selector, address(t)));
        safe.execDelegatecall(address(fwd), _raiseCall(address(t), 5000e6, borrower));
        assertEq(_liveBorrowCap(address(t)), cap);
        assertEq(_debtToken(address(t)).balanceOf(borrower), 5000e6);
    }

    /// During the transfer the token (or a hook in the borrower) calls raiseCapAndBorrow on the forwarder:
    /// NotRiskCouncilContext.
    function test_adv_reentrant_raiseCapAndBorrow_fromToken_reverts() public {
        ReentrantERC20 t = _listReentrant();
        _delegate(borrower, address(t), 10_000e6);
        t.arm(address(fwd), borrower, address(fwd), _raiseCall(address(t), 5000e6, borrower), false);

        safe.execCall(address(fwd), _borrowForCall(address(t), 5000e6, borrower));
        assertFalse(t.lastOk());
        assertEq(_selector(t.lastRet()), ICapsBorrowForwarder.NotRiskCouncilContext.selector);
        assertEq(_debtToken(address(t)).balanceOf(borrower), 5000e6);
        assertEq(_liveBorrowCap(address(t)), LIVE_CAP);
    }

    /// Worst case: the re-entry comes from the Safe itself (MockSafe has no signature check, so this models a
    /// nested Safe transaction). A nested borrowFor during the Pool payout, for a second delegating borrower:
    /// both borrows succeed, each borrower gets exactly its amount, the forwarder and the Safe keep nothing.
    function test_adv_reentrant_nestedSafeBorrowFor_tokensStillOnlyToBorrowers() public {
        ReentrantERC20 t = _listReentrant();
        address borrower2 = makeAddr("borrower2");
        _delegate(borrower, address(t), 5000e6);
        _delegate(borrower2, address(t), 3000e6);
        t.arm(
            address(pool),
            address(fwd),
            address(safe),
            abi.encodeCall(MockSafe.execCall, (address(fwd), _borrowForCall(address(t), 3000e6, borrower2))),
            true
        );

        safe.execDelegatecall(address(fwd), _raiseCall(address(t), 5000e6, borrower));
        assertTrue(t.lastOk());
        assertEq(t.balanceOf(borrower), 5000e6);
        assertEq(t.balanceOf(borrower2), 3000e6);
        assertEq(_debtToken(address(t)).balanceOf(borrower), 5000e6);
        assertEq(_debtToken(address(t)).balanceOf(borrower2), 3000e6);
        assertEq(t.balanceOf(address(fwd)), 0);
        assertEq(t.balanceOf(riskCouncil), 0);
    }

    /// Nested raiseCapAndBorrow by delegatecall during the transfer to the borrower (Steward delay 0 so the
    /// inner raise is allowed): both complete, all tokens at the borrower.
    function test_adv_reentrant_nestedSafeRaise_tokensStillOnlyToBorrower() public {
        ReentrantERC20 t = _listReentrant();
        steward.setLimits(0, 10_000);
        _delegate(borrower, address(t), 8000e6);
        t.arm(
            address(fwd),
            borrower,
            address(safe),
            abi.encodeCall(MockSafe.execDelegatecall, (address(fwd), _raiseCall(address(t), 3000e6, borrower))),
            true
        );

        safe.execDelegatecall(address(fwd), _raiseCall(address(t), 5000e6, borrower));
        assertTrue(t.lastOk());
        assertEq(t.balanceOf(borrower), 8000e6);
        assertEq(_debtToken(address(t)).balanceOf(borrower), 8000e6);
        assertEq(t.balanceOf(address(fwd)) + t.balanceOf(riskCouncil), 0);
        assertEq(_debtToken(address(t)).borrowAllowance(borrower, address(fwd)), 0);
    }

    /// Nested borrowFor that tries to send the tokens to the Safe or the forwarder: InvalidInput, bubbled.
    function test_adv_reentrant_nestedSafeBorrowFor_toSafe_reverts() public {
        ReentrantERC20 t = _listReentrant();
        _delegate(borrower, address(t), 5000e6);
        t.arm(
            address(pool),
            address(fwd),
            address(safe),
            abi.encodeCall(MockSafe.execCall, (address(fwd), _borrowForCall(address(t), 1000e6, riskCouncil))),
            true
        );
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        safe.execDelegatecall(address(fwd), _raiseCall(address(t), 5000e6, borrower));
        assertEq(_debtToken(address(t)).balanceOf(borrower), 0);
    }
}

/// @title CapsBorrowForwarderAdversarialInvariantTest
/// @notice Stateful invariant: after any mix of handler calls the forwarder and the Safe hold only donations,
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

    /// The handler's success paths are live: a Safe raise and borrow and a Safe borrowFor for a delegator both
    /// succeed and are recorded, so the invariant is not vacuous.
    function test_adv_handler_successPathsLive() public {
        handler.raiseAndBorrow(1, 0, 5000e6, 10);
        handler.borrowForFromSafe(1, 1, 1000e6);
        handler.borrowForFromSafe(1, 3, 1000e6); // non-delegator: reverts, not recorded
        assertEq(handler.successes(), 2);
        handler.checkAll();
    }

    /// The invariant runner also counts successes across a run: at least one borrow lands.
    function afterInvariant() public view {
        require(handler.successes() > 0, "no borrow succeeded in the run");
    }

    /// Runs the handler as a plain fuzz sequence too, so the invariant setup is exercised by forge test.
    function testFuzz_adv_sequence(uint256[24] memory ops) public {
        for (uint256 i = 0; i < ops.length; i++) {
            uint256 op = ops[i] % 7;
            uint256 r = uint256(keccak256(abi.encode(ops[i], i)));
            if (op == 0) handler.raiseAndBorrow(r, r >> 8, r >> 16, r >> 32);
            else if (op == 1) handler.borrowForFromSafe(r, r >> 8, r >> 16);
            else if (op == 2) handler.borrowForFromStranger(address(uint160(r >> 64)), r, r >> 8, r >> 16);
            else if (op == 3) handler.raiseDirect(address(uint160(r >> 64)), r, r >> 8, r >> 16);
            else if (op == 4) handler.safeBadTarget(r, r >> 8, r >> 16);
            else if (op == 5) handler.donate(r, r >> 8, r >> 16);
            else handler.borrowForDelegatecall(r, r >> 8, r >> 16);
        }
        handler.checkAll();
    }
}

/// @title ForwarderHandler
/// @notice Drives a mix of forwarder calls: Safe raise and borrow, Safe borrowFor, stranger calls, Safe calls to
///         bad targets, donations and delegatecalls of borrowFor. Accounts 0-2 delegate credit to the forwarder;
///         accounts 3-4 never do.
contract ForwarderHandler is Test {
    CapsBorrowForwarder internal fwd;
    MockSafe internal safe;
    MockPoolV3 internal pool;
    address[3] internal assets;
    address[5] internal accts;

    mapping(address asset => uint256) public ghostBorrowed;
    mapping(address who => mapping(address asset => uint256)) public ghostBorrowedBy;
    mapping(address asset => uint256) public ghostDonatedFwd;
    mapping(address asset => uint256) public ghostDonatedSafe;
    mapping(address asset => uint256) public poolStart;
    bool public badSucceeded;
    uint256 public successes;

    constructor(CapsBorrowForwarder fwd_, MockSafe safe_, MockPoolV3 pool_, address[3] memory assets_) {
        fwd = fwd_;
        safe = safe_;
        pool = pool_;
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

    function accounts() external view returns (address[5] memory) {
        return accts;
    }

    function ALLOWANCE(address asset) public view returns (uint256) {
        return 200_000 * 10 ** MockERC20(asset).decimals();
    }

    function _unit(address asset) internal view returns (uint256) {
        return 10 ** MockERC20(asset).decimals();
    }

    function raiseAndBorrow(uint256 a, uint256 w, uint256 amount, uint256 extra) external {
        address asset = assets[a % 3];
        address who = accts[w % 5];
        amount = bound(amount, 1, 5000 * _unit(asset));
        extra = bound(extra, 0, 10);
        vm.warp(block.timestamp + 36 hours);
        try safe.execDelegatecall(
            address(fwd),
            abi.encodeCall(ICapsBorrowForwarder.raiseCapAndBorrow, (asset, amount, who, extra, type(uint256).max))
        ) {
            _record(asset, who, amount);
        } catch { }
    }

    function borrowForFromSafe(uint256 a, uint256 w, uint256 amount) external {
        address asset = assets[a % 3];
        address who = accts[w % 5];
        amount = bound(amount, 1, 5000 * _unit(asset));
        try safe.execCall(address(fwd), abi.encodeCall(ICapsBorrowForwarder.borrowFor, (asset, amount, who))) {
            _record(asset, who, amount);
        } catch { }
    }

    function borrowForFromStranger(address caller, uint256 a, uint256 w, uint256 amount) external {
        if (caller == address(safe)) caller = address(this);
        address asset = assets[a % 3];
        address who = accts[w % 5];
        amount = bound(amount, 1, 5000 * _unit(asset));
        vm.prank(caller);
        try fwd.borrowFor(asset, amount, who) {
            badSucceeded = true;
        } catch { }
    }

    function raiseDirect(address caller, uint256 a, uint256 w, uint256 amount) external {
        address asset = assets[a % 3];
        address who = accts[w % 5];
        amount = bound(amount, 1, 5000 * _unit(asset));
        vm.prank(caller);
        try fwd.raiseCapAndBorrow(asset, amount, who, 10, type(uint256).max) {
            badSucceeded = true;
        } catch { }
    }

    /// The Safe tries to borrow to itself, the forwarder or address(0), by either entry point.
    function safeBadTarget(uint256 a, uint256 k, uint256 amount) external {
        address asset = assets[a % 3];
        address[3] memory bad = [address(safe), address(fwd), address(0)];
        address to = bad[k % 3];
        amount = bound(amount, 1, 5000 * _unit(asset));
        try safe.execCall(address(fwd), abi.encodeCall(ICapsBorrowForwarder.borrowFor, (asset, amount, to))) {
            badSucceeded = true;
        } catch { }
        vm.warp(block.timestamp + 36 hours);
        try safe.execDelegatecall(
            address(fwd),
            abi.encodeCall(ICapsBorrowForwarder.raiseCapAndBorrow, (asset, amount, to, 10, type(uint256).max))
        ) {
            badSucceeded = true;
        } catch { }
    }

    function borrowForDelegatecall(uint256 a, uint256 w, uint256 amount) external {
        address asset = assets[a % 3];
        address who = accts[w % 5];
        amount = bound(amount, 1, 5000 * _unit(asset));
        try safe.execDelegatecall(address(fwd), abi.encodeCall(ICapsBorrowForwarder.borrowFor, (asset, amount, who))) {
            badSucceeded = true;
        } catch { }
    }

    function donate(uint256 a, uint256 toSafe, uint256 amount) external {
        address asset = assets[a % 3];
        amount = bound(amount, 1, 1000 * _unit(asset));
        if (toSafe % 2 == 0) {
            MockERC20(asset).mint(address(safe), amount);
            ghostDonatedSafe[asset] += amount;
        } else {
            MockERC20(asset).mint(address(fwd), amount);
            ghostDonatedFwd[asset] += amount;
        }
    }

    function _record(address asset, address who, uint256 amount) internal {
        ghostBorrowed[asset] += amount;
        ghostBorrowedBy[who][asset] += amount;
        successes++;
    }

    function checkAll() external view {
        require(!badSucceeded, "a call that must revert succeeded");
        for (uint256 i = 0; i < 3; i++) {
            address asset = assets[i];
            MockVariableDebtToken vdt = MockVariableDebtToken(pool.getReserveVariableDebtToken(asset));
            require(IERC20(asset).balanceOf(address(fwd)) == ghostDonatedFwd[asset], "forwarder holds borrowed tokens");
            require(IERC20(asset).balanceOf(address(safe)) == ghostDonatedSafe[asset], "safe holds borrowed tokens");
            require(vdt.balanceOf(address(fwd)) == 0, "forwarder carries debt");
            require(vdt.balanceOf(address(safe)) == 0, "safe carries debt");
            require(
                poolStart[asset] - IERC20(asset).balanceOf(address(pool)) == ghostBorrowed[asset],
                "pool payout != borrowed"
            );
            for (uint256 j = 0; j < 5; j++) {
                address who = accts[j];
                uint256 debt = vdt.balanceOf(who);
                require(debt == ghostBorrowedBy[who][asset], "debt != recorded borrows");
                require(IERC20(asset).balanceOf(who) == debt, "borrower tokens != debt");
                if (j >= 3) require(debt == 0, "non-delegator carries debt");
                else require(vdt.borrowAllowance(who, address(fwd)) + debt == ALLOWANCE(asset), "allowance drift");
            }
        }
    }
}

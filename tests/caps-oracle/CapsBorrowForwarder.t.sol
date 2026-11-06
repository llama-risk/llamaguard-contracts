// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Vm as VmFull, VmSafe as Vm } from "forge-std/Vm.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    IAaveV3ConfigEngine as IEngine
} from "aave-v3-origin/src/contracts/extensions/v3-config-engine/IAaveV3ConfigEngine.sol";
import { EngineFlags } from "aave-v3-origin/src/contracts/extensions/v3-config-engine/EngineFlags.sol";
import { CapsTestBase } from "./CapsTestBase.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockSafe } from "./mocks/MockSafe.sol";
import { MockPoolV3, MockVariableDebtToken } from "./mocks/MockPoolV3.sol";
import { MockRiskSteward } from "./mocks/MockRiskSteward.sol";
import { CapsBorrowForwarder } from "../../src/caps-oracle/CapsBorrowForwarder.sol";
import { ICapsBorrowForwarder } from "../../src/caps-oracle/interfaces/ICapsBorrowForwarder.sol";

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
/// @notice Unit tests of CapsBorrowForwarder against MockPoolV3, MockRiskSteward and MockSafe at the Risk Council
///         address. Covers CAP-ST-26, CAP-ST-27, CAP-ST-29, CAP-ST-30, CAP-ST-31, CAP-ACL-12, CAP-ACL-13,
///         CAP-ACL-16 and CAP-UNIT-13. The fork versions of the (fork) entries run
///         against the real Pool and Risk Steward elsewhere.
contract CapsBorrowForwarderTest is CapsTestBase {
    CapsBorrowForwarder internal fwd;
    MockSafe internal safe;

    uint256 internal constant LIVE_CAP = 1_000_000; // whole USDC
    uint256 internal constant LIVE_DEBT = 900_000; // whole USDC
    uint256 internal constant LIQUIDITY = 100_000_000; // whole tokens per asset in the pool

    function setUp() public override {
        super.setUp();
        // The Steward debounce compares against lastUpdated = 0, so start well past 36 h.
        vm.warp(1_700_000_000);
        _etchSafeAtRiskCouncil();
        safe = MockSafe(riskCouncil);
        fwd = new CapsBorrowForwarder(address(pool), address(steward), riskCouncil);

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

    function _delegate(address asset, uint256 amount) internal {
        MockVariableDebtToken vdt = _debtToken(asset);
        vm.prank(borrower);
        vdt.approveDelegation(riskCouncil, amount);
    }

    function _call(
        address asset,
        uint256 amount,
        address to,
        uint256 extraCapTokens,
        uint256 maxNewCap
    )
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeCall(ICapsBorrowForwarder.raiseCapAndBorrow, (asset, amount, to, extraCapTokens, maxNewCap));
    }

    function _run(address asset, uint256 amount, uint256 extraCapTokens, uint256 maxNewCap) internal {
        safe.execDelegatecall(address(fwd), _call(asset, amount, borrower, extraCapTokens, maxNewCap));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR AND IMMUTABLES
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CapsBorrowForwarder_immutables() public view {
        assertEq(fwd.POOL(), address(pool));
        assertEq(fwd.RISK_STEWARD(), address(steward));
        assertEq(fwd.RISK_COUNCIL(), riskCouncil);
    }

    function test_CapsBorrowForwarder_constructor_zeroAddress_reverts() public {
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        new CapsBorrowForwarder(address(0), address(steward), riskCouncil);
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        new CapsBorrowForwarder(address(pool), address(0), riskCouncil);
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        new CapsBorrowForwarder(address(pool), address(steward), address(0));
    }

    /// A Steward on another Pool, or with another Risk Council, is refused at deploy: the forwarder would
    /// otherwise raise the cap on one Pool and borrow on another.
    function test_CapsBorrowForwarder_constructor_stewardMismatch_reverts() public {
        MockPoolV3 otherPool = new MockPoolV3();
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        new CapsBorrowForwarder(address(otherPool), address(steward), riskCouncil);

        MockRiskSteward otherCouncil = new MockRiskSteward(makeAddr("otherCouncil"), pool);
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        new CapsBorrowForwarder(address(pool), address(otherCouncil), riskCouncil);
    }

    function test_CapsBorrowForwarder_invalidInput_reverts() public {
        _delegate(address(usdc), type(uint256).max);
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        safe.execDelegatecall(address(fwd), _call(address(usdc), 0, borrower, 10, 2_000_000));
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        safe.execDelegatecall(address(fwd), _call(address(usdc), 5000e6, address(0), 10, 2_000_000));
        vm.expectRevert(ICapsBorrowForwarder.InvalidInput.selector);
        safe.execDelegatecall(address(fwd), _call(address(usdc), 5000e6, riskCouncil, 10, 2_000_000));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE TRANSITIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// CAP-ST-26: raiseCapAndBorrow(USDC, 5,000e6, borrower, 10, 2,000,000): borrower debt +5,000, borrower USDC
    /// +5,000, Risk Council Safe USDC +0, no other account keeps tokens.
    function test_CAP_ST_26_raiseCapAndBorrow_tokensOnlyToBorrower() public {
        uint256 amount = 5000e6;
        _delegate(address(usdc), amount);
        MockVariableDebtToken vdt = _debtToken(address(usdc));

        uint256 debtBefore = vdt.balanceOf(borrower);
        uint256 totalDebtBefore = vdt.totalSupply();
        uint256 poolBefore = usdc.balanceOf(address(pool));

        vm.expectEmit(true, true, false, true, riskCouncil);
        emit ICapsBorrowForwarder.CapRaisedAndBorrowed(address(usdc), borrower, amount, LIVE_CAP, LIVE_CAP + 5000 + 10);
        _run(address(usdc), amount, 10, 2_000_000);

        assertEq(vdt.balanceOf(borrower) - debtBefore, amount, "borrower debt +amount");
        assertEq(vdt.totalSupply() - totalDebtBefore, amount, "total debt +amount");
        assertEq(usdc.balanceOf(borrower), amount, "borrower tokens +amount");
        assertEq(usdc.balanceOf(riskCouncil), 0, "safe keeps nothing");
        assertEq(usdc.balanceOf(address(fwd)), 0, "forwarder keeps nothing");
        assertEq(poolBefore - usdc.balanceOf(address(pool)), amount, "pool paid out exactly amount");
        assertEq(vdt.balanceOf(riskCouncil), 0, "safe carries no debt");
        assertEq(vdt.borrowAllowance(borrower, riskCouncil), 0, "delegation used up");
    }

    /// CAP-ST-26 fuzzed over amount and the three decimals.
    function testFuzz_CAP_ST_26_raiseCapAndBorrow_tokensOnlyToBorrower(uint256 seed, uint256 amount) public {
        MockERC20[3] memory assets = [weth, usdc, wbtc];
        address asset = address(assets[seed % 3]);
        pool.setBorrowCap(asset, LIVE_CAP);
        amount = bound(amount, 1, _wei(asset, LIVE_CAP / 2));
        _delegate(asset, amount);

        _run(asset, amount, 1, type(uint256).max);

        assertEq(_debtToken(asset).balanceOf(borrower), amount);
        assertEq(IERC20(asset).balanceOf(borrower), amount);
        assertEq(IERC20(asset).balanceOf(riskCouncil), 0);
    }

    /// CAP-ST-27: the Safe's token balance is the same before and after raiseCapAndBorrow, also when it already
    /// holds some of the asset.
    function test_CAP_ST_27_raiseCapAndBorrow_noResidualBalance() public {
        usdc.mint(riskCouncil, 777e6);
        uint256 safeBefore = usdc.balanceOf(riskCouncil);
        _delegate(address(usdc), 5000e6);

        _run(address(usdc), 5000e6, 10, 2_000_000);

        assertEq(usdc.balanceOf(riskCouncil), safeBefore, "safe balance unchanged");
        assertEq(usdc.balanceOf(borrower), 5000e6);
    }

    /// CAP-ST-29: live cap 1,000,000 USDC at execution (1,000,050 at signing is ignored). amount 5,000.5 USDC,
    /// extraCapTokens 10: new cap 1,005,011.
    function test_CAP_ST_29_raiseCapAndBorrow_raisesExactlyAmountPlusExtra() public {
        // The signers saw 1,000,050 when they signed; the cap moved back to 1,000,000 before execution.
        pool.setBorrowCap(address(usdc), 1_000_050);
        pool.setBorrowCap(address(usdc), LIVE_CAP);

        uint256 amount = 5_000_500_000; // 5,000.5 USDC
        _delegate(address(usdc), amount);
        _run(address(usdc), amount, 10, 2_000_000);

        assertEq(_liveBorrowCap(address(usdc)), 1_005_011, "live cap + ceil(5,000.5) + 10");
        assertEq(steward.updateCapsCalls(), 1);
        assertEq(steward.lastAsset(), address(usdc));
        assertEq(steward.lastBorrowCap(), 1_005_011);
        assertEq(steward.lastSupplyCap(), EngineFlags.KEEP_CURRENT, "supply cap kept");
    }

    /// CAP-ST-29 fuzzed: new cap = live cap + ceil(amount / 10^dec) + extraCapTokens, read at execution.
    function testFuzz_CAP_ST_29_raiseCapAndBorrow_raisesExactlyAmountPlusExtra(
        uint256 seed,
        uint256 liveCap,
        uint256 amount,
        uint256 extra
    )
        public
    {
        MockERC20[3] memory assets = [weth, usdc, wbtc];
        address asset = address(assets[seed % 3]);
        liveCap = bound(liveCap, 10, 1_000_000);
        // Stay inside the Steward's +100% range: ceil(amount) + extra <= liveCap.
        amount = bound(amount, 1, _wei(asset, liveCap / 2));
        extra = bound(extra, 0, liveCap / 2 - 1);
        pool.setBorrowCap(asset, liveCap);
        _setDebt(asset, 0, 0);
        _delegate(asset, amount);

        uint256 unit = 10 ** MockERC20(asset).decimals();
        uint256 expected = liveCap + (amount + unit - 1) / unit + extra;

        _run(asset, amount, extra, expected);

        assertEq(_liveBorrowCap(asset), expected);
    }

    /// CAP-ST-30: live cap 1,000,000, amount 5,000 USDC, extraCapTokens 10, maxNewCap 1,005,000: reverts.
    /// Live cap 0: reverts. No cap change and no borrow in either case.
    function test_CAP_ST_30_raiseCapAndBorrow_aboveMaxNewCap_reverts() public {
        _delegate(address(usdc), 5000e6);

        vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.NewCapAboveMax.selector, 1_005_010, 1_005_000));
        _run(address(usdc), 5000e6, 10, 1_005_000);
        assertEq(_liveBorrowCap(address(usdc)), LIVE_CAP);
        assertEq(_debtToken(address(usdc)).balanceOf(borrower), 0);

        // Exactly at the limit passes.
        _run(address(usdc), 5000e6, 10, 1_005_010);
        assertEq(_liveBorrowCap(address(usdc)), 1_005_010);
    }

    /// CAP-ST-30: the forwarder does not set a first cap.
    function test_CAP_ST_30_raiseCapAndBorrow_uncapped_reverts() public {
        pool.setBorrowCap(address(usdc), 0);
        _delegate(address(usdc), 5000e6);

        vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.BorrowCapNotSet.selector, address(usdc)));
        _run(address(usdc), 5000e6, 10, type(uint256).max);
        assertEq(_liveBorrowCap(address(usdc)), 0);
        assertEq(_debtToken(address(usdc)).balanceOf(borrower), 0);
        assertEq(steward.updateCapsCalls(), 0);
    }

    /// CAP-ST-31: the Risk Steward 36 h timer is still running, so the Steward reverts and raiseCapAndBorrow reverts
    /// with cap and debt unchanged.
    function test_CAP_ST_31_raiseCapAndBorrow_stepFails_revertsAll() public {
        _delegate(address(usdc), 10_000e6);
        _run(address(usdc), 5000e6, 10, 2_000_000);

        uint256 capAfterFirst = _liveBorrowCap(address(usdc));
        uint256 debtAfterFirst = _debtToken(address(usdc)).balanceOf(borrower);
        uint256 allowanceAfterFirst = _debtToken(address(usdc)).borrowAllowance(borrower, riskCouncil);

        vm.warp(block.timestamp + 36 hours - 1);
        vm.expectRevert(MockRiskSteward.DebounceNotRespected.selector);
        _run(address(usdc), 5000e6, 10, 2_000_000);

        assertEq(_liveBorrowCap(address(usdc)), capAfterFirst, "cap unchanged");
        assertEq(_debtToken(address(usdc)).balanceOf(borrower), debtAfterFirst, "debt unchanged");
        assertEq(_debtToken(address(usdc)).borrowAllowance(borrower, riskCouncil), allowanceAfterFirst);
        assertEq(usdc.balanceOf(borrower), 5000e6, "borrower tokens unchanged");

        // After the debounce the same call goes through.
        vm.warp(block.timestamp + 1);
        _run(address(usdc), 5000e6, 10, 2_000_000);
        assertEq(_debtToken(address(usdc)).balanceOf(borrower), 10_000e6);
    }

    /// CAP-ST-31: the Steward range (+100%) rejects the raise: nothing changes.
    function test_CAP_ST_31_raiseCapAndBorrow_stewardRangeFails_revertsAll() public {
        // ceil(amount) + extra above the live cap gives more than +100%.
        uint256 amount = _wei(address(usdc), LIVE_CAP);
        _delegate(address(usdc), amount);
        vm.expectRevert(MockRiskSteward.UpdateNotInRange.selector);
        _run(address(usdc), amount, 1, type(uint256).max);
        assertEq(_liveBorrowCap(address(usdc)), LIVE_CAP);
        assertEq(_debtToken(address(usdc)).balanceOf(borrower), 0);
    }

    /// CAP-ST-31: the Steward owner restricted the asset: nothing changes.
    function test_CAP_ST_31_raiseCapAndBorrow_assetRestricted_revertsAll() public {
        _delegate(address(usdc), 10_000e6);
        steward.setAddressRestricted(address(usdc), true);
        vm.expectRevert(MockRiskSteward.AssetIsRestricted.selector);
        _run(address(usdc), 5000e6, 10, 2_000_000);
        assertEq(_liveBorrowCap(address(usdc)), LIVE_CAP);
        assertEq(_debtToken(address(usdc)).balanceOf(borrower), 0);
    }

    /// CAP-ST-31: only the borrowCap Steward config applies, as the supplyCap is KEEP_CURRENT.
    function test_CAP_ST_31_raiseCapAndBorrow_usesBorrowCapStewardConfig() public {
        _delegate(address(usdc), 10_000e6);
        steward.setCapConfig(
            MockRiskSteward.RiskParamConfig({ minDelay: 365 days, maxPercentChange: 0 }),
            MockRiskSteward.RiskParamConfig({ minDelay: 0, maxPercentChange: 10_000 })
        );
        _run(address(usdc), 5000e6, 10, 2_000_000);
        _run(address(usdc), 5000e6, 10, 2_000_000);
        assertEq(_debtToken(address(usdc)).balanceOf(borrower), 10_000e6);
    }

    /// CAP-ST-31: the borrow fails (no credit delegation): the cap raise is rolled back.
    function test_CAP_ST_31_raiseCapAndBorrow_borrowFails_revertsAll() public {
        _delegate(address(usdc), 4999e6);
        vm.expectRevert(
            abi.encodeWithSelector(
                MockVariableDebtToken.InsufficientBorrowAllowance.selector, riskCouncil, 4999e6, 5000e6
            )
        );
        _run(address(usdc), 5000e6, 10, 2_000_000);
        assertEq(_liveBorrowCap(address(usdc)), LIVE_CAP, "cap raise rolled back");
        assertEq(_debtToken(address(usdc)).balanceOf(borrower), 0);
        assertEq(steward.borrowCapLastUpdated(address(usdc)), 0, "steward timer rolled back");
    }

    /// CAP-ST-31: the borrow hits the Aave borrow cap (debt moved up after signing and no extra): reverts.
    function test_CAP_ST_31_raiseCapAndBorrow_aaveCapCheckFails_revertsAll() public {
        // Debt sits 1 unit above the live cap, so live cap + ceil(amount) cannot fit debt + amount.
        _setDebt(address(usdc), LIVE_CAP, 1);
        _delegate(address(usdc), 5000e6);
        vm.expectRevert(MockPoolV3.BorrowCapExceeded.selector);
        _run(address(usdc), 5000e6, 0, 2_000_000);
        assertEq(_liveBorrowCap(address(usdc)), LIVE_CAP);
    }

    /// CAP-ST-31: the transfer to the borrower fails (returns false, as for a blocklisted borrower).
    function test_CAP_ST_31_raiseCapAndBorrow_transferFails_revertsAll() public {
        QuirkyERC20 q = _listQuirky();
        q.setBlockedTo(borrower);
        _delegate(address(q), 5000e6);

        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(q)));
        _run(address(q), 5000e6, 10, 2_000_000);
        assertEq(_liveBorrowCap(address(q)), LIVE_CAP);
        assertEq(_debtToken(address(q)).balanceOf(borrower), 0);
        assertEq(q.balanceOf(riskCouncil), 0);
    }

    /// The token's transfer reverts: the revert bubbles up and nothing changes.
    function test_CapsBorrowForwarder_transferReverts_revertsAll() public {
        QuirkyERC20 q = _listQuirky();
        q.setRevertFrom(riskCouncil);
        _delegate(address(q), 5000e6);

        vm.expectRevert("QuirkyERC20: transfer reverted");
        _run(address(q), 5000e6, 10, 2_000_000);
        assertEq(_liveBorrowCap(address(q)), LIVE_CAP);
        assertEq(_debtToken(address(q)).balanceOf(borrower), 0);
    }

    /// The asset has no code (and no return data) when the transfer runs: reverts SafeERC20FailedOperation.
    function test_CapsBorrowForwarder_assetWithNoCode_reverts() public {
        QuirkyERC20 q = _listQuirky();
        q.setSelfEtchFrom(riskCouncil);
        _delegate(address(q), 5000e6);

        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(q)));
        _run(address(q), 5000e6, 10, 2_000_000);
    }

    /// CAP-ST-31: the Safe balance differs after the transfer (token moved only half): reverts.
    function test_CAP_ST_31_raiseCapAndBorrow_balanceChanged_revertsAll() public {
        QuirkyERC20 q = _listQuirky();
        q.setHalfFrom(riskCouncil);
        _delegate(address(q), 5000e6);

        vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.SafeBalanceChanged.selector, 0, 2500e6));
        _run(address(q), 5000e6, 10, 2_000_000);
        assertEq(_liveBorrowCap(address(q)), LIVE_CAP);
        assertEq(_debtToken(address(q)).balanceOf(borrower), 0);
        assertEq(q.balanceOf(borrower), 0);
    }

    /// A token with no return value on `transfer` (USDT style) is accepted.
    function test_CapsBorrowForwarder_noReturnValueToken_succeeds() public {
        QuirkyERC20 q = _listQuirky();
        q.setNoReturnFrom(riskCouncil);
        _delegate(address(q), 5000e6);

        _run(address(q), 5000e6, 10, 2_000_000);
        assertEq(q.balanceOf(borrower), 5000e6);
        assertEq(q.balanceOf(riskCouncil), 0);
    }

    function _listQuirky() internal returns (QuirkyERC20 q) {
        q = new QuirkyERC20(6);
        pool.listReserve(address(q), 6, LIVE_CAP, 0);
        q.mint(address(pool), _wei(address(q), LIQUIDITY));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ACCESS CONTROL
    // ═══════════════════════════════════════════════════════════════════════════

    /// CAP-ACL-12: a borrower calls raiseCapAndBorrow on the forwarder: reverts. Another Safe delegatecalls it:
    /// reverts. No borrow in either case.
    function test_CAP_ACL_12_raiseCapAndBorrow_notRiskCouncilContext_reverts() public {
        _delegate(address(usdc), 5000e6);

        // Direct call: address(this) is the forwarder.
        vm.prank(borrower);
        vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.NotRiskCouncilContext.selector, address(fwd)));
        fwd.raiseCapAndBorrow(address(usdc), 5000e6, borrower, 10, 2_000_000);

        // Direct call from the Risk Council address itself is still not its context.
        vm.prank(riskCouncil);
        vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.NotRiskCouncilContext.selector, address(fwd)));
        fwd.raiseCapAndBorrow(address(usdc), 5000e6, borrower, 10, 2_000_000);

        // Delegatecall from another Safe.
        MockSafe other = new MockSafe();
        vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.NotRiskCouncilContext.selector, address(other)));
        other.execDelegatecall(address(fwd), _call(address(usdc), 5000e6, borrower, 10, 2_000_000));

        assertEq(_liveBorrowCap(address(usdc)), LIVE_CAP);
        assertEq(_debtToken(address(usdc)).balanceOf(borrower), 0);
    }

    /// CAP-ACL-12 fuzzed over the context address.
    function testFuzz_CAP_ACL_12_raiseCapAndBorrow_notRiskCouncilContext_reverts(address context) public {
        vm.assume(context != riskCouncil);
        vm.assume(uint160(context) > 0x10000); // skip precompiles and low addresses
        vm.assume(context.code.length == 0);
        vm.etch(context, address(new MockSafe()).code);
        vm.expectRevert(abi.encodeWithSelector(ICapsBorrowForwarder.NotRiskCouncilContext.selector, context));
        MockSafe(context).execDelegatecall(address(fwd), _call(address(usdc), 5000e6, borrower, 10, 2_000_000));
    }

    /// CAP-ACL-13: the runtime bytecode has no SSTORE and no DELEGATECALL (nor CALLCODE or SELFDESTRUCT), and
    /// a run writes no Safe storage slot except the nonce that MockSafe itself bumps.
    function test_CAP_ACL_13_forwarder_noStorageNoDelegatecall() public {
        bytes memory code = address(fwd).code;
        // Skip the CBOR metadata at the end: its length is in the last two bytes.
        uint256 metaLen = (uint256(uint8(code[code.length - 2])) << 8) | uint256(uint8(code[code.length - 1]));
        uint256 end = code.length - 2 - metaLen;
        for (uint256 i = 0; i < end; i++) {
            uint8 op = uint8(code[i]);
            assertTrue(op != 0x55, "SSTORE");
            assertTrue(op != 0xf4, "DELEGATECALL");
            assertTrue(op != 0xf2, "CALLCODE");
            assertTrue(op != 0xff, "SELFDESTRUCT");
            if (op >= 0x60 && op <= 0x7f) i += op - 0x5f; // skip PUSH1..PUSH32 data
        }

        _delegate(address(usdc), 5000e6);
        vm.record();
        _run(address(usdc), 5000e6, 10, 2_000_000);
        (, bytes32[] memory writes) = vm.accesses(riskCouncil);
        for (uint256 i = 0; i < writes.length; i++) {
            assertEq(writes[i], bytes32(0), "only the MockSafe nonce slot");
        }
        (, bytes32[] memory fwdWrites) = vm.accesses(address(fwd));
        assertEq(fwdWrites.length, 0, "forwarder storage untouched");
    }

    /// CAP-ACL-16: in the Safe's context raiseCapAndBorrow calls only POOL.getConfiguration, RISK_STEWARD.updateCaps
    /// for the given asset, POOL.borrow with onBehalfOf = borrower and asset.transfer(borrower, amount).
    /// The interface step 6 also needs asset.balanceOf(Safe) (twice) and the transfer helper checks
    /// the asset has code; CAP-ACL-16 lists four calls. These read-only calls are allowed here.
    function test_CAP_ACL_16_raiseCapAndBorrow_onlyExpectedCalls() public {
        uint256 amount = 5000e6;
        _delegate(address(usdc), amount);

        vm.startStateDiffRecording();
        _run(address(usdc), amount, 10, 2_000_000);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();

        uint256 nDelegate;
        uint256 nConfig;
        uint256 nUpdate;
        uint256 nBorrow;
        uint256 nTransfer;
        uint256 nBalance;
        for (uint256 i = 0; i < acc.length; i++) {
            Vm.AccountAccess memory a = acc[i];
            bytes4 sel = a.data.length >= 4 ? bytes4(a.data) : bytes4(0);
            // Foundry records the delegatecall with the outer caller as accessor, so check it across the whole
            // trace: the only delegatecall is the Safe into the forwarder (the forwarder makes none).
            if (a.kind == Vm.AccountAccessKind.DelegateCall) {
                assertEq(a.account, address(fwd), "only delegatecall is the Safe into the forwarder");
                assertEq(sel, ICapsBorrowForwarder.raiseCapAndBorrow.selector);
                nDelegate++;
                continue;
            }
            if (a.accessor != riskCouncil) continue;
            if (a.kind == Vm.AccountAccessKind.Resume) continue;

            if (a.kind == Vm.AccountAccessKind.Extcodesize) {
                // The transfer helper checks the asset; solc checks the Pool and Steward before calls with no
                // return data.
                assertTrue(
                    a.account == address(usdc) || a.account == address(pool) || a.account == address(steward),
                    "code-size check on an expected account only"
                );
            } else if (a.account == address(pool)) {
                if (sel == MockPoolV3.getConfiguration.selector) {
                    assertEq(a.data, abi.encodeCall(MockPoolV3.getConfiguration, (address(usdc))));
                    nConfig++;
                } else if (sel == MockPoolV3.borrow.selector) {
                    assertEq(a.data, abi.encodeCall(MockPoolV3.borrow, (address(usdc), amount, 2, 0, borrower)));
                    nBorrow++;
                } else {
                    revert("unexpected Pool call");
                }
            } else if (a.account == address(steward)) {
                assertEq(sel, MockRiskSteward.updateCaps.selector, "unexpected Steward call");
                IEngine.CapsUpdate[] memory u = new IEngine.CapsUpdate[](1);
                u[0] = IEngine.CapsUpdate({
                    asset: address(usdc), supplyCap: EngineFlags.KEEP_CURRENT, borrowCap: LIVE_CAP + 5000 + 10
                });
                assertEq(a.data, abi.encodeCall(MockRiskSteward.updateCaps, (u)));
                nUpdate++;
            } else if (a.account == address(usdc)) {
                if (sel == IERC20.transfer.selector) {
                    assertEq(a.data, abi.encodeCall(IERC20.transfer, (borrower, amount)));
                    nTransfer++;
                } else if (sel == IERC20.balanceOf.selector) {
                    assertEq(a.data, abi.encodeCall(IERC20.balanceOf, (riskCouncil)));
                    nBalance++;
                } else {
                    revert("unexpected asset call");
                }
            } else {
                revert("unexpected account called from the Safe context");
            }
        }
        assertEq(nDelegate, 1, "one delegatecall");
        assertEq(nConfig, 1, "one getConfiguration");
        assertEq(nUpdate, 1, "one updateCaps");
        assertEq(nBorrow, 1, "one borrow");
        assertEq(nTransfer, 1, "one transfer");
        assertEq(nBalance, 2, "two balance reads");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UNITS
    // ═══════════════════════════════════════════════════════════════════════════

    /// CAP-UNIT-13: USDC amount 5,000,000,001 units (5,000.000001 USDC) adds 5,001 tokens to the cap; an
    /// exact 5,000 USDC adds 5,000.
    function test_CAP_UNIT_13_raiseCapAndBorrow_amountRoundsUp() public {
        _delegate(address(usdc), type(uint256).max);
        _run(address(usdc), 5_000_000_001, 0, type(uint256).max);
        assertEq(_liveBorrowCap(address(usdc)), LIVE_CAP + 5001);

        // WBTC (8 decimals), exact whole amount: no round-up.
        pool.setBorrowCap(address(wbtc), 1000);
        _delegate(address(wbtc), type(uint256).max);
        _run(address(wbtc), 5e8, 0, type(uint256).max);
        assertEq(_liveBorrowCap(address(wbtc)), 1005);

        // WETH (18 decimals), 1 wei adds a whole token.
        pool.setBorrowCap(address(weth), 1000);
        _delegate(address(weth), type(uint256).max);
        _run(address(weth), 1, 0, type(uint256).max);
        assertEq(_liveBorrowCap(address(weth)), 1001);
    }

    /// CAP-UNIT-13 fuzzed: cap increase * 10^dec >= amount and the increase is the least such whole number.
    function testFuzz_CAP_UNIT_13_raiseCapAndBorrow_amountRoundsUp(uint256 seed, uint256 amount) public {
        MockERC20[3] memory assets = [weth, usdc, wbtc];
        address asset = address(assets[seed % 3]);
        pool.setBorrowCap(asset, LIVE_CAP);
        amount = bound(amount, 1, _wei(asset, LIVE_CAP / 2));
        _delegate(asset, amount);

        _run(asset, amount, 0, type(uint256).max);

        uint256 unit = 10 ** MockERC20(asset).decimals();
        uint256 increase = _liveBorrowCap(asset) - LIVE_CAP;
        assertGe(increase * unit, amount, "raise covers the borrow");
        assertLt((increase - 1) * unit, amount, "raise is the least whole-token cover");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {
    IAaveV3ConfigEngine as IEngine
} from "aave-v3-origin/src/contracts/extensions/v3-config-engine/IAaveV3ConfigEngine.sol";
import { DataTypes } from "aave-v3-origin/src/contracts/protocol/libraries/types/DataTypes.sol";
import { CapsTestBase } from "./CapsTestBase.sol";
import { MockCapsRvm } from "./mocks/MockCapsRvm.sol";
import { MockSafe } from "./mocks/MockSafe.sol";
import { MockVariableDebtToken } from "./mocks/MockPoolV3.sol";
import { ICapsRangeValidationModule as IRvm } from "../../src/caps-oracle/interfaces/ICapsRangeValidationModule.sol";

/// @notice Smoke tests for the scaffold: they check the mocks and fixtures, not Stage 1 contracts.
contract ScaffoldTest is CapsTestBase {
    function test_Scaffold_debtReadsBackAndRoundsUp() public {
        _applyFixture(address(weth), _f1(), 1085);
        MockVariableDebtToken vdt = MockVariableDebtToken(pool.getReserveVariableDebtToken(address(weth)));
        assertEq(vdt.totalSupply(), 1000e18);
        assertEq(pool.getTotalDebt(address(weth)), 1000e18);

        // index above 1 ray: scaled total x index rounds up, as VariableDebtToken.totalSupply does
        pool.setScaledDebt(address(usdc), 1e9 + 1);
        pool.setIndex(address(usdc), 1.5e27);
        assertEq(MockVariableDebtToken(pool.getReserveVariableDebtToken(address(usdc))).totalSupply(), 1_500_000_002);
    }

    function test_Scaffold_configBitsMatchAave() public {
        _applyFixture(address(usdc), _f1(), 1085);
        pool.setFrozen(address(usdc), true);
        pool.setPaused(address(usdc), true);
        DataTypes.ReserveConfigurationMap memory c = pool.getConfiguration(address(usdc));
        assertEq((c.data >> 48) & 0xff, 6, "decimals bits 48-55");
        assertEq((c.data >> 57) & 1, 1, "frozen bit 57");
        assertEq((c.data >> 60) & 1, 1, "paused bit 60");
        assertEq((c.data >> 80) & ((1 << 36) - 1), 1085, "borrow cap bits 80-115");
        assertEq((c.data >> 116) & ((1 << 36) - 1), 5000, "supply cap bits 116-151");
        DataTypes.ReserveDataLegacy memory d = pool.getReserveData(address(usdc));
        assertEq(d.variableDebtTokenAddress, pool.getReserveVariableDebtToken(address(usdc)));
        assertEq(d.variableBorrowIndex, 1e27);
    }

    function test_Scaffold_borrowRespectsCapAndDelegation() public {
        _applyFixture(address(weth), _f1(), 1085);
        weth.mint(address(pool), 1000e18);
        MockVariableDebtToken vdt = MockVariableDebtToken(pool.getReserveVariableDebtToken(address(weth)));

        vm.prank(borrower);
        vdt.approveDelegation(riskCouncil, 85e18);

        vm.startPrank(riskCouncil);
        vm.expectRevert(abi.encodeWithSignature("BorrowCapExceeded()"));
        pool.borrow(address(weth), 86e18, 2, 0, borrower); // 1,086 > cap 1,085
        pool.borrow(address(weth), 85e18, 2, 0, borrower);
        vm.stopPrank();

        assertEq(vdt.balanceOf(borrower), 85e18);
        assertEq(weth.balanceOf(riskCouncil), 85e18);
        assertEq(vdt.borrowAllowance(borrower, riskCouncil), 0);
    }

    function test_Scaffold_stewardGuardsLikeAave() public {
        _applyFixture(address(weth), _f1(), 1000);
        IEngine.CapsUpdate[] memory u = new IEngine.CapsUpdate[](1);
        u[0] = IEngine.CapsUpdate({ asset: address(weth), supplyCap: type(uint256).max - 42, borrowCap: 1500 });

        vm.expectRevert(abi.encodeWithSignature("InvalidCaller()"));
        steward.updateCaps(u);

        vm.startPrank(riskCouncil);
        steward.updateCaps(u);
        assertEq(_liveBorrowCap(address(weth)), 1500);
        u[0].borrowCap = 1600;
        vm.expectRevert(abi.encodeWithSignature("DebounceNotRespected()"));
        steward.updateCaps(u);
        vm.warp(block.timestamp + 36 hours);
        u[0].borrowCap = 3001; // above +100%
        vm.expectRevert(abi.encodeWithSignature("UpdateNotInRange()"));
        steward.updateCaps(u);
        vm.stopPrank();
    }

    function test_Scaffold_safeDelegatecallRunsInSafeContext() public {
        _etchSafeAtRiskCouncil();
        // delegatecall to the MockSafe code itself would be recursion; use a plain target
        Ctx ctx = new Ctx();
        bytes memory ret = MockSafe(riskCouncil).execDelegatecall(address(ctx), abi.encodeCall(Ctx.who, ()));
        assertEq(abi.decode(ret, (address)), riskCouncil);
        assertEq(MockSafe(riskCouncil).nonce(), 1);
    }

    function test_Scaffold_mockRvmServesReducerReads() public {
        MockCapsRvm rvm = new MockCapsRvm();
        rvm.setCut(address(weth), IRvm.CapKind.BORROW, true, 1200, 1100);
        (bool due, uint256 cur, uint256 next) = rvm.previewCut(address(weth), IRvm.CapKind.BORROW);
        assertTrue(due);
        assertEq(cur, 1200);
        assertEq(next, 1100);
    }

    function test_Scaffold_fixturesDerivedValues() public pure {
        // F1: L = max(Lmin, min(maxHeadroom, alpha * D)) = max(20, min(500, 100)) = 100
        uint256 d = F1_DEBT;
        uint256 l = d * ALPHA_BPS / 10_000;
        assertEq(l, F1_L);
        assertEq(d + l, F1_RAISE_BOUND);
        assertEq(d + l + l * CUT_CUT_BAND_BPS / 10_000, F1_CUT_TRIGGER);
        assertEq(uint256(MAX_HEADROOM) / 25, F1_LMIN);
        // F2: alpha * D = 1,000 clamps to maxHeadroom = 500
        assertEq(F2_DEBT + F2_L, F2_RAISE_BOUND);
    }
}

contract Ctx {
    function who() external view returns (address) {
        return address(this);
    }
}

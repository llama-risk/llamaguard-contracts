// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { AaveV3Ethereum, AaveV3EthereumAssets } from "aave-address-book/AaveV3Ethereum.sol";
import { IPool } from "aave-v3-origin/src/contracts/interfaces/IPool.sol";
import { ICreditDelegationToken } from "aave-v3-origin/src/contracts/interfaces/ICreditDelegationToken.sol";
import { DataTypes } from "aave-v3-origin/src/contracts/protocol/libraries/types/DataTypes.sol";
import {
    ReserveConfiguration
} from "aave-v3-origin/src/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import { WadRayMath } from "aave-v3-origin/src/contracts/protocol/libraries/math/WadRayMath.sol";
import { IRiskSteward } from "aave-v3-risk-stewards/interfaces/IRiskSteward.sol";
import { CapsBorrowForwarder } from "../../../src/caps-oracle/CapsBorrowForwarder.sol";
import { CapsRangeValidationModuleV3 } from "../../../src/caps-oracle/CapsRangeValidationModuleV3.sol";
import { ICapsRangeValidationModule as IRvm } from "../../../src/caps-oracle/interfaces/ICapsRangeValidationModule.sol";

/// @notice Etched at the Risk Council Safe address: delegatecalls a target, as a Safe `DelegateCall` operation
///         does. No storage, so the Safe's slots stay untouched.
contract DelegatecallShim {
    function execDelegatecall(address target, bytes calldata data) external returns (bytes memory ret) {
        bool ok;
        (ok, ret) = target.delegatecall(data);
        if (!ok) {
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }
    }
}

/// @title CapsForkEthereumCore
/// @notice CapsBorrowForwarder on the live Aave V3 Ethereum Core Pool and the live Risk Steward, and the RVM
///         reads on the live Pool.
/// @dev Skips unless `ETH_RPC_URL` is set and the profile is `fork` (the live config engine needs a
///      post-shanghai EVM, see EthereumCoreForkTest):
///        ETH_RPC_URL=... FOUNDRY_PROFILE=fork forge test --match-path 'tests/caps-oracle/fork/**'
contract CapsForkEthereumCore is Test {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using WadRayMath for uint256;

    /// @dev Pinned so the same commit gives the same result on every run.
    uint256 internal constant FORK_BLOCK = 26_344_000;

    IPool internal constant POOL = AaveV3Ethereum.POOL;
    address internal constant STEWARD = AaveV3Ethereum.RISK_STEWARD;
    address internal constant USDC = AaveV3EthereumAssets.USDC_UNDERLYING;
    address internal constant WETH = AaveV3EthereumAssets.WETH_UNDERLYING;

    bool internal forked;
    address internal riskCouncil;
    CapsBorrowForwarder internal forwarder;
    address internal borrower = makeAddr("borrower");

    function setUp() public {
        string memory rpc = vm.envOr("ETH_RPC_URL", string(""));
        string memory profile = vm.envOr("FOUNDRY_PROFILE", string(""));
        if (bytes(rpc).length == 0 || keccak256(bytes(profile)) != keccak256("fork")) return;
        vm.createSelectFork(rpc, FORK_BLOCK);
        forked = true;

        riskCouncil = IRiskSteward(STEWARD).RISK_COUNCIL();
        forwarder = new CapsBorrowForwarder(address(POOL), STEWARD, riskCouncil);
        vm.etch(riskCouncil, address(new DelegatecallShim()).code);

        // Past any running cap debounce of the Steward.
        vm.warp(block.timestamp + 30 days);

        // Borrower: 100 WETH collateral, credit delegation of USDC to the Safe.
        deal(WETH, borrower, 100 ether);
        vm.startPrank(borrower);
        IERC20(WETH).approve(address(POOL), 100 ether);
        POOL.supply(WETH, 100 ether, borrower, 0);
        ICreditDelegationToken(AaveV3EthereumAssets.USDC_V_TOKEN).approveDelegation(riskCouncil, 100_000e6);
        vm.stopPrank();
    }

    modifier onlyForked() {
        if (!forked) vm.skip(true);
        _;
    }

    function _borrowCap(address asset) internal view returns (uint256) {
        return POOL.getConfiguration(asset).getBorrowCap();
    }

    function _raise(uint256 amount, uint256 extra) internal {
        DelegatecallShim(riskCouncil)
            .execDelegatecall(
                address(forwarder),
                abi.encodeCall(
                    CapsBorrowForwarder.raiseCapAndBorrow, (USDC, amount, borrower, extra, type(uint256).max)
                )
            );
    }

    function test_fork_raiseCapAndBorrow_raisesCapAndBorrows() public onlyForked {
        uint256 amount = 10_000e6;
        uint256 oldCap = _borrowCap(USDC);
        uint256 debtBefore = IERC20(AaveV3EthereumAssets.USDC_V_TOKEN).balanceOf(borrower);
        uint256 safeBefore = IERC20(USDC).balanceOf(riskCouncil);

        _raise(amount, 0);

        assertEq(_borrowCap(USDC), oldCap + 10_000, "cap raised by the amount in whole tokens");
        assertEq(IERC20(USDC).balanceOf(borrower), amount, "borrower got the tokens");
        // Aave rounds the scaled debt and the balance up, so the debt can sit a few wei above the amount.
        uint256 debtAfter = IERC20(AaveV3EthereumAssets.USDC_V_TOKEN).balanceOf(borrower);
        assertGe(debtAfter, debtBefore + amount, "debt on borrower");
        assertLe(debtAfter, debtBefore + amount + 2, "debt on borrower, rounding");
        assertEq(IERC20(USDC).balanceOf(riskCouncil), safeBefore, "Safe keeps nothing");
    }

    function test_fork_raiseCapAndBorrow_stewardDebounce_revertsAll() public onlyForked {
        _raise(10_000e6, 0);
        uint256 capAfterFirst = _borrowCap(USDC);
        uint256 debtAfterFirst = IERC20(AaveV3EthereumAssets.USDC_V_TOKEN).balanceOf(borrower);

        vm.expectRevert(IRiskSteward.DebounceNotRespected.selector);
        _raise(10_000e6, 0);

        assertEq(_borrowCap(USDC), capAfterFirst, "cap unchanged");
        assertEq(IERC20(AaveV3EthereumAssets.USDC_V_TOKEN).balanceOf(borrower), debtAfterFirst, "debt unchanged");
        assertEq(IERC20(USDC).balanceOf(borrower), 10_000e6, "no second transfer");
    }

    function test_fork_rvm_getReserveState_matchesPool() public onlyForked {
        address owner = makeAddr("owner");
        CapsRangeValidationModuleV3 rvm = new CapsRangeValidationModuleV3(
            owner, makeAddr("agentHub"), address(POOL), riskCouncil, "BorrowCapUpdate_Core", "SupplyCapUpdate_Core"
        );
        IRvm.RateLimitConfig memory c =
            IRvm.RateLimitConfig({ maxCap: 1e10, maxHeadroom: 1e9, alphaBps: 1000, cutBandBps: 1000 });
        IRvm.Bounds memory b =
            IRvm.Bounds({ alphaBpsLimit: 10_000, cutBandBpsLimit: 10_000, maxIncreaseBps: 10_000, cooldown: 0 });
        vm.startPrank(owner);
        rvm.setBounds(IRvm.CapKind.BORROW, b);
        rvm.setBounds(IRvm.CapKind.SUPPLY, b);
        rvm.setRateLimitConfig(USDC, IRvm.CapKind.BORROW, c);
        rvm.setRateLimitConfig(USDC, IRvm.CapKind.SUPPLY, c);
        vm.stopPrank();

        DataTypes.ReserveConfigurationMap memory config = POOL.getConfiguration(USDC);
        DataTypes.ReserveDataLegacy memory data = POOL.getReserveData(USDC);
        uint256 unit = 10 ** config.getDecimals();

        IRvm.ReserveState memory s = rvm.getReserveState(USDC, IRvm.CapKind.BORROW);
        assertEq(s.cap, config.getBorrowCap(), "borrow cap");
        assertEq(s.usage, Math.ceilDiv(IERC20(data.variableDebtTokenAddress).totalSupply(), unit), "debt");
        assertEq(s.supplyBound, config.getSupplyCap(), "supply cap bound");
        assertEq(s.raiseBlocked, config.getFrozen() || config.getPaused(), "raise blocked");
        assertGt(s.usage, 0, "live debt");

        s = rvm.getReserveState(USDC, IRvm.CapKind.SUPPLY);
        uint256 treasury = uint256(data.accruedToTreasury).rayMul(POOL.getReserveNormalizedIncome(USDC));
        assertEq(s.cap, config.getSupplyCap(), "supply cap");
        assertEq(s.usage, Math.ceilDiv(IERC20(data.aTokenAddress).totalSupply() + treasury, unit), "supplied");
        assertGe(s.usage, Math.ceilDiv(IERC20(USDC).balanceOf(data.aTokenAddress), unit), "supplied >= idle cash");
    }
}

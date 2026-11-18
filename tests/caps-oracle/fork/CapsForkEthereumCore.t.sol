// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { AaveV3Ethereum, AaveV3EthereumAssets } from "aave-address-book/AaveV3Ethereum.sol";
import { IPool } from "aave-v3-origin/src/contracts/interfaces/IPool.sol";
import { IPoolConfigurator } from "aave-v3-origin/src/contracts/interfaces/IPoolConfigurator.sol";
import { ICreditDelegationToken } from "aave-v3-origin/src/contracts/interfaces/ICreditDelegationToken.sol";
import { DataTypes } from "aave-v3-origin/src/contracts/protocol/libraries/types/DataTypes.sol";
import {
    ReserveConfiguration
} from "aave-v3-origin/src/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import { WadRayMath } from "aave-v3-origin/src/contracts/protocol/libraries/math/WadRayMath.sol";
import { IRiskSteward } from "aave-v3-risk-stewards/interfaces/IRiskSteward.sol";
import { CapsBorrowForwarder } from "../../../src/caps-oracle/CapsBorrowForwarder.sol";
import { ICapsBorrowForwarder } from "../../../src/caps-oracle/interfaces/ICapsBorrowForwarder.sol";
import { CapsRangeValidationModuleV3 } from "../../../src/caps-oracle/CapsRangeValidationModuleV3.sol";
import { ICapsRangeValidationModule as IRvm } from "../../../src/caps-oracle/interfaces/ICapsRangeValidationModule.sol";

/// @title CapsForkEthereumCore
/// @notice The standalone CapsBorrowForwarder on the live Aave V3 Ethereum Core Pool and config engine, with
///         RISK_ADMIN granted to the forwarder on the live ACL Manager, and the RVM reads on the live Pool.
/// @dev Skips unless `ETH_RPC_URL` is set and the profile is `fork` (the live config engine needs a
///      post-shanghai EVM, see EthereumCoreForkTest):
///        ETH_RPC_URL=... FOUNDRY_PROFILE=fork forge test --match-path 'tests/caps-oracle/fork/**'
contract CapsForkEthereumCore is Test {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using WadRayMath for uint256;

    /// @dev Pinned so the same commit gives the same result on every run.
    uint256 internal constant FORK_BLOCK = 26_344_000;

    IPool internal constant POOL = AaveV3Ethereum.POOL;
    address internal constant USDC = AaveV3EthereumAssets.USDC_UNDERLYING;
    address internal constant WETH = AaveV3EthereumAssets.WETH_UNDERLYING;
    address internal constant USDC_V_TOKEN = AaveV3EthereumAssets.USDC_V_TOKEN;

    /// Placeholder limits: +100% per raise, one raise per asset per day.
    uint256 internal constant MAX_RAISE_BPS = 10_000;
    uint256 internal constant MIN_RAISE_DELAY = 1 days;

    bool internal forked;
    address internal riskCouncil;
    CapsBorrowForwarder internal forwarder;
    CapsRangeValidationModuleV3 internal forwarderRvm;
    address internal owner = makeAddr("agentHubOwner");
    address internal rvmOwner = makeAddr("rvmOwner");
    address internal borrower = makeAddr("borrower");

    function setUp() public {
        string memory rpc = vm.envOr("ETH_RPC_URL", string(""));
        string memory profile = vm.envOr("FOUNDRY_PROFILE", string(""));
        if (bytes(rpc).length == 0 || keccak256(bytes(profile)) != keccak256("fork")) return;
        vm.createSelectFork(rpc, FORK_BLOCK);
        forked = true;

        // The live Risk Council Safe, as the one allowlisted caller. A plain call, so no Safe code is needed.
        riskCouncil = IRiskSteward(AaveV3Ethereum.RISK_STEWARD).RISK_COUNCIL();
        forwarderRvm = new CapsRangeValidationModuleV3(
            rvmOwner, makeAddr("agentHub"), address(POOL), riskCouncil, "BorrowCapUpdate_Core", "SupplyCapUpdate_Core"
        );
        forwarder = new CapsBorrowForwarder(
            owner,
            address(POOL),
            AaveV3Ethereum.CONFIG_ENGINE,
            address(forwarderRvm),
            riskCouncil,
            MAX_RAISE_BPS,
            MIN_RAISE_DELAY
        );

        // The AIP grants RISK_ADMIN to the forwarder: the engine runs by delegatecall, so the PoolConfigurator
        // sees the forwarder as caller.
        vm.prank(AaveV3Ethereum.ACL_ADMIN);
        AaveV3Ethereum.ACL_MANAGER.addRiskAdmin(address(forwarder));

        // RVM borrow entry for USDC with room above the live cap.
        _setRvmMaxCap(uint64(_borrowCap(USDC) * 2));

        // Borrower: 100 WETH collateral, credit delegation of USDC to the forwarder.
        deal(WETH, borrower, 100 ether);
        vm.startPrank(borrower);
        IERC20(WETH).approve(address(POOL), 100 ether);
        POOL.supply(WETH, 100 ether, borrower, 0);
        ICreditDelegationToken(USDC_V_TOKEN).approveDelegation(address(forwarder), 100_000e6);
        vm.stopPrank();
    }

    modifier onlyForked() {
        if (!forked) vm.skip(true);
        _;
    }

    function _borrowCap(address asset) internal view returns (uint256) {
        return POOL.getConfiguration(asset).getBorrowCap();
    }

    function _setRvmMaxCap(uint64 maxCap) internal {
        IRvm.Bounds memory b =
            IRvm.Bounds({ alphaBpsLimit: 10_000, cutBandBpsLimit: 10_000, maxIncreaseBps: 10_000, cooldown: 1 days });
        IRvm.RateLimitConfig memory c =
            IRvm.RateLimitConfig({ maxCap: maxCap, maxHeadroom: 1e9, alphaBps: 1000, cutBandBps: 1000 });
        vm.startPrank(rvmOwner);
        forwarderRvm.setBounds(IRvm.CapKind.BORROW, b);
        forwarderRvm.setRateLimitConfig(USDC, IRvm.CapKind.BORROW, c);
        vm.stopPrank();
    }

    function _raise(uint256 amount) internal {
        vm.prank(riskCouncil);
        forwarder.raiseCapAndBorrow(USDC, amount, borrower);
    }

    function test_fork_forwarderIsRiskAdmin() public onlyForked {
        assertTrue(AaveV3Ethereum.ACL_MANAGER.isRiskAdmin(address(forwarder)));
        assertEq(forwarder.CONFIG_ENGINE(), AaveV3Ethereum.CONFIG_ENGINE);
        assertEq(forwarder.owner(), owner);
    }

    function test_fork_raiseCapAndBorrow_raisesCapAndBorrows() public onlyForked {
        uint256 amount = 10_000e6;
        uint256 oldCap = _borrowCap(USDC);
        uint256 debtBefore = IERC20(USDC_V_TOKEN).balanceOf(borrower);
        uint256 callerBefore = IERC20(USDC).balanceOf(riskCouncil);

        _raise(amount);

        assertEq(_borrowCap(USDC), oldCap + 10_001, "cap raised by the amount in whole tokens, plus 1");
        assertEq(IERC20(USDC).balanceOf(borrower), amount, "borrower got the tokens");
        // Aave rounds the scaled debt and the balance up, so the debt can sit a few wei above the amount.
        uint256 debtAfter = IERC20(USDC_V_TOKEN).balanceOf(borrower);
        assertGe(debtAfter, debtBefore + amount, "debt on borrower");
        assertLe(debtAfter, debtBefore + amount + 2, "debt on borrower, rounding");
        assertEq(IERC20(USDC).balanceOf(riskCouncil), callerBefore, "caller keeps nothing");
        assertEq(IERC20(USDC).balanceOf(address(forwarder)), 0, "forwarder keeps nothing");
        // Needs renounceDelegation on the live debt token (Aave v3.6+).
        assertEq(
            ICreditDelegationToken(USDC_V_TOKEN).borrowAllowance(borrower, address(forwarder)), 0, "rest renounced"
        );
    }

    /// Without RISK_ADMIN the live PoolConfigurator refuses the engine's setBorrowCap: nothing changes.
    function test_fork_raiseCapAndBorrow_withoutRiskAdmin_reverts() public onlyForked {
        vm.prank(AaveV3Ethereum.ACL_ADMIN);
        AaveV3Ethereum.ACL_MANAGER.removeRiskAdmin(address(forwarder));
        uint256 oldCap = _borrowCap(USDC);
        vm.expectRevert();
        _raise(10_000e6);
        assertEq(_borrowCap(USDC), oldCap, "cap unchanged");
        assertEq(IERC20(USDC).balanceOf(borrower), 0, "no borrow");
    }

    /// The per-asset delay: a second raise within MIN_RAISE_DELAY reverts with cap and debt unchanged.
    function test_fork_raiseCapAndBorrow_minRaiseDelay_revertsAll() public onlyForked {
        _raise(10_000e6);
        uint256 capAfterFirst = _borrowCap(USDC);
        uint256 debtAfterFirst = IERC20(USDC_V_TOKEN).balanceOf(borrower);

        vm.prank(borrower);
        ICreditDelegationToken(USDC_V_TOKEN).approveDelegation(address(forwarder), 10_000e6);
        vm.expectRevert(
            abi.encodeWithSelector(ICapsBorrowForwarder.RaiseTooSoon.selector, USDC, block.timestamp + MIN_RAISE_DELAY)
        );
        _raise(10_000e6);

        assertEq(_borrowCap(USDC), capAfterFirst, "cap unchanged");
        assertEq(IERC20(USDC_V_TOKEN).balanceOf(borrower), debtAfterFirst, "debt unchanged");
        assertEq(IERC20(USDC).balanceOf(borrower), 10_000e6, "no second transfer");
    }

    /// Accrued interest above the cap: the cap is set to the debt, then 30 days of interest push the debt above
    /// it. The new cap starts from the debt, so the borrow fits.
    function test_fork_raiseCapAndBorrow_debtAboveCap_startsFromDebt() public onlyForked {
        uint256 debt = Math.ceilDiv(IERC20(USDC_V_TOKEN).totalSupply(), 1e6);
        vm.prank(AaveV3Ethereum.ACL_ADMIN);
        IPoolConfigurator(address(AaveV3Ethereum.POOL_CONFIGURATOR)).setBorrowCap(USDC, debt);
        vm.warp(block.timestamp + 30 days);
        uint256 debtNow = Math.ceilDiv(IERC20(USDC_V_TOKEN).totalSupply(), 1e6);
        assertGt(debtNow, debt, "interest pushed the debt above the cap");

        _raise(10_000e6);
        assertEq(_borrowCap(USDC), debtNow + 10_001, "new cap = debt + amount + 1");
        assertEq(IERC20(USDC).balanceOf(borrower), 10_000e6, "borrower got the tokens");
    }

    /// The live RVM borrow maxCap bounds the forwarder: 1 token below the new cap reverts, at it passes.
    function test_fork_raiseCapAndBorrow_aboveRvmMaxCap_reverts() public onlyForked {
        uint256 oldCap = _borrowCap(USDC);
        _setRvmMaxCap(uint64(oldCap + 10_000));

        vm.expectRevert(
            abi.encodeWithSelector(ICapsBorrowForwarder.NewCapAboveMaxCap.selector, oldCap + 10_001, oldCap + 10_000)
        );
        _raise(10_000e6);
        assertEq(_borrowCap(USDC), oldCap, "cap unchanged");

        _setRvmMaxCap(uint64(oldCap + 10_001));
        _raise(10_000e6);
        assertEq(_borrowCap(USDC), oldCap + 10_001, "at maxCap passes");
    }

    function test_fork_rvm_getReserveState_matchesPool() public onlyForked {
        address rvmOwner2 = makeAddr("owner");
        CapsRangeValidationModuleV3 rvm = new CapsRangeValidationModuleV3(
            rvmOwner2, makeAddr("agentHub"), address(POOL), riskCouncil, "BorrowCapUpdate_Core", "SupplyCapUpdate_Core"
        );
        IRvm.RateLimitConfig memory c =
            IRvm.RateLimitConfig({ maxCap: 1e10, maxHeadroom: 1e9, alphaBps: 1000, cutBandBps: 1000 });
        IRvm.Bounds memory b =
            IRvm.Bounds({ alphaBpsLimit: 10_000, cutBandBpsLimit: 10_000, maxIncreaseBps: 10_000, cooldown: 1 days });
        vm.startPrank(rvmOwner2);
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

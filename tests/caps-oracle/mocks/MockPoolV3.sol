// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { DataTypes } from "aave-v3-origin/src/contracts/protocol/libraries/types/DataTypes.sol";
import {
    ReserveConfiguration
} from "aave-v3-origin/src/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import { WadRayMath } from "aave-v3-origin/src/contracts/protocol/libraries/math/WadRayMath.sol";

/// @title MockVariableDebtToken
/// @notice Variable debt token of one MockPoolV3 reserve. Mirrors the parts of Aave's VariableDebtToken
///         that the caps oracle reads: `totalSupply()` is live debt, `scaledTotal.rayMulCeil(index)`
///         (VariableDebtToken.sol:150-153, TokenMath.sol:108-113 in aave-v3-origin 3.6.0), and credit
///         delegation (`approveDelegation`, `borrowAllowance`).
contract MockVariableDebtToken {
    using WadRayMath for uint256;

    error InsufficientBorrowAllowance(address delegatee, uint256 allowance, uint256 needed);
    error OnlyPool();

    MockPoolV3 public immutable POOL;
    address public immutable UNDERLYING_ASSET_ADDRESS;

    uint256 public scaledTotalSupply;
    mapping(address user => uint256) public scaledBalanceOf;
    mapping(address from => mapping(address to => uint256)) public borrowAllowance;

    constructor(MockPoolV3 pool, address underlying) {
        POOL = pool;
        UNDERLYING_ASSET_ADDRESS = underlying;
    }

    modifier onlyPool() {
        if (msg.sender != address(POOL)) revert OnlyPool();
        _;
    }

    /// @notice Live total debt in the underlying's smallest unit, at the current index, rounded up.
    function totalSupply() external view returns (uint256) {
        return scaledTotalSupply.rayMulCeil(POOL.getReserveNormalizedVariableDebt(UNDERLYING_ASSET_ADDRESS));
    }

    /// @notice Live debt of `user` in the underlying's smallest unit, rounded up.
    function balanceOf(address user) external view returns (uint256) {
        return scaledBalanceOf[user].rayMulCeil(POOL.getReserveNormalizedVariableDebt(UNDERLYING_ASSET_ADDRESS));
    }

    function approveDelegation(address delegatee, uint256 amount) external {
        borrowAllowance[msg.sender][delegatee] = amount;
    }

    /// @dev Pool only: use `amount` of the allowance that `from` gave to `to`.
    function spendAllowance(address from, address to, uint256 amount) external onlyPool {
        uint256 allowance = borrowAllowance[from][to];
        if (allowance < amount) revert InsufficientBorrowAllowance(to, allowance, amount);
        borrowAllowance[from][to] = allowance - amount;
    }

    /// @dev Pool only: add scaled debt for `user`.
    function mintScaled(address user, uint256 scaledAmount) external onlyPool {
        scaledBalanceOf[user] += scaledAmount;
        scaledTotalSupply += scaledAmount;
    }

    /// @dev Pool only: remove scaled debt of `user`, floored at their balance.
    function burnScaled(address user, uint256 scaledAmount) external onlyPool {
        uint256 bal = scaledBalanceOf[user];
        if (scaledAmount > bal) scaledAmount = bal;
        scaledBalanceOf[user] = bal - scaledAmount;
        scaledTotalSupply -= scaledAmount;
    }

    /// @dev Pool only: set the scaled total directly (test setup of D without a borrower).
    function setScaledTotal(uint256 scaledAmount) external onlyPool {
        scaledTotalSupply = scaledAmount;
    }
}

/// @title MockPoolV3
/// @notice Aave V3 Pool stand-in for the caps oracle tests. It implements the Pool functions that the
///         CapsRangeValidationModuleV3, the AaveBorrowCapAgent and the CapsBorrowForwarder call,
///         with the signatures of aave-v3-origin 3.6.0 `IPool`:
///           getConfiguration, getReserveData, getReservesList, getReserveNormalizedVariableDebt,
///           getReserveVariableDebtToken, borrow, repay.
///         It also exposes the `IPoolDataProvider` reads the V3 RVM may use (`getReserveCaps`,
///         `getTotalDebt`, `getPaused`, `getReserveConfigurationData`, `getReserveTokensAddresses`), so
///         one mock can be passed as the pool and as the data provider.
/// @dev Per reserve it stores: the configuration word (decimals, borrow cap, supply cap, frozen, paused),
///      the variable borrow index (ray, default 1e27), `lastUpdateTimestamp`, and a MockVariableDebtToken
///      that holds the debt. Test setters are open on purpose and have no access control.
///      Not mocked: health factor, collateral, interest accrual (set the index by hand with `setIndex`),
///      supply and aTokens. Liquidity is whatever underlying the test mints to the pool address.
contract MockPoolV3 {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using WadRayMath for uint256;

    error ReserveNotListed(address asset);
    error ReserveFrozenOrPaused(address asset);
    error BorrowCapExceeded();
    error InvalidInterestRateMode();
    error InsufficientLiquidity();

    struct Reserve {
        bool listed;
        DataTypes.ReserveConfigurationMap configuration;
        uint128 variableBorrowIndex; // ray
        uint40 lastUpdateTimestamp;
        MockVariableDebtToken debtToken;
    }

    mapping(address asset => Reserve) internal _reserves;
    address[] internal _reservesList;
    /// @dev Optional aToken and scaled accruedToTreasury per reserve, for SUPPLY-kind reads (added by the RVM
    ///      tests). 0 by default, so getReserveData keeps returning aTokenAddress 0 unless a test sets one.
    mapping(address asset => address) internal _aTokens;
    mapping(address asset => uint128) internal _accruedToTreasury;

    // ═══════════════════════════════════════════════════════════════════════════
    // TEST SETUP
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice List a reserve. Caps are in whole tokens, as Aave stores them. Index starts at 1 ray.
    function listReserve(
        address asset,
        uint256 decimals,
        uint256 borrowCap,
        uint256 supplyCap
    )
        external
        returns (MockVariableDebtToken debtToken)
    {
        Reserve storage r = _reserves[asset];
        r.listed = true;
        // The library setters take a memory struct, so edit a copy and write it back.
        DataTypes.ReserveConfigurationMap memory c = r.configuration;
        c.setDecimals(decimals);
        c.setActive(true);
        c.setBorrowingEnabled(true);
        c.setBorrowCap(borrowCap);
        c.setSupplyCap(supplyCap);
        r.configuration = c;
        r.variableBorrowIndex = uint128(WadRayMath.RAY);
        r.lastUpdateTimestamp = uint40(block.timestamp);
        debtToken = new MockVariableDebtToken(this, asset);
        r.debtToken = debtToken;
        _reservesList.push(asset);
    }

    /// @notice Set the borrow cap directly, as `PoolConfigurator.setBorrowCap` does: no check against
    ///         debt and no frozen or paused check (PoolConfigurator.sol:345-355).
    function setBorrowCap(address asset, uint256 cap) external {
        DataTypes.ReserveConfigurationMap memory c = _reserves[asset].configuration;
        c.setBorrowCap(cap);
        _reserves[asset].configuration = c;
    }

    function setSupplyCap(address asset, uint256 cap) external {
        DataTypes.ReserveConfigurationMap memory c = _reserves[asset].configuration;
        c.setSupplyCap(cap);
        _reserves[asset].configuration = c;
    }

    function setFrozen(address asset, bool frozen) external {
        DataTypes.ReserveConfigurationMap memory c = _reserves[asset].configuration;
        c.setFrozen(frozen);
        _reserves[asset].configuration = c;
    }

    function setPaused(address asset, bool paused) external {
        DataTypes.ReserveConfigurationMap memory c = _reserves[asset].configuration;
        c.setPaused(paused);
        _reserves[asset].configuration = c;
    }

    /// @notice Set the variable borrow index (ray). Also sets lastUpdateTimestamp to now.
    function setIndex(address asset, uint256 indexRay) external {
        _reserves[asset].variableBorrowIndex = uint128(indexRay);
        _reserves[asset].lastUpdateTimestamp = uint40(block.timestamp);
    }

    function setLastUpdateTimestamp(address asset, uint40 ts) external {
        _reserves[asset].lastUpdateTimestamp = ts;
    }

    /// @notice Set total variable debt in the underlying's smallest unit (wei for 18 decimals).
    /// @dev Stores `scaled = debtWei.rayDivFloor(index)`. At index 1 ray the total reads back exactly. At
    ///      another index it reads back `scaled.rayMulCeil(index)`, which can differ from `debtWei` by
    ///      1 unit. Use `setScaledDebt` to pin the scaled value instead.
    function setTotalDebt(address asset, uint256 debtWei) external {
        Reserve storage r = _reserves[asset];
        r.debtToken.setScaledTotal(debtWei.rayDivFloor(r.variableBorrowIndex));
    }

    /// @notice Set the aToken of a reserve (any ERC20 whose totalSupply is the supplied amount) and the scaled
    ///         accruedToTreasury. Used by SUPPLY-kind RVM reads. Normalized income is 1 ray in this mock.
    function setAToken(address asset, address aToken, uint128 accruedToTreasuryScaled) external {
        _aTokens[asset] = aToken;
        _accruedToTreasury[asset] = accruedToTreasuryScaled;
    }

    /// @notice IPool.getReserveNormalizedIncome (IPool.sol:502). The mock has no supply accrual: 1 ray.
    function getReserveNormalizedIncome(address) external pure returns (uint256) {
        return WadRayMath.RAY;
    }

    /// @notice Set the scaled total variable debt directly.
    function setScaledDebt(address asset, uint256 scaledDebt) external {
        _reserves[asset].debtToken.setScaledTotal(scaledDebt);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // IPool SURFACE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice IPool.getConfiguration (IPool.sol:484). The RVM reads the frozen flag (bit 57), the paused
    ///         flag (bit 60), the decimals (bits 48-55), the borrow cap (bits 80-115) and the supply cap
    ///         (bits 116-151) from it.
    function getConfiguration(address asset) external view returns (DataTypes.ReserveConfigurationMap memory) {
        return _reserves[asset].configuration;
    }

    /// @notice IPool.getReserveData (IPool.sol:523). Only the fields the caps oracle reads are filled:
    ///         configuration, variableBorrowIndex, lastUpdateTimestamp, variableDebtTokenAddress.
    function getReserveData(address asset) external view returns (DataTypes.ReserveDataLegacy memory data) {
        Reserve storage r = _reserves[asset];
        data.configuration = r.configuration;
        data.liquidityIndex = uint128(WadRayMath.RAY);
        data.variableBorrowIndex = r.variableBorrowIndex;
        data.lastUpdateTimestamp = r.lastUpdateTimestamp;
        data.variableDebtTokenAddress = address(r.debtToken);
        data.aTokenAddress = _aTokens[asset];
        data.accruedToTreasury = _accruedToTreasury[asset];
    }

    /// @notice IPool.getReservesList (IPool.sol:554).
    function getReservesList() external view returns (address[] memory) {
        return _reservesList;
    }

    /// @notice IPool.getReserveNormalizedVariableDebt. The mock returns the stored index (no virtual accrual).
    function getReserveNormalizedVariableDebt(address asset) external view returns (uint256) {
        return _reserves[asset].variableBorrowIndex;
    }

    /// @notice IPool.getReserveVariableDebtToken (IPool.sol:830).
    function getReserveVariableDebtToken(address asset) external view returns (address) {
        return address(_reserves[asset].debtToken);
    }

    /// @notice IPool.borrow (IPool.sol:266). Variable rate only. Checks: reserve listed, not frozen or
    ///         paused, credit delegation if `msg.sender != onBehalfOf`, and the borrow cap with the same
    ///         comparison as ValidationLogic.sol:182-189 (`totalDebt + amount <= cap * 10**decimals`, no
    ///         check when the cap is 0). Debt goes to `onBehalfOf`, the tokens go to `msg.sender`.
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16, address onBehalfOf) external {
        if (interestRateMode != 2) revert InvalidInterestRateMode();
        Reserve storage r = _reserves[asset];
        if (!r.listed) revert ReserveNotListed(asset);
        if (r.configuration.getFrozen() || r.configuration.getPaused()) revert ReserveFrozenOrPaused(asset);

        uint256 scaledAmount = amount.rayDivCeil(r.variableBorrowIndex);
        uint256 cap = r.configuration.getBorrowCap();
        if (cap != 0) {
            uint256 totalDebt = (r.debtToken.scaledTotalSupply() + scaledAmount).rayMulCeil(r.variableBorrowIndex);
            if (totalDebt > cap * 10 ** r.configuration.getDecimals()) revert BorrowCapExceeded();
        }

        if (msg.sender != onBehalfOf) r.debtToken.spendAllowance(onBehalfOf, msg.sender, amount);
        r.debtToken.mintScaled(onBehalfOf, scaledAmount);

        if (IERC20(asset).balanceOf(address(this)) < amount) revert InsufficientLiquidity();
        IERC20(asset).transfer(msg.sender, amount);
    }

    /// @notice IPool.repay (IPool.sol). Pulls `amount` (capped at the debt of `onBehalfOf`) from
    ///         `msg.sender`. Returns the repaid amount. Needs no frozen check, as in Aave.
    function repay(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        address onBehalfOf
    )
        external
        returns (uint256 repaid)
    {
        if (interestRateMode != 2) revert InvalidInterestRateMode();
        Reserve storage r = _reserves[asset];
        if (!r.listed) revert ReserveNotListed(asset);

        uint256 debt = r.debtToken.balanceOf(onBehalfOf);
        repaid = amount > debt ? debt : amount;
        r.debtToken.burnScaled(onBehalfOf, repaid.rayDivFloor(r.variableBorrowIndex));
        IERC20(asset).transferFrom(msg.sender, address(this), repaid);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // IPoolDataProvider SURFACE (the pool also serves as the data provider)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice IPoolDataProvider.getReserveCaps (AaveProtocolDataProvider.sol:119). Whole tokens.
    function getReserveCaps(address asset) external view returns (uint256 borrowCap, uint256 supplyCap) {
        (borrowCap, supplyCap) = _reserves[asset].configuration.getCaps();
    }

    /// @notice IPoolDataProvider.getPaused (AaveProtocolDataProvider.sol:126).
    function getPaused(address asset) external view returns (bool isPaused) {
        return _reserves[asset].configuration.getPaused();
    }

    /// @notice IPoolDataProvider.getTotalDebt (AaveProtocolDataProvider.sol:203): the debt token's
    ///         `totalSupply()`.
    function getTotalDebt(address asset) external view returns (uint256) {
        return _reserves[asset].debtToken.totalSupply();
    }

    /// @notice IPoolDataProvider.getReserveConfigurationData. Only `decimals`, `isActive` and `isFrozen`
    ///         and `borrowingEnabled` are meaningful. The other fields are 0 or false.
    function getReserveConfigurationData(address asset)
        external
        view
        returns (
            uint256 decimals,
            uint256 ltv,
            uint256 liquidationThreshold,
            uint256 liquidationBonus,
            uint256 reserveFactor,
            bool usageAsCollateralEnabled,
            bool borrowingEnabled,
            bool stableBorrowRateEnabled,
            bool isActive,
            bool isFrozen
        )
    {
        DataTypes.ReserveConfigurationMap memory c = _reserves[asset].configuration;
        decimals = c.getDecimals();
        borrowingEnabled = c.getBorrowingEnabled();
        isActive = c.getActive();
        isFrozen = c.getFrozen();
        ltv = 0;
        liquidationThreshold = 0;
        liquidationBonus = 0;
        reserveFactor = 0;
        usageAsCollateralEnabled = false;
        stableBorrowRateEnabled = false;
    }

    /// @notice IPoolDataProvider.getReserveTokensAddresses. aToken and stable debt token are 0.
    function getReserveTokensAddresses(address asset)
        external
        view
        returns (address aTokenAddress, address stableDebtTokenAddress, address variableDebtTokenAddress)
    {
        return (address(0), address(0), address(_reserves[asset].debtToken));
    }
}

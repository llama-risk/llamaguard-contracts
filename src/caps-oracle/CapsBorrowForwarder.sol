// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IPool } from "aave-v3-origin/src/contracts/interfaces/IPool.sol";
import { DataTypes } from "aave-v3-origin/src/contracts/protocol/libraries/types/DataTypes.sol";
import {
    ReserveConfiguration
} from "aave-v3-origin/src/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import {
    IAaveV3ConfigEngine as IEngine
} from "aave-v3-origin/src/contracts/extensions/v3-config-engine/IAaveV3ConfigEngine.sol";
import { EngineFlags } from "aave-v3-origin/src/contracts/extensions/v3-config-engine/EngineFlags.sol";
import { ICapsBorrowForwarder } from "./interfaces/ICapsBorrowForwarder.sol";
import { ICapsRangeValidationModule } from "./interfaces/ICapsRangeValidationModule.sol";
import { IRiskSteward } from "aave-v3-risk-stewards/interfaces/IRiskSteward.sol";

/// @title CapsBorrowForwarder
/// @notice Raises an Aave V3 borrow cap through the Risk Steward and borrows in one transaction, with the
///         debt on the borrower. The Risk Council Safe calls `raiseCapAndBorrow` by delegatecall, which raises
///         the cap as the Safe and then calls `borrowFor` on this deployed contract. The borrower delegates credit
///         to this contract, so the borrowed tokens can only reach the borrower.
/// @dev No storage. The immutables are read from code, so they resolve inside the delegatecall.
contract CapsBorrowForwarder is ICapsBorrowForwarder {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using SafeERC20 for IERC20;

    /// @notice Variable interest rate mode for `IPool.borrow`.
    uint256 internal constant VARIABLE_RATE_MODE = 2;

    /// @inheritdoc ICapsBorrowForwarder
    address public immutable POOL;

    /// @inheritdoc ICapsBorrowForwarder
    address public immutable RISK_STEWARD;

    /// @inheritdoc ICapsBorrowForwarder
    address public immutable RISK_COUNCIL;

    /// @inheritdoc ICapsBorrowForwarder
    address public immutable RVM;

    /// @inheritdoc ICapsBorrowForwarder
    address public immutable SELF;

    /// @param pool the Aave V3 Pool
    /// @param riskSteward the Risk Steward whose `RISK_COUNCIL` is `riskCouncil`
    /// @param riskCouncil the Risk Council Safe, the only context in which `raiseCapAndBorrow` runs
    /// @param rvm the rate-limiter RVM of the Pool, whose borrow `maxCap` bounds the new cap
    /// @dev Reverts InvalidInput on a zero address, when the Steward's `POOL()` or `RISK_COUNCIL()` differs, or
    ///      when the RVM's `POOL()` differs.
    constructor(address pool, address riskSteward, address riskCouncil, address rvm) {
        if (pool == address(0) || riskSteward == address(0) || riskCouncil == address(0) || rvm == address(0)) {
            revert InvalidInput();
        }
        if (
            address(IRiskSteward(riskSteward).POOL()) != pool || IRiskSteward(riskSteward).RISK_COUNCIL() != riskCouncil
                || ICapsRangeValidationModule(rvm).POOL() != pool
        ) {
            revert InvalidInput();
        }
        POOL = pool;
        RISK_STEWARD = riskSteward;
        RISK_COUNCIL = riskCouncil;
        RVM = rvm;
        SELF = address(this);
    }

    /// @inheritdoc ICapsBorrowForwarder
    function raiseCapAndBorrow(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint256 extraCapTokens,
        uint256 maxNewCap
    )
        external
    {
        // 1. Only the Risk Council Safe's context, with valid inputs.
        if (address(this) != RISK_COUNCIL) revert NotRiskCouncilContext(address(this));
        if (amount == 0 || onBehalfOf == address(0) || onBehalfOf == RISK_COUNCIL) revert InvalidInput();

        // 2. Read the live borrow cap and decimals.
        DataTypes.ReserveConfigurationMap memory config = IPool(POOL).getConfiguration(asset);
        uint256 oldCap = config.getBorrowCap();
        if (oldCap == 0) revert BorrowCapNotSet(asset);

        // 3. newCap = the larger of the live cap and the debt, plus the amount and extraCapTokens, at most
        //    maxNewCap. Whole tokens, the debt and the amount rounded up. Starting from the debt keeps room for
        //    the amount when accrued interest has pushed the debt above the cap.
        uint256 newCap = _newCap(asset, oldCap, config.getDecimals(), amount, extraCapTokens);
        if (newCap > maxNewCap) revert NewCapAboveMax(newCap, maxNewCap);

        // 4. At most the RVM max cap, so a later cut never sets the cap below the debt. 0: no rate limit entry.
        uint256 maxCap =
            ICapsRangeValidationModule(RVM).getKeyState(asset, ICapsRangeValidationModule.CapKind.BORROW).maxCap;
        if (maxCap != 0 && newCap > maxCap) revert NewCapAboveMaxCap(newCap, maxCap);

        // 5. Raise the borrow cap through the Risk Steward, which sees the Safe as caller.
        IEngine.CapsUpdate[] memory updates = new IEngine.CapsUpdate[](1);
        updates[0] = IEngine.CapsUpdate({ asset: asset, supplyCap: EngineFlags.KEEP_CURRENT, borrowCap: newCap });
        IRiskSteward(RISK_STEWARD).updateCaps(updates);

        // 6. Borrow through the deployed forwarder, which holds the borrower's credit delegation and sends the
        //    tokens to the borrower. No token passes through the Safe.
        ICapsBorrowForwarder(SELF).borrowFor(asset, amount, onBehalfOf);

        emit CapRaisedAndBorrowed(asset, onBehalfOf, amount, oldCap, newCap);
    }

    /// @inheritdoc ICapsBorrowForwarder
    function borrowFor(address asset, uint256 amount, address onBehalfOf) external {
        // 1. Only a plain call from the Risk Council Safe, with valid inputs.
        if (address(this) != SELF) revert NotDirectCall(address(this));
        if (msg.sender != RISK_COUNCIL) revert NotRiskCouncil(msg.sender);
        if (amount == 0 || onBehalfOf == address(0) || onBehalfOf == RISK_COUNCIL || onBehalfOf == SELF) {
            revert InvalidInput();
        }

        // 2. Borrow with the debt on the borrower, under its credit delegation to this contract. The Pool sends
        //    the tokens here.
        uint256 balanceBefore = IERC20(asset).balanceOf(address(this));
        // The balance check around the borrow is the point: any balance change, re-entrant or not, reverts.
        IPool(POOL).borrow(asset, amount, VARIABLE_RATE_MODE, 0, onBehalfOf);

        // 3. Send the tokens to the borrower and require this contract to keep nothing.
        IERC20(asset).safeTransfer(onBehalfOf, amount);
        uint256 balanceAfter = IERC20(asset).balanceOf(address(this));
        if (balanceAfter != balanceBefore) revert ForwarderBalanceChanged(balanceBefore, balanceAfter);

        emit BorrowedFor(asset, onBehalfOf, amount);
    }

    /// @dev max(live cap, debt) + amount + extraCapTokens, in whole tokens. The debt and the amount round up.
    function _newCap(
        address asset,
        uint256 oldCap,
        uint256 decimals,
        uint256 amount,
        uint256 extraCapTokens
    )
        internal
        view
        returns (uint256)
    {
        uint256 unit = 10 ** decimals;
        uint256 debt =
            Math.ceilDiv(IERC20(IPool(POOL).getReserveData(asset).variableDebtTokenAddress).totalSupply(), unit);
        return Math.max(oldCap, debt) + Math.ceilDiv(amount, unit) + extraCapTokens;
    }
}

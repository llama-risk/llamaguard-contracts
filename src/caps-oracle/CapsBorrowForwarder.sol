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
import { IRiskSteward } from "aave-v3-risk-stewards/interfaces/IRiskSteward.sol";

/// @title CapsBorrowForwarder
/// @notice Raises an Aave V3 borrow cap through the Risk Steward and borrows in one transaction, with the
///         debt on the borrower. The Risk Council Safe calls `raiseCapAndBorrow` by delegatecall.
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

    /// @param pool the Aave V3 Pool
    /// @param riskSteward the Risk Steward whose `RISK_COUNCIL` is `riskCouncil`
    /// @param riskCouncil the Risk Council Safe, the only context in which `raiseCapAndBorrow` runs
    /// @dev Reverts InvalidInput on a zero address, or when the Steward's `POOL()` or `RISK_COUNCIL()` differs.
    constructor(address pool, address riskSteward, address riskCouncil) {
        if (pool == address(0) || riskSteward == address(0) || riskCouncil == address(0)) revert InvalidInput();
        if (
            address(IRiskSteward(riskSteward).POOL()) != pool || IRiskSteward(riskSteward).RISK_COUNCIL() != riskCouncil
        ) {
            revert InvalidInput();
        }
        POOL = pool;
        RISK_STEWARD = riskSteward;
        RISK_COUNCIL = riskCouncil;
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

        // 3. newCap = live cap + amount in whole tokens (rounded up) + extraCapTokens, at most maxNewCap.
        uint256 newCap = oldCap + Math.ceilDiv(amount, 10 ** config.getDecimals()) + extraCapTokens;
        if (newCap > maxNewCap) revert NewCapAboveMax(newCap, maxNewCap);

        // 4. Raise the borrow cap through the Risk Steward, which sees the Safe as caller.
        IEngine.CapsUpdate[] memory updates = new IEngine.CapsUpdate[](1);
        updates[0] = IEngine.CapsUpdate({ asset: asset, supplyCap: EngineFlags.KEEP_CURRENT, borrowCap: newCap });
        IRiskSteward(RISK_STEWARD).updateCaps(updates);

        // 5. Borrow with the debt on the borrower. The Pool sends the tokens to the Safe.
        uint256 balanceBefore = IERC20(asset).balanceOf(address(this));
        IPool(POOL).borrow(asset, amount, VARIABLE_RATE_MODE, 0, onBehalfOf);

        // 6. Send the tokens to the borrower and require the Safe to keep nothing.
        IERC20(asset).safeTransfer(onBehalfOf, amount);
        uint256 balanceAfter = IERC20(asset).balanceOf(address(this));
        if (balanceAfter != balanceBefore) revert SafeBalanceChanged(balanceBefore, balanceAfter);

        emit CapRaisedAndBorrowed(asset, onBehalfOf, amount, oldCap, newCap);
    }
}

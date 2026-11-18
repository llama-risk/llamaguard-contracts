// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { Ownable, Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IPool } from "aave-v3-origin/src/contracts/interfaces/IPool.sol";
import { ICreditDelegationToken } from "aave-v3-origin/src/contracts/interfaces/ICreditDelegationToken.sol";
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

/// @title CapsBorrowForwarder
/// @notice Raises an Aave V3 borrow cap and borrows for a borrower in one transaction. Holds RISK_ADMIN and
///         the borrowers' credit delegations. Borrowed tokens only reach the borrower.
contract CapsBorrowForwarder is ICapsBorrowForwarder, Ownable2Step, ReentrancyGuard {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using SafeERC20 for IERC20;

    uint256 internal constant VARIABLE_RATE_MODE = 2;
    uint256 internal constant BPS = 10_000;
    /// @dev Cap 1 is Aave's manual freeze of borrowing.
    uint256 internal constant FROZEN_CAP = 1;
    uint256 internal constant ROUNDING_BUFFER = 1;
    uint256 internal constant MAX_BATCH_SIZE = 20;

    /// @inheritdoc ICapsBorrowForwarder
    address public immutable POOL;

    /// @inheritdoc ICapsBorrowForwarder
    address public immutable CONFIG_ENGINE;

    /// @inheritdoc ICapsBorrowForwarder
    address public immutable RVM;

    /// @inheritdoc ICapsBorrowForwarder
    mapping(address account => bool allowed) public isCaller;

    /// @inheritdoc ICapsBorrowForwarder
    uint256 public maxRaiseBps;

    /// @inheritdoc ICapsBorrowForwarder
    uint256 public minRaiseDelay;

    /// @inheritdoc ICapsBorrowForwarder
    mapping(address asset => uint256 timestamp) public lastRaiseAt;

    modifier onlyCaller() {
        _checkCaller();
        _;
    }

    /// @param owner_ same owner as the AgentHub
    /// @param pool Aave V3 Pool
    /// @param configEngine config engine of the Pool
    /// @param rvm caps RVM of the Pool
    /// @param caller initial allowlisted caller
    /// @param maxRaiseBps_ max increase per raise, bps of the live cap
    /// @param minRaiseDelay_ min seconds between raises of one asset
    constructor(
        address owner_,
        address pool,
        address configEngine,
        address rvm,
        address caller,
        uint256 maxRaiseBps_,
        uint256 minRaiseDelay_
    )
        Ownable(owner_)
    {
        if (pool == address(0) || configEngine == address(0) || rvm == address(0)) revert InvalidInput();
        if (ICapsRangeValidationModule(rvm).POOL() != pool) revert InvalidInput();
        if (address(IEngine(configEngine).POOL()) != pool) revert InvalidInput();
        if (
            address(IEngine(configEngine).POOL_CONFIGURATOR()) != IPool(pool).ADDRESSES_PROVIDER().getPoolConfigurator()
        ) {
            revert InvalidInput();
        }
        POOL = pool;
        CONFIG_ENGINE = configEngine;
        RVM = rvm;
        _setCaller(caller, true);
        _setLimits(maxRaiseBps_, minRaiseDelay_);
    }

    /// @inheritdoc ICapsBorrowForwarder
    function raiseCapAndBorrow(address asset, uint256 amount, address onBehalfOf) external nonReentrant onlyCaller {
        _checkBorrow(amount, onBehalfOf);
        (uint256 oldCap, uint256 newCap) = _raiseCap(asset, amount);
        _borrowFor(asset, amount, onBehalfOf);
        emit CapRaisedAndBorrowed(asset, onBehalfOf, amount, oldCap, newCap);
    }

    /// @inheritdoc ICapsBorrowForwarder
    function raiseCapAndBorrowBatch(address asset, BorrowRequest[] calldata requests) external nonReentrant onlyCaller {
        uint256 count = requests.length;
        if (count == 0 || count > MAX_BATCH_SIZE) revert InvalidInput();

        uint256 total = 0;
        for (uint256 i; i < count; ++i) {
            _checkBorrow(requests[i].amount, requests[i].onBehalfOf);
            total += requests[i].amount;
        }

        // One raise for the sum, then one borrow per request. Any failure reverts the whole batch.
        (uint256 oldCap, uint256 newCap) = _raiseCap(asset, total);
        for (uint256 i; i < count; ++i) {
            _borrowFor(asset, requests[i].amount, requests[i].onBehalfOf);
            emit CapRaisedAndBorrowed(asset, requests[i].onBehalfOf, requests[i].amount, oldCap, newCap);
        }
    }

    /// @inheritdoc ICapsBorrowForwarder
    function setCaller(address account, bool allowed) external onlyOwner {
        _setCaller(account, allowed);
    }

    /// @inheritdoc ICapsBorrowForwarder
    function setLimits(uint256 maxRaiseBps_, uint256 minRaiseDelay_) external onlyOwner {
        _setLimits(maxRaiseBps_, minRaiseDelay_);
    }

    /// @dev Disabled.
    function renounceOwnership() public view override onlyOwner {
        revert NotSupported();
    }

    function _checkCaller() internal view {
        if (!isCaller[msg.sender]) revert NotCaller(msg.sender);
    }

    function _checkBorrow(uint256 amount, address onBehalfOf) internal view {
        if (amount == 0 || onBehalfOf == address(0) || onBehalfOf == address(this) || onBehalfOf == msg.sender) {
            revert InvalidInput();
        }
    }

    /// @dev Checks the delay and the limits, then raises the borrow cap to cover `amount`.
    function _raiseCap(address asset, uint256 amount) internal returns (uint256 oldCap, uint256 newCap) {
        uint256 nextRaiseAt = lastRaiseAt[asset] + minRaiseDelay;
        if (lastRaiseAt[asset] != 0 && block.timestamp < nextRaiseAt) revert RaiseTooSoon(asset, nextRaiseAt);
        lastRaiseAt[asset] = block.timestamp;

        (oldCap, newCap) = _checkedNewCap(asset, amount);

        // The engine runs by delegatecall, so the PoolConfigurator sees this contract (RISK_ADMIN).
        IEngine.CapsUpdate[] memory updates = new IEngine.CapsUpdate[](1);
        updates[0] = IEngine.CapsUpdate({ asset: asset, supplyCap: EngineFlags.KEEP_CURRENT, borrowCap: newCap });
        Address.functionDelegateCall(CONFIG_ENGINE, abi.encodeCall(IEngine.updateCaps, (updates)));
    }

    function _setCaller(address account, bool allowed) internal {
        if (account == address(0)) revert InvalidInput();
        isCaller[account] = allowed;
        emit CallerSet(account, allowed);
    }

    function _setLimits(uint256 maxRaiseBps_, uint256 minRaiseDelay_) internal {
        if (maxRaiseBps_ == 0 || minRaiseDelay_ == 0) revert InvalidInput();
        maxRaiseBps = maxRaiseBps_;
        minRaiseDelay = minRaiseDelay_;
        emit LimitsSet(maxRaiseBps_, minRaiseDelay_);
    }

    /// @dev Live cap and new cap, after the RVM `maxCap` and `maxRaiseBps` checks.
    function _checkedNewCap(address asset, uint256 amount) internal view returns (uint256 oldCap, uint256 newCap) {
        DataTypes.ReserveConfigurationMap memory config = IPool(POOL).getConfiguration(asset);
        oldCap = config.getBorrowCap();
        if (oldCap == 0) revert BorrowCapNotSet(asset);
        if (oldCap == FROZEN_CAP) revert BorrowCapFrozen(asset);

        newCap = _newCap(asset, oldCap, config.getDecimals(), amount);

        // An asset with no RVM entry has maxCap 0 and always reverts here.
        uint256 maxCap =
            ICapsRangeValidationModule(RVM).getKeyState(asset, ICapsRangeValidationModule.CapKind.BORROW).maxCap;
        if (newCap > maxCap) revert NewCapAboveMaxCap(newCap, maxCap);

        uint256 maxIncrease = oldCap * maxRaiseBps / BPS;
        if (newCap - oldCap > maxIncrease) revert RaiseAboveLimit(newCap - oldCap, maxIncrease);
    }

    /// @dev Borrows under the borrower's delegation, forwards the tokens, then renounces the rest of the delegation.
    function _borrowFor(address asset, uint256 amount, address onBehalfOf) internal {
        ICreditDelegationToken debtToken =
            ICreditDelegationToken(IPool(POOL).getReserveData(asset).variableDebtTokenAddress);
        uint256 balanceBefore = IERC20(asset).balanceOf(address(this));
        IPool(POOL).borrow(asset, amount, VARIABLE_RATE_MODE, 0, onBehalfOf);
        IERC20(asset).safeTransfer(onBehalfOf, amount);
        uint256 balanceAfter = IERC20(asset).balanceOf(address(this));
        if (balanceAfter != balanceBefore) revert ForwarderBalanceChanged(balanceBefore, balanceAfter);

        debtToken.renounceDelegation(onBehalfOf);
    }

    /// @dev max(live cap, debt) + amount + 1, whole tokens, debt and amount rounded up.
    function _newCap(address asset, uint256 oldCap, uint256 decimals, uint256 amount) internal view returns (uint256) {
        uint256 unit = 10 ** decimals;
        uint256 debt =
            Math.ceilDiv(IERC20(IPool(POOL).getReserveData(asset).variableDebtTokenAddress).totalSupply(), unit);
        // +1 token: Aave rounds the new debt up, which can land 1 unit above an exact cap.
        return Math.max(oldCap, debt) + Math.ceilDiv(amount, unit) + ROUNDING_BUFFER;
    }
}

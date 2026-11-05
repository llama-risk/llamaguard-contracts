// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IPool } from "aave-v3-origin/src/contracts/interfaces/IPool.sol";
import { DataTypes } from "aave-v3-origin/src/contracts/protocol/libraries/types/DataTypes.sol";
import {
    ReserveConfiguration
} from "aave-v3-origin/src/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import { PercentageMath } from "aave-v3-origin/src/contracts/protocol/libraries/math/PercentageMath.sol";
import { WadRayMath } from "aave-v3-origin/src/contracts/protocol/libraries/math/WadRayMath.sol";
import { IAgentConfigurator } from "chaos-agents/interfaces/IAgentConfigurator.sol";
import { IBaseAgent } from "chaos-agents/interfaces/IBaseAgent.sol";
import { IRangeValidationModule } from "chaos-agents/interfaces/IRangeValidationModule.sol";
import { ICapsRangeValidationModule } from "./interfaces/ICapsRangeValidationModule.sol";
import { IAaveCapAgent } from "./interfaces/IAaveCapAgent.sol";

/**
 * @title CapsRangeValidationModuleV3
 * @notice Rate-limiter RVM for the borrow and supply caps of one Aave V3 Pool.
 * @dev Rule, in whole tokens, with alpha and band clamped to the global limits of the kind:
 *        L     = max(ceil(maxHeadroom / 25), min(maxHeadroom, alpha * D))
 *        raise : not frozen or paused, cap < to <= min(D + L, C-bar, S)
 *        lo    = min(max(min(D + L, S), D), C-bar)
 *        hi    = max(min(D + (1 + band) * L, C-bar, S), lo)
 *        cut   : cap > hi, lo <= to <= hi, no active hold
 *      D and the floor of L round up, everything else rounds down. `validate` and the previews never revert
 *      on a rule failure.
 */
contract CapsRangeValidationModuleV3 is ICapsRangeValidationModule, Ownable2Step {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    /// @inheritdoc ICapsRangeValidationModule
    uint256 public constant MAX_HOLD_DURATION = 24 hours;

    /// @dev Floor of L = ceilDiv(maxHeadroom, MIN_HEADROOM_DIVISOR). A live entry has maxHeadroom > 0, so L >= 1.
    uint256 internal constant MIN_HEADROOM_DIVISOR = 25;

    /// @dev Largest cap Aave stores, 36 bits. The borrow and supply limits are equal.
    uint256 internal constant MAX_VALID_CAP = ReserveConfiguration.MAX_VALID_BORROW_CAP;

    /// @dev Saturation of D, so that D + L never overflows.
    uint256 internal constant MAX_USAGE = type(uint128).max;

    /// @dev Above this, 10 ** decimals times a cap could overflow, so the reserve reads as uncapped.
    uint256 internal constant MAX_DECIMALS = 60;

    /// @inheritdoc ICapsRangeValidationModule
    address public immutable AGENT_HUB;

    /// @inheritdoc ICapsRangeValidationModule
    address public immutable POOL;

    /// @inheritdoc ICapsRangeValidationModule
    bytes32 public immutable BORROW_UPDATE_TYPE_HASH;

    /// @inheritdoc ICapsRangeValidationModule
    bytes32 public immutable SUPPLY_UPDATE_TYPE_HASH;

    /// @inheritdoc ICapsRangeValidationModule
    address public riskCouncil;

    mapping(uint256 agentId => AgentConfig) internal _agents;
    mapping(CapKind kind => Bounds) internal _bounds;
    mapping(address asset => mapping(CapKind kind => KeyState)) internal _keys;

    /**
     * @param owner_ the governance executor
     * @param agentHub the only AgentHub this RVM serves
     * @param pool the only Aave V3 Pool this RVM serves
     * @param riskCouncil_ the Risk Council Safe
     * @param borrowUpdateType the full update type of the BORROW agents, for example `BorrowCapUpdate_Core`
     * @param supplyUpdateType the full update type of the SUPPLY agents, for example `SupplyCapUpdate_Core`
     */
    constructor(
        address owner_,
        address agentHub,
        address pool,
        address riskCouncil_,
        string memory borrowUpdateType,
        string memory supplyUpdateType
    )
        Ownable(owner_)
    {
        if (agentHub == address(0) || pool == address(0) || riskCouncil_ == address(0)) revert ZeroAddress();
        bytes32 borrowHash = keccak256(bytes(borrowUpdateType));
        bytes32 supplyHash = keccak256(bytes(supplyUpdateType));
        if (bytes(borrowUpdateType).length == 0 || bytes(supplyUpdateType).length == 0 || borrowHash == supplyHash) {
            revert InvalidUpdateTypes();
        }
        AGENT_HUB = agentHub;
        POOL = pool;
        BORROW_UPDATE_TYPE_HASH = borrowHash;
        SUPPLY_UPDATE_TYPE_HASH = supplyHash;
        riskCouncil = riskCouncil_;
        emit RiskCouncilChanged(address(0), riskCouncil_);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VALIDATION (IRangeValidationModule)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc IRangeValidationModule
    /// @dev `market` is the asset address, as in AgentHub and the agents.
    function validate(
        address agentHub,
        uint256 agentId,
        address market,
        RangeValidationInput calldata input
    )
        external
        view
        returns (bool)
    {
        if (agentHub != AGENT_HUB || input.from == 0 || input.to == 0) return false;
        AgentConfig memory a = _agents[agentId];
        if (a.direction == Direction.NONE) return false;
        (bool ok, ReserveState memory s) = _keyContext(market, a.kind);
        if (!ok || input.from != s.cap) return false;
        return a.direction == Direction.RAISE ? _raiseOk(s, input.to) : _cutOk(s, input.to);
    }

    /// @inheritdoc IRangeValidationModule
    /// @dev Cap agents never batch, so every batch is rejected.
    function validate(address, uint256, address, RangeValidationInput[] calldata) external pure returns (bool) {
        return false;
    }

    /// @inheritdoc ICapsRangeValidationModule
    function previewRaise(
        address asset,
        CapKind kind
    )
        external
        view
        returns (bool allowed, uint256 currentCap, uint256 newCap)
    {
        (bool ok, ReserveState memory s) = _keyContext(asset, kind);
        if (!ok) return (false, 0, 0);
        currentCap = s.cap;
        if (_raiseOk(s, s.raiseCap)) return (true, currentCap, s.raiseCap);
    }

    /// @inheritdoc ICapsRangeValidationModule
    function previewCut(
        address asset,
        CapKind kind
    )
        external
        view
        returns (bool due, uint256 currentCap, uint256 newCap)
    {
        (bool ok, ReserveState memory s) = _keyContext(asset, kind);
        if (!ok) return (false, 0, 0);
        currentCap = s.cap;
        if (_cutOk(s, s.cutFloor)) return (true, currentCap, s.cutFloor);
    }

    /// @inheritdoc ICapsRangeValidationModule
    function getReserveState(address asset, CapKind kind) external view returns (ReserveState memory s) {
        bool ok;
        (ok, s) = _keyContext(asset, kind);
        if (!ok) revert RateLimitConfigNotFound(asset, kind);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // IRangeValidationModule: range configs are not used by this module
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc IRangeValidationModule
    function setDefaultRangeConfig(address, uint256, string calldata, RangeConfig calldata) external pure {
        revert NotSupported();
    }

    /// @inheritdoc IRangeValidationModule
    function setRangeConfigByMarket(address, uint256, address, string calldata, RangeConfig calldata) external pure {
        revert NotSupported();
    }

    /// @inheritdoc IRangeValidationModule
    function getDefaultRangeConfig(address, uint256, string calldata) external pure returns (RangeConfig memory) { }

    /// @inheritdoc IRangeValidationModule
    function getRangeConfigByMarket(
        address,
        uint256,
        address,
        string calldata
    )
        external
        pure
        returns (RangeConfig memory)
    { }

    // ═══════════════════════════════════════════════════════════════════════════
    // OWNER
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc ICapsRangeValidationModule
    function setAgent(uint256 agentId, Direction direction) external onlyOwner {
        if (direction == Direction.NONE) {
            CapKind oldKind = _agents[agentId].kind;
            delete _agents[agentId];
            emit AgentSet(agentId, Direction.NONE, oldKind);
            return;
        }

        address agent;
        try IAgentConfigurator(AGENT_HUB).getAgentAddress(agentId) returns (address a) {
            agent = a;
        } catch {
            revert InvalidAgent(agentId);
        }
        if (
            agent.code.length == 0 || _readAddress(agent, IBaseAgent.AGENT_HUB.selector) != AGENT_HUB
                || _readAddress(agent, IAaveCapAgent.RANGE_VALIDATION_MODULE.selector) != address(this)
                || _readAddress(agent, IAaveCapAgent.POOL.selector) != POOL
        ) revert InvalidAgent(agentId);

        bytes32 typeHash;
        try IAgentConfigurator(AGENT_HUB).getUpdateType(agentId) returns (string memory updateType) {
            typeHash = keccak256(bytes(updateType));
        } catch {
            revert InvalidAgent(agentId);
        }
        CapKind kind;
        if (typeHash == BORROW_UPDATE_TYPE_HASH) kind = CapKind.BORROW;
        else if (typeHash == SUPPLY_UPDATE_TYPE_HASH) kind = CapKind.SUPPLY;
        else revert InvalidAgent(agentId);

        _agents[agentId] = AgentConfig({ direction: direction, kind: kind });
        emit AgentSet(agentId, direction, kind);
    }

    /// @inheritdoc ICapsRangeValidationModule
    function setBounds(CapKind kind, Bounds calldata bounds) external onlyOwner {
        uint256 pf = PercentageMath.PERCENTAGE_FACTOR;
        if (bounds.alphaBpsLimit > pf || bounds.cutBandBpsLimit > pf || bounds.maxIncreaseBps > pf) {
            revert InvalidBounds();
        }
        _bounds[kind] = bounds;
        emit BoundsSet(kind, bounds);
    }

    /// @inheritdoc ICapsRangeValidationModule
    function setRiskCouncil(address riskCouncil_) external onlyOwner {
        if (riskCouncil_ == address(0)) revert ZeroAddress();
        emit RiskCouncilChanged(riskCouncil, riskCouncil_);
        riskCouncil = riskCouncil_;
    }

    /// @notice Disabled: the RVM always has a governance owner.
    function renounceOwnership() public view override onlyOwner {
        revert NotSupported();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // OWNER OR RISK COUNCIL SAFE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc ICapsRangeValidationModule
    function setRateLimitConfig(address asset, CapKind kind, RateLimitConfig calldata rateLimitConfig) external {
        bool isOwner = msg.sender == owner();
        if (!isOwner && msg.sender != riskCouncil) revert OnlyRiskCouncilOrOwner(msg.sender);

        KeyState storage k = _keys[asset][kind];
        if (rateLimitConfig.maxCap == 0) {
            delete _keys[asset][kind];
            emit RateLimitConfigSet(asset, kind, rateLimitConfig, msg.sender);
            return;
        }

        if (!isOwner && k.maxCap == 0) revert RateLimitConfigNotFound(asset, kind);
        Bounds memory b = _bounds[kind];
        if (
            rateLimitConfig.alphaBps > b.alphaBpsLimit || rateLimitConfig.cutBandBps > b.cutBandBpsLimit
                || rateLimitConfig.maxHeadroom == 0 || rateLimitConfig.maxCap > MAX_VALID_CAP
        ) {
            revert RateLimitConfigOutOfBounds();
        }

        if (!isOwner) {
            bool raisesCap = _checkIncrease(k.maxCap, rateLimitConfig.maxCap, b.maxIncreaseBps);
            bool raisesHeadroom = _checkIncrease(k.maxHeadroom, rateLimitConfig.maxHeadroom, b.maxIncreaseBps);
            if (raisesCap || raisesHeadroom) {
                uint256 nextIncreaseAt = uint256(k.lastIncreaseAt) + b.cooldown;
                if (block.timestamp < nextIncreaseAt) revert CooldownActive(nextIncreaseAt);
                k.lastIncreaseAt = uint40(block.timestamp);
            }
        }

        k.maxCap = rateLimitConfig.maxCap;
        k.maxHeadroom = rateLimitConfig.maxHeadroom;
        k.alphaBps = rateLimitConfig.alphaBps;
        k.cutBandBps = rateLimitConfig.cutBandBps;
        emit RateLimitConfigSet(asset, kind, rateLimitConfig, msg.sender);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // RISK COUNCIL SAFE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc ICapsRangeValidationModule
    function setHold(address asset, CapKind kind, uint40 until) external {
        if (msg.sender != riskCouncil) revert OnlyRiskCouncil(msg.sender);
        KeyState storage k = _keys[asset][kind];
        if (k.maxCap == 0) revert RateLimitConfigNotFound(asset, kind);
        uint256 maxUntil = block.timestamp + MAX_HOLD_DURATION;
        if (until > maxUntil) revert HoldTooLong(until, maxUntil);
        k.holdUntil = until;
        emit HoldSet(asset, kind, until);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GETTERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc ICapsRangeValidationModule
    function getAgent(uint256 agentId) external view returns (AgentConfig memory) {
        return _agents[agentId];
    }

    /// @inheritdoc ICapsRangeValidationModule
    function getKeyState(address asset, CapKind kind) external view returns (KeyState memory) {
        return _keys[asset][kind];
    }

    /// @inheritdoc ICapsRangeValidationModule
    function getBounds(CapKind kind) external view returns (Bounds memory) {
        return _bounds[kind];
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // RULE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Raise: not frozen or paused, up only, at most the raise cap. The hold does not apply.
    function _raiseOk(ReserveState memory s, uint256 to) internal pure returns (bool) {
        return s.cap != 0 && !s.raiseBlocked && to > s.cap && to <= s.raiseCap;
    }

    /// @dev Cut: cap above the band, lands inside [cutFloor, cutTrigger], no active hold.
    function _cutOk(ReserveState memory s, uint256 to) internal view returns (bool) {
        return s.cap != 0 && s.cutFloor != 0 && s.cap > s.cutTrigger && to >= s.cutFloor && to <= s.cutTrigger
            && block.timestamp >= s.holdUntil;
    }

    /**
     * @dev Reads the key and the reserve and computes the rule. Never reverts on a missing entry.
     * @return ok false if the key has no entry
     * @return s the live state
     */
    function _keyContext(address asset, CapKind kind) internal view returns (bool ok, ReserveState memory s) {
        KeyState memory k = _keys[asset][kind];
        if (k.maxCap == 0) return (false, s);
        Bounds memory b = _bounds[kind];

        _readReserve(asset, kind, s);
        uint256 d = Math.min(s.usage, MAX_USAGE);
        uint256 supplyBound = Math.min(s.supplyBound, MAX_VALID_CAP);
        uint256 maxCap = Math.min(k.maxCap, MAX_VALID_CAP);
        uint256 l = Math.max(
            Math.ceilDiv(k.maxHeadroom, MIN_HEADROOM_DIVISOR),
            Math.min(k.maxHeadroom, d.percentMulFloor(Math.min(k.alphaBps, b.alphaBpsLimit)))
        );
        uint256 dPlusL = d + l;
        uint256 bandTop = dPlusL + l.percentMulFloor(Math.min(k.cutBandBps, b.cutBandBpsLimit));

        s.usage = d;
        s.supplyBound = supplyBound;
        s.maxCap = maxCap;
        s.holdUntil = k.holdUntil;
        s.headroomTarget = l;
        s.raiseCap = Math.min(Math.min(dPlusL, maxCap), supplyBound);
        s.cutFloor = Math.min(Math.max(Math.min(dPlusL, supplyBound), d), maxCap);
        s.cutTrigger = Math.max(Math.min(Math.min(bandTop, maxCap), supplyBound), s.cutFloor);
        ok = true;
    }

    /**
     * @dev Fills cap, usage D, supply bound S and raiseBlocked of `s` from the Pool. D rounds up to whole
     *      tokens: BORROW is the variable debt, SUPPLY the aToken supply plus the accrued treasury. S is the
     *      supply cap for BORROW and MAX_VALID_CAP for SUPPLY or an uncapped supply. An unreadable reserve leaves
     *      cap 0, so every check fails.
     */
    function _readReserve(address asset, CapKind kind, ReserveState memory s) internal view {
        DataTypes.ReserveConfigurationMap memory config = IPool(POOL).getConfiguration(asset);
        uint256 decimals = config.getDecimals();
        if (decimals > MAX_DECIMALS) return;
        uint256 unit = 10 ** decimals;
        DataTypes.ReserveDataLegacy memory data = IPool(POOL).getReserveData(asset);

        if (kind == CapKind.BORROW) {
            if (data.variableDebtTokenAddress == address(0)) return;
            s.cap = config.getBorrowCap();
            s.usage = Math.ceilDiv(IERC20(data.variableDebtTokenAddress).totalSupply(), unit);
            uint256 supplyCap = config.getSupplyCap();
            s.supplyBound = supplyCap == 0 ? MAX_VALID_CAP : supplyCap;
        } else {
            if (data.aTokenAddress == address(0)) return;
            s.cap = config.getSupplyCap();
            uint256 treasury = uint256(data.accruedToTreasury).rayMul(IPool(POOL).getReserveNormalizedIncome(asset));
            s.usage = Math.ceilDiv(IERC20(data.aTokenAddress).totalSupply() + treasury, unit);
            s.supplyBound = MAX_VALID_CAP;
        }
        s.raiseBlocked = config.getFrozen() || config.getPaused();
    }

    /**
     * @dev Checks a Risk Council change of a token field against the relative limit. Reverts IncreaseTooLarge.
     * @return raised true if `newValue` is above `oldValue`
     */
    function _checkIncrease(uint256 oldValue, uint256 newValue, uint256 increaseBps) internal pure returns (bool) {
        if (newValue <= oldValue) return false;
        uint256 limit = oldValue.percentMulFloor(PercentageMath.PERCENTAGE_FACTOR + increaseBps);
        if (newValue > limit) revert IncreaseTooLarge(newValue, limit);
        return true;
    }

    /// @dev Address returned by a no-argument view of `target`, or 0 if the call fails or returns no word.
    function _readAddress(address target, bytes4 selector) internal view returns (address a) {
        (bool ok, bytes memory ret) = target.staticcall(abi.encodeWithSelector(selector));
        if (ok && ret.length >= 32) a = abi.decode(ret, (address));
    }
}

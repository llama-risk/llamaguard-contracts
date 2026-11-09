// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { IRangeValidationModule } from "chaos-agents/interfaces/IRangeValidationModule.sol";

/**
 * @title ICapsRangeValidationModule
 * @notice Rate-limiter range validation module (RVM) for the caps of one Aave Pool.
 * @dev Keys are (asset, kind). Cap values are whole tokens, bps fields are bps (10_000 = 100%), times are
 *      unix seconds. Functions inherited from `IRangeValidationModule` use `market` for the asset.
 */
interface ICapsRangeValidationModule is IRangeValidationModule {
    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Cap type in a key.
    enum CapKind {
        BORROW,
        SUPPLY
    }

    /// @notice Direction that the RVM accepts from one agentId. NONE rejects every update.
    enum Direction {
        NONE,
        RAISE,
        CUT
    }

    /// @notice Registration of one agentId. `kind` is read from the agent's update type.
    struct AgentConfig {
        Direction direction;
        CapKind kind;
    }

    /// @notice Entry written by the owner or the Risk Council Safe. `maxCap` 0 retires the key.
    struct RateLimitConfig {
        uint64 maxCap; // hard maximum cap, whole tokens, at most 2^36 - 1
        uint64 maxHeadroom; // ceiling of headroomTarget, whole tokens, non-zero. Floor is ceil(maxHeadroom / 25)
        uint16 alphaBps; // headroomTarget as a share of usage
        uint16 cutBandBps; // a cut needs headroom above (1 + band) * headroomTarget
    }

    /// @notice Stored state of one key, one slot (240 bits). `maxCap` 0 means no entry.
    struct KeyState {
        uint64 maxCap; // whole tokens
        uint64 maxHeadroom; // whole tokens
        uint16 alphaBps; // bps
        uint16 cutBandBps; // bps
        uint40 holdUntil; // unix seconds, cuts are rejected before it
        uint40 lastIncreaseAt; // unix seconds of the last Risk Council maxCap or maxHeadroom raise
    }

    /// @notice Global limits of a kind, set by the owner.
    struct Bounds {
        uint16 alphaBpsLimit; // bps, max alphaBps
        uint16 cutBandBpsLimit; // bps, max cutBandBps
        uint16 maxIncreaseBps; // bps, max Risk Council raise of maxCap or maxHeadroom per cooldown
        uint40 cooldown; // seconds between two Risk Council raises, non-zero
    }

    /// @notice Live view of one key, read from Aave in the current block.
    struct ReserveState {
        uint256 cap; // current cap, whole tokens. 0 means no cap
        uint256 usage; // whole tokens
        uint256 supplyBound; // whole tokens
        uint256 headroomTarget; // whole tokens
        uint256 raiseCap; // highest accepted raise
        uint256 cutFloor; // lowest accepted cut
        uint256 cutTrigger; // a cut needs cap > cutTrigger
        uint40 holdUntil; // end of the hold, unix seconds. 0 or past means no hold
        bool raiseBlocked; // reserve frozen or paused
        uint256 maxCap; // the maxCap the rule uses, at most the largest cap Aave stores
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice The owner registered, changed or cleared an agentId.
    event AgentSet(uint256 indexed agentId, Direction direction, CapKind kind);

    /// @notice The owner set the global bounds of a kind.
    event BoundsSet(CapKind indexed kind, Bounds bounds);

    /// @notice An entry was set or retired. `caller` is the Risk Council Safe or the owner.
    event RateLimitConfigSet(
        address indexed asset, CapKind indexed kind, RateLimitConfig rateLimitConfig, address caller
    );

    /// @notice The Risk Council Safe wrote or cleared (`until` 0) the hold of a key.
    event HoldSet(address indexed asset, CapKind indexed kind, uint40 until);

    /// @notice The owner changed the Risk Council Safe address.
    event RiskCouncilChanged(address indexed previousRiskCouncil, address indexed newRiskCouncil);

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Caller is not the Risk Council Safe or the owner.
    error OnlyRiskCouncilOrOwner(address account);

    /// @notice Caller is not the Risk Council Safe.
    error OnlyRiskCouncil(address account);

    /// @notice The agent at `agentId` is not a cap agent of this RVM, AgentHub and Pool.
    error InvalidAgent(uint256 agentId);

    /// @notice A bps field of the bounds is above 10_000, or the cooldown is 0.
    error InvalidBounds();

    /// @notice alphaBps or cutBandBps is above the global limit of the kind, maxHeadroom is 0, or maxCap is
    ///         above 2^36 - 1.
    error RateLimitConfigOutOfBounds();

    /// @notice The key has no entry (max cap 0).
    error RateLimitConfigNotFound(address asset, CapKind kind);

    /// @notice A Risk Council raise of maxCap or maxHeadroom above the relative limit.
    error IncreaseTooLarge(uint256 value, uint256 limit);

    /// @notice A Risk Council raise of maxCap or maxHeadroom before the cooldown ends.
    error CooldownActive(uint256 nextIncreaseAt);

    /// @notice The hold ends more than MAX_HOLD_DURATION after block.timestamp.
    error HoldTooLong(uint40 until, uint256 maxUntil);

    /// @notice Zero address passed for a role or an immutable.
    error ZeroAddress();

    /// @notice The call is not supported (stock range config setters, `renounceOwnership`).
    error NotSupported();

    /// @notice An update type passed to the constructor is empty, or both are equal.
    error InvalidUpdateTypes();

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS AND IMMUTABLES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice The only AgentHub this RVM serves.
    function AGENT_HUB() external view returns (address);

    /// @notice The only Aave Pool this RVM serves.
    function POOL() external view returns (address);

    /// @notice keccak256 of the full update type of the BORROW agents of this Pool.
    function BORROW_UPDATE_TYPE_HASH() external view returns (bytes32);

    /// @notice keccak256 of the full update type of the SUPPLY agents of this Pool.
    function SUPPLY_UPDATE_TYPE_HASH() external view returns (bytes32);

    /// @notice Longest hold, 24 hours, in seconds.
    function MAX_HOLD_DURATION() external view returns (uint256);

    // ═══════════════════════════════════════════════════════════════════════════
    // PREVIEWS: anyone, view
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice The raise the RVM accepts on the key in the current block.
     * @dev Returns (false, 0, 0) without a revert when the key has no entry.
     * @param asset the token address
     * @param kind the cap kind
     * @return allowed true if a raise to `newCap` is accepted now
     * @return currentCap live cap, whole tokens
     * @return newCap highest accepted raise, whole tokens. 0 when `allowed` is false, so check `allowed`
     */
    function previewRaise(
        address asset,
        CapKind kind
    )
        external
        view
        returns (bool allowed, uint256 currentCap, uint256 newCap);

    /**
     * @notice The cut the RVM accepts on the key in the current block.
     * @dev Returns (false, 0, 0) without a revert when the key has no entry.
     * @param asset the token address
     * @param kind the cap kind
     * @return due true if a cut to `newCap` is accepted now
     * @return currentCap live cap, whole tokens
     * @return newCap the cut target, whole tokens
     */
    function previewCut(
        address asset,
        CapKind kind
    )
        external
        view
        returns (bool due, uint256 currentCap, uint256 newCap);

    /// @notice Live state of one key. Reverts RateLimitConfigNotFound if the key has no entry.
    function getReserveState(address asset, CapKind kind) external view returns (ReserveState memory);

    // ═══════════════════════════════════════════════════════════════════════════
    // OWNER
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Register an agentId of AGENT_HUB with a direction, or clear it with NONE.
    /// @dev The kind comes from an exact match of the agentId's AgentHub update type. Reverts InvalidAgent.
    function setAgent(uint256 agentId, Direction direction) external;

    /// @notice Set the global bounds of a kind. Reverts InvalidBounds on a bps field above 10_000 or a cooldown
    ///         of 0.
    function setBounds(CapKind kind, Bounds calldata bounds) external;

    /// @notice Set the Risk Council Safe address. Reverts ZeroAddress.
    function setRiskCouncil(address riskCouncil) external;

    // ═══════════════════════════════════════════════════════════════════════════
    // OWNER OR RISK COUNCIL SAFE
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Set the entry of a key. `maxCap` 0 retires the key and clears its slot, and reverts
     *         RateLimitConfigNotFound for both callers if the key has no entry.
     * @dev A live entry needs a non-zero maxHeadroom and a maxCap of at most 2^36 - 1, for both callers.
     *      Within that, the owner may set any maxCap and maxHeadroom. The Risk Council Safe needs an existing
     *      entry, and a raise of maxCap or maxHeadroom must stay within maxIncreaseBps of the current value, once
     *      per cooldown shared by both fields. Lowering is free, including retiring the key; only the owner
     *      adds a key back, so the Risk Council Safe can tighten but never loosen beyond the owner's entries.
     *      Reverts OnlyRiskCouncilOrOwner, RateLimitConfigOutOfBounds, RateLimitConfigNotFound,
     *      IncreaseTooLarge, CooldownActive.
     * @param asset the token address
     * @param kind the cap kind
     * @param rateLimitConfig the new entry
     */
    function setRateLimitConfig(address asset, CapKind kind, RateLimitConfig calldata rateLimitConfig) external;

    // ═══════════════════════════════════════════════════════════════════════════
    // RISK COUNCIL SAFE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Write the hold of a key. Cuts are rejected while block.timestamp < until. `until` 0 clears it.
    /// @dev The hold also blocks the cut down to maxCap. Raises are not held.
    ///      Reverts OnlyRiskCouncil, HoldTooLong, RateLimitConfigNotFound.
    function setHold(address asset, CapKind kind, uint40 until) external;

    // ═══════════════════════════════════════════════════════════════════════════
    // GETTERS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Registration of an agentId. Direction NONE if not registered.
    function getAgent(uint256 agentId) external view returns (AgentConfig memory);

    /// @notice Stored state of a key. All zero if none.
    function getKeyState(address asset, CapKind kind) external view returns (KeyState memory);

    /// @notice The global bounds of a kind. All zero if none.
    function getBounds(CapKind kind) external view returns (Bounds memory);

    /// @notice The Risk Council Safe address.
    function riskCouncil() external view returns (address);
}

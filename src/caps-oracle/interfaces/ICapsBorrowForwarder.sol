// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

/**
 * @title ICapsBorrowForwarder
 * @notice Large-borrower helper. An allowlisted caller (the Risk Council Safe at launch) raises an Aave V3 borrow
 *         cap and borrows in one plain call, with the debt on the borrower. The forwarder holds RISK_ADMIN on the
 *         Pool's ACL Manager and writes the cap through the config engine by delegatecall. The borrower delegates
 *         credit to the forwarder, and every borrowed token goes to the borrower.
 * @dev The config engine and the RVM are immutable, so the delegatecall target cannot change on a contract that
 *      holds credit delegations. Each raise is bounded by the RVM borrow `maxCap`, the per-raise limit
 *      `maxRaiseBuffers` and the per-asset delay `minRaiseDelay`.
 */
interface ICapsBorrowForwarder {
    /// @notice One borrow of a batch: `amount` in token smallest units, with the debt on `onBehalfOf`.
    struct BorrowRequest {
        address onBehalfOf;
        uint256 amount;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice The cap was raised and `amount` was borrowed for `onBehalfOf` and sent to it.
    event CapRaisedAndBorrowed(
        address indexed asset, address indexed onBehalfOf, uint256 amount, uint256 oldBorrowCap, uint256 newBorrowCap
    );

    /// @notice `account` was added to (`allowed` true) or removed from the caller allowlist.
    event CallerSet(address indexed account, bool allowed);

    /// @notice The per-raise and per-period limits were set.
    event LimitsSet(uint256 maxRaiseBuffers, uint256 minRaiseDelay);

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice `raiseCapAndBorrow` was called by an account outside the caller allowlist.
    error NotCaller(address caller);

    /// @notice Zero address or zero value, or the borrower is the zero address, the forwarder or the caller.
    error InvalidInput();

    /// @notice The live borrow cap is 0 (no cap).
    error BorrowCapNotSet(address asset);

    /// @notice The live borrow cap is 1, Aave's manual freeze of borrowing. The forwarder does not lift it.
    error BorrowCapFrozen(address asset);

    /// @notice The computed new cap is above the RVM borrow `maxCap` of the asset (0 when the asset has no entry).
    ///         The Risk Council sets or raises `maxCap` first.
    error NewCapAboveMaxCap(uint256 newCap, uint256 maxCap);

    /// @notice The cap increase is above `maxRaiseBuffers` buffers of the asset.
    error RaiseAboveLimit(uint256 increase, uint256 maxIncrease);

    /// @notice The last raise for the asset was less than `minRaiseDelay` ago.
    error RaiseTooSoon(address asset, uint256 nextRaiseAt);

    /// @notice The forwarder's token balance changed across the borrow.
    error ForwarderBalanceChanged(uint256 before, uint256 afterCall);

    /// @notice Renouncing ownership is not supported.
    error NotSupported();

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEWS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice The Aave V3 Pool.
    function POOL() external view returns (address);

    /// @notice The Aave V3 config engine, the delegatecall target that writes the cap.
    function CONFIG_ENGINE() external view returns (address);

    /// @notice The rate-limiter RVM of the Pool. Its borrow `maxCap` bounds the new cap.
    function RVM() external view returns (address);

    /// @notice Whether `account` may call `raiseCapAndBorrow`.
    function isCaller(address account) external view returns (bool);

    /// @notice Max cap increase in one raise, in buffers: the asset's RVM `headroomTarget`, the room one
    ///         automatic raise adds. One value fits every market.
    function maxRaiseBuffers() external view returns (uint256);

    /// @notice Min seconds between two raises of the same asset.
    function minRaiseDelay() external view returns (uint256);

    /// @notice Timestamp of the last raise of `asset`, 0 if never raised.
    function lastRaiseAt(address asset) external view returns (uint256);

    // ═══════════════════════════════════════════════════════════════════════════
    // ACTION (ALLOWLISTED CALLER ONLY)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Raise the borrow cap, borrow `amount` with the debt on `onBehalfOf`, and send the tokens to it.
     * @dev The borrower must have delegated credit to this contract on the asset's variable debt token. The
     *      delegation left after the borrow is renounced, so each raise needs a fresh `approveDelegation`.
     *      The new cap is max(live cap, debt) + amount + 1 in whole tokens, the debt and the amount
     *      rounded up, so accrued interest above the cap cannot make the borrow fail.
     *      Reverts when the new cap is above the RVM borrow `maxCap` (an asset without an RVM entry has `maxCap`
     *      0 and cannot be raised), or more than `maxRaiseBuffers` buffers above the live cap, and when the last raise
     *      of the asset was less than `minRaiseDelay` ago.
     *      Also reverts on a failed token transfer, on any config engine or Pool revert, and when the forwarder's
     *      balance changes.
     * @param asset the token to borrow
     * @param amount token smallest units
     * @param onBehalfOf the account that carries the debt and receives the tokens
     */
    function raiseCapAndBorrow(address asset, uint256 amount, address onBehalfOf) external;

    /**
     * @notice Raise the borrow cap once for the sum of `requests`, then borrow for each borrower.
     * @dev Same rules as `raiseCapAndBorrow`, with the limits applied to the sum. 1 to 20 requests. Any failed
     *      borrow reverts the whole batch. Emits one `CapRaisedAndBorrowed` per request.
     * @param asset the token to borrow
     * @param requests the borrowers and amounts
     */
    function raiseCapAndBorrowBatch(address asset, BorrowRequest[] calldata requests) external;

    // ═══════════════════════════════════════════════════════════════════════════
    // ADMIN (OWNER ONLY)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Add `account` to (`allowed` true) or remove it from the caller allowlist.
    /// @dev Reverts InvalidInput on the zero address.
    function setCaller(address account, bool allowed) external;

    /// @notice Set the per-raise limit and the per-period delay.
    /// @dev Reverts InvalidInput when `maxRaiseBuffers_` is 0.
    /// @param maxRaiseBuffers_ max cap increase in one raise, in buffers of the asset
    /// @param minRaiseDelay_ min seconds between two raises of the same asset, above 0
    function setLimits(uint256 maxRaiseBuffers_, uint256 minRaiseDelay_) external;
}

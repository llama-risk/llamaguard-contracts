// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

/**
 * @title ICapsBorrowForwarder
 * @notice Large-borrower helper. The Risk Council Safe delegatecalls it to raise a borrow cap through
 *         the Risk Steward and borrow in one Safe transaction, with the debt on the borrower. The borrower
 *         delegates credit to the forwarder contract, and `borrowFor` sends every borrowed token to the borrower.
 * @dev Has no state and no admin function. `raiseCapAndBorrow` reverts unless it runs in the Risk Council Safe's
 *      context. `borrowFor` reverts unless the Risk Council Safe calls the deployed forwarder directly.
 */
interface ICapsBorrowForwarder {
    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice The cap was raised and `amount` was borrowed for `onBehalfOf` and sent to it.
    /// @dev Emitted from the Risk Council Safe's address, because the code runs by delegatecall.
    event CapRaisedAndBorrowed(
        address indexed asset, address indexed onBehalfOf, uint256 amount, uint256 oldBorrowCap, uint256 newBorrowCap
    );

    /// @notice `amount` was borrowed for `onBehalfOf` under its credit delegation to the forwarder and sent to it.
    /// @dev Emitted from the forwarder's address.
    event BorrowedFor(address indexed asset, address indexed onBehalfOf, uint256 amount);

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice The code does not run by delegatecall from the Risk Council Safe.
    error NotRiskCouncilContext(address context);

    /// @notice `borrowFor` was called by an account other than the Risk Council Safe.
    error NotRiskCouncil(address caller);

    /// @notice `borrowFor` runs by delegatecall, outside the deployed forwarder.
    error NotDirectCall(address context);

    /// @notice Zero amount, or the borrower is the zero address, the Safe or the forwarder.
    error InvalidInput();

    /// @notice The live borrow cap is 0 (no cap).
    error BorrowCapNotSet(address asset);

    /// @notice The computed new cap is above `maxNewCap`.
    error NewCapAboveMax(uint256 newCap, uint256 maxNewCap);

    /// @notice The computed new cap is above the RVM borrow `maxCap` of the asset. The Risk Council raises
    ///         `maxCap` first.
    error NewCapAboveMaxCap(uint256 newCap, uint256 maxCap);

    /// @notice The forwarder's token balance changed across `borrowFor`.
    error ForwarderBalanceChanged(uint256 before, uint256 afterCall);

    // ═══════════════════════════════════════════════════════════════════════════
    // IMMUTABLES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice The Aave V3 Pool.
    function POOL() external view returns (address);

    /// @notice The Risk Steward that writes the cap.
    function RISK_STEWARD() external view returns (address);

    /// @notice The Risk Council Safe, the only context in which `raiseCapAndBorrow` runs.
    function RISK_COUNCIL() external view returns (address);

    /// @notice The rate-limiter RVM of the Pool. Its borrow `maxCap` bounds the new cap.
    function RVM() external view returns (address);

    /// @notice The forwarder's own deployed address, read from code so it resolves inside the delegatecall.
    ///         Borrowers delegate credit to it.
    function SELF() external view returns (address);

    // ═══════════════════════════════════════════════════════════════════════════
    // ACTION (DELEGATECALL FROM THE RISK COUNCIL SAFE ONLY)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Raise the borrow cap, borrow `amount` with the debt on `onBehalfOf`, and send the tokens to it.
     * @dev Delegatecall from the Risk Council Safe only. The borrower must have delegated credit to `SELF`, the
     *      forwarder contract. The borrow runs through `borrowFor` on `SELF`.
     *      The new cap is max(live cap, debt) + amount + extraCapTokens in whole tokens, the debt and the amount
     *      rounded up, so accrued interest above the cap cannot make the borrow fail.
     *      The new cap stays within the asset's RVM borrow `maxCap` when the asset has a rate limit entry,
     *      so a later cut never sets the cap below the debt.
     *      Also reverts on a failed token transfer and on any Risk Steward or Pool revert.
     * @param asset the token to borrow
     * @param amount token smallest units
     * @param onBehalfOf the account that carries the debt and receives the tokens
     * @param extraCapTokens extra cap on top of the borrowed amount, whole tokens
     * @param maxNewCap the highest new cap the signers accept, whole tokens
     */
    function raiseCapAndBorrow(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint256 extraCapTokens,
        uint256 maxNewCap
    )
        external;

    // ═══════════════════════════════════════════════════════════════════════════
    // ACTION (PLAIN CALL FROM THE RISK COUNCIL SAFE ONLY)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Borrow `amount` with the debt on `onBehalfOf`, under its credit delegation to the forwarder, and send
     *         the tokens to it.
     * @dev Plain call from the Risk Council Safe only, to the deployed forwarder. `raiseCapAndBorrow` calls it after
     *      the cap raise. The Safe can also call it alone when the cap already has room. Reverts on a failed token
     *      transfer, on any Pool revert, and when the forwarder's balance changes.
     * @param asset the token to borrow
     * @param amount token smallest units
     * @param onBehalfOf the account that carries the debt and receives the tokens
     */
    function borrowFor(address asset, uint256 amount, address onBehalfOf) external;
}

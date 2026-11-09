// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

/**
 * @title ICapsBorrowForwarder
 * @notice Large-borrower helper. The Risk Council Safe delegatecalls it to raise a borrow cap through
 *         the Risk Steward and borrow in one Safe transaction, with the debt on the borrower.
 * @dev Has no state and no admin function. It reverts unless it runs in the Risk Council Safe's context.
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

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice The code does not run by delegatecall from the Risk Council Safe.
    error NotRiskCouncilContext(address context);

    /// @notice Zero amount, or the borrower is the zero address or the Safe.
    error InvalidInput();

    /// @notice The live borrow cap is 0 (no cap).
    error BorrowCapNotSet(address asset);

    /// @notice The computed new cap is above `maxNewCap`.
    error NewCapAboveMax(uint256 newCap, uint256 maxNewCap);

    /// @notice The computed new cap is above the RVM borrow `maxCap` of the asset. The Risk Council raises
    ///         `maxCap` first.
    error NewCapAboveMaxCap(uint256 newCap, uint256 maxCap);

    /// @notice The Safe's token balance changed across the call.
    error SafeBalanceChanged(uint256 before, uint256 afterCall);

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

    // ═══════════════════════════════════════════════════════════════════════════
    // ACTION (DELEGATECALL FROM THE RISK COUNCIL SAFE ONLY)
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Raise the borrow cap, borrow `amount` with the debt on `onBehalfOf`, and send the tokens to it.
     * @dev Delegatecall from the Risk Council Safe only. The borrower must have delegated credit to the Safe.
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
}

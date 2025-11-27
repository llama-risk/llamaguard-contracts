// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title ILlamaGuardOracle
 * @notice Interface for LlamaGuard Oracle combining Chainlink AggregatorV3
 * @dev Implements risk parameter update history with update type validation
 */
interface ILlamaGuardOracle {
    // ═══════════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Structure for storing risk parameter updates
     */
    struct RiskParameterUpdate {
        uint256 timestamp; // Timestamp of the update
        bytes newValue; // ABI-encoded price (int256) for Chainlink AggregatorV3 compatibility
        string referenceId; // External reference, potentially linking to off-chain data
        bytes previousValue; // Previous newValue (price) for historical comparison
        string updateType; // Classification of the update for validation purposes
        uint256 updateId; // Unique identifier (equals roundId)
        address market; // Address for market of the parameter update
        bytes additionalData; // ABI-encoded tuple: (uint256 supply, int256 price, uint256 state)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when a parameter update is recorded
     */
    event ParameterUpdated(
        string referenceId,
        bytes newValue,
        bytes previousValue,
        uint256 timestamp,
        string indexed updateType,
        uint256 indexed updateId,
        bytes additionalData
    );

    /**
     * @notice Emitted when a new update type is added
     */
    event UpdateTypeAdded(string indexed updateType);

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Thrown when an unauthorized update type is used
    error UnauthorizedUpdateType(string updateType);

    /// @notice Thrown when update type string is invalid (empty or too long)
    error InvalidUpdateTypeString(string updateType);

    /// @notice Thrown when attempting to add a duplicate update type
    error UpdateTypeAlreadyExists(string updateType);

    /// @notice Thrown when querying an invalid update ID
    error InvalidUpdateId(uint256 updateId);

    /// @notice Thrown when attempting to update/query an unauthorized market
    error UnauthorizedMarket(address market);

    /// @notice Thrown when market address is address(0)
    error InvalidMarketAddress(address market);

    /// @notice Thrown when attempting to add a market that is already authorized
    error MarketAlreadyAuthorized(address market);

    /// @notice Thrown when attempting to remove a market that is not authorized
    error MarketNotFound(address market);

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS - Market Authorization
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Emitted when a market is added to the authorized list
     * @param market Address of the newly authorized market
     */
    event AuthorizedMarketAdded(address indexed market);

    /**
     * @notice Emitted when a market is removed from the authorized list
     * @param market Address of the deauthorized market
     */
    event AuthorizedMarketRemoved(address indexed market);

    // ═══════════════════════════════════════════════════════════════════════════
    // MUTATORS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Update the oracle with new parameter data
     * @dev Only callable by addresses with WRITER_ROLE.
     *      newValue contains ABI-encoded price (int256) for Chainlink AggregatorV3 compatibility.
     *      additionalData contains the full data bundle: abi.encode(uint256 supply, int256 price, uint256 state).
     * @param referenceId External reference ID for the update
     * @param newValue ABI-encoded price (int256) - used as the Chainlink round answer
     * @param updateType Classification of the update (must be authorized)
     * @param additionalData ABI-encoded tuple (uint256 supply, int256 price, uint256 state)
     */
    function updateData(
        string calldata referenceId,
        bytes calldata newValue,
        string calldata updateType,
        bytes calldata additionalData
    )
        external;

    /**
     * @notice Add a new authorized update type
     * @dev Only callable by owner/admin
     * @param newUpdateType The update type string to authorize (1-64 chars)
     */
    function addUpdateType(string calldata newUpdateType) external;

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEWS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Fetch an update record by its ID
     * @param updateId The unique update identifier (equals roundId)
     * @return The RiskParameterUpdate struct for the specified ID
     */
    function getUpdateById(uint256 updateId) external view returns (RiskParameterUpdate memory);

    /**
     * @notice Get all authorized update types
     * @return Array of authorized update type strings
     */
    function getAllUpdateTypes() external view returns (string[] memory);

    /**
     * @notice Check if an address has write access
     * @param account The address to check
     * @return True if the address has WRITER_ROLE
     */
    function hasWriteAccess(address account) external view returns (bool);

    /**
     * @notice Check if an update type is valid
     * @param updateType The update type string to check
     * @return True if the update type is authorized
     */
    function isValidUpdateType(string calldata updateType) external view returns (bool);

    /**
     * @notice Fetches the most recent update for a specific parameter type
     * @dev Returns empty struct (timestamp=0) if no update exists for the updateType.
     *      Does NOT revert for non-existent update types - callers should check timestamp.
     *      The input market address will be rewritten to the returned RiskParameterUpdate.market field.
     * @param updateType The parameter type identifier (e.g., "price", "supply", "risk_state")
     * @param market The market address to be written to the returned RiskParameterUpdate.market field
     * @return The most recent RiskParameterUpdate for the specified updateType,
     *         with the market field set to the input market address,
     *         or an empty struct if no matching update exists
     */
    function getLatestUpdateByParameterAndMarket(
        string calldata updateType,
        address market
    )
        external
        view
        returns (RiskParameterUpdate memory);

    // ═══════════════════════════════════════════════════════════════════════════
    // MARKET AUTHORIZATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Add a market address to the authorized list
     * @dev Restricted to DEFAULT_ADMIN_ROLE
     * @param market Address of the market to authorize (must be non-zero)
     */
    function addAuthorizedMarket(address market) external;

    /**
     * @notice Remove a market address from the authorized list
     * @dev Restricted to DEFAULT_ADMIN_ROLE
     * @param market Address of the market to deauthorize
     */
    function removeAuthorizedMarket(address market) external;

    /**
     * @notice Check if a market address is authorized
     * @param market Address to check
     * @return bool True if market is authorized, false otherwise
     */
    function isAuthorizedMarket(address market) external view returns (bool);
}

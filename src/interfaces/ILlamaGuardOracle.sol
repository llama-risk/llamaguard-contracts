// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

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

    /**
     * @notice Structure for update input data
     * @dev Used as input parameter for updateLatestRiskRoundData function to enable single-struct external calls
     */
    struct UpdateInput {
        string referenceId; // External reference ID for the update
        bytes newValue; // ABI-encoded price (int256) - used as the Chainlink round answer
        string updateType; // Classification of the update for validation purposes (must be authorized)
        bytes additionalData; // ABI-encoded tuple (uint256 supply, int256 price, uint256 state)
        uint256 deadline; // Unix timestamp after which this update is rejected
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
     * @param updateType The update type string that was added
     * @param expectedAdditionalDataLength Expected byte length for additionalData (type(uint256).max = no validation)
     */
    event UpdateTypeAdded(string indexed updateType, uint256 expectedAdditionalDataLength);

    /**
     * @notice Emitted when the expected additionalData length for an update type is changed
     * @param updateType The update type string
     * @param expectedLength The new expected length
     */
    event ExpectedAdditionalDataLengthUpdated(string indexed updateType, uint256 expectedLength);

    /**
     * @notice Emitted when an update type is removed
     */
    event UpdateTypeRemoved(string indexed updateType);

    /**
     * @notice Emitted when the max price deviation is updated
     * @param previousValue The previous max price deviation value
     * @param newValue The new max price deviation value
     */
    event MaxPriceDeviationUpdated(uint256 previousValue, uint256 newValue);

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Thrown when an unauthorized update type is used
    error UnauthorizedUpdateType(string updateType);

    /// @notice Thrown when update type string is invalid (empty or too long)
    error InvalidUpdateTypeString(string updateType);

    /// @notice Thrown when attempting to add a duplicate update type
    error UpdateTypeAlreadyExists(string updateType);

    /// @notice Thrown when attempting to remove an update type that does not exist
    error UpdateTypeNotFound(string updateType);

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

    /// @notice Thrown when price deviation exceeds the maximum allowed
    /// @param previousPrice The previous price value
    /// @param newPrice The new price value
    /// @param deviation The calculated deviation in basis points
    /// @param maxAllowed The maximum allowed deviation in basis points
    error PriceDeviationExceeded(int256 previousPrice, int256 newPrice, uint256 deviation, uint256 maxAllowed);

    /// @notice Thrown when additionalData length doesn't match the expected length for the update type
    /// @param actual The actual length of additionalData
    /// @param expected The expected length for this update type
    error InvalidAdditionalDataLength(uint256 actual, uint256 expected);

    /// @notice Thrown when the update deadline has passed
    /// @param deadline The deadline timestamp specified in the update
    /// @param currentTimestamp The current block.timestamp
    error DeadlineExpired(uint256 deadline, uint256 currentTimestamp);

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
     * @notice Update the oracle with new risk round data
     * @dev Only callable by addresses with WRITER_ROLE.
     *      input.newValue contains ABI-encoded price (int256) for Chainlink AggregatorV3 compatibility.
     *      input.additionalData contains the full data bundle: abi.encode(uint256 supply, int256 price, uint256 state).
     * @param input UpdateInput struct containing referenceId, newValue, updateType, and additionalData
     */
    function updateLatestRiskRoundData(UpdateInput calldata input) external;

    /**
     * @notice Add a new authorized update type with optional additionalData length requirement
     * @dev Only callable by owner/admin
     * @param newUpdateType The update type string to authorize (1-64 chars)
     * @param expectedAdditionalDataLength Expected byte length (type(uint256).max = no validation, 0 = must be empty)
     */
    function addUpdateType(string calldata newUpdateType, uint256 expectedAdditionalDataLength) external;

    /**
     * @notice Remove an existing update type
     * @dev Only callable by owner/admin. Reverts if the update type does not exist.
     * @param updateType The update type string to remove
     */
    function removeUpdateType(string calldata updateType) external;

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
     * @notice Get the expected additionalData length for an update type
     * @param updateType The update type to query
     * @return The expected length (type(uint256).max = no validation, 0 = must be empty)
     */
    function getExpectedAdditionalDataLength(string calldata updateType) external view returns (uint256);

    /**
     * @notice Update the expected additionalData length for an existing update type
     * @dev Only callable by owner/admin. Reverts if the update type does not exist.
     * @param updateType The update type to update
     * @param expectedLength The new expected length (type(uint256).max = disable validation, 0 = must be empty)
     */
    function setExpectedAdditionalDataLength(string calldata updateType, uint256 expectedLength) external;

    /**
     * @notice Fetches the most recent update for a specific parameter type
     * @dev Reverts with InvalidUpdateId(0) if no update exists for the updateType.
     *      The input market address will be rewritten to the returned RiskParameterUpdate.market field.
     * @param updateType The parameter type identifier (e.g., "price", "supply", "risk_state")
     * @param market The market address to be written to the returned RiskParameterUpdate.market field
     * @return The most recent RiskParameterUpdate for the specified updateType,
     *         with the market field set to the input market address
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

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title ILlamaGuardOracle
 * @notice Interface for LlamaGuard Oracle combining Chainlink AggregatorV3 with RiskOracle patterns
 * @dev Implements risk parameter update history with update type validation
 */
interface ILlamaGuardOracle {
    // ═══════════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Structure for storing risk parameter updates
     * @dev Adopted from MIT-licensed IRiskOracle interface
     */
    struct RiskParameterUpdate {
        uint256 timestamp; // Timestamp of the update
        bytes newValue; // Encoded parameters, flexible for various data types
        string referenceId; // External reference, potentially linking to off-chain data
        bytes previousValue; // Previous value for historical comparison
        string updateType; // Classification of the update for validation purposes
        uint256 updateId; // Unique identifier (equals roundId)
        address market; // Address for market of the parameter update
        bytes additionalData; // Additional data for the update
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
        address indexed market,
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

    // ═══════════════════════════════════════════════════════════════════════════
    // MUTATORS
    // ═══════════════════════════════════════════════════════════════════════════

    /**
     * @notice Update the oracle with new parameter data
     * @dev Only callable by addresses with WRITER_ROLE
     * @param referenceId External reference ID for the update
     * @param newValue ABI-encoded new parameter values
     * @param updateType Classification of the update (must be authorized)
     * @param market Market address (use address(0) for global updates)
     * @param additionalData Optional additional data for the update
     */
    function updateData(
        string calldata referenceId,
        bytes calldata newValue,
        string calldata updateType,
        address market,
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
     * @notice Get combined data from the oracle (backward compatible)
     * @return supply The supply value from the latest update
     * @return state The state value from the latest update
     * @return price The price value from the latest update
     * @return startedAt The timestamp of the latest update
     */
    function getData() external view returns (uint256 supply, uint256 state, int256 price, uint256 startedAt);

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
}

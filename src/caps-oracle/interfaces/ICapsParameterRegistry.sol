// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

/**
 * @title ICapsParameterRegistry
 * @notice Parameters of the offchain rate limiter workflow: markets, the work list per market, and
 *         trigger and margin settings with per-key overrides. The updater writes, the owner appoints
 *         the updater, anyone reads.
 * @dev `kind` uses the RVM numbering: 0 = BORROW, 1 = SUPPLY. No onchain cap decision reads this contract.
 */
interface ICapsParameterRegistry {
    // ═══════════════════════════════════════════════════════════════════════════
    // TYPES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Per-key switch. INHERIT uses the market default.
    enum EnabledOverride {
        INHERIT,
        ON,
        OFF
    }

    /// @notice Workflow parameters. Used as the market default and, resolved, as the effective value.
    struct WorkflowParams {
        bool enabled; // false: the workflow sends no raise
        uint16 triggerBps; // raise due when headroom <= theta * L
        uint16 marginBps; // raise margin as a share of L
        uint64 minMarginTokens; // margin floor, whole tokens
    }

    /// @notice Per market (Aave Pool).
    struct MarketParams {
        uint64 maxBaseFeeGwei; // raises skipped while base fee is above it. 0 = no gas gate
        WorkflowParams defaultParams; // market-wide default for every key
        address rvm; // RVM of the market, read by the views only. 0 = not set
    }

    /// @notice Per-key override. A field at 0 (or INHERIT) uses the market default.
    struct ReserveOverride {
        EnabledOverride enabled;
        uint16 triggerBps;
        uint16 marginBps;
        uint64 minMarginTokens;
    }

    /// @notice One work list item.
    struct ReserveKey {
        address asset;
        uint8 kind;
    }

    /**
     * @notice One row of `getReservesRaiseData`: the raise inputs of one (market, asset, kind).
     * @dev `found` false means the key is not listed, the market RVM is not set, the kind is invalid,
     *      the RVM has no config for the key, or the RVM state read reverts. Every field other than
     *      `asset` is then 0.
     */
    struct ReserveRaiseData {
        address asset; // token address, as passed in
        bool found; // false: skip the key
        WorkflowParams params; // effective parameters
        uint256 cap; // C, live Aave cap, whole tokens
        uint256 usage; // D, whole tokens
        uint256 supplyBound; // S, whole tokens
        uint256 headroomTarget; // L, whole tokens
        uint256 maxCap; // C-bar the RVM uses, whole tokens
        bool raiseBlocked; // reserve frozen or paused
        bool allowed; // RVM previewRaise: a raise to newCap passes the RVM in this block
        uint256 newCap; // RVM previewRaise newCap, whole tokens
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    event UpdaterChanged(address indexed previousUpdater, address indexed newUpdater);
    event MarketAdded(address indexed market, MarketParams params);
    event MarketParamsSet(address indexed market, MarketParams params);
    event MarketRemoved(address indexed market);
    event ReserveAdded(address indexed market, address indexed asset, uint8 indexed kind, ReserveOverride params);
    event ReserveOverrideSet(address indexed market, address indexed asset, uint8 indexed kind, ReserveOverride params);
    event EnabledSet(address indexed market, address indexed asset, uint8 indexed kind, EnabledOverride enabled);
    event ReserveRemoved(address indexed market, address indexed asset, uint8 indexed kind);

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    error OnlyUpdater();
    error ZeroAddress();
    error MarketNotFound(address market);
    error MarketAlreadyExists(address market);
    error MarketNotEmpty(address market);
    error ReserveNotFound(address market, address asset, uint8 kind);
    error ReserveAlreadyListed(address market, address asset, uint8 kind);
    error InvalidKind(uint8 kind);
    /// @notice triggerBps or marginBps above 10_000, or a market default triggerBps of 0.
    error InvalidBps(uint16 value);
    /// @notice A non-zero RVM whose `POOL()` is not the market.
    error InvalidRvm(address rvm);

    // ═══════════════════════════════════════════════════════════════════════════
    // OWNER
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Appoint the updater. Caller: owner. Reverts ZeroAddress.
    function setUpdater(address updater) external;

    // ═══════════════════════════════════════════════════════════════════════════
    // UPDATER
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Add a market with its max base fee, defaults and RVM. Caller: updater.
    /// @dev Reverts MarketAlreadyExists, ZeroAddress, InvalidBps, InvalidRvm (non-zero RVM with POOL() != market).
    function addMarket(address market, MarketParams calldata params) external;

    /// @notice Change the max base fee, defaults and RVM of a market. Caller: updater.
    /// @dev Reverts MarketNotFound, InvalidBps, InvalidRvm. Same bounds as addMarket.
    function setMarketParams(address market, MarketParams calldata params) external;

    /// @notice Remove a market with an empty work list. Caller: updater. Reverts MarketNotEmpty.
    function removeMarket(address market) external;

    /// @notice Add a key to the work list of a market, with optional overrides. Caller: updater.
    /// @dev Reverts MarketNotFound, ReserveAlreadyListed, InvalidKind, InvalidBps, ZeroAddress.
    function addReserve(address market, address asset, uint8 kind, ReserveOverride calldata params) external;

    /// @notice Change the overrides of a key. Caller: updater. Same bounds as addReserve.
    function setReserveOverride(address market, address asset, uint8 kind, ReserveOverride calldata params) external;

    /// @notice Set the workflow switch of a key (ON, OFF or INHERIT). Caller: updater.
    function setEnabled(address market, address asset, uint8 kind, EnabledOverride enabled) external;

    /// @notice Remove a key from the work list. Caller: updater.
    function removeReserve(address market, address asset, uint8 kind) external;

    // ═══════════════════════════════════════════════════════════════════════════
    // GETTERS: anyone
    // ═══════════════════════════════════════════════════════════════════════════

    function updater() external view returns (address);

    function getMarkets() external view returns (address[] memory);

    function getMarketParams(address market) external view returns (MarketParams memory);

    /// @notice Work list of a market, enabled or not.
    function getReservesList(address market) external view returns (ReserveKey[] memory);

    /// @notice Work list keys of `market` with this `kind`, in set order.
    /// @dev Reverts MarketNotFound, InvalidKind (kind > MAX_KIND).
    function getReservesListByKind(address market, uint8 kind) external view returns (ReserveKey[] memory keys);

    /// @notice The stored overrides of a key.
    function getReserveOverride(
        address market,
        address asset,
        uint8 kind
    )
        external
        view
        returns (ReserveOverride memory);

    /// @notice The effective parameters of a key: each override, else the market default.
    /// @dev Reverts ReserveNotFound if the key is not listed.
    function getEffectiveParams(address market, address asset, uint8 kind) external view returns (WorkflowParams memory);

    function isListed(address market, address asset, uint8 kind) external view returns (bool);

    /**
     * @notice Raise inputs for a page of assets, one row per asset in input order.
     * @dev View. Never reverts on a missing key: the row has `found` false. Reverts if the market RVM
     *      reverts on `previewRaise` or returns data that does not decode.
     * @param market the Aave Pool
     * @param kind 0 = BORROW, 1 = SUPPLY
     * @param assets token addresses, one page of the work list
     */
    function getReservesRaiseData(
        address market,
        uint8 kind,
        address[] calldata assets
    )
        external
        view
        returns (ReserveRaiseData[] memory);
}

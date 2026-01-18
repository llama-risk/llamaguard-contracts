## ParameterRegistry

**Purpose**: Serves as a central registry for asset-specific risk parameters (such as max APY, tolerances, and oracle
addresses) used by off-chain agents and on-chain consumers to monitor and react to market conditions.

**Inheritance**:

- `Ownable2Step`

**Key State Variables**: | Variable | Type | Visibility | Purpose | |----------|------|------------|---------| |
`updater` | `address` | `public` | The address authorized to update asset parameters. | | `assetConfigs` |
`mapping(address => AssetConfig)` | `private` | Stores configuration structs (`AssetConfig`) for each asset address. | |
`MAX_EXPECTED_APY_LIMIT` | `uint64` | `public constant` | Safety limit for Max Expected APY (20,000 BPS). | |
`MAX_UPPER_BOUND_TOLERANCE` | `uint32` | `public constant` | Safety limit for Upper Bound Tolerance (250 BPS). | |
`MAX_LOWER_BOUND_TOLERANCE` | `uint32` | `public constant` | Safety limit for Lower Bound Tolerance (250 BPS). | |
`MAX_DISCOUNT_LIMIT` | `uint32` | `public constant` | Safety limit for Max Discount (250 BPS). |

**External/Public Functions**: | Function | Parameters | Returns | Access Control | Description |
|----------|------------|---------|----------------|-------------| | `setUpdater` | `address _updater` | `void` |
`onlyOwner` | Sets the address authorized to perform updates. | | `setParametersForAsset` | `address asset`,
`string assetName`, `address oracle`, `...params` | `void` | `onlyUpdater` | Sets the complete configuration for a
specific asset. | | `setMaxExpectedApy` | `address asset`, `uint64` | `void` | `onlyUpdater` | Updates the max expected
APY for an asset. | | `setUpperBoundTolerance` | `address asset`, `uint32` | `void` | `onlyUpdater` | Updates the upper
bound tolerance for an asset. | | `setLowerBoundTolerance` | `address asset`, `uint32` | `void` | `onlyUpdater` |
Updates the lower bound tolerance for an asset. | | `setMaxDiscount` | `address asset`, `uint32` | `void` |
`onlyUpdater` | Updates the max discount for an asset. | | `setIsUpperBoundEnabled` | `address asset`, `bool` | `void` |
`onlyUpdater` | Toggles upper bound checking for an asset. | | `setIsLowerBoundEnabled` | `address asset`, `bool` |
`void` | `onlyUpdater` | Toggles lower bound checking for an asset. | | `setIsActionTakingEnabled` | `address asset`,
`bool` | `void` | `onlyUpdater` | Toggles whether action taking is enabled for an asset. | | `setLookbackWindowSize` |
`address asset`, `uint80` | `void` | `onlyUpdater` | Updates the lookback window size for an asset. | | `setOracle` |
`address asset`, `address oracle` | `void` | `onlyUpdater` | Updates the oracle source for an asset. | | `deleteAsset` |
`address asset` | `void` | `onlyUpdater` | Removes an asset from the registry. | | `getParametersForAsset` |
`address asset` | `...params` | `public` | Retrieves the full configuration for an asset. | | `getAssetName` |
`address asset` | `string` | `public` | Retrieves the name of an asset. | | `assetExists` | `address asset` | `bool` |
`public` | Checks if an asset is registered. | | `getOracle` | `address asset` | `address` | `public` | Retrieves the
oracle address for an asset. | | `getLookbackData` | `address asset` | `...roundData` | `public` | Fetches historical
round data from the asset's configured oracle based on the lookback window. |

**Events**:

- `UpdaterChanged(address previousUpdater, address newUpdater)`
- `AssetParametersSet(address asset, ...)`
- `AssetDeleted(address asset)`
- `AssetNameSet`, `AssetOracleSet`, `LookbackWindowSizeSet`, `MaxExpectedApySet`, `UpperBoundToleranceSet`,
  `LowerBoundToleranceSet`, `MaxDiscountSet`, `IsUpperBoundEnabledSet`, `IsLowerBoundEnabledSet`,
  `IsActionTakingEnabledSet`: Granular events for property updates.

**Access Control**:

- **Owner**: Can set the `updater`.
- **Updater**: Can add, modify, and delete asset configurations.

**Integration Points**:

- **Chainlink Aggregators**: `getLookbackData` interacts with contracts implementing `AggregatorV3Interface` (via the
  configured oracle addresses) to fetch price data.
- **Off-chain Agents**: Used by monitoring bots to retrieve the latest risk parameters and thresholds for assets.

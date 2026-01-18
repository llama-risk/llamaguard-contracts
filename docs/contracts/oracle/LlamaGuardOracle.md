## LlamaGuardOracle

**Purpose**: The LlamaGuardOracle serves as a centralized on-chain registry for risk parameters, allowing authorized
writers to push updates and providing an `AggregatorV3`-compatible interface for historical data tracking.

**Inheritance**:

- `AggregatorV3`
- `ILlamaGuardOracle`
- `AbstractReadWriteAccessController`

**Key State Variables**: | Variable | Type | Visibility | Purpose | |----------|------|------------|---------| |
`updateTypes` | `string[]` | `public` | Array of all valid update type strings supported by the oracle. | |
`updateHistory` | `mapping(uint256 => RiskParameterUpdate)` | `public` | Stores the history of risk parameter updates by
update ID (round ID). | | `_validUpdateTypes` | `mapping(bytes32 => bool)` | `private` | Mapping for O(1) validation of
supported update types. | | `_latestUpdateIdByType` | `mapping(bytes32 => uint256)` | `private` | Tracks the latest
update ID for each specific update type. | | `_authorizedMarkets` | `mapping(address => bool)` | `private` | Tracks
which market addresses are authorized for updates. |

**External/Public Functions**: | Function | Parameters | Returns | Access Control | Description |
|----------|------------|---------|----------------|-------------| | `updateLatestRiskRoundData` | `UpdateInput input` |
`void` | `WRITER_ROLE` | Updates the oracle with new risk data, storing it in history and updating the latest round
data. | | `addUpdateType` | `string newUpdateType` | `void` | `DEFAULT_ADMIN_ROLE` | Adds a new valid update type string
to the system. | | `getUpdateById` | `uint256 updateId` | `RiskParameterUpdate` | `public` | Retrieves the details of a
specific update by its ID. | | `isValidUpdateType` | `string updateType` | `bool` | `public` | Checks if a given update
type string is valid and supported. | | `hasWriteAccess` | `address account` | `bool` | `public` | Checks if an account
has the `WRITER_ROLE`. | | `getLatestUpdateByParameterAndMarket` | `string updateType`, `address market` |
`RiskParameterUpdate` | `public` | Retrieves the latest update for a specific parameter type and market (note: market is
rewritten in return value). | | `isAuthorizedMarket` | `address market` | `bool` | `public` | Checks if a market address
is authorized. | | `addAuthorizedMarket` | `address market` | `void` | `DEFAULT_ADMIN_ROLE` | Authorizes a new market
address. | | `removeAuthorizedMarket` | `address market` | `void` | `DEFAULT_ADMIN_ROLE` | Deauthorizes a market
address. |

**Events**:

- `UpdateTypeAdded(string updateType)`: Emitted when a new update type is added.
- `AuthorizedMarketAdded(address market)`: Emitted when a market is authorized.
- `AuthorizedMarketRemoved(address market)`: Emitted when a market is removed.
- `ParameterUpdated(...)`: Emitted in `updateLatestRiskRoundData` with full details of the update (referenceId, values,
  timestamp, etc.).

**Access Control**:

- **WRITER_ROLE**: Required to call `updateLatestRiskRoundData`. This is typically held by the `LlamaGuardOracleProxy`
  or other authorized data providers.
- **DEFAULT_ADMIN_ROLE**: Required to manage configuration (add/remove update types and authorized markets).

**Integration Points**:

- **LlamaGuardOracleProxy**: The primary writer that forwards validated reports to this oracle.
- **AggregatorV3 Consumers**: Any contract that reads data using the Chainlink `AggregatorV3Interface`.

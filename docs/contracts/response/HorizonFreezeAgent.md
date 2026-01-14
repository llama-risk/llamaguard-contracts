## HorizonFreezeAgent

**Purpose**: A specialized agent capable of freezing Aave V3 markets (reserves) in the Horizon protocol when a valid
risk update (indicating a freeze command) is received from the oracle.

**Inheritance**:

- `BaseHorizonAgent`

**Key State Variables**: | Variable | Type | Visibility | Purpose | |----------|------|------------|---------| |
`FROZEN_STATE` | `uint256` | `public constant` | The value (1) representing a "frozen" state in the `additionalData`
payload. |

**External/Public Functions**: | Function | Parameters | Returns | Access Control | Description |
|----------|------------|---------|----------------|-------------| | `inject` | `uint256 agentId`, `bytes agentContext`,
`RiskParameterUpdate update` | `void` | `onlyAgentHub` | Overrides base `inject` to perform re-validation before
processing. Executes the freeze if valid. | | `_validateInternal` | `uint256`, `bytes`, `RiskParameterUpdate update` |
`bool` | `internal` (view) | Checks if the update requests a freeze and if the market is not already frozen. Unfreezing
is explicitly disallowed. | | `_processUpdate` | `uint256`, `bytes agentContext`, `RiskParameterUpdate update` | `void`
| `internal` | Decodes the context and update data, then calls `setReserveFreeze` on the pool configurator. |

**Events**:

- `ReserveFreezeUpdated(address indexed market, bool frozen, uint256 freezeState)`: Emitted when a reserve is
  successfully frozen.

**Access Control**:

- **onlyAgentHub**: Inherited from `BaseHorizonAgent`.
- **Pool Configurator**: The `_processUpdate` function assumes the contract (or the `poolConfigurator` passed in
  context) has permissions to freeze reserves. _Note: The code calls `poolConfigurator.functionCall`, implying this
  agent or the caller must have the necessary permissions on the configurator._

**Integration Points**:

- **LlamaGuardOracle**: Consumes `RiskParameterUpdate` structs, specifically decoding `additionalData`.
- **Aave V3 IPoolConfigurator**: Calls `setReserveFreeze` to enact the freeze.
- **Aave V3 Pool**: Checks current freeze state via `POOL.getConfiguration(market).getFrozen()`.

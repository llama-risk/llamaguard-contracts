## BaseHorizonAgent

**Purpose**: An abstract base contract that provides common infrastructure for Horizon agents, including connections to
the `AgentHub` and the Aave V3 `Pool`.

**Inheritance**:

- None (Implements interfaces implied by `AgentHub` architecture)

**Key State Variables**: | Variable | Type | Visibility | Purpose | |----------|------|------------|---------| |
`AGENT_HUB` | `address` | `public immutable` | The address of the `HorizonAgentHub` that is authorized to call this
agent. | | `POOL` | `IPool` | `public immutable` | The Aave V3 Pool contract used for fetching reserves and interacting
with the protocol. |

**External/Public Functions**: | Function | Parameters | Returns | Access Control | Description |
|----------|------------|---------|----------------|-------------| | `inject` | `uint256 agentId`, `bytes agentContext`,
`RiskParameterUpdate update` | `void` | `onlyAgentHub` | The entry point for the AgentHub to trigger an action. Calls
`_processUpdate`. | | `validate` | `uint256 agentId`, `bytes agentContext`, `RiskParameterUpdate update` | `bool` |
`public` | Checks if a proposed update is valid for the given agent context. Calls `_validateInternal`. | | `getMarkets`
| `uint256` | `address[]` | `public` | Returns the list of active reserves (markets) from the Aave V3 Pool. |

**Events**:

- None.

**Access Control**:

- **onlyAgentHub**: The `inject` function can only be called by the immutable `AGENT_HUB` address.

**Integration Points**:

- **HorizonAgentHub**: The sole authorized caller for actions.
- **Aave V3 Pool**: Used to fetch the list of reserves.
- **Subclasses**: Must implement `_validateInternal` and `_processUpdate`.

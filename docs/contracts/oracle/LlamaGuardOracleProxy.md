## LlamaGuardOracleProxy

**Purpose**: Acts as a secure gateway for submitting risk reports to the `LlamaGuardOracle`, validating the source and
integrity of reports before forwarding them.

**Inheritance**:

- `Ownable2Step`
- `AbstractCreReceiver`

**Key State Variables**: | Variable | Type | Visibility | Purpose | |----------|------|------------|---------| |
`llamaguardOracle` | `ILlamaGuardOracle` | `public` | The target `LlamaGuardOracle` contract where reports are
forwarded. | | `description` | `string` | `public` | A human-readable description of the proxy instance. | |
`workflowConfigs` | `mapping(bytes32 => WorkflowConfig)` | `internal` (inherited) | Stores validation configuration for
specific workflow IDs. | | `isReportWriteSecured` | `bool constant` | `public` (inherited) | Always `true` - security
checks for report writing are always enforced. |

**External/Public Functions**: | Function | Parameters | Returns | Access Control | Description |
|----------|------------|---------|----------------|-------------| | `setLlamaGuardOracle` |
`address newLlamaGuardOracle` | `void` | `onlyOwner` | Updates the target `LlamaGuardOracle` address. Checks for write
access on the new oracle. | | `setWorkflowConfig` | `bytes32 workflowId`, `address expectedForwarder`,
`address expectedAuthor`, `bytes10 expectedWorkflowName`, `bool isActive` | `void` | `onlyOwner` | Configures the
validation parameters for a specific workflow ID. | | `setWorkflowActive` | `bytes32 workflowId`, `bool isActive` |
`void` | `onlyOwner` | Toggles the active state of a specific workflow configuration. |

**Events**:

- `WorkflowConfigUpdated(bytes32 workflowId, address expectedForwarder, address expectedAuthor, bytes10 expectedWorkflowName, bool isActive)`:
  Emitted when a workflow configuration is set or updated.

**Access Control**:

- **Owner**: Has full control over the contract configuration, including the target oracle and workflow validation
  settings.
- **AbstractCreReceiver**: The `_processReport` function (internal) is called by the `handleReport` (or similar)
  mechanism in the parent contract, which likely validates the `msg.sender` or report signature against the
  `workflowConfigs`.

**Integration Points**:

- **LlamaGuardOracle**: Calls `updateLatestRiskRoundData` on the oracle to submit validated reports.
- **Off-chain Relayer/Forwarder**: Receives transactions from an authorized forwarder (e.g., Chainlink Functions or a
  specific keeper) containing the risk reports.

## HorizonAgentHub

**Purpose**: Acts as the central orchestration hub for Horizon-specific agents, likely facilitating the coordination and
execution of risk management actions like freezing markets.

**Inheritance**:

- `AgentHub` (from `chaos-agents`)

**Key State Variables**:

- Inherits state variables from `AgentHub` (typically managing registered agents, roles, etc., though not visible in
  this specific file).

**External/Public Functions**:

- Inherits functions from `AgentHub`. This contract is currently an empty extension, implying it uses the standard
  `AgentHub` functionality without modification for Horizon specific logic at the hub level.

**Events**:

- Inherits events from `AgentHub`.

**Access Control**:

- Inherits access control from `AgentHub`. Typically involves an owner or administrator who can register agents.

**Integration Points**:

- **Horizon Agents**: Serves as the caller for `inject` functions on agents like `HorizonFreezeAgent`.
- **Chaos Agents Framework**: extends the `AgentHub` from the `chaos-agents` library.

# Access Control Analysis

This document provides a comprehensive analysis of all access control roles, privileged functions, and ownership
patterns in the `src/` contracts.

## Access Control Matrix

| Role/Owner                        | Contract                                  | Functions Controlled                                                                                                                                                                                                                                                                                            | Impact if Compromised                                                                                                              |
| --------------------------------- | ----------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| **Owner** (Ownable2Step)          | `ParameterRegistry`                       | `setUpdater()`, `transferOwnership()`, `acceptOwnership()`                                                                                                                                                                                                                                                      | Can replace the updater address, gaining control over all asset parameters                                                         |
| **Updater**                       | `ParameterRegistry`                       | `setParametersForAsset()`, `setMaxExpectedApy()`, `setUpperBoundTolerance()`, `setLowerBoundTolerance()`, `setMaxDiscount()`, `setIsUpperBoundEnabled()`, `setIsLowerBoundEnabled()`, `setIsActionTakingEnabled()`, `setLookbackWindowSize()`, `setOracle()`, `deleteAsset()`                                   | Full control over risk parameters for all assets; could manipulate APY limits, tolerances, enable/disable bounds, or delete assets |
| **DEFAULT_ADMIN_ROLE**            | `LlamaGuardOracle`                        | `addUpdateType()`, `addAuthorizedMarket()`, `removeAuthorizedMarket()`, `grantRole()`, `revokeRole()`                                                                                                                                                                                                           | Can add malicious update types, authorize/deauthorize markets, and grant WRITER_ROLE to attackers                                  |
| **WRITER_ROLE**                   | `LlamaGuardOracle`                        | `updateLatestRiskRoundData()`                                                                                                                                                                                                                                                                                   | Can push arbitrary oracle data (prices, states); downstream consumers would receive manipulated values                             |
| **Owner** (Ownable2Step)          | `LlamaGuardOracleProxy`                   | `setLlamaGuardOracle()`, `setWorkflowConfig()`, `setWorkflowActive()`                                                                                                                                                                                                                                           | Can redirect to malicious oracle or modify/deactivate workflows                                                                    |
| **expectedForwarder** (Chainlink) | `LlamaGuardOracleProxy`                   | `onReport()` (via `AbstractCreReceiver`)                                                                                                                                                                                                                                                                        | Trusted external caller; if compromised, can push arbitrary reports to the oracle                                                  |
| **Owner** (Ownable)               | `EACAggregatorProxy`                      | `proposeAggregator()`                                                                                                                                                                                                                                                                                           | Can replace the underlying oracle with a malicious one, returning fake price data                                                  |
| **Owner**                         | `HorizonAgentHub`                         | `registerAgent()`, `setAgentAdmin()`, `setMaxBatchSize()`, `setAgentAddress()`                                                                                                                                                                                                                                  | Full control over agent registration; can register malicious agents or replace existing agent addresses                            |
| **Owner or AgentAdmin**           | `HorizonAgentHub`                         | `setAgentAsPermissioned()`, `addPermissionedSender()`, `removePermissionedSender()`, `addAllowedMarket()`, `removeAllowedMarket()`, `addRestrictedMarket()`, `removeRestrictedMarket()`, `setExpirationPeriod()`, `setAgentEnabled()`, `setMinimumDelay()`, `setAgentContext()`, `setMarketsFromAgentEnabled()` | Can enable/disable agents, modify market access, change timing constraints, or alter agent behavior via context                    |
| **PermissionedSenders**           | `HorizonAgentHub`                         | `execute()` (when agent is permissioned)                                                                                                                                                                                                                                                                        | Can trigger agent injections for specific agents; could execute unwanted protocol actions                                          |
| **AGENT_HUB** (immutable)         | `BaseHorizonAgent` / `HorizonFreezeAgent` | `inject()`, `validate()`                                                                                                                                                                                                                                                                                        | Only AgentHub can call; if compromised, can inject malicious risk parameter updates                                                |

## Critical Paths

### 1. Oracle Data Flow

```
WRITER_ROLE → LlamaGuardOracle.updateLatestRiskRoundData() → stored price/state data
```

### 2. Chainlink Workflow

```
expectedForwarder → LlamaGuardOracleProxy.onReport() → LlamaGuardOracle.updateLatestRiskRoundData()
```

### 3. Agent Execution

```
HorizonAgentHub.execute() → HorizonFreezeAgent.inject() → IPoolConfigurator.setReserveFreeze()
```

### 4. Parameter Registry

```
Updater → ParameterRegistry.setParametersForAsset() → asset risk parameters
```

## Contract-by-Contract Breakdown

### ParameterRegistry

**Access Control Model**: Two-step ownership (Ownable2Step) + custom `onlyUpdater` modifier

| Role    | Source         | Description                         |
| ------- | -------------- | ----------------------------------- |
| Owner   | `Ownable2Step` | Can set updater, transfer ownership |
| Updater | Custom role    | Can manage all asset parameters     |

### LlamaGuardOracle

**Access Control Model**: OpenZeppelin AccessControl with custom roles

| Role               | Identifier                 | Description                                        |
| ------------------ | -------------------------- | -------------------------------------------------- |
| DEFAULT_ADMIN_ROLE | `0x00`                     | Can manage roles, add update types, manage markets |
| WRITER_ROLE        | `keccak256("WRITER_ROLE")` | Can push oracle updates                            |
| READER_ROLE        | `keccak256("READER_ROLE")` | Optional read restriction (not enforced)           |

### LlamaGuardOracleProxy

**Access Control Model**: Ownable2Step + Chainlink workflow validation

| Role              | Source          | Description                                 |
| ----------------- | --------------- | ------------------------------------------- |
| Owner             | `Ownable2Step`  | Can configure oracle and workflow settings  |
| expectedForwarder | Workflow config | Chainlink forwarder that can submit reports |

### EACAggregatorProxy

**Access Control Model**: Single-step Ownable

| Role  | Source    | Description                       |
| ----- | --------- | --------------------------------- |
| Owner | `Ownable` | Can replace underlying aggregator |

### HorizonAgentHub (via AgentConfigurator)

**Access Control Model**: OwnableUpgradeable + per-agent admins

| Role                | Source               | Description                                   |
| ------------------- | -------------------- | --------------------------------------------- |
| Owner               | `OwnableUpgradeable` | Full control over hub and agent registration  |
| AgentAdmin          | Per-agent config     | Can configure specific agent settings         |
| PermissionedSenders | Per-agent set        | Can execute specific agents when permissioned |

### BaseHorizonAgent / HorizonFreezeAgent

**Access Control Model**: Immutable AGENT_HUB address

| Role      | Source                      | Description                           |
| --------- | --------------------------- | ------------------------------------- |
| AGENT_HUB | Immutable constructor param | Only caller allowed to inject updates |

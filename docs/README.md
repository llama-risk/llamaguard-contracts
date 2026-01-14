# LlamaGuard Contracts Documentation

This folder contains documentation for the LlamaGuard multi-asset parameter registry system integrated with Chainlink
oracle infrastructure and Aave Horizon markets.

## Documentation Index

### System Architecture

- **[architecture.md](./architecture.md)** — High-level system design integrating LlamaGuard NAV oracle with Aave
  Horizon markets. Includes data flow diagrams, execution flows for freeze/unfreeze operations, and state machine
  diagrams.

- **[access-control-analysis.md](./access-control-analysis.md)** — Comprehensive security analysis covering role
  hierarchies, privileged functions, and ownership patterns. Documents impact of compromising each role and critical
  execution paths.

- **[assets/data-flow-diagram.png](./assets/data-flow-diagram.png)** — Visual representation of the system architecture.

### Contract Reference

#### Oracle Contracts

| Document                                                                | Description                                                                                                                                                       |
| ----------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [LlamaGuardOracle.md](./contracts/oracle/LlamaGuardOracle.md)           | Central on-chain registry for risk parameters with AggregatorV3-compatible interface. Documents state variables, update functions, and role-based access control. |
| [LlamaGuardOracleProxy.md](./contracts/oracle/LlamaGuardOracleProxy.md) | Secure gateway for submitting risk reports with source and integrity validation. Integrates with Chainlink CRE workflow for authenticated updates.                |

#### Registry Contracts

| Document                                                          | Description                                                                                                                                             |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [ParameterRegistry.md](./contracts/registry/ParameterRegistry.md) | Central registry for asset-specific risk parameters including max APY, bound tolerances, and oracle addresses. Two-role access control (Owner/Updater). |

#### Response Agents

| Document                                                            | Description                                                                                                                     |
| ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| [BaseHorizonAgent.md](./contracts/response/BaseHorizonAgent.md)     | Abstract base contract providing common infrastructure for Horizon agents. Defines the inject pattern and AgentHub integration. |
| [HorizonAgentHub.md](./contracts/response/HorizonAgentHub.md)       | Central orchestration hub for Horizon-specific agents. Extends the chaos-agents AgentHub for risk management.                   |
| [HorizonFreezeAgent.md](./contracts/response/HorizonFreezeAgent.md) | Specialized agent for freezing Aave V3 markets when risk updates indicate a freeze command. Interacts with PoolConfigurator.    |

### Operations

- **[operational_playbook.md](./operational_playbook.md)** — Step-by-step deployment and operational guide covering
  Sepolia testing, mainnet deployment, monitoring periods, and rollback procedures.

---

## Suggested Reading Order

### For Developers

1. [architecture.md](./architecture.md) — Understand the system design
2. Contract docs in [contracts/](./contracts/) — Deep dive into specific contracts
3. [access-control-analysis.md](./access-control-analysis.md) — Understand permission model

### For Security Auditors

1. [access-control-analysis.md](./access-control-analysis.md) — Role hierarchy and attack surfaces
2. [architecture.md](./architecture.md) — Data flow and trust boundaries
3. Contract docs — Implementation details

### For Operators/Deployment Teams

1. [architecture.md](./architecture.md) — System overview
2. [operational_playbook.md](./operational_playbook.md) — Deployment procedures
3. [access-control-analysis.md](./access-control-analysis.md) — Understand what roles to configure

---

## Directory Structure

```
docs/
├── README.md                      # This file
├── architecture.md                # System design and data flows
├── access-control-analysis.md     # Security and permissions analysis
├── operational_playbook.md        # Deployment and operations guide
├── assets/
│   └── data-flow-diagram.png      # Visual architecture diagram
└── contracts/
    ├── oracle/
    │   ├── LlamaGuardOracle.md
    │   └── LlamaGuardOracleProxy.md
    ├── registry/
    │   └── ParameterRegistry.md
    └── response/
        ├── BaseHorizonAgent.md
        ├── HorizonAgentHub.md
        └── HorizonFreezeAgent.md
```

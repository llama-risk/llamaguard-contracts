# LlamaGuard Contracts

Smart contracts for on-chain risk parameter delivery with Chainlink AggregatorV3 compatibility and automated response
agents for Aave Horizon integration.

## Features

- **AggregatorV3 Compatibility**: Seamless integration with existing DeFi protocols using Chainlink interfaces
- **Role-Based Access Control**: Granular permissions with admin, reader, and writer roles
- **CRE Integration**: Native support for Chainlink Compute Runtime Environment reports
- **Historical Tracking**: Query past updates with O(1) lookups by update type
- **Multi-Asset Support**: Manage parameters for multiple assets independently
- **Horizon Response Agents**: Automated agents for executing protocol actions based on oracle state (e.g., freezing
  markets)

## Contracts

### LlamaGuardOracle

Core oracle contract for storing and exposing risk parameter updates.

- Chainlink AggregatorV3 interface compatibility
- Role-based access control (admin, reader, writer)
- Typed update categories with validation
- Historical update tracking
- Market authorization management

### LlamaGuardOracleProxy

Receiver contract for Chainlink CRE (Compute Runtime Environment) reports.

- Validates incoming reports against expected workflow parameters
- Forwards decoded updates to the LlamaGuardOracle

### ParameterRegistry

Multi-asset parameter registry for offchain oracle network consumption.

- Manage parameters for multiple assets independently
- Owner manages the updater role, updater manages parameters

### HorizonAgentHub

Orchestration hub for Horizon response agents, extending the AgentHub.

- Coordinates agent execution for automated protocol responses

### BaseHorizonAgent

Abstract base contract for Horizon agents compatible with AgentHub.

- Defines inject/validate interface for risk parameter updates
- Integrates with Aave V3 Pool for reserve operations
- Provides market discovery via `getMarkets()`

### HorizonFreezeAgent

Agent for freezing Aave Horizon markets based on LlamaGuard oracle state.

- Automatically freezes reserves when freeze state is detected
- Defense-in-depth validation before execution
- One-way freeze only (unfreezing requires manual multisig intervention)

## Installation

```sh
bun install
```

## Build

```sh
forge build
```

## Test

```sh
forge test
```

Run with gas report:

```sh
forge test --gas-report
```

Run with coverage:

```sh
forge coverage
```

## Deploy

Deploy to Anvil:

```sh
forge script script/Deploy.s.sol --broadcast --fork-url http://localhost:8545
```

Deploy to testnet/mainnet:

```sh
forge script script/DeployParameterRegistry.s.sol --rpc-url <RPC_URL> --broadcast --verify
```

## Format

```sh
forge fmt
```

## Audits

See [`audit/`](./audit) for security reviews and the onchain contracts specification. The Trail of Bits
February 2026 review is also published at
[trailofbits/publications](https://github.com/trailofbits/publications/blob/master/reviews/2026-02-chainlink-llamariskllamaguardnavcre-securityreview.pdf).

## License

BUSL-1.1

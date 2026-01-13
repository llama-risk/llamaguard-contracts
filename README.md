# LlamaGuard Contracts

Smart contracts for on-chain risk parameter delivery with Chainlink AggregatorV3 compatibility.

## Features

- **AggregatorV3 Compatibility**: Seamless integration with existing DeFi protocols using Chainlink interfaces
- **Role-Based Access Control**: Granular permissions with admin, reader, and writer roles
- **CRE Integration**: Native support for Chainlink Compute Runtime Environment reports
- **Historical Tracking**: Query past updates with O(1) lookups by update type
- **Multi-Asset Support**: Manage parameters for multiple assets independently

## Contracts

### LlamaGuardOracle

Core oracle contract for storing and exposing risk parameter updates.

- Chainlink AggregatorV3 interface compatibility
- Role-based access control (admin, reader, writer)
- Typed update categories with validation
- Historical update tracking

### LlamaGuardOracleProxy

Receiver contract for Chainlink CRE (Compute Runtime Environment) reports.

- Validates incoming reports against expected workflow parameters
- Forwards decoded updates to the LlamaGuardOracle

### ParameterRegistry

Multi-asset parameter registry for offchain oracle network consumption.

- Manage parameters for multiple assets independently
- Owner manages the updater role, updater manages parameters

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

## License

BUSL-1.1

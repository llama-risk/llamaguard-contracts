# Parameter Registry

A multi-asset parameter registry contract for offchain oracle network consumption.

## Features

- **Multi-Asset Support**: Manage parameters for multiple assets independently
- **Role-Based Access**: Owner manages the updater role, updater manages parameters
- **Parameter Management**: Set APY bounds, tolerances, and control flags per asset
- **Asset Lifecycle**: Add, update, and delete asset configurations

## Contract Structure

### Roles
- **Owner**: Can transfer ownership and set the updater address
- **Updater**: Can manage asset parameters

### Parameters Per Asset
- `maxExpectedApy`: Maximum expected annual percentage yield (basis points)
- `upperBoundTolerance`: Upper bound tolerance (basis points)
- `lowerBoundTolerance`: Lower bound tolerance (basis points)
- `isUpperBoundEnabled`: Enable/disable upper bound checks
- `isLowerBoundEnabled`: Enable/disable lower bound checks
- `isActionTakingEnabled`: Enable/disable action taking

## Installation

```sh
forge install
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

Required environment variables:
- `OWNER_ADDRESS`: Contract owner address
- `UPDATER_ADDRESS`: Initial updater address

## Format

```sh
forge fmt
```

## License

BUSL-1.1
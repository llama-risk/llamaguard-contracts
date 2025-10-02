# LlamaGuard Oracle

LlamaGuard Oracle is a smart price feed oracle that is being written to by a CRE workflow.

## Overview

This project implements an oracle system that:

- Receives off-chain reports from CRE workflow
- Validates workflow ownership and metadata
- Stores supply, price, and state data on-chain
- Exposes price feed through Chainlink AggregatorV3 interface

## Architecture

### Contracts

- **LlamaGuardOracle**: Main oracle contract with Ownable2Step access control
- **LlamaGuardOracleProxy**: Proxy contract implementing IReceiverTemplate for workflow validation
- **AggregatorV3**: Chainlink-compatible price feed interface
- **IReceiverTemplate**: Abstract base contract for metadata decoding and validation

## Installation

```bash
# Install dependencies
bun install

# Build contracts
forge build
```

## Testing

```bash
# Run all tests
forge test

# Run tests with verbosity
forge test -vv

# Generate coverage report
bun run test:coverage
```

## Deployment

TODO

## Development

### Linting

```bash
# Check Solidity style
bun run lint:sol

# Check formatting
bun run prettier:check

# Auto-fix formatting
bun run prettier:write
```

### Gas Reports

Gas reports are automatically generated during tests. See `foundry.toml` configuration.

## Security

- Access control via Ownable2Step (two-step ownership transfer)
- Proxy-only updates (onlyProxy modifier)
- Workflow validation (author + workflow name verification)
- ERC165 interface support


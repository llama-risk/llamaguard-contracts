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

### Configuration

Before deploying, configure the target network in `script/DeployConfig.sol`:

```solidity
function getMainnetConfig() public pure returns (Config memory) {
    return Config({
        expectedAuthor: address(0x...), // Set CRE workflow author
        expectedWorkflowName: bytes10("YOUR_FLOW"),
        decimals: 8,
        description: "LlamaGuard Oracle - Mainnet",
        version: 1,
        pendingOwner: address(0x...), // Set final owner
        networkName: "mainnet"
    });
}
```

### Deployment Options

#### Option 1: Deploy with Configuration (Recommended)

Deploys both contracts, configures proxy, and optionally transfers ownership:

```bash
# Using chain-specific config from DeployConfig.sol
forge script script/DeployLlamaGuardOracle.s.sol:DeployLlamaGuardOracle \
  --rpc-url mainnet \
  --broadcast \
  --verify

# Using environment variables
USE_ENV_CONFIG=true \
EXPECTED_AUTHOR=0x... \
EXPECTED_WORKFLOW_NAME=0x5445535446... \
PENDING_OWNER=0x... \
forge script script/DeployLlamaGuardOracle.s.sol:DeployLlamaGuardOracle \
  --rpc-url mainnet \
  --broadcast \
  --verify
```

#### Option 2: Mainnet-Specific Deployment

Uses dedicated mainnet script with additional safety checks:

```bash
forge script script/DeployMainnet.s.sol:DeployMainnet \
  --rpc-url mainnet \
  --broadcast \
  --verify
```

#### Option 3: Step-by-Step Deployment

Deploy, configure, and transfer ownership separately:

```bash
# 1. Deploy only
forge script script/DeployLlamaGuardOracle.s.sol:DeployLlamaGuardOracle \
  --sig "deployOnly()" \
  --rpc-url mainnet \
  --broadcast

# 2. Configure with proxy
forge script script/DeployLlamaGuardOracle.s.sol:DeployLlamaGuardOracle \
  --sig "configureManually(address,address)" <ORACLE_ADDRESS> <PROXY_ADDRESS> \
  --rpc-url mainnet \
  --broadcast

# 3. Transfer ownership
forge script script/DeployLlamaGuardOracle.s.sol:DeployLlamaGuardOracle \
  --sig "transferOwnershipManually(address)" <ORACLE_ADDRESS> \
  --rpc-url mainnet \
  --broadcast
```

### Local Testing

Test deployment on Anvil:

```bash
# Start Anvil
anvil

# Deploy to local network
forge script script/DeployLlamaGuardOracle.s.sol:DeployLlamaGuardOracle \
  --rpc-url localhost \
  --broadcast
```

### Post-Deployment

After deployment with ownership transfer:

1. **Accept Ownership**: New owner must call `acceptOwnership()` on the oracle
2. **Verify Contracts**: Check on Etherscan that contracts are verified
3. **Test Update**: Send a test report through the proxy to verify functionality

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


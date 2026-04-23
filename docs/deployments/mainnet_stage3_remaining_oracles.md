# Stage 3: Remaining Oracle Infrastructure Deployment

**Network:** Ethereum Mainnet (Chain ID: 1) **Deployer:** `0x9118964074e2AA11393ce0797264759dB2F2ef69` **Script:**
`script/3_DeployRemainingOracles.s.sol` **Date:** 2026-03-01

## Deployed Contracts

| Asset | Contract              | Address                                      |
| ----- | --------------------- | -------------------------------------------- |
| USCC  | LlamaGuardOracle      | `0x8f1dff6D95f4D6A9E10416B834D5918bE1Eb5802` |
| USCC  | LlamaGuardOracleProxy | `0x3606A9Ab8D47EE31A6cC1134fA6995B7d16DB529` |
| USYC  | LlamaGuardOracle      | `0x228Cb3e49EAeb10dD1B56Eeae0A8cBffD0bdF2A4` |
| USYC  | LlamaGuardOracleProxy | `0x7cf933fc475da2E3b45FA207d7df2EF9855c0B60` |
| JTRSY | LlamaGuardOracle      | `0x74c0e98b5853e418219D6bF87fD26A73182F8876` |
| JTRSY | LlamaGuardOracleProxy | `0x069f65edEC8FbC6bd7c0C03104d9beC350F0A1C1` |
| JAAA  | LlamaGuardOracle      | `0x8fA713d4E79238E5f6eB7479bEF0B7CFA51a9Ada` |
| JAAA  | LlamaGuardOracleProxy | `0xb3fF4a48DEf4d1D2249180F02Ce505668aFd8D46` |
| ACRED | LlamaGuardOracle      | `0xE952F28c9DB1424e120d8c78aA174B0dC98200B9` |
| ACRED | LlamaGuardOracleProxy | `0xE5d4D8500D73fb30E0941C8A3BA1e47F06A9bF5F` |

## Oracle Decimals

| Asset | Token Decimals | Oracle Decimals |
| ----- | :------------: | :-------------: |
| USCC  |       6        |        6        |
| USYC  |       6        |        8        |
| JTRSY |       6        |        6        |
| JAAA  |       6        |        6        |
| ACRED |       6        |        8        |

## Configuration Applied

For each asset:

- `WRITER_ROLE` granted to `LlamaGuardOracleProxy` on `LlamaGuardOracle`
- Token address added as authorized market on oracle

## Current Ownership

| Contract                      | Role                 | Holder                     |
| ----------------------------- | -------------------- | -------------------------- |
| All 5 LlamaGuardOracles       | `DEFAULT_ADMIN_ROLE` | Deployer (`0x9118...ef69`) |
| All 5 LlamaGuardOracleProxies | Owner                | Deployer (`0x9118...ef69`) |

## What's NOT Activated

- CRE workflow not configured on oracle proxies (deployed with zero params — configured via
  `1a_ConfigureCreWorkflow.s.sol` after Chainlink provides parameters)
- Ownership not yet transferred to final parties

## Next Steps

1. **Stage 1a** — Configure CRE workflow params on all proxies once Chainlink provides workflow ID, forwarder, author,
   and workflow name
2. **Stage 4** — Run `4_ActivateAllAssets` to register agents in AgentHub for all assets
3. Transfer ownership to LlamaRisk multisig (`0xE6ec1f0Ae6Cd023bd0a9B4d0253BDC755103253c`)

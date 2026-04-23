# Deployment Scripts

Scripts are organized by deployment stage. Each stage has ONE script so external parties (Chainlink, Horizon) can follow
along. All configuration lives in `config/`.

## Deployment Stages (Mainnet)

### Stage 1 — `1_DeployUstbInfrastructure.s.sol`

Deploys all contracts for the USTB pilot. **Nothing is activated.**

- Deploy `LlamaGuardOracle(USTB)` + `LlamaGuardOracleProxy(USTB)`
- Grant `WRITER_ROLE` to proxy on oracle
- Add USTB token as authorized market
- Deploy `HorizonAgentHub` (behind `TransparentUpgradeableProxy` + `initialize`)
- Deploy `HorizonFreezeAgent(agentHub, pool)`

```bash
forge script script/1_DeployUstbInfrastructure.s.sol --rpc-url $RPC_URL --broadcast
```

### Stage 1a — `1a_ConfigureCreWorkflow.s.sol`

Configures Chainlink CRE workflow details on deployed oracle proxies. Called after Stage 1 once Chainlink provides the
CRE parameters. Reads config from `config/CreConfig.sol`.

- Set workflow ID, forwarder, author, and workflow name on the proxy
- Activates the workflow
- Supports single-asset or batch configuration

> **Note:** The proxy is deployed in Stage 1 with placeholder (zero) CRE params. Update `CreConfig.sol` with the real
> values, then run this script.

```bash
# Single asset
forge script script/1a_ConfigureCreWorkflow.s.sol --sig "run(string)" "USTB" --rpc-url $RPC_URL --broadcast

# All assets at once
forge script script/1a_ConfigureCreWorkflow.s.sol --sig "runAll()" --rpc-url $RPC_URL --broadcast
```

### Stage 2 — `2_ActivateUstbPilot.s.sol`

Registers the FreezeAgent in AgentHub for USTB. Takes deployed addresses from Stage 1 as parameters.

- Register FreezeAgent with permissioned access (LlamaRisk multisig only)

> **Note:** Chainlink separately switches their `EACAggregatorProxy` to point to our USTB oracle.

```bash
forge script script/2_ActivateUstbPilot.s.sol --sig "run(address,address,address)" $AGENT_HUB $FREEZE_AGENT $USTB_ORACLE --rpc-url $RPC_URL --broadcast
```

### Stage 3 — `3_DeployRemainingOracles.s.sol`

Deploys oracle infrastructure for the remaining 5 assets: USCC, USYC, JTRSY, JAAA, ACRED.

For each asset:

- Deploy `LlamaGuardOracle` + `LlamaGuardOracleProxy`
- Grant `WRITER_ROLE` to proxy on oracle
- Add token as authorized market

```bash
forge script script/3_DeployRemainingOracles.s.sol --rpc-url $RPC_URL --broadcast
```

### Stage 4 — `4_ActivateAllAssets.s.sol`

Registers remaining 5 assets in AgentHub. Takes deployed addresses from Stage 3 as parameters.

- Register FreezeAgent for each asset (same permissioned config as USTB)

> **Note:** Chainlink separately switches their proxies for each asset.

```bash
forge script script/4_ActivateAllAssets.s.sol --sig "run(address,address,address[5])" $AGENT_HUB $FREEZE_AGENT "[$USCC_ORACLE,$USYC_ORACLE,$JTRSY_ORACLE,$JAAA_ORACLE,$ACRED_ORACLE]" --rpc-url $RPC_URL --broadcast
```

### Stage 5 — `5_TransferOwnership.s.sol`

Transfers ownership of all deployed contracts to their final parties.

For each oracle:

- Grant `DEFAULT_ADMIN_ROLE` to new admin
- Renounce `DEFAULT_ADMIN_ROLE` from deployer

For each oracle proxy:

- `transferOwnership` (two-step — new owner must call `acceptOwnership` separately)

For HorizonAgentHub:

- Transfer `ProxyAdmin` ownership to Aave Horizon (single-step, immediate)

```bash
forge script script/5_TransferOwnership.s.sol --sig "run(address[],address[],address,address,address)" $ORACLE_ADDRS $PROXY_ADDRS $NEW_ADMIN $AGENT_HUB_PROXY_ADMIN $AAVE_HORIZON_ADMIN --rpc-url $RPC_URL --broadcast
```

---

## Sepolia Scripts

Located in `sepolia/`.

| Script                         | Purpose                                                                                        |
| ------------------------------ | ---------------------------------------------------------------------------------------------- |
| `DeploySepoliaInfra.s.sol`     | Full Sepolia deployment — oracles, proxies, EAC proxies, oracle seeding, AgentHub, FreezeAgent |
| `SepoliaIntegrationTest.s.sol` | Activate system + verify full freeze flow (register agents, push updates, execute freeze)      |
| `EACAggregatorProxy.sol`       | Chainlink aggregator proxy mock (Sepolia-only contract)                                        |

---

## Parameter Registry Scripts

Located in `parameter-registry/`. The ParameterRegistry is already deployed on mainnet.

| Script                          | Purpose                                                                         |
| ------------------------------- | ------------------------------------------------------------------------------- |
| `DeployParameterRegistry.s.sol` | Deploy a new `ParameterRegistry` with deployer as initial owner/updater         |
| `ConfigureAssets.s.sol`         | Configure assets on an existing registry (auto-detects chain)                   |
| `ValidateAssetConfigs.s.sol`    | On-chain validation of asset configs (calls `symbol()`, oracle `description()`) |

---

## Config

Located in `config/`. Single source of truth for all deployment parameters.

| File                | Description                                                                                               |
| ------------------- | --------------------------------------------------------------------------------------------------------- |
| `DeployStructs.sol` | Shared struct definitions (`OracleConfig`, `ProxyConfig`, `AgentRegistrationConfig`, `AssetConfig`, etc.) |
| `Addresses.sol`     | Well-known addresses per network (deployer, multisig, tokens, oracles, Aave contracts)                    |
| `MainnetConfig.sol` | Mainnet oracle, agent, and asset configurations (USTB, USCC, USYC, JTRSY, JAAA, ACRED, vBILL)             |
| `SepoliaConfig.sol` | Sepolia configurations (USCC, USTB) with seed configs for oracle seeding                                  |
| `AnvilConfig.sol`   | Local test configurations for Anvil                                                                       |
| `CreConfig.sol`     | Chainlink CRE workflow configurations per asset (workflow ID, forwarder, author, workflow name)           |

---

## Base

`Base.s.sol` — Shared base contract for all scripts. Resolves the broadcaster address from `$ETH_FROM` or `$MNEMONIC`
env vars and provides the `broadcast` modifier.

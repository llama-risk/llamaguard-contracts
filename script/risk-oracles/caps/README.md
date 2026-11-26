# Caps deployment scripts

One set of steps for every caps deployment. Each step reads `config/<label>.json`, the asset values file it names in
`assets/`, and the deployment so far in `deployments/<label>.json`.

| Step | Script                    | What it does                                                                                          |
| ---- | ------------------------- | ----------------------------------------------------------------------------------------------------- |
| 0    | `0_DeployShadow.s.sol`    | Shadow deployments only: our own AgentHub and a ShadowPool in front of the real Pool                  |
| 1    | `1_DeployCaps.s.sol`      | RiskOracle, Router, registry, RVM, reducer, raise and cut agents. Constructors only                   |
| 2    | `2_WireCaps.s.sol`        | One-time connections: RiskOracle, Router roles, both agents on the hub, RVM agents and bounds, market |
| 3    | `3_ConfigureAssets.s.sol` | First values of each borrow cap key: RVM entry, then registry key. Checks coverage of the reserves    |
| 4    | `4_AddRoute.s.sol`        | Router route and throttle off, in the same sitting as `cre workflow deploy`                           |

A call is sent when the broadcaster holds the role on chain, and printed as a Safe batch otherwise. On staging the hot
wallet holds every role. On production the same steps print the batches for the Safes and the AIP.

## Running a step

```bash
export CAPS_DEPLOYMENT=arbitrum-core-staging ETH_FROM=<deployer in the config>
forge script script/risk-oracles/caps/1_DeployCaps.s.sol \
  --rpc-url "$ARBITRUM_RPC_URL" --account <keystore> --sender "$ETH_FROM"
```

Without `--broadcast` it is a dry run: the addresses are simulated and `deployments/` is not written. Add
`--broadcast --verify` once the dry run looks right, then commit the deployment file.

Step 4 takes the workflow id and name that `cre workflow hash` prints for the exact wasm and config being deployed:

```bash
forge script script/risk-oracles/caps/4_AddRoute.s.sol --sig "run(bytes32,bytes10)" <workflowId> <workflowName> \
  --rpc-url "$ARBITRUM_RPC_URL" --account <keystore> --sender "$ETH_FROM" --broadcast
```

## Files

- **Config.** Market, roles, agent timing, RVM bounds, registry defaults and the route. Any `"TODO"` stops the step
  before it sends anything.
- **Asset values.** Per borrowable reserve: `maxCap` (`"current"` is the cap the stack sees when step 3 runs),
  `maxHeadroom` in whole tokens, `alphaBps`, `cutBandBps`. Reserves that are not borrowable go in `skip`. Step 3 reverts
  if a borrowable reserve is in neither list. Later changes go through llamaguard-ci with the same fields.
- **Deployments.** Written by steps 0 to 2 on a real broadcast only.

## Shadow deployments

With `"shadow": true` the stack runs on a ShadowPool (`src/staging/ShadowPool.sol`): every read is the real Pool's,
except the borrow cap, which is Aave's until one of our agents writes it. Nothing reaches Aave.

Tests: `tests/staging/`. The Arbitrum fork test runs steps 0 to 4 on the staging config:

```bash
ARBITRUM_RPC_URL=... FOUNDRY_PROFILE=fork forge test --match-path 'tests/staging/*'
```

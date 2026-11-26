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

## Production: Arbitrum Core

`config/arbitrum-core-production.json` runs on the real Pool and Aave's AgentHub. The deployer only holds the RiskOracle
and the Router until it hands them over, so most calls print instead of sending:

| Who                                | Holds                                                         | Signs                                                                              |
| ---------------------------------- | ------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| Deployer (prod EOA)                | RiskOracle and Router until the hand-over                     | step 1, the RiskOracle and Router calls of step 2, the route of step 4             |
| Aave Executor lvl 1                | AgentHub, RVM and registry owner                              | the AIP: agent registration, RVM agents, bounds and entries (printed by steps 2-3) |
| `LLAMARISK_RISK_ORACLE_ADMIN_SAFE` | RiskOracle and Router owner, Router updater, registry updater | registry market and reserves, Router `acceptOwnership`, route throttle and routes  |
| Protocol Guardian                  | agent admin, Router guardian                                  | nothing at deployment                                                              |

`roles.deployer` is `"TODO"` until the prod EOA is chosen, so nothing runs before that. Order:

1. Step 1 from the prod EOA, `--broadcast --verify`. Commit `deployments/arbitrum-core-production.json`.
2. Step 2. The deployer sends the RiskOracle and Router calls and starts both hand-overs. It prints the AIP batch
   (executor) and the admin Safe batch (registry market). The agent ids are predicted from the hub's agent count; the
   AIP reverts if they differ.
3. Step 3. Sends nothing; prints the RVM entries (AIP) and the registry reserves (admin Safe).
4. Step 4 for the raise workflow, before the admin Safe accepts the Router: the deployer is still the owner and adds the
   route, and the throttle prints for the admin Safe. The keeper route has the cut agent only and goes through the same
   owner:

   ```bash
   cast send <router> 'addRoute(bytes32,address,address,bytes10,address,bytes4,address,uint256[],uint64)' \
     <keeperWorkflowId> <forwarder> <workflowOwner> <keeperWorkflowName> <riskOracle> 0x031ed79c <agentHub> \
     '[<cutAgentId>]' 360
   ```

   Workflow ids come from `cre workflow hash --public_key <workflowOwner>` with the production configs.

5. Admin Safe: the step 2 and 3 batches, both throttles off, then `acceptOwnership` on the Router.
6. Aave's CRE owner deploys both workflows; the AIP executes.

## Shadow deployments

With `"shadow": true` the stack runs on a ShadowPool (`src/staging/ShadowPool.sol`): every read is the real Pool's,
except the borrow cap, which is Aave's until one of our agents writes it. Nothing reaches Aave.

Tests: `tests/staging/`. The Arbitrum fork test runs steps 0 to 4 on the staging config:

```bash
ARBITRUM_RPC_URL=... FOUNDRY_PROFILE=fork forge test --match-path 'tests/staging/*'
```

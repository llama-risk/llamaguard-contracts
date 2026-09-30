# Avalanche NAV ParameterRegistry Deployment

**Network:** Avalanche C-Chain (Chain ID: 43114) **Deployer:** `0x2aAFe923C6440855b0Cbb87117135a5BC39eE320` **Script:**
`script/parameter-registry/avalanche/DeployAvalancheParameterRegistry.s.sol` **Date:** 2026-09-30

## Deployed Contract

| Contract                   | Address                                      |
| -------------------------- | -------------------------------------------- |
| AvalancheParameterRegistry | `0x23B81c8374A99A0648ee951750839b1AE486E203` |

| Field        | Value                                                                |
| ------------ | -------------------------------------------------------------------- |
| Transaction  | `0x7c63d387e680a3447430a0349ca814ee595b55c0de69052ae5fdc313cd387a0a` |
| Block        | 96,476,882 (2026-09-30 19:50:49 UTC)                                 |
| Source       | `d45aa12`, `src/AvalancheParameterRegistry.sol`                      |
| Compiler     | solc 0.8.27, optimizer 10,000 runs, EVM shanghai                     |
| Verification | Verified on Snowtrace. The runtime bytecode matches the artifact.    |

`AvalancheParameterRegistry` is a copy of `ParameterRegistry`. Only the contract name and `MAX_DISCOUNT_LIMIT` differ.

## Current Ownership

The constructor set both roles. The deployer holds no role.

| Role           | Holder                                                                                     |
| -------------- | ------------------------------------------------------------------------------------------ |
| `owner`        | Aave governance executor `0x3C06dce358add17aAf230f2234bCCC4afd50d090` (`EXECUTOR_LVL_1`) |
| `pendingOwner` | `0x0000000000000000000000000000000000000000`                                               |
| `updater`      | Avalanche Risk Council safe `0xCa66149425E7DC8f81276F6D80C4b486B9503D1a` (2-of-2)          |

The owner can only rotate the updater. The updater writes all asset parameters.

## Limits

| Constant                    | Value      |
| --------------------------- | ---------- |
| `MAX_DISCOUNT_LIMIT`        | 1,000 bps  |
| `MAX_LOWER_BOUND_TOLERANCE` | 250 bps    |
| `MAX_UPPER_BOUND_TOLERANCE` | 250 bps    |
| `MAX_EXPECTED_APY_LIMIT`    | 20,000 bps |

## State

The registry has no assets. The updater adds each asset with `setParametersForAsset`.

# Avalanche NAV ParameterRegistry Deployment

**Network:** Avalanche C-Chain (Chain ID: 43114) **Deployer:** `0x2aAFe923C6440855b0Cbb87117135a5BC39eE320` **Script:**
`script/parameter-registry/avalanche/DeployAvalancheParameterRegistry.s.sol` **Date:** 2026-09-30

## Deployed Contract

| Contract          | Address                                      |
| ----------------- | -------------------------------------------- |
| ParameterRegistry | `0x7CBFF0Bd45f75a80aBF9F7a235A6a59A69539252` |

| Field        | Value                                                                |
| ------------ | -------------------------------------------------------------------- |
| Transaction  | `0x4f2ce69f97c8e38bf31bb960e7b687f969d10466c1076371e17f742dfd1ab8b7` |
| Block        | 96,475,649 (2026-09-30 19:24:33 UTC)                                 |
| Source       | `09e2a0a`                                                            |
| Compiler     | solc 0.8.27, optimizer 10,000 runs, EVM shanghai                     |
| Verification | Verified on Snowtrace. The runtime bytecode matches the artifact.    |

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
| `MAX_DISCOUNT_LIMIT`        | 250 bps    |
| `MAX_LOWER_BOUND_TOLERANCE` | 250 bps    |
| `MAX_UPPER_BOUND_TOLERANCE` | 250 bps    |
| `MAX_EXPECTED_APY_LIMIT`    | 20,000 bps |

## State

The registry has no assets. The updater adds each asset with `setParametersForAsset`.

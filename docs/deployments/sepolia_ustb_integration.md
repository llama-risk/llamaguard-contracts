# Sepolia USTB Integration Deployment

**Network:** Sepolia Testnet (Chain ID: 11155111) **Deployer:** `0x9118964074e2AA11393ce0797264759dB2F2ef69` **Script:**
`script/sepolia/DeploySepoliaUstb.s.sol`

## Purpose

Deploy USTB oracle infrastructure on Sepolia for live CRE integration testing with Horizon. A cron job feeds real USTB
prices to a writable `RawNAVOracle`, CRE picks up events and updates `LlamaGuardOracle` via the proxy, and Horizon lists
the `EACAggregatorProxy` for USTB.

## Deployed Contracts

| Contract                         | Address                                      | Decimals | Etherscan                                                                               |
| -------------------------------- | -------------------------------------------- | -------- | --------------------------------------------------------------------------------------- |
| LlamaGuardOracle (USTB)          | `0x54F2879D0a903B864782A40D67776aE53871B166` | 6        | [View](https://sepolia.etherscan.io/address/0x54F2879D0a903B864782A40D67776aE53871B166) |
| LlamaGuardOracleProxy (USTB)     | `0x2B079561590C6ACfb6af3C4aF5Bc3927acc98bD2` | —        | [View](https://sepolia.etherscan.io/address/0x2B079561590C6ACfb6af3C4aF5Bc3927acc98bD2) |
| EACAggregatorProxy               | `0x3046553a69a4dBD2aB2AccB30Cbf7C8d8db84D79` | —        | [View](https://sepolia.etherscan.io/address/0x3046553a69a4dBD2aB2AccB30Cbf7C8d8db84D79) |
| RawNAVOracle                     | `0xba88Da783C44DC01dBC828a2Cf7F9eB4C5E2A620` | 6        | [View](https://sepolia.etherscan.io/address/0xba88Da783C44DC01dBC828a2Cf7F9eB4C5E2A620) |
| HorizonAgentHub (proxy)          | `0x1DcDe45392E4fE8c1a9D60AaE5dd01057c234C68` | —        | [View](https://sepolia.etherscan.io/address/0x1DcDe45392E4fE8c1a9D60AaE5dd01057c234C68) |
| HorizonAgentHub (implementation) | `0xe3654B4277767BEf520625FB4D7D82cd14C7E26B` | —        | [View](https://sepolia.etherscan.io/address/0xe3654B4277767BEf520625FB4D7D82cd14C7E26B) |
| HorizonAgentHub (ProxyAdmin)     | `0xC7a06948557a3998375ec8388786e024Bd2D2d45` | —        | [View](https://sepolia.etherscan.io/address/0xC7a06948557a3998375ec8388786e024Bd2D2d45) |
| HorizonFreezeAgent               | `0xC363afB380cd6C972Fd8219d9f51F3f6b05CD60c` | —        | [View](https://sepolia.etherscan.io/address/0xC363afB380cd6C972Fd8219d9f51F3f6b05CD60c) |

### Deprecated (replaced)

| Contract                   | Address                                      | Notes                                        |
| -------------------------- | -------------------------------------------- | -------------------------------------------- |
| LlamaGuardOracle (USTB) v1 | `0x08bFEb45bA1437708bB6FBDBa94E04Df0a9F8045` | 8 decimals — replaced with 6 decimal version |
| RawNAVOracle v1            | `0xdCb47643002c3259912e1bA65b53b92F81e93703` | 8 decimals — replaced with 6 decimal version |

## Configuration Applied

- `WRITER_ROLE` granted to `LlamaGuardOracleProxy` (`0x2B07...8bD2`) on `LlamaGuardOracle`
- `WRITER_ROLE` granted to deployer (`0x9118...ef69`) on `LlamaGuardOracle` (for direct seeding before CRE is active)
- SEPOLIA_USTB token (`0x39727692cF58137Bd8c401eFE87Cc8A190D62ead`) added as authorized market on oracle
- Oracle seeded with price `10994190` (10.994190 USD, 6 decimals)
- `RawNAVOracle` (6 decimals) initialized with same seed price
- HorizonAgentHub initialized with deployer as owner
- HorizonFreezeAgent linked to AgentHub and Sepolia Aave Horizon Pool (`0x553aA902Df9C6770c43Ef047cDD13431Ecdf09fF`)
- Proxy swapped from old oracle (`0x08bF`) to new oracle (`0x54F2`) via `setLlamaGuardOracle()`
- EACAggregatorProxy swapped from old oracle to new oracle via `proposeAggregator()`

## CRE Workflow Parameters

| Parameter     | Value                                                                |
| ------------- | -------------------------------------------------------------------- |
| Workflow ID   | `0x00a9cf308e875f62fb6df1f6e1a55dd7db46384876e4059c35abd54125a9c1af` |
| Forwarder     | `0xDB9DE209C276E14bd36aAc18A1f551e09586e8Ba`                         |
| Author        | `0x4EDEaFc9b862F08464423EFe9423153B22B28f17`                         |
| Workflow Name | `llamaguard_nav_ustb_dev` (bytes10: `0x32336262336637396562`)        |

## Current Ownership

| Contract                   | Role                 | Holder                     |
| -------------------------- | -------------------- | -------------------------- |
| LlamaGuardOracle           | `DEFAULT_ADMIN_ROLE` | Deployer (`0x9118...ef69`) |
| LlamaGuardOracleProxy      | Owner                | Deployer (`0x9118...ef69`) |
| EACAggregatorProxy         | Owner                | Deployer (`0x9118...ef69`) |
| RawNAVOracle               | Owner                | Deployer (`0x9118...ef69`) |
| HorizonAgentHub            | Owner                | Deployer (`0x9118...ef69`) |
| HorizonAgentHub ProxyAdmin | Owner                | Deployer (`0x9118...ef69`) |

## Architecture

```
Cron Job ──writes──► RawNAVOracle (0xba88) ──event──► CRE Workflow
                                                        │
Deployer ──bad write─► RawNAVOracle (0xba88) ──event──► │
                                                        ▼
                                              LlamaGuardOracleProxy (0x2B07)
                                                        │
                                                        ▼
                                              LlamaGuardOracle (0x54F2, 6 dec)
                                                  │           │
                                                  ▼           ▼
                                           EACAggregatorProxy  AgentHub (0x1DcD)
                                           (0x3046)               │
                                           Horizon lists          ▼
                                                          FreezeAgent (0xC363)
                                                                │
                                                                ▼
                                                          Horizon Pool
                                                          (0x553a)
```

## Verification Commands

```bash
# Oracle decimals (should be 6)
cast call 0x54F2879D0a903B864782A40D67776aE53871B166 "decimals()(uint8)" --rpc-url sepolia

# Oracle has seed data
cast call 0x54F2879D0a903B864782A40D67776aE53871B166 "latestAnswer()(int256)" --rpc-url sepolia

# Deployer has write access
cast call 0x54F2879D0a903B864782A40D67776aE53871B166 "hasWriteAccess(address)(bool)" 0x9118964074e2AA11393ce0797264759dB2F2ef69 --rpc-url sepolia

# Proxy has write access
cast call 0x54F2879D0a903B864782A40D67776aE53871B166 "hasWriteAccess(address)(bool)" 0x2B079561590C6ACfb6af3C4aF5Bc3927acc98bD2 --rpc-url sepolia

# USTB market authorized
cast call 0x54F2879D0a903B864782A40D67776aE53871B166 "isAuthorizedMarket(address)(bool)" 0x39727692cF58137Bd8c401eFE87Cc8A190D62ead --rpc-url sepolia

# EAC returns seeded price (6 decimals)
cast call 0x3046553a69a4dBD2aB2AccB30Cbf7C8d8db84D79 "latestRoundData()(uint80,int256,uint256,uint256,uint80)" --rpc-url sepolia

# EAC points to new oracle
cast call 0x3046553a69a4dBD2aB2AccB30Cbf7C8d8db84D79 "aggregator()(address)" --rpc-url sepolia

# Proxy points to new oracle
cast call 0x2B079561590C6ACfb6af3C4aF5Bc3927acc98bD2 "llamaguardOracle()(address)" --rpc-url sepolia

# RawNAVOracle returns initial price
cast call 0xba88Da783C44DC01dBC828a2Cf7F9eB4C5E2A620 "latestRoundData()(uint80,int256,uint256,uint256,uint80)" --rpc-url sepolia

# RawNAVOracle owned by deployer
cast call 0xba88Da783C44DC01dBC828a2Cf7F9eB4C5E2A620 "owner()(address)" --rpc-url sepolia

# AgentHub owned by deployer
cast call 0x1DcDe45392E4fE8c1a9D60AaE5dd01057c234C68 "owner()(address)" --rpc-url sepolia

# FreezeAgent points to hub
cast call 0xC363afB380cd6C972Fd8219d9f51F3f6b05CD60c "AGENT_HUB()(address)" --rpc-url sepolia

# FreezeAgent points to pool
cast call 0xC363afB380cd6C972Fd8219d9f51F3f6b05CD60c "POOL()(address)" --rpc-url sepolia
```

## Next Steps

1. **Share with Horizon** — Give `EACAggregatorProxy` (`0x3046553a69a4dBD2aB2AccB30Cbf7C8d8db84D79`) to Horizon so they
   list USTB with this oracle
2. **Share with Chainlink** — Give `RawNAVOracle` (`0xba88Da783C44DC01dBC828a2Cf7F9eB4C5E2A620`) to Chainlink so they
   configure CRE to listen to `RoundDataUpdated` events
3. **Horizon grants RISK_ADMIN** — Horizon grants `RISK_ADMIN` to `HorizonFreezeAgent`
   (`0xC363afB380cd6C972Fd8219d9f51F3f6b05CD60c`) on Sepolia ACLManager (`0xa98845b72768bD31287cE93eAE1F97DE90426e35`)
4. **Register FreezeAgent in AgentHub** — Deployer registers the FreezeAgent in AgentHub for USTB market
5. **Start cron job** — Begin writing USTB prices to RawNAVOracle:
   ```bash
   cast send 0xba88Da783C44DC01dBC828a2Cf7F9eB4C5E2A620 "updateLatestRoundData(int256)" $PRICE --rpc-url sepolia --private-key $PRIVATE_KEY
   ```

## Fire Drill (Freeze Test)

Push an out-of-bounds value to trigger the CRE freeze flow end-to-end:

```bash
cast send 0xba88Da783C44DC01dBC828a2Cf7F9eB4C5E2A620 "updateLatestRoundData(int256)" 50000000 --rpc-url sepolia --private-key $PRIVATE_KEY
```

Expected flow: CRE detects bad value -> pushes freeze state=1 to LlamaGuardOracle -> AgentHub.check() returns actionable
-> execute() freezes USTB market on Horizon Pool.

## Transaction Hashes

### Initial Deployment (Block 10288601)

| Transaction                    | Hash                                                                 |
| ------------------------------ | -------------------------------------------------------------------- |
| Deploy LlamaGuardOracle (v1)   | `0xc74882935c000b94d75d043899f84d01efcc95fa179c939469900fcdba01e668` |
| Deploy LlamaGuardOracleProxy   | `0x427dfd7563e3b87a2b8f6569469a3957a317a9f2710156a40d6e2cfd2a5b593e` |
| Grant WRITER_ROLE (proxy)      | `0x7515a15c048176e4d61fe74177e0a833b955ff09a81539a099aa852d280f5f8f` |
| Grant WRITER_ROLE (deployer)   | `0x25960911e6d4780b1e67e9d18489292602f2a6da5a2fd14915a4d58a2c4b8689` |
| Add authorized market          | `0x002ec95056acd8bcf2228e7a55d812b46c5b856d4fdb15bceb9f513d8afec747` |
| Seed oracle                    | `0x31dee821b92aa839ec5bea550495f9a281ee04c36d50a54dcdb54f5252154f55` |
| Deploy EACAggregatorProxy      | `0x4b64194a1277b89becc3f35db57464869d087d65f5869c4260079a85c1d1d1ff` |
| Deploy RawNAVOracle (v1)       | `0x601110679c2754fb932c2f5109a0c55819e5cf5b888f9cde7468a842c740e75f` |
| Deploy HorizonAgentHub (proxy) | `0x10ab73f840f7313cffd60bd75515d1c1e3c0b3bcdc7c6ef9b8f2e21e7914ca97` |
| Deploy HorizonAgentHub (impl)  | `0x869db8558a6316ab403bf7d4fa5b9344b839f9b275863febc4ac31a2c76b8b84` |
| Deploy HorizonFreezeAgent      | `0x333c58498f31aa26c463a7c541387e18dab9b47a60d212eb6f305dedd0ae670e` |

### Oracle Redeployment — 6 Decimals (Block 10293418)

| Transaction                         | Hash                                                                 |
| ----------------------------------- | -------------------------------------------------------------------- |
| Deploy LlamaGuardOracle (v2, 6 dec) | `0x3fd7e10a1093e72ffcc219cdd24f4c0a02227de8b389b9417efd1fd925d1701e` |
| Grant WRITER_ROLE (proxy)           | `0x0d5f0b0a6cdf1922e97566c99dc36b3a4a779aba1e655a7631bf4ec538dfafa0` |
| Grant WRITER_ROLE (deployer)        | `0xea53fbc87890356bc7c993613061f6b86d894b10343effd91157e99f0b5ac12f` |
| Add authorized market               | `0xd966369630f3446f7cd35188059bca354c7e3d3fbd4444ce113de74c1b68e16a` |
| Seed oracle (6 decimals)            | `0x01550b2fb83717a924f1ff35979cfaaac8ddf42ca8b9b7b8ac0af62027aa6d07` |
| Proxy setLlamaGuardOracle           | `0x73657e10131b37b4a53d2e3e6466cd47481aaf236f82a54a8ce3001b48de4fbc` |
| EAC proposeAggregator               | `0x1e1105d4f927f7c542f2cff6ef3b0f3f45fd43734e0919f9b08e1f6699fea14c` |

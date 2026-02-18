# Stage 1: USTB Infrastructure Deployment

**Network:** Ethereum Mainnet (Chain ID: 1) **Deployer:** `0x9118964074e2AA11393ce0797264759dB2F2ef69`

## Deployed Contracts

| Contract                         | Address                                      |
| -------------------------------- | -------------------------------------------- |
| LlamaGuardOracle (USTB)          | `0xc11B9FbFF1739dba70D1418BC8E6828cE66f61A2` |
| LlamaGuardOracleProxy (USTB)     | `0x67e347aeac84bbD4644425d8Ca8665046FD2C4e0` |
| HorizonAgentHub (proxy)          | `0x7acBfb30736B40d9B8EAE03582FEeE16bA4ADA94` |
| HorizonAgentHub (implementation) | `0xc81657782a294D2F56B129B2051A739196Ecc1d8` |
| HorizonAgentHub (ProxyAdmin)     | `0x692940a9689890f227e4d39ec3F8BdCdd36E10e2` |
| HorizonFreezeAgent               | `0x9CF889F6bB0b77E143608CdaD1Fe83C09f12FBDa` |

## Configuration Applied

- `WRITER_ROLE` granted to `LlamaGuardOracleProxy` on `LlamaGuardOracle`
- USTB token (`0x43415eB6ff9DB7E26A15b704e7A3eDCe97d31C4e`) added as authorized market on oracle
- HorizonAgentHub initialized with deployer as owner
- HorizonFreezeAgent linked to AgentHub and Aave Horizon Pool (`0xAe05Cd22df81871bc7cC2a04BeCfb516bFe332C8`)

## Current Ownership

| Contract                   | Role                      | Holder                     |
| -------------------------- | ------------------------- | -------------------------- |
| LlamaGuardOracle           | `DEFAULT_ADMIN_ROLE`      | Deployer (`0x9118...ef69`) |
| LlamaGuardOracleProxy      | Owner                     | Deployer (`0x9118...ef69`) |
| HorizonAgentHub            | Owner                     | Deployer (`0x9118...ef69`) |
| HorizonAgentHub ProxyAdmin | Owner (upgrade authority) | Deployer (`0x9118...ef69`) |

## What's NOT Activated

- CRE workflow not configured on oracle proxy (deployed with placeholder zero params)
- No agents registered in AgentHub
- Ownership not yet transferred to final parties

## Next Steps

1. **Stage 1a** — Update `CreConfig.sol` with Chainlink CRE details, then run `1a_ConfigureCreWorkflow.s.sol` to
   configure the USTB proxy
2. **Stage 2** — Run `2_ActivateUstbPilot.s.sol` to register FreezeAgent in AgentHub for USTB
3. Chainlink switches their `EACAggregatorProxy` to point to our USTB oracle
4. Aave Horizon grants `RISK_ADMIN` role to `HorizonFreezeAgent` (`0x9CF889F6bB0b77E143608CdaD1Fe83C09f12FBDa`) on
   ACLManager (`0xEFD5df7b87d2dCe6DD454b4240b3e0A4db562321`)

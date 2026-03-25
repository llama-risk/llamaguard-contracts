# LlamaGuard Operational Playbook

This playbook provides step-by-step instructions for making the LlamaGuard NAV oracle system with Aave Horizon
integration operational. The rollout follows a staged approach: infrastructure is deployed first, followed by a
monitoring period, then USYC is activated as a pilot asset to validate the full system. After successful USYC
validation, the remaining assets (USTB, USCC, JTRSY, JAAA, ACRED) are activated as part of a full rollout.

---

## Timeline Overview

**Last Updated:** March 25, 2026

**Current Status:** Phase 3 Complete, Phase 4 Pending

### Gantt Chart

```
2026        Feb                 Mar                 Apr
Week        1    2    3    4    1    2    3    4    1    2
            ├────┼────┼────┼────┼────┼────┼────┼────┼────┼────┤
Phase 1     ████ ✓ Complete
Sepolia

Phase 2     ██████████████████ ✓ Complete
Deployment  (Feb 4 - Mar 1)

Phase 3               ████████████ ✓ Complete
Monitoring            (LlamaRisk & Horizon)
  ├─ 3.3              ████████████ ✓ Complete
     Sepolia          (LlamaRisk & Horizon)
     Integration

Phase 4                              ████ (LlamaRisk & Horizon)
USYC Pilot

Phase 5                                 ████████ (LlamaRisk & Horizon)
USYC Valid.                            ├3-7 days┤

Phase 6                                        ████████ (LlamaRisk & Horizon)
Full Activ.

Phase 7                                        ████ (LlamaRisk & Horizon)
Ownership
```

### Milestone Summary

| Phase | Description                                 | Target Start   | Target End     | Status         |
| ----- | ------------------------------------------- | -------------- | -------------- | -------------- |
| 1     | Sepolia Testing                             | Jan 2026       | Feb 4, 2026    | ✅ Complete    |
| 2     | Mainnet Infrastructure Deployment           | Feb 4, 2026    | Mar 1, 2026    | ✅ Complete    |
| 3     | Pre-Configuration & Monitoring              | Mar 1, 2026    | Mar 21, 2026   | ✅ Complete    |
| 3.3   | Sepolia Integration with Horizon (parallel) | Feb 9, 2026    | Mar 2026       | ✅ Complete    |
| 4     | USYC Pilot Activation                       | TBD            | TBD            | ⏳ Pending     |
| 5     | USYC Validation Period                      | TBD            | TBD + 3-7 days | ⏳ Pending     |
| 6     | Full Asset Activation                       | TBD            | TBD            | ⏳ Pending     |
| 7     | Ownership Transfers                         | TBD            | TBD            | ⏳ Pending     |

### Key Dependencies & Blockers

| Dependency                         | Owner              | Blocks                     | Status                           |
| ---------------------------------- | ------------------ | -------------------------- | -------------------------------- |
| CRE workflow config                | Chainlink          | Phase 2 proxy deployment   | ✅ Complete (5/6, ACRED pending) |
| Chainlink kickoff meeting          | All                | Timeline refinement        | ✅ Complete                      |
| Horizon+LlamaRisk multisig setup   | LlamaRisk+Horizon  | Phase 4 ReadProxy deploy   | 🔄 In Discussion                |
| ACRED CRE workflow config          | Chainlink          | ACRED activation (Phase 6) | ⏳ Awaiting                      |
| CLL ReadProxy verification         | Chainlink          | Phase 4 completion         | ⏳ Pending                       |
| CRE calcs sign-off                 | Chainlink          | Phase 4 completion         | ⏳ Pending                       |

---

## System Architecture Overview

### Per-Asset Components

Each asset (USCC, USTB, USYC, JTRSY, JAAA, ACRED) requires its own oracle infrastructure:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Per-Asset Components                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  USYC:   LlamaGuardOracle(USYC) ← LlamaGuardOracleProxy(USYC) ← CRE   │
│              ↓                                                          │
│          ReadProxy(USYC) [LLR/Horizon-owned] (EACAggregatorProxy)       │
│                                                                         │
│  USTB:   LlamaGuardOracle(USTB) ← LlamaGuardOracleProxy(USTB) ← CRE   │
│              ↓                                                          │
│          ReadProxy(USTB) [LLR/Horizon-owned] (EACAggregatorProxy)       │
│                                                                         │
│  USCC:   LlamaGuardOracle(USCC) ← LlamaGuardOracleProxy(USCC) ← CRE   │
│              ↓                                                          │
│          ReadProxy(USCC) [LLR/Horizon-owned] (EACAggregatorProxy)       │
│                                                                         │
│  (... same pattern for JTRSY, JAAA, ACRED)                              │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Shared Components

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Shared Components                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  HorizonAgentHub (1 instance, owned by Horizon)                         │
│    ├── agentId=1: USYC  → riskOracle: LlamaGuardOracle(USYC)           │
│    ├── agentId=2: USTB  → riskOracle: LlamaGuardOracle(USTB)           │
│    ├── agentId=3: USCC  → riskOracle: LlamaGuardOracle(USCC)           │
│    ├── agentId=4: JTRSY → riskOracle: LlamaGuardOracle(JTRSY)          │
│    ├── agentId=5: JAAA  → riskOracle: LlamaGuardOracle(JAAA)           │
│    └── agentId=6: ACRED → riskOracle: LlamaGuardOracle(ACRED)          │
│         (all point to same agentAddress: HorizonFreezeAgent)            │
│                                                                         │
│  HorizonFreezeAgent (1 instance)                                        │
│    └── Has RISK_ADMIN role on ACLManager                                │
│                                                                         │
│  ParameterRegistry (existing - no new deployment)                       │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Agent Hub Registration Pattern

Each asset requires a **separate agent registration** because the AgentHub requires one `riskOracle` per agent:

```solidity
// Agent registration for USYC (pilot)
AgentRegistrationInput({
    agentAddress: freezeAgentAddress,        // Same FreezeAgent for all
    riskOracle: llamaGuardOracleUSYC,        // USYC-specific oracle
    admin: llamaRiskMultisig,                // LlamaRisk as agent admin
    agentContext: abi.encode(poolConfiguratorAddress),
    isAgentEnabled: true,
    isAgentPermissioned: true,
    isMarketsFromAgentEnabled: false,
    expirationPeriod: 86400,
    minimumDelay: 0,
    updateType: "boundedNAV",
    allowedMarkets: [USYC_TOKEN_ADDRESS],    // Single market per registration
    restrictedMarkets: [],
    permissionedSenders: [llamaRiskMultisig]
})

// Repeat for USTB, USCC, JTRSY, JAAA, ACRED with respective oracle and token addresses
```

### ReadProxy Deployment Per Asset

For each asset, LlamaRisk deploys a ReadProxy (standard Chainlink `EACAggregatorProxy` contract) pointing to the
corresponding `LlamaGuardOracle` as the aggregator:

```solidity
// Deploy ReadProxy for an asset
EACAggregatorProxy readProxy = new EACAggregatorProxy(llamaGuardOracleAddress);

// Transfer ownership (options under discussion):
// Option A: Horizon-owned
readProxy.transferOwnership(horizonMultisig);
// Option B: Joint Horizon+LLR multisig
readProxy.transferOwnership(jointMultisig);
```

Horizon then updates the pool's price feed address for the given asset to point to the new ReadProxy.

---

## Responsibility Matrix (New Architecture)

| Component                        | Old Architecture             | New Architecture                          |
| -------------------------------- | ---------------------------- | ----------------------------------------- |
| ReadProxy (EACAggregatorProxy)   | Chainlink-owned              | LlamaRisk-deployed, LLR/Horizon-owned     |
| Aggregator (LlamaGuardOracle)    | LlamaRisk                    | LlamaRisk (unchanged)                     |
| Price bounds calculation         | CLL External Adapter via DON | LLR CRE workflow (CLL sign-off required)  |
| CRE workflow execution           | Chainlink DON                | Chainlink DON (unchanged)                 |
| Horizon price feed swap          | N/A (same proxy)             | Horizon must update asset oracle address   |

---

## Pre-Deployment Checklist

### Addresses Required

- [x] **LlamaRisk Multisig Address** - `0xE6ec1f0Ae6Cd023bd0a9B4d0253BDC755103253c`
- [ ] **Horizon Multisig Address** - Owner of HorizonAgentHub (TBD)
- [ ] **Joint Horizon+LLR Multisig** - For ReadProxy ownership (TBD - under discussion)
- [x] **Aave Horizon Pool Address** - `0xAe05Cd22df81871bc7cC2a04BeCfb516bFe332C8`
- [x] **Aave Horizon PoolConfigurator Address** - `0x83Cb1B4af26EEf6463aC20AFbAC9c0e2E017202F`
- [x] **Aave Horizon ACLManager Address** - `0xEFD5df7b87d2dCe6DD454b4240b3e0A4db562321`

### Agent Admin Role (LlamaRisk)

LlamaRisk serves as **agent admin** for all registered agents in HorizonAgentHub. This allows LlamaRisk to:

- Enable/disable agents (`setAgentEnabled`)
- Add/remove allowed markets (`addAllowedMarket`, `removeAllowedMarket`)
- Adjust timing parameters (`setMinimumDelay`, `setExpirationPeriod`)
- Configure permissioned senders if needed

**Note:** Agent admin cannot change the agent contract address or reassign the admin role - only the hub owner (Horizon)
can do that.

### Chainlink CRE Configuration

- [x] **expectedForwarder** (address) - `0x0b93082D9b3C7C97fAcd250082899BAcf3af3885`
- [x] **expectedAuthor** (address) - `0x4EDEaFc9b862F08464423EFe9423153B22B28f17` (CRE multisig)
- [x] **workflowIds** - Configured per asset (see CRE Workflow Details below)

### CRE Workflow Details

| Asset | Workflow ID | Status |
| ----- | ----------- | ------ |
| USTB  | `0x00a9cf308e875f62fb6df1f6e1a55dd7db46384876e4059c35abd54125a9c1af` | ✅ Configured |
| USCC  | `0x00886db7652f86b1e90aa63388139bbc9a82069ad80360fce3a2f7d38fe884eb` | ✅ Configured |
| USYC  | `0x00eabb3f208f6e34aa9a2e643cd1ca7a38c5de290a274da7d6ff37c255faec22` | ✅ Configured |
| JTRSY | `0x0058a4e15806379bed41052228a76d6d6ccc45ebcfc167058a73c6065bda6b72` | ✅ Configured |
| JAAA  | `0x00264afe850ac2514dd13809e5e6ccdc9d5070bccc2ebf457baae1c2720dc2be` | ✅ Configured |
| ACRED | TBD | ⏳ Awaiting Chainlink |

### Asset Configuration

#### Pilot Asset (USYC)

| Asset | Token Address | LlamaGuardOracle | LlamaGuardOracleProxy | ReadProxy |
| ----- | ------------- | ---------------- | --------------------- | --------- |
| USYC  | `0x136471a34f6ef19fE571EFFC1CA711fdb8E49f2b` | `0x228Cb3e49EAeb10dD1B56Eeae0A8cBffD0bdF2A4` | `0x7cf933fc475da2E3b45FA207d7df2EF9855c0B60` | TBD |

#### First Wave (USTB, USCC)

| Asset | Token Address | LlamaGuardOracle | LlamaGuardOracleProxy | ReadProxy |
| ----- | ------------- | ---------------- | --------------------- | --------- |
| USTB  | `0x43415eB6ff9DB7E26A15b704e7A3eDCe97d31C4e` | `0xc11B9FbFF1739dba70D1418BC8E6828cE66f61A2` | `0x67e347aeac84bbD4644425d8Ca8665046FD2C4e0` | TBD |
| USCC  | `0x14d60E7FDC0D71d8611742720E4C50E7a974020c` | `0x8f1dff6D95f4D6A9E10416B834D5918bE1Eb5802` | `0x3606A9Ab8D47EE31A6cC1134fA6995B7d16DB529` | TBD |

#### Second Wave (JTRSY, JAAA, ACRED)

| Asset | Token Address | LlamaGuardOracle | LlamaGuardOracleProxy | ReadProxy |
| ----- | ------------- | ---------------- | --------------------- | --------- |
| JTRSY | `0x8c213ee79581Ff4984583C6a801e5263418C4b86` | `0x74c0e98b5853e418219D6bF87fD26A73182F8876` | `0x069f65edEC8FbC6bd7c0C03104d9beC350F0A1C1` | TBD |
| JAAA  | `0x5a0F93D040De44e78F251b03c43be9CF317Dcf64` | `0x8fA713d4E79238E5f6eB7479bEF0B7CFA51a9Ada` | `0xb3fF4a48DEf4d1D2249180F02Ce505668aFd8D46` | TBD |
| ACRED | `0x17418038ecF73BA4026c4f428547BF099706F27B` | `0xE952F28c9DB1424e120d8c78aA174B0dC98200B9` | `0xE5d4D8500D73fb30E0941C8A3BA1e47F06A9bF5F` | TBD |

### Ownership & Access Control Plan

**Current State:** All contracts owned by deployer EOA (`0x9118964074e2AA11393ce0797264759dB2F2ef69`)

**Target State (options to be decided jointly with Horizon):**

| Contract | Current Owner | Option A | Option B |
| -------- | ------------- | -------- | -------- |
| HorizonAgentHub | Deployer | Horizon multisig | Horizon multisig |
| LlamaGuardOracle (DEFAULT_ADMIN_ROLE) | Deployer | LlamaRisk multisig | Joint Horizon+LLR multisig |
| LlamaGuardOracleProxy (Owner) | Deployer | LlamaRisk multisig | Joint Horizon+LLR multisig |
| ReadProxy (Owner) | LlamaRisk (at deploy) | Horizon multisig | Joint Horizon+LLR multisig |

**Centralized failure risks to consider:**

- OracleProxy owner can call `setLlamaGuardOracle()` to change the underlying oracle
- Oracle DEFAULT_ADMIN can grant/revoke `WRITER_ROLE` (controls who can push updates)
- ReadProxy owner can call `proposeAggregator()` to change the aggregator

**Decision required:** Exact ownership split to be agreed between LlamaRisk and Horizon. Transfer flow documented in
Phase 7.

---

## Phase 1: Sepolia Integration Testing ✅

**Status: COMPLETE (February 4, 2026)** **Owner: LlamaRisk (internal)**

**Note:** Fork tests for this architecture have also been executed on Tenderly, validating the full integration flow.

### 1.1 Deploy to Sepolia

| Field            | Value                                |
| ---------------- | ------------------------------------ |
| **Script**       | `script/sepolia/DeploySepolia.s.sol` |
| **Deployer**     | LlamaRisk (test wallet)              |
| **Dependencies** | Sepolia RPC, test ETH                |

**Command:**

```bash
forge script script/sepolia/DeploySepolia.s.sol \
  --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
```

This script deploys:

- [x] LlamaGuardOracle instances (USCC, USTB)
- [x] LlamaGuardOracleProxy instances
- [x] EACAggregatorProxy instances (for testing)
- [x] Seeds oracles with initial data from source oracles

**Post-Deploy Verification:**

- [x] All contracts deployed and verified on Etherscan
- [x] Oracle proxies have WRITER_ROLE granted
- [x] Registry assets configured with correct oracle addresses

---

### 1.2 Test Oracle Update Flow

| Field        | Value                                   |
| ------------ | --------------------------------------- |
| **Caller**   | LlamaRisk (or Chainlink CRE on testnet) |
| **Contract** | `LlamaGuardOracleProxy`                 |

**Test Normal Update (state=0):**

```solidity
// Construct metadata: workflowId (32) + workflowName (10) + expectedAuthor (20)
bytes memory metadata = abi.encodePacked(workflowId, workflowName, expectedAuthor);

// Construct report with normal state
ILlamaGuardOracle.UpdateInput memory input = ILlamaGuardOracle.UpdateInput({
    referenceId: "test-update-001",
    newValue: abi.encode(int256(1e8)),  // $1.00 price
    updateType: "boundedNAV",
    additionalData: abi.encode(
        int256(99e6),   // lowerBound
        int256(101e6),  // upperBound
        uint256(0)      // state: 0 = normal
    )
});

bytes memory report = abi.encode(input);
proxy.onReport(metadata, report);
```

**Verification:**

- [x] `oracle.latestRoundData()` returns new roundId
- [x] `oracle.latestAnswer()` returns expected price
- [x] Event `ParameterUpdated` emitted

---

### 1.3 Test Freeze Flow (End-to-End)

| Field               | Value                                                    |
| ------------------- | -------------------------------------------------------- |
| **Requires**        | HorizonAgentHub + HorizonFreezeAgent deployed on Sepolia |
| **Aave Dependency** | Sepolia Horizon Pool (if available) or mock contracts    |

**Step 1: Push Freeze Update to Oracle**

```solidity
ILlamaGuardOracle.UpdateInput memory freezeInput = ILlamaGuardOracle.UpdateInput({
    referenceId: "test-freeze-001",
    newValue: abi.encode(int256(95e6)),  // Price below lower bound
    updateType: "boundedNAV",
    additionalData: abi.encode(
        int256(99e6),   // lowerBound
        int256(101e6),  // upperBound
        uint256(1)      // state: 1 = FREEZE
    )
});

proxy.onReport(metadata, abi.encode(freezeInput));
```

**Step 2: Verify Agent Can Execute**

```solidity
uint256[] memory agentIds = new uint256[](1);
agentIds[0] = agentId;

(bool shouldExecute, IAgentHub.ActionData[] memory actions) = hub.check(agentIds);
```

- [x] `shouldExecute` returns `true`
- [x] `actions` array contains correct agentId and market

**Step 3: Execute Freeze via Hub**

```solidity
hub.execute(actions);
```

- [x] Transaction succeeds
- [x] Event `ReserveFreezeUpdated` emitted from FreezeAgent
- [x] Event `UpdateInjected` emitted from AgentHub

**Step 4: Verify Market State**

```solidity
DataTypes.ReserveConfigurationMap memory config = pool.getConfiguration(marketAddress);
bool isFrozen = config.getFrozen();
```

- [x] `isFrozen` returns `true`

---

### 1.4 Test Validation Rejection

Verify that invalid updates are rejected:

**Test 1: Unfreeze Rejected (state=0 after freeze)**

```solidity
// Attempt to push unfreeze update
ILlamaGuardOracle.UpdateInput memory unfreezeInput = ILlamaGuardOracle.UpdateInput({
    referenceId: "test-unfreeze-001",
    newValue: abi.encode(int256(100e6)),
    updateType: "boundedNAV",
    additionalData: abi.encode(int256(99e6), int256(101e6), uint256(0))  // state=0
});

proxy.onReport(metadata, abi.encode(unfreezeInput));

// Check agent validation
(bool shouldExecute,) = hub.check(agentIds);
```

- [x] `shouldExecute` returns `false` (agent rejects unfreeze)

**Test 2: Already Frozen Market Rejected**

- [x] Push freeze update for already-frozen market
- [x] `hub.check()` returns `false` (prevents double-freeze)

**Test 3: Unauthorized Update Type Rejected**

```solidity
// Attempt update with invalid type
ILlamaGuardOracle.UpdateInput memory badInput = ILlamaGuardOracle.UpdateInput({
    referenceId: "test-bad",
    newValue: abi.encode(int256(100e6)),
    updateType: "invalidType",  // Not registered
    additionalData: ""
});
```

- [x] Transaction reverts with `UnauthorizedUpdateType`

---

### 1.5 Sepolia Testing Complete

| Test                 | Status   | Notes |
| -------------------- | -------- | ----- |
| Oracle deployment    | [x] Pass |       |
| Proxy WRITER_ROLE    | [x] Pass |       |
| Normal price update  | [x] Pass |       |
| Freeze update        | [x] Pass |       |
| Validation rejection | [x] Pass |       |

**Internal sign-off (LlamaRisk):** Zeki & Exa, Date: 26 Jan 2026

---

## Phase 2: Mainnet Infrastructure Deployment ✅

**Status: COMPLETE (February 4 - March 1, 2026)**

Deploy all infrastructure. **No activation yet.**

### 2.1 Deploy LlamaGuardOracle (per asset)

| Field        | Value                                       |
| ------------ | ------------------------------------------- |
| **Contract** | `LlamaGuardOracle`                          |
| **Deployer** | LlamaRisk                                   |
| **Assets**   | USTB (Stage 1), USCC, USYC, JTRSY, JAAA, ACRED (Stage 3) |

**Post-Deploy Checklist:**

- [x] LlamaGuardOracle(USTB) deployed: `0xc11B9FbFF1739dba70D1418BC8E6828cE66f61A2`
- [x] LlamaGuardOracle(USCC) deployed: `0x8f1dff6D95f4D6A9E10416B834D5918bE1Eb5802`
- [x] LlamaGuardOracle(USYC) deployed: `0x228Cb3e49EAeb10dD1B56Eeae0A8cBffD0bdF2A4`
- [x] LlamaGuardOracle(JTRSY) deployed: `0x74c0e98b5853e418219D6bF87fD26A73182F8876`
- [x] LlamaGuardOracle(JAAA) deployed: `0x8fA713d4E79238E5f6eB7479bEF0B7CFA51a9Ada`
- [x] LlamaGuardOracle(ACRED) deployed: `0xE952F28c9DB1424e120d8c78aA174B0dC98200B9`

---

### 2.2 Deploy LlamaGuardOracleProxy (per asset)

| Field            | Value                                  |
| ---------------- | -------------------------------------- |
| **Contract**     | `LlamaGuardOracleProxy`                |
| **Deployer**     | LlamaRisk                              |
| **Dependencies** | LlamaGuardOracle, Chainlink CRE config |

**Post-Deploy Checklist:**

- [x] LlamaGuardOracleProxy(USTB) deployed: `0x67e347aeac84bbD4644425d8Ca8665046FD2C4e0`
- [x] LlamaGuardOracleProxy(USCC) deployed: `0x3606A9Ab8D47EE31A6cC1134fA6995B7d16DB529`
- [x] LlamaGuardOracleProxy(USYC) deployed: `0x7cf933fc475da2E3b45FA207d7df2EF9855c0B60`
- [x] LlamaGuardOracleProxy(JTRSY) deployed: `0x069f65edEC8FbC6bd7c0C03104d9beC350F0A1C1`
- [x] LlamaGuardOracleProxy(JAAA) deployed: `0xb3fF4a48DEf4d1D2249180F02Ce505668aFd8D46`
- [x] LlamaGuardOracleProxy(ACRED) deployed: `0xE5d4D8500D73fb30E0941C8A3BA1e47F06A9bF5F`

---

### 2.3 Grant WRITER_ROLE to Proxies

| Field        | Value                                 |
| ------------ | ------------------------------------- |
| **Contract** | `LlamaGuardOracle` (each)             |
| **Caller**   | LlamaRisk (DEFAULT_ADMIN_ROLE holder) |

```solidity
// For each oracle/proxy pair
LlamaGuardOracle(ustb).grantRole(WRITER_ROLE, proxyUSTB);
LlamaGuardOracle(uscc).grantRole(WRITER_ROLE, proxyUSCC);
LlamaGuardOracle(usyc).grantRole(WRITER_ROLE, proxyUSYC);
LlamaGuardOracle(jtrsy).grantRole(WRITER_ROLE, proxyJTRSY);
LlamaGuardOracle(jaaa).grantRole(WRITER_ROLE, proxyJAAA);
LlamaGuardOracle(acred).grantRole(WRITER_ROLE, proxyACRED);
```

**Verification:**

- [x] All 6 assets: `oracle.hasRole(WRITER_ROLE, proxy)` = true

---

### 2.4 Add Authorized Markets to Oracles

| Field        | Value                                 |
| ------------ | ------------------------------------- |
| **Contract** | `LlamaGuardOracle` (each)             |
| **Caller**   | LlamaRisk (DEFAULT_ADMIN_ROLE holder) |

```solidity
// Each oracle authorizes its own token as a market
LlamaGuardOracle(ustb).addAuthorizedMarket(USTB_TOKEN);
LlamaGuardOracle(uscc).addAuthorizedMarket(USCC_TOKEN);
LlamaGuardOracle(usyc).addAuthorizedMarket(USYC_TOKEN);
LlamaGuardOracle(jtrsy).addAuthorizedMarket(JTRSY_TOKEN);
LlamaGuardOracle(jaaa).addAuthorizedMarket(JAAA_TOKEN);
LlamaGuardOracle(acred).addAuthorizedMarket(ACRED_TOKEN);
```

---

### 2.5 Deploy HorizonAgentHub

| Field        | Value             |
| ------------ | ----------------- |
| **Contract** | `HorizonAgentHub` |
| **Deployer** | LlamaRisk         |

**Post-Deploy:**

- [x] HorizonAgentHub (proxy) deployed: `0x7acBfb30736B40d9B8EAE03582FEeE16bA4ADA94`
- [x] HorizonAgentHub (implementation): `0xc81657782a294D2F56B129B2051A739196Ecc1d8`
- [x] HorizonAgentHub (ProxyAdmin): `0x692940a9689890f227e4d39ec3F8BdCdd36E10e2`

---

### 2.6 Deploy HorizonFreezeAgent

| Field            | Value                      |
| ---------------- | -------------------------- |
| **Contract**     | `HorizonFreezeAgent`       |
| **Deployer**     | Horizon                    |
| **Dependencies** | HorizonAgentHub, Aave Pool |

```solidity
constructor(
    address agentHub,  // HorizonAgentHub address
    address pool       // Aave Pool address
)
```

**Post-Deploy:**

- [x] HorizonFreezeAgent deployed: `0x9CF889F6bB0b77E143608CdaD1Fe83C09f12FBDa`
- [x] `AGENT_HUB()` = HorizonAgentHub address `0x7acBfb30736B40d9B8EAE03582FEeE16bA4ADA94`
- [x] `POOL()` = Aave Pool address `0xAe05Cd22df81871bc7cC2a04BeCfb516bFe332C8`

---

### 2.7 Activate CRE Workflow

| Field     | Value     |
| --------- | --------- |
| **Owner** | Chainlink |

- [x] CRE workflow activated for USTB
- [x] Oracle updates flowing to LlamaGuardOracles
- [ ] CRE workflow configured for remaining assets (5/6 configured, ACRED pending)

---

### Phase 2 Complete Checklist

| Component                        | Address                                      | Status     |
| -------------------------------- | -------------------------------------------- | ---------- |
| LlamaGuardOracle(USTB)           | `0xc11B9FbFF1739dba70D1418BC8E6828cE66f61A2` | ✅ Deployed |
| LlamaGuardOracle(USCC)           | `0x8f1dff6D95f4D6A9E10416B834D5918bE1Eb5802` | ✅ Deployed |
| LlamaGuardOracle(USYC)           | `0x228Cb3e49EAeb10dD1B56Eeae0A8cBffD0bdF2A4` | ✅ Deployed |
| LlamaGuardOracle(JTRSY)          | `0x74c0e98b5853e418219D6bF87fD26A73182F8876` | ✅ Deployed |
| LlamaGuardOracle(JAAA)           | `0x8fA713d4E79238E5f6eB7479bEF0B7CFA51a9Ada` | ✅ Deployed |
| LlamaGuardOracle(ACRED)          | `0xE952F28c9DB1424e120d8c78aA174B0dC98200B9` | ✅ Deployed |
| LlamaGuardOracleProxy(USTB)      | `0x67e347aeac84bbD4644425d8Ca8665046FD2C4e0` | ✅ Deployed |
| LlamaGuardOracleProxy(USCC)      | `0x3606A9Ab8D47EE31A6cC1134fA6995B7d16DB529` | ✅ Deployed |
| LlamaGuardOracleProxy(USYC)      | `0x7cf933fc475da2E3b45FA207d7df2EF9855c0B60` | ✅ Deployed |
| LlamaGuardOracleProxy(JTRSY)     | `0x069f65edEC8FbC6bd7c0C03104d9beC350F0A1C1` | ✅ Deployed |
| LlamaGuardOracleProxy(JAAA)      | `0xb3fF4a48DEf4d1D2249180F02Ce505668aFd8D46` | ✅ Deployed |
| LlamaGuardOracleProxy(ACRED)     | `0xE5d4D8500D73fb30E0941C8A3BA1e47F06A9bF5F` | ✅ Deployed |
| HorizonAgentHub (proxy)          | `0x7acBfb30736B40d9B8EAE03582FEeE16bA4ADA94` | ✅ Deployed |
| HorizonAgentHub (implementation) | `0xc81657782a294D2F56B129B2051A739196Ecc1d8` | ✅ Deployed |
| HorizonAgentHub (ProxyAdmin)     | `0x692940a9689890f227e4d39ec3F8BdCdd36E10e2` | ✅ Deployed |
| HorizonFreezeAgent               | `0x9CF889F6bB0b77E143608CdaD1Fe83C09f12FBDa` | ✅ Deployed |
| WRITER_ROLE granted (all)        | -                                            | ✅ Granted  |
| Authorized markets set (all)     | -                                            | ✅ Set      |
| CRE workflow active              | -                                            | ✅ Active (USTB) |

---

## Phase 3: Pre-Configuration & Monitoring ✅

**Status: COMPLETE**

**Duration: 1 week minimum**

### 3.1 Grant RISK_ADMIN to FreezeAgent

| Field        | Value                |
| ------------ | -------------------- |
| **Contract** | `ACLManager` (Aave)  |
| **Caller**   | Horizon (Pool Admin) |

```solidity
ACLManager.addRiskAdmin(freezeAgentAddress)
```

**Note:** Agent is not yet registered in hub, so RISK_ADMIN grant is safe - agent cannot execute anything yet.

**Verification:**

- [ ] `aclManager.isRiskAdmin(freezeAgentAddress)` = true

**Note:** RISK_ADMIN can be granted during Phase 3 or Phase 4 - it is not strictly required for Phase 3 monitoring.

---

### 3.2 Oracle Monitoring

LlamaRisk monitors oracle updates via the LlamaGuard Dashboard.

**Dashboard:** https://llamaguard-nav.staging.llamarisk.com/

**Daily Checks:**

| Day | Date | Updates Received | State=1 Count | Issues |
| --- | ---- | ---------------- | ------------- | ------ |
| 1   |      | ✅               | 0             | None   |
| 2   |      | ✅               | 0             | None   |
| 3   |      | ✅               | 0             | None   |
| 4   |      | ✅               | 0             | None   |
| 5   |      | ✅               | 0             | None   |
| 6   |      | ✅               | 0             | None   |
| 7   |      | ✅               | 0             | None   |

---

### 3.3 Sepolia Integration Testing with Horizon ✅

**Status: COMPLETE**

**Owner: LlamaRisk + Horizon**

Full end-to-end integration testing on Sepolia with HorizonFreezeAgent completed.

**Deployed Sepolia Contracts:**

| Contract                        | Address                                      |
| ------------------------------- | -------------------------------------------- |
| LlamaGuardOracle (USTB)         | `0x54F2879D0a903B864782A40D67776aE53871B166` |
| LlamaGuardOracleProxy (v2)      | `0x860EeAEA09ff6A26F3F4C8681e79B200D9412382` |
| EACAggregatorProxy (V2V3)       | `0xa3180C43c5B52887008538942b9C6E1993535def` |
| HorizonAgentHub (proxy)         | `0x1DcDe45392E4fE8c1a9D60AaE5dd01057c234C68` |
| HorizonFreezeAgent (v2)         | `0xe16504396EdDb8822197540d3AF5E560b27E4e1e` |

See: `docs/testing/sepolia_integration_freeze_test.md` and `docs/testing/sepolia_tenderly_freeze_test.md`

**Test Scenarios:**

- [x] Register agent in Sepolia hub
- [x] Push out of bounds update to raw NAV
- [x] Verify CRE picks up and updates freeze state
- [x] Verify `hub.check()` returns actionable data
- [x] Execute freeze via `hub.execute()`
- [x] Confirm market is frozen on Sepolia pool
- [x] Test validation rejection (unfreeze, double-freeze)

**Completion Criteria:**

- [x] Full freeze flow validated on Sepolia
- [x] No issues with agent registration or execution

---

### 3.4 Go/No-Go Decision

**Prerequisites for proceeding to Phase 4:**

- [x] No false positive freeze signals during monitoring period
- [x] Price data consistently matches expected NAV values
- [x] Bound calculations verified as accurate
- [x] No unexpected errors or reverts
- [x] Sepolia integration testing with Horizon complete (Section 3.3)

**Sign-off Required:**

- [ ] LlamaRisk: _________________ Date: _______
- [ ] Horizon: _________________ Date: _______
- [ ] Chainlink (optional): _________________ Date: _______

**Decision:**

- [ ] **GO** - Proceed to Phase 4: USYC Pilot
- [ ] **NO-GO** - Extend monitoring / investigate issues

---

## Phase 4: USYC Pilot Activation

**Activate USYC only to validate the full system before expanding.**

### 4.1 Deploy ReadProxy for USYC

| Field        | Value                                               |
| ------------ | --------------------------------------------------- |
| **Contract** | `EACAggregatorProxy` (deployed as ReadProxy)         |
| **Deployer** | LlamaRisk                                            |
| **Owner**    | TBD (Horizon or joint Horizon+LLR multisig)          |

```solidity
// Deploy ReadProxy pointing to USYC LlamaGuardOracle
EACAggregatorProxy readProxy = new EACAggregatorProxy(
    0x228Cb3e49EAeb10dD1B56Eeae0A8cBffD0bdF2A4  // LlamaGuardOracle(USYC)
);

// Transfer ownership
readProxy.transferOwnership(multisigAddress);
```

**Verification:**

- [ ] ReadProxy deployed and verified on Etherscan
- [ ] `ReadProxy.aggregator()` = LlamaGuardOracle(USYC)
- [ ] `ReadProxy.latestAnswer()` returns expected USYC price
- [ ] `ReadProxy.decimals()` = 8
- [ ] `ReadProxy.owner()` = target multisig

---

### 4.2 Chainlink Verification of ReadProxy

| Field     | Value     |
| --------- | --------- |
| **Owner** | Chainlink |

After deployment, Chainlink team verifies the open source proxy is working as expected.

- [ ] CLL confirms ReadProxy correctly reads from LlamaGuardOracle
- [ ] CLL confirms data format and interface compatibility
- [ ] CLL sign-off on ReadProxy deployment

---

### 4.3 CRE Workflow Calculation Sign-off

| Field     | Value     |
| --------- | --------- |
| **Owner** | Chainlink |

With this architecture, Horizon no longer relies on CLL External Adapter via DON for price bounds calculation.
Instead, LLR's CRE workflow handles bounded prices.

- [ ] CLL team confirms LLR CRE bounded price calcs match CLL's calcs
- [ ] CLL sign-off on CRE workflow calculation accuracy

---

### 4.4 Register USYC Agent in Hub

| Field        | Value             |
| ------------ | ----------------- |
| **Contract** | `HorizonAgentHub` |
| **Caller**   | Horizon (owner)   |

```solidity
HorizonAgentHub.registerAgent(
    IAgentConfigurator.AgentRegistrationInput({
        agentAddress: freezeAgentAddress,
        riskOracle: 0x228Cb3e49EAeb10dD1B56Eeae0A8cBffD0bdF2A4,  // LlamaGuardOracle(USYC)
        admin: llamaRiskMultisig,
        agentContext: abi.encode(poolConfiguratorAddress),
        isAgentEnabled: true,
        isAgentPermissioned: true,
        isMarketsFromAgentEnabled: false,
        expirationPeriod: 86400,
        minimumDelay: 0,
        updateType: "boundedNAV",
        allowedMarkets: [0x136471a34f6ef19fE571EFFC1CA711fdb8E49f2b],  // USYC token
        restrictedMarkets: [],
        permissionedSenders: [llamaRiskMultisig]
    })
)
```

**Returns:** `agentId` for USYC (record this)

**Verification:**

- [ ] `hub.getAgentAddress(agentId)` = FreezeAgent
- [ ] `hub.isAgentEnabled(agentId)` = true
- [ ] `hub.getRiskOracle(agentId)` = LlamaGuardOracle(USYC)

**Note:** Agent is permissioned for pilot purposes to eliminate false positives. After pilot, all agents will be
permissionless.

---

### 4.5 Horizon Swaps Price Feed Address

| Field        | Value             |
| ------------ | ----------------- |
| **Contract** | Horizon Pool      |
| **Caller**   | Horizon           |

Horizon updates the USYC asset's oracle source in the pool to point to the new ReadProxy address.

- [ ] Horizon pool configured with new USYC ReadProxy as price feed
- [ ] Horizon frontend updated to reflect new oracle source

---

### 4.6 Grant RISK_ADMIN (if not done in Phase 3)

- [ ] `aclManager.isRiskAdmin(freezeAgentAddress)` = true

---

### Phase 4 Complete - USYC Now Operational

| Component                               | Status |
| --------------------------------------- | ------ |
| ReadProxy deployed for USYC             | [ ]    |
| CLL verification of ReadProxy           | [ ]    |
| CRE calcs sign-off from CLL             | [ ]    |
| USYC agent registered in hub            | [ ]    |
| Horizon price feed swapped to ReadProxy  | [ ]    |
| RISK_ADMIN granted to FreezeAgent        | [ ]    |
| USYC freeze capability operational      | [ ]    |

---

## Phase 5: USYC Validation Period

**Duration: TBD (recommend 3-7 days minimum)**

### 5.1 USYC Monitoring

**Daily Checks:**

| Day | Date | Oracle Working | Hub Check() OK | Issues |
| --- | ---- | -------------- | -------------- | ------ |
| 1   |      | [ ]            | [ ]            |        |
| 2   |      | [ ]            | [ ]            |        |
| 3   |      | [ ]            | [ ]            |        |

### 5.2 Success Criteria for USYC Pilot

**Technical Validation:**

- [ ] ReadProxy consistently returns correct price from LlamaGuardOracle
- [ ] `hub.check([usycAgentId])` returns expected results
- [ ] No false positive freeze signals
- [ ] Price feed latency acceptable

**Operational Validation:**

- [ ] Aave frontend displays correct USYC prices
- [ ] No user-reported issues with USYC market
- [ ] Liquidation calculations remain accurate

**Sign-off Required Before Expanding:**

- [ ] LlamaRisk: _________________ Date: _______
- [ ] Horizon: _________________ Date: _______
- [ ] Chainlink (optional): _________________ Date: _______

**Decision:**

- [ ] **GO** - Proceed to Phase 6: Full Asset Activation
- [ ] **NO-GO** - Investigate issues / extend validation

---

## Phase 6: Full Asset Activation

**Activate remaining assets: USTB, USCC, JTRSY, JAAA, ACRED**

### 6.1 Deploy ReadProxies (Remaining Assets)

For each remaining asset, deploy a ReadProxy (EACAggregatorProxy) pointing to the corresponding LlamaGuardOracle.

| Asset | LlamaGuardOracle                             | ReadProxy Address | Deploy Status |
| ----- | -------------------------------------------- | ----------------- | ------------- |
| USTB  | `0xc11B9FbFF1739dba70D1418BC8E6828cE66f61A2` | TBD               | [ ]           |
| USCC  | `0x8f1dff6D95f4D6A9E10416B834D5918bE1Eb5802` | TBD               | [ ]           |
| JTRSY | `0x74c0e98b5853e418219D6bF87fD26A73182F8876` | TBD               | [ ]           |
| JAAA  | `0x8fA713d4E79238E5f6eB7479bEF0B7CFA51a9Ada` | TBD               | [ ]           |
| ACRED | `0xE952F28c9DB1424e120d8c78aA174B0dC98200B9` | TBD               | [ ]           |

---

### 6.2 Register Remaining Agents in Hub

```solidity
// USTB
hub.registerAgent({
    riskOracle: llamaGuardOracleUSTB,
    allowedMarkets: [USTB_TOKEN_ADDRESS],
    // ... same config as USYC pilot
});

// USCC, JTRSY, JAAA, ACRED similarly
```

**Agent ID Registry:**

| Asset | agentId | Oracle Address                               | Status |
| ----- | ------- | -------------------------------------------- | ------ |
| USYC  |         | `0x228Cb3e49EAeb10dD1B56Eeae0A8cBffD0bdF2A4` | [ ]    |
| USTB  |         | `0xc11B9FbFF1739dba70D1418BC8E6828cE66f61A2` | [ ]    |
| USCC  |         | `0x8f1dff6D95f4D6A9E10416B834D5918bE1Eb5802` | [ ]    |
| JTRSY |         | `0x74c0e98b5853e418219D6bF87fD26A73182F8876` | [ ]    |
| JAAA  |         | `0x8fA713d4E79238E5f6eB7479bEF0B7CFA51a9Ada` | [ ]    |
| ACRED |         | `0xE952F28c9DB1424e120d8c78aA174B0dC98200B9` | [ ]    |

### 6.3 Horizon Swaps Price Feeds (Remaining Assets)

Horizon updates each remaining asset's oracle source in the pool to point to the corresponding ReadProxy.

---

### Phase 6 Complete - All Assets Operational

| Component                            | Status |
| ------------------------------------ | ------ |
| All ReadProxies deployed             | [ ]    |
| All agents registered in hub         | [ ]    |
| All price feeds swapped in Horizon   | [ ]    |
| Full freeze capability operational   | [ ]    |

---

## Phase 7: Ownership Transfers

### 7.1 Transfer HorizonAgentHub Ownership

```solidity
// Transfer to Horizon multisig
agentHub.transferOwnership(horizonMultisig);
```

### 7.2 Transfer LlamaGuardOracle Admin

```solidity
// For each oracle - transfer to agreed owner (LLR multisig or joint multisig)
oracle.grantRole(DEFAULT_ADMIN_ROLE, newAdminAddress);
oracle.revokeRole(DEFAULT_ADMIN_ROLE, oldAdminAddress);
```

### 7.3 Transfer LlamaGuardOracleProxy Ownership

```solidity
// Two-step transfer (Ownable2Step) - transfer to agreed owner
proxy.transferOwnership(newOwnerAddress);
// New owner accepts
proxy.acceptOwnership();
```

### 7.4 Verify ReadProxy Ownership

ReadProxy ownership is set at deploy time (Phase 4/6). Verify all ReadProxies are owned by the agreed party.

```solidity
// For each ReadProxy
readProxy.owner() == expectedOwner;
```

### Access Control Transfer Summary

| Contract | Current Owner | Target Owner | Transfer Method | Status |
| -------- | ------------- | ------------ | --------------- | ------ |
| HorizonAgentHub | Deployer | Horizon multisig | `transferOwnership` | [ ] |
| HorizonAgentHub ProxyAdmin | Deployer | Horizon multisig | `transferOwnership` | [ ] |
| LlamaGuardOracle (x6) | Deployer | TBD (LLR or joint) | `grantRole` + `revokeRole` | [ ] |
| LlamaGuardOracleProxy (x6) | Deployer | TBD (LLR or joint) | `transferOwnership` + `acceptOwnership` | [ ] |
| ReadProxy (x6) | LlamaRisk | TBD (Horizon or joint) | Set at deploy time | [ ] |

---

## Cross-Org Coordination Summary

| Step                                                     | Owner              | Depends On          | Blocker For |
| -------------------------------------------------------- | ------------------ | ------------------- | ----------- |
| Provide CRE config                                       | Chainlink          | None                | Phase 1     |
| **Phase 1**: Sepolia testing                             | LlamaRisk          | CRE config          | Phase 2     |
| **Phase 2**: Deploy oracles, proxies, hub, agent         | LlamaRisk + Horizon | Phase 1             | Phase 3     |
| Activate CRE workflow                                    | Chainlink          | Phase 2 oracles     | Phase 3     |
| **Phase 3**: Monitor oracles, Sepolia integration        | LlamaRisk + Horizon | CRE active          | Phase 4     |
| Go/No-Go sign-off                                        | LlamaRisk + Horizon | Monitoring          | Phase 4     |
| Setup joint multisig (if applicable)                     | LlamaRisk + Horizon | Sign-off            | Phase 4     |
| **Phase 4**: Deploy USYC ReadProxy, CLL verify, register agent | LlamaRisk + Horizon | Multisig ready | Phase 5     |
| Horizon swaps USYC price feed                            | Horizon            | ReadProxy deployed  | Phase 5     |
| CLL ReadProxy verification + CRE calcs sign-off          | Chainlink          | ReadProxy deployed  | Phase 4     |
| **Phase 5**: USYC validation                            | All                | USYC active         | Phase 6     |
| USYC validation sign-off                                 | LlamaRisk + Horizon | USYC validation    | Phase 6     |
| **Phase 6**: Deploy remaining ReadProxies, register agents | LlamaRisk + Horizon | USYC sign-off    | Phase 7     |
| Horizon swaps remaining price feeds                      | Horizon            | ReadProxies deployed | Phase 7    |
| **Phase 7**: Ownership transfers                         | All                | Phase 6             | System live |

---

## Open Questions

- [x] What is the delay between `proposeAggregator` and `confirmAggregator`? → N/A (LlamaRisk deploys own ReadProxy)
- [x] Will Chainlink deploy EACAggregatorProxy for Sepolia testing? → N/A (LlamaRisk deployed own on Sepolia)
- [x] CRE workflow configuration parameters → ✅ Configured for 5/6 assets (ACRED pending)
- [ ] Joint multisig structure (Gnosis Safe? Threshold? Signers?)
- [ ] Exact ownership split for Oracle, Proxy, and ReadProxy contracts
- [ ] Access control transfer timeline
- [ ] Coordination process for Horizon price feed swaps

---

## Emergency Procedures

### Disable Single Asset Agent

**Caller:** LlamaRisk (agent admin) or Horizon (hub owner)

```solidity
hub.setAgentEnabled(agentId, false);
```

### Disable All Freeze Capability

```solidity
aclManager.removeRiskAdmin(freezeAgentAddress);
```

### Stop Oracle Updates

```solidity
oracle.revokeRole(WRITER_ROLE, proxyAddress);
```

### Replace Oracle for an Asset

```solidity
// 1. Deploy new oracle
// 2. Update proxy
proxy.setLlamaGuardOracle(newOracleAddress);
// 3. Update ReadProxy aggregator (owner action via multisig)
readProxy.proposeAggregator(newOracleAddress);
// 4. Update agent registration if needed
```

---

## Deployment Summary

### Phase 2: Infrastructure (Complete)

| Contract                         | Address                                      | Deployer  |
| -------------------------------- | -------------------------------------------- | --------- |
| LlamaGuardOracle(USTB)           | `0xc11B9FbFF1739dba70D1418BC8E6828cE66f61A2` | LlamaRisk |
| LlamaGuardOracle(USCC)           | `0x8f1dff6D95f4D6A9E10416B834D5918bE1Eb5802` | LlamaRisk |
| LlamaGuardOracle(USYC)           | `0x228Cb3e49EAeb10dD1B56Eeae0A8cBffD0bdF2A4` | LlamaRisk |
| LlamaGuardOracle(JTRSY)          | `0x74c0e98b5853e418219D6bF87fD26A73182F8876` | LlamaRisk |
| LlamaGuardOracle(JAAA)           | `0x8fA713d4E79238E5f6eB7479bEF0B7CFA51a9Ada` | LlamaRisk |
| LlamaGuardOracle(ACRED)          | `0xE952F28c9DB1424e120d8c78aA174B0dC98200B9` | LlamaRisk |
| LlamaGuardOracleProxy(USTB)      | `0x67e347aeac84bbD4644425d8Ca8665046FD2C4e0` | LlamaRisk |
| LlamaGuardOracleProxy(USCC)      | `0x3606A9Ab8D47EE31A6cC1134fA6995B7d16DB529` | LlamaRisk |
| LlamaGuardOracleProxy(USYC)      | `0x7cf933fc475da2E3b45FA207d7df2EF9855c0B60` | LlamaRisk |
| LlamaGuardOracleProxy(JTRSY)     | `0x069f65edEC8FbC6bd7c0C03104d9beC350F0A1C1` | LlamaRisk |
| LlamaGuardOracleProxy(JAAA)      | `0xb3fF4a48DEf4d1D2249180F02Ce505668aFd8D46` | LlamaRisk |
| LlamaGuardOracleProxy(ACRED)     | `0xE5d4D8500D73fb30E0941C8A3BA1e47F06A9bF5F` | LlamaRisk |
| HorizonAgentHub (proxy)          | `0x7acBfb30736B40d9B8EAE03582FEeE16bA4ADA94` | LlamaRisk |
| HorizonAgentHub (implementation) | `0xc81657782a294D2F56B129B2051A739196Ecc1d8` | LlamaRisk |
| HorizonAgentHub (ProxyAdmin)     | `0x692940a9689890f227e4d39ec3F8BdCdd36E10e2` | LlamaRisk |
| HorizonFreezeAgent               | `0x9CF889F6bB0b77E143608CdaD1Fe83C09f12FBDa` | Horizon   |

### Phase 4-6: Activation Timeline

| Asset | ReadProxy Deploy Date | Agent Registration Date | agentId |
| ----- | --------------------- | ----------------------- | ------- |
| USYC  |                       |                         |         |
| USTB  |                       |                         |         |
| USCC  |                       |                         |         |
| JTRSY |                       |                         |         |
| JAAA  |                       |                         |         |
| ACRED |                       |                         |         |

# Operational Playbook

This playbook provides step-by-step instructions for making the LlamaGuard NAV oracle system with Aave Horizon
integration operational. The rollout follows a staged approach: infrastructure is deployed first, followed by a
monitoring period, then USTB is activated as a pilot asset to validate the full system. After successful USTB
validation, the remaining assets (USCC, USYC, JTRSY, JAAA, ACRED) are activated in a full rollout.

---

## Timeline Overview

**Last Updated:** February 4, 2025

**Current Status:** Phase 1 Complete, Phase 2 In Progress

### Gantt Chart

```
2025        Feb                 Mar                 Apr
Week        1    2    3    4    1    2    3    4    1    2
            ├────┼────┼────┼────┼────┼────┼────┼────┼────┼────┤
Phase 1     ████ ✓ Complete
Sepolia

Phase 2        █████████ (LlamaRisk)
Deployment

Phase 3                 ████████████ (LlamaRisk & Horizon)
Monitoring              ├1 week min┤├sign-off┤
  ├─ 3.3                ███████████ ( LlamaRisk & Horizon)
     Sepolia            ├─parallel──┤
     Integration

Phase 4                             ████ (LlamaRisk & Horizon & Chainlink)
USTB Pilot

Phase 5                                ████████ (LlamaRisk & Horizon & Chainlink)
USTB Valid.                           ├3-7 days┤

Phase 6                                       ████████ (LlamaRisk & Horizon & Chainlink)
Full Activ.

Phase 7                                       ████ (LlamaRisk & Horizon)
Ownership
```

### Milestone Summary

| Phase | Description                                 | Target Start | Target End     | Status         |
| ----- | ------------------------------------------- | ------------ | -------------- | -------------- |
| 1     | Sepolia Testing                             | Jan 2025     | Feb 4, 2025    | ✅ Complete    |
| 2     | Mainnet Infrastructure Deployment           | Feb 4, 2025  | TBD            | 🔄 In Progress |
| 3     | Pre-Configuration & Monitoring              | TBD          | TBD + 1 week   | ⏳ Pending     |
| 3.3   | Sepolia Integration with Horizon (parallel) | TBD          | TBD            | ⏳ Pending     |
| 4     | USTB Pilot Activation                       | TBD          | TBD            | ⏳ Pending     |
| 5     | USTB Validation Period                      | TBD          | TBD + 3-7 days | ⏳ Pending     |
| 6     | Full Asset Activation                       | TBD          | TBD            | ⏳ Pending     |
| 7     | Ownership Transfers                         | TBD          | TBD            | ⏳ Pending     |

### Key Dependencies & Blockers

| Dependency                   | Owner     | Blocks                   | Status       |
| ---------------------------- | --------- | ------------------------ | ------------ |
| CRE workflow config          | Chainlink | Phase 2 proxy deployment | ⏳ Awaiting  |
| Chainlink kickoff meeting    | All       | Timeline refinement      | ⏳ Scheduled |
| Aggregator switch delay info | Chainlink | Phase 4 planning         | ⏳ Awaiting  |

---

## System Architecture Overview

### Per-Asset Components

Each asset (USCC, USTB, USYC, JTRSY, JAAA, ACRED) requires its own oracle infrastructure:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Per-Asset Components                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  USCC:   LlamaGuardOracle(USCC) ← LlamaGuardOracleProxy(USCC) ← CRE     │
│              ↓                                                          │
│          EACAggregatorProxy(USCC) [Chainlink-owned]                     │
│                                                                         │
│  USTB:   LlamaGuardOracle(USTB) ← LlamaGuardOracleProxy(USTB) ← CRE     │
│              ↓                                                          │
│          EACAggregatorProxy(USTB) [Chainlink-owned]                     │
│                                                                         │
│  USYC:   LlamaGuardOracle(USYC) ← LlamaGuardOracleProxy(USYC) ← CRE     │
│              ↓                                                          │
│          EACAggregatorProxy(USYC) [Chainlink-owned]                     │
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
│    ├── agentId=1: USTB  → riskOracle: LlamaGuardOracle(USTB)            │
│    ├── agentId=2: USCC  → riskOracle: LlamaGuardOracle(USCC)            │
│    ├── agentId=3: USYC  → riskOracle: LlamaGuardOracle(USYC)            │
│    ├── agentId=4: JTRSY → riskOracle: LlamaGuardOracle(JTRSY)           │
│    ├── agentId=5: JAAA  → riskOracle: LlamaGuardOracle(JAAA)            │
│    └── agentId=6: ACRED → riskOracle: LlamaGuardOracle(ACRED)           │
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
// Agent registration for USTB
AgentRegistrationInput({
    agentAddress: freezeAgentAddress,        // Same FreezeAgent for all
    riskOracle: llamaGuardOracleUSTB,        // USTB-specific oracle
    admin: llamaRiskMultisig,                // LlamaRisk as agent admin
    agentContext: abi.encode(poolConfiguratorAddress),
    isAgentEnabled: true,
    isAgentPermissioned: false,
    isMarketsFromAgentEnabled: false,
    expirationPeriod: 86400,
    minimumDelay: 0,
    updateType: "boundedNAV",
    allowedMarkets: [USTB_TOKEN_ADDRESS],    // Single market per registration
    restrictedMarkets: [],
    permissionedSenders: []
})

// Repeat for USCC with llamaGuardOracleUSCC, [USCC_TOKEN_ADDRESS], etc.
```

### Chainlink Actions Per Asset

For each asset, Chainlink performs:

```solidity
// Switch aggregator in existing EACAggregatorProxy
EACAggregatorProxy(assetProxy).proposeAggregator(llamaGuardOracleAddress);
// After confirmation period (TBD - ask Chainlink)
EACAggregatorProxy(assetProxy).confirmAggregator(llamaGuardOracleAddress);
```

---

## Pre-Deployment Checklist

### Addresses Required

- [ ] **Horizon Multisig Address** - Owner of HorizonAgentHub
- [ ] **LlamaRisk Multisig Address** - Owner of LlamaGuardOracle, LlamaGuardOracleProxy; Updater of ParameterRegistry;
      Agent Admin in HorizonAgentHub
- [ ] **Aave Pool Address** - Existing Horizon Pool contract
- [ ] **Aave PoolConfigurator Address** - Existing Horizon PoolConfigurator contract
- [ ] **Aave ACLManager Address** - For granting RISK_ADMIN role

### Agent Admin Role (LlamaRisk)

LlamaRisk serves as **agent admin** for all registered agents in HorizonAgentHub. This allows LlamaRisk to:

- Enable/disable agents (`setAgentEnabled`)
- Add/remove allowed markets (`addAllowedMarket`, `removeAllowedMarket`)
- Adjust timing parameters (`setMinimumDelay`, `setExpirationPeriod`)
- Configure permissioned senders if needed

**Note:** Agent admin cannot change the agent contract address or reassign the admin role - only the hub owner (Horizon)
can do that.

### Chainlink Configuration (from Chainlink team)

- [ ] **workflowId** (bytes32) - CRE workflow identifier
- [ ] **expectedForwarder** (address) - Chainlink CrossDomainForwarder address
- [ ] **expectedAuthor** (address) - Workflow author address
- [ ] **expectedWorkflowName** (bytes10) - Workflow name identifier
- [ ] **Aggregator switch delay** - Time between proposeAggregator and confirmAggregator (TBD)

### First Wave Asset Configuration (USCC, USTB, USYC)

For each asset:

| Asset | Token Address | EACAggregatorProxy Address | maxExpectedApy | Tolerances |
| ----- | ------------- | -------------------------- | -------------- | ---------- |
| USCC  | TBD           | TBD                        | TBD BPS        | TBD        |
| USTB  | TBD           | TBD                        | TBD BPS        | TBD        |
| USYC  | TBD           | TBD                        | TBD BPS        | TBD        |

### Second Wave Asset Configuration (JTRSY, JAAA, ACRED)

| Asset | Token Address | EACAggregatorProxy Address | maxExpectedApy | Tolerances |
| ----- | ------------- | -------------------------- | -------------- | ---------- |
| JTRSY | TBD           | TBD                        | TBD BPS        | TBD        |
| JAAA  | TBD           | TBD                        | TBD BPS        | TBD        |
| ACRED | TBD           | TBD                        | TBD BPS        | TBD        |

---

## Phase 1: Sepolia Integration Testing ✅

**Status: COMPLETE (February 4, 2025)** **Owner: LlamaRisk (internal)**

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

- [ ] LlamaGuardOracle instances (USCC, USTB)
- [ ] LlamaGuardOracleProxy instances
- [ ] EACAggregatorProxy instances (for testing)
- [ ] Seeds oracles with initial data from source oracles

**Post-Deploy Verification:**

- [ ] All contracts deployed and verified on Etherscan
- [ ] Oracle proxies have WRITER_ROLE granted
- [ ] Registry assets configured with correct oracle addresses

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

- [ ] `oracle.latestRoundData()` returns new roundId
- [ ] `oracle.latestAnswer()` returns expected price
- [ ] Event `ParameterUpdated` emitted

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

- [ ] `shouldExecute` returns `true`
- [ ] `actions` array contains correct agentId and market

**Step 3: Execute Freeze via Hub**

```solidity
hub.execute(actions);
```

- [ ] Transaction succeeds
- [ ] Event `ReserveFreezeUpdated` emitted from FreezeAgent
- [ ] Event `UpdateInjected` emitted from AgentHub

**Step 4: Verify Market State**

```solidity
DataTypes.ReserveConfigurationMap memory config = pool.getConfiguration(marketAddress);
bool isFrozen = config.getFrozen();
```

- [ ] `isFrozen` returns `true`

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

- [ ] `shouldExecute` returns `false` (agent rejects unfreeze)

**Test 2: Already Frozen Market Rejected**

- [ ] Push freeze update for already-frozen market
- [ ] `hub.check()` returns `false` (prevents double-freeze)

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

- [ ] Transaction reverts with `UnauthorizedUpdateType`

---

### 1.5 Sepolia Testing Complete

| Test                 | Status   | Notes |
| -------------------- | -------- | ----- |
| Oracle deployment    | [ ] Pass |       |
| Proxy WRITER_ROLE    | [ ] Pass |       |
| Normal price update  | [ ] Pass |       |
| Freeze update        | [ ] Pass |       |
| Validation rejection | [ ] Pass |       |

**Internal sign-off (LlamaRisk):** ********\_******** Date: **\_\_\_**

---

## Phase 2: Mainnet Infrastructure Deployment 🔄

**Status: IN PROGRESS (Started February 4, 2025)**

Deploy all infrastructure. **No activation yet.**

### 2.1 Deploy LlamaGuardOracle (per asset)

| Field        | Value                         |
| ------------ | ----------------------------- |
| **Contract** | `LlamaGuardOracle`            |
| **Deployer** | LlamaRisk                     |
| **Assets**   | USCC, USTB, USYC (first wave) |

**Deploy one oracle per asset:**

```bash
# Deploy USCC oracle
forge script script/llamaguard-oracle/DeployLlamaGuardOracle.s.sol \
  --rpc-url $RPC_URL --broadcast --verify \
  --sig "run(string)" "USCC"

# Repeat for USTB, USYC
```

**Post-Deploy Checklist:**

- [ ] LlamaGuardOracle(USCC) deployed: `0x___`
- [ ] LlamaGuardOracle(USTB) deployed: `0x___`
- [ ] LlamaGuardOracle(USYC) deployed: `0x___`

---

### 2.2 Deploy LlamaGuardOracleProxy (per asset)

| Field            | Value                                  |
| ---------------- | -------------------------------------- |
| **Contract**     | `LlamaGuardOracleProxy`                |
| **Deployer**     | LlamaRisk                              |
| **Dependencies** | LlamaGuardOracle, Chainlink CRE config |

**Post-Deploy Checklist:**

- [ ] LlamaGuardOracleProxy(USCC) deployed: `0x___`
- [ ] LlamaGuardOracleProxy(USTB) deployed: `0x___`
- [ ] LlamaGuardOracleProxy(USYC) deployed: `0x___`

---

### 2.3 Grant WRITER_ROLE to Proxies

| Field        | Value                                 |
| ------------ | ------------------------------------- |
| **Contract** | `LlamaGuardOracle` (each)             |
| **Caller**   | LlamaRisk (DEFAULT_ADMIN_ROLE holder) |

```solidity
// For each oracle/proxy pair
LlamaGuardOracle(uscc).grantRole(WRITER_ROLE, proxyUSCC);
LlamaGuardOracle(ustb).grantRole(WRITER_ROLE, proxyUSTB);
LlamaGuardOracle(usyc).grantRole(WRITER_ROLE, proxyUSYC);
```

**Verification:**

- [ ] USCC: `oracle.hasRole(WRITER_ROLE, proxy)` = true
- [ ] USTB: `oracle.hasRole(WRITER_ROLE, proxy)` = true
- [ ] USYC: `oracle.hasRole(WRITER_ROLE, proxy)` = true

---

### 2.4 Add Authorized Markets to Oracles

| Field        | Value                                 |
| ------------ | ------------------------------------- |
| **Contract** | `LlamaGuardOracle` (each)             |
| **Caller**   | LlamaRisk (DEFAULT_ADMIN_ROLE holder) |

```solidity
// Each oracle authorizes its own token as a market
LlamaGuardOracle(uscc).addAuthorizedMarket(USCC_TOKEN);
LlamaGuardOracle(ustb).addAuthorizedMarket(USTB_TOKEN);
LlamaGuardOracle(usyc).addAuthorizedMarket(USYC_TOKEN);
```

---

### 2.5 Deploy HorizonAgentHub

| Field        | Value             |
| ------------ | ----------------- |
| **Contract** | `HorizonAgentHub` |
| **Deployer** | Horizon           |

**Post-Deploy:**

- [ ] HorizonAgentHub deployed: `0x___`
- [ ] `owner()` = Horizon multisig

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

- [ ] HorizonFreezeAgent deployed: `0x___`
- [ ] `AGENT_HUB()` = HorizonAgentHub address
- [ ] `POOL()` = Aave Pool address

---

### 2.7 Activate CRE Workflow

| Field     | Value     |
| --------- | --------- |
| **Owner** | Chainlink |

- [ ] Chainlink activates CRE workflow
- [ ] Oracle updates start flowing to LlamaGuardOracles

---

### Phase 2 Complete Checklist

| Component                    | Address | Status |
| ---------------------------- | ------- | ------ |
| LlamaGuardOracle(USCC)       |         | [ ]    |
| LlamaGuardOracle(USTB)       |         | [ ]    |
| LlamaGuardOracle(USYC)       |         | [ ]    |
| LlamaGuardOracleProxy(USCC)  |         | [ ]    |
| LlamaGuardOracleProxy(USTB)  |         | [ ]    |
| LlamaGuardOracleProxy(USYC)  |         | [ ]    |
| HorizonAgentHub              |         | [ ]    |
| HorizonFreezeAgent           |         | [ ]    |
| WRITER_ROLE granted (all)    | -       | [ ]    |
| Authorized markets set (all) | -       | [ ]    |
| CRE workflow active          | -       | [ ]    |

---

## Phase 3: Pre-Configuration & Monitoring

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

---

### 3.2 Oracle Monitoring

**Daily Checks:**

| Day | Date | Updates Received | State=1 Count | Issues |
| --- | ---- | ---------------- | ------------- | ------ |
| 1   |      |                  |               |        |
| 2   |      |                  |               |        |
| 3   |      |                  |               |        |
| 4   |      |                  |               |        |
| 5   |      |                  |               |        |
| 6   |      |                  |               |        |
| 7   |      |                  |               |        |

---

### 3.3 Sepolia Integration Testing with Horizon (Parallel Track)

**Runs in parallel with mainnet monitoring.** **Owner: LlamaRisk + Horizon**

While mainnet oracles are being monitored, conduct full end-to-end integration testing on Sepolia with
HorizonFreezeAgent.

**Prerequisites:**

- [ ] HorizonAgentHub deployed on Sepolia
- [ ] HorizonFreezeAgent deployed on Sepolia
- [ ] Sepolia Horizon Pool available (or mock contracts)

**Test Scenarios:**

- [ ] Register agent in Sepolia hub
- [ ] Push out of bounds update to raw NAV
- [ ] Verify CRE picks up and update freeze state
- [ ] Verify `hub.check()` returns actionable data
- [ ] Execute freeze via `hub.execute()`
- [ ] Confirm market is frozen on Sepolia pool
- [ ] Test validation rejection (unfreeze, double-freeze)

**Completion Criteria:**

- [ ] Full freeze flow validated on Sepolia
- [ ] No issues with agent registration or execution

---

### 3.4 Go/No-Go Decision

**Prerequisites for proceeding to Phase 4:**

- [ ] No false positive freeze signals during monitoring period
- [ ] Price data consistently matches expected NAV values
- [ ] Bound calculations verified as accurate
- [ ] No unexpected errors or reverts
- [ ] RISK_ADMIN granted to FreezeAgent
- [ ] Sepolia integration testing with Horizon complete (Section 3.3)

**Sign-off Required:**

- [ ] LlamaRisk: ********\_******** Date: **\_\_\_**
- [ ] Horizon: ********\_******** Date: **\_\_\_**
- [ ] Chainlink: ********\_******** Date: **\_\_\_**

**Decision:**

- [ ] **GO** - Proceed to Phase 4: USTB Pilot
- [ ] **NO-GO** - Extend monitoring / investigate issues

---

## Phase 4: USTB Pilot Activation

**Activate USTB only to validate the full system before expanding.**

### 4.1 Switch Chainlink Proxy (USTB)

| Field        | Value                      |
| ------------ | -------------------------- |
| **Contract** | `EACAggregatorProxy(USTB)` |
| **Caller**   | Chainlink                  |

```solidity
// Step 1: Propose new aggregator
EACAggregatorProxy(ustbProxy).proposeAggregator(llamaGuardOracleUSTB);

// Step 2: After delay (TBD), confirm
EACAggregatorProxy(ustbProxy).confirmAggregator(llamaGuardOracleUSTB);
```

**Verification:**

- [ ] `EACAggregatorProxy(ustbProxy).aggregator()` = LlamaGuardOracle(USTB)
- [ ] `EACAggregatorProxy(ustbProxy).latestAnswer()` returns expected price

---

### 4.2 Register USTB Agent in Hub

| Field        | Value             |
| ------------ | ----------------- |
| **Contract** | `HorizonAgentHub` |
| **Caller**   | Horizon (owner)   |

```solidity
HorizonAgentHub.registerAgent(
    IAgentConfigurator.AgentRegistrationInput({
        agentAddress: freezeAgentAddress,
        riskOracle: llamaGuardOracleUSTB,
        admin: llamaRiskMultisig,            // LlamaRisk as agent admin
        agentContext: abi.encode(poolConfiguratorAddress),
        isAgentEnabled: true,
        isAgentPermissioned: false,
        isMarketsFromAgentEnabled: false,
        expirationPeriod: 86400,
        minimumDelay: 0,
        updateType: "boundedNAV",
        allowedMarkets: [USTB_TOKEN_ADDRESS],
        restrictedMarkets: [],
        permissionedSenders: []
    })
)
```

**Returns:** `agentId` for USTB (record this)

**Verification:**

- [ ] `hub.getAgentAddress(agentId)` = FreezeAgent
- [ ] `hub.isAgentEnabled(agentId)` = true
- [ ] `hub.getRiskOracle(agentId)` = LlamaGuardOracle(USTB)

---

### Phase 4 Complete - USTB Now Operational

| Component                          | Status |
| ---------------------------------- | ------ |
| Chainlink proxy switched to USTB   | [ ]    |
| USTB agent registered in hub       | [ ]    |
| USTB freeze capability operational | [ ]    |

---

## Phase 5: USTB Validation Period

**Duration: TBD (recommend 3-7 days minimum)**

### 5.1 USTB Monitoring

**Daily Checks:**

| Day | Date | Oracle Working | Hub Check() OK | Issues |
| --- | ---- | -------------- | -------------- | ------ |
| 1   |      | [ ]            | [ ]            |        |
| 2   |      | [ ]            | [ ]            |        |
| 3   |      | [ ]            | [ ]            |        |

### 5.2 Success Criteria for USTB Pilot

**Technical Validation:**

- [ ] Chainlink proxy consistently returns correct price from LlamaGuardOracle
- [ ] `hub.check([ustbAgentId])` returns expected results
- [ ] No false positive freeze signals
- [ ] Price feed latency acceptable

**Operational Validation:**

- [ ] Aave frontend displays correct USTB prices
- [ ] No user-reported issues with USTB market
- [ ] Liquidation calculations remain accurate

**Sign-off Required Before Expanding:**

- [ ] LlamaRisk: ********\_******** Date: **\_\_\_**
- [ ] Horizon: ********\_******** Date: **\_\_\_**
- [ ] Chainlink: ********\_******** Date: **\_\_\_**

**Decision:**

- [ ] **GO** - Proceed to Phase 6: Full Asset Activation
- [ ] **NO-GO** - Investigate issues / extend validation

---

## Phase 6: Full Asset Activation

**Activate remaining assets: USCC, USYC, JTRSY, JAAA, ACRED**

### 6.1 Switch Chainlink Proxies (Remaining Assets)

| Asset | EACAggregatorProxy | LlamaGuardOracle | Switch Status |
| ----- | ------------------ | ---------------- | ------------- |
| USCC  | 0x\_\_\_           | 0x\_\_\_         | [ ]           |
| USYC  | 0x\_\_\_           | 0x\_\_\_         | [ ]           |
| JTRSY | 0x\_\_\_           | 0x\_\_\_         | [ ]           |
| JAAA  | 0x\_\_\_           | 0x\_\_\_         | [ ]           |
| ACRED | 0x\_\_\_           | 0x\_\_\_         | [ ]           |

---

### 6.2 Register Remaining Agents in Hub

```solidity
// USCC
hub.registerAgent({
    riskOracle: llamaGuardOracleUSCC,
    allowedMarkets: [USCC_TOKEN_ADDRESS],
    // ... same config as USTB
});

// USYC
hub.registerAgent({
    riskOracle: llamaGuardOracleUSYC,
    allowedMarkets: [USYC_TOKEN_ADDRESS],
    // ... same config as USTB
});

// JTRSY, JAAA, ACRED similarly
```

**Agent ID Registry:**

| Asset | agentId | Oracle Address | Status |
| ----- | ------- | -------------- | ------ |
| USTB  |         | 0x\_\_\_       | [ ]    |
| USCC  |         | 0x\_\_\_       | [ ]    |
| USYC  |         | 0x\_\_\_       | [ ]    |
| JTRSY |         | 0x\_\_\_       | [ ]    |
| JAAA  |         | 0x\_\_\_       | [ ]    |
| ACRED |         | 0x\_\_\_       | [ ]    |

---

### Phase 6 Complete - All Assets Operational

| Component                          | Status |
| ---------------------------------- | ------ |
| All Chainlink proxies switched     | [ ]    |
| All agents registered in hub       | [ ]    |
| Full freeze capability operational | [ ]    |

---

## Phase 7: Ownership Transfers

### 7.1 Transfer LlamaGuardOracle Admin (if needed)

```solidity
// For each oracle
oracle.grantRole(DEFAULT_ADMIN_ROLE, newAdminAddress);
oracle.revokeRole(DEFAULT_ADMIN_ROLE, oldAdminAddress);
```

### 7.2 Transfer LlamaGuardOracleProxy Ownership (if needed)

```solidity
// Two-step transfer (Ownable2Step)
proxy.transferOwnership(newOwnerAddress);
// New owner accepts
proxy.acceptOwnership();
```

---

## Cross-Org Coordination Summary

| Step                                             | Owner                           | Depends On      | Blocker For |
| ------------------------------------------------ | ------------------------------- | --------------- | ----------- |
| Provide CRE config                               | Chainlink                       | None            | Phase 1     |
| **Phase 1**: Sepolia testing                     | LlamaRisk                       | CRE config      | Phase 2     |
| **Phase 2**: Deploy oracles, proxies, hub, agent | LlamaRisk + Horizon             | Phase 1         | Phase 3     |
| Activate CRE workflow                            | Chainlink                       | Phase 2 oracles | Phase 3     |
| **Phase 3**: Grant RISK_ADMIN, monitor           | Horizon + LlamaRisk             | CRE active      | Phase 4     |
| Go/No-Go sign-off                                | LlamaRisk + Horizon + Chainlink | Monitoring      | Phase 4     |
| **Phase 4**: Switch USTB proxy, register agent   | Chainlink + Horizon             | Sign-off        | Phase 5     |
| **Phase 5**: USTB validation                     | All                             | USTB active     | Phase 6     |
| USTB validation sign-off                         | LlamaRisk + Horizon + Chainlink | USTB validation | Phase 6     |
| **Phase 6**: Activate remaining assets           | Chainlink + Horizon             | USTB sign-off   | Phase 7     |
| **Phase 7**: Ownership transfers                 | All                             | Phase 6         | System live |

---

## Open Questions for Chainlink Kickoff

- [ ] What is the delay between `proposeAggregator` and `confirmAggregator`?
- [ ] Will Chainlink deploy EACAggregatorProxy for Sepolia testing?
- [ ] CRE workflow configuration parameters (workflowId, forwarder, author, name)
- [ ] Coordination process for aggregator switch timing

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
// 3. Chainlink switches aggregator
// 4. Update agent registration if needed
```

---

## Deployment Summary Template

### Phase 2: Infrastructure

| Contract                    | Address | Deployer  | Tx Hash | Date |
| --------------------------- | ------- | --------- | ------- | ---- |
| LlamaGuardOracle(USCC)      |         | LlamaRisk |         |      |
| LlamaGuardOracle(USTB)      |         | LlamaRisk |         |      |
| LlamaGuardOracle(USYC)      |         | LlamaRisk |         |      |
| LlamaGuardOracleProxy(USCC) |         | LlamaRisk |         |      |
| LlamaGuardOracleProxy(USTB) |         | LlamaRisk |         |      |
| LlamaGuardOracleProxy(USYC) |         | LlamaRisk |         |      |
| HorizonAgentHub             |         | Horizon   |         |      |
| HorizonFreezeAgent          |         | Horizon   |         |      |

### Phase 4-6: Activation Timeline

| Asset | Chainlink Switch Date | Agent Registration Date | agentId |
| ----- | --------------------- | ----------------------- | ------- |
| USTB  |                       |                         |         |
| USCC  |                       |                         |         |
| USYC  |                       |                         |         |
| JTRSY |                       |                         |         |
| JAAA  |                       |                         |         |
| ACRED |                       |                         |         |

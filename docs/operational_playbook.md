# Operational Playbook

This playbook provides step-by-step instructions for making the LlamaGuard NAV oracle system with Aave Horizon
integration operational.

---

## Pre-Deployment Checklist

### Addresses Required

- [ ] **Horizon Multisig Address** - Owner of ParameterRegistry, HorizonAgentHub
- [ ] **LlamaRisk Multisig Address** - Owner of LlamaGuardOracle, LlamaGuardOracleProxy; Updater of ParameterRegistry
- [ ] **Aave Pool Address** - Existing Horizon Pool contract
- [ ] **Aave PoolConfigurator Address** - Existing Horizon PoolConfigurator contract
- [ ] **Aave ACLManager Address** - For granting RISK_ADMIN role

### Chainlink Configuration (from Chainlink team)

- [ ] **workflowId** (bytes32) - CRE workflow identifier
- [ ] **expectedForwarder** (address) - Chainlink CrossDomainForwarder address
- [ ] **expectedAuthor** (address) - Workflow author address
- [ ] **expectedWorkflowName** (bytes10) - Workflow name identifier

### Asset Configuration

For each asset (JAAA, USTB, JTRSY, USCC, USYC, vBILL, ACRED):

- [ ] Asset token address
- [ ] maxExpectedApy (BPS, max 20000)
- [ ] upperBoundTolerance (BPS, max 250)
- [ ] lowerBoundTolerance (BPS, max 250)
- [ ] maxDiscount (BPS, max 250)
- [ ] lookbackWindowSize (blocks)

### Environment Setup

- [ ] RPC endpoint configured
- [ ] Deployer wallet funded with ETH
- [ ] `MNEMONIC` or `ETH_FROM` environment variable set
- [ ] Etherscan API key for verification

---

## Open Questions

- [ ] **EACAggregatorProxy on Sepolia**: Will Chainlink deploy the EACAggregatorProxy for Sepolia testing, or should
      LlamaRisk deploy a local instance using `src/sepolia/EACAggregatorProxy.sol`? If Chainlink is not available for
      Sepolia, determine the appropriate approach for Aave integration testing.

---

## Phase 1: Sepolia Integration Testing

**Before any mainnet deployment**, validate the full system on Sepolia testnet.

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
- [ ] EACAggregatorProxy instances
- [ ] ParameterRegistry with test configuration
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

### 1.5 Sepolia Testing Sign-Off

| Test                           | Status   | Notes |
| ------------------------------ | -------- | ----- |
| Oracle deployment              | [ ] Pass |       |
| Proxy WRITER_ROLE              | [ ] Pass |       |
| Normal price update            | [ ] Pass |       |
| Freeze update                  | [ ] Pass |       |
| Agent check() returns true     | [ ] Pass |       |
| Agent execute() freezes market | [ ] Pass |       |
| Unfreeze rejected              | [ ] Pass |       |
| Double-freeze rejected         | [ ] Pass |       |
| Invalid update type rejected   | [ ] Pass |       |

**Sign-off Required Before Proceeding to Mainnet:**

- [ ] LlamaRisk: **\*\*\*\***\_**\*\*\*\*** Date: **\_\_\_**
- [ ] Horizon: **\*\*\*\***\_**\*\*\*\*** Date: **\_\_\_**
- [ ] Chainlink: **\*\*\*\***\_**\*\*\*\*** Date: **\_\_\_**

---

## Phase 2: Mainnet Oracle Infrastructure

Deploy oracle infrastructure only. **Do NOT deploy agent infrastructure yet.**

### 2.1 Deploy LlamaGuardOracle

| Field            | Value              |
| ---------------- | ------------------ |
| **Contract**     | `LlamaGuardOracle` |
| **Deployer**     | LlamaRisk          |
| **Dependencies** | None               |

**Constructor Parameters:**

```solidity
constructor(
    uint8 decimals_,              // 6 for USD-based, 8 for others
    string memory description_,   // e.g., "LlamaGuard USCC Risk Oracle"
    uint256 version_,             // 1
    string[] memory updateTypes,  // ["boundedNAV"]
    address[] memory authorizedMarkets  // [] (empty, add later)
)
```

**Command:**

```bash
forge script script/llamaguard-oracle/DeployLlamaGuardOracle.s.sol \
  --rpc-url $RPC_URL --broadcast --verify
```

**Post-Deploy:**

- [ ] Record deployed oracle address
- [ ] Verify DEFAULT_ADMIN_ROLE is granted to deployer

---

### 2.2 Deploy LlamaGuardOracleProxy

| Field            | Value                                         |
| ---------------- | --------------------------------------------- |
| **Contract**     | `LlamaGuardOracleProxy`                       |
| **Deployer**     | LlamaRisk                                     |
| **Dependencies** | LlamaGuardOracle (step 2.1), Chainlink config |

**Constructor Parameters:**

```solidity
constructor(
    address llamaGuardOracleAddress,  // From step 2.1
    bytes32 workflowId,               // From Chainlink
    address expectedForwarder,        // From Chainlink
    address expectedAuthor,           // From Chainlink
    bytes10 expectedWorkflowName,     // From Chainlink
    string memory _description        // e.g., "LlamaGuard USCC Oracle Proxy"
)
```

**Post-Deploy:**

- [ ] Record deployed proxy address
- [ ] Verify owner() returns deployer address

---

### 2.3 Grant WRITER_ROLE to Proxy

| Field            | Value                                 |
| ---------------- | ------------------------------------- |
| **Contract**     | `LlamaGuardOracle`                    |
| **Caller**       | LlamaRisk (DEFAULT_ADMIN_ROLE holder) |
| **Dependencies** | Steps 2.1, 2.2                        |

**Function Call:**

```solidity
LlamaGuardOracle.grantRole(
    keccak256("WRITER_ROLE"),  // WRITER_ROLE
    proxyAddress               // LlamaGuardOracleProxy address
)
```

**Verification:**

- [ ] `oracle.hasRole(oracle.WRITER_ROLE(), proxyAddress)` returns `true`

---

### 2.4 Add Authorized Markets

| Field        | Value                                 |
| ------------ | ------------------------------------- |
| **Contract** | `LlamaGuardOracle`                    |
| **Caller**   | LlamaRisk (DEFAULT_ADMIN_ROLE holder) |

**Function Call (for each market):**

```solidity
LlamaGuardOracle.addAuthorizedMarket(marketAddress)
```

**Verification:**

- [ ] `oracle.isAuthorizedMarket(marketAddress)` returns `true` for each market

---

### 2.5 Deploy Chainlink Proxy (EACAggregatorProxy)

| Field            | Value                       |
| ---------------- | --------------------------- |
| **Contract**     | `EACAggregatorProxy`        |
| **Deployer**     | Chainlink                   |
| **Dependencies** | LlamaGuardOracle (step 2.1) |

**Constructor Parameters:**

```solidity
constructor(address _aggregator)  // LlamaGuardOracle address
```

**Post-Deploy:**

- [ ] Record Chainlink proxy address
- [ ] This is the address Horizon Pool will use for price feeds

---

### 2.6 Deploy ParameterRegistry

| Field            | Value               |
| ---------------- | ------------------- |
| **Contract**     | `ParameterRegistry` |
| **Deployer**     | Horizon             |
| **Dependencies** | None                |

**Constructor Parameters:**

```solidity
constructor(
    address _owner,    // Horizon multisig
    address _updater   // LlamaRisk multisig
)
```

**Command:**

```bash
forge script script/parameter-registry/DeployParameterRegistry.s.sol \
  --rpc-url $RPC_URL --broadcast --verify
```

**Post-Deploy:**

- [ ] Record registry address
- [ ] Verify `owner()` returns Horizon address
- [ ] Verify `updater()` returns LlamaRisk address

---

### 2.7 Configure Assets on ParameterRegistry

| Field            | Value                                |
| ---------------- | ------------------------------------ |
| **Contract**     | `ParameterRegistry`                  |
| **Caller**       | LlamaRisk (updater)                  |
| **Dependencies** | Step 2.6, Chainlink Proxy (step 2.5) |

**Function Call (for each asset):**

```solidity
ParameterRegistry.setParametersForAsset(
    address asset,                  // Token address
    string memory name,             // e.g., "USCC"
    address oracle,                 // Chainlink Proxy address (NOT LlamaGuardOracle directly)
    uint64 maxExpectedApy,          // e.g., 2500 (25%)
    uint32 upperBoundTolerance,     // e.g., 100 (1%)
    uint32 lowerBoundTolerance,     // e.g., 50 (0.5%)
    uint32 maxDiscount,             // e.g., 200 (2%)
    uint80 lookbackWindowSize,      // e.g., 7200 blocks
    bool isUpperBoundEnabled,       // true
    bool isLowerBoundEnabled,       // true
    bool isActionTakingEnabled      // true
)
```

**Verification:**

- [ ] `registry.getParametersForAsset(assetAddress)` returns expected config

---

### 2.8 Activate CRE Workflow

| Field            | Value                      |
| ---------------- | -------------------------- |
| **Owner**        | Chainlink                  |
| **Dependencies** | All Phase 2 steps complete |

- [ ] Chainlink activates CRE workflow
- [ ] First oracle updates start flowing to LlamaGuardOracle
- [ ] Verify data is being written correctly

**Phase 2 Complete Checklist:**

- [ ] LlamaGuardOracle deployed and verified
- [ ] LlamaGuardOracleProxy deployed and verified
- [ ] WRITER_ROLE granted to proxy
- [ ] Authorized markets added
- [ ] Chainlink Proxy deployed
- [ ] ParameterRegistry deployed and configured
- [ ] CRE workflow active and pushing data

---

## Phase 3: Oracle Monitoring Period

**Duration: 1 week minimum**

Before enabling agent infrastructure, monitor the oracle for data quality and potential false positives.

### 3.1 Monitoring Checklist

**Daily Checks:**

- [ ] Day 1: **_/_**/**_ - Oracle updates received: _** | Issues: \_\_\_
- [ ] Day 2: **_/_**/**_ - Oracle updates received: _** | Issues: \_\_\_
- [ ] Day 3: **_/_**/**_ - Oracle updates received: _** | Issues: \_\_\_
- [ ] Day 4: **_/_**/**_ - Oracle updates received: _** | Issues: \_\_\_
- [ ] Day 5: **_/_**/**_ - Oracle updates received: _** | Issues: \_\_\_
- [ ] Day 6: **_/_**/**_ - Oracle updates received: _** | Issues: \_\_\_
- [ ] Day 7: **_/_**/**_ - Oracle updates received: _** | Issues: \_\_\_

### 3.2 Data Quality Verification

**Price Accuracy:**

```solidity
// Compare oracle price with expected NAV
int256 oraclePrice = oracle.latestAnswer();
// Compare against issuer-reported NAV
```

- [ ] Price data matches expected NAV values (within tolerance)
- [ ] No significant deviations from issuer-reported values

**Bound Calculations:**

- [ ] Upper bound calculations are accurate
- [ ] Lower bound calculations are accurate
- [ ] State determination (freeze vs normal) is correct

**Update Frequency:**

- [ ] Updates received at expected intervals
- [ ] No missed updates or gaps

### 3.3 False Positive Analysis

**Critical: Verify NO false freeze signals would have occurred**

For each update during monitoring period:

```solidity
// Check state value in additionalData
(int256 lowerBound, int256 upperBound, uint256 state) =
    abi.decode(update.additionalData, (int256, int256, uint256));

// state == 1 means freeze would have triggered
```

- [ ] Total updates with state=0 (normal): \_\_\_
- [ ] Total updates with state=1 (freeze): \_\_\_
- [ ] Any state=1 updates were legitimate breach scenarios: [ ] Yes / [ ] No

**If any unexpected state=1 updates occurred:**

- [ ] Root cause identified: \***\*\*\*\*\***\_\_\_\***\*\*\*\*\***
- [ ] Issue resolved: [ ] Yes / [ ] No
- [ ] Extended monitoring required: [ ] Yes / [ ] No

### 3.4 Go/No-Go Decision

**Prerequisites for proceeding to Phase 4:**

- [ ] No false positive freeze signals during monitoring period
- [ ] Price data consistently matches expected NAV values
- [ ] Bound calculations verified as accurate
- [ ] No unexpected errors or reverts
- [ ] Update frequency meets expectations

**Sign-off Required Before Proceeding:**

- [ ] LlamaRisk: **\*\*\*\***\_**\*\*\*\*** Date: **\_\_\_**
- [ ] Horizon: **\*\*\*\***\_**\*\*\*\*** Date: **\_\_\_**

**Decision:**

- [ ] **GO** - Proceed to Phase 4: Agent Infrastructure
- [ ] **NO-GO** - Extend monitoring / investigate issues

---

## Phase 4: Mainnet Agent Infrastructure

**Only proceed after Phase 3 sign-off.**

### 4.1 Deploy HorizonAgentHub

| Field            | Value             |
| ---------------- | ----------------- |
| **Contract**     | `HorizonAgentHub` |
| **Deployer**     | Horizon           |
| **Dependencies** | None              |

**Constructor:** Inherits from `AgentHub` (BGD Labs), typically no constructor params.

**Post-Deploy:**

- [ ] Record AgentHub address
- [ ] Verify `owner()` returns Horizon address

---

### 4.2 Deploy HorizonFreezeAgent

| Field            | Value                                 |
| ---------------- | ------------------------------------- |
| **Contract**     | `HorizonFreezeAgent`                  |
| **Deployer**     | Horizon                               |
| **Dependencies** | HorizonAgentHub (step 4.1), Aave Pool |

**Constructor Parameters:**

```solidity
constructor(
    address agentHub,  // HorizonAgentHub address
    address pool       // Aave Pool address
)
```

**Post-Deploy:**

- [ ] Record FreezeAgent address
- [ ] Verify `AGENT_HUB()` returns correct address
- [ ] Verify `POOL()` returns correct address

---

### 4.3 Register Agent in HorizonAgentHub

| Field            | Value                          |
| ---------------- | ------------------------------ |
| **Contract**     | `HorizonAgentHub`              |
| **Caller**       | Horizon (owner)                |
| **Dependencies** | Steps 4.1, 4.2, Phase 2 oracle |

**Function Call:**

```solidity
HorizonAgentHub.registerAgent(
    IAgentConfigurator.AgentRegistrationInput({
        agentAddress: freezeAgentAddress,
        riskOracle: llamaGuardOracleAddress,  // LlamaGuardOracle, NOT proxy
        admin: agentAdminAddress,             // Can be same as Horizon multisig
        agentContext: abi.encode(poolConfiguratorAddress),
        isAgentEnabled: true,
        isAgentPermissioned: false,           // Permissionless execution
        isMarketsFromAgentEnabled: false,     // Markets from allowedMarkets list
        expirationPeriod: 86400,              // 1 day in seconds
        minimumDelay: 0,
        updateType: "boundedNAV",
        allowedMarkets: [market1, market2, ...],  // Asset addresses to protect
        restrictedMarkets: [],
        permissionedSenders: []
    })
)
```

**Returns:** `agentId` (uint256) - record this for verification

**Verification:**

- [ ] `hub.getAgentAddress(agentId)` returns FreezeAgent address
- [ ] `hub.isAgentEnabled(agentId)` returns `true`
- [ ] `hub.getRiskOracle(agentId)` returns LlamaGuardOracle address
- [ ] `hub.getUpdateType(agentId)` returns `"boundedNAV"`

---

### 4.4 Grant RISK_ADMIN to FreezeAgent

| Field            | Value                |
| ---------------- | -------------------- |
| **Contract**     | `ACLManager` (Aave)  |
| **Caller**       | Horizon (Pool Admin) |
| **Dependencies** | Step 4.2             |

**This is the final step that enables actual market freezing.**

**Function Call:**

```solidity
ACLManager.addRiskAdmin(freezeAgentAddress)
```

**Verification:**

- [ ] `aclManager.isRiskAdmin(freezeAgentAddress)` returns `true`

**System is now fully operational.**

---

## Phase 5: Ownership Transfers (Optional)

### 5.1 Transfer LlamaGuardOracle Admin

If transferring DEFAULT_ADMIN_ROLE from deployer to multisig:

```solidity
// Step 1: Grant role to new admin
oracle.grantRole(DEFAULT_ADMIN_ROLE, newAdminAddress)

// Step 2: Revoke from old admin
oracle.revokeRole(DEFAULT_ADMIN_ROLE, oldAdminAddress)
```

---

### 5.2 Transfer LlamaGuardOracleProxy Ownership

Two-step transfer (Ownable2Step):

```solidity
// Step 1: Current owner initiates
proxy.transferOwnership(newOwnerAddress)

// Step 2: New owner accepts
proxy.acceptOwnership()  // Called by new owner
```

---

## Cross-Org Coordination

| Step                                                     | Owner              | Depends On                | Blocker For        |
| -------------------------------------------------------- | ------------------ | ------------------------- | ------------------ |
| Provide CRE config (workflowId, forwarder, author, name) | Chainlink          | None                      | Sepolia testing    |
| **PHASE 1: Sepolia Testing**                             | All                | CRE config                | Mainnet deployment |
| Sepolia sign-off                                         | All                | Sepolia testing complete  | Phase 2 start      |
| Deploy LlamaGuardOracle                                  | LlamaRisk          | Sepolia sign-off          | OracleProxy        |
| Deploy LlamaGuardOracleProxy                             | LlamaRisk          | Oracle, CRE config        | WRITER_ROLE grant  |
| Grant WRITER_ROLE to proxy                               | LlamaRisk          | OracleProxy               | CRE activation     |
| Deploy Chainlink Proxy                                   | Chainlink          | Oracle                    | Registry config    |
| Deploy ParameterRegistry                                 | Horizon            | None                      | Asset config       |
| Configure assets                                         | LlamaRisk          | Registry, Chainlink Proxy | CRE operation      |
| Activate CRE workflow                                    | Chainlink          | All Phase 2               | Monitoring         |
| **PHASE 3: Oracle Monitoring (1 week)**                  | All                | CRE active                | Agent deployment   |
| Monitoring sign-off                                      | LlamaRisk, Horizon | 1 week passed, no issues  | Phase 4 start      |
| Deploy HorizonAgentHub                                   | Horizon            | Monitoring sign-off       | FreezeAgent        |
| Deploy HorizonFreezeAgent                                | Horizon            | AgentHub, Pool            | Agent registration |
| Register agent in Hub                                    | Horizon            | FreezeAgent, Oracle       | RISK_ADMIN grant   |
| **Grant RISK_ADMIN**                                     | Horizon            | Agent registered          | **System live**    |

---

## Verification Checklist

### LlamaGuardOracle

```solidity
// Basic info
oracle.decimals()         // Expected: 6 or 8
oracle.description()      // Expected: "LlamaGuard <ASSET> Risk Oracle"
oracle.version()          // Expected: 1

// Access control
oracle.hasRole(oracle.DEFAULT_ADMIN_ROLE(), llamaRiskMultisig)  // true
oracle.hasRole(oracle.WRITER_ROLE(), proxyAddress)              // true

// Configuration
oracle.isValidUpdateType("boundedNAV")      // true
oracle.isAuthorizedMarket(market1)          // true for each market
```

### LlamaGuardOracleProxy

```solidity
proxy.owner()                               // LlamaRisk multisig
proxy.llamaGuardOracle()                    // LlamaGuardOracle address
proxy.getWorkflowConfig(workflowId).isActive  // true
proxy.getWorkflowConfig(workflowId).expectedForwarder  // Chainlink forwarder
```

### ParameterRegistry

```solidity
registry.owner()          // Horizon multisig
registry.updater()        // LlamaRisk multisig

// For each asset
(name, oracle, exists, ...) = registry.getParametersForAsset(assetAddress)
// Verify: exists == true, oracle == Chainlink Proxy address
```

### HorizonAgentHub

```solidity
hub.owner()                           // Horizon multisig
hub.getAgentCount()                   // Expected agent count

// For each agent
hub.getAgentAddress(agentId)          // HorizonFreezeAgent address
hub.isAgentEnabled(agentId)           // true
hub.getRiskOracle(agentId)            // LlamaGuardOracle address
hub.getUpdateType(agentId)            // "boundedNAV"
hub.getAllowedMarkets(agentId)        // List of protected markets
hub.getAgentContext(agentId)          // abi.encode(poolConfiguratorAddress)
```

### HorizonFreezeAgent

```solidity
agent.AGENT_HUB()         // HorizonAgentHub address
agent.POOL()              // Aave Pool address
```

### Aave ACLManager

```solidity
aclManager.isRiskAdmin(freezeAgentAddress)  // true
```

---

## Rollback Plan

### If Oracle Deployment Fails (Phase 2)

- [ ] Retry deployment with corrected parameters
- [ ] No cleanup needed - failed deployment has no state

### If Proxy Deployment Fails (Step 2.2)

- [ ] Retry deployment
- [ ] Oracle can be reused; no need to redeploy

### If WRITER_ROLE Grant Fails (Step 2.3)

- [ ] Verify deployer still has DEFAULT_ADMIN_ROLE
- [ ] Retry grantRole transaction

### If ParameterRegistry Configuration Fails (Step 2.7)

- [ ] Verify caller is updater
- [ ] Check parameter values are within limits:
  - maxExpectedApy <= 20000 BPS
  - upperBoundTolerance <= 250 BPS
  - lowerBoundTolerance <= 250 BPS
  - maxDiscount <= 250 BPS
- [ ] Retry setParametersForAsset

### If Monitoring Reveals Issues (Phase 3)

- [ ] Do NOT proceed to Phase 4
- [ ] Identify and fix root cause
- [ ] Restart monitoring period
- [ ] Consider parameter adjustments

### If Agent Registration Fails (Step 4.3)

- [ ] Verify caller is hub owner
- [ ] Check oracle address is valid
- [ ] Verify updateType is registered on oracle
- [ ] Check allowedMarkets are authorized on oracle
- [ ] Retry registerAgent

### If RISK_ADMIN Grant Fails (Step 4.4)

- [ ] Verify caller has Pool Admin role
- [ ] Check FreezeAgent address is correct
- [ ] Retry addRiskAdmin

### Emergency: Disable Agent

If agent is misbehaving after deployment:

```solidity
// Option 1: Disable agent (reversible)
hub.setAgentEnabled(agentId, false)

// Option 2: Revoke RISK_ADMIN (prevents freeze execution)
aclManager.removeRiskAdmin(freezeAgentAddress)

// Option 3: Revoke WRITER_ROLE (prevents oracle updates)
oracle.revokeRole(WRITER_ROLE, proxyAddress)
```

### Emergency: Replace Oracle

If oracle needs replacement:

```solidity
// 1. Deploy new oracle
newOracle = new LlamaGuardOracle(...)

// 2. Update proxy to point to new oracle
proxy.setLlamaGuardOracle(newOracleAddress)

// 3. Update Chainlink proxy (requires Chainlink)
chainlinkProxy.proposeAggregator(newOracleAddress)
chainlinkProxy.confirmAggregator(newOracleAddress)

// 4. Update agent registration
hub.setAgentAddress(agentId, newAgentAddress)  // If agent also replaced
```

---

## Deployment Summary Template

After deployment, fill in this summary:

### Phase 2: Oracle Infrastructure

| Contract                      | Address | Deployer  | Tx Hash | Date |
| ----------------------------- | ------- | --------- | ------- | ---- |
| LlamaGuardOracle (ASSET)      |         | LlamaRisk |         |      |
| LlamaGuardOracleProxy (ASSET) |         | LlamaRisk |         |      |
| Chainlink Proxy (ASSET)       |         | Chainlink |         |      |
| ParameterRegistry             |         | Horizon   |         |      |

### Phase 3: Monitoring

| Metric                   | Value |
| ------------------------ | ----- |
| Monitoring start date    |       |
| Monitoring end date      |       |
| Total updates received   |       |
| False positives detected |       |
| Sign-off date            |       |

### Phase 4: Agent Infrastructure

| Contract           | Address | Deployer | Tx Hash | Date |
| ------------------ | ------- | -------- | ------- | ---- |
| HorizonAgentHub    |         | Horizon  |         |      |
| HorizonFreezeAgent |         | Horizon  |         |      |

| Configuration       | Contract          | Value        | Date |
| ------------------- | ----------------- | ------------ | ---- |
| WRITER_ROLE granted | LlamaGuardOracle  | proxy:       |      |
| Authorized markets  | LlamaGuardOracle  | [list]       |      |
| Registry updater    | ParameterRegistry |              |      |
| Agent registered    | HorizonAgentHub   | agentId:     |      |
| RISK_ADMIN granted  | ACLManager        | FreezeAgent: |      |

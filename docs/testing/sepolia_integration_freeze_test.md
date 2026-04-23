# Sepolia Integration Test: AgentHub Freeze Flow

End-to-end integration test of the HorizonAgentHub freeze pipeline on Sepolia. Validates the full flow: push an
out-of-bounds price to RawNAVOracle, CRE picks it up and writes a freeze update to LlamaGuardOracle, then the AgentHub
freezes the USTB reserve on the Horizon pool.

## Contract Addresses

| Contract                 | Address                                      |
| ------------------------ | -------------------------------------------- |
| LlamaGuardOracle (USTB)  | `0x54F2879D0a903B864782A40D67776aE53871B166` |
| LlamaGuardOracleProxy v2 | `0x860EeAEA09ff6A26F3F4C8681e79B200D9412382` |
| EACAggregatorProxy       | `0xa3180C43c5B52887008538942b9C6E1993535def` |
| RawNAVOracle             | `0xba88Da783C44DC01dBC828a2Cf7F9eB4C5E2A620` |
| HorizonAgentHub (proxy)  | `0x1DcDe45392E4fE8c1a9D60AaE5dd01057c234C68` |
| HorizonFreezeAgent       | `0xe16504396EdDb8822197540d3AF5E560b27E4e1e` |
| Horizon Pool             | `0xc16E5D2cA6c955213971B9641c1Eea7b104D561F` |
| Pool Configurator        | `0x452708660c6e9e5E69704992C0303274B84b407A` |
| PoolDataProvider         | `0xc83ba9e7b833DD295793619BB4365677173C7417` |
| ACL Manager              | `0x03E4fbd3Ae230A913d668e0C3f765d8Bc6Be303E` |
| USTB Token (Sepolia)     | `0x39727692cF58137Bd8c401eFE87Cc8A190D62ead` |
| Deployer                 | `0x9118964074e2AA11393ce0797264759dB2F2ef69` |
| RawNAVOracle Owner       | `0x4F0D905BD323FfC55bbaEf0B93dB3ef382c98AdD` |

## Architecture

```
RawNAVOracle Owner
  │
  │  updateLatestRoundData(veryLowPrice)
  ▼
RawNAVOracle (0xba88)
  │
  │  emits RoundDataUpdated event
  ▼
CRE Workflow (off-chain)
  │  detects out-of-bounds price
  │  sets freezeState = 1, clamps price to lowerBound
  ▼
LlamaGuardOracleProxy v2 (0x860E) ──► LlamaGuardOracle (0x54F2)
                                          │
                                          │  getLatestUpdateByParameterAndMarket("boundedNAV", USTB)
                                          ▼
                                     AgentHub (0x1DcD)
                                          │  check() → true
                                          │  execute()
                                          ▼
                                     FreezeAgent (0xe165)
                                          │  inject() → setReserveFreeze(USTB, true)
                                          ▼
                                     Pool Configurator (0x4527)
                                          │
                                          ▼
                                     Horizon Pool (0xc16E)
                                     USTB reserve frozen
```

---

## Pre-Test Checklist

Run these checks before starting the test. All must pass.

### Check 1 — `boundedNAV` is a registered updateType

```bash
cast call 0x54F2879D0a903B864782A40D67776aE53871B166 \
  "isValidUpdateType(string)(bool)" "boundedNAV" \
  --rpc-url sepolia
# Expected: true
```

### Check 2 — USTB is an authorized market on the oracle

```bash
cast call 0x54F2879D0a903B864782A40D67776aE53871B166 \
  "isAuthorizedMarket(address)(bool)" \
  0x39727692cF58137Bd8c401eFE87Cc8A190D62ead \
  --rpc-url sepolia
# Expected: true
```

### Check 3 — FreezeAgent has `RISK_ADMIN` on Horizon ACL Manager

```bash
cast call 0x03E4fbd3Ae230A913d668e0C3f765d8Bc6Be303E \
  "isRiskAdmin(address)(bool)" \
  0xe16504396EdDb8822197540d3AF5E560b27E4e1e \
  --rpc-url sepolia
# Expected: true
```

### Check 4 — FreezeAgent is registered in AgentHub

```bash
cast call 0x1DcDe45392E4fE8c1a9D60AaE5dd01057c234C68 \
  "getAgentCount()(uint256)" \
  --rpc-url sepolia
# Expected: >= 1
```

If `0` — the FreezeAgent needs to be registered first. See [Register FreezeAgent](#register-freezeagent-in-agenthub)
below.

### Check 5 — USTB reserve is NOT already frozen

```bash
cast call 0xc83ba9e7b833DD295793619BB4365677173C7417 \
  "getReserveConfigurationData(address)(uint256,uint256,uint256,uint256,uint256,bool,bool,bool,bool,bool)" \
  0x39727692cF58137Bd8c401eFE87Cc8A190D62ead \
  --rpc-url sepolia
# Last field (isFrozen) should be: false
```

### Check 6 — CRE workflow is active and listening

Confirm with Chainlink that the CRE workflow (`0x00a9cf308e...`) is running and subscribed to `RoundDataUpdated` events
on the RawNAVOracle (`0xba88`).

### Check 7 — Current oracle price and bounds

```bash
# RawNAVOracle latest price
cast call 0xba88Da783C44DC01dBC828a2Cf7F9eB4C5E2A620 \
  "latestRoundData()(uint80,int256,uint256,uint256,uint80)" \
  --rpc-url sepolia

# LlamaGuardOracle latest price
cast call 0x54F2879D0a903B864782A40D67776aE53871B166 \
  "latestRoundData()(uint80,int256,uint256,uint256,uint80)" \
  --rpc-url sepolia
# Both should show ~11.00 USD (11003521 at 6 decimals)
```

### Checklist Summary

| #   | Check                                  | Expected |
| --- | -------------------------------------- | -------- |
| 1   | `boundedNAV` is valid updateType       | `true`   |
| 2   | USTB is authorized market              | `true`   |
| 3   | FreezeAgent has `RISK_ADMIN`           | `true`   |
| 4   | FreezeAgent registered in AgentHub     | `>= 1`   |
| 5   | USTB reserve is not frozen             | `false`  |
| 6   | CRE workflow is active                 | confirm  |
| 7   | Oracle prices are in sync (~11.00 USD) | confirm  |

---

## Register FreezeAgent in AgentHub

> Skip this section if Check 4 passed (agent already registered).

**Sender:** Deployer (`0x9118...ef69`) — AgentHub owner

```solidity
struct AgentRegistrationInput {
    address admin;
    address riskOracle;
    bool    isAgentEnabled;
    bool    isAgentPermissioned;
    bool    isMarketsFromAgentEnabled;
    address agentAddress;
    uint256 expirationPeriod;
    uint256 minimumDelay;
    string  updateType;
    bytes   agentContext;
    address[] allowedMarkets;
    address[] restrictedMarkets;
    address[] permissionedSenders;
}
```

| Field                       | Value                                                                        |
| --------------------------- | ---------------------------------------------------------------------------- |
| `admin`                     | `0x9118964074e2AA11393ce0797264759dB2F2ef69` (deployer)                      |
| `riskOracle`                | `0x54F2879D0a903B864782A40D67776aE53871B166` (LlamaGuardOracle)              |
| `isAgentEnabled`            | `true`                                                                       |
| `isAgentPermissioned`       | `false`                                                                      |
| `isMarketsFromAgentEnabled` | `false` (markets specified explicitly)                                       |
| `agentAddress`              | `0xe16504396EdDb8822197540d3AF5E560b27E4e1e` (HorizonFreezeAgent)            |
| `expirationPeriod`          | `3600` (1 hour)                                                              |
| `minimumDelay`              | `0` (no cooldown)                                                            |
| `updateType`                | `"boundedNAV"`                                                               |
| `agentContext`              | `abi.encode(0x452708660c6e9e5E69704992C0303274B84b407A)` (Pool Configurator) |
| `allowedMarkets`            | `[0x39727692cF58137Bd8c401eFE87Cc8A190D62ead]` (USTB)                        |
| `restrictedMarkets`         | `[]`                                                                         |
| `permissionedSenders`       | `[]`                                                                         |

```bash
AGENT_CONTEXT=$(cast abi-encode "f(address)" 0x452708660c6e9e5E69704992C0303274B84b407A)

cast send 0x1DcDe45392E4fE8c1a9D60AaE5dd01057c234C68 \
  "registerAgent((address,address,bool,bool,bool,address,uint256,uint256,string,bytes,address[],address[],address[]))" \
  "(0x9118964074e2AA11393ce0797264759dB2F2ef69,0x54F2879D0a903B864782A40D67776aE53871B166,true,false,false,0xe16504396EdDb8822197540d3AF5E560b27E4e1e,3600,0,boundedNAV,$AGENT_CONTEXT,[0x39727692cF58137Bd8c401eFE87Cc8A190D62ead],[],[])" \
  --rpc-url sepolia \
  --private-key $PRIVATE_KEY
```

**Verify:**

```bash
cast call 0x1DcDe45392E4fE8c1a9D60AaE5dd01057c234C68 \
  "getAgentCount()(uint256)" --rpc-url sepolia
# Expected: 1

cast call 0x1DcDe45392E4fE8c1a9D60AaE5dd01057c234C68 \
  "isAgentEnabled(uint256)(bool)" 0 --rpc-url sepolia
# Expected: true

cast call 0x1DcDe45392E4fE8c1a9D60AaE5dd01057c234C68 \
  "getAgentAddress(uint256)(address)" 0 --rpc-url sepolia
# Expected: 0xe16504396EdDb8822197540d3AF5E560b27E4e1e
```

---

## Test Execution

### Step 1 — Push Out-of-Bounds Price to RawNAVOracle

Push a very low price to the RawNAVOracle. This simulates a catastrophic NAV drop that should trigger the CRE freeze
flow.

Current bounds (from latest `boundedNAV` update):

- Lower bound: ~10.986035 USD (`10986035`)
- Upper bound: ~11.015338 USD (`11015338`)
- Current price: ~11.003521 USD (`11003521`)

Push a price far below the lower bound (e.g. 1.000000 USD):

**Sender:** RawNAVOracle Owner (`0x4F0D905BD323FfC55bbaEf0B93dB3ef382c98AdD`)

```bash
cast send 0xba88Da783C44DC01dBC828a2Cf7F9eB4C5E2A620 \
  "updateLatestRoundData(int256)" \
  1000000 \
  --rpc-url sepolia \
  --private-key $RAW_NAV_OWNER_KEY
```

**Verify the price was written:**

```bash
cast call 0xba88Da783C44DC01dBC828a2Cf7F9eB4C5E2A620 \
  "latestRoundData()(uint80,int256,uint256,uint256,uint80)" \
  --rpc-url sepolia
# answer field should be 1000000
```

---

### Step 2 — Verify CRE Picked Up and Updated LlamaGuardOracle

Wait for the CRE workflow to detect the `RoundDataUpdated` event from the RawNAVOracle, determine the price is out of
bounds, and push an update to the LlamaGuardOracle via the proxy.

CRE should:

1. Clamp the price to the **lower bound** (~10.986035 USD)
2. Set `freezeState = 1` in `additionalData`

**Poll the oracle** (may take 30s–2min depending on CRE latency):

```bash
# Check LlamaGuardOracle latest price — should be clamped to lower bound
cast call 0x54F2879D0a903B864782A40D67776aE53871B166 \
  "latestRoundData()(uint80,int256,uint256,uint256,uint80)" \
  --rpc-url sepolia
# answer should be ~10986035 (lower bound), NOT 1000000

# Check the full update — freezeState should be 1
cast call 0x54F2879D0a903B864782A40D67776aE53871B166 \
  "getLatestUpdateByParameterAndMarket(string,address)((uint256,bytes,string,bytes,string,uint256,address,bytes))" \
  "boundedNAV" \
  0x39727692cF58137Bd8c401eFE87Cc8A190D62ead \
  --rpc-url sepolia
```

**Decode additionalData from the update:**

The last field of the returned tuple is
`additionalData = abi.encode(int256 lowerBound, int256 upperBound, uint256 freezeState)`.

```bash
# Decode additionalData (replace 0x... with the actual bytes from above)
cast abi-decode "f(int256,int256,uint256)" <additionalData_hex>
# Expected: lowerBound, upperBound, freezeState = 1
```

If `freezeState != 1`, the CRE did not flag the price as out-of-bounds. Verify:

- The RawNAVOracle price is actually below the current lower bound
- The CRE workflow is running and subscribed to the correct oracle

---

### Step 3 — Verify AgentHub `check()` Returns Actionable

Once CRE has written the freeze update, the AgentHub should detect it as actionable.

```bash
cast call 0x1DcDe45392E4fE8c1a9D60AaE5dd01057c234C68 \
  "check(uint256[])(bool,(uint256,address[])[])" \
  "[0]" \
  --rpc-url sepolia
```

**Expected:** `(true, [(0, [0x39727692cF58137Bd8c401eFE87Cc8A190D62ead])])`

If `false`:

- Update may have expired (>3600s since CRE wrote it) — act faster or increase `expirationPeriod`
- Reserve is already frozen
- `freezeState != 1` in the update

---

### Step 4 — Execute Freeze

Trigger the freeze by calling `execute()` on the AgentHub.

**Sender:** Any EOA (agent is not permissioned)

```bash
cast send 0x1DcDe45392E4fE8c1a9D60AaE5dd01057c234C68 \
  "execute((uint256,address[])[])" \
  "[(0,[0x39727692cF58137Bd8c401eFE87Cc8A190D62ead])]" \
  --rpc-url sepolia \
  --private-key $PRIVATE_KEY
```

This triggers:

```
AgentHub.execute()
  → re-validates update (expiry, cooldown, market)
  → HorizonFreezeAgent.inject()
    → _validateInternal(): freezeState == 1 AND reserve is not already frozen
    → _processUpdate(): PoolConfigurator.setReserveFreeze(USTB, true)
```

---

### Step 5 — Verify USTB Reserve is Frozen

```bash
cast call 0xc83ba9e7b833DD295793619BB4365677173C7417 \
  "getReserveConfigurationData(address)(uint256,uint256,uint256,uint256,uint256,bool,bool,bool,bool,bool)" \
  0x39727692cF58137Bd8c401eFE87Cc8A190D62ead \
  --rpc-url sepolia
```

**Expected output:**

```
6           # decimals
8250        # ltv
8600        # liquidationThreshold
10500       # liquidationBonus
1000        # reserveFactor
true        # usageAsCollateral
false       # borrowingEnabled
false       # stableBorrowRate
true        # isActive
true        # isFrozen  <── MUST BE true
```

---

### Step 6 — Verify Idempotency

Calling `check()` again should return `false` — the reserve is already frozen, so the FreezeAgent's
`_validateInternal()` rejects the action (idempotency guard).

```bash
cast call 0x1DcDe45392E4fE8c1a9D60AaE5dd01057c234C68 \
  "check(uint256[])(bool,(uint256,address[])[])" \
  "[0]" \
  --rpc-url sepolia
# Expected: (false, [])
```

Calling `execute()` again should revert with `NoActionCanBePerformed()`.

---

## Test Summary

```
Pre-Test:
  ✓ boundedNAV is registered updateType
  ✓ USTB is authorized market
  ✓ FreezeAgent has RISK_ADMIN
  ✓ FreezeAgent registered in AgentHub
  ✓ USTB reserve is NOT frozen
  ✓ CRE workflow is active
  ✓ Oracle prices in sync

Test:
  Step 1: Push very low price (1.000000) to RawNAVOracle
  Step 2: Verify CRE updated LlamaGuardOracle (price → lower bound, freezeState → 1)
  Step 3: check([0]) → true, USTB is actionable
  Step 4: execute([(0, [USTB])]) → freeze triggered
  Step 5: getReserveConfigurationData(USTB) → isFrozen = true
  Step 6: check([0]) → false (idempotent)
```

## Troubleshooting

| Symptom                                       | Likely Cause                                          | Fix                                            |
| --------------------------------------------- | ----------------------------------------------------- | ---------------------------------------------- |
| RawNAVOracle write reverts                    | Sender is not the owner                               | Use RawNAVOracle owner (`0x4F0D...3006ff`)     |
| CRE doesn't update oracle                     | CRE workflow not running or not subscribed            | Confirm with Chainlink that workflow is active |
| LlamaGuardOracle price didn't change          | CRE latency or proxy issue                            | Wait 2min; check proxy `WRITER_ROLE` on oracle |
| `freezeState` is `0` in oracle update         | Price was within bounds                               | Push a price further below `lowerBound`        |
| `check()` returns `false`                     | Update expired (>3600s old) or reserve already frozen | Act within expiration window; check pool state |
| `execute()` reverts `NoActionCanBePerformed`  | Same as above — revalidation fails                    | Run `check()` first to diagnose                |
| `execute()` reverts inside `setReserveFreeze` | FreezeAgent missing `RISK_ADMIN`                      | Grant via `addRiskAdmin()` on ACL Manager      |

## Post-Test: Unfreeze

After testing, the USTB reserve needs to be manually unfrozen. The FreezeAgent intentionally **cannot unfreeze**
(validation rejects `freezeState != 1`). Unfreezing requires a direct call to the Pool Configurator by an account with
`RISK_ADMIN` or `POOL_ADMIN` role:

```bash
cast send 0x452708660c6e9e5E69704992C0303274B84b407A \
  "setReserveFreeze(address,bool)" \
  0x39727692cF58137Bd8c401eFE87Cc8A190D62ead \
  false \
  --rpc-url sepolia \
  --private-key $RISK_ADMIN_KEY
```

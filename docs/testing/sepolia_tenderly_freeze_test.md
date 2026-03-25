# Sepolia Tenderly Fork Test: AgentHub Freeze Flow

End-to-end test of the HorizonAgentHub freeze pipeline on a Tenderly fork of Sepolia.
Validates that registering the FreezeAgent, writing freeze state to the oracle, and calling
`execute()` on the AgentHub successfully freezes the USTB reserve on the Horizon pool.

## Contract Addresses

| Contract                | Address                                      |
| ----------------------- | -------------------------------------------- |
| LlamaGuardOracle (USTB) | `0x54F2879D0a903B864782A40D67776aE53871B166` |
| HorizonAgentHub (proxy) | `0x1DcDe45392E4fE8c1a9D60AaE5dd01057c234C68` |
| HorizonFreezeAgent      | `0xe16504396EdDb8822197540d3AF5E560b27E4e1e` |
| Horizon Pool            | `0xc16E5D2cA6c955213971B9641c1Eea7b104D561F` |
| Pool Configurator       | `0x452708660c6e9e5E69704992C0303274B84b407A` |
| ACL Manager             | `0x03E4fbd3Ae230A913d668e0C3f765d8Bc6Be303E` |
| USTB Token (Sepolia)    | `0x39727692cF58137Bd8c401eFE87Cc8A190D62ead` |
| Deployer                | `0x9118964074e2AA11393ce0797264759dB2F2ef69` |

## Pre-Conditions (current Sepolia state)

| Check                                        | Status |
| -------------------------------------------- | ------ |
| Deployer has `DEFAULT_ADMIN_ROLE` on oracle   | Yes    |
| Deployer has `WRITER_ROLE` on oracle          | **No** (revoked) |
| `boundedNav` is valid updateType on oracle     | **No** (not added yet) |
| USTB is authorized market on oracle           | Yes    |
| Deployer is owner of AgentHub                 | Yes    |
| FreezeAgent has `RISK_ADMIN` on ACL Manager   | Yes    |
| AgentHub has registered agents                | **No** (count = 0) |
| USTB reserve is frozen on Pool                | No (active, not frozen) |

## Fork Setup

Create a Tenderly fork of Sepolia at the latest block. All transactions below use
`eth_sendTransaction` with Tenderly's state override / impersonation — no private key needed.

```
Network:   Sepolia (chain ID 11155111)
Fork from: latest block
```

---

## Step 1 — Add `boundedNav` Update Type on Oracle

The oracle only accepts writes for registered updateTypes. `boundedNav` hasn't been added yet.
This is the same updateType that CRE uses in production to push NAV + bounds + freeze state.

**Impersonate:** Deployer (`0x9118...ef69`) — has `DEFAULT_ADMIN_ROLE`

```bash
cast send 0x54F2879D0a903B864782A40D67776aE53871B166 \
  "addUpdateType(string,uint256)" \
  "boundedNav" \
  96 \
  --from 0x9118964074e2AA11393ce0797264759dB2F2ef69 \
  --unlocked \
  --rpc-url $TENDERLY_FORK_RPC
```

- `96` = expected `additionalData` length in bytes (`abi.encode(int256, int256, uint256)` = 3 x 32)

**Verify:**

```bash
cast call 0x54F2879D0a903B864782A40D67776aE53871B166 \
  "isValidUpdateType(string)(bool)" "boundedNav" \
  --rpc-url $TENDERLY_FORK_RPC
# Expected: true
```

---

## Step 2 — Grant `WRITER_ROLE` to Deployer on Oracle

The deployer's `WRITER_ROLE` was previously revoked. Re-grant it so we can write freeze data
directly (simulating what the proxy/CRE would do in production).

**Impersonate:** Deployer (`0x9118...ef69`) — has `DEFAULT_ADMIN_ROLE`

```bash
WRITER_ROLE=0x2b8f168f361ac1393a163ed4adfa899a87be7b7c71645167bdaddd822ae453c8

cast send 0x54F2879D0a903B864782A40D67776aE53871B166 \
  "grantRole(bytes32,address)" \
  $WRITER_ROLE \
  0x9118964074e2AA11393ce0797264759dB2F2ef69 \
  --from 0x9118964074e2AA11393ce0797264759dB2F2ef69 \
  --unlocked \
  --rpc-url $TENDERLY_FORK_RPC
```

**Verify:**

```bash
cast call 0x54F2879D0a903B864782A40D67776aE53871B166 \
  "hasRole(bytes32,address)(bool)" \
  $WRITER_ROLE \
  0x9118964074e2AA11393ce0797264759dB2F2ef69 \
  --rpc-url $TENDERLY_FORK_RPC
# Expected: true
```

---

## Step 3 — Register FreezeAgent in AgentHub

**Impersonate:** Deployer (`0x9118...ef69`) — AgentHub owner

The `registerAgent` function takes an `AgentRegistrationInput` struct:

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

Values for this test:

| Field                      | Value |
| -------------------------- | ----- |
| `admin`                    | `0x9118964074e2AA11393ce0797264759dB2F2ef69` (deployer) |
| `riskOracle`               | `0x54F2879D0a903B864782A40D67776aE53871B166` (LlamaGuardOracle) |
| `isAgentEnabled`           | `true` |
| `isAgentPermissioned`      | `false` (anyone can call execute) |
| `isMarketsFromAgentEnabled`| `false` (we specify markets explicitly) |
| `agentAddress`             | `0xe16504396EdDb8822197540d3AF5E560b27E4e1e` (HorizonFreezeAgent) |
| `expirationPeriod`         | `3600` (1 hour — generous for testing) |
| `minimumDelay`             | `0` (no cooldown) |
| `updateType`               | `"boundedNav"` |
| `agentContext`             | `abi.encode(0x452708660c6e9e5E69704992C0303274B84b407A)` (Pool Configurator) |
| `allowedMarkets`           | `[0x39727692cF58137Bd8c401eFE87Cc8A190D62ead]` (USTB) |
| `restrictedMarkets`        | `[]` |
| `permissionedSenders`      | `[]` |

```bash
# Encode agentContext (Pool Configurator address)
AGENT_CONTEXT=$(cast abi-encode "f(address)" 0x452708660c6e9e5E69704992C0303274B84b407A)

cast send 0x1DcDe45392E4fE8c1a9D60AaE5dd01057c234C68 \
  "registerAgent((address,address,bool,bool,bool,address,uint256,uint256,string,bytes,address[],address[],address[]))" \
  "(0x9118964074e2AA11393ce0797264759dB2F2ef69,0x54F2879D0a903B864782A40D67776aE53871B166,true,false,false,0xe16504396EdDb8822197540d3AF5E560b27E4e1e,3600,0,boundedNav,$AGENT_CONTEXT,[0x39727692cF58137Bd8c401eFE87Cc8A190D62ead],[],[])" \
  --from 0x9118964074e2AA11393ce0797264759dB2F2ef69 \
  --unlocked \
  --rpc-url $TENDERLY_FORK_RPC
```

The returned agentId should be `0` (first registered agent).

**Verify:**

```bash
# Agent count should be 1
cast call 0x1DcDe45392E4fE8c1a9D60AaE5dd01057c234C68 \
  "getAgentCount()(uint256)" \
  --rpc-url $TENDERLY_FORK_RPC
# Expected: 1

# Agent 0 should be enabled
cast call 0x1DcDe45392E4fE8c1a9D60AaE5dd01057c234C68 \
  "isAgentEnabled(uint256)(bool)" 0 \
  --rpc-url $TENDERLY_FORK_RPC
# Expected: true

# Agent 0 address should be FreezeAgent
cast call 0x1DcDe45392E4fE8c1a9D60AaE5dd01057c234C68 \
  "getAgentAddress(uint256)(address)" 0 \
  --rpc-url $TENDERLY_FORK_RPC
# Expected: 0xe16504396EdDb8822197540d3AF5E560b27E4e1e
```

---

## Step 4 — Write Freeze State to LlamaGuardOracle

Simulate what the CRE proxy would do: write a `boundedNav` update with `freezeState = 1` in additionalData.

**Impersonate:** Deployer (`0x9118...ef69`) — now has `WRITER_ROLE` (from Step 2)

```bash
# Encode newValue (price in 6 decimals — e.g. 10.994190 USD)
NEW_VALUE=$(cast abi-encode "f(int256)" 10994190)

# Encode additionalData: (lowerBound, upperBound, freezeState)
# lowerBound: 10.000000 (10000000), upperBound: 12.000000 (12000000), freezeState: 1
ADDITIONAL_DATA=$(cast abi-encode "f(int256,int256,uint256)" 10000000 12000000 1)

# Deadline: current block timestamp + 1 hour
DEADLINE=$(echo "$(cast block latest --field timestamp --rpc-url $TENDERLY_FORK_RPC) + 3600" | bc)

cast send 0x54F2879D0a903B864782A40D67776aE53871B166 \
  "updateLatestRiskRoundData((string,bytes,string,bytes,uint256))" \
  "(test-freeze-001,$NEW_VALUE,boundedNav,$ADDITIONAL_DATA,$DEADLINE)" \
  --from 0x9118964074e2AA11393ce0797264759dB2F2ef69 \
  --unlocked \
  --rpc-url $TENDERLY_FORK_RPC
```

**Verify:**

```bash
# Check latest round data has the new price
cast call 0x54F2879D0a903B864782A40D67776aE53871B166 \
  "latestRoundData()(uint80,int256,uint256,uint256,uint80)" \
  --rpc-url $TENDERLY_FORK_RPC

# Check the oracle returns the freeze update for USTB
cast call 0x54F2879D0a903B864782A40D67776aE53871B166 \
  "getLatestUpdateByParameterAndMarket(string,address)((uint256,bytes,string,bytes,string,uint256,address,bytes))" \
  "boundedNav" \
  0x39727692cF58137Bd8c401eFE87Cc8A190D62ead \
  --rpc-url $TENDERLY_FORK_RPC
```

---

## Step 5 — Verify `check()` Returns Actionable

Call `check` with agentId `0` to confirm the hub sees the freeze update as actionable.

```bash
cast call 0x1DcDe45392E4fE8c1a9D60AaE5dd01057c234C68 \
  "check(uint256[])(bool,(uint256,address[])[])" \
  "[0]" \
  --rpc-url $TENDERLY_FORK_RPC
```

**Expected:** `(true, [(0, [0x39727692cF58137Bd8c401eFE87Cc8A190D62ead])])`

If `false` — check:
- Is the update expired? (`expirationPeriod` is 3600s from registration)
- Is the reserve already frozen? (should not be)
- Did `validate` pass? (freezeState must be `1` and reserve must be unfrozen)

---

## Step 6 — Execute Freeze

Trigger the actual freeze by calling `execute()` on the AgentHub.

```bash
cast send 0x1DcDe45392E4fE8c1a9D60AaE5dd01057c234C68 \
  "execute((uint256,address[])[])" \
  "[(0,[0x39727692cF58137Bd8c401eFE87Cc8A190D62ead])]" \
  --from 0x9118964074e2AA11393ce0797264759dB2F2ef69 \
  --unlocked \
  --rpc-url $TENDERLY_FORK_RPC
```

This triggers the chain:
```
AgentHub.execute()
  -> validates update (expiry, cooldown, market)
  -> HorizonFreezeAgent.inject()
     -> _validateInternal() confirms freezeState==1 and reserve is unfrozen
     -> _processUpdate() calls PoolConfigurator.setReserveFreeze(USTB, true)
```

---

## Step 7 — Verify USTB Reserve is Frozen

```bash
# Decode reserve config — frozen bit is bit 57
CONFIG=$(cast call 0xc16E5D2cA6c955213971B9641c1Eea7b104D561F \
  "getConfiguration(address)((uint256))" \
  0x39727692cF58137Bd8c401eFE87Cc8A190D62ead \
  --rpc-url $TENDERLY_FORK_RPC)

echo "Raw config: $CONFIG"

python3 -c "
config = int('$CONFIG'.strip().strip('()').strip(), 0) if '0x' in '$CONFIG' else int('$CONFIG'.strip().split()[0].strip('()'))
frozen = (config >> 57) & 1
print(f'USTB Reserve Frozen: {\"YES\" if frozen else \"NO\"}')
"
# Expected: USTB Reserve Frozen: YES
```

---

## Step 8 — Verify Idempotency (Optional)

Calling `check()` again should return `false` — the reserve is already frozen, so the
FreezeAgent's `validate()` rejects the action.

```bash
cast call 0x1DcDe45392E4fE8c1a9D60AaE5dd01057c234C68 \
  "check(uint256[])(bool,(uint256,address[])[])" \
  "[0]" \
  --rpc-url $TENDERLY_FORK_RPC
# Expected: (false, [])
```

Calling `execute()` again should revert with `NoActionCanBePerformed()`.

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
| ------- | ------------ | --- |
| `addUpdateType` reverts | Deployer lost `DEFAULT_ADMIN_ROLE` | Check `hasRole(0x00, deployer)` |
| `updateLatestRiskRoundData` reverts | Missing `WRITER_ROLE` or wrong `additionalData` length | Verify Step 2; ensure `additionalData` is exactly 96 bytes |
| `check()` returns `false` | Update expired, already injected, or reserve already frozen | Check `expirationPeriod`, `lastInjectedUpdate`, pool frozen state |
| `execute()` reverts with `NoActionCanBePerformed` | Same as above — revalidation fails | Run `check()` first to diagnose |
| `execute()` reverts inside `setReserveFreeze` | FreezeAgent missing `RISK_ADMIN` on ACL Manager | Grant via `addRiskAdmin()` on ACL Manager (need pool admin impersonation) |
| Price deviation revert on `updateLatestRiskRoundData` | New price too far from last round | Use a price within `maxPriceDeviation` bps of the last answer, or set deviation to 0 |

## Summary

```
Step 1: addUpdateType("boundedNav", 96)         — oracle admin setup
Step 2: grantRole(WRITER_ROLE, deployer)           — oracle write access
Step 3: registerAgent(...)                          — hub registration
Step 4: updateLatestRiskRoundData(boundedNav=1)  — simulate CRE writing freeze
Step 5: check([0])                                  — verify actionable (should be true)
Step 6: execute([(0, [USTB])])                      — trigger freeze
Step 7: getConfiguration(USTB)                      — confirm frozen bit = 1
Step 8: check([0]) again                            — confirm idempotent (should be false)
```

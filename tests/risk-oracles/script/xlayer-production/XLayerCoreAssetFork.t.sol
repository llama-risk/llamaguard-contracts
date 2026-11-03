// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";
import { AaveV3XLayer } from "aave-address-book/AaveV3XLayer.sol";
import {
    XLayerCoreExternalAddresses
} from "../../../../script/risk-oracles/xlayer/production/XLayerCoreExternalAddresses.sol";
import { PTUSDG25FEB2027 } from "../../../../script/risk-oracles/xlayer/production/assets/PTUSDG25FEB2027.sol";

interface IPendlePrincipalToken {
    function expiry() external view returns (uint256);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

interface IPendleMarket {
    function readTokens() external view returns (address sy, address pt, address yt);
    function expiry() external view returns (uint256);
}

interface IPendlePtOracle {
    function getPtToAssetRate(address market, uint32 duration) external view returns (uint256);
}

interface ITypeAndVersion {
    function typeAndVersion() external view returns (string memory);
}

/// @notice Re-reads every X Layer literal the config cannot check on its own against live chain
///         196: the PT, its Pendle market, the CRE forwarder and the Aave principals.
/// @dev    Same two preconditions as `EthereumCoreForkTest`, both of which skip rather than fail
///         when unmet: the `fork` profile and an RPC, here `XLAYER_RPC_URL`.
///
///           FOUNDRY_PROFILE=fork XLAYER_RPC_URL=https://rpc.xlayer.tech \
///             forge test --match-path "tests/risk-oracles/script/xlayer-production/*"
contract XLayerCoreAssetForkTest is Test {
    /// @notice The block these tests fork from.
    /// @dev    Pinned rather than latest, so the same commit does not pass and fail on different
    ///         days. The trade is that the state read here is frozen.
    uint256 internal constant FORK_BLOCK = 73_326_000;

    /// @notice Pendle's PT oracle on X Layer; prices `PENDLE_MARKET`. Not a dependency of any
    ///         script here, only of the workflows, so it lives in the test.
    address internal constant PENDLE_PT_ORACLE = 0x5542be50420E88dd7D5B4a3D488FA6ED82F6DAc2;

    /// @notice TWAP window the PT oracle is read over.
    uint32 internal constant PT_ORACLE_TWAP_SECONDS = 900;

    /// @notice True when both preconditions hold and the assertions here mean something.
    bool internal forked;

    function setUp() public {
        if (!_isForkProfile()) return;

        string memory rpc = vm.envOr("XLAYER_RPC_URL", string(""));
        if (bytes(rpc).length == 0) return;

        vm.createSelectFork(rpc, FORK_BLOCK);
        forked = true;
    }

    function test_theForkIsXLayer() public {
        _skipUnlessForked();
        assertEq(block.chainid, XLayerCoreExternalAddresses.XLAYER_CHAIN_ID, "not chain 196");
    }

    // ============================================================================================
    // The asset
    // ============================================================================================

    function test_thePtIsTheOneTheAssetFileDescribes() public {
        _skipUnlessForked();

        IPendlePrincipalToken pt = IPendlePrincipalToken(PTUSDG25FEB2027.PT_ASSET);
        assertEq(pt.expiry(), PTUSDG25FEB2027.PT_MATURITY, "PT expiry is not PT_MATURITY");
        assertEq(pt.symbol(), "PT-USDG-25FEB2027", "PT symbol");
        assertEq(pt.decimals(), 6, "PT decimals");
    }

    function test_theMarketTradesThisPt() public {
        _skipUnlessForked();

        IPendleMarket market = IPendleMarket(PTUSDG25FEB2027.PENDLE_MARKET);
        (, address pt,) = market.readTokens();
        assertEq(pt, PTUSDG25FEB2027.PT_ASSET, "market PT is not PT_ASSET");
        assertEq(market.expiry(), PTUSDG25FEB2027.PT_MATURITY, "market expiry is not PT_MATURITY");
    }

    /// @dev A PT trades at or under par before maturity, so anything outside (0, 1e18] means the
    ///      oracle is reading another market or is not initialised for this one.
    function test_thePendleOraclePricesTheMarket() public {
        _skipUnlessForked();

        uint256 rate =
            IPendlePtOracle(PENDLE_PT_ORACLE).getPtToAssetRate(PTUSDG25FEB2027.PENDLE_MARKET, PT_ORACLE_TWAP_SECONDS);
        assertGt(rate, 0, "PT oracle returned zero");
        assertLe(rate, 1e18, "PT oracle rate is above par");
    }

    // ============================================================================================
    // External addresses
    // ============================================================================================

    function test_theCreForwarderIsAKeystoneForwarder() public {
        _skipUnlessForked();

        address forwarder = XLayerCoreExternalAddresses.CRE_FORWARDER;
        assertGt(forwarder.code.length, 0, "CRE_FORWARDER has no code on X Layer");
        assertEq(ITypeAndVersion(forwarder).typeAndVersion(), "KeystoneForwarder 1.0.0", "CRE_FORWARDER version");
    }

    function test_theExecutorIsTheAclAdmin() public {
        _skipUnlessForked();

        assertEq(XLayerCoreExternalAddresses.AAVE_EXECUTOR, AaveV3XLayer.ACL_ADMIN, "Executor is not the ACL admin");
        assertGt(XLayerCoreExternalAddresses.AAVE_EXECUTOR.code.length, 0, "AAVE_EXECUTOR has no code");
    }

    function test_theProtocolGuardianIsDeployed() public {
        _skipUnlessForked();
        assertGt(XLayerCoreExternalAddresses.AAVE_PROTOCOL_GUARDIAN.code.length, 0, "guardian has no code");
    }

    function test_theAclManagerIsDeployed() public {
        _skipUnlessForked();
        assertGt(XLayerCoreExternalAddresses.AAVE_ACL_MANAGER.code.length, 0, "ACL manager has no code");
    }

    function _skipUnlessForked() internal {
        if (!forked) {
            vm.skip(true);
        }
    }

    function _isForkProfile() private view returns (bool) {
        string memory profile = vm.envOr("FOUNDRY_PROFILE", string(""));
        return keccak256(bytes(profile)) == keccak256(bytes("fork"));
    }
}

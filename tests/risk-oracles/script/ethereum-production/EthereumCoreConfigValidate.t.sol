// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";
import { EthereumCoreConfig } from "../../../../script/risk-oracles/ethereum/production/EthereumCoreConfig.sol";
import {
    EthereumCoreExternalAddresses
} from "../../../../script/risk-oracles/ethereum/production/EthereumCoreExternalAddresses.sol";

/// @notice Exercises `EthereumCoreConfig.validate`, the guard every production script calls before
///         it deploys anything.
/// @dev    No fork and no RPC. `validate` reads `block.chainid` and compares constants, so `vm.chainId`
///         is enough to drive both of its reachable branches, and these run under the default profile
///         alongside the rest of the suite.
///
///         The two branches covered are the two that can actually fail: the chain guard, which is
///         what stops a mainnet-shaped config being deployed somewhere else, and the broadcaster
///         check, which is what stops it being broadcast by a key that cannot then complete the
///         handovers. The remaining `require`s compare compile-time constants against zero and
///         cannot be driven from a test without editing the config itself; they are a guard against
///         a future edit landing an unset constant, not a runtime condition.
contract EthereumCoreConfigValidateTest is Test {
    /// @dev `validate` is `internal`, so it is reached through this wrapper rather than directly.
    function validate(address broadcaster) external view {
        EthereumCoreConfig.validate(broadcaster);
    }

    function setUp() public {
        vm.chainId(EthereumCoreExternalAddresses.ETHEREUM_CHAIN_ID);
    }

    // ============================================================================================
    // The chain guard
    // ============================================================================================

    function test_passesOnMainnetWithTheConfiguredDeployer() public view {
        this.validate(EthereumCoreConfig.DEPLOYER);
    }

    /// @dev The whole config is a set of mainnet addresses. Anywhere else they are meaningless, so
    ///      this must fail before the first contract is created.
    function test_revertsOffMainnet() public {
        vm.chainId(11_155_111); // Sepolia
        vm.expectRevert(bytes("EthereumCoreConfig: not on Ethereum mainnet"));
        this.validate(EthereumCoreConfig.DEPLOYER);
    }

    /// @dev A fork of mainnet keeps chain id 1, so the guard is on the id rather than on the RPC.
    function test_revertsOnAnyNonMainnetChainId() public {
        uint256[3] memory foreignChains = [uint256(10), uint256(8453), uint256(42_161)];
        for (uint256 i = 0; i < foreignChains.length; i++) {
            vm.chainId(foreignChains[i]);
            vm.expectRevert(bytes("EthereumCoreConfig: not on Ethereum mainnet"));
            this.validate(EthereumCoreConfig.DEPLOYER);
        }
    }

    // ============================================================================================
    // The broadcaster guard
    // ============================================================================================

    /// @dev The RiskOracle hardcodes `msg.sender` as owner and the Router is constructed owned by the
    ///      deployer, so a broadcast from the wrong key produces a stack that key cannot hand over.
    ///      Failing here is the difference between a refused run and an orphaned deployment.
    function test_revertsWhenBroadcasterIsNotTheDeployer() public {
        vm.expectRevert(bytes("EthereumCoreConfig: broadcaster is not DEPLOYER"));
        this.validate(address(0xBAD));
    }

    /// @dev The LlamaRisk safe is the eventual owner of the stack, but it is not the account that
    ///      broadcasts phase 1, so it is rejected here like any other non-deployer.
    function test_revertsWhenBroadcasterIsTheSafe() public {
        vm.expectRevert(bytes("EthereumCoreConfig: broadcaster is not DEPLOYER"));
        this.validate(EthereumCoreConfig.LLAMARISK_SAFE);
    }

    /// @dev Zero is the documented opt out, for a script that only reads and broadcasts nothing. The
    ///      chain guard still applies to it.
    function test_zeroBroadcasterSkipsTheDeployerCheck() public view {
        this.validate(address(0));
    }

    function test_zeroBroadcasterIsStillChainGuarded() public {
        vm.chainId(11_155_111);
        vm.expectRevert(bytes("EthereumCoreConfig: not on Ethereum mainnet"));
        this.validate(address(0));
    }
}

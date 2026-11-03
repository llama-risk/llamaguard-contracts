// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { AvalancheParameterRegistry } from "../../../src/AvalancheParameterRegistry.sol";
import {
    AvalancheParameterRegistryConfig,
    ISafeOwners
} from "../../../script/parameter-registry/avalanche/AvalancheParameterRegistryConfig.sol";
import {
    DeployAvalancheParameterRegistry
} from "../../../script/parameter-registry/avalanche/DeployAvalancheParameterRegistry.s.sol";

/// @notice Runs the deploy on an Avalanche fork and checks the roles.
/// @dev    The tests skip when `AVALANCHE_RPC_URL` is not set. The fork uses `FORK_BLOCK`, so the
///         RPC must be an archive node.
contract DeployAvalancheParameterRegistryTest is Test {
    uint256 internal constant FORK_BLOCK = 96_472_000;

    DeployAvalancheParameterRegistry internal script;
    bool internal forked;

    function setUp() public {
        string memory rpc = vm.envOr("AVALANCHE_RPC_URL", string(""));
        if (bytes(rpc).length == 0) return;

        vm.createSelectFork(rpc, FORK_BLOCK);
        forked = true;
        script = new DeployAvalancheParameterRegistry();
    }

    modifier onlyForked() {
        if (!forked) vm.skip(true);
        _;
    }

    function test_validatePassesAgainstLiveState() public onlyForked {
        this.validate();
    }

    function test_validateRejectsAnotherChain() public onlyForked {
        vm.chainId(1);
        vm.expectRevert("AvalancheParameterRegistryConfig: not on Avalanche C-Chain");
        this.validate();
    }

    function test_validateRejectsAChangedThreshold() public onlyForked {
        vm.mockCall(
            AvalancheParameterRegistryConfig.REGISTRY_UPDATER,
            abi.encodeWithSelector(ISafeOwners.getThreshold.selector),
            abi.encode(uint256(1))
        );
        vm.expectRevert("AvalancheParameterRegistryConfig: updater threshold changed");
        this.validate();
    }

    function test_validateRejectsAnExtraSigner() public onlyForked {
        address[] memory owners = new address[](3);
        owners[0] = AvalancheParameterRegistryConfig.LLAMARISK_SIGNER;
        owners[1] = AvalancheParameterRegistryConfig.COSIGNER;
        owners[2] = address(0xBEEF);
        vm.mockCall(
            AvalancheParameterRegistryConfig.REGISTRY_UPDATER,
            abi.encodeWithSelector(ISafeOwners.getOwners.selector),
            abi.encode(owners)
        );
        vm.expectRevert("AvalancheParameterRegistryConfig: updater signer count changed");
        this.validate();
    }

    function test_deploySetsTheFinalRoles() public onlyForked {
        AvalancheParameterRegistry registry = script.deploy();

        assertEq(registry.owner(), AvalancheParameterRegistryConfig.REGISTRY_OWNER, "owner");
        assertEq(registry.pendingOwner(), address(0), "pending owner");
        assertEq(registry.updater(), AvalancheParameterRegistryConfig.REGISTRY_UPDATER, "updater");
    }

    function test_onlyTheDiscountLimitDiffersFromTheBase() public onlyForked {
        AvalancheParameterRegistry registry = script.deploy();

        assertEq(registry.MAX_DISCOUNT_LIMIT(), 1000, "discount limit");
        assertEq(registry.MAX_LOWER_BOUND_TOLERANCE(), 250, "lower bound tolerance limit");
        assertEq(registry.MAX_UPPER_BOUND_TOLERANCE(), 250, "upper bound tolerance limit");
        assertEq(registry.MAX_EXPECTED_APY_LIMIT(), 20_000, "expected APY limit");
    }

    function test_theUpdaterCanSetADiscountOfUpTo1000Bps() public onlyForked {
        AvalancheParameterRegistry registry = script.deploy();

        vm.startPrank(AvalancheParameterRegistryConfig.REGISTRY_UPDATER);
        registry.setParametersForAsset(address(1), "X", address(2), 100, 10, 10, 1000, 4, true, true, false);
        (,,, uint32 maxDiscount,,,,) = registry.getParametersForAsset(address(1));
        assertEq(maxDiscount, 1000, "maxDiscount");

        vm.expectRevert(abi.encodeWithSelector(AvalancheParameterRegistry.MaxDiscountTooHigh.selector, 1001));
        registry.setParametersForAsset(address(1), "X", address(2), 100, 10, 10, 1001, 4, true, true, false);

        registry.setMaxDiscount(address(1), 999);
        vm.expectRevert(abi.encodeWithSelector(AvalancheParameterRegistry.MaxDiscountTooHigh.selector, 1001));
        registry.setMaxDiscount(address(1), 1001);
        vm.stopPrank();
    }

    function test_onlyTheUpdaterCanWrite() public onlyForked {
        AvalancheParameterRegistry registry = script.deploy();

        vm.expectRevert(AvalancheParameterRegistry.OnlyUpdater.selector);
        registry.setParametersForAsset(address(1), "X", address(2), 100, 10, 10, 10, 4, true, true, false);

        vm.prank(AvalancheParameterRegistryConfig.REGISTRY_UPDATER);
        registry.setParametersForAsset(address(1), "X", address(2), 100, 10, 10, 10, 4, true, true, false);
        assertTrue(registry.assetExists(address(1)), "asset not set");
    }

    function test_onlyTheOwnerCanRotateTheUpdater() public onlyForked {
        AvalancheParameterRegistry registry = script.deploy();

        vm.prank(AvalancheParameterRegistryConfig.REGISTRY_UPDATER);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector, AvalancheParameterRegistryConfig.REGISTRY_UPDATER
            )
        );
        registry.setUpdater(address(3));

        vm.prank(AvalancheParameterRegistryConfig.REGISTRY_OWNER);
        registry.setUpdater(address(3));
        assertEq(registry.updater(), address(3), "updater not rotated");
    }

    /// @dev External, so that `vm.expectRevert` can catch a revert from the library.
    function validate() external view {
        AvalancheParameterRegistryConfig.validate();
    }
}

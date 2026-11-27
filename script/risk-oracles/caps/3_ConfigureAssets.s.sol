// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { console2 } from "forge-std/console2.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IPool } from "aave-v3-origin/src/contracts/interfaces/IPool.sol";
import { DataTypes } from "aave-v3-origin/src/contracts/protocol/libraries/types/DataTypes.sol";
import {
    ReserveConfiguration
} from "aave-v3-origin/src/contracts/protocol/libraries/configuration/ReserveConfiguration.sol";
import { CapsParameterRegistry } from "../../../src/caps-oracle/CapsParameterRegistry.sol";
import { ICapsParameterRegistry } from "../../../src/caps-oracle/interfaces/ICapsParameterRegistry.sol";
import { ICapsRangeValidationModule as IRvm } from "../../../src/caps-oracle/interfaces/ICapsRangeValidationModule.sol";
import { CapsConfig } from "./CapsConfig.sol";
import { CapsDeployment } from "./CapsDeployment.sol";
import { CapsScript } from "./CapsScript.sol";

/// @title ConfigureAssets
/// @notice Step 3: the first values of every borrow cap key, from the asset values file. Per asset, the RVM entry
///         first and then the registry key: a registry key without an RVM entry makes the workflow alert
///         `entryNotFound`. Later changes go through llamaguard-ci with the same fields.
/// @dev Coverage is checked against the live reserve list before anything is sent: every borrowable reserve must
///      be in `reserves` or `skip`, and every configured asset must be a reserve of the Pool. A reserve is
///      borrowable when it is active, borrowing is on, it is neither frozen nor paused, and its borrow cap is not 1.
contract ConfigureAssets is CapsScript {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    /// @dev The cap Aave uses to stop new borrows on a reserve.
    uint256 internal constant FROZEN_BORROW_CAP = 1;

    function run() external {
        (, CapsConfig.Config memory config, CapsDeployment.Deployment memory deployment) = _context();
        configureAssets(config, deployment, broadcaster);
    }

    function configureAssets(
        CapsConfig.Config memory config,
        CapsDeployment.Deployment memory deployment,
        address sender
    )
        public
    {
        require(deployment.raiseAgentId != deployment.cutAgentId, "ConfigureAssets: run step 2 first");
        IPool pool = IPool(_stackPool(config.market, deployment));
        checkCoverage(pool, config.assets);

        address rvmOwner = Ownable(deployment.rvm).owner();
        address registryUpdater = CapsParameterRegistry(deployment.registry).updater();
        ICapsParameterRegistry.ReserveOverride memory inherit;

        _begin(sender);
        for (uint256 i; i < config.assets.reserves.length; ++i) {
            CapsConfig.Reserve memory r = config.assets.reserves[i];
            IRvm.RateLimitConfig memory entry = IRvm.RateLimitConfig({
                maxCap: r.currentCap ? uint64(pool.getConfiguration(r.asset).getBorrowCap()) : r.maxCap,
                maxHeadroom: r.maxHeadroom,
                alphaBps: r.alphaBps,
                cutBandBps: r.cutBandBps
            });
            _call(
                string.concat("RVM: ", r.symbol),
                rvmOwner,
                deployment.rvm,
                abi.encodeCall(IRvm.setRateLimitConfig, (r.asset, IRvm.CapKind.BORROW, entry))
            );
            _call(
                string.concat("Registry: ", r.symbol),
                registryUpdater,
                deployment.registry,
                abi.encodeCall(
                    ICapsParameterRegistry.addReserve, (address(pool), r.asset, uint8(IRvm.CapKind.BORROW), inherit)
                )
            );
            console2.log(r.symbol, "maxCap", entry.maxCap);
        }
        _end("Step 3: asset values");
    }

    /// @notice Reverts unless the asset values file covers exactly the Pool's borrowable reserves.
    function checkCoverage(IPool pool, CapsConfig.Assets memory assets) public view {
        address[] memory listed = pool.getReservesList();
        for (uint256 i; i < listed.length; ++i) {
            if (_borrowable(pool, listed[i]) && !_covered(assets, listed[i])) {
                revert(
                    string.concat(
                        "ConfigureAssets: borrowable reserve not in the asset values file: ", vm.toString(listed[i])
                    )
                );
            }
        }
        for (uint256 i; i < assets.reserves.length; ++i) {
            if (!_contains(listed, assets.reserves[i].asset)) {
                revert(string.concat("ConfigureAssets: not a reserve of the Pool: ", assets.reserves[i].symbol));
            }
        }
    }

    /// @dev Borrowable globally, or through an eMode: an eMode user is checked against the category's borrowable
    ///      bitmap only, not the reserve's borrowing flag.
    function _borrowable(IPool pool, address asset) private view returns (bool) {
        DataTypes.ReserveConfigurationMap memory c = pool.getConfiguration(asset);
        if (!c.getActive() || c.getFrozen() || c.getPaused() || c.getBorrowCap() == FROZEN_BORROW_CAP) return false;
        if (c.getBorrowingEnabled()) return true;
        uint256 id = pool.getReserveData(asset).id;
        for (uint256 category = 1; category <= type(uint8).max; ++category) {
            if ((pool.getEModeCategoryBorrowableBitmap(uint8(category)) >> id) & 1 == 1) return true;
        }
        return false;
    }

    function _covered(CapsConfig.Assets memory assets, address asset) private pure returns (bool) {
        for (uint256 i; i < assets.reserves.length; ++i) {
            if (assets.reserves[i].asset == asset) return true;
        }
        return _contains(assets.skip, asset);
    }

    function _contains(address[] memory list, address item) private pure returns (bool) {
        for (uint256 i; i < list.length; ++i) {
            if (list[i] == item) return true;
        }
        return false;
    }
}

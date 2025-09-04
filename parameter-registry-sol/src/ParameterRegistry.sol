// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ParameterRegistry
 * @dev Multi-asset parameter registry for offchain oracle network consumption
 */
contract ParameterRegistry is Ownable {
    struct AssetParameters {
        uint256 maxExpectedApy;
        uint256 upperBoundTolerance;
        uint256 lowerBoundTolerance;
        bool isUpperBoundEnabled;
        bool isLowerBoundEnabled;
        bool isActionTakingEnabled;
    }

    struct AssetInfo {
        string name;
        bool exists;
    }

    address public updater;
    mapping(address _assetAddress => AssetParameters _assetParameters) private assetParameters;
    mapping(address _assetAddress => AssetInfo _assetInfo) private assetInfos;

    event UpdaterChanged(address indexed previousUpdater, address indexed newUpdater);
    event AssetParametersSet(
        address indexed asset,
        uint256 maxExpectedApy,
        uint256 upperBoundTolerance,
        uint256 lowerBoundTolerance,
        bool isUpperBoundEnabled,
        bool isLowerBoundEnabled,
        bool isActionTakingEnabled
    );
    event AssetDeleted(address indexed asset);
    event AssetNameSet(address indexed asset, string name);

    error OnlyUpdater();
    error AssetNotFound();
    error ZeroAddress();

    modifier onlyUpdater() {
        if (msg.sender != updater) revert OnlyUpdater();
        _;
    }

    constructor(address _owner, address _updater) Ownable(_owner) {
        if (_updater == address(0)) revert ZeroAddress();
        updater = _updater;
        emit UpdaterChanged(address(0), _updater);
    }

    function setUpdater(address _updater) external onlyOwner {
        if (_updater == address(0)) revert ZeroAddress();
        address previousUpdater = updater;
        updater = _updater;
        emit UpdaterChanged(previousUpdater, _updater);
    }

    function setParametersForAsset(
        address asset,
        string calldata assetName,
        uint256 maxExpectedApy,
        uint256 upperBoundTolerance,
        uint256 lowerBoundTolerance,
        bool isUpperBoundEnabled,
        bool isLowerBoundEnabled,
        bool isActionTakingEnabled
    )
        external
        onlyUpdater
    {
        if (asset == address(0)) revert ZeroAddress();

        assetParameters[asset] = AssetParameters({
            maxExpectedApy: maxExpectedApy,
            upperBoundTolerance: upperBoundTolerance,
            lowerBoundTolerance: lowerBoundTolerance,
            isUpperBoundEnabled: isUpperBoundEnabled,
            isLowerBoundEnabled: isLowerBoundEnabled,
            isActionTakingEnabled: isActionTakingEnabled
        });

        assetInfos[asset] = AssetInfo({ name: assetName, exists: true });

        emit AssetNameSet(asset, assetName);
        emit AssetParametersSet(
            asset,
            maxExpectedApy,
            upperBoundTolerance,
            lowerBoundTolerance,
            isUpperBoundEnabled,
            isLowerBoundEnabled,
            isActionTakingEnabled
        );
    }

    function setMaxExpectedApy(address asset, uint256 _maxExpectedApy) external onlyUpdater {
        if (!assetInfos[asset].exists) revert AssetNotFound();
        AssetParameters storage params = assetParameters[asset];
        params.maxExpectedApy = _maxExpectedApy;

        emit AssetParametersSet(
            asset,
            params.maxExpectedApy,
            params.upperBoundTolerance,
            params.lowerBoundTolerance,
            params.isUpperBoundEnabled,
            params.isLowerBoundEnabled,
            params.isActionTakingEnabled
        );
    }

    function setUpperBoundTolerance(address asset, uint256 _upperBoundTolerance) external onlyUpdater {
        if (!assetInfos[asset].exists) revert AssetNotFound();
        AssetParameters storage params = assetParameters[asset];
        params.upperBoundTolerance = _upperBoundTolerance;

        emit AssetParametersSet(
            asset,
            params.maxExpectedApy,
            params.upperBoundTolerance,
            params.lowerBoundTolerance,
            params.isUpperBoundEnabled,
            params.isLowerBoundEnabled,
            params.isActionTakingEnabled
        );
    }

    function setLowerBoundTolerance(address asset, uint256 _lowerBoundTolerance) external onlyUpdater {
        if (!assetInfos[asset].exists) revert AssetNotFound();
        AssetParameters storage params = assetParameters[asset];
        params.lowerBoundTolerance = _lowerBoundTolerance;

        emit AssetParametersSet(
            asset,
            params.maxExpectedApy,
            params.upperBoundTolerance,
            params.lowerBoundTolerance,
            params.isUpperBoundEnabled,
            params.isLowerBoundEnabled,
            params.isActionTakingEnabled
        );
    }

    function setIsUpperBoundEnabled(address asset, bool _isUpperBoundEnabled) external onlyUpdater {
        if (!assetInfos[asset].exists) revert AssetNotFound();
        AssetParameters storage params = assetParameters[asset];
        params.isUpperBoundEnabled = _isUpperBoundEnabled;

        emit AssetParametersSet(
            asset,
            params.maxExpectedApy,
            params.upperBoundTolerance,
            params.lowerBoundTolerance,
            params.isUpperBoundEnabled,
            params.isLowerBoundEnabled,
            params.isActionTakingEnabled
        );
    }

    function setIsLowerBoundEnabled(address asset, bool _isLowerBoundEnabled) external onlyUpdater {
        if (!assetInfos[asset].exists) revert AssetNotFound();
        AssetParameters storage params = assetParameters[asset];
        params.isLowerBoundEnabled = _isLowerBoundEnabled;

        emit AssetParametersSet(
            asset,
            params.maxExpectedApy,
            params.upperBoundTolerance,
            params.lowerBoundTolerance,
            params.isUpperBoundEnabled,
            params.isLowerBoundEnabled,
            params.isActionTakingEnabled
        );
    }

    function setIsActionTakingEnabled(address asset, bool _isActionTakingEnabled) external onlyUpdater {
        if (!assetInfos[asset].exists) revert AssetNotFound();
        AssetParameters storage params = assetParameters[asset];
        params.isActionTakingEnabled = _isActionTakingEnabled;

        emit AssetParametersSet(
            asset,
            params.maxExpectedApy,
            params.upperBoundTolerance,
            params.lowerBoundTolerance,
            params.isUpperBoundEnabled,
            params.isLowerBoundEnabled,
            params.isActionTakingEnabled
        );
    }

    function deleteAsset(address asset) external onlyUpdater {
        if (!assetInfos[asset].exists) revert AssetNotFound();

        delete assetParameters[asset];
        delete assetInfos[asset];

        emit AssetDeleted(asset);
    }

    function getParametersForAsset(address asset)
        external
        view
        returns (
            uint256 maxExpectedApy,
            uint256 upperBoundTolerance,
            uint256 lowerBoundTolerance,
            bool isUpperBoundEnabled,
            bool isLowerBoundEnabled,
            bool isActionTakingEnabled
        )
    {
        if (!assetInfos[asset].exists) revert AssetNotFound();
        AssetParameters memory params = assetParameters[asset];

        return (
            params.maxExpectedApy,
            params.upperBoundTolerance,
            params.lowerBoundTolerance,
            params.isUpperBoundEnabled,
            params.isLowerBoundEnabled,
            params.isActionTakingEnabled
        );
    }

    function getAssetName(address asset) external view returns (string memory) {
        if (!assetInfos[asset].exists) revert AssetNotFound();
        return assetInfos[asset].name;
    }

    function assetExists(address asset) external view returns (bool) {
        return assetInfos[asset].exists;
    }
}

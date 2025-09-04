// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IAggregatorV3 } from "./interfaces/IAggregatorV3.sol";

/**
 * @title ParameterRegistry
 * @dev Multi-asset parameter registry for offchain oracle network consumption
 */
contract ParameterRegistry is Ownable {
    struct AssetParameters {
        uint256 maxExpectedApy;
        uint256 upperBoundTolerance;
        uint256 lowerBoundTolerance;
        uint256 window;
        bool isUpperBoundEnabled;
        bool isLowerBoundEnabled;
        bool isActionTakingEnabled;
    }

    struct AssetInfo {
        string name;
        address oracle;
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
        uint256 window,
        bool isUpperBoundEnabled,
        bool isLowerBoundEnabled,
        bool isActionTakingEnabled
    );
    event AssetDeleted(address indexed asset);
    event AssetNameSet(address indexed asset, string name);
    event AssetOracleSet(address indexed asset, address oracle);

    error OnlyUpdater();
    error AssetNotFound();
    error ZeroAddress();

    modifier onlyUpdater() {
        if (msg.sender != updater) revert OnlyUpdater();
        _;
    }

    constructor(address _owner, address _updater) Ownable(_owner) {
        if (_updater == address(0)) revert ZeroAddress();
        emit UpdaterChanged(address(0), updater = _updater);
    }

    function setUpdater(address _updater) external onlyOwner {
        if (_updater == address(0)) revert ZeroAddress();
        address previousUpdater = updater;
        emit UpdaterChanged(previousUpdater, updater = _updater);
    }

    function setParametersForAsset(
        address asset,
        string calldata assetName,
        address oracle,
        uint256 maxExpectedApy,
        uint256 upperBoundTolerance,
        uint256 lowerBoundTolerance,
        uint256 window,
        bool isUpperBoundEnabled,
        bool isLowerBoundEnabled,
        bool isActionTakingEnabled
    )
        external
        onlyUpdater
    {
        if (asset == address(0)) revert ZeroAddress();
        if (oracle == address(0)) revert ZeroAddress();

        assetParameters[asset] = AssetParameters({
            maxExpectedApy: maxExpectedApy,
            upperBoundTolerance: upperBoundTolerance,
            lowerBoundTolerance: lowerBoundTolerance,
            window: window,
            isUpperBoundEnabled: isUpperBoundEnabled,
            isLowerBoundEnabled: isLowerBoundEnabled,
            isActionTakingEnabled: isActionTakingEnabled
        });

        assetInfos[asset] = AssetInfo({ name: assetName, oracle: oracle, exists: true });

        emit AssetNameSet(asset, assetName);
        emit AssetOracleSet(asset, oracle);
        emit AssetParametersSet(
            asset,
            maxExpectedApy,
            upperBoundTolerance,
            lowerBoundTolerance,
            window,
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
            params.window,
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
            params.window,
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
            params.window,
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
            params.window,
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
            params.window,
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
            params.window,
            params.isUpperBoundEnabled,
            params.isLowerBoundEnabled,
            params.isActionTakingEnabled
        );
    }

    function setWindow(address asset, uint256 _window) external onlyUpdater {
        if (!assetInfos[asset].exists) revert AssetNotFound();
        AssetParameters storage params = assetParameters[asset];
        params.window = _window;

        emit AssetParametersSet(
            asset,
            params.maxExpectedApy,
            params.upperBoundTolerance,
            params.lowerBoundTolerance,
            params.window,
            params.isUpperBoundEnabled,
            params.isLowerBoundEnabled,
            params.isActionTakingEnabled
        );
    }

    function setOracle(address asset, address _oracle) external onlyUpdater {
        if (!assetInfos[asset].exists) revert AssetNotFound();
        if (_oracle == address(0)) revert ZeroAddress();
        AssetInfo storage info = assetInfos[asset];
        info.oracle = _oracle;

        emit AssetOracleSet(asset, _oracle);
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
            uint256 window,
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
            params.window,
            params.isUpperBoundEnabled,
            params.isLowerBoundEnabled,
            params.isActionTakingEnabled
        );
    }

    function getAssetName(address asset) external view returns (string memory) {
        if (!assetInfos[asset].exists) revert AssetNotFound();
        return assetInfos[asset].name;
    }

    function getAssetOracle(address asset) external view returns (address) {
        if (!assetInfos[asset].exists) revert AssetNotFound();
        return assetInfos[asset].oracle;
    }

    function assetExists(address asset) external view returns (bool) {
        return assetInfos[asset].exists;
    }

    function getRoundDatas(address asset)
        external
        view
        returns (int256[] memory answers, uint256[] memory timestamps)
    {
        if (!assetInfos[asset].exists) revert AssetNotFound();

        AssetInfo memory info = assetInfos[asset];
        if (info.oracle == address(0)) revert ZeroAddress();

        uint256 window = assetParameters[asset].window;

        // Calculate how many rounds to fetch
        answers = new int256[](window + 1);
        timestamps = new uint256[](window + 1);

        IAggregatorV3 oracle = IAggregatorV3(info.oracle);

        // Get latest round data in a single call
        {
            (uint80 roundId, int256 answer,, uint256 updatedAt,) = oracle.latestRoundData();
            answers[0] = answer;
            timestamps[0] = updatedAt;

            // Fetch historical rounds
            uint256 actualSize = 1; // Start with 1 for the latest round
            for (uint256 i = 1; i <= window; i++) {
                // Check if we can fetch this round
                if (roundId <= i) {
                    // We've reached the earliest available round
                    break;
                }

                uint80 targetId = roundId - uint80(i);

                // low-level call to avoid stack issues with try-catch
                (bool success, bytes memory data) =
                    info.oracle.staticcall(abi.encodeWithSelector(IAggregatorV3.getRoundData.selector, targetId));

                if (success && data.length >= 160) {
                    // Decode the response
                    (, int256 historicalAnswer,, uint256 historicalTimestamp,) =
                        abi.decode(data, (uint80, int256, uint256, uint256, uint80));
                    answers[i] = historicalAnswer;
                    timestamps[i] = historicalTimestamp;
                    actualSize = i + 1;
                } else {
                    // Can't get more data
                    break;
                }
            }

            // Resize arrays to actual size if needed
            if (actualSize < window + 1) {
                assembly {
                    mstore(answers, actualSize)
                    mstore(timestamps, actualSize)
                }
            }
        }

        return (answers, timestamps);
    }
}

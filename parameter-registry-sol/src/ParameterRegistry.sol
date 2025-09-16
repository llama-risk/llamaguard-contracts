// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";

interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    function getRoundData(uint80 _roundId)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/**
 * @title ParameterRegistry
 * @dev Multi-asset parameter registry for offchain oracle network consumption
 */
contract ParameterRegistry is Ownable2Step {
    uint256 public constant MAX_EXPECTED_APY_LIMIT = 20_000; // Max 200% (20000 BPS)
    uint256 public constant MAX_UPPER_BOUND_TOLERANCE = 250; // Max 2.5% (250 BPS)
    uint256 public constant MAX_LOWER_BOUND_TOLERANCE = 250; // Max 2.5% (250 BPS)
    uint256 public constant MAX_DISCOUNT_LIMIT = 250; // Max 2.5% (250 BPS)

    struct AssetParameters {
        uint256 maxExpectedApy; // BPS format (basis points, e.g., 500 = 5%)
        uint256 upperBoundTolerance; // BPS format (basis points, e.g., 100 = 1%)
        uint256 lowerBoundTolerance; // BPS format (basis points, e.g., 50 = 0.5%)
        uint256 maxDiscount; // BPS format (basis points, e.g., 2000 = 20%)
        uint80 lookbackWindowSize;
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
        uint256 maxDiscount,
        uint80 lookbackWindowSize,
        bool isUpperBoundEnabled,
        bool isLowerBoundEnabled,
        bool isActionTakingEnabled
    );
    event AssetDeleted(address indexed asset);
    event AssetNameSet(address indexed asset, string name);
    event AssetOracleSet(address indexed asset, address oracle);
    event LookbackWindowSizeSet(address indexed asset, uint80 lookbackWindowSize);

    error OnlyUpdater();
    error AssetNotFound();
    error ZeroAddress();
    error OracleNotSet();
    error InvalidLookbackWindow();
    error MaxExpectedApyTooHigh(uint256 value);
    error UpperBoundToleranceTooHigh(uint256 value);
    error LowerBoundToleranceTooHigh(uint256 value);
    error MaxDiscountTooHigh(uint256 value);

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
        uint256 maxDiscount,
        uint80 lookbackWindowSize,
        bool isUpperBoundEnabled,
        bool isLowerBoundEnabled,
        bool isActionTakingEnabled
    )
        external
        onlyUpdater
    {
        if (asset == address(0)) revert ZeroAddress();
        if (oracle == address(0)) revert ZeroAddress();
        if (maxExpectedApy > MAX_EXPECTED_APY_LIMIT) revert MaxExpectedApyTooHigh(maxExpectedApy);
        if (upperBoundTolerance > MAX_UPPER_BOUND_TOLERANCE) revert UpperBoundToleranceTooHigh(upperBoundTolerance);
        if (lowerBoundTolerance > MAX_LOWER_BOUND_TOLERANCE) revert LowerBoundToleranceTooHigh(lowerBoundTolerance);
        if (maxDiscount > MAX_DISCOUNT_LIMIT) revert MaxDiscountTooHigh(maxDiscount);

        assetParameters[asset] = AssetParameters({
            maxExpectedApy: maxExpectedApy,
            upperBoundTolerance: upperBoundTolerance,
            lowerBoundTolerance: lowerBoundTolerance,
            maxDiscount: maxDiscount,
            lookbackWindowSize: lookbackWindowSize,
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
            maxDiscount,
            lookbackWindowSize,
            isUpperBoundEnabled,
            isLowerBoundEnabled,
            isActionTakingEnabled
        );
    }

    function setMaxExpectedApy(address asset, uint256 _maxExpectedApy) external onlyUpdater {
        if (!assetInfos[asset].exists) revert AssetNotFound();
        if (_maxExpectedApy > MAX_EXPECTED_APY_LIMIT) revert MaxExpectedApyTooHigh(_maxExpectedApy);
        AssetParameters storage params = assetParameters[asset];
        params.maxExpectedApy = _maxExpectedApy;

        emit AssetParametersSet(
            asset,
            params.maxExpectedApy,
            params.upperBoundTolerance,
            params.lowerBoundTolerance,
            params.maxDiscount,
            params.lookbackWindowSize,
            params.isUpperBoundEnabled,
            params.isLowerBoundEnabled,
            params.isActionTakingEnabled
        );
    }

    function setUpperBoundTolerance(address asset, uint256 _upperBoundTolerance) external onlyUpdater {
        if (!assetInfos[asset].exists) revert AssetNotFound();
        if (_upperBoundTolerance > MAX_UPPER_BOUND_TOLERANCE) revert UpperBoundToleranceTooHigh(_upperBoundTolerance);
        AssetParameters storage params = assetParameters[asset];
        params.upperBoundTolerance = _upperBoundTolerance;

        emit AssetParametersSet(
            asset,
            params.maxExpectedApy,
            params.upperBoundTolerance,
            params.lowerBoundTolerance,
            params.maxDiscount,
            params.lookbackWindowSize,
            params.isUpperBoundEnabled,
            params.isLowerBoundEnabled,
            params.isActionTakingEnabled
        );
    }

    function setLowerBoundTolerance(address asset, uint256 _lowerBoundTolerance) external onlyUpdater {
        if (!assetInfos[asset].exists) revert AssetNotFound();
        if (_lowerBoundTolerance > MAX_LOWER_BOUND_TOLERANCE) revert LowerBoundToleranceTooHigh(_lowerBoundTolerance);
        AssetParameters storage params = assetParameters[asset];
        params.lowerBoundTolerance = _lowerBoundTolerance;

        emit AssetParametersSet(
            asset,
            params.maxExpectedApy,
            params.upperBoundTolerance,
            params.lowerBoundTolerance,
            params.maxDiscount,
            params.lookbackWindowSize,
            params.isUpperBoundEnabled,
            params.isLowerBoundEnabled,
            params.isActionTakingEnabled
        );
    }

    function setMaxDiscount(address asset, uint256 _maxDiscount) external onlyUpdater {
        if (!assetInfos[asset].exists) revert AssetNotFound();
        if (_maxDiscount > MAX_DISCOUNT_LIMIT) revert MaxDiscountTooHigh(_maxDiscount);
        AssetParameters storage params = assetParameters[asset];
        params.maxDiscount = _maxDiscount;

        emit AssetParametersSet(
            asset,
            params.maxExpectedApy,
            params.upperBoundTolerance,
            params.lowerBoundTolerance,
            params.maxDiscount,
            params.lookbackWindowSize,
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
            params.maxDiscount,
            params.lookbackWindowSize,
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
            params.maxDiscount,
            params.lookbackWindowSize,
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
            params.maxDiscount,
            params.lookbackWindowSize,
            params.isUpperBoundEnabled,
            params.isLowerBoundEnabled,
            params.isActionTakingEnabled
        );
    }

    function setLookbackWindowSize(address asset, uint80 _lookbackWindowSize) external onlyUpdater {
        if (!assetInfos[asset].exists) revert AssetNotFound();
        AssetParameters storage params = assetParameters[asset];
        params.lookbackWindowSize = _lookbackWindowSize;

        emit LookbackWindowSizeSet(asset, _lookbackWindowSize);
        emit AssetParametersSet(
            asset,
            params.maxExpectedApy,
            params.upperBoundTolerance,
            params.lowerBoundTolerance,
            params.maxDiscount,
            params.lookbackWindowSize,
            params.isUpperBoundEnabled,
            params.isLowerBoundEnabled,
            params.isActionTakingEnabled
        );
    }

    function setOracle(address asset, address oracle) external onlyUpdater {
        if (!assetInfos[asset].exists) revert AssetNotFound();
        if (oracle == address(0)) revert ZeroAddress();
        assetInfos[asset].oracle = oracle;
        emit AssetOracleSet(asset, oracle);
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
            uint256 maxDiscount,
            uint80 lookbackWindowSize,
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
            params.maxDiscount,
            params.lookbackWindowSize,
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

    function getOracle(address asset) external view returns (address) {
        if (!assetInfos[asset].exists) revert AssetNotFound();
        return assetInfos[asset].oracle;
    }

    function getLookbackData(address asset)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        if (!assetInfos[asset].exists) revert AssetNotFound();

        address oracle = assetInfos[asset].oracle;
        if (oracle == address(0)) revert OracleNotSet();

        uint80 lookbackWindowSize = assetParameters[asset].lookbackWindowSize;
        if (lookbackWindowSize == 0) revert InvalidLookbackWindow();

        AggregatorV3Interface aggregator = AggregatorV3Interface(oracle);

        // Get the latest round data
        (uint80 latestRoundId,,,,) = aggregator.latestRoundData();

        // Calculate the lookback round ID
        uint80 lookbackSubstration;
        if (latestRoundId <= lookbackWindowSize) {
            lookbackSubstration = latestRoundId - 1;
        } else {
            lookbackSubstration = lookbackWindowSize;
        }
        uint80 lookbackRoundId = latestRoundId - lookbackSubstration;

        // Get and return the lookback round data
        return aggregator.getRoundData(lookbackRoundId);
    }
}

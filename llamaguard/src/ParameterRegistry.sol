// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.26;

import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

interface OracleProxyInterface {
    function aggregator() external view returns (address);
}

/**
 * @title ParameterRegistry
 * @dev Multi-asset parameter registry for offchain oracle network consumption
 */
contract ParameterRegistry is Ownable2Step {
    uint64 public constant MAX_EXPECTED_APY_LIMIT = 20_000; // Max 200% (20000 BPS)
    uint32 public constant MAX_UPPER_BOUND_TOLERANCE = 250; // Max 2.5% (250 BPS)
    uint32 public constant MAX_LOWER_BOUND_TOLERANCE = 250; // Max 2.5% (250 BPS)
    uint32 public constant MAX_DISCOUNT_LIMIT = 250; // Max 2.5% (250 BPS)

    struct AssetConfig {
        string name;
        address oracle; // 20 bytes
        bool exists; // 1 byte
        uint80 lookbackWindowSize; // 10 bytes (up to 1.2M blocks)
        uint64 maxExpectedApy; // 8 bytes (BPS format, max ~1.84 * 10^15%)
        uint32 lowerBoundTolerance; // 4 bytes (BPS format, max ~42949672 = 429496.72%)
        uint32 upperBoundTolerance; // 4 bytes (BPS format, max ~42949672 = 429496.72%)
        uint32 maxDiscount; // 4 bytes (BPS format, max ~42949672 = 429496.72%)
        bool isUpperBoundEnabled; // 1 byte
        bool isLowerBoundEnabled; // 1 byte
        bool isActionTakingEnabled; // 1 byte
    }

    address public updater;
    mapping(address _assetAddress => AssetConfig _assetConfig) private assetConfigs;

    event UpdaterChanged(address indexed previousUpdater, address indexed newUpdater);
    event AssetParametersSet(
        address indexed asset,
        uint64 maxExpectedApy,
        uint32 upperBoundTolerance,
        uint32 lowerBoundTolerance,
        uint32 maxDiscount,
        uint80 lookbackWindowSize,
        bool isUpperBoundEnabled,
        bool isLowerBoundEnabled,
        bool isActionTakingEnabled
    );
    event AssetDeleted(address indexed asset);
    event AssetNameSet(address indexed asset, string name);
    event AssetOracleSet(address indexed asset, address oracle);
    event LookbackWindowSizeSet(address indexed asset, uint80 lookbackWindowSize);
    event MaxExpectedApySet(address indexed asset, uint64 maxExpectedApy);
    event UpperBoundToleranceSet(address indexed asset, uint32 upperBoundTolerance);
    event LowerBoundToleranceSet(address indexed asset, uint32 lowerBoundTolerance);
    event MaxDiscountSet(address indexed asset, uint32 maxDiscount);
    event IsUpperBoundEnabledSet(address indexed asset, bool isUpperBoundEnabled);
    event IsLowerBoundEnabledSet(address indexed asset, bool isLowerBoundEnabled);
    event IsActionTakingEnabledSet(address indexed asset, bool isActionTakingEnabled);

    error OnlyUpdater();
    error AssetNotFound();
    error ZeroAddress();
    error OracleNotSet();
    error InvalidLookbackWindow();
    error MaxExpectedApyTooHigh(uint64 value);
    error UpperBoundToleranceTooHigh(uint32 value);
    error LowerBoundToleranceTooHigh(uint32 value);
    error MaxDiscountTooHigh(uint32 value);

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
        uint64 maxExpectedApy,
        uint32 upperBoundTolerance,
        uint32 lowerBoundTolerance,
        uint32 maxDiscount,
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
        if (lookbackWindowSize == 0) revert InvalidLookbackWindow();

        assetConfigs[asset] = AssetConfig({
            name: assetName,
            oracle: oracle,
            exists: true,
            lookbackWindowSize: lookbackWindowSize,
            maxExpectedApy: maxExpectedApy,
            lowerBoundTolerance: lowerBoundTolerance,
            upperBoundTolerance: upperBoundTolerance,
            maxDiscount: maxDiscount,
            isUpperBoundEnabled: isUpperBoundEnabled,
            isLowerBoundEnabled: isLowerBoundEnabled,
            isActionTakingEnabled: isActionTakingEnabled
        });

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

    function setMaxExpectedApy(address asset, uint64 _maxExpectedApy) external onlyUpdater {
        if (!assetConfigs[asset].exists) revert AssetNotFound();
        if (_maxExpectedApy > MAX_EXPECTED_APY_LIMIT) revert MaxExpectedApyTooHigh(_maxExpectedApy);
        assetConfigs[asset].maxExpectedApy = _maxExpectedApy;
        emit MaxExpectedApySet(asset, _maxExpectedApy);
    }

    function setUpperBoundTolerance(address asset, uint32 _upperBoundTolerance) external onlyUpdater {
        if (!assetConfigs[asset].exists) revert AssetNotFound();
        if (_upperBoundTolerance > MAX_UPPER_BOUND_TOLERANCE) revert UpperBoundToleranceTooHigh(_upperBoundTolerance);
        assetConfigs[asset].upperBoundTolerance = _upperBoundTolerance;
        emit UpperBoundToleranceSet(asset, _upperBoundTolerance);
    }

    function setLowerBoundTolerance(address asset, uint32 _lowerBoundTolerance) external onlyUpdater {
        if (!assetConfigs[asset].exists) revert AssetNotFound();
        if (_lowerBoundTolerance > MAX_LOWER_BOUND_TOLERANCE) revert LowerBoundToleranceTooHigh(_lowerBoundTolerance);
        assetConfigs[asset].lowerBoundTolerance = _lowerBoundTolerance;
        emit LowerBoundToleranceSet(asset, _lowerBoundTolerance);
    }

    function setMaxDiscount(address asset, uint32 _maxDiscount) external onlyUpdater {
        if (!assetConfigs[asset].exists) revert AssetNotFound();
        if (_maxDiscount > MAX_DISCOUNT_LIMIT) revert MaxDiscountTooHigh(_maxDiscount);
        assetConfigs[asset].maxDiscount = _maxDiscount;
        emit MaxDiscountSet(asset, _maxDiscount);
    }

    function setIsUpperBoundEnabled(address asset, bool _isUpperBoundEnabled) external onlyUpdater {
        if (!assetConfigs[asset].exists) revert AssetNotFound();
        assetConfigs[asset].isUpperBoundEnabled = _isUpperBoundEnabled;
        emit IsUpperBoundEnabledSet(asset, _isUpperBoundEnabled);
    }

    function setIsLowerBoundEnabled(address asset, bool _isLowerBoundEnabled) external onlyUpdater {
        if (!assetConfigs[asset].exists) revert AssetNotFound();
        assetConfigs[asset].isLowerBoundEnabled = _isLowerBoundEnabled;
        emit IsLowerBoundEnabledSet(asset, _isLowerBoundEnabled);
    }

    function setIsActionTakingEnabled(address asset, bool _isActionTakingEnabled) external onlyUpdater {
        if (!assetConfigs[asset].exists) revert AssetNotFound();
        assetConfigs[asset].isActionTakingEnabled = _isActionTakingEnabled;
        emit IsActionTakingEnabledSet(asset, _isActionTakingEnabled);
    }

    function setLookbackWindowSize(address asset, uint80 _lookbackWindowSize) external onlyUpdater {
        if (!assetConfigs[asset].exists) revert AssetNotFound();
        if (_lookbackWindowSize == 0) revert InvalidLookbackWindow();
        assetConfigs[asset].lookbackWindowSize = _lookbackWindowSize;
        emit LookbackWindowSizeSet(asset, _lookbackWindowSize);
    }

    function setOracle(address asset, address oracle) external onlyUpdater {
        if (!assetConfigs[asset].exists) revert AssetNotFound();
        if (oracle == address(0)) revert ZeroAddress();
        assetConfigs[asset].oracle = oracle;
        emit AssetOracleSet(asset, oracle);
    }

    function deleteAsset(address asset) external onlyUpdater {
        if (!assetConfigs[asset].exists) revert AssetNotFound();

        delete assetConfigs[asset];

        emit AssetDeleted(asset);
    }

    function getParametersForAsset(address asset)
        external
        view
        returns (
            uint64 maxExpectedApy,
            uint32 upperBoundTolerance,
            uint32 lowerBoundTolerance,
            uint32 maxDiscount,
            uint80 lookbackWindowSize,
            bool isUpperBoundEnabled,
            bool isLowerBoundEnabled,
            bool isActionTakingEnabled
        )
    {
        if (!assetConfigs[asset].exists) revert AssetNotFound();
        AssetConfig memory config = assetConfigs[asset];

        return (
            config.maxExpectedApy,
            config.upperBoundTolerance,
            config.lowerBoundTolerance,
            config.maxDiscount,
            config.lookbackWindowSize,
            config.isUpperBoundEnabled,
            config.isLowerBoundEnabled,
            config.isActionTakingEnabled
        );
    }

    function getAssetName(address asset) external view returns (string memory) {
        if (!assetConfigs[asset].exists) revert AssetNotFound();
        return assetConfigs[asset].name;
    }

    function assetExists(address asset) external view returns (bool) {
        return assetConfigs[asset].exists;
    }

    function getOracle(address asset) external view returns (address) {
        if (!assetConfigs[asset].exists) revert AssetNotFound();
        return assetConfigs[asset].oracle;
    }

    function getLookbackData(address asset)
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        if (!assetConfigs[asset].exists) revert AssetNotFound();
        if (assetConfigs[asset].oracle == address(0)) revert OracleNotSet();

        address aggregatorAddress;
        address oracleProxy = assetConfigs[asset].oracle;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x245a7bfc00000000000000000000000000000000000000000000000000000000) // aggregator() selector
            let success := staticcall(gas(), oracleProxy, ptr, 4, ptr, 32)
            if iszero(success) { revert(0, 0) }
            aggregatorAddress := mload(ptr)
        }

        AggregatorV3Interface aggregator = AggregatorV3Interface(aggregatorAddress);

        // Get the latest round data
        (uint80 latestRoundId,,,,) = aggregator.latestRoundData();

        uint80 lookbackRoundId = latestRoundId <= assetConfigs[asset].lookbackWindowSize
            ? (latestRoundId == 0 ? 0 : 1)
            : latestRoundId - assetConfigs[asset].lookbackWindowSize;

        return aggregator.getRoundData(lookbackRoundId);
    }
}

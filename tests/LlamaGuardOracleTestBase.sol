// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { LlamaGuardOracle } from "../src/LlamaGuardOracle.sol";
import { ILlamaGuardOracle } from "../src/interfaces/ILlamaGuardOracle.sol";

/// @title LlamaGuardOracleTestBase
/// @notice Shared base contract for LlamaGuardOracle tests
abstract contract LlamaGuardOracleTestBase is Test {
    LlamaGuardOracle internal oracle;

    address internal admin = makeAddr("admin");
    address internal writer = makeAddr("writer");
    address internal nonWriter = makeAddr("nonWriter");
    address internal defaultMarket = makeAddr("defaultMarket");

    string[] internal defaultUpdateTypes;

    // Update type string constants
    string internal constant PRICE_TYPE = "price";
    string internal constant SUPPLY_TYPE = "supply";
    string internal constant RISK_STATE_TYPE = "risk_state";
    string internal constant BOUNDED_NAV_TYPE = "boundedNAV";

    // Hashes computed from string constants (set in setUp)
    bytes32 internal priceHash;
    bytes32 internal supplyHash;
    bytes32 internal riskStateHash;
    bytes32 internal boundedNavHash;

    event ParameterUpdated(
        string referenceId,
        bytes newValue,
        bytes previousValue,
        uint256 timestamp,
        string indexed updateType,
        uint256 indexed updateId,
        bytes additionalData
    );

    event UpdateTypeAdded(string indexed updateType, uint256 expectedAdditionalDataLength);

    // V2 AggregatorInterface events
    event AnswerUpdated(int256 indexed current, uint256 indexed roundId, uint256 updatedAt);
    event NewRound(uint256 indexed roundId, address indexed startedBy, uint256 startedAt);

    function setUp() public virtual {
        // Compute hashes from string constants
        priceHash = keccak256(bytes(PRICE_TYPE));
        supplyHash = keccak256(bytes(SUPPLY_TYPE));
        riskStateHash = keccak256(bytes(RISK_STATE_TYPE));
        boundedNavHash = keccak256(bytes(BOUNDED_NAV_TYPE));

        // Setup default update types
        defaultUpdateTypes = new string[](4);
        defaultUpdateTypes[0] = PRICE_TYPE;
        defaultUpdateTypes[1] = SUPPLY_TYPE;
        defaultUpdateTypes[2] = RISK_STATE_TYPE;
        defaultUpdateTypes[3] = BOUNDED_NAV_TYPE;

        // Create initial authorized markets array with defaultMarket
        address[] memory initialMarkets = new address[](1);
        initialMarkets[0] = defaultMarket;
        oracle = new LlamaGuardOracle(8, "Test Feed", 1, defaultUpdateTypes, initialMarkets);
    }

    /// @dev Encode price for newValue parameter (just price for Chainlink compatibility)
    function _encodePrice(int256 price_) internal pure returns (bytes memory) {
        return abi.encode(price_);
    }

    /// @dev Encode full bundle for additionalData parameter (supply, price, state)
    function _encodeAdditionalData(uint256 supply_, int256 price_, uint256 state_)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(supply_, price_, state_);
    }

    /// @dev Create UpdateInput struct for updateLatestRiskRoundData calls
    function _createUpdateInput(
        string memory referenceId,
        int256 price_,
        string memory updateType,
        uint256 supply_,
        uint256 state_
    )
        internal
        view
        returns (ILlamaGuardOracle.UpdateInput memory)
    {
        return ILlamaGuardOracle.UpdateInput({
            referenceId: referenceId,
            newValue: abi.encode(price_),
            updateType: updateType,
            additionalData: abi.encode(supply_, price_, state_),
            deadline: block.timestamp + 1 hours
        });
    }

    /// @dev Create UpdateInput struct with explicit deadline for testing deadline validation
    function _createUpdateInputWithDeadline(
        string memory referenceId,
        int256 price_,
        string memory updateType,
        uint256 supply_,
        uint256 state_,
        uint256 deadline_
    )
        internal
        pure
        returns (ILlamaGuardOracle.UpdateInput memory)
    {
        return ILlamaGuardOracle.UpdateInput({
            referenceId: referenceId,
            newValue: abi.encode(price_),
            updateType: updateType,
            additionalData: abi.encode(supply_, price_, state_),
            deadline: deadline_
        });
    }
}

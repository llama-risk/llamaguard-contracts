// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { EACAggregatorProxy } from "../../../script/sepolia/EACAggregatorProxy.sol";
import { LlamaGuardOracle } from "../../../src/LlamaGuardOracle.sol";
import { ILlamaGuardOracle } from "../../../src/interfaces/ILlamaGuardOracle.sol";

contract EACAggregatorProxyTest is Test {
    EACAggregatorProxy internal proxy;
    LlamaGuardOracle internal oracle;

    address internal owner = address(this);
    address internal dataProxy = address(0x1234);

    // Default test market for legacy tests
    address internal defaultMarket = address(0xDEFA);

    string[] internal defaultUpdateTypes;

    // Update type string constants
    string internal constant PRICE_TYPE = "price";
    string internal constant BOUNDED_NAV_TYPE = "boundedNAV";

    function setUp() public {
        // Setup default update types
        defaultUpdateTypes = new string[](4);
        defaultUpdateTypes[0] = "price";
        defaultUpdateTypes[1] = "supply";
        defaultUpdateTypes[2] = "risk_state";
        defaultUpdateTypes[3] = "boundedNAV";

        // Deploy oracle with initial authorized market and grant write role to dataProxy
        address[] memory initialMarkets = new address[](1);
        initialMarkets[0] = defaultMarket;
        oracle = new LlamaGuardOracle(8, "Test Oracle", 1, defaultUpdateTypes, initialMarkets);
        oracle.grantRole(oracle.WRITER_ROLE(), dataProxy);

        // Deploy EAC proxy pointing to oracle
        proxy = new EACAggregatorProxy(address(oracle));
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

    function _callUpdateData(uint256 supply_, int256 price_, uint256 state_) internal {
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", price_, PRICE_TYPE, supply_, state_));
    }

    function testConstructor() public view {
        assertEq(proxy.owner(), owner);
        assertEq(address(proxy.aggregator()), address(oracle));
    }

    function testConstructorRevertsForZeroAddress() public {
        vm.expectRevert(EACAggregatorProxy.InvalidAggregator.selector);
        new EACAggregatorProxy(address(0));
    }

    function testDecimalsPassthrough() public view {
        assertEq(proxy.decimals(), oracle.decimals());
        assertEq(proxy.decimals(), 8);
    }

    function testDescriptionPassthrough() public view {
        assertEq(proxy.description(), oracle.description());
        assertEq(proxy.description(), "Test Oracle");
    }

    function testVersionPassthrough() public view {
        assertEq(proxy.version(), oracle.version());
        assertEq(proxy.version(), 1);
    }

    function testLatestRoundDataPassthrough() public {
        // Update oracle data
        vm.prank(dataProxy);
        _callUpdateData(1000, 500, 2);

        // Read through proxy
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            proxy.latestRoundData();

        assertEq(roundId, 1);
        assertEq(answer, 500);
        assertGt(startedAt, 0);
        assertGt(updatedAt, 0);
        assertEq(answeredInRound, 1);
    }

    function testGetRoundDataPassthrough() public {
        // Update oracle data
        vm.prank(dataProxy);
        _callUpdateData(1000, 500, 2);

        // Read specific round through proxy
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            proxy.getRoundData(1);

        assertEq(roundId, 1);
        assertEq(answer, 500);
        assertGt(startedAt, 0);
        assertGt(updatedAt, 0);
        assertEq(answeredInRound, 1);
    }

    function testProposeAggregator() public {
        // Deploy new oracle
        address[] memory noMarkets = new address[](0);
        LlamaGuardOracle newOracle = new LlamaGuardOracle(18, "New Oracle", 2, defaultUpdateTypes, noMarkets);

        // Update proxy to point to new oracle
        vm.expectEmit(true, true, false, true);
        emit EACAggregatorProxy.AggregatorUpdated(address(oracle), address(newOracle));
        proxy.proposeAggregator(address(newOracle));

        // Verify update
        assertEq(address(proxy.aggregator()), address(newOracle));
        assertEq(proxy.decimals(), 18);
        assertEq(proxy.description(), "New Oracle");
        assertEq(proxy.version(), 2);
    }

    function testProposeAggregatorRevertsForNonOwner() public {
        address nonOwner = address(0x9999);
        address[] memory noMarkets = new address[](0);
        LlamaGuardOracle newOracle = new LlamaGuardOracle(18, "New Oracle", 2, defaultUpdateTypes, noMarkets);

        vm.prank(nonOwner);
        vm.expectRevert();
        proxy.proposeAggregator(address(newOracle));
    }

    function testProposeAggregatorRevertsForZeroAddress() public {
        vm.expectRevert(EACAggregatorProxy.InvalidAggregator.selector);
        proxy.proposeAggregator(address(0));
    }

    function testPhaseAggregators() public view {
        // phaseAggregators always returns current aggregator regardless of phase
        assertEq(proxy.phaseAggregators(0), address(oracle));
        assertEq(proxy.phaseAggregators(1), address(oracle));
        assertEq(proxy.phaseAggregators(99), address(oracle));
    }

    function testProxyMaintainsAddressThroughUpgrade() public {
        address proxyAddress = address(proxy);

        // Update oracle data through old oracle
        vm.prank(dataProxy);
        _callUpdateData(1000, 500, 2);

        // Read through proxy
        (, int256 answer1,,,) = proxy.latestRoundData();
        assertEq(answer1, 500);

        // Deploy and switch to new oracle
        address[] memory initialMarketsNew = new address[](1);
        initialMarketsNew[0] = defaultMarket;
        LlamaGuardOracle newOracle = new LlamaGuardOracle(8, "New Oracle", 2, defaultUpdateTypes, initialMarketsNew);
        newOracle.grantRole(newOracle.WRITER_ROLE(), dataProxy);

        vm.prank(dataProxy);
        newOracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", 750, PRICE_TYPE, 2000, 3));

        proxy.proposeAggregator(address(newOracle));

        // Proxy address unchanged
        assertEq(address(proxy), proxyAddress);

        // But now reads from new oracle
        (, int256 answer2,,,) = proxy.latestRoundData();
        assertEq(answer2, 750);
    }

    function testMultipleUpdatesWithSameProxy() public {
        // Multiple updates should all be readable through proxy
        for (uint256 i = 1; i <= 5; i++) {
            vm.prank(dataProxy);
            oracle.updateLatestRiskRoundData(
                _createUpdateInput(
                    string(abi.encodePacked("ref-", vm.toString(i))), int256(i * 50), PRICE_TYPE, i * 100, i
                )
            );
        }

        // Read latest
        (uint80 roundId, int256 answer,,,) = proxy.latestRoundData();
        assertEq(roundId, 5); // 5 updates, starting at roundId 1
        assertEq(answer, 250); // 5 * 50
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // V2 (AggregatorInterface) passthrough tests
    // ═══════════════════════════════════════════════════════════════════════════

    function testLatestAnswerPassthrough() public {
        vm.prank(dataProxy);
        _callUpdateData(1000, 500, 2);

        assertEq(proxy.latestAnswer(), 500);
        assertEq(proxy.latestAnswer(), oracle.latestAnswer());
    }

    function testLatestTimestampPassthrough() public {
        vm.prank(dataProxy);
        _callUpdateData(1000, 500, 2);

        uint256 ts = proxy.latestTimestamp();
        assertGt(ts, 0);
        assertEq(ts, oracle.latestTimestamp());
    }

    function testLatestRoundPassthrough() public {
        vm.prank(dataProxy);
        _callUpdateData(1000, 500, 2);

        assertEq(proxy.latestRound(), 1);
        assertEq(proxy.latestRound(), oracle.latestRound());
    }

    function testGetAnswerPassthrough() public {
        // Push two rounds
        vm.prank(dataProxy);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 100, PRICE_TYPE, 500, 1));
        vm.prank(dataProxy);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", 200, PRICE_TYPE, 600, 1));

        // Query historical round via V2
        assertEq(proxy.getAnswer(1), 100);
        assertEq(proxy.getAnswer(2), 200);
        assertEq(proxy.getAnswer(1), oracle.getAnswer(1));
        assertEq(proxy.getAnswer(2), oracle.getAnswer(2));
    }

    function testGetTimestampPassthrough() public {
        vm.warp(1_000_000);
        vm.prank(dataProxy);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-1", 100, PRICE_TYPE, 500, 1));

        vm.warp(2_000_000);
        vm.prank(dataProxy);
        oracle.updateLatestRiskRoundData(_createUpdateInput("ref-2", 200, PRICE_TYPE, 600, 1));

        assertEq(proxy.getTimestamp(1), oracle.getTimestamp(1));
        assertEq(proxy.getTimestamp(2), oracle.getTimestamp(2));
        assertGt(proxy.getTimestamp(2), proxy.getTimestamp(1));
    }

    function testLatestAnswerZeroBeforeAnyUpdate() public view {
        // Before any update, latestAnswer should return 0
        assertEq(proxy.latestAnswer(), 0);
        assertEq(proxy.latestTimestamp(), 0);
        assertEq(proxy.latestRound(), 0);
    }

    function testV2MethodsAfterAggregatorUpgrade() public {
        // Seed original oracle
        vm.prank(dataProxy);
        _callUpdateData(1000, 500, 2);
        assertEq(proxy.latestAnswer(), 500);

        // Deploy new oracle with different data
        address[] memory markets = new address[](1);
        markets[0] = defaultMarket;
        LlamaGuardOracle newOracle = new LlamaGuardOracle(8, "New Oracle", 2, defaultUpdateTypes, markets);
        newOracle.grantRole(newOracle.WRITER_ROLE(), dataProxy);

        vm.prank(dataProxy);
        newOracle.updateLatestRiskRoundData(_createUpdateInput("ref-new", 999, PRICE_TYPE, 2000, 1));

        // Upgrade aggregator
        proxy.proposeAggregator(address(newOracle));

        // V2 methods should now read from new oracle
        assertEq(proxy.latestAnswer(), 999);
        assertEq(proxy.latestRound(), 1);
        assertGt(proxy.latestTimestamp(), 0);
        assertEq(proxy.getAnswer(1), 999);
    }

    function testMultipleUpdatesV2Methods() public {
        for (uint256 i = 1; i <= 3; i++) {
            vm.prank(dataProxy);
            oracle.updateLatestRiskRoundData(
                _createUpdateInput(
                    string(abi.encodePacked("ref-", vm.toString(i))), int256(i * 100), PRICE_TYPE, i * 500, i
                )
            );
        }

        // latestAnswer should return the last update
        assertEq(proxy.latestAnswer(), 300);
        assertEq(proxy.latestRound(), 3);

        // Historical V2 queries
        assertEq(proxy.getAnswer(1), 100);
        assertEq(proxy.getAnswer(2), 200);
        assertEq(proxy.getAnswer(3), 300);
    }
}

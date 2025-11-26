// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { Test } from "forge-std/Test.sol";
import { EACAggregatorProxy } from "../src/sepolia/EACAggregatorProxy.sol";
import { LlamaGuardOracle } from "../src/LlamaGuardOracle.sol";

contract EACAggregatorProxyTest is Test {
    EACAggregatorProxy internal proxy;
    LlamaGuardOracle internal oracle;

    address internal owner = address(this);
    address internal dataProxy = address(0x1234);

    // Default test market for legacy tests
    address internal defaultMarket = address(0xDEFA);

    string[] internal defaultUpdateTypes;

    function setUp() public {
        // Setup default update types
        defaultUpdateTypes = new string[](3);
        defaultUpdateTypes[0] = "price";
        defaultUpdateTypes[1] = "supply";
        defaultUpdateTypes[2] = "risk_state";

        // Deploy oracle with initial authorized market and grant write role to dataProxy
        address[] memory initialMarkets = new address[](1);
        initialMarkets[0] = defaultMarket;
        oracle = new LlamaGuardOracle(8, "Test Oracle", 1, defaultUpdateTypes, initialMarkets);
        oracle.grantRole(oracle.WRITER_ROLE(), dataProxy);

        // Deploy EAC proxy pointing to oracle
        proxy = new EACAggregatorProxy(address(oracle));
    }

    function _encodeUpdateValue(uint256 supply_, int256 price_, uint256 state_) internal pure returns (bytes memory) {
        return abi.encode(supply_, price_, state_);
    }

    function _callUpdateData(uint256 supply_, int256 price_, uint256 state_) internal {
        oracle.updateData("ref-1", _encodeUpdateValue(supply_, price_, state_), "price", "");
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

        assertEq(roundId, 2);
        assertEq(answer, 500);
        assertGt(startedAt, 0);
        assertGt(updatedAt, 0);
        assertEq(answeredInRound, 2);
    }

    function testGetRoundDataPassthrough() public {
        // Update oracle data
        vm.prank(dataProxy);
        _callUpdateData(1000, 500, 2);

        // Read specific round through proxy
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            proxy.getRoundData(2);

        assertEq(roundId, 2);
        assertEq(answer, 500);
        assertGt(startedAt, 0);
        assertGt(updatedAt, 0);
        assertEq(answeredInRound, 2);
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
        newOracle.updateData("ref-2", _encodeUpdateValue(2000, 750, 3), "price", "");

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
            oracle.updateData(
                string(abi.encodePacked("ref-", vm.toString(i))),
                _encodeUpdateValue(i * 100, int256(i * 50), i),
                "price",
                ""
            );
        }

        // Read latest
        (uint80 roundId, int256 answer,,,) = proxy.latestRoundData();
        assertEq(roundId, 6); // Initial round + 5 updates
        assertEq(answer, 250); // 5 * 50
    }
}

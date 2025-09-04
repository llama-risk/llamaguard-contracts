// SPDX-License-Identifier: MIT
pragma solidity >=0.8.29 <0.9.0;

import { ParameterRegistry } from "../src/ParameterRegistry.sol";
import { MockAggregatorV3 } from "../tests/mocks/MockAggregatorV3.sol";
import { BaseScript } from "./Base.s.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/guides/scripting-with-solidity
contract DeployParameterRegistry is BaseScript {
    function run() public broadcast returns (ParameterRegistry parameterRegistry, address mockOracle) {
        // Read environment variables for constructor arguments
        address owner = vm.envAddress("OWNER_ADDRESS");
        address updater = vm.envAddress("UPDATER_ADDRESS");

        // Deploy the contract
        parameterRegistry = new ParameterRegistry(owner, updater);

        // Deploy mock oracle for testing (optional - only for test environments)
        // In production, you would use actual Chainlink oracles
        bool deployMockOracle = vm.envOr("DEPLOY_MOCK_ORACLE", false);
        if (deployMockOracle) {
            MockAggregatorV3 oracle = new MockAggregatorV3(8, "ETH / USD");
            mockOracle = address(oracle);

            // Setup initial round data for testing
            uint80[] memory roundIds = new uint80[](5);
            int256[] memory answers = new int256[](5);
            uint256[] memory timestamps = new uint256[](5);

            for (uint80 i = 0; i < 5; i++) {
                roundIds[i] = i + 1;
                answers[i] = int256(uint256(2000 + i * 10)) * 1e8; // Sample prices
                timestamps[i] = block.timestamp - (4 - i) * 3600; // 1 hour apart
            }

            oracle.setMultipleRounds(roundIds, answers, timestamps);
        }
    }
}

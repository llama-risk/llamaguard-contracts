// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { Vm } from "forge-std/Vm.sol";
import { CapsConfig } from "./CapsConfig.sol";

/// @title CapsDeployment
/// @notice The addresses one caps deployment has so far, in `deployments/<label>.json` under
///         `script/risk-oracles/caps/`. Steps 0 and 1 write the contracts, step 2 the agent ids; every later step
///         reads them back, so no address is pasted by hand.
library CapsDeployment {
    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct Deployment {
        address agentHub;
        address shadowPool;
        address riskOracle;
        address router;
        address registry;
        address rvm;
        address reducer;
        address raiseAgent;
        address cutAgent;
        uint256 raiseAgentId;
        uint256 cutAgentId;
        address forwarder; // step 5, production only
    }

    function path(string memory label) internal pure returns (string memory) {
        return string.concat(CapsConfig.DIR, "deployments/", label, ".json");
    }

    /// @notice The deployment so far; all zero before step 0 or 1 has run.
    function read(string memory label) internal view returns (Deployment memory d) {
        string memory file = path(label);
        if (!VM.exists(file)) return d;
        string memory json = VM.readFile(file);
        d.agentHub = VM.parseJsonAddress(json, ".agentHub");
        d.shadowPool = VM.parseJsonAddress(json, ".shadowPool");
        d.riskOracle = VM.parseJsonAddress(json, ".riskOracle");
        d.router = VM.parseJsonAddress(json, ".router");
        d.registry = VM.parseJsonAddress(json, ".registry");
        d.rvm = VM.parseJsonAddress(json, ".rvm");
        d.reducer = VM.parseJsonAddress(json, ".reducer");
        d.raiseAgent = VM.parseJsonAddress(json, ".raiseAgent");
        d.cutAgent = VM.parseJsonAddress(json, ".cutAgent");
        d.raiseAgentId = VM.parseJsonUint(json, ".raiseAgentId");
        d.cutAgentId = VM.parseJsonUint(json, ".cutAgentId");
        if (VM.keyExistsJson(json, ".forwarder")) d.forwarder = VM.parseJsonAddress(json, ".forwarder");
    }

    function write(string memory label, Deployment memory d) internal {
        string memory key = "deployment";
        VM.serializeAddress(key, "agentHub", d.agentHub);
        VM.serializeAddress(key, "shadowPool", d.shadowPool);
        VM.serializeAddress(key, "riskOracle", d.riskOracle);
        VM.serializeAddress(key, "router", d.router);
        VM.serializeAddress(key, "registry", d.registry);
        VM.serializeAddress(key, "rvm", d.rvm);
        VM.serializeAddress(key, "reducer", d.reducer);
        VM.serializeAddress(key, "raiseAgent", d.raiseAgent);
        VM.serializeAddress(key, "cutAgent", d.cutAgent);
        VM.serializeUint(key, "raiseAgentId", d.raiseAgentId);
        VM.serializeUint(key, "cutAgentId", d.cutAgentId);
        VM.writeJson(VM.serializeAddress(key, "forwarder", d.forwarder), path(label));
    }
}

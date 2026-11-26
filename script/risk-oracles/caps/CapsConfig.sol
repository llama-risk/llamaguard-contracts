// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { Vm } from "forge-std/Vm.sol";
import { ICapsParameterRegistry } from "../../../src/caps-oracle/interfaces/ICapsParameterRegistry.sol";
import { ICapsRangeValidationModule as IRvm } from "../../../src/caps-oracle/interfaces/ICapsRangeValidationModule.sol";

/// @title CapsConfig
/// @notice Loads one caps deployment from `config/<label>.json` and the asset values file it names, from
///         `assets/<name>.json`, both under `script/risk-oracles/caps/`.
/// @dev Every key is read on its own (`vm.parseJson*` per key), so the JSON key order does not matter. Addresses
///      are strings: `"TODO"` reverts with the key's name, so an unfilled deployment can never broadcast.
///      Token amounts are base-10 strings.
library CapsConfig {
    Vm private constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    string internal constant DIR = "script/risk-oracles/caps/";
    string internal constant BORROW_UPDATE_TYPE_PREFIX = "BorrowCapUpdate";
    string internal constant SUPPLY_UPDATE_TYPE_PREFIX = "SupplyCapUpdate";
    /// @dev `maxCap` value meaning "the borrow cap the stack sees when step 3 runs".
    string internal constant CURRENT_CAP = "current";

    /// @notice Who holds each role. On staging all of them are the one staging EOA.
    struct Roles {
        address deployer;
        address agentHubOwner;
        address agentAdmin;
        address shadowPoolOwner;
        address riskOracleOwner;
        address routerOwner;
        address routerUpdater;
        address routerGuardian;
        address registryOwner;
        address registryUpdater;
        address rvmOwner;
        address riskCouncil;
    }

    /// @notice The Router route to the raise agent, added in step 4.
    struct Route {
        address forwarder; // the chain's KeystoneForwarder
        address workflowOwner; // the CRE workflow owner the route pins as author
        uint64 maxReportAgeSeconds;
    }

    struct Market {
        string label;
        uint256 chainId;
        /// @dev true: our AgentHub and a ShadowPool from step 0. false: `agentHub`, `configEngine` and `pool` as is.
        bool shadow;
        address pool; // the real Aave V3 Pool
        address agentHub; // production only
        address configEngine; // production only: the agents' agentContext
        string updateTypeSuffix; // e.g. "_Core"
        string riskOracleDescription;
        uint256 expirationSeconds; // AgentHub expirationPeriod of both agents
        uint256 tauSeconds; // AgentHub minimumDelay of the raise agent
        IRvm.Bounds bounds;
        ICapsParameterRegistry.WorkflowParams defaults;
        string assets;
    }

    /// @notice One borrow cap key of the RVM and the registry.
    struct Reserve {
        string symbol;
        address asset;
        bool currentCap; // maxCap is the cap the stack sees when step 3 runs
        uint64 maxCap; // used when currentCap is false
        uint64 maxHeadroom;
        uint16 alphaBps;
        uint16 cutBandBps;
    }

    struct Assets {
        Reserve[] reserves;
        address[] skip;
    }

    struct Config {
        Market market;
        Roles roles;
        Assets assets;
    }

    /// @notice The whole deployment. Reverts on any `"TODO"`.
    function load(string memory label) internal view returns (Config memory config) {
        string memory json = VM.readFile(string.concat(DIR, "config/", label, ".json"));
        config.market = _market(json);
        config.roles = _roles(json);
        config.assets = loadAssets(config.market.assets);
    }

    /// @notice Everything but the roles, for a fork test that brings its own principals.
    function loadMarket(string memory label) internal view returns (Market memory) {
        return _market(VM.readFile(string.concat(DIR, "config/", label, ".json")));
    }

    function loadAssets(string memory name) internal view returns (Assets memory assets) {
        string memory json = VM.readFile(string.concat(DIR, "assets/", name, ".json"));
        uint256 count = _length(json, ".reserves");
        assets.reserves = new Reserve[](count);
        for (uint256 i; i < count; ++i) {
            string memory key = string.concat(".reserves[", VM.toString(i), "]");
            Reserve memory r = assets.reserves[i];
            r.symbol = VM.parseJsonString(json, string.concat(key, ".symbol"));
            r.asset = _address(json, string.concat(key, ".asset"));
            string memory maxCap = VM.parseJsonString(json, string.concat(key, ".maxCap"));
            r.currentCap = _eq(maxCap, CURRENT_CAP);
            if (!r.currentCap) r.maxCap = uint64(VM.parseUint(maxCap));
            r.maxHeadroom = uint64(VM.parseUint(VM.parseJsonString(json, string.concat(key, ".maxHeadroom"))));
            r.alphaBps = uint16(VM.parseJsonUint(json, string.concat(key, ".alphaBps")));
            r.cutBandBps = uint16(VM.parseJsonUint(json, string.concat(key, ".cutBandBps")));
        }
        count = _length(json, ".skip");
        assets.skip = new address[](count);
        for (uint256 i; i < count; ++i) {
            assets.skip[i] = _address(json, string.concat(".skip[", VM.toString(i), "].asset"));
        }
    }

    function borrowUpdateType(Market memory market) internal pure returns (string memory) {
        return string.concat(BORROW_UPDATE_TYPE_PREFIX, market.updateTypeSuffix);
    }

    function supplyUpdateType(Market memory market) internal pure returns (string memory) {
        return string.concat(SUPPLY_UPDATE_TYPE_PREFIX, market.updateTypeSuffix);
    }

    function _market(string memory json) private pure returns (Market memory m) {
        m.label = VM.parseJsonString(json, ".label");
        m.chainId = VM.parseJsonUint(json, ".chainId");
        m.shadow = VM.parseJsonBool(json, ".shadow");
        m.pool = _address(json, ".pool");
        m.agentHub = _address(json, ".agentHub");
        m.configEngine = _address(json, ".configEngine");
        m.updateTypeSuffix = VM.parseJsonString(json, ".updateTypeSuffix");
        m.riskOracleDescription = VM.parseJsonString(json, ".riskOracleDescription");
        m.expirationSeconds = VM.parseJsonUint(json, ".agents.expirationSeconds");
        m.tauSeconds = VM.parseJsonUint(json, ".agents.tauSeconds");
        m.bounds = IRvm.Bounds({
            alphaBpsLimit: uint16(VM.parseJsonUint(json, ".bounds.alphaBpsLimit")),
            cutBandBpsLimit: uint16(VM.parseJsonUint(json, ".bounds.cutBandBpsLimit")),
            maxIncreaseBps: uint16(VM.parseJsonUint(json, ".bounds.maxIncreaseBps")),
            cooldown: uint40(VM.parseJsonUint(json, ".bounds.cooldownSeconds"))
        });
        m.defaults = ICapsParameterRegistry.WorkflowParams({
            enabled: VM.parseJsonBool(json, ".defaults.enabled"),
            triggerBps: uint16(VM.parseJsonUint(json, ".defaults.triggerBps")),
            marginBps: uint16(VM.parseJsonUint(json, ".defaults.marginBps")),
            minMarginTokens: uint64(VM.parseUint(VM.parseJsonString(json, ".defaults.minMarginTokens")))
        });
        m.assets = VM.parseJsonString(json, ".assets");
    }

    /// @notice The route, read only by step 4, so steps 0 to 3 can run before the workflow owner is known.
    function loadRoute(string memory label) internal view returns (Route memory route) {
        string memory json = VM.readFile(string.concat(DIR, "config/", label, ".json"));
        route.forwarder = _address(json, ".route.forwarder");
        route.workflowOwner = _address(json, ".route.workflowOwner");
        route.maxReportAgeSeconds = uint64(VM.parseJsonUint(json, ".route.maxReportAgeSeconds"));
    }

    function _roles(string memory json) private pure returns (Roles memory r) {
        r.deployer = _address(json, ".roles.deployer");
        r.agentHubOwner = _address(json, ".roles.agentHubOwner");
        r.agentAdmin = _address(json, ".roles.agentAdmin");
        r.shadowPoolOwner = _address(json, ".roles.shadowPoolOwner");
        r.riskOracleOwner = _address(json, ".roles.riskOracleOwner");
        r.routerOwner = _address(json, ".roles.routerOwner");
        r.routerUpdater = _address(json, ".roles.routerUpdater");
        r.routerGuardian = _address(json, ".roles.routerGuardian");
        r.registryOwner = _address(json, ".roles.registryOwner");
        r.registryUpdater = _address(json, ".roles.registryUpdater");
        r.rvmOwner = _address(json, ".roles.rvmOwner");
        r.riskCouncil = _address(json, ".roles.riskCouncil");
    }

    function _address(string memory json, string memory key) private pure returns (address) {
        string memory value = VM.parseJsonString(json, key);
        if (_eq(value, "TODO")) revert(string.concat("CapsConfig: ", key, " is TODO"));
        return VM.parseAddress(value);
    }

    function _length(string memory json, string memory key) private view returns (uint256 count) {
        while (VM.keyExistsJson(json, string.concat(key, "[", VM.toString(count), "]"))) ++count;
    }

    function _eq(string memory a, string memory b) private pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}

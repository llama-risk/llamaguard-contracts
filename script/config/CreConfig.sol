// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

import { DeployStructs } from "./DeployStructs.sol";

/// @title CreConfig
/// @notice Chainlink CRE workflow configurations per asset
/// @dev Update these values once Chainlink provides the CRE workflow details.
///      Each asset's oracle proxy gets its own workflow config.
contract CreConfig {
    error UnknownAsset();

    /// @notice Get CRE workflow config for a named asset
    function getCreConfig(string memory assetName) public pure returns (DeployStructs.CreWorkflowConfig memory) {
        bytes32 key = keccak256(abi.encodePacked(assetName));

        if (key == keccak256("USTB")) return _ustbCreConfig();
        if (key == keccak256("USCC")) return _usccCreConfig();
        if (key == keccak256("USYC")) return _usycCreConfig();
        if (key == keccak256("JTRSY")) return _jtrsyCreConfig();
        if (key == keccak256("JAAA")) return _jaaaCreConfig();
        if (key == keccak256("ACRED")) return _acredCreConfig();

        revert UnknownAsset();
    }

    /// @notice Get all CRE workflow configs
    function getAllCreConfigs() public pure returns (DeployStructs.CreWorkflowConfig[] memory configs) {
        configs = new DeployStructs.CreWorkflowConfig[](6);
        configs[0] = _ustbCreConfig();
        configs[1] = _usccCreConfig();
        configs[2] = _usycCreConfig();
        configs[3] = _jtrsyCreConfig();
        configs[4] = _jaaaCreConfig();
        configs[5] = _acredCreConfig();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PER-ASSET CRE CONFIGS
    // ═══════════════════════════════════════════════════════════════════════════

    function _ustbCreConfig() internal pure returns (DeployStructs.CreWorkflowConfig memory) {
        return DeployStructs.CreWorkflowConfig({
            proxyAddress: 0x67e347aeac84bbD4644425d8Ca8665046FD2C4e0,
            workflowId: 0x00a9cf308e875f62fb6df1f6e1a55dd7db46384876e4059c35abd54125a9c1af,
            expectedForwarder: 0x0b93082D9b3C7C97fAcd250082899BAcf3af3885,
            expectedAuthor: 0x4EDEaFc9b862F08464423EFe9423153B22B28f17, // CRE multisig
            expectedWorkflowName: _creWorkflowName("llamaguard_nav_ustb_prod")
        });
    }

    function _usccCreConfig() internal pure returns (DeployStructs.CreWorkflowConfig memory) {
        return DeployStructs.CreWorkflowConfig({
            proxyAddress: 0x3606A9Ab8D47EE31A6cC1134fA6995B7d16DB529,
            workflowId: 0x00886db7652f86b1e90aa63388139bbc9a82069ad80360fce3a2f7d38fe884eb,
            expectedForwarder: 0x0b93082D9b3C7C97fAcd250082899BAcf3af3885,
            expectedAuthor: 0x4EDEaFc9b862F08464423EFe9423153B22B28f17, // CRE multisig
            expectedWorkflowName: _creWorkflowName("llamaguard_nav_uscc_prod")
        });
    }

    function _usycCreConfig() internal pure returns (DeployStructs.CreWorkflowConfig memory) {
        return DeployStructs.CreWorkflowConfig({
            proxyAddress: 0x7cf933fc475da2E3b45FA207d7df2EF9855c0B60,
            workflowId: 0x00eabb3f208f6e34aa9a2e643cd1ca7a38c5de290a274da7d6ff37c255faec22,
            expectedForwarder: 0x0b93082D9b3C7C97fAcd250082899BAcf3af3885,
            expectedAuthor: 0x4EDEaFc9b862F08464423EFe9423153B22B28f17, // CRE multisig
            expectedWorkflowName: _creWorkflowName("llamaguard_nav_usyc_prod")
        });
    }

    function _jtrsyCreConfig() internal pure returns (DeployStructs.CreWorkflowConfig memory) {
        return DeployStructs.CreWorkflowConfig({
            proxyAddress: 0x069f65edEC8FbC6bd7c0C03104d9beC350F0A1C1,
            workflowId: 0x0058a4e15806379bed41052228a76d6d6ccc45ebcfc167058a73c6065bda6b72,
            expectedForwarder: 0x0b93082D9b3C7C97fAcd250082899BAcf3af3885,
            expectedAuthor: 0x4EDEaFc9b862F08464423EFe9423153B22B28f17, // CRE multisig
            expectedWorkflowName: _creWorkflowName("llamaguard_nav_jtrsy_prod")
        });
    }

    function _jaaaCreConfig() internal pure returns (DeployStructs.CreWorkflowConfig memory) {
        return DeployStructs.CreWorkflowConfig({
            proxyAddress: 0xb3fF4a48DEf4d1D2249180F02Ce505668aFd8D46,
            workflowId: 0x00264afe850ac2514dd13809e5e6ccdc9d5070bccc2ebf457baae1c2720dc2be,
            expectedForwarder: 0x0b93082D9b3C7C97fAcd250082899BAcf3af3885,
            expectedAuthor: 0x4EDEaFc9b862F08464423EFe9423153B22B28f17, // CRE multisig
            expectedWorkflowName: _creWorkflowName("llamaguard_nav_jaaa_prod")
        });
    }

    /// @notice Derive CRE workflow name from human-readable name
    /// @dev Chainlink CRE workflow name derivation:
    ///      1. SHA-256 hash of the workflow name string
    ///      2. Hex-encode the hash
    ///      3. Take first 10 hex characters
    ///      4. Store as bytes10 (ASCII)
    function _creWorkflowName(string memory workflowName) internal pure returns (bytes10) {
        bytes32 hash = sha256(bytes(workflowName));
        bytes memory hexChars = "0123456789abcdef";
        bytes memory result = new bytes(10);
        for (uint256 i = 0; i < 5; i++) {
            uint8 b = uint8(hash[i]);
            result[i * 2] = hexChars[b >> 4];
            result[i * 2 + 1] = hexChars[b & 0x0f];
        }
        return bytes10(bytes(result));
    }

    function _acredCreConfig() internal pure returns (DeployStructs.CreWorkflowConfig memory) {
        return DeployStructs.CreWorkflowConfig({
            proxyAddress: address(0), // TODO: Set after Stage 3 deployment
            workflowId: bytes32(0), // TODO: Set Chainlink CRE workflow ID for ACRED
            expectedForwarder: address(0), // TODO: Set Chainlink CRE forwarder for ACRED
            expectedAuthor: address(0), // TODO: Set Chainlink CRE author for ACRED
            expectedWorkflowName: bytes10(0) // TODO: Set Chainlink CRE workflow name for ACRED
        });
    }
}

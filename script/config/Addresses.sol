// SPDX-License-Identifier: MIT
pragma solidity >=0.8.26 <0.9.0;

/// @title Addresses
/// @notice Well-known addresses per network (single source of truth)
library Addresses {
    // ═══════════════════════════════════════════════════════════════════════════
    // ETHEREUM MAINNET (Chain ID: 1)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice LlamaRisk deployer EOA (used for deployment transactions)
    address internal constant LLAMARISK_DEPLOYER = 0x9118964074e2AA11393ce0797264759dB2F2ef69;

    /// @notice LlamaRisk multisig on mainnet
    address internal constant LLAMARISK_MULTISIG = 0xE6ec1f0Ae6Cd023bd0a9B4d0253BDC755103253c;

    /// @notice Already deployed ParameterRegistry on mainnet
    address internal constant PARAMETER_REGISTRY = 0x69D55D504BC9556E377b340D19818E736bbB318b;

    // --- Asset token addresses (mainnet) ---
    address internal constant JAAA = 0x5a0F93D040De44e78F251b03c43be9CF317Dcf64;
    address internal constant USTB = 0x43415eB6ff9DB7E26A15b704e7A3eDCe97d31C4e;
    address internal constant JTRSY = 0x8c213ee79581Ff4984583C6a801e5263418C4b86;
    address internal constant USCC = 0x14d60E7FDC0D71d8611742720E4C50E7a974020c;
    address internal constant USYC = 0x136471a34f6ef19fE571EFFC1CA711fdb8E49f2b;
    address internal constant VBILL = 0x2255718832bC9fD3bE1CaF75084F4803DA14FF01;
    address internal constant ACRED = address(0); // TODO: Set ACRED token address

    // --- Existing Chainlink oracle addresses (mainnet) ---
    address internal constant JAAA_ORACLE = 0x1E41Ef40AC148706c114534E8192Ca608f80fC48;
    address internal constant USTB_ORACLE = 0xde49c7B5C0E54b1624ED21C7D88bA6593d444Aa0;
    address internal constant JTRSY_ORACLE = 0x23adce82907D20c509101E2Af0723A9e16224EFb;
    address internal constant USCC_ORACLE = 0x19e2d716288751c5A59deaB61af012D5DF895962;
    address internal constant USYC_ORACLE = 0xE8E65Fb9116875012F5990Ecaab290B3531DbeB9;
    address internal constant VBILL_ORACLE = 0x5ed77a9D9b7cc80E9d0D7711024AF38C2643C1c4;
    address internal constant ACRED_ORACLE = address(0); // TODO: Set ACRED oracle address

    // --- Aave Horizon mainnet ---
    address internal constant AAVE_HORIZON_POOL = 0xAe05Cd22df81871bc7cC2a04BeCfb516bFe332C8;
    address internal constant AAVE_HORIZON_POOL_CONFIGURATOR = 0x83Cb1B4af26EEf6463aC20AFbAC9c0e2E017202F;
    address internal constant AAVE_HORIZON_ACL_MANAGER = 0xEFD5df7b87d2dCe6DD454b4240b3e0A4db562321;

    // ═══════════════════════════════════════════════════════════════════════════
    // SEPOLIA TESTNET (Chain ID: 11155111)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Test wallet on Sepolia
    address internal constant SEPOLIA_DEPLOYER = 0xb0AD0E3A19490E9145bE9Ad45F7B285eb71756F6;

    // --- Sepolia asset addresses ---
    address internal constant SEPOLIA_USCC = 0x862776CC41B728c43D9375Abc65c9CEda6547E28;
    address internal constant SEPOLIA_USTB = 0x39727692cF58137Bd8c401eFE87Cc8A190D62ead;

    // --- Sepolia source oracles (for seeding) ---
    address internal constant SEPOLIA_USCC_SOURCE_ORACLE = 0xE38b0917888d0d5d8d03B7371d5214A1aF8e1892;
    address internal constant SEPOLIA_USTB_SOURCE_ORACLE = 0x732d3C7515356eAB22E3F3DcA183c5c65102d518;

    // --- Sepolia CRE (Chainlink) ---
    address internal constant SEPOLIA_CRE_FORWARDER = 0xDB9DE209C276E14bd36aAc18A1f551e09586e8Ba;
    address internal constant SEPOLIA_CRE_AUTHOR = 0x4EDEaFc9b862F08464423EFe9423153B22B28f17;

    // --- Sepolia deployed LlamaGuard infrastructure ---
    address internal constant SEPOLIA_USTB_LLAMAGUARD_ORACLE = 0x54F2879D0a903B864782A40D67776aE53871B166;
    address internal constant SEPOLIA_USTB_FREEZE_AGENT = 0xC363afB380cd6C972Fd8219d9f51F3f6b05CD60c;
    address internal constant SEPOLIA_HORIZON_AGENT_HUB = 0x1DcDe45392E4fE8c1a9D60AaE5dd01057c234C68;
    address internal constant SEPOLIA_USTB_LLAMAGUARD_ORACLE_PROXY = 0x2B079561590C6ACfb6af3C4aF5Bc3927acc98bD2;
    address internal constant SEPOLIA_HOT_WALLET = 0x9118964074e2AA11393ce0797264759dB2F2ef69;

    // --- Sepolia Aave Horizon ---
    address internal constant SEPOLIA_AAVE_HORIZON_POOL = 0x553aA902Df9C6770c43Ef047cDD13431Ecdf09fF;
    address internal constant SEPOLIA_AAVE_HORIZON_POOL_CONFIGURATOR = 0x5d5215F0901e58b442Fbb443d2dAD2645A553B18;
    address internal constant SEPOLIA_AAVE_HORIZON_ACL_MANAGER = 0xa98845b72768bD31287cE93eAE1F97DE90426e35;

    // ═══════════════════════════════════════════════════════════════════════════
    // ANVIL LOCAL (Chain ID: 31337)
    // ═══════════════════════════════════════════════════════════════════════════

    address internal constant ANVIL_ACCOUNT_0 = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address internal constant ANVIL_ACCOUNT_1 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
}

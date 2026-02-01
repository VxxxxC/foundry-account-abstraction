// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

/**
 * @title HelperConfigTest
 * @notice Test suite for HelperConfig script covering network configurations
 * @dev Tests cover:
 *   - Network configuration retrieval
 *   - Chain ID validation
 *   - Edge cases for unsupported chains
 */
contract HelperConfigTest is Test {
    HelperConfig public helperConfig;
    
    // Chain IDs as defined in HelperConfig
    uint256 constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 constant ZKSYNC_SEPOLIA_CHAIN_ID = 300;
    uint256 constant LOCAL_CHAIN_ID = 31337;
    address constant BURNER_WALLET = 0x0406c906ad4214E97F80F706d4203e6d1cBF5E3E;
    address constant SEPOLIA_ENTRY_POINT = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;
    
    function setUp() public {
        helperConfig = new HelperConfig();
    }
    
    /*//////////////////////////////////////////////////////////////
                    SEPOLIA CONFIGURATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test Sepolia configuration returns correct EntryPoint
    function test_GetEthSepoliaConfig_ReturnsCorrectEntryPoint() public pure {
        HelperConfig tempConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = tempConfig.getEthSepoliaConfig();
        
        assertEq(config.entryPoint, SEPOLIA_ENTRY_POINT);
    }
    
    /// @notice Test Sepolia configuration returns correct burner wallet
    function test_GetEthSepoliaConfig_ReturnsCorrectAccount() public pure {
        HelperConfig tempConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = tempConfig.getEthSepoliaConfig();
        
        assertEq(config.account, BURNER_WALLET);
    }
    
    /// @notice Test getConfigByChainId returns Sepolia config for Sepolia chain ID
    function test_GetConfigByChainId_ReturnsSepolia_ForSepoliaChainId() public {
        HelperConfig.NetworkConfig memory config = helperConfig.getConfigByChainId(ETH_SEPOLIA_CHAIN_ID);
        
        assertEq(config.entryPoint, SEPOLIA_ENTRY_POINT);
        assertEq(config.account, BURNER_WALLET);
    }
    
    /*//////////////////////////////////////////////////////////////
                    ZKSYNC CONFIGURATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test zkSync Sepolia configuration returns zero address for EntryPoint
    /// @dev zkSync has native AA so no EntryPoint contract is used
    function test_GetZkSyncSepoliaConfig_ReturnsZeroEntryPoint() public pure {
        HelperConfig tempConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = tempConfig.getZkSyncSepoliaConfig();
        
        assertEq(config.entryPoint, address(0));
    }
    
    /// @notice Test zkSync Sepolia uses same burner wallet
    function test_GetZkSyncSepoliaConfig_ReturnsCorrectAccount() public pure {
        HelperConfig tempConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = tempConfig.getZkSyncSepoliaConfig();
        
        assertEq(config.account, BURNER_WALLET);
    }
    
    /*//////////////////////////////////////////////////////////////
                    LOCAL/ANVIL CONFIGURATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test getConfig on local chain returns local network config
    function test_GetConfig_OnLocalChain() public {
        // Set chain to local (Anvil)
        vm.chainId(LOCAL_CHAIN_ID);
        
        // getOrCreateAnvilEthConfig has an issue - returns nothing when localNetworkConfig is empty
        // This is a potential bug in the HelperConfig contract
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        
        // Since getOrCreateAnvilEthConfig doesn't actually create a config when empty,
        // it returns an empty struct
        assertEq(config.entryPoint, address(0));
        assertEq(config.account, address(0));
    }
    
    /// @notice Test getOrCreateAnvilEthConfig returns empty config when not initialized
    /// @dev This is a potential vulnerability/bug - function returns empty struct
    function test_GetOrCreateAnvilEthConfig_ReturnsEmpty_WhenNotInitialized() public {
        HelperConfig.NetworkConfig memory config = helperConfig.getOrCreateAnvilEthConfig();
        
        // The function has a missing return statement when localNetworkConfig is not set
        // This means it returns an empty NetworkConfig
        assertEq(config.entryPoint, address(0));
        assertEq(config.account, address(0));
    }
    
    /*//////////////////////////////////////////////////////////////
                    INVALID CHAIN ID TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test getConfigByChainId reverts for unsupported chain
    function test_GetConfigByChainId_RevertsFor_UnsupportedChain() public {
        uint256 unsupportedChainId = 999999;
        
        vm.expectRevert(HelperConfig.HelperConfig__InvalidChainId.selector);
        helperConfig.getConfigByChainId(unsupportedChainId);
    }
    
    /// @notice Test getConfigByChainId reverts for mainnet
    function test_GetConfigByChainId_RevertsFor_Mainnet() public {
        uint256 mainnetChainId = 1;
        
        vm.expectRevert(HelperConfig.HelperConfig__InvalidChainId.selector);
        helperConfig.getConfigByChainId(mainnetChainId);
    }
    
    /// @notice Test getConfigByChainId reverts for zkSync Sepolia 
    /// @dev zkSync config not added in constructor mapping
    function test_GetConfigByChainId_RevertsFor_ZkSyncSepolia() public {
        // zkSync Sepolia is not in the networkConfigs mapping
        vm.expectRevert(HelperConfig.HelperConfig__InvalidChainId.selector);
        helperConfig.getConfigByChainId(ZKSYNC_SEPOLIA_CHAIN_ID);
    }
    
    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test that constructor correctly initializes Sepolia config
    function test_Constructor_InitializesSepoliaConfig() public {
        (address entryPoint, address account) = helperConfig.networkConfigs(ETH_SEPOLIA_CHAIN_ID);
        
        assertEq(entryPoint, SEPOLIA_ENTRY_POINT);
        assertEq(account, BURNER_WALLET);
    }
    
    /// @notice Test that other chain IDs are not initialized
    function test_Constructor_DoesNotInitializeOtherChains() public {
        (address entryPoint, address account) = helperConfig.networkConfigs(1); // Mainnet
        
        assertEq(entryPoint, address(0));
        assertEq(account, address(0));
    }
    
    /// @notice Test localNetworkConfig starts empty
    function test_LocalNetworkConfig_StartsEmpty() public {
        (address entryPoint, address account) = helperConfig.localNetworkConfig();
        
        assertEq(entryPoint, address(0));
        assertEq(account, address(0));
    }
    
    /*//////////////////////////////////////////////////////////////
                    VULNERABILITY: INCOMPLETE FUNCTION
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test vulnerability: getOrCreateAnvilEthConfig has incomplete implementation
    /// @dev The function doesn't create config when localNetworkConfig is not set
    ///      This means calling getConfig on Anvil returns empty config, potentially
    ///      causing issues with deployment (zero address EntryPoint)
    function test_Vulnerability_IncompleteAnvilConfig() public {
        vm.chainId(LOCAL_CHAIN_ID);
        
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        
        // This demonstrates the vulnerability:
        // When deploying on Anvil, the config will have address(0) for both values
        // This would cause deployment to fail or create a broken MinimalAccount
        assertEq(config.entryPoint, address(0), "EntryPoint should be zero - incomplete function");
        assertEq(config.account, address(0), "Account should be zero - incomplete function");
    }
}

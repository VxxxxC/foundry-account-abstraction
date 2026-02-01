// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {DeployMinimal} from "../script/DeployMinimal.s.sol";
import {MinimalAccount} from "../src/ethereum/MinimalAccount.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {EntryPoint} from "lib/account-abstraction/contracts/core/EntryPoint.sol";

/**
 * @title DeployMinimalTest
 * @notice Test suite for DeployMinimal script
 * @dev Tests cover:
 *   - Deployment correctness
 *   - Configuration handling
 *   - Edge cases
 */
contract DeployMinimalTest is Test {
    DeployMinimal public deployer;
    
    // Chain IDs
    uint256 constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 constant LOCAL_CHAIN_ID = 31337;
    
    // Expected addresses
    address constant SEPOLIA_ENTRY_POINT = 0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789;
    address constant BURNER_WALLET = 0x0406c906ad4214E97F80F706d4203e6d1cBF5E3E;
    
    function setUp() public {
        deployer = new DeployMinimal();
    }
    
    /*//////////////////////////////////////////////////////////////
                    DEPLOYMENT ON SEPOLIA TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test deployment on Sepolia returns valid contracts
    function test_DeployMinimalAccount_OnSepolia() public {
        vm.chainId(ETH_SEPOLIA_CHAIN_ID);
        
        // Need to simulate BURNER_WALLET having balance
        vm.deal(BURNER_WALLET, 100 ether);
        
        (HelperConfig helperConfig, MinimalAccount minimalAccount) = deployer.deployMinimalAccount();
        
        // Verify HelperConfig is created
        assertTrue(address(helperConfig) != address(0));
        
        // Verify MinimalAccount is created
        assertTrue(address(minimalAccount) != address(0));
        
        // Verify EntryPoint is set correctly
        assertEq(minimalAccount.getEntryPoint(), SEPOLIA_ENTRY_POINT);
    }
    
    /// @notice Test that deployed account has correct owner
    function test_DeployMinimalAccount_SetsCorrectOwner() public {
        vm.chainId(ETH_SEPOLIA_CHAIN_ID);
        vm.deal(BURNER_WALLET, 100 ether);
        
        (, MinimalAccount minimalAccount) = deployer.deployMinimalAccount();
        
        // Owner should be the BURNER_WALLET (config.account)
        assertEq(minimalAccount.owner(), BURNER_WALLET);
    }
    
    /*//////////////////////////////////////////////////////////////
                    DEPLOYMENT ON LOCAL/ANVIL TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test deployment on local chain (Anvil)
    /// @dev This test demonstrates the vulnerability in HelperConfig
    function test_DeployMinimalAccount_OnAnvil_WithBrokenConfig() public {
        vm.chainId(LOCAL_CHAIN_ID);
        
        // Due to the incomplete getOrCreateAnvilEthConfig function,
        // this will fail or create a broken account with zero address EntryPoint
        // and zero address account (cannot broadcast)
        
        // This should either revert or create a broken contract
        // Let's verify what happens
        try deployer.deployMinimalAccount() returns (HelperConfig, MinimalAccount minimalAccount) {
            // If it doesn't revert, the account will have address(0) as EntryPoint
            assertEq(minimalAccount.getEntryPoint(), address(0));
        } catch {
            // Expected to fail due to incomplete config
            assertTrue(true);
        }
    }
    
    /*//////////////////////////////////////////////////////////////
                    VULNERABILITY TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test vulnerability: run() function is empty
    function test_Run_IsEmpty() public {
        // The run() function has no implementation
        // This means calling the script directly does nothing
        deployer.run();
        // No way to verify - function does nothing
        assertTrue(true, "run() is empty but doesn't revert");
    }
    
    /// @notice Test that deployment creates new HelperConfig each time
    /// @dev This is inefficient and could lead to inconsistent configs
    function test_MultipleDeployments_CreateNewConfigs() public {
        vm.chainId(ETH_SEPOLIA_CHAIN_ID);
        vm.deal(BURNER_WALLET, 100 ether);
        
        (HelperConfig config1,) = deployer.deployMinimalAccount();
        (HelperConfig config2,) = deployer.deployMinimalAccount();
        
        // Each call creates a new HelperConfig
        assertTrue(address(config1) != address(config2));
    }
}

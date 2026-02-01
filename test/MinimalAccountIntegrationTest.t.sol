// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {MinimalAccount} from "../src/ethereum/MinimalAccount.sol";
import {EntryPoint} from "lib/account-abstraction/contracts/core/EntryPoint.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS} from "lib/account-abstraction/contracts/core/Helpers.sol";

/**
 * @title MinimalAccountIntegrationTest
 * @notice Integration tests for MinimalAccount with real EntryPoint
 * @dev Tests cover:
 *   - Full UserOperation flow through EntryPoint
 *   - handleOps execution
 *   - Gas management
 *   - Real-world attack scenarios
 */
contract MinimalAccountIntegrationTest is Test {
    MinimalAccount public minimalAccount;
    EntryPoint public entryPoint;
    
    // Test accounts
    address public owner;
    uint256 public ownerPrivateKey;
    address public beneficiary;
    
    // Constants
    uint256 constant INITIAL_BALANCE = 100 ether;
    
    function setUp() public {
        // Generate owner keypair
        ownerPrivateKey = 0xA11CE;
        owner = vm.addr(ownerPrivateKey);
        beneficiary = makeAddr("beneficiary");
        
        // Deploy EntryPoint
        entryPoint = new EntryPoint();
        
        // Deploy MinimalAccount
        vm.prank(owner);
        minimalAccount = new MinimalAccount(address(entryPoint));
        
        // Fund accounts
        vm.deal(address(minimalAccount), INITIAL_BALANCE);
        vm.deal(owner, INITIAL_BALANCE);
    }
    
    /*//////////////////////////////////////////////////////////////
                    FULL USEROPERATION FLOW TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test complete UserOperation flow through EntryPoint
    function test_HandleOps_ExecutesUserOp() public {
        // Create target for the operation
        address target = makeAddr("target");
        uint256 sendAmount = 1 ether;
        
        // Create UserOperation
        PackedUserOperation memory userOp = _createExecuteUserOp(
            address(minimalAccount),
            target,
            sendAmount,
            ""
        );
        
        // Get the userOp hash from EntryPoint
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        
        // Sign the operation
        userOp.signature = _signUserOp(userOpHash, ownerPrivateKey);
        
        // Create ops array
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        
        // Execute via EntryPoint
        entryPoint.handleOps(ops, payable(beneficiary));
        
        // Verify target received funds
        assertEq(target.balance, sendAmount);
    }
    
    /// @notice Test handleOps reverts with invalid signature
    function test_HandleOps_RevertsWithInvalidSignature() public {
        address target = makeAddr("target");
        uint256 attackerPrivateKey = 0xB0B;
        
        PackedUserOperation memory userOp = _createExecuteUserOp(
            address(minimalAccount),
            target,
            1 ether,
            ""
        );
        
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        
        // Sign with wrong key
        userOp.signature = _signUserOp(userOpHash, attackerPrivateKey);
        
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        
        // Should revert due to invalid signature
        vm.expectRevert();
        entryPoint.handleOps(ops, payable(beneficiary));
    }
    
    /// @notice Test handleOps with contract interaction
    function test_HandleOps_ExecutesContractCall() public {
        // Deploy target contract
        CounterContract counter = new CounterContract();
        
        bytes memory callData = abi.encodeWithSignature("increment()");
        
        PackedUserOperation memory userOp = _createExecuteUserOp(
            address(minimalAccount),
            address(counter),
            0,
            callData
        );
        
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        userOp.signature = _signUserOp(userOpHash, ownerPrivateKey);
        
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        
        entryPoint.handleOps(ops, payable(beneficiary));
        
        assertEq(counter.count(), 1);
    }
    
    /// @notice Test multiple operations in single handleOps call
    function test_HandleOps_MultipleOperations() public {
        // Deploy multiple accounts for different owners
        uint256 owner2PrivateKey = 0xB0B2;
        address owner2 = vm.addr(owner2PrivateKey);
        
        vm.prank(owner2);
        MinimalAccount account2 = new MinimalAccount(address(entryPoint));
        vm.deal(address(account2), INITIAL_BALANCE);
        
        address target1 = makeAddr("target1");
        address target2 = makeAddr("target2");
        
        // Create two UserOperations
        PackedUserOperation memory userOp1 = _createExecuteUserOp(
            address(minimalAccount),
            target1,
            1 ether,
            ""
        );
        PackedUserOperation memory userOp2 = _createExecuteUserOpForAccount(
            address(account2),
            target2,
            2 ether,
            ""
        );
        
        bytes32 userOpHash1 = entryPoint.getUserOpHash(userOp1);
        bytes32 userOpHash2 = entryPoint.getUserOpHash(userOp2);
        
        userOp1.signature = _signUserOp(userOpHash1, ownerPrivateKey);
        userOp2.signature = _signUserOp(userOpHash2, owner2PrivateKey);
        
        PackedUserOperation[] memory ops = new PackedUserOperation[](2);
        ops[0] = userOp1;
        ops[1] = userOp2;
        
        entryPoint.handleOps(ops, payable(beneficiary));
        
        assertEq(target1.balance, 1 ether);
        assertEq(target2.balance, 2 ether);
    }
    
    /*//////////////////////////////////////////////////////////////
                    NONCE MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test that nonce prevents replay attacks
    function test_Nonce_PreventsReplay() public {
        address target = makeAddr("target");
        
        PackedUserOperation memory userOp = _createExecuteUserOp(
            address(minimalAccount),
            target,
            1 ether,
            ""
        );
        
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        userOp.signature = _signUserOp(userOpHash, ownerPrivateKey);
        
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        
        // First execution succeeds
        entryPoint.handleOps(ops, payable(beneficiary));
        assertEq(target.balance, 1 ether);
        
        // Second execution with same nonce should fail
        vm.expectRevert();
        entryPoint.handleOps(ops, payable(beneficiary));
    }
    
    /// @notice Test sequential nonce increment
    function test_Nonce_IncrementsSequentially() public {
        address target = makeAddr("target");
        
        // Execute three operations with incrementing nonces
        for (uint256 i = 0; i < 3; i++) {
            PackedUserOperation memory userOp = _createExecuteUserOpWithNonce(
                address(minimalAccount),
                target,
                0.1 ether,
                "",
                i
            );
            
            bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
            userOp.signature = _signUserOp(userOpHash, ownerPrivateKey);
            
            PackedUserOperation[] memory ops = new PackedUserOperation[](1);
            ops[0] = userOp;
            
            entryPoint.handleOps(ops, payable(beneficiary));
        }
        
        assertEq(target.balance, 0.3 ether);
    }
    
    /*//////////////////////////////////////////////////////////////
                    GAS HANDLING TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test that insufficient gas causes revert
    function test_InsufficientGas_CausesRevert() public {
        address target = makeAddr("target");
        
        // Create UserOp with very low gas limits
        PackedUserOperation memory userOp = _createExecuteUserOpWithLowGas(
            address(minimalAccount),
            target,
            1 ether,
            ""
        );
        
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        userOp.signature = _signUserOp(userOpHash, ownerPrivateKey);
        
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        
        // Should revert due to insufficient gas
        vm.expectRevert();
        entryPoint.handleOps(ops, payable(beneficiary));
    }
    
    /// @notice Test that account is charged for gas
    function test_AccountIsChargedForGas() public {
        address target = makeAddr("target");
        uint256 accountBalanceBefore = address(minimalAccount).balance;
        
        PackedUserOperation memory userOp = _createExecuteUserOp(
            address(minimalAccount),
            target,
            0,  // Don't send ETH, just test gas consumption
            ""
        );
        
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        userOp.signature = _signUserOp(userOpHash, ownerPrivateKey);
        
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        
        entryPoint.handleOps(ops, payable(beneficiary));
        
        uint256 accountBalanceAfter = address(minimalAccount).balance;
        
        // Account balance should decrease due to gas payment
        assertTrue(accountBalanceAfter < accountBalanceBefore, "Account should be charged for gas");
    }
    
    /*//////////////////////////////////////////////////////////////
                    ATTACK SCENARIO TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test front-running attack (bundle manipulation)
    function test_FrontRunningAttack() public {
        address target = makeAddr("target");
        
        // User creates legitimate transaction
        PackedUserOperation memory userOp = _createExecuteUserOp(
            address(minimalAccount),
            target,
            10 ether,
            ""
        );
        
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        userOp.signature = _signUserOp(userOpHash, ownerPrivateKey);
        
        // Attacker sees the pending operation and tries to front-run
        // But they cannot forge a signature, so they can only:
        // 1. Include it in their bundle (MEV extraction)
        // 2. Try to DOS by consuming nonce (not possible without valid sig)
        
        // The attack that IS possible: attacker as bundler can:
        // - Reorder operations
        // - Extract MEV from state changes
        // This is a known limitation of ERC-4337
        
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        
        // Execution still succeeds (no replay possible)
        entryPoint.handleOps(ops, payable(beneficiary));
        assertEq(target.balance, 10 ether);
    }
    
    /// @notice Test griefing attack on prefund
    function test_GriefingAttack_OnPrefund() public {
        // Create account with minimal balance
        vm.prank(owner);
        MinimalAccount lowBalanceAccount = new MinimalAccount(address(entryPoint));
        vm.deal(address(lowBalanceAccount), 0.001 ether);  // Very low balance
        
        address target = makeAddr("target");
        
        PackedUserOperation memory userOp = _createExecuteUserOpForAccount(
            address(lowBalanceAccount),
            target,
            0,
            ""
        );
        
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        userOp.signature = _signUserOp(userOpHash, ownerPrivateKey);
        
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        
        // Should fail due to insufficient balance for prefund
        vm.expectRevert();
        entryPoint.handleOps(ops, payable(beneficiary));
    }
    
    /*//////////////////////////////////////////////////////////////
                    DEPOSIT/WITHDRAW TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test depositing to EntryPoint for account
    function test_DepositToEntryPoint() public {
        // Deposit ETH to EntryPoint for our account
        entryPoint.depositTo{value: 10 ether}(address(minimalAccount));
        
        // Check deposit balance
        uint256 depositBalance = entryPoint.balanceOf(address(minimalAccount));
        assertEq(depositBalance, 10 ether);
    }
    
    /// @notice Test that deposit is used for gas
    function test_DepositUsedForGas() public {
        // Deposit some ETH
        entryPoint.depositTo{value: 10 ether}(address(minimalAccount));
        
        address target = makeAddr("target");
        uint256 depositBefore = entryPoint.balanceOf(address(minimalAccount));
        
        PackedUserOperation memory userOp = _createExecuteUserOp(
            address(minimalAccount),
            target,
            0,
            ""
        );
        
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        userOp.signature = _signUserOp(userOpHash, ownerPrivateKey);
        
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        
        entryPoint.handleOps(ops, payable(beneficiary));
        
        uint256 depositAfter = entryPoint.balanceOf(address(minimalAccount));
        assertTrue(depositAfter < depositBefore, "Deposit should be used for gas");
    }
    
    /*//////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _createExecuteUserOp(
        address sender,
        address target,
        uint256 value,
        bytes memory data
    ) internal view returns (PackedUserOperation memory) {
        bytes memory executeCallData = abi.encodeWithSelector(
            MinimalAccount.execute.selector,
            target,
            value,
            data
        );
        
        return PackedUserOperation({
            sender: sender,
            nonce: entryPoint.getNonce(sender, 0),
            initCode: "",
            callData: executeCallData,
            accountGasLimits: bytes32(uint256(200000) << 128 | uint256(200000)),
            preVerificationGas: 50000,
            gasFees: bytes32(uint256(1 gwei) << 128 | uint256(1 gwei)),
            paymasterAndData: "",
            signature: ""
        });
    }
    
    function _createExecuteUserOpForAccount(
        address sender,
        address target,
        uint256 value,
        bytes memory data
    ) internal view returns (PackedUserOperation memory) {
        bytes memory executeCallData = abi.encodeWithSelector(
            MinimalAccount.execute.selector,
            target,
            value,
            data
        );
        
        return PackedUserOperation({
            sender: sender,
            nonce: entryPoint.getNonce(sender, 0),
            initCode: "",
            callData: executeCallData,
            accountGasLimits: bytes32(uint256(200000) << 128 | uint256(200000)),
            preVerificationGas: 50000,
            gasFees: bytes32(uint256(1 gwei) << 128 | uint256(1 gwei)),
            paymasterAndData: "",
            signature: ""
        });
    }
    
    function _createExecuteUserOpWithNonce(
        address sender,
        address target,
        uint256 value,
        bytes memory data,
        uint256 nonce
    ) internal pure returns (PackedUserOperation memory) {
        bytes memory executeCallData = abi.encodeWithSelector(
            MinimalAccount.execute.selector,
            target,
            value,
            data
        );
        
        return PackedUserOperation({
            sender: sender,
            nonce: nonce,
            initCode: "",
            callData: executeCallData,
            accountGasLimits: bytes32(uint256(200000) << 128 | uint256(200000)),
            preVerificationGas: 50000,
            gasFees: bytes32(uint256(1 gwei) << 128 | uint256(1 gwei)),
            paymasterAndData: "",
            signature: ""
        });
    }
    
    function _createExecuteUserOpWithLowGas(
        address sender,
        address target,
        uint256 value,
        bytes memory data
    ) internal view returns (PackedUserOperation memory) {
        bytes memory executeCallData = abi.encodeWithSelector(
            MinimalAccount.execute.selector,
            target,
            value,
            data
        );
        
        return PackedUserOperation({
            sender: sender,
            nonce: entryPoint.getNonce(sender, 0),
            initCode: "",
            callData: executeCallData,
            accountGasLimits: bytes32(uint256(1000) << 128 | uint256(1000)), // Very low gas
            preVerificationGas: 100,
            gasFees: bytes32(uint256(1 gwei) << 128 | uint256(1 gwei)),
            paymasterAndData: "",
            signature: ""
        });
    }
    
    function _signUserOp(bytes32 userOpHash, uint256 privateKey) internal pure returns (bytes memory) {
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethSignedMessageHash);
        return abi.encodePacked(r, s, v);
    }
}

/*//////////////////////////////////////////////////////////////
                    HELPER CONTRACTS
//////////////////////////////////////////////////////////////*/

/// @notice Simple counter contract for testing
contract CounterContract {
    uint256 public count;
    
    function increment() external {
        count++;
    }
    
    function decrement() external {
        require(count > 0, "Cannot decrement below zero");
        count--;
    }
    
    receive() external payable {}
}

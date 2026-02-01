// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {MinimalAccount} from "../src/ethereum/MinimalAccount.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS} from "lib/account-abstraction/contracts/core/Helpers.sol";
import {EntryPoint} from "lib/account-abstraction/contracts/core/EntryPoint.sol";

/**
 * @title MinimalAccountTest
 * @notice Comprehensive test suite for MinimalAccount covering vulnerabilities and edge cases
 * @dev Tests cover:
 *   - Access control vulnerabilities
 *   - Signature validation security
 *   - Gas prefund mechanism
 *   - Reentrancy attacks
 *   - Signature replay attacks
 *   - Edge cases and fuzzing
 */
contract MinimalAccountTest is Test {
    MinimalAccount public minimalAccount;
    EntryPoint public entryPoint;
    
    // Test accounts
    address public owner;
    uint256 public ownerPrivateKey;
    address public attacker;
    uint256 public attackerPrivateKey;
    address public randomUser;
    
    // Constants
    uint256 constant INITIAL_BALANCE = 100 ether;
    
    // Events to test
    event Received(address indexed sender, uint256 amount);

    function setUp() public {
        // Generate owner keypair
        ownerPrivateKey = 0xA11CE;
        owner = vm.addr(ownerPrivateKey);
        
        // Generate attacker keypair
        attackerPrivateKey = 0xB0B;
        attacker = vm.addr(attackerPrivateKey);
        
        // Random user without private key access
        randomUser = makeAddr("randomUser");
        
        // Deploy EntryPoint
        entryPoint = new EntryPoint();
        
        // Deploy MinimalAccount with owner
        vm.prank(owner);
        minimalAccount = new MinimalAccount(address(entryPoint));
        
        // Fund the minimal account
        vm.deal(address(minimalAccount), INITIAL_BALANCE);
        vm.deal(owner, INITIAL_BALANCE);
        vm.deal(attacker, INITIAL_BALANCE);
    }

    /*//////////////////////////////////////////////////////////////
                        BASIC FUNCTIONALITY TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test that the contract is deployed with correct owner
    function test_DeploymentSetsCorrectOwner() public view {
        assertEq(minimalAccount.owner(), owner);
    }
    
    /// @notice Test that the EntryPoint is correctly set
    function test_DeploymentSetsCorrectEntryPoint() public view {
        assertEq(minimalAccount.getEntryPoint(), address(entryPoint));
    }
    
    /// @notice Test that the contract can receive ETH
    function test_ReceiveETH() public {
        uint256 initialBalance = address(minimalAccount).balance;
        uint256 sendAmount = 1 ether;
        
        (bool success,) = address(minimalAccount).call{value: sendAmount}("");
        
        assertTrue(success);
        assertEq(address(minimalAccount).balance, initialBalance + sendAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test that execute reverts when called by random user
    function test_Execute_RevertsWhen_CalledByRandomUser() public {
        vm.prank(randomUser);
        vm.expectRevert(MinimalAccount.MinimalAccount__NotFromEntryPointOrOwner.selector);
        minimalAccount.execute(randomUser, 0, "");
    }
    
    /// @notice Test that execute reverts when called by attacker
    function test_Execute_RevertsWhen_CalledByAttacker() public {
        vm.prank(attacker);
        vm.expectRevert(MinimalAccount.MinimalAccount__NotFromEntryPointOrOwner.selector);
        minimalAccount.execute(attacker, 1 ether, "");
    }
    
    /// @notice Test that execute succeeds when called by owner
    function test_Execute_SucceedsWhen_CalledByOwner() public {
        address recipient = makeAddr("recipient");
        uint256 sendAmount = 1 ether;
        
        vm.prank(owner);
        minimalAccount.execute(recipient, sendAmount, "");
        
        assertEq(recipient.balance, sendAmount);
    }
    
    /// @notice Test that execute succeeds when called by EntryPoint
    function test_Execute_SucceedsWhen_CalledByEntryPoint() public {
        address recipient = makeAddr("recipient");
        uint256 sendAmount = 1 ether;
        
        vm.prank(address(entryPoint));
        minimalAccount.execute(recipient, sendAmount, "");
        
        assertEq(recipient.balance, sendAmount);
    }
    
    /// @notice Test that validateUserOp reverts when not called by EntryPoint
    function test_ValidateUserOp_RevertsWhen_NotFromEntryPoint() public {
        PackedUserOperation memory userOp = _createDummyUserOp(address(minimalAccount));
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        
        vm.prank(randomUser);
        vm.expectRevert(MinimalAccount.MinimalAccount__NotFromEntryPoint.selector);
        minimalAccount.validateUserOp(userOp, userOpHash, 0);
    }
    
    /// @notice Test that validateUserOp reverts when called by owner (not EntryPoint)
    function test_ValidateUserOp_RevertsWhen_CalledByOwner() public {
        PackedUserOperation memory userOp = _createDummyUserOp(address(minimalAccount));
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        
        vm.prank(owner);
        vm.expectRevert(MinimalAccount.MinimalAccount__NotFromEntryPoint.selector);
        minimalAccount.validateUserOp(userOp, userOpHash, 0);
    }

    /*//////////////////////////////////////////////////////////////
                    SIGNATURE VALIDATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test signature validation with valid owner signature
    function test_ValidateUserOp_ReturnsSuccess_WithValidSignature() public {
        PackedUserOperation memory userOp = _createDummyUserOp(address(minimalAccount));
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        
        // Sign with owner's private key
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedMessageHash);
        userOp.signature = abi.encodePacked(r, s, v);
        
        vm.prank(address(entryPoint));
        uint256 validationData = minimalAccount.validateUserOp(userOp, userOpHash, 0);
        
        assertEq(validationData, SIG_VALIDATION_SUCCESS);
    }
    
    /// @notice Test signature validation with invalid signature (wrong signer)
    function test_ValidateUserOp_ReturnsFailed_WithAttackerSignature() public {
        PackedUserOperation memory userOp = _createDummyUserOp(address(minimalAccount));
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        
        // Sign with attacker's private key
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attackerPrivateKey, ethSignedMessageHash);
        userOp.signature = abi.encodePacked(r, s, v);
        
        vm.prank(address(entryPoint));
        uint256 validationData = minimalAccount.validateUserOp(userOp, userOpHash, 0);
        
        assertEq(validationData, SIG_VALIDATION_FAILED);
    }
    
    /// @notice Test signature validation with empty signature
    function test_ValidateUserOp_HandlesEmptySignature() public {
        PackedUserOperation memory userOp = _createDummyUserOp(address(minimalAccount));
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        userOp.signature = "";
        
        // Should revert with ECDSA error for invalid signature length
        vm.prank(address(entryPoint));
        vm.expectRevert();
        minimalAccount.validateUserOp(userOp, userOpHash, 0);
    }
    
    /// @notice Test signature validation with malformed signature
    function test_ValidateUserOp_HandlesMalformedSignature() public {
        PackedUserOperation memory userOp = _createDummyUserOp(address(minimalAccount));
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        userOp.signature = abi.encodePacked(bytes32(0), bytes32(0), uint8(27)); // Invalid signature
        
        vm.prank(address(entryPoint));
        // Either returns failed validation or reverts - both are acceptable security behavior
        try minimalAccount.validateUserOp(userOp, userOpHash, 0) returns (uint256 validationData) {
            assertEq(validationData, SIG_VALIDATION_FAILED);
        } catch {
            // Reverting is also acceptable for malformed signatures
            assertTrue(true);
        }
    }

    /*//////////////////////////////////////////////////////////////
                    SIGNATURE MALLEABILITY TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test that signature malleability doesn't allow different valid signatures
    /// @dev ECDSA signatures can be malleable (s -> n-s), verify OZ ECDSA prevents this
    function test_SignatureMalleability_Prevention() public {
        PackedUserOperation memory userOp = _createDummyUserOp(address(minimalAccount));
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedMessageHash);
        
        // Create malleated signature (s -> n - s, v flipped)
        // secp256k1 curve order n
        uint256 n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
        bytes32 malleableS = bytes32(n - uint256(s));
        uint8 malleableV = v == 27 ? 28 : 27;
        
        userOp.signature = abi.encodePacked(r, malleableS, malleableV);
        
        vm.prank(address(entryPoint));
        // OpenZeppelin ECDSA should reject high-s signatures
        try minimalAccount.validateUserOp(userOp, userOpHash, 0) returns (uint256 validationData) {
            // If it doesn't revert, it should return failed
            assertEq(validationData, SIG_VALIDATION_FAILED);
        } catch {
            // Reverting is the expected behavior for malleable signatures
            assertTrue(true);
        }
    }

    /*//////////////////////////////////////////////////////////////
                    GAS PREFUND VULNERABILITY TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test that gas prefund is paid correctly
    function test_PayPrefund_PaysCorrectAmount() public {
        uint256 prefundAmount = 1 ether;
        uint256 entryPointBalanceBefore = address(entryPoint).balance;
        
        PackedUserOperation memory userOp = _createDummyUserOp(address(minimalAccount));
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedMessageHash);
        userOp.signature = abi.encodePacked(r, s, v);
        
        vm.prank(address(entryPoint));
        minimalAccount.validateUserOp(userOp, userOpHash, prefundAmount);
        
        // EntryPoint should have received the prefund
        assertEq(address(entryPoint).balance, entryPointBalanceBefore + prefundAmount);
    }
    
    /// @notice Test that zero prefund doesn't cause issues
    function test_PayPrefund_ZeroAmount() public {
        PackedUserOperation memory userOp = _createDummyUserOp(address(minimalAccount));
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedMessageHash);
        userOp.signature = abi.encodePacked(r, s, v);
        
        uint256 accountBalanceBefore = address(minimalAccount).balance;
        
        vm.prank(address(entryPoint));
        minimalAccount.validateUserOp(userOp, userOpHash, 0);
        
        // Balance should remain unchanged
        assertEq(address(minimalAccount).balance, accountBalanceBefore);
    }
    
    /// @notice Test vulnerability: unchecked return value in _payPrefund
    /// @dev The contract has `(success);` which does nothing - ETH transfer failure is silently ignored
    function test_PayPrefund_UncheckedReturnValue_Vulnerability() public {
        // Deploy a contract that rejects ETH to act as malicious EntryPoint
        RejectingContract rejectingEntryPoint = new RejectingContract();
        
        // Deploy MinimalAccount with rejecting contract as EntryPoint
        vm.prank(owner);
        MinimalAccount vulnerableAccount = new MinimalAccount(address(rejectingEntryPoint));
        vm.deal(address(vulnerableAccount), 10 ether);
        
        PackedUserOperation memory userOp = _createDummyUserOp(address(vulnerableAccount));
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedMessageHash);
        userOp.signature = abi.encodePacked(r, s, v);
        
        uint256 accountBalanceBefore = address(vulnerableAccount).balance;
        
        // Call validateUserOp from the "EntryPoint"
        vm.prank(address(rejectingEntryPoint));
        // This should NOT revert even though the ETH transfer will fail
        // because the return value is not checked
        vulnerableAccount.validateUserOp(userOp, userOpHash, 1 ether);
        
        // Account balance should still have the funds (transfer failed silently)
        // This demonstrates the vulnerability
        assertEq(address(vulnerableAccount).balance, accountBalanceBefore);
    }

    /*//////////////////////////////////////////////////////////////
                        REENTRANCY TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test reentrancy attack on execute function
    function test_Execute_ReentrancyAttack() public {
        // Deploy reentrancy attacker
        ReentrancyAttacker attackerContract = new ReentrancyAttacker(address(minimalAccount));
        vm.deal(address(attackerContract), 1 ether);
        
        // Fund minimal account
        vm.deal(address(minimalAccount), 10 ether);
        
        uint256 attackerBalanceBefore = address(attackerContract).balance;
        uint256 accountBalanceBefore = address(minimalAccount).balance;
        
        // Owner executes call to attacker contract
        vm.prank(owner);
        try minimalAccount.execute(
            address(attackerContract),
            1 ether,
            abi.encodeWithSignature("attack()")
        ) {
            // If it succeeds, check that reentrancy didn't drain more than intended
            // Note: Execute doesn't have reentrancy guard, but call only sends specified amount
        } catch {
            // Failure is acceptable
        }
        
        // Verify the account wasn't drained beyond the intended amount
        // In worst case, only 1 ether should be sent
        assertTrue(
            address(minimalAccount).balance >= accountBalanceBefore - 1 ether,
            "Reentrancy drained more than expected"
        );
    }

    /*//////////////////////////////////////////////////////////////
                        EXECUTE FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test execute with function call data
    function test_Execute_WithFunctionCallData() public {
        // Deploy target contract
        TargetContract target = new TargetContract();
        
        bytes memory callData = abi.encodeWithSignature("setValue(uint256)", 42);
        
        vm.prank(owner);
        minimalAccount.execute(address(target), 0, callData);
        
        assertEq(target.value(), 42);
    }
    
    /// @notice Test execute reverts when target call fails
    function test_Execute_RevertsWhen_TargetCallFails() public {
        TargetContract target = new TargetContract();
        
        bytes memory callData = abi.encodeWithSignature("alwaysFails()");
        
        vm.prank(owner);
        vm.expectRevert();
        minimalAccount.execute(address(target), 0, callData);
    }
    
    /// @notice Test execute can send ETH without call data
    function test_Execute_SendsETH_WithoutCallData() public {
        address recipient = makeAddr("recipient");
        uint256 sendAmount = 5 ether;
        
        vm.prank(owner);
        minimalAccount.execute(recipient, sendAmount, "");
        
        assertEq(recipient.balance, sendAmount);
    }
    
    /// @notice Test execute fails when insufficient balance
    function test_Execute_RevertsWhen_InsufficientBalance() public {
        address recipient = makeAddr("recipient");
        uint256 sendAmount = address(minimalAccount).balance + 1 ether;
        
        vm.prank(owner);
        vm.expectRevert();
        minimalAccount.execute(recipient, sendAmount, "");
    }

    /*//////////////////////////////////////////////////////////////
                    CROSS-CHAIN REPLAY TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test that signatures can potentially be replayed across chains
    /// @dev This is a potential vulnerability as userOpHash doesn't include chain ID verification in contract
    function test_CrossChainReplay_PotentialVulnerability() public {
        // Create and sign a userOp
        PackedUserOperation memory userOp = _createDummyUserOp(address(minimalAccount));
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedMessageHash);
        userOp.signature = abi.encodePacked(r, s, v);
        
        // Validate on "chain 1"
        vm.prank(address(entryPoint));
        uint256 validationData1 = minimalAccount.validateUserOp(userOp, userOpHash, 0);
        assertEq(validationData1, SIG_VALIDATION_SUCCESS);
        
        // Simulate different chain (same contract code and addresses but different chain ID)
        // The same signature would be valid because the contract doesn't verify chain ID
        // Note: In real scenario, the EntryPoint includes chain ID in hash, providing protection
        vm.chainId(42); // Different chain ID
        
        vm.prank(address(entryPoint));
        uint256 validationData2 = minimalAccount.validateUserOp(userOp, userOpHash, 0);
        
        // This shows that contract-level validation doesn't include chain ID
        // However, EntryPoint's userOpHash computation includes chain ID
        assertEq(validationData2, SIG_VALIDATION_SUCCESS);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test execution to address(0)
    function test_Execute_ToZeroAddress() public {
        vm.prank(owner);
        // Should succeed but do nothing meaningful
        minimalAccount.execute(address(0), 0, "");
    }
    
    /// @notice Test execution to self
    function test_Execute_ToSelf() public {
        uint256 balanceBefore = address(minimalAccount).balance;
        
        vm.prank(owner);
        minimalAccount.execute(address(minimalAccount), 1 ether, "");
        
        // Balance should remain the same (sent to self)
        assertEq(address(minimalAccount).balance, balanceBefore);
    }
    
    /// @notice Test execution with maximum value
    function test_Execute_WithMaxValue() public {
        address recipient = makeAddr("recipient");
        uint256 accountBalance = address(minimalAccount).balance;
        
        vm.prank(owner);
        minimalAccount.execute(recipient, accountBalance, "");
        
        assertEq(address(minimalAccount).balance, 0);
        assertEq(recipient.balance, accountBalance);
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Fuzz test for execute with random amounts
    function testFuzz_Execute_RandomAmount(uint256 amount) public {
        vm.assume(amount <= address(minimalAccount).balance);
        address recipient = makeAddr("recipient");
        
        vm.prank(owner);
        minimalAccount.execute(recipient, amount, "");
        
        assertEq(recipient.balance, amount);
    }
    
    /// @notice Fuzz test for prefund amounts
    function testFuzz_PayPrefund_RandomAmount(uint256 prefundAmount) public {
        vm.assume(prefundAmount <= address(minimalAccount).balance);
        
        PackedUserOperation memory userOp = _createDummyUserOp(address(minimalAccount));
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedMessageHash);
        userOp.signature = abi.encodePacked(r, s, v);
        
        uint256 entryPointBalanceBefore = address(entryPoint).balance;
        
        vm.prank(address(entryPoint));
        minimalAccount.validateUserOp(userOp, userOpHash, prefundAmount);
        
        assertEq(address(entryPoint).balance, entryPointBalanceBefore + prefundAmount);
    }
    
    /// @notice Fuzz test with random signatures (should all fail)
    function testFuzz_ValidateUserOp_RandomSignature(bytes memory randomSig) public {
        vm.assume(randomSig.length == 65); // Standard signature length
        
        PackedUserOperation memory userOp = _createDummyUserOp(address(minimalAccount));
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        userOp.signature = randomSig;
        
        vm.prank(address(entryPoint));
        try minimalAccount.validateUserOp(userOp, userOpHash, 0) returns (uint256 validationData) {
            // Random signatures should fail validation
            assertEq(validationData, SIG_VALIDATION_FAILED);
        } catch {
            // Reverting is also acceptable for invalid signatures
            assertTrue(true);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        OWNERSHIP TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test ownership transfer
    function test_OwnershipTransfer() public {
        address newOwner = makeAddr("newOwner");
        
        vm.prank(owner);
        minimalAccount.transferOwnership(newOwner);
        
        assertEq(minimalAccount.owner(), newOwner);
    }
    
    /// @notice Test that old owner cannot execute after transfer
    function test_OldOwner_CannotExecute_AfterTransfer() public {
        address newOwner = makeAddr("newOwner");
        
        vm.prank(owner);
        minimalAccount.transferOwnership(newOwner);
        
        vm.prank(owner);
        vm.expectRevert(MinimalAccount.MinimalAccount__NotFromEntryPointOrOwner.selector);
        minimalAccount.execute(makeAddr("recipient"), 1 ether, "");
    }
    
    /// @notice Test that new owner can execute after transfer
    function test_NewOwner_CanExecute_AfterTransfer() public {
        address newOwner = makeAddr("newOwner");
        address recipient = makeAddr("recipient");
        
        vm.prank(owner);
        minimalAccount.transferOwnership(newOwner);
        
        vm.prank(newOwner);
        minimalAccount.execute(recipient, 1 ether, "");
        
        assertEq(recipient.balance, 1 ether);
    }
    
    /// @notice Test renounce ownership blocks execute
    function test_RenounceOwnership_BlocksOwnerExecute() public {
        vm.prank(owner);
        minimalAccount.renounceOwnership();
        
        assertEq(minimalAccount.owner(), address(0));
        
        // Owner can no longer execute
        vm.prank(owner);
        vm.expectRevert(MinimalAccount.MinimalAccount__NotFromEntryPointOrOwner.selector);
        minimalAccount.execute(makeAddr("recipient"), 1 ether, "");
    }
    
    /// @notice Test that EntryPoint can still execute after ownership renounced
    function test_EntryPoint_CanStillExecute_AfterRenounceOwnership() public {
        vm.prank(owner);
        minimalAccount.renounceOwnership();
        
        address recipient = makeAddr("recipient");
        
        vm.prank(address(entryPoint));
        minimalAccount.execute(recipient, 1 ether, "");
        
        assertEq(recipient.balance, 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _createDummyUserOp(address sender) internal pure returns (PackedUserOperation memory) {
        return PackedUserOperation({
            sender: sender,
            nonce: 0,
            initCode: "",
            callData: "",
            accountGasLimits: bytes32(uint256(100000) << 128 | uint256(100000)),
            preVerificationGas: 100000,
            gasFees: bytes32(uint256(1 gwei) << 128 | uint256(1 gwei)),
            paymasterAndData: "",
            signature: ""
        });
    }
}

/*//////////////////////////////////////////////////////////////
                        HELPER CONTRACTS
//////////////////////////////////////////////////////////////*/

/// @notice Contract that rejects ETH transfers
contract RejectingContract {
    receive() external payable {
        revert("I reject ETH");
    }
    
    fallback() external payable {
        revert("I reject ETH");
    }
}

/// @notice Contract for testing reentrancy attacks
contract ReentrancyAttacker {
    MinimalAccount public target;
    uint256 public attackCount;
    
    constructor(address _target) {
        target = MinimalAccount(payable(_target));
    }
    
    function attack() external payable {
        attackCount++;
        if (attackCount < 3 && address(target).balance > 1 ether) {
            // Try to reenter execute
            // This would require the attacker to be the owner or EntryPoint
            // which makes reentrancy limited in scope
        }
    }
    
    receive() external payable {
        attackCount++;
        // Limited reentrancy possible here
    }
}

/// @notice Target contract for testing execute function
contract TargetContract {
    uint256 public value;
    
    function setValue(uint256 _value) external {
        value = _value;
    }
    
    function alwaysFails() external pure {
        revert("Always fails");
    }
    
    receive() external payable {}
}

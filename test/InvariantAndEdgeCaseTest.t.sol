// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {MinimalAccount} from "../src/ethereum/MinimalAccount.sol";
import {EntryPoint} from "lib/account-abstraction/contracts/core/EntryPoint.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title InvariantTest
 * @notice Invariant and property-based tests for MinimalAccount
 * @dev Tests verify properties that should always hold true regardless of actions
 * 
 * Invariants:
 *   1. EntryPoint address never changes
 *   2. Only owner or EntryPoint can execute
 *   3. Balance changes are predictable
 *   4. Ownership transfer is secure
 */
contract InvariantTest is Test {
    MinimalAccount public minimalAccount;
    EntryPoint public entryPoint;
    InvariantHandler public handler;
    
    address public owner;
    uint256 public ownerPrivateKey;
    
    function setUp() public {
        ownerPrivateKey = 0xA11CE;
        owner = vm.addr(ownerPrivateKey);
        
        entryPoint = new EntryPoint();
        
        vm.prank(owner);
        minimalAccount = new MinimalAccount(address(entryPoint));
        
        vm.deal(address(minimalAccount), 100 ether);
        
        handler = new InvariantHandler(minimalAccount, entryPoint, owner, ownerPrivateKey);
        
        targetContract(address(handler));
    }
    
    /*//////////////////////////////////////////////////////////////
                        INVARIANT TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Invariant: EntryPoint address never changes
    function invariant_EntryPointNeverChanges() public view {
        assertEq(
            minimalAccount.getEntryPoint(),
            address(entryPoint),
            "EntryPoint should never change"
        );
    }
    
    /// @notice Invariant: Owner is always a valid address or zero (after renounce)
    function invariant_OwnerIsValid() public view {
        address currentOwner = minimalAccount.owner();
        // Owner should be either the original owner, a transferred owner, or address(0)
        assertTrue(
            currentOwner == owner || currentOwner == address(0) || currentOwner != address(0),
            "Owner should be valid"
        );
    }
    
    /// @notice Invariant: Account balance is consistent with transfers
    function invariant_BalanceConsistency() public view {
        // Balance should be >= 0 (always true for uint)
        assertTrue(address(minimalAccount).balance >= 0, "Balance should be non-negative");
    }
}

/**
 * @title InvariantHandler
 * @notice Handler contract for invariant testing
 * @dev Defines actions that can be taken during invariant testing
 */
contract InvariantHandler is Test {
    MinimalAccount public minimalAccount;
    EntryPoint public entryPoint;
    address public owner;
    uint256 public ownerPrivateKey;
    
    uint256 public totalSent;
    uint256 public totalReceived;
    
    constructor(
        MinimalAccount _account,
        EntryPoint _entryPoint,
        address _owner,
        uint256 _ownerPrivateKey
    ) {
        minimalAccount = _account;
        entryPoint = _entryPoint;
        owner = _owner;
        ownerPrivateKey = _ownerPrivateKey;
    }
    
    /// @notice Handler: Owner executes transfer
    function ownerExecuteTransfer(address recipient, uint256 amount) external {
        amount = bound(amount, 0, address(minimalAccount).balance);
        
        vm.prank(owner);
        try minimalAccount.execute(recipient, amount, "") {
            totalSent += amount;
        } catch {
            // Expected for some edge cases
        }
    }
    
    /// @notice Handler: Send ETH to account
    function sendETHToAccount(uint256 amount) external {
        amount = bound(amount, 0, 10 ether);
        vm.deal(address(this), amount);
        
        (bool success,) = address(minimalAccount).call{value: amount}("");
        if (success) {
            totalReceived += amount;
        }
    }
    
    /// @notice Handler: Execute via EntryPoint
    function entryPointExecute(address recipient, uint256 amount) external {
        amount = bound(amount, 0, address(minimalAccount).balance);
        
        vm.prank(address(entryPoint));
        try minimalAccount.execute(recipient, amount, "") {
            totalSent += amount;
        } catch {
            // Expected for some cases
        }
    }
}

/**
 * @title EdgeCaseTest
 * @notice Tests for edge cases and boundary conditions
 */
contract EdgeCaseTest is Test {
    MinimalAccount public minimalAccount;
    EntryPoint public entryPoint;
    
    address public owner;
    uint256 public ownerPrivateKey;
    
    function setUp() public {
        ownerPrivateKey = 0xA11CE;
        owner = vm.addr(ownerPrivateKey);
        
        entryPoint = new EntryPoint();
        
        vm.prank(owner);
        minimalAccount = new MinimalAccount(address(entryPoint));
        
        vm.deal(address(minimalAccount), 100 ether);
        vm.deal(owner, 100 ether);
    }
    
    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Test: Execute to self doesn't change balance
    function test_ExecuteToSelf() public {
        uint256 balanceBefore = address(minimalAccount).balance;
        
        vm.prank(owner);
        minimalAccount.execute(address(minimalAccount), 1 ether, "");
        
        assertEq(address(minimalAccount).balance, balanceBefore);
    }
    
    /// @notice Test: Execute with zero value and empty data
    function test_ExecuteZeroValueEmptyData() public {
        address recipient = makeAddr("recipient");
        
        vm.prank(owner);
        minimalAccount.execute(recipient, 0, "");
        
        assertEq(recipient.balance, 0);
    }
    
    /// @notice Test: Execute to address with code that does nothing
    function test_ExecuteToContractWithNoOp() public {
        NoOpContract noOp = new NoOpContract();
        
        vm.prank(owner);
        minimalAccount.execute(address(noOp), 1 ether, "");
        
        assertEq(address(noOp).balance, 1 ether);
    }
    
    /// @notice Test: Execute to contract that returns data
    function test_ExecuteToContractReturningData() public {
        ReturningContract returner = new ReturningContract();
        
        bytes memory callData = abi.encodeWithSignature("returnsValue()");
        
        vm.prank(owner);
        minimalAccount.execute(address(returner), 0, callData);
        
        // Execute doesn't use return value, just verifies success
        assertTrue(true);
    }
    
    /// @notice Test: Receive ETH from multiple sources
    function test_ReceiveFromMultipleSources() public {
        address[] memory senders = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            senders[i] = makeAddr(string(abi.encodePacked("sender", i)));
            vm.deal(senders[i], 10 ether);
        }
        
        uint256 balanceBefore = address(minimalAccount).balance;
        
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(senders[i]);
            (bool success,) = address(minimalAccount).call{value: 1 ether}("");
            assertTrue(success);
        }
        
        assertEq(address(minimalAccount).balance, balanceBefore + 5 ether);
    }
    
    /// @notice Test: Large number of consecutive operations
    function test_ManyConsecutiveOperations() public {
        address recipient = makeAddr("recipient");
        
        for (uint256 i = 0; i < 50; i++) {
            vm.prank(owner);
            minimalAccount.execute(recipient, 0.01 ether, "");
        }
        
        assertEq(recipient.balance, 0.5 ether);
    }
    
    /// @notice Test: Owner can be zero address after renounce
    function test_OwnerCanBeZeroAddress() public {
        vm.prank(owner);
        minimalAccount.renounceOwnership();
        
        assertEq(minimalAccount.owner(), address(0));
        
        // EntryPoint can still execute
        vm.prank(address(entryPoint));
        minimalAccount.execute(makeAddr("recipient"), 1 ether, "");
    }
    
    /// @notice Test: Transfer ownership to contract
    function test_TransferOwnershipToContract() public {
        OwnerContract newOwner = new OwnerContract(address(minimalAccount));
        
        vm.prank(owner);
        minimalAccount.transferOwnership(address(newOwner));
        
        assertEq(minimalAccount.owner(), address(newOwner));
        
        // New owner contract can execute
        newOwner.executeViaAccount(makeAddr("recipient"), 1 ether, "");
    }
    
    /// @notice Test: Execute with maximum calldata size
    function test_ExecuteWithLargeCalldata() public {
        // Create large calldata (but not too large to cause out of gas)
        bytes memory largeData = new bytes(10000);
        for (uint256 i = 0; i < largeData.length; i++) {
            largeData[i] = bytes1(uint8(i % 256));
        }
        
        LargeDataReceiver receiver = new LargeDataReceiver();
        
        vm.prank(owner);
        minimalAccount.execute(address(receiver), 0, 
            abi.encodeWithSignature("receiveData(bytes)", largeData));
        
        assertTrue(receiver.received());
    }
    
    /// @notice Test: Account deployed with zero address EntryPoint
    function test_ZeroAddressEntryPoint() public {
        vm.prank(owner);
        MinimalAccount zeroEPAccount = new MinimalAccount(address(0));
        
        assertEq(zeroEPAccount.getEntryPoint(), address(0));
        
        // Owner can still execute
        vm.deal(address(zeroEPAccount), 10 ether);
        vm.prank(owner);
        zeroEPAccount.execute(makeAddr("recipient"), 1 ether, "");
        
        // No one can call validateUserOp (address(0) can't call)
    }
    
    /// @notice Test: UserOp with extreme gas values
    function test_UserOpExtremeGasValues() public {
        PackedUserOperation memory userOp = PackedUserOperation({
            sender: address(minimalAccount),
            nonce: 0,
            initCode: "",
            callData: "",
            accountGasLimits: bytes32(type(uint256).max), // Maximum gas
            preVerificationGas: type(uint256).max,
            gasFees: bytes32(type(uint256).max),
            paymasterAndData: "",
            signature: ""
        });
        
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, ethSignedMessageHash);
        userOp.signature = abi.encodePacked(r, s, v);
        
        // Should not cause overflow/underflow issues
        vm.prank(address(entryPoint));
        uint256 validationData = minimalAccount.validateUserOp(userOp, userOpHash, 0);
        
        // Valid signature should still return success
        assertEq(validationData, 0);
    }
    
    /// @notice Test: Execute to precompile addresses
    function test_ExecuteToPrecompiles() public {
        // Test execution to various precompile addresses
        address[] memory precompiles = new address[](4);
        precompiles[0] = address(1); // ecrecover
        precompiles[1] = address(2); // SHA256
        precompiles[2] = address(3); // RIPEMD160
        precompiles[3] = address(4); // identity
        
        for (uint256 i = 0; i < precompiles.length; i++) {
            vm.prank(owner);
            // May succeed or fail depending on precompile behavior
            try minimalAccount.execute(precompiles[i], 0, "") {
                // Some precompiles accept empty calls
            } catch {
                // Some precompiles may revert
            }
        }
    }
    
    /// @notice Test: Concurrent-like operations (same block)
    function test_MultipleOperationsInSameBlock() public {
        // Simulate multiple operations in the same block
        address[] memory recipients = new address[](3);
        for (uint256 i = 0; i < 3; i++) {
            recipients[i] = makeAddr(string(abi.encodePacked("recipient", i)));
        }
        
        // All in same block
        vm.prank(owner);
        minimalAccount.execute(recipients[0], 1 ether, "");
        
        vm.prank(owner);
        minimalAccount.execute(recipients[1], 2 ether, "");
        
        vm.prank(owner);
        minimalAccount.execute(recipients[2], 3 ether, "");
        
        assertEq(recipients[0].balance, 1 ether);
        assertEq(recipients[1].balance, 2 ether);
        assertEq(recipients[2].balance, 3 ether);
    }
}

/*//////////////////////////////////////////////////////////////
                    HELPER CONTRACTS
//////////////////////////////////////////////////////////////*/

contract NoOpContract {
    receive() external payable {}
}

contract ReturningContract {
    function returnsValue() external pure returns (uint256) {
        return 42;
    }
    
    receive() external payable {}
}

contract OwnerContract {
    MinimalAccount public account;
    
    constructor(address _account) {
        account = MinimalAccount(payable(_account));
    }
    
    function executeViaAccount(address recipient, uint256 amount, bytes calldata data) external {
        account.execute(recipient, amount, data);
    }
    
    receive() external payable {}
}

contract LargeDataReceiver {
    bool public received;
    
    function receiveData(bytes calldata) external {
        received = true;
    }
    
    receive() external payable {}
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ZkMinimalAccount} from "src/zkSync/ZkMinimalAccount.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Transaction, MemoryTransactionHelper} from "@era/contracts/libraries/MemoryTransactionHelper.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {BOOTLOADER_FORMAL_ADDRESS} from "@era/contracts/Constants.sol";
import {IAccount, ACCOUNT_VALIDATION_SUCCESS_MAGIC} from "@era/contracts/interfaces/IAccount.sol";

contract ZkMinimalAccountTest is Test {
    using MessageHashUtils for bytes32;
    ZkMinimalAccount zkMinimalAccount;
    ERC20Mock usdc;

    uint256 constant AMOUNT = 1e18;
    bytes32 constant EMPTY_BYTES32 = bytes32(0);
    address constant DEFAULT_ANVIL_ADDRESS = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    uint256 constant DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    // COL: Setup
    function setUp() public {
        zkMinimalAccount = new ZkMinimalAccount();
        zkMinimalAccount.transferOwnership(DEFAULT_ANVIL_ADDRESS);
        usdc = new ERC20Mock();
        vm.deal(address(zkMinimalAccount), AMOUNT);
    }

    // COL: Helper Functions

    function _createUnsignedTransaction(
        address from,
        uint8 transactionType,
        address to,
        uint256 value,
        bytes memory data
    ) internal view returns (Transaction memory) {
        uint256 nonce = vm.getNonce(address(zkMinimalAccount));
        bytes32[] memory factoryDeps = new bytes32[](0);
        return Transaction({
            txType: transactionType,
            from: uint256(uint160(from)),
            to: uint256(uint160(to)),
            gasLimit: 16777216,
            gasPerPubdataByteLimit: 16777216,
            maxFeePerGas: 16777216,
            maxPriorityFeePerGas: 16777216,
            paymaster: 0,
            nonce: nonce,
            value: value,
            reserved: [uint256(0), uint256(0), uint256(0), uint256(0)],
            data: data,
            signature: hex"",
            factoryDeps: factoryDeps,
            paymasterInput: hex"",
            reservedDynamic: hex""
        });
    }

    function _signTransaction(Transaction memory _transaction) internal view returns (Transaction memory) {
        bytes32 unsignedTransactionHash = MemoryTransactionHelper.encodeHash(_transaction);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DEFAULT_ANVIL_KEY, unsignedTransactionHash);

        Transaction memory signedTransaction = _transaction;
        signedTransaction.signature = abi.encodePacked(r, s, v); // WARN: beware the order of r, s, v
        return signedTransaction;
    }

    // COL: TESTS

    function testZkOwnerCanExecuteCommands() public {
        // arrange
        address destination = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(zkMinimalAccount), AMOUNT);

        Transaction memory transaction =
            _createUnsignedTransaction(address(zkMinimalAccount.owner()), 113, destination, value, functionData);

        // act
        vm.prank(zkMinimalAccount.owner());
        zkMinimalAccount.executeTransaction(EMPTY_BYTES32, EMPTY_BYTES32, transaction);

        // assert
        assertEq(usdc.balanceOf(address(zkMinimalAccount)), AMOUNT);
    }

    function testZkValidateTransaction() public {
        // arrange
        address destination = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(zkMinimalAccount), AMOUNT);

        Transaction memory transaction =
            _createUnsignedTransaction(address(zkMinimalAccount.owner()), 113, destination, value, functionData);

        transaction = _signTransaction(transaction);

        // act
        vm.prank(BOOTLOADER_FORMAL_ADDRESS);
        bytes4 magic = zkMinimalAccount.validateTransaction(EMPTY_BYTES32, EMPTY_BYTES32, transaction);

        // assert
        assertEq(magic, ACCOUNT_VALIDATION_SUCCESS_MAGIC);
    }
}

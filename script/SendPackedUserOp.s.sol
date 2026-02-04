// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract SendPackedUserOp is Script {
    using MessageHashUtils for bytes32;

    function run() external {}

    function generateSignedUserOperation(
        bytes memory callData,
        HelperConfig.NetworkConfig memory networkConfig,
        address sender
    ) public returns (PackedUserOperation memory) {
        // INFO: 1. Generate unsigned user operation
        uint256 nonce = vm.getNonce(sender) - 1; // WARN: subtract 1 because vm.getNonce increments the nonce after each call
        PackedUserOperation memory unsignedUserOp = _generateUnsignedUserOperation(callData, sender, nonce);

        // INFO: 2. Get the userOpHash from EntryPoint
        bytes32 userOpHash = IEntryPoint(networkConfig.entryPoint).getUserOpHash(unsignedUserOp);
        bytes32 digest = userOpHash.toEthSignedMessageHash();

        // INFO: 3. Sign the userOpHash
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(networkConfig.accountKey, digest);
        unsignedUserOp.signature = abi.encodePacked(r, s, v); // WARN: beware the order of r, s, v
        return unsignedUserOp;
    }

    function _generateUnsignedUserOperation(bytes memory callData, address sender, uint256 nonce)
        internal
        pure
        returns (PackedUserOperation memory)
    {
        uint128 verificationGasLimit = 16777216;
        uint128 callGasLimit = verificationGasLimit;
        uint128 maxPriorityFeePerGas = 256;
        uint128 maxFeePerGas = maxPriorityFeePerGas;

        return PackedUserOperation({
            sender: sender,
            nonce: nonce,
            initCode: hex"",
            callData: callData,
            accountGasLimits: bytes32(uint256(verificationGasLimit) << 128 | uint256(callGasLimit)), // NOTE: pack two uint128 into bytes32, uint128 cannot convert to bytes32 directly, need to use uint256 first
            preVerificationGas: verificationGasLimit,
            gasFees: bytes32(uint256(maxPriorityFeePerGas) << 128 | uint256(maxFeePerGas)),
            paymasterAndData: hex"",
            signature: hex""
        });
    }
}

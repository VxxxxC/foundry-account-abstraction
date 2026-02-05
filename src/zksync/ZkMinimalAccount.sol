// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAccount, ACCOUNT_VALIDATION_SUCCESS_MAGIC} from "@era/contracts/interfaces/IAccount.sol";
import {Transaction, MemoryTransactionHelper} from "@era/contracts/libraries/MemoryTransactionHelper.sol";
import {SystemContractsCaller} from "@era/contracts/libraries/SystemContractsCaller.sol";
import {NONCE_HOLDER_SYSTEM_CONTRACT, BOOTLOADER_FORMAL_ADDRESS} from "@era/contracts/Constants.sol";
import {INonceHolder} from "@era/contracts/interfaces/INonceHolder.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ZkMinimalAccount is IAccount, Ownable {
    using MemoryTransactionHelper for Transaction;

    // COL: ERRORS
    error ZkMinimalAccount__NotEnoughBalance();
    error ZkMinimalAccount__NotFromBootLoader();

    // COL: MODIFIERS
    modifier requireFromBootLoader(){
        if(msg.sender != BOOTLOADER_FORMAL_ADDRESS){
            revert ZkMinimalAccount__NotFromBootLoader();
        }
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * INFO: Account Abstraction Transaction flow on zkSync
     *
     * Lifecycle of type 113 (0x71) transaction
     * NOTE: msg.sender is the zkSync Bootloader contract
     *
     * Phase 1 : Validation
     *  - a. User send the transaction to the zkSync API client
     *  - b. zkSync API client check the nonce is unique by querying the NonceHolder system contract
     *  - c. zkSync API client call validateTransaction, which must update the nonce
     *  - d. zkSync API client check the nonce updated
     *  - e. zkSync API client call payForTransaction, or prepareForPaymaster & validateAnyPayForPaymasterTransaction if a paymaster is used
     *
     * Phase 2 : Execution
     *  - f. zkSync API client pass validated transacion to main node / sequencer ( For now they are the same )
     *  - g. The main node / sequencer call executeTransaction
     *  - h. If paymaster used, the postTransaction handler of the paymaster is called
     *
     */
    // NOTE: ***EXTERNAL FUNCTIONS***/
    /**
     * @notice must increase the nonce
     * @notice must validate the tx (check owner signed the tx)
     */
    function validateTransaction(bytes32 _txHash, bytes32 _suggestedSignedHash, Transaction calldata _transaction)
        external
        payable
        requireFromBootLoader
        returns (bytes4 magic)
    {
        // call nonce holder to increase the nonce
        // call (x, y, z) -> system contract
        SystemContractsCaller.systemCallWithPropagatedRevert(
            uint32(gasleft()),
            address(NONCE_HOLDER_SYSTEM_CONTRACT),
            0,
            abi.encodeCall(INonceHolder.incrementMinNonceIfEquals, (_transaction.nonce))
        );

        // check the fee
        uint256 totalRequiredBalance = _transaction.totalRequiredBalance();
        if(totalRequiredBalance > address(this).balance){
            revert ZkMinimalAccount__NotEnoughBalance();
        }

        // check the signature
        bytes32 txHash = _transaction.encodeHash();
        bytes32 convertedHash = MessageHashUtils.toEthSignedMessageHash(txHash);
        address signer = ECDSA.recover(convertedHash, _transaction.signature);
        bool isValidSigner = (signer == owner());
        if(isValidSigner){
            magic = ACCOUNT_VALIDATION_SUCCESS_MAGIC;
        } else {
            magic = bytes4(0);
        }
        // return the magic value
        return magic;
    }

    function executeTransaction(bytes32 _txHash, bytes32 _suggestedSignedHash, Transaction calldata _transaction)
        external
        payable {}

    // There is no point in providing possible signed hash in the `executeTransactionFromOutside` method,
    // since it typically should not be trusted.
    function executeTransactionFromOutside(Transaction calldata _transaction) external payable {}

    function payForTransaction(bytes32 _txHash, bytes32 _suggestedSignedHash, Transaction calldata _transaction)
        external
        payable {}

    function prepareForPaymaster(bytes32 _txHash, bytes32 _possibleSignedHash, Transaction calldata _transaction)
        external
        payable {}
}
